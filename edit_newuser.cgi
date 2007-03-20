#!/usr/local/bin/perl
# edit_newuser.cgi
# Display the current new mailbox email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newuser_ecannot'});
&ui_print_header(undef, $text{'newuser_title'}, "");

print &ui_form_start("save_newuser.cgi", "form-data");
$file = $config{'user_template'};
$file = "$module_config_directory/user-template"
	if ($file eq "none" || $file eq 'default');

$text{'sub_USER'} = $text{'sub_POP3'};
$text{'sub_HOME'} = $text{'sub_POP3HOME'};
print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print $text{'newuser_desc2'},"<p>\n";
&print_subs_table("MAILBOX", "USER", "PLAINPASS", "DOM", "FTP", "HOME",
		  "QUOTA");
print &ui_hidden_end(),"<p>\n";

print &email_template_input($file,
	    $config{'newuser_subject'} || $text{'mail_usubject'},
	    $config{'newuser_cc'},
	    $config{'newuser_bcc'},
	    $config{'newuser_to_mailbox'},
	    $config{'newuser_to_owner'},
	    $config{'newuser_to_reseller'},
	    $text{'newuser_header'},
	    $config{'user_template'});
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

