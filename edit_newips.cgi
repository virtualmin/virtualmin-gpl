#!/usr/local/bin/perl
# Show a form for changing the IP addresses of multiple servers

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newips_ecannot'});
&ui_print_header(undef, $text{'newips_title'}, "", "newips");

@v6doms = grep { $_->{'ip6'} } &list_domains();
$anyv6 = &supports_ip6() && @v6doms;

print "$text{'newips_desc'}<p>\n";
print &ui_form_start("save_newips.cgi", "post");
print &ui_hidden("setold", $in{'setold'});
print &ui_table_start($text{'newips_header'}, undef, 2);

# Changing real or external IP?
print &ui_table_row(&hlink($text{'newips_mode'}, "newips_mode"),
		    &ui_radio("mode", 0, [ [ 0, $text{'newips_mode0'} ],
					   [ 1, $text{'newips_mode1'} ] ]));

# Old IPv4 address
print &ui_table_row(&hlink($text{'newips_old'}, "newips_old"),
		    &ui_textbox("old", $in{'old'} || &get_default_ip(), 20));

# New IPv4 address
print &ui_table_row(&hlink($text{'newips_new'}, "newips_new"),
		    $anyv6 ? &ui_opt_textbox("new", $in{'new'}, 20,
				   	     $text{'newips_leave'})
			   : &ui_textbox("new", $in{'new'}, 20));

if ($anyv6 && ($in{'old6'} || &get_default_ip6())) {
	# Old IPv6 address
	print &ui_table_row(&hlink($text{'newips_old6'}, "newips_old6"),
		    &ui_textbox("old6", $in{'old6'} || &get_default_ip6(), 40));

	# New IPv6 address
	print &ui_table_row(&hlink($text{'newips_new6'}, "newips_new6"),
		    &ui_opt_textbox("new6", $in{'new6'}, 40,
				    $text{'newips_leave'}));
	}

# Virtual servers to update
@doms = grep { !$_->{'virt'} && !$_->{'alias'} } &list_domains();
print &ui_table_row(&hlink($text{'newips_servers'}, "newips_servers_def"),
		    &ui_radio("servers_def", 1,
			[ [ 1, $text{'newips_all'} ],
			  [ 0, $text{'newips_sel'} ] ])."<br>\n".
		    &servers_input("servers", [ ], \@doms));

# Other global settings to update
print &ui_table_row($text{'newips_also'},
	&ui_checkbox("masterip", 1, $text{'newips_masterip'}, $in{'also'}));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newips_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
