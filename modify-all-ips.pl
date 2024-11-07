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
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$oldip || &usage("One of --old-ip or --default-old-ip must be given");
$newip || &usage("One of --new-ip or --detect-new-ip must be given");
$oldip ne $newip || &usage("The old and new IP addresses are the same!");

# Do the change on all domains
&$first_print("Changing IP address from $oldip to $newip ..");
&$indent_print();
$dc = &update_all_domain_ip_addresses($newip, $oldip);
&$outdent_print();
&$second_print(".. updated $dc virtual servers");

# Also change shared IP
@shared = &list_shared_ips();
$idx = &indexof($oldip, @shared);
if ($idx >= 0) {
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
exit(1);
}


