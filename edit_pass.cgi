#!/usr/local/bin/perl
# Show a form for changing a domain's password

require './virtual-server-lib.pl';
&ReadParse();
if ($in{'dom'}) {
	$in{'dom'} || &error($text{'pass_ecannot2'});
	$d = &get_domain($in{'dom'});
	&can_passwd() && &can_edit_domain($d) || &error($text{'pass_ecannot'});
	}
elsif (!&reseller_admin() && !&extra_admin()) {
	&error($text{'pass_ecannot2'});
	}

&ui_print_header($d ? &domain_in($d) : undef, $text{'pass_title'}, "");

print &ui_form_start("save_pass.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($d ? $text{'pass_header1'} : $text{'pass_header2'},
		      undef, 2);

print &ui_table_row($text{'pass_new1'},
		    &ui_password("new1", undef, 20));
print &ui_table_row($text{'pass_new2'},
		    &ui_password("new2", undef, 20));

if ($d && $d->{'hashpass'} && &master_admin()) {
	print &ui_table_row($text{'pass_hashpass'},
			    &ui_yesno_radio("hashpass", 1));
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'pass_ok'} ] ]);

if ($d) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

