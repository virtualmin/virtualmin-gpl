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

print &text($config{'local_template'} eq "none" ?
	    'newlocal_descdis' : 'newlocal_desc', "<tt>$file</tt>"),"<p>\n";
$text{'sub_USER'} = $text{'sub_MAILBOX'};
$text{'sub_HOME'} = $text{'sub_LOCALHOME'};
&print_subs_table("USER", "FTP", "HOME");
print &email_template_input($file,
	    $config{'newlocal_subject'} || $text{'mail_usubject'},
	    $config{'newlocal_cc'});
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

