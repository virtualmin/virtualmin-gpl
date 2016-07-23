#!/usr/local/bin/perl

=head1 delete-backup.pl

Delete one previous logged backup.

This command removes a Virtualmin backup, which can be identified either using
the C<--id> flag followed by a backup log ID (from the C<list-backup-logs>
command), or C<--dest> followed by a destination path like
C</backups/foo.com.tar.gz>.

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
	$0 = "$pwd/delete-backup.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-backup.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--id") {
		$id = shift(@ARGV);
		}
	elsif ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$id || $dest || &usage("One of the --id or --dest flags must be given");

# Work out destination from the backup log
if ($id) {
	$log = &get_backup_log($id);
	$log || &usage("No logged backup with ID $id was found");
	$dest = $log->{'dest'};
	}

print "Deleting backup at $dest ..\n";
if ($log) {
	$err = &delete_backup_from_log($log);
	}
else {
	$err = &delete_backup($dest);
	}
if ($log && !$err) {
	$err = &delete_backup_log($log);
	}
&virtualmin_api_log(\@OLDARGV, { 'dest' => $dest, 'id' => $id });
if ($err) {
	print ".. failed : $err\n";
	}
else {
	print ".. backup removed\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Delete one previous logged backup.\n";
print "\n";
print "virtualmin delete-backup [--id backup-id]\n";
print "                         [--dest url]\n";
exit(1);
}
