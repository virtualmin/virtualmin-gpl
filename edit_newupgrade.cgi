#!/usr/local/bin/perl
# Show a page for upgrading from the GPL version to Pro

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'upgrade_ecannot'});
&ui_print_header(undef, $text{'upgrade_title'}, "");

print $text{'upgrade_desc1'},"<br>\n";
print "<ol>\n";
print "<li>",&text('upgrade_step1', $config{'serials_link'} ||
				    "http://www.virtualmin.com/catalog");
print "<li>",&text('upgrade_step2');
print "<li>",&text('upgrade_step3');
print "</ol>\n";

print &ui_form_start("upgrade.cgi", "post");
print &ui_table_start($text{'upgrade_header'}, undef, 4);

print &ui_table_row($text{'upgrade_serial'},
		    &ui_textbox("serial", undef, 30));

print &ui_table_row($text{'upgrade_key'},
		    &ui_textbox("key", undef, 30));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'upgrade_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});

