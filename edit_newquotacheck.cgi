#!/usr/local/bin/perl
# Show a form for checking quotas on home and mail filesystems

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newquotacheck_ecannot'});
&has_quotacheck() || &error($text{'newquotacheck_esupport'});
&ui_print_header(undef, $text{'newquotacheck_title'}, "");

print "$text{'newquotacheck_desc'}<p>\n";
print &ui_form_start("quotacheck.cgi", "post");
print &ui_table_start($text{'newquotacheck_header'}, undef, 2);

# Filesystems to check
if (&has_home_quotas()) {
	print &ui_table_row($text{'newquotacheck_home'},
			    &ui_yesno_radio("home", 1));
	}
if (&has_mail_quotas()) {
	print &ui_table_row($text{'newquotacheck_mail'},
			    &ui_yesno_radio("mail", 1));
	}

# Quota types of check
if ($config{'group_quotas'}) {
	print &ui_table_row($text{'newquotacheck_who'},
		   &ui_radio("who", 2, [ [ 0, $text{'newquotacheck_users'} ],
					 [ 1, $text{'newquotacheck_groups'} ],
					 [ 2, $text{'newquotacheck_both'} ] ]));
	}
else {
	print &ui_hidden("who", 0),"\n";
	}

print &ui_table_end();
print &ui_form_end([ [ "check", $text{'newquotacheck_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});

