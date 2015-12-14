#!/usr/local/bin/perl
# Show a form for emailing virtual server owners

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
&ui_print_header(&domain_in($d), $text{'mailusers_title'}, "");
&foreign_require("mailboxes");

print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
$text{'sub_USER'} = $text{'sub_POP3'};
$text{'sub_HOME'} = $text{'sub_POP3HOME'};
print "$text{'mailusers_desc'}<p>\n";
&print_subs_table("MAILBOX", "USER", "PLAINPASS", "DOM", "HOME", "QUOTA");
print &ui_hidden_end(),"<p>\n";

print &ui_form_start("mailusers.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'mailusers_header'}, undef, 2);

# Users to email
@users = grep { $_->{'email'} || $_->{'user'} eq $d->{'user'} }
	      &list_domain_users($d, 0, 0, 1, 1);
print &ui_table_row($text{'mailusers_to'},
		    &ui_radio("to_def", 1,
			[ [ 1, $text{'mailusers_all'} ],
			  [ 0, $text{'mailusers_sel'} ] ])."<br>\n".
		    &ui_select("to", undef,
			[ map { [ $_->{'user'},
				  &remove_userdom($_->{'user'}, $d) ] } @users ],
			5, 1));

# Message subject
print &ui_table_row($text{'newnotify_subject'},
		    &ui_textbox("subject", undef, 50));

# Message sender
print &ui_table_row($text{'newnotify_from'},
		    &ui_textbox("from", $d->{'emailto_addr'}, 50));

# Message body
print &ui_table_row($text{'newnotify_body'},
		    &ui_textarea("body", undef, 10, 60));

# Attachment
print &ui_table_row($text{'newnotify_attach'},
		    &ui_upload("attach"));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newnotify_ok'} ] ]);

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return'});
