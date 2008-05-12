#!/usr/local/bin/perl
# Display memory and process limits

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_res($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'res_title'}, "", "res");
$rv = &get_domain_resource_limits($d);

print &ui_form_start("save_res.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'res_header'}, undef, 2);
print &show_resource_limit_inputs($rv);
print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

