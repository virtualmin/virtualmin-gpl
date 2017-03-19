#!/usr/local/bin/perl

=head1 delete-proxy.pl

Removes a proxy balancer from some domain

This command deletes one proxy path from the virtual server identified
by the C<--domain> flag. The proxy to remove must be identified by the 
C<--path> parameter. Any backend services that the proxy previously mapped
to will not be halted.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/pro\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/delete-proxy.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-proxy.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
&require_mail();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$domain || &usage("No domain specified");
$path || &usage("No proxy path specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&has_proxy_balancer($d) || &usage("Proxy balancers cannot be configured for this virtual server");

# Get the balancer
&obtain_lock_web($d);
@balancers = &list_proxy_balancers($d);
($b) = grep { $_->{'path'} eq $path } @balancers;
$b || &usage("No proxy balancer for the path $path was found");

# Delete it
$err = &delete_proxy_balancer($d, $b);
&release_lock_web($d);
if ($err) {
	print "Failed to delete balancer : $err\n";
	exit(1);
	}
else {
	&set_all_null_print();
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	print "Proxy balancer for $path deleted successfully\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes a proxy balancer from a virtual server's website.\n";
print "\n";
print "virtualmin delete-proxy --domain domain.name\n";
print "                        --path url-path\n";
exit(1);
}

