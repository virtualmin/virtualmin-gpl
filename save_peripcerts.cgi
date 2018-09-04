#!/usr/local/bin/perl
# Update per-IP webmin and usermin certs

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&can_webmin_cert() || &error($text{'edit_ecannot'});

# Figure out current state
@already = &get_all_domain_service_ssl_certs($d);
($webmina) = grep { $_->{'d'} && $_->{'id'} eq 'webmin' } @already;
($usermina) = grep { $_->{'d'} && $_->{'id'} eq 'usermin' } @already;

# Apply user selections
if ($in{'webmin'} && !$webmina) {
	&setup_domain_ipkeys($d, undef, 'webmin');
	}
elsif (!$in{'webmin'} && $webmina) {
	&delete_domain_ipkeys($d, 'webmin');
	}
if ($in{'usermin'} && !$usermina) {
	&setup_domain_ipkeys($d, undef, 'usermin');
	}
elsif (!$in{'usermin'} && $usermina) {
	&delete_domain_ipkeys($d, 'usermin');
	}

&run_post_actions_silently();
&webmin_log("peripcerts", "domain", $d->{'dom'}, $d);
&redirect("cert_form.cgi?dom=$d->{'id'}");

