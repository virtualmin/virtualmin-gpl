#!/usr/local/bin/perl
# frame_form.cgi
# Display frame-forwarding settings form

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() || &error($text{'edit_ecannot'});
&ui_print_header(&domain_in($d), $text{'frame_title'}, "");

$ff = &framefwd_file($d);
print &text('frame_desc', "<tt>$ff</tt>"),"<p>\n";

print &ui_form_start("save_frame.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'frame_header'}, "width=100%", 2);

print &ui_table_row($text{'frame_enabled'},
    &ui_yesno_radio("enabled", $d->{'proxy_pass_mode'} ? 1 : 0));

print &ui_table_row($text{'frame_url'},
    &ui_textbox("url", $d->{'proxy_pass'}, 40));

print &ui_table_row($text{'frame_owner'},
    &ui_textbox("title", $d->{'proxy_title'} || $d->{'owner'}, 40));

print &ui_table_row($text{'frame_meta'},
    &ui_textarea("meta", join("\n", split(/\t+/, $d->{'proxy_meta'})), 5, 50));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'frame_ok'} ] ]);

# Show button for 'expert' mode
if ($d->{'proxy_pass_mode'}) {
	print &virtualmin_ui_hr();
	print &ui_buttons_start();

	print &ui_buttons_row("expframe_form.cgi", $text{'edit_expframe'},
			      $text{'edit_expframedesc'},
			      &ui_hidden("dom", $in{'dom'}));
	print &ui_buttons_end();
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});

