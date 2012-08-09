#!/usr/local/bin/perl
# Show a form for changing the IP addresses of multiple servers

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newips_ecannot'});
&ui_print_header(undef, $text{'newips_title'}, "", "newips");

print "$text{'newips_desc'}<p>\n";
print &ui_form_start("save_newips.cgi", "post");
print &ui_hidden("setold", $in{'setold'});
print &ui_table_start($text{'newips_header'}, undef, 2);

print &ui_table_row(&hlink($text{'newips_old'}, "newips_old"),
		    &ui_textbox("old", $in{'old'} || &get_default_ip(), 20));

print &ui_table_row(&hlink($text{'newips_new'}, "newips_new"),
		    &ui_textbox("new", $in{'new'}, 20));

@doms = grep { !$_->{'virt'} && !$_->{'alias'} } &list_domains();
print &ui_table_row(&hlink($text{'newips_servers'}, "newips_servers_def"),
		    &ui_radio("servers_def", 1,
			[ [ 1, $text{'newips_all'} ],
			  [ 0, $text{'newips_sel'} ] ])."<br>\n".
		    &servers_input("servers", [ ], \@doms));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newips_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
