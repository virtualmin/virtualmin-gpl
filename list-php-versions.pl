#!/usr/local/bin/perl

=head1 list-php-versions.pl

Lists the available PHP versions on this system.

This command simply outputs a table of the installed PHP versions on your
system. Use the C<--name-only> flag to limit the output to version numbers only,
or C<--multiline> to show more details.

By default all versions available on the system will be shown, but you can
limit the list to those available for one virtual server with the C<--domain>
flag.

=cut

package virtual_server;
if (!$module_name) {
	$no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/list-php-versions.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-php-versions.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

if ($dname) {
	$d = &get_domain_by("dom", $dname);
	$d || &usage("Virtual server $dname does not exist");
	}

@vers = &list_available_php_versions($d);
$fmt = "%-15.15s %-60.60s\n";
if ($nameonly) {
	# Just show version numbers
	foreach $s (@vers) {
		print $s->[0],"\n";
		}
	}
elsif ($multiline) {
	# Show full details
	foreach $s (@vers) {
		print $s->[0],"\n";
		if ($s->[1]) {
			print "    Command: $s->[1]\n";
			}
		if ($s->[2]) {
			print "    PHP modes: ",join(" ", @{$s->[2]}),"\n";
			}
		$fpm = &get_php_fpm_config($s->[0]);
		print "    FPM support: ",($fpm ? "Yes" : "No"),"\n";
		$fv = &get_php_version($s->[0]);
		print "    Full version: ",$fv,"\n";
		}
	}
else {
	# Show table of details
	printf $fmt, "Version", "Path";
	printf $fmt, ("-" x 15), ("-" x 60);
	foreach $s (@vers) {
		printf $fmt, $s->[0], $s->[1];
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available PHP versions on this system.\n";
print "\n";
print "virtualmin list-php-versions [--name-only | --multiline]\n";
print "                             [--domain name]\n";
exit(1);
}


