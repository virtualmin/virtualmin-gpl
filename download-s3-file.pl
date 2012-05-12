#!/usr/local/bin/perl

=head1 download-s3-file.pl

Downloads a single file from an S3 bucket.

This command downloads a single file from Amazon's S3 service to your Virtualmin
system. The login and password for S3 must be set using the
C<--access-key> and C<--secret-key> flags, unless defaults have been set in
the Virtualmin configuration.

The C<--bucket> flag must be given to specify the bucket containing the file,
the C<--dest> flag to choose the local file to write, and the C<--file>
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
	$0 = "$pwd/download-s3-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "download-s3-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--bucket") {
		$bucket = shift(@ARGV);
		}
	elsif ($a eq "--file") {
		$file = shift(@ARGV);
		}
	elsif ($a eq "--access-key") {
		$akey = shift(@ARGV);
		}
	elsif ($a eq "--secret-key") {
		$skey = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$akey ||= $config{'s3_akey'};
$skey ||= $config{'s3_skey'};
$akey || &usage("Missing --access-key parameter");
$skey || &usage("Missing --secret-key parameter");
$dest || &usage("Missing --dest parameter");
$file || &usage("Missing --file parameter");
if (-d $dest) {
	$dest = $dest."/".$file;
	}
$bucket || &usage("Missing --bucket parameter");

# Try the download
$err = &s3_download($akey, $skey, $bucket, $file, $dest);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($dest);
	print "OK: Downloaded $bucket/$file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Downloads a single file from an S3 bucket.\n";
print "\n";
print "virtualmin download-s3-file [--access-key key]\n";
print "                            [--secret-key key]\n";
print "                             --dest local-file\n";
print "                             --bucket name\n";
print "                            [--file remote-file]\n";
exit(1);
}
