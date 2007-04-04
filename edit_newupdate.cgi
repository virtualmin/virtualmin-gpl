#!/usr/local/bin/perl
# Display the current updated user email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newupdate_ecannot'});
&ui_print_header(undef, $text{'newupdate_title'}, "");

print &ui_form_start("save_newupdate.cgi", "form-data");
$file = $config{'update_template'};
$file = "$module_config_directory/update-template"
	if ($file eq "none" || $file eq 'default');

$text{'sub_USER'} = $text{'sub_POP3'};
$text{'sub_HOME'} = $text{'sub_POP3HOME'};
print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print $text{'newupdate_desc2'},"<p>\n";
&print_subs_table("MAILBOX", "USER", "PLAINPASS", "DOM", "FTP", "HOME",
		  "QUOTA");
print &ui_hidden_end(),"<p>\n";

print &email_template_input($file,
	    $config{'newupdate_subject'} || $text{'mail_upsubject'},
	    $config{'newupdate_cc'},
	    $config{'newupdate_bcc'},
	    $config{'newupdate_to_mailbox'},
	    $config{'newupdate_to_owner'},
	    $config{'newupdate_to_reseller'},
	    $text{'newupdate_header'},
	    $config{'update_template'});
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

