#!/usr/local/bin/perl
# save_newuser.cgi
# Save the new mailbox email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newuser_ecannot'});
&ReadParseMime();
$file = $config{'user_template'};
$file = "$module_config_directory/user-template"
	if ($file eq "none" || $file eq 'default');

&parse_email_template($file, "newuser_subject", "newuser_cc",
	      "newuser_to_mailbox", "newuser_to_owner", "newuser_to_reseller");

&webmin_log("newuser");
&redirect("");

