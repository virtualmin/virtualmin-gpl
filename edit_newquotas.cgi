#!/usr/local/bin/perl
# Show a form for setting up regular quota monitoring

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newquotas_ecannot'});
&ui_print_header(undef, $text{'newquotas_title'}, "", "newquotas");

if ($config{'group_quotas'}) {
	print "$text{'newquotas_desc'}\n";
	}
else {
	print "$text{'newquotas_desc2'}\n";
	}
print "<p>\n";
print "$text{'newquotas_desc3'}<p>\n";

print &ui_form_start("save_newquotas.cgi", "post");
print &ui_table_start($text{'newquotas_header'}, undef, 2);

# Email results to
print &ui_table_row($text{'newquotas_email'},
		    &ui_opt_textbox("email", $config{'quota_email'}, 40,
				    $text{'newquotas_nobody'},
				    $text{'newquotas_addr'}));

# Email admins too
print &ui_table_row($text{'newquotas_users'},
		    &ui_yesno_radio("users", $config{'quota_users'}));

# Also check mailbox quotas?
print &ui_table_row($text{'newquotas_mailbox'},
		    &ui_yesno_radio("mailbox", $config{'quota_mailbox'}));

# Notify mailbox users?
print &ui_table_row($text{'newquotas_mailbox_send'},
	    &ui_yesno_radio("mailbox_send", $config{'quota_mailbox_send'}));

# Warning levels
print &ui_table_row($text{'newquotas_warn'},
		    &ui_opt_textbox("warn", $config{'quota_warn'}, 20,
				    $text{'newquotas_nowarn'},
				    $text{'newquotas_warnlist'})." %");

# Interval between warnings
print &ui_table_row($text{'newquotas_interval'},
		    &ui_opt_textbox("interval", $config{'quota_interval'},
				    5, $text{'newquotas_noint'})." ".
		    $text{'newquotas_hours'});

# Scheduled checking enabled?
$job = &find_cron_script($quotas_cron_cmd);
print &ui_table_row($text{'newquotas_when'},
	&virtualmin_ui_show_cron_time("sched", $job,
				      $text{'newquotas_whenno'}));

# Email message template
print &ui_table_row($text{'newquotas_msg'},
	&ui_textarea("msg", &get_quotas_message(), 10, 60));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newquotas_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
