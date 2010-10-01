#!/usr/bin/perl
# Enable or disable DKIM

require './virtual-server-lib.pl';
&error_setup($text{'dkim_err'});
&can_edit_templates() || &error($text{'dkim_ecannot'});
&ReadParse();

# Validate inputs
$dkim = &get_dkim_config();
$dkim ||= { };
$in{'selector'} =~ /^[a-z0-9\.\-\_]+/i || &error($text{'dkim_eselector'});
$dkim->{'selector'} = $in{'selector'};
$dkim->{'enabled'} = $in{'enabled'};

if ($in{'enabled'}) {
	# Turn on DKIM, or change settings
	&ui_print_unbuffered_header(undef, $text{'dkim_title1'}, "");
	$ok = &enable_dkim($dkim);
	if (!$ok) {
		print "<b>$text{'dkim_somefail'}</b><p>\n";
		}
	}
else {
	# Turn off DKIM
	&ui_print_unbuffered_header(undef, $text{'dkim_title2'}, "");
	$ok = &disable_dkim($dkim);
	}
&run_post_actions();
&webmin_log($in{'enabled'} ? "enable" : "disable", "dkim");

&ui_print_footer("dkim.cgi", $text{'dkim_return'});

