#!/usr/local/bin/perl
# save_newlocal.cgi
# Save the new local mailbox email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newlocal_ecannot'});
&ReadParseMime();
$file = $config{'local_template'};
$file = "$module_config_directory/local-template"
	if ($file eq "none" || $file eq 'default');

&parse_email_template($file, "newlocal_subject", "newlocal_cc", "newlocal_bcc");

&webmin_log("newlocal");
&redirect("");

