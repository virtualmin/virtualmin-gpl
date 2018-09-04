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
	elsif ($a eq "--activate") {
		$activate = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs
$ip || &usage("Either the --ip or --allocate-ip flag must be given");
$ip eq "allocate" || &check_ipaddress($ip) ||
	&usage("The --ip flag must be followed by a valid address");
if ($ip eq "allocate" && !$activate) {
	&usage("The --allocate-ip flag can only be used when --activate is");
	}

# Get all existing shared IPs
@ips = ( &get_default_ip(), &list_shared_ips() );
if (defined(&list_resellers)) {
	push(@ips, map { $r->{'acl'}->{'defip'} } &list_resellers());
	}
if ($ip ne "allocate") {
	&indexof($ip, @ips) < 0 ||
		&usage("IP address $ip is already a shared address");
	$clash = &get_domain_by("ip", $ip);
	$clash && &usage("The virtual server $clash->{'dom'} is already using ".
			 "address $ip");
	}

# Try to allocate the IP if required
if ($ip eq "allocate") {
	$tmpl = &get_template(&get_init_template(0));
	$tmpl->{'ranges'} || &usage("The --allocate-ip flag cannot be used ".
				  "unless IP allocation ranges are configured");
	($ip, $netmask) = &free_ip_address($tmpl);
	$ip || &usage("Failed to find a free IP address in ".
		      "range $tmpl->{'ranges'}");
	&indexof($ip, @ips) < 0 ||
		&usage("Allocated IP address $ip is already a shared address");
	}

# Activate if required, otherwise ensure it is on the system
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

# Add to shared list
@oldips = &list_shared_ips();
&lock_file($module_config_file);
&save_shared_ips(@oldips, $ip);
&unlock_file($module_config_file);
print "Created shared IP address $ip\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a new IP address for use by multiple virtual servers.\n";
print "\n";
print "virtualmin create-shared-address --ip address | --allocate-ip\n";
print "                                [--activate]\n";
exit(1);
}


