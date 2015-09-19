#!/usr/local/bin/perl
# Show a form for searching mail logs, and the results

require './virtual-server-lib.pl';
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

print $text{'maillog_desc'},"<p>\n";
$ok = &procmail_log_status();
if ($ok == 0) {
	print "<b>$text{'maillog_ok0'}</b><p>\n";
	}
elsif ($ok == 1) {
	print "<b>$text{'maillog_ok1'}</b><p>\n";
	}

# Show the search form
print &ui_form_start("maillog.cgi");
print &ui_table_start($text{'maillog_header'}, undef, 4);

# Start and end dates
if (!defined($in{'start_d'})) {
	# Default to today
	@tm = localtime(time());
	$in{'start_d'} = $tm[3];
	$in{'start_m'} = $tm[4];
	$in{'start_y'} = $tm[5]+1900;
	}
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

# Spam and virus flags
print &ui_table_row($text{'maillog_bad'},
	&ui_checkbox('spam', 1, $text{'maillog_showspam'}, $in{'spam'})."\n".
	&ui_checkbox('virus', 1, $text{'maillog_showvirus'}, $in{'virus'}), 3);

print &ui_table_end();
print &ui_form_end([ [ "search", $text{'maillog_search'} ] ]);

if ($in{'search'}) {
	# Parse criteria
	$start = &parse_time("start", 0);
	$end = &parse_time("end", 1);
	$source = $in{'source'};
	$dest = $in{'user'};
	$dest .= "\@".$d->{'dom'} if ($in{'dom'});

	# Get matching results
	@logs = &parse_procmail_log($start, $end, $source, $dest,
				    undef, $ok == 1);
	@logs = grep { ($in{'spam'} || !$_->{'spam'}) &&
		       ($in{'virus'} || !$_->{'virus'}) } @logs;

	# Show them
	if (@logs) {
		print "<b>",&text('maillog_results', scalar(@logs)),
		      "</b><br>\n";
		}
	@table = ( );
	foreach $l (@logs) {
		@tm = localtime($l->{'time'});
		$dest = &maillog_destination($l);
		$link = "view_maillog.cgi?cid=$l->{'cid'}";
		push(@table, [
			"<a href='$link'>".
				strftime("%Y-%m-%d", @tm)."</a>",
			"<a href='$link'>".
				strftime("%H:%M:%S", @tm)."</a>",
			$l->{'from'},
			$l->{'to'},
			$l->{'user'},
			$dest
			]);
		}

	# Print the table
	print &ui_columns_table(
		[ $text{'maillog_date'}, $text{'maillog_time'},
		  $text{'maillog_from'}, $text{'maillog_to'},
		  $text{'maillog_user'}, $text{'maillog_action'}, ],
		100,
		\@table,
		undef,
		0,
		undef,
		$text{'maillog_none'},
		);
	}

&ui_print_footer($d ? ( &domain_footer_link($d) ) : ( ),
		 "", $text{'index_return'});

# parse_time(name, end-day)
sub parse_time
{
local ($name, $end) = @_;
local $d = $in{$name."_d"};
local $m = $in{$name."_m"};
local $y = $in{$name."_y"};
return 0 if (!$d && !$y);
local $rv;
eval { $rv = $end ? timelocal(59, 59, 23, $d, $m, $y-1900)
		  : timelocal(0, 0, 0, $d, $m, $y-1900) };
&error($text{'maillog_etime'}) if ($@);
return $rv;
}
