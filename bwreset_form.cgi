#!/usr/local/bin/perl
# Show a form for re-generating bandwidth stats

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newbw_ecannot'});
&ui_print_header(undef, $text{'bwreset_title'}, "");

print $text{'bwreset_desc'},"<p>\n";
print $text{'bwreset_desc2'},"<p>\n";
print $text{'bwreset_desc3'},"<p>\n";

print &ui_form_start("bwreset.cgi", "post");
print &ui_table_start($text{'bwreset_header'}, undef, 2);

# When to reset from
@tm = localtime(time());
print &ui_table_row($text{'bwreset_date'},
		&ui_textbox("date_d", $tm[3], 2)."/".
		&ui_select("date_m", $tm[4],
		   [ map { [ $_, $text{"smonth_".($_+1)} ] } (0..11) ])."/".
		&ui_textbox("date_y", $tm[5]+1900, 4)." ".
		&date_chooser_button("date_d", "date_m", "date_y"));

# Features to reset
foreach $f (@features) {
	$afunc = "bandwidth_all_$f";
	$bwfunc = "bandwidth_$f";
	if (defined(&$afunc) || defined(&$bwfunc)) {
		push(@cbs, &ui_checkbox("feature", $f, $text{'feature_'.$f},1));
		}
	}
print &ui_table_row($text{'bwreset_features'},
		    join("<br>\n", @cbs));

# Domains to reset
@doms = &list_domains();
print &ui_table_row($text{'bwreset_domains'},
		    &ui_radio("domains_def", 1,
			      [ [ 1, $text{'bwreset_domains1'} ],
				[ 0, $text{'bwreset_domains0'} ] ])."<br>".
		    &servers_input("domains", [ map { $_->{'id'} } @doms ], \@doms));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'bwreset_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
