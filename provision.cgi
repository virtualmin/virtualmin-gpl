#!/usr/bin/perl
# Show form to use a provisioning server

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'provision_ecannot'});
&ui_print_header(undef, $text{'provision_title'}, "", "provision");
&ReadParse();

print &ui_form_start("save_provision.cgi");
print &ui_table_start($text{'provision_header'}, undef, 2);

# Central provisioning server
print &ui_table_row($text{'provision_server'},
	&ui_textbox("provision_server", $config{'provision_server'}, 40));

# Login name
print &ui_table_row($text{'provision_user'},
	&ui_textbox("provision_user", $config{'provision_user'}, 40));

# Password
print &ui_table_row($text{'provision_pass'},
	&ui_password("provision_pass", $config{'provision_pass'}, 40));

# Features to use
print &ui_table_row($text{'provision_features'},
	join("<br>\n",
	     map { &ui_checkbox("provision_".$_, 1, $text{'provision_'.$_},
				$config{'provision_'.$_}) }
		 &list_provision_features()));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
