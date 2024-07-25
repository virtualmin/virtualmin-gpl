#!/usr/local/bin/perl
# Move all cert files to the default location

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d && &can_edit_domain($d) && &can_edit_ssl() ||
	&error($text{'defaultcert_ecannot'});
$d->{'ssl_same'} && &error($text{'defaultcert_esame'});

&ui_print_unbuffered_header(&domain_in($d), $text{'defaultcert_title'}, "");

&lock_domain($d);
&obtain_lock_web($d);
@beforecerts = &get_all_domain_service_ssl_certs($d);

foreach my $t ("key", "cert", "ca", "combined", "everything") {
	$deffile = &default_certificate_file($d, $t);
	$desc = $text{'cert_type_'.$t};
	&$first_print(&text('defaultcert_moving', $desc, "<tt>$deffile</tt>"));
	if (&move_website_ssl_file($d, $t, $deffile)) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'defaultcert_none'});
		}
	}

# Update other services using the cert
&$first_print($text{'cert_updatesvcs'});
&update_all_domain_service_ssl_certs($d, \@beforecerts);
&$second_print($text{'setup_done'});

&run_post_actions();
&save_domain($d);

&release_lock_web($d);
&unlock_domain($d);
&webmin_log("defaultcert", "domain", $d->{'dom'}, $d);

&ui_print_footer("cert_form.cgi?dom=$d->{'id'}", $text{'cert_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

