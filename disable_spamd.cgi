#!/usr/local/bin/perl
# Shut down spamd

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sv_ecannot'});
&ui_print_header(undef, $text{'sv_title4'}, "");

print $text{'sv_sdisabling'},"<br>\n";
&$indent_print();
$ok = &disable_spamd();
if ($ok) {
	($scanner) = &get_global_spam_client();
	if ($scanner eq "spamc") {
		&$first_print("<b>".$text{'sv_swarning'}."</b>");
		}
	&webmin_log("disable", "spamd");
	}
&$outdent_print();

&ui_print_footer("edit_newsv.cgi", $text{'sv_return'});



