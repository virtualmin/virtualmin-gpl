#!/usr/local/bin/perl
# Delete several scheduled backups

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'dsched_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'dsched_enone'});

# Do the deletion
@scheds = &list_scheduled_backups();
foreach $sid (@d) {
	($sched) = grep { $_->{'id'} eq $sid } @scheds;
	$sched || &error(&text('dsched_egone', $sid));
	&can_backup_sched($sched) || &error(&text('dsched_ecannot', $sid));
	&delete_scheduled_backup($sched);
	}

&run_post_actions_silently();
&webmin_log("delete", "scheds", scalar(@d));
&redirect("list_sched.cgi");

