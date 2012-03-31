#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into HTML format, and upload them to
# virtualmin.com.

use Pod::Simple::HTML;

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/virtualmin-api";
$wiki_pages_su = "jcameron";
require 'commands-lib.pl';

while(@ARGV) {
	$a = shift(@ARGV);
	if ($a eq "--no-upload") {
		$noupload = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

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
		foreach my $dir (&list_api_directories($pwd)) {
			chdir($dir);
			foreach $f (glob($cglob)) {
				$catmap{$f} ||= $cname;
				}
			}
		chdir($pwd);
		}
	}

# Find all API scripts
@apis = ( );
@skip_scripts = &list_api_skip_scripts();
foreach my $dir (&list_api_directories($pwd)) {
	opendir(DIR, $dir);
	foreach my $f (readdir(DIR)) {
		if ($f =~ /\.pl$/ && &indexof($f, @skip_scripts) < 0) {
			local $/ = undef;
			open(FILE, "$dir/$f");
			my $data = <FILE>;
			close(FILE);
			if ($data =~ /=head1/) {
				push(@apis, { 'file' => $f,
					      'path' => "$dir/$f",
					      'data' => $data,
					      'cat' => $catmap{$f} });
				}
			elsif ($data =~ /WEBMIN_CONFIG/) {
				print STDERR "$f is missing POD format docs\n";
				}
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
	$a->{'wikifile'} = "$tempdir/$a->{'wikiname'}.html";
	@wst = stat($a->{'wikifile'});
	@cst = stat($a->{'path'});
	if (@wst && $wst[9] >= $cst[9]) {
		# New enough
		$a->{'done'} = 1;
		$a->{'wiki'} = `cat $a->{'wikifile'}`;
		$a->{'title'} = &extract_html_title($a->{'wiki'});
		}
	$a->{'cmd'} = $a->{'file'};
	$a->{'cmd'} =~ s/\.pl$//;
	}

# Convert to wiki format
print "Converting to Wiki format ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	($a->{'wiki'}, $a->{'title'}) = &convert_to_html($a->{'data'});
	$a->{'wiki'} =~ s/\.pl\s+<\/a>/ <\/a>/;		# Remove .pl from title
	}

# Extract command-line args summary, by running with --help flag
print "Adding command-line flags ..\n";
foreach $a (@apis) {
	next if ($a->{'done'});
	print STDERR "doing $a->{'file'}\n";
	$out = `$a->{'path'} --help 2>&1`;
	if ($out =~ /usage:|\nvirtualmin/) {
		$out =~ s/^.*\n\n//;	# Strip description
		$usage = "<h1>Command Line Help</h1>\n".
			 "\n".
			 "<pre>$out</pre>\n";
		$a->{'wiki'} =~ s/<\/body>/$usage<\/body>/;
		}
	else {
		print STDERR "Failed to get args for $a->{'file'}\n";
		}
	}

# Write pages to temp dir
print "Writing out HTML format files ..\n";
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
	$catfile = "$tempdir/$catname.html";
	open(CAT, ">$catfile");
	print CAT "<html>\n";
	print CAT "<title>$c</title>\n";
	print CAT "<body>\n";
	print CAT "<h1>$c</h1>\n";
	print CAT "<p>",$category_descs{$c},"</p>\n";
	print CAT "<ul>\n";
	@incat = grep { $_->{'cat'} eq $c } @apis;
	foreach $a (sort { $a->{'wikiname'} cmp $b->{'wikiname'} } @incat) {
		print CAT "<li><a href=$a->{'wikiname'}>$a->{'cmd'}</a> - $a->{'title'}</li>\n";
		}
	print CAT "</ul>\n";
	print CAT "</body>\n";
	print CAT "</html>\n";
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
open(PAGE, ">$tempdir/virtualmin_script_installers.html");
print PAGE "<html>\n";
print PAGE "<title>Virtualmin Script Installers</title>\n";
print PAGE "<body>\n";
print PAGE "<h1>Virtualmin Script Installers</h1>\n";
print PAGE "\n";
print PAGE "<p>The following scripts can be installed by the latest version ";
print PAGE "of Virtualmin professional :</p>\n\n";
print PAGE "<table>\n";
print PAGE "<tr> <th>Name</th> <th>Description</th> <th>Versions</th> </tr>\n";
foreach $s (sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @scripts) {
	next if ($s->{'available'} ne 'Yes');
	next if ($s->{'description'} eq '');
	$s->{'versions'} =~ s/ / , /g;
	print PAGE "<tr> <td>$s->{'name'}</td> <td>$s->{'description'}</td> <td>$s->{'versions'}</td> </tr>\n";
	}
print PAGE "</table>\n";
print PAGE "</body>\n";
print PAGE "</html>\n";
close(PAGE);

# Upload to server
if (!$noupload) {
	print "Uploading to Wiki server $wiki_pages_host ..\n";
	system("su $wiki_pages_su -c 'scp $tempdir/* $wiki_pages_user\@$wiki_pages_host:$wiki_pages_dir/'");
	}

# convert_to_html(pod-text)
# Converts a POD-format text into HTML format, and returns that and
# the program summary line.
sub convert_to_html
{
local ($data) = @_;
my $parser = Pod::Simple::HTML->new('dokuwiki');
local $infile = "/tmp/pod2html.in";
local $outfile = "/tmp/pod2html.out";
open(INFILE, ">$infile");
print INFILE $data;
close(INFILE);
open(INFILE, "<$infile");
open(OUTFILE, ">$outfile");
$parser->output_fh(*OUTFILE);
$parser->parse_file(*INFILE);
close(INFILE);
close(OUTFILE);
local $html = `cat $outfile`;
return ($html, &extract_html_title($html));
}

sub extract_html_title
{
local ($html) = @_;
if ($html =~ /<p>([^<]+)<\/p>/i) {
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

sub usage
{
print STDERR "upload-api-docs.pl [--no-upload]\n";
exit(1);
}

