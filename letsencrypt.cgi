#!/usr/local/bin/perl
# Request and install a cert and key from Let's Encrypt

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'letsencrypt_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});

if ($in{'dname_def'}) {
	@dnames = &get_hostnames_for_ssl($d);
	$custom_dname = undef;
	}
else {
	foreach my $dname (split(/\s+/, $in{'dname'})) {
		$dname = lc(&parse_domain_name($dname));
		my $checkname = $dname;
		$checkname =~ s/^www\.//;
		$err = &valid_domain_name($checkname);
		&error($err) if ($err);
		push(@dnames, $dname);
		}
	$custom_dname = join(" ", @dnames);
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'letsencrypt_title'}, "");

&$first_print(&text('letsencrypt_doing2',
		    join(", ", map { "<tt>$_</tt>" } @dnames)));
&foreign_require("webmin");
$phd = &public_html_dir($d);
if (&get_webmin_version() >= 1.782) {
	($ok, $cert, $key, $chain) =
		&webmin::request_letsencrypt_cert(\@dnames, $phd);
	}
else {
	($ok, $cert, $key, $chain) =
		&webmin::request_letsencrypt_cert($dnames[0], $phd);
	}
if (!$ok) {
	&$second_print(&text('letsencrypt_failed',
			     "<pre>".&html_escape($cert)."</pre>"));
	}
else {
	&$second_print($text{'letsencrypt_done'});

	# Worked .. copy to the domain
	&obtain_lock_ssl($d);
	&$first_print($text{'newkey_apache'});

	# Copy and save the cert
	$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
	$cert_text = &read_file_contents($cert);
	&lock_file($d->{'ssl_cert'});
        &unlink_file($d->{'ssl_cert'});
        &open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_cert'}");
        &print_tempfile(CERT, $cert_text);
        &close_tempfile_as_domain_user($d, CERT);
        &set_certificate_permissions($d, $d->{'ssl_cert'});
        &unlock_file($d->{'ssl_cert'});
	&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});

	# And the key
	$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
	$key_text = &read_file_contents($key);
        &lock_file($d->{'ssl_key'});
        &unlink_file($d->{'ssl_key'});
        &open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_key'}");
        &print_tempfile(CERT, $key_text);
        &close_tempfile_as_domain_user($d, CERT);
        &set_certificate_permissions($d, $d->{'ssl_key'});
        &unlock_file($d->{'ssl_key'});
	&save_website_ssl_file($d, "key", $d->{'ssl_key'});

	# Let's encrypt certs have no passphrase
	$d->{'ssl_pass'} = undef;
	&save_domain_passphrase($d);

	# And the chained file
	if ($chain) {
		$chainfile = &default_certificate_file($d, 'ca');
		$chain_text = &read_file_contents($chain);
		&lock_file($chainfile);
		&unlink_file_as_domain_user($d, $chainfile);
		&open_tempfile_as_domain_user($d, CERT, ">$chainfile");
		&print_tempfile(CERT, $chain_text);
		&close_tempfile_as_domain_user($d, CERT);
		&set_permissions_as_domain_user($d, 0755, $chainfile);
		&unlock_file($chainfile);
		$err = &save_website_ssl_file($d, 'ca', $chainfile);
		}

	$d->{'letsencrypt_dname'} = $custom_dname;
	&save_domain($d);

	# Apply any per-domain cert to Dovecot and Postfix
	if ($d->{'virt'}) {
		&sync_dovecot_ssl_cert($d, 1);
		&sync_postfix_ssl_cert($d, 1);
		}

	# For domains that were using the SSL cert on this domain originally but
	# can no longer due to the cert hostname changing, break the linkage
	&break_invalid_ssl_linkages($d);

	# Copy SSL directives to domains using same cert
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		next if (!&domain_has_ssl($od));
		$od->{'ssl_cert'} = $d->{'ssl_cert'};
		$od->{'ssl_key'} = $d->{'ssl_key'};
		$od->{'ssl_newkey'} = $d->{'ssl_newkey'};
		$od->{'ssl_csr'} = $d->{'ssl_csr'};
		$od->{'ssl_pass'} = $d->{'ssl_pass'};
		&save_domain_passphrase($od);
		&save_domain($od);
		}

	&release_lock_ssl();
	&$second_print($text{'setup_done'});

	&run_post_actions();
	&webmin_log("letsencrypt", "domain", $d->{'dom'}, $d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

