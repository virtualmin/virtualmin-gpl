#!/usr/local/bin/perl
# Show a form for searching mail logs, and the results

$0 =~ /^(.*)\/pro\// && chdir($1);
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

&demo_maillog_pro_tip();

# Show the search form
print &ui_form_start('demo', undef, undef, 'data-demo-form  onsubmit="return false;"');
print &ui_table_start($text{'maillog_header'} . " " . $text{'scripts_gpl_pro_tip_demo'}, undef, 4);


# Start and end dates
# Default to today
@tm = localtime(time());
$in{'start_d'} = $tm[3];
$in{'start_m'} = $tm[4];
$in{'start_y'} = $tm[5]+1900;

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
print &ui_form_end();


&ui_print_footer();

