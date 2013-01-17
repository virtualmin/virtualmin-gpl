#!/usr/local/bin/perl
# Show a form for emailing virtual server owners

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newnotify_ecannot'});
&ui_print_header(undef, $text{'newnotify_title'}, "");
&foreign_require("mailboxes", "mailboxes-lib.pl");

print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print "$text{'newnotify_desc'}<p>\n";
&print_subs_table("USER", "DOM", "HOME", "QUOTA");
print &ui_hidden_end(),"<p>\n";

print &ui_form_start("notify.cgi", "form-data");
print &ui_table_start($text{'newnotify_header'}, undef, 2);

# Servers to email
@doms = grep { $_->{'emailto'} } &list_domains();
print &ui_table_row($text{'newnotify_servers'},
		    &ui_radio("servers_def", 1,
			[ [ 1, $text{'newips_all'} ],
			  [ 0, $text{'newips_sel'} ] ])."<br>\n".
		    &servers_input("servers", [ ], \@doms).
		    "<br>".
		    &ui_checkbox("admins", 1, $text{'newnotify_admins'}, 1).
		    "<br>".
		    &ui_checkbox("users", 1, $text{'newnotify_users'}, 0).
		    "<br>".
		    &ui_checkbox("nomany", 1, $text{'newnotify_nomany'}, 1));

# Message subject
print &ui_table_row($text{'newnotify_subject'},
		    &ui_textbox("subject", undef, 50));

# Message sender
print &ui_table_row($text{'newnotify_from'},
		    &ui_textbox("from", &get_global_from_address(), 50));

# Message body
print &ui_table_row($text{'newnotify_body'},
		    &ui_textarea("body", undef, 10, 60));

# Attachment
print &ui_table_row($text{'newnotify_attach'},
		    &ui_upload("attach"));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newnotify_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
