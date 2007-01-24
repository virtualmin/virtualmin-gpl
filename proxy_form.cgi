#!/usr/local/bin/perl
# Display proxying settings

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() || &error($text{'edit_ecannot'});
&ui_print_header(&domain_in($d), $text{'proxy_title'}, "");

print &text('proxy_desc'),"<p>\n";

print &ui_form_start("save_proxy.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'proxy_header'}, "width=100%", 2);

print &ui_table_row($text{'proxy_enabled'},
    &ui_yesno_radio("enabled", $d->{'proxy_pass_mode'} ? 1 : 0));

print &ui_table_row($text{'proxy_url'},
    &ui_textbox("url", $d->{'proxy_pass'}, 40));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'frame_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});

