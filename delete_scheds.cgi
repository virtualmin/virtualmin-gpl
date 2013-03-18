#!/usr/local/bin/perl
# Delete several scheduled backups

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'dsched_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'dsched_enone'});

# Get the backups to operate on
@allscheds = &list_scheduled_backups();
foreach $sid (@d) {
	($sched) = grep { $_->{'id'} eq $sid } @allscheds;
	$sched || &error(&text('dsched_egone', $sid));
	&can_backup_sched($sched) ||
		&error(&text('dsched_ecannot', $sid));
	push(@scheds, $sched);
	}

if ($in{'disable'}) {
	# Disable selected
	foreach $sched (@scheds) {
		if ($sched->{'enabled'}) {
			$sched->{'enabled'} = 0;
			&save_scheduled_backup($sched);
			}
		}
	}
elsif ($in{'enable'}) {
	foreach $sched (@scheds) {
		if (!$sched->{'enabled'}) {
			$sched->{'enabled'} = 1;
			&save_scheduled_backup($sched);
			}
		}
	}
elsif ($in{'delete'}) {
	# Do the deletion
	foreach $sched (@scheds) {
		&delete_scheduled_backup($sched);
		}
	&run_post_actions_silently();
	&webmin_log("delete", "scheds", scalar(@d));
	}
else {
	&error("No button clicked");
	}

&redirect("list_sched.cgi");

