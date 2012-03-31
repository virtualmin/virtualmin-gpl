#!/usr/local/bin/perl

=head1 list-shared-addresses.pl

Lists shared IP addresses for virtual servers

This command outputs a list of shared IP addresses that can be used by new
or existing virtual servers. You can use the --shared-ip flag to
C<create-domain> to add the virtual server on one of the listed IPs.

Output is in table format by default, but you can switch to a more detailed
and easily parsed list with the C<--multiline> flag. Or to just get a list
of addresses, use the C<--name-only> parameter.

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
	$0 = "$pwd/list-shared-addresses.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-shared-addresses.pl must be run as root";
	}
use POSIX;

# Parse command-line args
$owner = 1;
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

# Get the IPs
push(@ips, { 'ip' => &get_default_ip(), 'type' => 'default' });
if (defined(&list_resellers)) {
	foreach $r (&list_resellers()) {
		if ($r->{'acl'}->{'defip'}) {
			push(@ips, { 'ip' => $r->{'acl'}->{'defip'},
				     'type' => 'reseller',
				     'reseller' => $r->{'name'} });
			}
		}
	}
foreach $ip (&list_shared_ips()) {
	push(@ips, { 'ip' => $ip, 'type' => 'shared' });
	}

if ($multi) {
	# Several lines each
	foreach $ip (@ips) {
		print "$ip->{'ip'}\n";
		print "    Type: $ip->{'type'}\n";
		if ($ip->{'reseller'}) {
			print "    Reseller: $ip->{'reseller'}\n"
			}
		@doms = &get_domain_by("ip", $ip->{'ip'});
		foreach $d (@doms) {
			print "    Virtual server: $d->{'dom'}\n";
			}
		}
	}
elsif ($nameonly) {
	# Just addresses
	foreach $ip (@ips) {
		print $ip->{'ip'},"\n";
		}
	}
else {
	# One per line
	$fmt = "%-20.20s %-20.20s %-30.30s\n";
	printf $fmt, "Address", "Type", "Reseller name";
	printf $fmt, ("-" x 20), ("-" x 20), ("-" x 30);
	foreach $ip (@ips) {
		printf $fmt, $ip->{'ip'},
			     $ip->{'type'} eq 'default' ? 'System default' :
			     $ip->{'type'} eq 'reseller' ? 'Reseller' :
			     $ip->{'type'} eq 'shared' ? 'Shared address' :
							 $ip->{'type'},
			     $ip->{'reseller'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available shared IP addresses for new virtual servers.\n";
print "\n";
print "virtualmin list-shared-addresses [--multiline | --name-only]\n";
exit(1);
}


