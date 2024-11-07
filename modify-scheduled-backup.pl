#!/usr/local/bin/perl

=head1 modify-scheduled-backup.pl

Change some attributes of a scheduled backup.

This command can be used to change some attributes of a scheduled backup that
has been created in the Virtualmin UI. The backup must be selected with the
C<--id> flag followed by a unique ID, as shown by the C<list-scheduled-backups>
command.

To stop a backup from running, you can use the C<--disable> flag. Or to
re-enable a backup that's been turned off, use the C<--enable> flag.

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
	$0 = "$pwd/modify-scheduled-backup.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-scheduled-backup.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--id") {
		$schedid = shift(@ARGV);
		}
	elsif ($a eq "--enable") {
		$enabled = 1;
		}
	elsif ($a eq "--disable") {
		$enabled = 0;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$schedid || &usage("Missing backup ID flag");

# Get the backup
@scheds = &list_scheduled_backups();
($sched) = grep { $_->{'id'} eq $schedid } @scheds;
$sched || &usage("No scheduled backup with ID $schedid found");

# Make any changes
if (defined($enabled)) {
	$sched->{'enabled'} = $enabled;
	}

# Save the new schedule
&obtain_lock_cron();
&save_scheduled_backup($sched);
&release_lock_cron();
&run_post_actions_silently();
print "Updated scheduled backup $sched->{'id'}\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Change some attributes of a scheduled backup.\n";
print "\n";
print "virtualmin modify-scheduled-backup --id backup-id\n";
print "                                  [--enable | --disable]\n";
exit(1);
}

