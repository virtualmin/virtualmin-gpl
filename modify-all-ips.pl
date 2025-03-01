#!/usr/local/bin/perl

=head1 modify-all-ips.pl

Update all virtual servers with a new IP address.

This command updates all virtual servers using the IP address specified with
the C<--old-ip> flag, and switches them to using the IP set by C<--new-ip>. It
can be useful if your system's IP address has just changed, for example if it
is dynamically assigned or was moved to a new network.

For convenience, the flag C<--default-old-ip> can be used instead of C<--old-ip>
to select the default address used before the last update. Similarly, the flag
C<--detect-new-ip> can be used instead of C<--new-ip> to automatically discover
the system's current default address.

Similarly, you can use the C<--old-ip6> and C<--new-ip6> flags to change the
IPv6 address on multiple domains. The flag C<--detect-newip6> can alternately
be used to automatically find the system's IPv6 address.

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
	$0 = "$pwd/modify-all-ips.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-all-ips.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--old-ip") {
		$oldip = shift(@ARGV);
		&check_ipaddress($oldip) || &usage("--old-ip must be followed ".
						   "by an IP address");
		}
	elsif ($a eq "--default-old-ip") {
		$oldip = $config{'old_defip'};
		$oldip || &usage("The previous IP address is not known");
		}
	elsif ($a eq "--new-ip") {
		$newip = shift(@ARGV);
		&check_ipaddress($newip) || &usage("--new-ip must be followed ".
						   "by an IP address");
		}
	elsif ($a eq "--detect-new-ip") {
		$newip = &get_default_ip();
		$newip || &usage("Failed to determine new IP address");
		}
	elsif ($a eq "--old-ip6") {
		$oldip6 = shift(@ARGV);
		&check_ip6address($oldip6) ||
			&usage("--old-ip6 must be followed ".
			       "by an IPv6 address");
		}
	elsif ($a eq "--new-ip6") {
		$newip6 = shift(@ARGV);
		&check_ip6address($newip6) ||
			&usage("--new-ip6 must be followed ".
			       "by an IPv6 address");
		}
	elsif ($a eq "--detect-new-ip6") {
		$newip6 = &get_default_ip6();
		$newip6 || &usage("Failed to determine new IPv6 address");
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
if ($oldip) {
	$newip || &usage("One of --new-ip or --detect-new-ip must be given");
	}
if ($oldip6) {
	$newip6 || &usage("One of --new-ip6 or --detect-new-ip6 must be given");
	}
if (!$oldip && !$oldip6) {
	&usage("One of --old-ip, --default-old-ip or --old-ip6 must be given");
	}
!$oldip || $oldip ne $newip ||
	&usage("The old and new IP addresses are the same!");
!$oldip6 || $oldip6 ne $newip6 ||
	&usage("The old and new IPv6 addresses are the same!");

# Do the IPv4 change on all domains
if ($oldip) {
	&$first_print("Changing IP addresses from $oldip to $newip ..");
	&$indent_print();
	$dc = &update_all_domain_ip_addresses($newip, $oldip);
	&$outdent_print();
	&$second_print(".. updated $dc virtual servers");

	# Also change shared IP
	@shared = &list_shared_ips();
	$idx = &indexof($oldip, @shared);
	if ($idx >= 0 && $newip ne &get_default_ip()) {
		&$first_print("Updating shared IP address $oldip ..");
		$shared[$idx] = $newip;
		&save_shared_ips(@shared);
		&$second_print(".. changed to $newip");
		}

	# Update any DNS slaves that were replicating from this IP
	&$first_print("Updating slave DNS servers ..");
	$bc = &update_dns_slave_ip_addresses($newip, $oldip);
	&$second_print(".. updated $bc domains");

	# Update the old default IP, which is used by a dashboard warning
	$config{'old_defip'} = &get_default_ip();
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	}

# Do the IPv6 change on all domains
if ($oldip6) {
	&$first_print("Changing IPv6 addresses from $oldip6 to $newip6 ..");
	&$indent_print();
	$dc = &update_all_domain_ip_addresses($newip6, $oldip6);
	&$outdent_print();
	&$second_print(".. updated $dc virtual servers");

	# Also change shared IPv6
	@shared = &list_shared_ip6s();
	$idx = &indexof($oldip6, @shared);
	if ($idx >= 0 && $newip6 ne &get_default_ip6()) {
		&$first_print("Updating shared IPv6 address $oldip6 ..");
		$shared[$idx] = $newip6;
		&save_shared_ip6s(@shared);
		&$second_print(".. changed to $newip6");
		}

	# Update the old default IPv6, which is used by a dashboard warning
	$config{'old_defip6'} = &get_default_ip6();
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
exit(0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Update all virtual servers with a new IP address.\n";
print "\n";
print "virtualmin modify-all-ips [--old-ip address | --default-old-ip]\n";
print "                          [--new-ip address | --detect-new-ip]\n";
print "                          [--old-ip6 address]\n";
print "                          [--new-ip6 address | --detect-new-ip6]\n";
exit(1);
}


