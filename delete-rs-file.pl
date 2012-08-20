#!/usr/local/bin/perl

=head1 delete-rs-file.pl

Deletes a single file from a Rackspace container.

This command deletes a file from Rackspace's Cloud Files service. The login
and API key for Rackspace must be set using the C<--user> and C<--key> flags,
unless defaults have been set in the Virtualmin configuration.

The C<--container> flag must be given to specify the container the file is
stored in, and the C<--file> flag to determine the name of the file to remove.

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
	$0 = "$pwd/delete-rs-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-rs-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$tries = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--container") {
		$container = shift(@ARGV);
		}
	elsif ($a eq "--file") {
		$file = shift(@ARGV);
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
$file || &usage("Missing --file parameter");

# Delete the file
$h = &rs_connect($config{'rs_endpoint'}, $user, $key);
if (!ref($h)) {
	print "ERROR: $h\n";
	exit(1);
	}
$err = &rs_delete_object($h, $container, $file);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($source);
	print "OK: Deleted $container/$file\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes a single file from a Rackspace container.\n";
print "\n";
print "virtualmin delete-rs-file [--user name]\n";
print "                          [--key key]\n";
print "                           --container name\n";
print "                           --file remote-file\n";
exit(1);
}
