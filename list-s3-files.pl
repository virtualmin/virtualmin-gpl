#!/usr/local/bin/perl

=head1 list-s3-files.pl

Lists files in one S3 bucket.

This command queries Amazon's S3 service for the list of files in a bucket,
specified using the C<--bucket> flag. The login and password for S3 must be
set using the C<--access-key> and C<--secret-key> flags, unless defaults have
been set in the Virtualmin configuration.

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
	$0 = "$pwd/list-s3-files.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-s3-files.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--bucket") {
		$bucket = shift(@ARGV);
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

# List the directory
$files = &s3_list_files($akey, $skey, $bucket);
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($multi) {
	# Full details
	foreach $f (@$files) {
		print $f->{'Key'},"\n";
		print "    Size: $f->{'Size'}\n";
		if ($f->{'Owner'}) {
			print "    Owner: $f->{'Owner'}->{'DisplayName'}\n";
			}
		print "    Last modified: $f->{'LastModified'}\n";
		print "    Storage class: $f->{'StorageClass'}\n";
		print "    ETag: $f->{'ETag'}\n";
		}
	}
elsif ($nameonly) {
	# Filenames only
	foreach $f (@$files) {
                print $f->{'Key'},"\n";
		}
	}
else {
	# Summary
	$fmt = "%-35.35s %-12.12s %-30.30s\n";
	printf $fmt, "Filename", "Size", "Last modified";
	printf $fmt, ("-" x 35), ("-" x 12), ("-" x 30);
	foreach $f (@$files) {
		printf $fmt, $f->{'Key'}, &nice_size($f->{'Size'}),
			     $f->{'LastModified'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists files in one S3 bucket.\n";
print "\n";
print "virtualmin list-s3-files [--multiline | --name-only]\n";
print "                         [--access-key key]\n";
print "                         [--secret-key key]\n";
print "                         --bucket name\n";
exit(1);
}
