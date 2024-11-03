#!/usr/local/bin/perl

=head1 detect-scripts.pl

Find scripts manually installed in some virtual server.

If you have installed supported apps like Wordpress into a Virtualmin domain
without using the built-in app installer feature, or have copied a website
from another non-Virtualmin system, this command will find those apps and
make them visible on the Manage Web Apps page.

The server to search must be set with the C<--domain> flag, and you can
optionally limit the search to a specific directory under the root with
the C<--dir> flag followed by a full path. By default any detected apps will
be immediately added to Virtualmin's database, but you can choose to just
display them instead with the C<--test> flag.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/detect-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "detect-scripts.pl must be run as root";
	}
@OLDARGV = @ARGV;

&foreign_require("mailboxes");
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--dir") {
		$dir = shift(@ARGV);
		}
	elsif ($a eq "--test") {
		$testmode = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args
$dname || &usage("No domain specified");
$d = &get_domain_by("dom", $dname);
$d || &usage("Domain $dname does not exist!");

# Search for scripts
&$first_print("Searching for installed scripts".
	      ($dir ? " under $dir" : "")."..");
@sinfos = &detect_installed_scripts($d, $dir);
&$second_print(".. found ",scalar(@sinfos)," scripts");

# Show what was found, and maybe save them
if (@sinfos) {
	if ($multiline) {
		foreach $sinfo (@sinfos) {
			$script = &get_script($sinfo->{'name'});
			$opts = $sinfo->{'opts'};
			print "$sinfo->{'name'}:\n";
			print "    Description: ",$script->{'desc'},"\n";
			print "    Version: $sinfo->{'version'}\n";
			if ($sinfo->{'url'}) {
				print "    URL: $sinfo->{'url'}\n";
				}
			if ($opts->{'dir'}) {
				print "    Directory: $opts->{'dir'}\n";
				}
			($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
			if ($dbtype) {
				print "    Database: $dbname ($dbtype)\n";
				}
			print "    Detected: ",
				($sinfo->{'already'} ? "Already known"
						     : "Newly detected"),"\n";
			}
		}
	else {
		$fmt = "%-18.18s %-10.10s %-10.10s %-35.35s\n";
		printf $fmt, "Type", "Detected?", "Version", "URL path";
		printf $fmt, ("-" x 18), ("-" x 10), ("-" x 10), ("-" x 35);
		foreach $sinfo (@sinfos) {
			$script = &get_script($sinfo->{'name'});
			$path = $sinfo->{'url'};
			$path =~ s/^(http|https):\/\/([^\/]+)//;
			$path ||= $sinfo->{'path'};
			printf $fmt, $sinfo->{'name'},
				$sinfo->{'already'} ? "Existing" : "New",
				$sinfo->{'version'},
				$path;
			}
		}
	}

if (!$testmode) {
	foreach my $sinfo (@sinfos) {
		next if ($sinfo->{'already'});
		&add_domain_script($d, $sinfo->{'name'}, $sinfo->{'version'},
				   $sinfo->{'opts'}, $sinfo->{'desc'},
				   $sinfo->{'url'}, $sinfo->{'user'},
				   $sinfo->{'pass'});
		}
	&virtualmin_api_log(\@OLDARGV, $d);
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Find scripts manually installed in some virtual server.\n";
print "\n";
print "virtualmin detect-scripts --domain domain.name\n";
print "                         [--dir directory]\n";
print "                         [--test]\n";
exit(1);
}

