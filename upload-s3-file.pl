#!/usr/local/bin/perl

=head1 upload-s3-file.pl

Uploads a single file to an S3 bucket.

This command uploads a file from your Virtualmin system to Amazon's S3
service. The login and password for S3 must be set using the
C<--access-key> and C<--secret-key> flags, unless defaults have been set in
the Virtualmin configuration.

The C<--bucket> flag must be given to specify the bucket to store the file
in, the C<--source> flag to choose the file to upload, and the C<--file>
flag to set the destination filename. The optional C<--rrs> flag can be used
to tell S3 that the file should be stored with reduced redundancy, which
is cheaper but has a lower reliability SLA.

By default, this command will perform a multi-part S3 upload only for files
above 2GB in size. However, you can force multi-part mode with the
C<--multipart> flag. Amazon requires that files above 5GB in size be multi-part
uploaded.

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
	$0 = "$pwd/upload-s3-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "upload-s3-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$source = shift(@ARGV);
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
	elsif ($a eq "--rrs") {
		$rrs = 1;
		}
	elsif ($a eq "--multipart") {
		$multipart = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$akey ||= $config{'s3_akey'};
$skey ||= $config{'s3_skey'};
$akey || &usage("Missing --access-key parameter");
$skey || &usage("Missing --secret-key parameter");
$source || &usage("Missing --source parameter");
-r $source && !-d $source || &usage("Source file $source does not exist");
$bucket || &usage("Missing --bucket parameter");
if (!$file) {
	$source =~ /([^\\\/]+)$/;
	$file = $1;
	}

# Try the upload
$err = &s3_upload($akey, $skey, $bucket, $source, $file, undef, undef, 1, $rrs,
		  $multipart);
if ($err) {
	print "ERROR: $err\n";
	}
else {
	@st = stat($source);
	print "OK: Uploaded $bucket/$file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Uploads a single file to an S3 bucket.\n";
print "\n";
print "virtualmin upload-s3-file [--access-key key]\n";
print "                          [--secret-key key]\n";
print "                           --source local-file\n";
print "                           --bucket name\n";
print "                          [--file remote-file]\n";
print "                          [--rrs]\n";
print "                          [--multipart]\n";
exit(1);
}
