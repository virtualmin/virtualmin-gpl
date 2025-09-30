#!/usr/local/bin/perl

=head1 create-shared-address.pl

Adds an IP address for use by multiple virtual servers

This command can be used to make an existing IP address on your system available
for multiple virtual servers. You must supply the C<--ip> flag, followed by
the address of an interface that is already active.

Alternately, it can select and activate a free IP address with the 
C<--allocate-ip> and C<--activate> flags. However, you must first have defined
an allocation range in the Virtual IP Addresses section of the default server
template.

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
	$0 = "$pwd/create-shared-address.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-shared-address.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--ip") {
		$ip = shift(@ARGV);
		}
	elsif ($a eq "--allocate-ip") {
		$ip = "allocate";
		}
	elsif ($a eq "--ip6") {
		$ip6 = shift(@ARGV);
		}
	elsif ($a eq "--allocate-ip6") {
		$ip6 = "allocate";
		}
	elsif ($a eq "--activate") {
		$activate = 1;
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

# Validate inputs
$ip || $ip6 || &usage("One of the --ip, --allocate-ip, --ip6 or --allocate-ip6 flag must be given");
!$ip || $ip eq "allocate" || &check_ipaddress($ip) ||
	&usage("The --ip flag must be followed by a valid address");
!$ip6 || $ip6 eq "allocate" || &check_ip6address($ip6) ||
	&usage("The --ip6 flag must be followed by a valid IPv6 address");
if ($ip eq "allocate" && !$activate) {
	&usage("The --allocate-ip flag can only be used when --activate is");
	}

# Get all existing shared IPs
@ips = ( &get_default_ip(), &list_shared_ips() );
if (defined(&list_resellers)) {
	push(@ips, grep { $_ } map { $r->{'acl'}->{'defip'} } &list_resellers());
	}
if ($ip && $ip ne "allocate") {
	&indexof($ip, @ips) < 0 ||
		&usage("IP address $ip is already a shared address");
	$clash = &get_domain_by("ip", $ip);
	$clash && &usage("The virtual server $clash->{'dom'} is already using ".
			 "address $ip");
	}

# Get all existing shared IPv6 addresses
@ip6s = ( &get_default_ip6(), &list_shared_ip6s() );
if (defined(&list_resellers)) {
	push(@ip6s, grep { $_ } map { $r->{'acl'}->{'defip6'} } &list_resellers());
	}
if ($ip6 && $ip6 ne "allocate") {
	&indexof($ip6, @ip6s) < 0 ||
		&usage("IPv6 address $ip6 is already a shared address");
	$clash = &get_domain_by("ip6", $ip6);
	$clash && &usage("The virtual server $clash->{'dom'} is already using ".
			 "IPv6 address $ip6");
	}

# Try to allocate the IPv4 addresss if required
$tmpl = &get_template(&get_init_template(0));
if ($ip eq "allocate") {
	$tmpl->{'ranges'} || &usage("The --allocate-ip flag cannot be used ".
				  "unless IP allocation ranges are configured");
	($ip, $netmask) = &free_ip_address($tmpl);
	$ip || &usage("Failed to find a free IP address in ".
		      "range $tmpl->{'ranges'}");
	&indexof($ip, @ips) < 0 ||
		&usage("Allocated IP address $ip is already a shared address");
	}

# Try to allocate the IPv6 addresss if required
if ($ip6 eq "allocate") {
	$tmpl->{'ranges6'} || &usage("The --allocate-ip6 flag cannot be used ".
				     "unless IPv6 allocation ranges are configured");
	($ip6, $netmask6) = &free_ip6_address($tmpl);
	$ip6 || &usage("Failed to find a free IPv6 address in ".
		       "range $tmpl->{'ranges6'}");
	&indexof($ip6, @ip6s) < 0 ||
		&usage("Allocated IPv6 address $ip6 is already a shared address");
	}

# Activate if required, otherwise ensure it is on the system
if ($ip) {
	if ($activate) {
		&obtain_lock_virt();
		$err = &activate_shared_ip($ip, $netmask);
		&usage("Activation failed : $err") if ($err);
		&release_lock_virt();
		}
	else {
		%active = map { $_, 1 } &active_ip_addresses();
		$active{$ip} || &usage("IP address $ip does not exist on this system");
		}
	}

# Activate IPv6 if required, otherwise ensure it is on the system
if ($ip6) {
	if ($activate) {
		&obtain_lock_virt();
		$err = &activate_shared_ip6($ip6, $netmask6);
		&usage("Activation failed : $err") if ($err);
		&release_lock_virt();
		}
	else {
		%active = map { $_, 1 } &active_ip_addresses();
		$active{$ip6} || &usage("IPv6 address $ip6 does not exist on this system");
		}
	}

# Add to shared list
if ($ip) {
	&lock_file($module_config_file);
	@oldips = &list_shared_ips();
	&save_shared_ips(@oldips, $ip);
	&unlock_file($module_config_file);
	print "Created shared IP address $ip\n";
	}
if ($ip6) {
	&lock_file($module_config_file);
	@oldip6s = &list_shared_ip6s();
	&save_shared_ip6s(@oldip6s, $ip6);
	&unlock_file($module_config_file);
	print "Created shared IPv6 address $ip6\n";
	}
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a new IP address for use by multiple virtual servers.\n";
print "\n";
print "virtualmin create-shared-address --ip address | --allocate-ip |\n";
print "                                 --ip6 address | --allocate-ip6\n";
print "                                [--activate]\n";
exit(1);
}


