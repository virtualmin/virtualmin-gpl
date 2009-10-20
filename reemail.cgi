#!/usr/local/bin/perl
# Re-send the signup email

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'reemail_title'}, "");

if (!&will_send_domain_email($d)) {
	# Disabled for the domain
	print $text{'reemail_dis'},"<p>\n";
	}
elsif ($in{'confirm'}) {
	# Send now
	&send_domain_email($d, $in{'to'});
	}
else {
	# Ask who to
	print "<center>\n";
	print &ui_form_start("reemail.cgi");
	print &ui_hidden("dom", $in{'dom'});
	print $text{'reemail_desc'},"<p>\n";
	print "<b>$text{'reemail_to'}</b>\n";
	print &ui_textbox("to", $d->{'emailto'}, 50),"<p>\n";
	print &ui_form_end([ [ "confirm", $text{'reemail_ok'} ] ]);
	print "</center>\n";
	}

&ui_print_footer(&domain_footer_link($d));

