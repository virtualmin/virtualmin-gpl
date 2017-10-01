#!/usr/local/bin/perl

=head1 upload-dropbox-file.pl

Uploads a single file to Dropbox.

This command uploads a file from your Virtualmin system to Dropbox, specified
using the C<--source> flag. The destination path can be set using the 
C<--file> flag, which must be a full path.

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
	$0 = "$pwd/upload-dropbox-file.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "upload-dropbox-file.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$tries = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$source = shift(@ARGV);
		}
	elsif ($a eq "--file") {
		$file = shift(@ARGV);
		}
	elsif ($a eq "--multipart") {
		$multipart = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$source || &usage("Missing --source parameter");
-r $source && !-d $source || &usage("Source file $source does not exist");
$file || &usage("Missing --file parameter");

# Try the upload
if ($file =~ /^(\/\S+)?\/([^\/]+)$/) {
	$path = $1;
	$file = $2;
	}
else {
	&usage("--file must be followed by an absolute path");
	}
$err = &upload_dropbox_file($path, $file, $source, 1, $multipart);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}
else {
	@st = stat($source);
	print "OK: Uploaded $file size $st[7] bytes\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Uploads a single file to Dropbox.\n";
print "\n";
print "virtualmin upload-dropbox-file --source local-file\n";
print "                               --file remote-file\n";
print "                              [--multipart]\n";
exit(1);
}
