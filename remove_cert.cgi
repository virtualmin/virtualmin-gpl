#!/usr/local/bin/perl
# Remove an un-used SSL cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&error_setup($text{'rcert_err'});

# Validate inputs
&domain_has_ssl_cert($d) || &error($text{'rcert_ecert'});
&domain_has_ssl($d) && &error($text{'rcert_essl'});
@same = &get_domain_by("ssl_same", $d->{'id'});
@same && &error($text{'rcert_esame'});
$d->{'ssl_same'} && &error($text{'rcert_esame2'});
@beforecerts = &get_all_domain_service_ssl_certs($d);
@beforecerts && &error($text{'rcert_eservice'});

&set_domain_envs($d, "SSL_DOMAIN");
my $merr = &making_changes();
&reset_domain_envs($d);
&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Remove the cert and key from the domain object
my $oldd = { %$d };
foreach my $k ('cert', 'key', 'chain', 'combined', 'everything') {
	if ($d->{'ssl_'.$k}) {
		&unlink_logged_as_domain_user($d, $d->{'ssl_'.$k});
		delete($d->{'ssl_'.$k});
		}
	}
delete($d->{'ssl_pass'});
&set_all_null_print();
foreach $f (&domain_features($d), &list_feature_plugins()) {
	&call_feature_func($f, $d, $oldd);
	}
&save_domain($d);

&set_domain_envs($d, "SSL_DOMAIN", undef);
my $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

&webmin_log("rcert", "domain", $d->{'dom'});
&redirect("cert_form.cgi?dom=$d->{'id'}");

