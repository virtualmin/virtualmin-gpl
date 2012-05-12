#!/usr/local/bin/perl

=head1 delete-s3-file.pl

Deletes a single file from an S3 bucket.

This command removes a single file from Amazon's S3 service. The login and
password for S3 must be set using the C<--access-key> and C<--secret-key>
flags, unless defaults have been set in the Virtualmin configuration.

The C<--bucket> flag must be given to specify the bucket the file is stored
in, and the C<--file> flag to choose the filename.

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
	$0 = "$pwd/delete-s3-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-s3-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--bucket") {
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
$bucket || &usage("Missing --bucket parameter");
$file || &usage("Missing --file parameter");

# Try the upload
$err = &s3_delete_file($akey, $skey, $bucket, $file);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	print "OK: Deleted $bucket/$file\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes a single file from an S3 bucket.\n";
print "\n";
print "virtualmin delete-s3-file [--access-key key]\n";
print "                          [--secret-key key]\n";
print "                           --bucket name\n";
print "                           --file remote-file\n";
exit(1);
}
