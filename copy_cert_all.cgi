#!/usr/local/bin/perl
# Copy this domain's cert to all services as the default

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d && &can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_unbuffered_header(&domain_in($d), $text{'copycert_title'}, "");
@already = &get_all_domain_service_ssl_certs($d);

foreach my $st (&list_service_ssl_cert_types()) {
	($a) = grep { !$_->{'d'} && $_->{'id'} eq $st->{'id'} } @already;
	if (!$a) {
		my $cfunc = "copy_".$st->{'id'}."_ssl_service";
		&$cfunc($d);
		}
	}

&run_post_actions();
&webmin_log("copycert", "all");

&ui_print_footer("cert_form.cgi?dom=$d->{'id'}", $text{'cert_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

