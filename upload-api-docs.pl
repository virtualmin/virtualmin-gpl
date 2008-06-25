#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into Wiki format, and upload them to
# virtualmin.com.

use Pod::Simple::Wiki;

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/domains/jdev.virtualmin.com/public_html/components/com_openwiki/data/pages";
$wiki_pages_su = "jcameron";
@api_categories = (
	[ "Virtual servers", "*-domain.pl", "*-domains.pl",
			     "enable-feature.pl", "disable-feature.pl" ],
	[ "Mail and FTP users", "*-user.pl", "*-users.pl",
				"list-available-shells.pl" ],
	[ "Mail aliases", "*-alias.pl", "*-aliases.pl",
			  "create-simple-alias.pl", "list-simple-aliases.pl" ],
	[ "Server owner limits", "*-limit.pl", "*-limits.pl" ],
	[ "Backup and restore", "backup-domain.pl", "list-scheduled-backups.pl",
				"restore-domain.pl" ],
	[ "Extra administrators", "*-admin.pl", "*-admins.pl" ],
	[ "Custom fields", "*-custom.pl" ],
	[ "Databases", "*-database.pl", "*-databases.pl",
		       "modify-database-hosts.pl" ],
	[ "Reseller accounts", "*-reseller.pl", "*-resellers.pl" ],
	[ "Script installers", "install-script.pl", "delete-script.pl",
			       "list-scripts.pl", "list-available-scripts.pl" ],
	[ "Proxies and balancers", "*-proxy.pl", "*-proxies.pl" ],
	[ "PHP versions", "*-php-directory.pl", "*-php-directories.pl" ],
	[ "Other scripts", "*.pl" ],
	);

%category_descs = (
"Virtual servers",
"Probably the most important programs are those for creating, listing,
modifying and deleting virtual servers. Because these actions may involve
several steps, all of these programs output messages as the proceed, showing
the success or failure of each step. These programs and their options are
documented below.",

"Backup and restore",
"Virtualmin has the ability to backup and restore virtual servers either
manually or on a set schedule, using the web interface. However, you can also
use the command line programs listed below to make backups. This can be used
for doing your own migration to other systems or products, or manually setting
up custom backup schedules for different servers.",

"Mail and FTP users",
"Each Virtualmin virtual server can have users associated with it, each of
which can be a mailbox, an FTP login, or a database user. Users can be created a
ny managed from the command line, using the programs described below.",

"Mail aliases",
"Virtual servers with email enabled can have mail aliases associated with them,
to forward email either to users within the server, or to addresses at some
other domain. Aliases can also be set up to deliver mail to files, or feed
them to programs as input. The programs in this section allow you to manage
mail aliases from the command line.",

"Custom fields",
"If your Virtualmin install has been configured to allow additional custom
fields to be stored for each virtual server, the programs listed in this
section can also be used to manage those fields.",

"Databases",
"All Virtualmin virtual servers with database features enabled can have several
MySQL and PostgreSQL databases associated with them. These can be created and
deleted from the web interface, or using the following programs.",

"Extra administrators",
"All Virtualmin virtual servers can have additional administration accounts
created, which are similar to the server administrator Webmin login, but
possibly with limited capabilities. These extra admin accounts can be
created and managed using the following programs.",

"Reseller accounts",
"If your Virtualmin site uses resellers, they can also be managed using the
command-line programs documented in this section. All of the reseller options
that can be set through the web interface can also be controlled from the
Unix shell prompt.",

"Script installers",
"Virtualmin allows scripts created by other developers to be easily installed
into the virtual servers that it manages. These are typically programs like
Wikis, Blogs and web-based mail readers, often written in PHP. Normally these
are setup through the web interface, but they can be managed by the following
command-line programs as well.",

"Proxies and balancers",
"XXX",

"PHP versions",
"XXX",

"Other scripts",
"XXX",
	);

@skip_scripts = ( "upload-api-docs.pl",
		  "functional-test.pl",
		  "generate-script-sites.pl",
		  "check-scripts.pl",
		  "fetch-script-files.pl" );

# Go to script's directory
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);

# Build category mappings
my %catmap;
foreach my $c (@api_categories) {
	my ($cname, @cglobs) = @$c;
	foreach my $cglob (@cglobs) {
		foreach $f (glob($cglob)) {
			$catmap{$f} ||= $cname;
			}
		}
	}

# Find all API scripts
@apis = ( );
opendir(DIR, $pwd);
foreach my $f (readdir(DIR)) {
	if ($f =~ /\.pl$/ && &indexof($f, @skip_scripts) < 0) {
		local $/ = undef;
		open(FILE, "$pwd/$f");
		my $data = <FILE>;
		close(FILE);
		if ($data =~ /=head1/) {
			push(@apis, { 'file' => $f,
				      'path' => "$pwd/$f",
				      'data' => $data,
				      'cat' => $catmap{$f} });
			}
		elsif ($data =~ /WEBMIN_CONFIG/) {
			print STDERR "$f is missing POD documentation\n";
			}
		}
	}

# Work out output files
$tempdir = "/tmp/virtualmin-api";
mkdir($tempdir, 0755);
foreach $a (@apis) {
	$a->{'wikiname'} = $a->{'file'};
	$a->{'wikiname'} =~ s/\.pl$/\.txt/;
	$a->{'wikiname'} =~ s/\-/_/g;
	$a->{'wikiname'} = "virtualmin_api_".$a->{'wikiname'};
	$a->{'wikifile'} = "$tempdir/$a->{'wikiname'}";
	@wst = stat($a->{'wikifile'});
	@cst = stat($a->{'path'});
	if (@wst && $wst[9] >= $cst[9]) {
		# New enough
		$a->{'done'} = 1;
		}
	}

# Write out category pages
foreach $c (&unique(map { $_->{'cat'} } @apis)) {
	next if (!$c);
	$catname = $c;
	$catname =~ s/ /_/g;
	$catname = lc($catname);
	$catname = "virtualmin_cat_".$catname;
	$catfile = "$tempdir/$catname";
	open(CAT, ">>$catfile");
	# XXX summary
	# XXX links to scripts
	close(CAT);
	}

# Convert to wiki format
print "Converting to Wiki format ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	$a->{'wiki'} = &convert_to_wiki($a->{'data'});
	}

# Extract command-line args summary, by running with --help flag
print "Adding command-line flags ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	print STDERR "doing $a->{'file'}\n";
	$out = `$a->{'path'} --help 2>&1`;
	if ($out =~ /usage:/) {
		$out =~ s/^.*\n\n//;	# Strip description
		$a->{'wiki'} .= "====== Command Line Help ======\n";
		$a->{'wiki'} .= "\n";
		$a->{'wiki'} .= "<code>$out</code>";
		}
	else {
		print STDERR "Failed to get args for $a->{'file'}\n";
		}
	}

# Write pages to temp dir
print "Writing out wiki format files ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	open(WIKI, ">$a->{'wikifile'}");
	print WIKI $a->{'wiki'};
	close(WIKI);
	}

# Upload to server
print "Uploading to Wiki server $wiki_pages_host ..\n";
foreach $a (@apis) {
	#system("su $wiki_pages_su -c 'scp $a->{'wikifile'} $wiki_pages_user\@$wiki_pages_host:$wiki_pages_dir/$a->{'wikiname'}'");
	}

sub convert_to_wiki
{
local ($data) = @_;
my $parser = Pod::Simple::Wiki->new('dokuwiki');
local $infile = "/tmp/pod2wiki.in";
local $outfile = "/tmp/pod2wiki.out";
open(INFILE, ">$infile");
print INFILE $data;
close(INFILE);
open(INFILE, "<$infile");
open(OUTFILE, ">$outfile");
$parser->output_fh(*OUTFILE);
$parser->parse_file(*INFILE);
close(INFILE);
close(OUTFILE);
return `cat $outfile`;
}

# unique
# Returns the unique elements of some array
sub unique
{
local(%found, @rv, $e);
foreach $e (@_) {
	if (!$found{$e}++) { push(@rv, $e); }
	}
return @rv;
}

# indexof(string, array)
# Returns the index of some value in an array, or -1
sub indexof {
  local($i);
  for($i=1; $i <= $#_; $i++) {
    if ($_[$i] eq $_[0]) { return $i - 1; }
  }
  return -1;
}


