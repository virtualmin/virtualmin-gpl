#!/usr/local/bin/perl
# Show a form for setting up mail client auto-configuration

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'autoconfig_ecannot'});
&ui_print_header(undef, $text{'newautoconfig_title'}, "", "autoconfig");

print &text('autoconfig_desc', "<tt>/mail/config-v1.1.xml</tt>"),"<p>\n";
print &ui_form_start("save_newautoconfig.cgi", "post");
print &ui_table_start($text{'autoconfig_header'}, undef, 2);

print &ui_table_row($text{'autoconfig_enabled'},
	&ui_yesno_radio("autoconfig", $config{'mail_autoconfig'}));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
