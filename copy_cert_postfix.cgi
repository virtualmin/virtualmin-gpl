#!/usr/local/bin/perl
# Copy this domain's cert to Postfix

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_header(&domain_in($d), $text{'copycert_title'}, "");

&copy_postfix_ssl_service($d);
&run_post_actions();
&webmin_log("copycert", "postfix");

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

