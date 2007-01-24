#!/usr/local/bin/perl
# Shows ranges from which IP addresses are allocated

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newrange_ecannot'});
&ui_print_header(undef, $text{'newrange_title'}, "");
@ranges = &get_ip_ranges();

print "$text{'newrange_desc'}<p>\n";
print &ui_form_start("save_newrange.cgi", "post");
print &ui_columns_start([ $text{'newrange_start'},
			  $text{'newrange_end'},
			  $text{'newrange_tot'},
			  $text{'newrange_used'}, ]);
$i = 0;
foreach $r (@ranges, [ ], [ ]) {
	@start = split(/\./, $r->[0]);
	@end = split(/\./, $r->[1]);
	print &ui_columns_row([
		&ui_textbox("start_$i", $r->[0], 15),
		&ui_textbox("end_$i", $r->[1], 15),
		$r->[0] ? $end[3]-$start[3]+1 : undef,
		$r->[0] ? scalar(&get_domain_by_range($r)) : undef,
		]);
	$i++;
	}
print &ui_columns_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

