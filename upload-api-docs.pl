#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into Wiki format, and upload them to
# virtualmin.com.

use Pod::Simple::Wiki;

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/domains/jdev.virtualmin.com/public_html/components/com_openwiki/data/pages";
$wiki_pages_su = "jcameron";
require 'commands-lib.pl';

# Go to script's directory
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);

# Build category mappings
my %catmap;
foreach my $c (&list_api_categories()) {
	my ($cname, @cglobs) = @$c;
	foreach my $cglob (@cglobs) {
		foreach $f (glob($cglob)) {
			$catmap{$f} ||= $cname;
			}
		}
	}

# Find all API scripts
@apis = ( );
@skip_scripts = &list_api_skip_scripts();
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
	$a->{'wikiname'} =~ s/\.pl$//;
	$a->{'wikiname'} =~ s/\-/_/g;
	$a->{'wikiname'} = "virtualmin_api_".$a->{'wikiname'};
	$a->{'wikifile'} = "$tempdir/$a->{'wikiname'}.txt";
	@wst = stat($a->{'wikifile'});
	@cst = stat($a->{'path'});
	if (@wst && $wst[9] >= $cst[9]) {
		# New enough
		$a->{'done'} = 1;
		$a->{'wiki'} = `cat $a->{'wikifile'}`;
		$a->{'title'} = &extract_wiki_title($a->{'wiki'});
		}
	}

# Convert to wiki format
print "Converting to Wiki format ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	($a->{'wiki'}, $a->{'title'}) = &convert_to_wiki($a->{'data'});
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

# Write out category pages
print "Creating category pages ..\n";
%category_descs = &list_api_category_descs();
foreach $c (&unique(map { $_->{'cat'} } @apis)) {
	next if (!$c);
	$catname = $c;
	$catname =~ s/ /_/g;
	$catname = lc($catname);
	$catname = "virtualmin_cat_".$catname;
	$catfile = "$tempdir/$catname.txt";
	open(CAT, ">$catfile");
	print CAT "====== $c ======\n\n";
	print CAT $category_descs{$c},"\n\n";
	@incat = grep { $_->{'cat'} eq $c } @apis;
	foreach $a (@incat) {
		print CAT "   * [[$a->{'wikiname'}|$a->{'file'}]] - $a->{'title'}\n";
		}
	print CAT "\n";
	close(CAT);
	}

# Create a special page for scripts
print "Creating scripts page ..\n";
open(SCRIPTS, "./list-available-scripts.pl --multiline --source core |");
while(<SCRIPTS>) {
	s/\r|\n//g;
	if (/^(\S+)$/) {
		$script = { 'id' => $1 };
		push(@scripts, $script);
		}
	elsif (/^\s+(\S+):\s*(.*)/) {
		$script->{lc($1)} = $2;
		}
	}
close(SCRIPTS);
open(PAGE, ">$tempdir/virtualmin_script_installers.txt");
print PAGE "====== Virtualmin Script Installers ======\n";
print PAGE "\n";
print PAGE "The following scripts can be installed by the latest version of ";
print PAGE "Virtualmin professional :\n\n";
$hfmt = "^ %-20.20s ^ %-80.80s ^ %-20.20s ^\n";
($rfmt = $hfmt) =~ s/\^/\|/g;
printf PAGE $hfmt, "Name", "Description", "Versions";
foreach $s (sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @scripts) {
	next if ($s->{'available'} ne 'Yes');
	next if ($s->{'description'} eq '');
	$s->{'versions'} =~ s/ / , /g;
	printf PAGE $rfmt, $s->{'name'}, $s->{'description'}, $s->{'versions'};
	}
close(PAGE);

# Upload to server
print "Uploading to Wiki server $wiki_pages_host ..\n";
foreach $a (@apis) {
	#system("su $wiki_pages_su -c 'scp $a->{'wikifile'} $wiki_pages_user\@$wiki_pages_host:$wiki_pages_dir/$a->{'wikiname'}'");
	}
system("su $wiki_pages_su -c 'scp $tempdir/* $wiki_pages_user\@$wiki_pages_host:$wiki_pages_dir/'");

# convert_to_wiki(pod-text)
# Converts a POD-format text into Dokuwiki format, and returns that and
# the program summary line.
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
local $wiki = `cat $outfile`;
return ($wiki, &extract_wiki_title($wiki));
}

sub extract_wiki_title
{
local ($wiki) = @_;
if ($wiki =~ /^======.*======\n(\S.*)\n/) {
	return $1;
	}
return undef;
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


