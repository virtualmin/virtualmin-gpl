#!/usr/local/bin/perl

=head1 list-s3-buckets.pl

Lists all buckets owned by an S3 account.

This command queries Amazon's S3 service for the list of all buckets owned
by an S3 account. The login and password for S3 must be set using the
C<--access-key> and C<--secret-key> flags, unless defaults have been set in
the Virtualmin configuration.

By default output is in a human-readable table format, but you can switch to
a more parsable output format with the C<--multiline> flag. Or to just get a
list of filenames, use the C<--name-only> flag.

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
	$0 = "$pwd/list-s3-buckets.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-s3-buckets.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--access-key") {
		$akey = shift(@ARGV);
		}
	elsif ($a eq "--secret-key") {
		$skey = shift(@ARGV);
		}
	elsif ($a eq "--bucket") {
		$bucket = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
($akey, $skey, $iam) = &lookup_s3_credentials($akey, $skey);
$iam || $akey || &usage("Missing --access-key parameter");
$iam || $skey || &usage("Missing --secret-key parameter");

# List the directory
$files = &s3_list_buckets($akey, $skey);
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($bucket) {
	@$files = grep { $_->{'Name'} eq $bucket } @$files;
	}
if ($multiline) {
	# Full details
	foreach $f (@$files) {
		print $f->{'Name'},"\n";
		local $ctime = &s3_parse_date($f->{'CreationDate'});
		print "    Created: ",&make_date($ctime),"\n";
		print "    Created time: ",$ctime,"\n";
		$info = &s3_get_bucket($akey, $skey, $f->{'Name'});
		if ($info && $info->{'location'}) {
			print "    Location: $info->{'location'}\n";
			}
		if ($info && $info->{'acl'}) {
			print "    Owner: ",
			      ($info->{'acl'}->{'Owner'}->[0]->{'DisplayName'}->[0] || $info->{'acl'}->{'Owner'}->[0]->{'ID'}->[0]),"\n";
			$acl = $info->{'acl'}->{'AccessControlList'}->[0];
			@grant = @{$acl->{'Grant'}};
			foreach my $g (@grant) {
				print "    Grant: $g->{'Permission'}->[0] to ",
				      ($g->{'Grantee'}->[0]->{'DisplayName'}->[0] || $g->{'Grantee'}->[0]->{'ID'}->[0]),"\n";
				}
			}
		if ($info && $info->{'lifecycle'}) {
			foreach my $r (@{$info->{'lifecycle'}->{'Rule'}}) {
				print "    Lifecycle ID: ",
				      $r->{'ID'}->[0],"\n";
				print "    Lifecycle status: ",
				      $r->{'Status'}->[0],"\n";
				print "    Lifecycle prefix: ",
				      $r->{'Prefix'}->[0],"\n";
				&show_lifecycle_period($r, "Transition",
					"move to glacier");
				&show_lifecycle_period($r, "Expiration",
					"delete");
				}
			}
		}
	}
elsif ($nameonly) {
	# Bucket names only
	foreach $f (@$files) {
                print $f->{'Name'},"\n";
		}
	}
else {
	# Summary
	$fmt = "%-45.45s %-30.30s\n";
	printf $fmt, "Bucket name", "Created";
	printf $fmt, ("-" x 45), ("-" x 30);
	foreach $f (@$files) {
		local $ctime = &s3_parse_date($f->{'CreationDate'});
		printf $fmt, $f->{'Name'}, &make_date($ctime);
		}
	}

sub show_lifecycle_period
{
local ($r, $name, $txt) = @_;
if ($r->{$name} && $r->{$name}->[0]) {
	my $obj = $r->{$name}->[0];
	if ($obj->{'Date'} && $obj->{'Date'}->[0]) {
		print "    Lifecycle ${txt}: On date $obj->{'Date'}->[0]\n";
		}
	if ($obj->{'Days'} && $obj->{'Days'}->[0]) {
		print "    Lifecycle ${txt}: After $obj->{'Days'}->[0] days\n";
		}
	}
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all buckets owned by an S3 account.\n";
print "\n";
print "virtualmin list-s3-buckets [--multiline | --json | --xml | --name-only]\n";
print "                           [--bucket name]\n";
print "                           [--access-key key]\n";
print "                           [--secret-key key]\n";
exit(1);
}
