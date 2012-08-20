#!/usr/local/bin/perl

=head1 download-rs-file.pl

Downloads a single file from a Rackspace container.

This command downloads a file to your Virtualmin system from Rackspace's Cloud
Files service. The login and API key for Rackspace must be set using the
C<--user> and C<--key> flags, unless defaults have been set in
the Virtualmin configuration.

The C<--container> flag must be given to specify the container the file is
stored in, the C<--dest> flag to choose the file to file, and the C<--file>
flag to set the source filename.

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
	$0 = "$pwd/download-rs-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "download-rs-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$tries = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--container") {
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
$dest || &usage("Missing --dest parameter");
$file || &usage("Missing --file parameter");
$container || &usage("Missing --container parameter");
if (-d $dest) {
	$dest = $dest."/".$file;
	}

# Try the upload
$h = &rs_connect($config{'rs_endpoint'}, $user, $key);
if (!ref($h)) {
	print "ERROR: $h\n";
	exit(1);
	}
$err = &rs_download_object($h, $container, $file, $dest);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($dest);
	print "OK: Downloaded $container/$file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Uploads a single file to a Rackspace container.\n";
print "\n";
print "virtualmin upload-download-file [--user name]\n";
print "                                [--key key]\n";
print "                                 --dest local-file\n";
print "                                 --container name\n";
print "                                 --file remote-file\n";
exit(1);
}
