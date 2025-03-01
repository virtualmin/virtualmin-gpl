#!/usr/local/bin/perl

=head1 list-shared-addresses.pl

Lists shared IP addresses for virtual servers

This command outputs a list of shared IP addresses that can be used by new
or existing virtual servers.

Output is in table format by default, but you can switch to a more detailed
and easily parsed list with the C<--multiline> flag. Or to just get a list
of addresses, use the C<--name-only> parameter.

By default only shared IPv4 addresses are shown, but you can use the C<--ipv6>
flag to also include IPv6 addresses.

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

# Parse command-line args
$owner = 1;
&parse_common_cli_flags(\@ARGV);
$ipv4 = 1;
$ipv6 = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--ipv6") {
		$ipv6 = 1;
		}
	elsif ($a eq "--no-ipv6") {
		$ipv6 = 0;
		}
	elsif ($a eq "--ipv4") {
		$ipv4 = 1;
		}
	elsif ($a eq "--no-ipv4") {
		$ipv4 = 0;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$ipv4 || $ipv6 || &usage("At least one of IPv4 or IPv6 mode must be enabled");
!$ipv6 || &supports_ip6() || &usage("This system does not support IPv6");

# Get the IPs
if ($ipv4) {
	push(@ips, { 'ip' => &get_default_ip(), 'type' => 'default' });
	}
if ($ipv4) {
	push(@ips, { 'ip' => &get_default_ip6(), 'type' => 'default' });
	}
if (defined(&list_resellers)) {
	foreach $r (&list_resellers()) {
		if ($ipv4 && $r->{'acl'}->{'defip'}) {
			push(@ips, { 'ip' => $r->{'acl'}->{'defip'},
				     'type' => 'reseller',
				     'reseller' => $r->{'name'} });
			}
		if ($ipv6 && $r->{'acl'}->{'defip6'}) {
			push(@ips, { 'ip' => $r->{'acl'}->{'defip6'},
				     'type' => 'reseller',
				     'reseller' => $r->{'name'} });
			}
		}
	}
if ($ipv4) {
	foreach $ip (&list_shared_ips()) {
		push(@ips, { 'ip' => $ip, 'type' => 'shared' });
		}
	}
if ($ipv6) {
	foreach $ip (&list_shared_ip6s()) {
		push(@ips, { 'ip' => $ip, 'type' => 'shared' });
		}
	}

if ($multiline) {
	# Several lines each
	foreach $ip (@ips) {
		print "$ip->{'ip'}\n";
		print "    Type: $ip->{'type'}\n";
		if ($ip->{'reseller'}) {
			print "    Reseller: $ip->{'reseller'}\n"
			}
		@doms = (&get_domain_by("ip", $ip->{'ip'}),
			 &get_domain_by("ip6", $ip->{'ip'}));
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
print "virtualmin list-shared-addresses [--multiline | --json | --xml |\n";
print "                                  --name-only]\n";
print "                                 [--ipv4 | --no-ipv4]\n";
print "                                 [--ipv6 | --no-ipv6]\n";
exit(1);
}


