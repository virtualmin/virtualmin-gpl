#!/usr/local/bin/perl
# Shut down clamd

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sv_ecannot'});
&ui_print_unbuffered_header(undef, $text{'sv_title2'}, "");

print $text{'sv_disabling'},"<br>\n";
&$indent_print();
$ok = &disable_clamd();
if ($ok) {
	($scanner) = &get_global_virus_scanner();
	&webmin_log("disable", "clamd");
	}
&$outdent_print();

# Warn if the server scanner is still selected but clamd is now stopped
if ($ok && $scanner eq "clamdscan") {
	print &ui_tag('p').&ui_alert_box($text{'sv_warning'}, 'warn',
					 undef, undef, '');
	}

&run_post_actions();
&ui_print_footer("edit_newsv.cgi", $text{'sv_return'});



