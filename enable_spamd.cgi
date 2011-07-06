#!/usr/local/bin/perl
# Configure and start up spamd

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sv_ecannot'});
&ui_print_header(undef, $text{'sv_title5'}, "");

print $text{'sv_senabling'},"<br>\n";
&$indent_print();
$ok = &enable_spamd();
&$outdent_print();
if ($ok) {
	print $text{'sv_enabledok'},"<p>\n";
	&webmin_log("enable", "spamd");
	}
else {
	print "<b>",$text{'sv_notenabled'},"</b><p>\n";
	}
&run_post_actions();

&ui_print_footer("edit_newsv.cgi", $text{'sv_return'});



