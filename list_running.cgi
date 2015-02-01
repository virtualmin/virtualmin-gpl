#!/usr/local/bin/perl
# Show a list of all running backups

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_sched() || &error($text{'sched_ecannot'});
&can_backup_domain() || &error($text{'backup_ecannot'});
&ui_print_header(undef, $text{'running_title'}, "");

@scheds = &list_running_backups();
@scheds = grep { &can_backup_sched($_) } @scheds;

# Work out what to show
@table = ( );
$hasowner = 0;
if (&can_backup_domain() == 1) {
	# For master admin, show it if any schedule has a non-master owner
	($hasowner) = grep { $_->{'owner'} } @scheds;
	}
elsif (&can_backup_domain() == 3) {
	# For resellers, always show owner column
	$hasowner = 1;
	}

# Build table of backups
foreach $s (@scheds) {
	my @row;
	push(@row, { 'type' => 'checkbox', 'name' => 'd',
	     'value' => $s->{'id'}, 'disabled' => $s->{'id'}==1 });
	@dests = &get_scheduled_backup_dests($s);
	@nices = map { &nice_backup_url($_, 1) } @dests;
	push(@row, &ui_link("backup_form.cgi?sched=$s->{'id'}",
			    join("<br>\n", @nices)));
	push(@row, &nice_backup_doms($s));
	push(@row, &make_date($s->{'started'}));
	push(@row, $text{'running_'.$s->{'scripttype'}} || $s->{'scripttype'});
	push(@table, \@row);
	}

# Output the form and table
print &ui_form_columns_table(
	"kill_running.cgi",
	[ [ 'stop', $text{'running_stop'} ] ],
	1,
	[ ],
	undef,
	[ "", $text{'sched_dest'}, $text{'sched_doms'},
	  $text{'running_started'}, $text{'running_mode'},
	],
	100, \@table, [ '', 'string', 'string' ],
	0, undef,
	$text{'running_none'});
if (!@table) {
	print &text('running_link', 'list_sched.cgi', 'backuplog.cgi'),"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});

