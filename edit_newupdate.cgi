#!/usr/local/bin/perl
# Display the current updated user email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newupdate_ecannot'});
&ui_print_header(undef, $text{'newupdate_title'}, "");

print &ui_form_start("save_newupdate.cgi", "form-data");
$file = $config{'update_template'};
$file = "$module_config_directory/update-template"
	if ($file eq "none" || $file eq 'default');

print &text($config{'update_template'} eq "none" ?
	    'newupdate_descdis' : 'newupdate_desc', "<tt>$file</tt>"),"<p>\n";
$text{'sub_USER'} = $text{'sub_POP3'};
$text{'sub_HOME'} = $text{'sub_POP3HOME'};
&print_subs_table("MAILBOX", "USER", "PLAINPASS", "DOM", "FTP", "HOME",
		  "QUOTA");
print &email_template_input($file,
	    $config{'newupdate_subject'} || $text{'mail_upsubject'},
	    $config{'newupdate_cc'},
	    $config{'newupdate_bcc'},
	    $config{'newupdate_to_mailbox'},
	    $config{'newupdate_to_owner'},
	    $config{'newupdate_to_reseller'});
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

