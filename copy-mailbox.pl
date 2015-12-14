#!/usr/local/bin/perl

=head1 copy-mailbox.pl

Copy mail from one location to another, perhaps converting formats.

The source mail is specified with the C<--source> flag, and the destination
with the C<--dest> parameter. Both must be followed by a full path, which
can end with a / to indicate that it is in Maildir format.

By default email is just coped, but the C<--delete> flag can be given to
have it moved instead.

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
	$0 = "$pwd/copy-mailbox.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-mailbox.pl must be run as root";
	}

# Parse command-line args
$delete = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$src = shift(@ARGV);
		}
	elsif ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--delete") {
		$delete = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$src && $dest || &usage("Missing --source or --dest parameter");

# Get the folders
&foreign_require("mailboxes");
$srcfolder = { 'file' => $src,
	       'type' => 0 };
if ($src =~ /\/$/ || -d $src) {
	$srcfolder->{'file'} =~ s/\/$//;
	$srcfolder->{'type'} = 1;
	}
$destfolder = { 'file' => $dest,
	        'type' => 0 };
if ($dest =~ /\/$/ || -d $dest) {
	$destfolder->{'file'} =~ s/\/$//;
	$destfolder->{'type'} = 1;
	}
-d $srcfolder->{'file'} || -r $srcfolder->{'file'} ||
	&usage("Source folder $srcfolder->{'file'} does not exist");

# Copy mail
$sz = &mailboxes::folder_size($srcfolder);
$count = &mailboxes::mailbox_folder_size($srcfolder);
print $delete ? "Moving" : "Copying";
print " $count messages totalling ",&nice_size($sz)," ...\n";
if ($delete) {
	&mailboxes::mailbox_move_folder($srcfolder, $destfolder);
	}
else {
	&mailboxes::mailbox_copy_folder($srcfolder, $destfolder);
	}

# Fix ownership
@st = stat($srcfolder->{'file'});
&execute_command("chown -R $st[4]:$st[5] ".quotemeta($destfolder->{'file'}));
print "... done\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Copies or moves mail from one file or directory to another.\n";
print "\n";
print "virtualmin copy-mailbox --source file\n";
print "                        --dest file\n";
print "                        [--delete]\n";
exit(1);
}

