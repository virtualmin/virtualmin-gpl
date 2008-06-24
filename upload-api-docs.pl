#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into Wiki format, and upload them to
# virtualmin.com.

use Pod::Simple::Wiki;

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/domains/jdev.virtualmin.com/public_html/components/com_openwiki/data/pages";
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

# Detect any pattern matches


# XXX identify categories (domains, users, etc..)
# XXX category summaries?

# Write out category pages
foreach $c (&unique(map { $_->{'cat'} } @apis)) {
	next if (!$c);
	}

# Convert to wiki format
print "Converting to Wiki format ..\n";
foreach $a (@apis) {
	$a->{'wiki'} = &convert_to_wiki($a->{'data'});
	}

# Extract command-line args summary, by running with --help flag
print "Adding command-line flags ..\n";
foreach $a (@apis) {
	print STDERR "doing $a->{'file'}\n";
	$out = `$a->{'path'} --help 2>&1`;
	if ($out =~ /usage:/) {
		$out =~ s/^.*\n\n//;	# Strip description
		$a->{'wiki'} .= "====== Command Line Arguments ======\n";
		$a->{'wiki'} .= "\n";
		$a->{'wiki'} .= "<code>$out</code>";
		}
	else {
		print STDERR "Failed to get args for $a->{'file'}\n";
		}
	}

# Write pages to temp dir
print "Writing out wiki format files ..\n";
$tempdir = "/tmp/virtualmin-api";
mkdir($tempdir, 0755);
foreach $a (@apis) {
	$a->{'wikiname'} = $a->{'file'};
	$a->{'wikiname'} =~ s/\.pl$/\.txt/;
	$a->{'wikiname'} =~ s/\-/_/g;
	$a->{'wikiname'} = "virtualmin_api_".$a->{'wikiname'};
	$a->{'wikifile'} = "$tempdir/$a->{'wikiname'}";
	open(WIKI, ">$a->{'wikifile'}");
	print WIKI $a->{'wiki'};
	close(WIKI);
	}

# Upload to server
print "Uploading to Wiki server $wiki_pages_host ..\n";
foreach $a (@apis) {
	#system("scp $a->{'wikifile'} $wiki_pages_user\@$wiki_pages_host:$wiki_pages_dir/$a->{'wikiname'}");
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


