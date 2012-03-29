#!/usr/local/bin/perl

=head1 delete-shared-address.pl

Removes an IP address that can be used by virtual servers

This command takes a single IP address out of the list available for use by
multiple virtual servers, specified with the C<--ip> flag. If the
C<--deactivate> flag is also given, the virtual interface associated with the
IP will also be shut down.

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
	$0 = "$pwd/delete-shared-address.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-shared-address.pl must be run as root";
	}
@OLDARGV = @ARGV;
use POSIX;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--ip") {
		$ip = shift(@ARGV);
		}
	elsif ($a eq "--deactivate") {
		$deactivate = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Validate inputs
$ip && &check_ipaddress($ip) ||
	&usage("The --ip flag must be given, and followed by an address");
@oldips = &list_shared_ips();
&indexof($ip, @oldips) >= 0 ||
	&usage("The IP address $ip is not on Virtualmin's shared address list");
@clash = &get_domain_by("ip", $ip);
@clash && &usage("The IP address $ip cannot be removed, as it is being used ".
		 "by virtual servers : ".
	 	 join(" ", map { $_->{'dom'} } @clash));

# De-activate if requested
if ($deactivate) {
	&obtain_lock_virt();
	$err = &deactivate_shared_ip($ip);
	&usage("De-activation failed : $err") if ($err);
	&release_lock_virt();
	}

# Remove from shared list
&lock_file($module_config_file);
@oldips = grep { $_ ne $ip } @oldips;
&save_shared_ips(@oldips);
&unlock_file($module_config_file);
print "Removed shared IP address $ip\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes an IP address that was used by multiple virtual servers.\n";
print "\n";
print "virtualmin delete-shared-address --ip address\n";
print "                                [--deactivate]\n";
exit(1);
}


