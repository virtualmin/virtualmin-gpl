#!/usr/local/bin/perl
# Show a form for searching mail logs, and the results

require './virtual-server-lib.pl';
use POSIX;
&ReadParse();
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_view_maillog($d) || &error($text{'maillog_ecannot'});
	}
else {
	&can_view_maillog() || &error($text{'maillog_ecannot2'});
	}

&ui_print_header($d ? &domain_in($d) : undef,
		 $text{'maillog_title'}, "", "maillog");

# Show the search form
print $text{'maillog_desc'},"<p>\n";
print &ui_form_start("maillog.cgi");
print &ui_table_start($text{'maillog_header'}, undef, 4);

# Start and end dates
foreach $t ("start", "end") {
	print &ui_table_row($text{'maillog_'.$t},
		&ui_textbox($t."_d", $in{$t."_d"}, 2)."/".
		&ui_select($t."_m", $in{$t."_m"},
		   [ map { [ $_, $text{"smonth_".($_+1)} ] } (0..11) ])."/".
		&ui_textbox($t."_y", $in{$t."_y"}, 4)." ".
		&date_chooser_button($t."_d", $t."_m", $t."_y"));
	}

# Source and dest
print &ui_table_row($text{'maillog_source'},
	&ui_textbox("source", $in{'source'}, 30));

@doms = sort { $a->{'dom'} cmp $b->{'dom'} }
	     grep { &can_view_maillog($_) } &list_domains();
print &ui_table_row($text{'maillog_dest'},
	&ui_textbox('user', $in{'user'}, 10)."\@".
	&ui_select('dom', $in{'dom'},
	   [ &can_view_maillog() ? ( [ "", $text{'maillog_any'} ] ) : ( ),
	     map { [ $_->{'id'}, $_->{'dom'} ] } @doms ]));

print &ui_table_end();
print &ui_form_end([ [ "search", $text{'maillog_search'} ] ]);

if ($in{'search'}) {
	# Parse criteria
	$start = &parse_time("start");
	$end = &parse_time("end");
	$source = $in{'source'};
	$dest = $in{'user'};
	$dest .= "\@".$d->{'dom'} if ($in{'dom'});

	# Get results
	@logs = &parse_procmail_log($start, $end);
	if ($source) {
		@logs = grep { $_->{'from'} =~ /\Q$source\E/i } @logs;
		}
	if ($dest) {
		@logs = grep { $_->{'to'} =~ /\Q$dest\E/i } @logs;
		}

	# Show them
	if (@logs) {
		print "<b>",&text('maillog_results', scalar(@logs)),
		      "</b><br>\n";
		print &ui_columns_start([
			$text{'maillog_date'},
			$text{'maillog_time'},
			$text{'maillog_from'},
			$text{'maillog_to'},
			$text{'maillog_user'},
			$text{'maillog_action'},
			]);
		foreach $l (@logs) {
			@tm = localtime($l->{'time'});
			if ($l->{'auto'}) {
				$dest = $text{'maillog_auto'};
				}
			elsif ($l->{'forward'}) {
				$dest = &text('maillog_forward',
					      "<tt>$l->{'forward'}</tt>");
				}
			elsif ($l->{'throw'}) {
				$dest = $text{'maillog_throw'};
				}
			elsif ($l->{'inbox'}) {
				$dest = $text{'maillog_inbox'};
				}
			elsif ($l->{'file'}) {
				$dest = "<tt>$l->{'file'}</tt>";
				}
			elsif ($l->{'bounce'}) {
				$dest = &text('maillog_bounce',
					      "<i>$l->{'bounce'}</i>");
				}
			elsif ($l->{'program'}) {
				$dest = &text('maillog_program',
					      "<tt>$l->{'program'}</tt>");
				}
			elsif ($l->{'local'}) {
				$dest = &text('maillog_local',
					      "<tt>$l->{'local'}</tt>");
				}
			else {
				$dest = $text{'maillog_unknown'};
				}
			print &ui_columns_row([
				strftime("%Y-%m-%d", @tm),
				strftime("%H:%M:%S", @tm),
				$l->{'from'},
				$l->{'to'},
				$l->{'user'},
				$dest
				]);
			}
		print &ui_columns_end();
		}
	else {
		print "<b>$text{'maillog_none'}</b><p>\n";
		}
	}

&ui_print_footer($d ? ( &domain_footer_link($d) ) : ( ),
		 "", $text{'index_return'});
sub parse_time
{
local $d = $in{"$_[0]_d"};
local $m = $in{"$_[0]_m"};
local $y = $in{"$_[0]_y"};
return 0 if (!$d && !$y);
local $rv;
eval { $rv = timelocal(0, 0, 0, $d, $m, $y-1900) };
&error($text{'maillog_etime'}) if ($@);
return $rv;
}
