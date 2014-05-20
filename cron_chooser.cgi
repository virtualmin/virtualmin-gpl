#!/usr/local/bin/perl
# Show the Cron scheduler in a popup window

require './virtual-server-lib.pl';
&ReadParse();
&foreign_require("cron", "cron-lib.pl");
&popup_header($text{'cron_title'});

# Create the job object
if ($in{'complex'} ne '') {
	@j = split(/\s+/, $in{'complex'});
	$job = { 'mins' => $j[0], 'hours' => $j[1], 'days' => $j[2],
                 'months' => $j[3], 'weekdays' => $j[4] };
	}
else {
	$job = { 'mins' => 0, 'hours' => '*', 'days' => '*',
		 'months' => '*', 'weekdays' => '*' };
	}

# Show it
print &ui_form_start("cron_select.cgi");
print "<table border width=100% class='ui_table'>\n";
&cron::show_times_input($job, 1);
print "</table>\n";
print &ui_form_end([ [ undef, $text{'cron_ok'} ] ]);

&popup_footer();

