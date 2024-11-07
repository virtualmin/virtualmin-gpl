#!/usr/local/bin/perl

=head1 delete-scheduled-backup.pl

Delete a scheduled backup for one or more virtual servers

This command removes the scheduled backup identified with the C<--id> flag,
which must be followed by the backup's unique numeric ID. Or you can select
a backup with C<--dest> followed by a backup destination path.

This only prevents future backups from happening on schedule, and it does not
remove any existing backup files.

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
	$0 = "$pwd/delete-scheduled-backup.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-scheduled-backup.pl must be run as root";
	}
&licence_status();

# Parse command-line args
@OLDARGV = @ARGV;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--id") {
		$id = shift(@ARGV);
		}
	elsif ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the backup to remove
if ($id) {
	($sched) = grep { $_->{'id'} eq $id } &list_scheduled_backups();
	$sched || &usage("No backup with ID $id exists");
	}
elsif ($dest) {
	($sched) = grep { &indexof($dest, &get_scheduled_backup_dests($_)) >= 0 } &list_scheduled_backups();
	$sched || &usage("No backup with destination $dest exists");
	}
else {
	&usage("Missing --id or --dest parameters");
	}
&delete_scheduled_backup($sched);
print "Scheduled backup deleted with ID $sched->{'id'}\n";

&virtualmin_api_log(\@OLDARGV);

sub usage
{
if ($_[0]) {
	print $_[0],"\n\n";
	}
print "Delete a scheduled backup for one or more virtual servers.\n";
print "\n";
print "virtualmin delete-scheduled-backup [--id number]\n";
print "                                   [--dest path]\n";
exit(1);
}

