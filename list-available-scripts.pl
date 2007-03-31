#!/usr/local/bin/perl
# Lists all scripts that are available for install

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-available-scripts.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-available-scripts.pl must be run as root";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	else {
		&usage();
		}
	}

@scripts = map { &get_script($_) } &list_scripts();
if ($multi) {
	# Show each script on a separate line
	$overall = &get_overall_script_ratings();
	foreach $script (@scripts) {
		print "$script->{'name'}\n";
		print "    Name: $script->{'desc'}\n";
		if ($script->{'category'}) {
			print "    Category: $script->{'category'}\n";
			}
		print "    Versions: ",join(" ", @{$script->{'versions'}}),"\n";
		print "    Available: ",$script->{'avail'} ? "Yes" : "No","\n";
		print "    Description: $script->{'longdesc'}\n";
		print "    Uses: ",join(" ", @{$script->{'uses'}}),"\n";
		if ($overall->{$script->{'name'}}) {
			print "    Rating: ".$overall->{$script->{'name'}}."\n";
			}
		}
	}
else {
	# Show all on one line
	$fmt = "%-30.30s %-30.30s %-10.10s\n";
	printf $fmt, "Name", "Versions", "Available?";
	printf $fmt, ("-" x 30), ("-" x 30), ("-" x 10);
	foreach $script (@scripts) {
		printf $fmt, $script->{'desc'},
			     join(" ", @{$script->{'versions'}}),
			     $script->{'avail'} ? "Yes" : "No";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the third-party scripts available for installation.\n";
print "\n";
print "usage: list-available-scripts.pl [--multiline]\n";
exit(1);
}

