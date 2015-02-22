#!/usr/local/bin/perl

=head1 list-dropbox-files.pl

Lists all files under a Dropbox path.

This command lists all files under a path owner by the cloud storage account
currently configured for use by Virtualmin, specified by the C<--path> flag.

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
$state = &cloud_dropbox_get_state();
$state->{'ok'} || &usage("Dropbox has not been configured yet");

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$path ||= "/";

# Login and list the buckets
$path =~ s/^\///;
$files = &list_dropbox_files($path);
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($multi) {
	# Full details
	foreach $f (@$files) {
		$name = $f->{'path'};
		$name =~ s/^\Q$path\E\/?//;
		print $name,"\n";
		print "    Last modified: ",
		      &make_date(&dropbox_timestamp($f->{'modified'})),"\n";
		print "    Size: ",$f->{'bytes'},"\n";
		print "    Type: ",($f->{'is_dir'} ? "Directory" :
					$f->{'mime_type'}),"\n";
		print "    Full path: ",$f->{'path'},"\n";
		}
	}
elsif ($nameonly) {
	# Container names only
	foreach $f (@$files) {
		$name = $f->{'path'};
		$name =~ s/^\Q$path\E\/?//;
		$name .= "/" if ($f->{'is_dir'});
                print $name,"\n";
		}
	}
else {
	# Summary
	$fmt = "%-40.40s %-4.4s %-20.20s %-10.10s\n";
	printf $fmt, "File name", "Type", "Modified", "Size";
	printf $fmt, ("-" x 40), ("-" x 4), ("-" x 20), ("-" x 10);
	foreach $f (@$files) {
		$name = $f->{'path'};
                $name =~ s/^\Q$path\E\/?//;
		printf $fmt, $name,
		     $f->{'is_dir'} ? "Dir" : "File",
		     &make_date(&dropbox_timestamp($f->{'modified'})),
		     &nice_size($f->{'bytes'});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all files under a Dropbox path.\n";
print "\n";
print "virtualmin list-dropbox-files [--multiline | --name-only]\n";
print "                              [--path dir]\n";
exit(1);
}
