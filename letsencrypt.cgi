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
@dnames || &error($text{'letsencrypt_ednames'});
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

	# Build list of domains
	my @cdoms = ( $d );
	if (!$d->{'alias'} && $in{'dname_def'}) {
		push(@cdoms, grep { &domain_has_website($_) }
				  &get_domain_by("alias", $d->{'id'}));
		}

	# Validate connectivity
	if ($in{'connectivity'} >= 1) {
		&$first_print(&text('letsencrypt_conncheck',
			join(" ", map { &show_domain_name($_) } @cdoms)));
		my @errs;
		foreach my $cd (@cdoms) {
			push(@errs, &check_domain_connectivity($cd,
					{ 'mail' => 1, 'ssl' => 1 }));
			}
		if (@errs) {
			&$second_print($text{'letsencrypt_connerrs'});
			print "<ul>\n";
			foreach my $e (@errs) {
				print "<li>",$e->{'desc'}," : ",
					     $e->{'error'},"\n";
				}
			print "</ul>\n";
			&ui_print_footer(&domain_footer_link($d),
					 "", $text{'index_return'});
			return;
			}
		else {
			&$second_print($text{'letsencrypt_connok'});
			}
		}

	# Validate config
	if ($in{'connectivity'} == 1) {
		&$first_print(&text('letsencrypt_validcheck',
			join(" ", map { &show_domain_name($_) } @cdoms)));
		my @errs = map { &validate_letsencrypt_config($_) } @cdoms;
		if (@errs) {
			&$second_print($text{'letsencrypt_connerrs'});
			print "<ul>\n";
			foreach my $e (@errs) {
				print "<li>",$e->{'desc'}," : ",
					     $e->{'error'},"\n";
				}
			print "</ul>\n";
			&ui_print_footer(&domain_footer_link($d),
					 "", $text{'index_return'});
			return;
			}
		else {
			&$second_print($text{'letsencrypt_connok'});
			}

		}

	# Run the before command
	&set_domain_envs($d, "SSL_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

	&$first_print(&text('letsencrypt_doing2',
			    join(", ", map { "<tt>$_</tt>" } @dnames)));
	&foreign_require("webmin");
	$phd = &public_html_dir($d);
	$before = &before_letsencrypt_website($d);
	($ok, $cert, $key, $chain) = &request_domain_letsencrypt_cert(
					$d, \@dnames);
	&after_letsencrypt_website($d, $before);
	if (!$ok) {
		&$second_print(&text('letsencrypt_failed', $cert));
		}
	else {
		&$second_print($text{'letsencrypt_done'});

		# Figure out which services (webmin, postfix, etc)
		# were using the old cert
		my @before;
		foreach my $svc (&get_all_service_ssl_certs($d, 0)) {
			if (&same_cert_file($d->{'ssl_cert'}, $svc->{'cert'})) {
				push(@before, $svc);
				}
			}

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
		$d->{'letsencrypt_last_success'} = time();
		&save_domain($d);

		# Apply any per-domain cert to Dovecot and Postfix
		&sync_dovecot_ssl_cert($d, 1);
		if ($d->{'virt'}) {
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

		# Update DANE DNS records
		&sync_domain_tlsa_records($d);
		foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
			&sync_domain_tlsa_records($od);
			}

		&release_lock_ssl($d);
		&$second_print($text{'setup_done'});

		# Update services that were using the old cert
		foreach my $svc (@before) {
			my $func = "copy_".$svc->{'id'}."_ssl_service";
			&$func($d);
			}

		# Run the after command
		&set_domain_envs($d, "SSL_DOMAIN");
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

