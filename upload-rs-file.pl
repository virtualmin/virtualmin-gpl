#!/usr/local/bin/perl

=head1 upload-rs-file.pl

Uploads a single file to a Rackspace container.

This command uploads a file from your Virtualmin system to Rackspace's Cloud
Files service. The login and API key for Rackspace must be set using the
C<--user> and C<--key> flags, unless defaults have been set in
the Virtualmin configuration.

The C<--container> flag must be given to specify the container to store the file
in, the C<--source> flag to choose the file to upload, and the C<--file>
flag to set the destination filename.

The optional C<--multipart> flag can be used to force a multi-part upload.
Otherwise only files above 2GB will be uploaded using Rackspace's multi-part
upload protocol.

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
	$0 = "$pwd/upload-rs-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "upload-rs-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$tries = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$source = shift(@ARGV);
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
	elsif ($a eq "--multipart") {
		$multipart = 1;
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
$source || &usage("Missing --source parameter");
-r $source && !-d $source || &usage("Source file $source does not exist");
$container || &usage("Missing --container parameter");
if (!$file) {
	$source =~ /([^\\\/]+)$/;
	$file = $1;
	}

# Try the upload
$h = &rs_connect($config{'rs_endpoint'}, $user, $key);
if (!ref($h)) {
	print "ERROR: $h\n";
	exit(1);
	}
$err = &rs_upload_object($h, $container, $file, $source, $multipart);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($source);
	print "OK: Uploaded $container/$file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Uploads a single file to a Rackspace container.\n";
print "\n";
print "virtualmin upload-rs-file [--user name]\n";
print "                          [--key key]\n";
print "                           --source local-file\n";
print "                           --container name\n";
print "                          [--file remote-file]\n";
print "                          [--multipart]\n";
exit(1);
}
