#!/usr/local/bin/perl
# Re-send the signup email

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_config_domain($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'reemail_title'}, "");
if (&will_send_domain_email()) {
	&send_domain_email($d);
	}
else {
	print $text{'reemail_dis'},"<p>\n";
	}
&ui_print_footer(&domain_footer_link($d));

