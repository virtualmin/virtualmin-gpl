#!/usr/local/bin/perl

=head1 download-dropbox-file.pl

Downloads a single file from a Dropbox.

This command downloads a single file from Dropbox to your Virtualmin
system, specified by the C<--file> flag. The destination it will be
written to locally is set with the C<--dest> flag.

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
	$0 = "$pwd/download-dropbox-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "download-dropbox-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--file") {
		$file = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$dest || &usage("Missing --dest parameter");
$file || &usage("Missing --file parameter");
if (-d $dest) {
	($base = $file) =~ s/^.*\///;
	$dest = $dest."/".$base;
	}

# Try the download
$file =~ /^\/?(.*)\/([^\/]+)$/ || &usage("Invalid file path");
$err = &download_dropbox_file($1, $2, $dest);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($dest);
	print "OK: Downloaded $file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Downloads a single file from a Dropbox.\n";
print "\n";
print "virtualmin download-dropbox-file --file source-path\n";
print "                                 --dest local-path\n";
exit(1);
}
