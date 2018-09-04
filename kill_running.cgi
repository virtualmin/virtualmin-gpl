#!/usr/local/bin/perl
# Kill running scheduled backups

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'running_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'running_enone'});

# Get the backups
@running = &list_running_backups();
foreach $sid_pid (@d) {
	($sid, $pid) = split(/-/, $sid_pid);
	($sched) = grep { $_->{'id'} eq $sid &&
			  $_->{'pid'} == $pid } @running;
	$sched && &can_backup_sched($sched) ||
		&error(&text('dsched_ecannot', $sid));
	push(@scheds, $sched);
	}

# Kill them
foreach my $sched (@scheds) {
	&kill_running_backup($sched);
	}

&webmin_log("kill", "scheds", scalar(@scheds));
&redirect("list_running.cgi");
