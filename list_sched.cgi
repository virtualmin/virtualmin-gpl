#!/usr/local/bin/perl
# Show a list of all scheduled backups
# XXX allow domain owners to use too

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_sched() || &error($text{'sched_ecannot'});
&ui_print_header(undef, $text{'sched_title'}, "");

@scheds = &list_scheduled_backups();
@scheds = grep { &can_backup_sched($_) } @scheds;

# Build table of backups
@table = ( );
foreach $s (@scheds) {
	my @row;
	push(@row, { 'type' => 'checkbox', 'name' => 'd',
	     'value' => $s->{'id'}, 'disabled' => $s->{'id'}==1 });
	push(@row, &nice_backup_url($s->{'dest'}));
	if ($s->{'all'}) {
		push(@row, "<i>$text{'sched_all'}</i>");
		}
	elsif ($s->{'doms'}) {
		local @dnames;
		foreach my $did (split(/\s+/, $s->{'doms'})) {
			local $d = &get_domain($did);
			push(@dnames, &show_domain_name($d)) if ($d);
			}
		if (@dnames > 4) {
			push(@row, join(", ", @dnames).", ...");
			}
		else {
			push(@row, join(", ", @dnames));
			}
		}
	elsif ($s->{'virtualmin'}) {
		push(@row, $text{'sched_virtualmin'});
		}
	else {
		push(@row, $text{'sched_nothing'});
		}
	push(@row, $s->{'enabled'} ?
		&text('sched_yes', &cron::when_text($s)) :
		$text{'no'});
	push(@table, \@row);
	}

# Output the form and table
print &ui_form_columns_table(
	"delete_scheds.cgi",
	[ [ undef, $text{'sched_delete'} ] ],
	1,
	[ [ "backup_form.cgi?new=1", $text{'sched_add'} ] ],
	[ "", $text{'sched_dest'}, $text{'sched_doms'},
	  $text{'sched_enabled'} ],
	100, \@table, [ '', 'string', 'string' ],
	$text{'sched_none'});

&ui_print_footer("", $text{'index_return'});

