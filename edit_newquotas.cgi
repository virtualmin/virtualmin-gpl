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

print &ui_form_start("save_newquotas.cgi", "post");
print &ui_table_start($text{'newquotas_header'}, undef, 2);

# Email results to
print &ui_table_row($text{'newquotas_email'},
		    &ui_textbox("email", $config{'quota_email'}, 40));

# Warning level
print &ui_table_row($text{'newquotas_warn'},
		    &ui_opt_textbox("warn", $config{'quota_warn'}, 4,
				    $text{'newquotas_nowarn'})." %");

# Scheduled checking enabled?
$job = &find_quotas_job();
print &ui_table_row($text{'newquotas_sched'},
		    &ui_radio("sched", $job ? 1 : 0,
			      [ [ 0, $text{'no'} ],
				[ 1, $text{'newquotas_schedyes'} ] ]));
print "<tr> <td colspan=2><table border width=100%>\n";
$job ||= { 'mins' => 0,
	   'hours' => 0,
	   'days' => '*',
	   'months' => '*',
	   'weekdays' => '*' };
&cron::show_times_input($job);
print "</table></td> </tr>\n";

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newquotas_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
