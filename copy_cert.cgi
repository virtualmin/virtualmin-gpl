#!/usr/local/bin/perl
# Copy this domain's cert to Webmin or Usermin

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_header(&domain_in($d), $text{'copycert_title'}, "");

if ($in{'usermin'}) {
	&copy_usermin_ssl_service($d);
	}
else {
	&copy_usermin_ssl_service($d);
	}

&run_post_actions();
&webmin_log("copycert", $in{'usermin'} ? "usermin" : "webmin");

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

