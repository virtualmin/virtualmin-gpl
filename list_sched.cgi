#!/usr/local/bin/perl
# Show a list of all scheduled backups
# XXX allow domain owners to use too

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_sched() || &error($text{'sched_ecannot'});
&ui_print_header(undef, $text{'sched_title'}, "");

@scheds = &list_backup_schedules();
@scheds = grep { &can_backup_sched($_) } @scheds;

if (@scheds) {
	# Show in a table
	}
else {
	# None yet
	}

&ui_print_footer("", $text{'index_return'});

