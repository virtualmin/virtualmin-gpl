#!/usr/local/bin/perl
# edit_newlocal.cgi
# Display the current new local user email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newlocal_ecannot'});
&ui_print_header(undef, $text{'newlocal_title'}, "");

print &ui_form_start("save_newlocal.cgi", "form-data");
$file = $config{'local_template'};
$file = "$module_config_directory/local-template"
	if ($file eq "none" || $file eq "default");

$text{'sub_USER'} = $text{'sub_MAILBOX'};
$text{'sub_HOME'} = $text{'sub_LOCALHOME'};
print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print $text{'newlocal_desc2'},"<p>\n";
&print_subs_table("USER", "FTP", "HOME");
print &ui_hidden_end(),"<p>\n";

print &email_template_input($file,
	    $config{'newlocal_subject'} || $text{'mail_usubject'},
	    $config{'newlocal_cc'},
	    $config{'newlocal_bcc'},
	    undef,
	    undef,
	    undef,
	    $text{'newlocal_header'},
	    $config{'local_template'});
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

