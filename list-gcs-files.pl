#!/usr/local/bin/perl

=head1 list-gcs-files.pl

Lists all files in a Google Cloud Storage bucket.

This command lists all files in a bucket under the cloud storage account
currently configured for use by Virtualmin, specified by the C<--bucket> flag.

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
	$0 = "$pwd/list-gcs-files.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-gcs-files.pl must be run as root";
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
$files = &list_gcs_files($bucket);
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($multi) {
	# Full details
	foreach $st (@$files) {
		print $st->{'name'},"\n";
		print "    Last modified: ",
		      &make_date(&google_timestamp($st->{'updated'})),"\n";
		print "    Size: ",$st->{'size'},"\n";
		print "    Type: ",$st->{'contentType'},"\n";
		print "    Storage class: ",$st->{'storageClass'},"\n";
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
	$fmt = "%-40.40s %-20.20s %-15.15s\n";
	printf $fmt, "File name", "Modified", "Size";
	printf $fmt, ("-" x 40), ("-" x 20), ("-" x 15);
	foreach $st (@$files) {
		printf $fmt, $st->{'name'},
		     &make_date(&google_timestamp($st->{'updated'})),
		     &nice_size($st->{'size'});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all files in a Google Cloud Storage bucket.\n";
print "\n";
print "virtualmin list-gcs-files [--multiline | --name-only]\n";
print "                           --bucket name\n";
exit(1);
}
