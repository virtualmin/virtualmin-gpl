#!/usr/local/bin/perl

=head1 create-s3-bucket.pl

Creates a new S3 bucket.

This command adds a bucket to Amazon's S3 service. The login and
password for S3 must be set using the C<--access-key> and C<--secret-key>
flags, unless defaults have been set in the Virtualmin configuration.
The C<--bucket> flag must be given to specify the bucket to created.

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
	$0 = "$pwd/create-s3-bucket.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-s3-bucket.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--bucket") {
		$bucket = shift(@ARGV);
		}
	elsif ($a eq "--location") {
		$location = shift(@ARGV);
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

# Try the upload
$err = &init_s3_bucket($akey, $skey, $bucket, 1, $location);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	print "OK: Created $bucket\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Creates a new S3 bucket.\n";
print "\n";
print "virtualmin create-s3-bucket [--access-key key]\n";
print "                            [--secret-key key]\n";
print "                             --bucket name\n";
exit(1);
}
