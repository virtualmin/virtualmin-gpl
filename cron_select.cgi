#!/usr/local/bin/perl
# Parse inputs from cron_chooser.cgi and update original field

require './virtual-server-lib.pl';
&ReadParse();
&foreign_require("cron");

# Parse inputs
$job = { };
&cron::parse_times_input($job, \%in);
$when = &cron::when_text($job, 1);

# Output Javascript to set main fields
&popup_header($text{'cron_title'});
print "<script>\n";
print "top.opener.hfield.value = \"",
	&quote_escape(join(" ", $job->{'mins'}, $job->{'hours'}, $job->{'days'},
		  		$job->{'months'}, $job->{'weekdays'}), '"'),
	"\";\n";
print "top.opener.cfield.value = \"$when\";\n";
print "window.close();\n";
print "</script>\n";

&popup_footer();


