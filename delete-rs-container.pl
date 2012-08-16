#!/usr/local/bin/perl

=head1 delete-rs-container.pl

Deletes an existing Rackspace container.

This command deletes a container (directory) from Rackspace's Cloud Files
service. The login and API key for Rackspace must be set using the C<--user>
and C<--key> flags, unless defaults have been set in the Virtualmin
configuration.

The C<--container> flag must be given to specify the name of the container to
remove. The optional C<--recursive> flag tells the command to delete all files
in the container first.

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
	$0 = "$pwd/delete-rs-container.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-rs-container.pl must be run as root";
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
	elsif ($a eq "--recursive") {
		$recursive = 1;
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
$err = &rs_delete_container($h, $container, $recursive);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	print "OK: Deleted $container\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes an existing Rackspace container.\n";
print "\n";
print "virtualmin delete-rs-container [--user name]\n";
print "                               [--key key]\n";
print "                                --container name\n";
print "                               [--recursive]\n";
exit(1);
}
