#!/usr/local/bin/perl
# Save the updated mailbox email

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newuser_ecannot'});
&ReadParseMime();
$file = $config{'update_template'};
$file = "$module_config_directory/update-template"
	if ($file eq "none" || $file eq 'default');

&parse_email_template($file, "newupdate_subject",
		      "newupdate_cc", "newupdate_bcc",
		      "newupdate_to_mailbox", "newupdate_to_owner",
		      "newupdate_to_reseller", "update_template");

&webmin_log("newupdate");
&redirect("");

