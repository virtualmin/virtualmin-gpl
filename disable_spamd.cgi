#!/usr/local/bin/perl
# Shut down spamd

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sv_ecannot'});
&ui_print_unbuffered_header(undef, $text{'sv_title4'}, "");

print $text{'sv_sdisabling'},"<br>\n";
&$indent_print();
$ok = &disable_spamd();
if ($ok) {
	($scanner) = &get_global_spam_client();
	&webmin_log("disable", "spamd");
	}
&$outdent_print();

# Warn if the server filter is still selected but spamd is now stopped
if ($ok && $scanner eq "spamc") {
	print &ui_tag('p').&ui_alert_box($text{'sv_swarning'}, 'warn',
					 undef, undef, '');
	}

&run_post_actions();

&ui_print_footer("edit_newsv.cgi", $text{'sv_return'});



