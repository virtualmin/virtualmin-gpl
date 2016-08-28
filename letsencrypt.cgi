#!/usr/local/bin/perl
# Request and install a cert and key from Let's Encrypt

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'letsencrypt_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_edit_letsencrypt() ||
	&error($text{'edit_ecannot'});
$d->{'disabled'} && &error($text{'letsencrypt_eenabled'});

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
$in{'renew_def'} || $in{'renew'} =~ /^\d+(\.\d+)?$/ ||
	&error($text{'letsencrypt_erenew'});

if ($in{'only'}) {
	# Just update renewal date and domains
	$d->{'letsencrypt_dname'} = $custom_dname;
	if ($in{'renew_def'}) {
		delete($d->{'letsencrypt_renew'});
		}
	else {
		$d->{'letsencrypt_renew'} = $in{'renew'};
		}
	&save_domain($d);
	&redirect("cert_form.cgi?dom=$d->{'id'}");
	}
else {
	&ui_print_unbuffered_header(&domain_in($d),
				    $text{'letsencrypt_title'}, "");

	# Run the before command
	&set_domain_envs($oldd, "SSL_DOMAIN", $d);
	$merr = &making_changes();
	&reset_domain_envs($oldd);
	&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

	&$first_print(&text('letsencrypt_doing2',
			    join(", ", map { "<tt>$_</tt>" } @dnames)));
	&foreign_require("webmin");
	$phd = &public_html_dir($d);
	&suppress_letsencrypt_proxy($d);
	($ok, $cert, $key, $chain) = &webmin::request_letsencrypt_cert(
					\@dnames, $phd, $d->{'emailto'});
	if (!$ok) {
		&$second_print(&text('letsencrypt_failed', $cert));
		}
	else {
		&$second_print($text{'letsencrypt_done'});

		# Worked .. copy to the domain
		&obtain_lock_ssl($d);
		&$first_print($text{'newkey_apache'});
		&install_letsencrypt_cert($d, $cert, $key, $chain);

		# Save renewal state
		$d->{'letsencrypt_dname'} = $custom_dname;
		if ($in{'renew_def'}) {
			delete($d->{'letsencrypt_renew'});
			}
		else {
			$d->{'letsencrypt_renew'} = $in{'renew'};
			}
		$d->{'letsencrypt_last'} = time();
		&save_domain($d);

		# Apply any per-domain cert to Dovecot and Postfix
		if ($d->{'virt'}) {
			&sync_dovecot_ssl_cert($d, 1);
			&sync_postfix_ssl_cert($d, 1);
			}

		# For domains that were using the SSL cert on this domain
		# originally but can no longer due to the cert hostname
		# changing, break the linkage
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

		&release_lock_ssl($d);
		&$second_print($text{'setup_done'});

		# Run the after command
		&set_domain_envs($d, "SSL_DOMAIN", undef, $oldd);
		local $merr = &made_changes();
		&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
			if (defined($merr));
		&reset_domain_envs($d);

		&run_post_actions();
		&webmin_log("letsencrypt", "domain", $d->{'dom'}, $d);
		}

	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	}

