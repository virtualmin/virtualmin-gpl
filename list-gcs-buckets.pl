#!/usr/local/bin/perl

=head1 list-gcs-buckets.pl

Lists all buckets owned by the Google Cloud Storage.

This command lists all buckets under the cloud storage account currently
configured for use by Virtualmin. However, you can select a specific bucket
to show with the C<--bucket> flag.

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
	$0 = "$pwd/list-gcs-buckets.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-gcs-buckets.pl must be run as root";
	}
$state = &cloud_google_get_state();
$state->{'ok'} || &usage("Google Cloud Storage has not been configured yet");

# Parse command-line args
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
	else {
		&usage("Unknown parameter $a");
		}
	}

# Login and list the buckets
$files = &list_gcs_buckets();
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($bucket) {
	@$files = grep { $_ eq $bucket } @$files;
	}
if ($multi) {
	# Full details
	foreach $st (@$files) {
		print $st->{'name'},"\n";
		print "    Created: ",
		      &make_date(&google_timestamp($st->{'timeCreated'})),"\n";
		print "    Location: ",
		      $st->{'location'},"\n";
		print "    Storage class: ",
		      $st->{'storageClass'},"\n";
		}
	}
elsif ($nameonly) {
	# Container names only
	foreach $f (@$files) {
                print $f->{'name'},"\n";
		}
	}
else {
	# Summary
	$fmt = "%-30.30s %-30.30s %-15.15s\n";
	printf $fmt, "Bucket name", "Created", "Location";
	printf $fmt, ("-" x 30), ("-" x 30), ("-" x 15);
	foreach $st (@$files) {
		printf $fmt, $st->{'name'},
		     &make_date(&google_timestamp($st->{'timeCreated'})),
		     $st->{'location'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all buckets owned by the Google Cloud Storage account.\n";
print "\n";
print "virtualmin list-gcs-buckets [--multiline | --name-only]\n";
print "                            [--bucket name]\n";
exit(1);
}
