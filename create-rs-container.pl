#!/usr/local/bin/perl

=head1 create-rs-container.pl

Creates a new empty Rackspace container.

This command creates a new container (directory) on Rackspace's Cloud Files
service. The login and API key for Rackspace must be set using the C<--user>
and C<--key> flags, unless defaults have been set in the Virtualmin
configuration.

The C<--container> flag must be given to specify the name of the container to
create.

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
	$0 = "$pwd/create-rs-container.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-rs-container.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$tries = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--container") {
		$container = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$user ||= $config{'rs_user'};
$key ||= $config{'rs_key'};
$user || &usage("Missing --user parameter");
$key || &usage("Missing --key parameter");
$container || &usage("Missing --container parameter");

# Create the container
$h = &rs_connect($config{'rs_endpoint'}, $user, $key);
if (!ref($h)) {
	print "ERROR: $h\n";
	exit(1);
	}
$err = &rs_create_container($h, $container);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	print "OK: Created $container\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Creates a new empty Rackspace container.\n";
print "\n";
print "virtualmin create-rs-container [--user name]\n";
print "                               [--key key]\n";
print "                                --container name\n";
exit(1);
}
