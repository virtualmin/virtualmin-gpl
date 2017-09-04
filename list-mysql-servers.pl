#!/usr/local/bin/perl

=head1 list-mysql-servers.pl

Lists all registered remote MySQL servers.

XXX

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
	$0 = "$pwd/list-mysql-servers.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-mysql-servers.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@mods = &list_remote_mysql_modules();

if ($multi) {
	# Show full details
	foreach $m (@mods) {
		print $m->{'minfo'}->{'dir'},"\n";
		print "    Description: ",&html_tags_to_text($m->{'desc'}),"\n";
		if ($m->{'config'}->{'sock'}) {
			print "    Socket: ",$m->{'config'}->{'sock'},"\n";
			}
		if ($m->{'config'}->{'host'}) {
			print "    Host: ",$m->{'config'}->{'host'},"\n";
			}
		if ($m->{'config'}->{'port'}) {
			print "    Host: ",$m->{'config'}->{'port'},"\n";
			}
		}
	}
elsif ($nameonly) {
	# Just module names
	foreach $m (@mods) {
		print $m->{'minfo'}->{'dir'},"\n";
		}
	}
else {
	# One per line
	$fmt = "%-30.30s %-30.30s %-10.10s\n";
	printf $fmt, "Module", "Host", "Port";
	printf $fmt, ("-" x 30), ("-" x 30), ("-" x 10);
	foreach $m (@mods) {
		printf $fmt, $m->{'minfo'}->{'dir'},
			     $m->{'config'}->{'host'} ||
			       $m->{'config'}->{'sock'} ||
			       'localhost',
			     $m->{'config'}->{'port'} || 3306;
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all registered remote MySQL servers.\n";
print "\n";
print "virtualmin list-mysql-servers [--multiline]\n";
print "                              [--name-only]\n";
exit(1);
}

