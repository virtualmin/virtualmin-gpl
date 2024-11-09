#!/usr/local/bin/perl
# Request and install a cert and key from Let's Encrypt

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'letsencrypt_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_edit_letsencrypt() &&
    (&domain_has_website($d) || $d->{'dns'}) ||
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
		$checkname =~ s/^\*\.//;
		$err = &valid_domain_name($checkname);
		&error($err) if ($err);
		push(@dnames, $dname);
		}
	$custom_dname = join(" ", @dnames);
	}
@dnames || &error($text{'letsencrypt_ednames'});
push(@dnames, "*.".$d->{'dom'}) if ($in{'dwild'});

# Filter wildcard to prevent redundancy
my $fdnames = &filter_ssl_wildcards(\@dnames);
@dnames = @$fdnames;

if ($in{'only'}) {
	# Just update renewal date and domains
	$d->{'letsencrypt_dname'} = $custom_dname;
	$d->{'letsencrypt_dwild'} = $in{'dwild'};
	$d->{'letsencrypt_renew'} = $in{'renew'};
	$d->{'letsencrypt_nodnscheck'} = !$in{'dnscheck'};
	$d->{'letsencrypt_subset'} = $in{'subset'};
	$d->{'letsencrypt_email'} = $in{'email'};
	$d->{'letsencrypt_id'} = $in{'acme'} if (defined($in{'acme'}));
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
	if ($in{'connectivity'} == 2) {
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
	if ($in{'connectivity'} >= 1) {
		&$first_print(&text('letsencrypt_validcheck',
			join(" ", map { &show_domain_name($_) } @cdoms)));
		my $vcheck = $in{'dwild'} ? ['dns'] : ['web'];
		my @errs = map { &validate_letsencrypt_config($_, $vcheck) } @cdoms;
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

	# Filter down hostnames to those that can be resolved
	if ($in{'dnscheck'}) {
		&$first_print($text{'letsencrypt_dnscheck'});
		my @badnames;
		my $fok = &filter_external_dns(\@dnames, \@badnames);
		if ($fok < 0) {
			&$second_print($text{'letsencrypt_ednscheck'});
			}
		elsif ($fok) {
			&$second_print($text{'letsencrypt_dnscheckok'});
			}
		elsif (!@dnames) {
			&$second_print($text{'letsencrypt_dnscheckall'});
			goto FAILED;
			}
		else {
			&$second_print(&text('letsencrypt_dnscheckbad',
				join(', ', map { "<tt>$_</tt>" } @badnames)));
			}
		}

	# Run the before command
	&set_domain_envs($d, "SSL_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

	$dlist = join(", ", map { "<tt>$_</tt>" } @dnames);
	if (defined($in{'acme'})) {
		($acme) = grep { $_->{'id'} eq $in{'acme'} }
			       &list_acme_providers();
		$acme || &error($text{'letsencrypt_eacme'});
		&can_acme_provider($acme) ||
			&error($text{'letsencrypt_eacme2'});
		if ($acme->{'type'}) {
			($prov) = grep { $_->{'id'} eq $acme->{'type'} }
				       &list_known_acme_providers();
			}
		&$first_print(&text('letsencrypt_doing2a', $dlist,
				    $prov ? $prov->{'desc'} : $acme->{'desc'}));
		}
	else {
		&$first_print(&text('letsencrypt_doing2', $dlist));
		}
	&foreign_require("webmin");
	$phd = &public_html_dir($d);
	$before = &before_letsencrypt_website($d);
	($ok, $cert, $key, $chain) = &request_domain_letsencrypt_cert(
					$d, \@dnames, 0, undef, undef,
					$in{'ctype'}, $acme, $in{'subset'});
	&after_letsencrypt_website($d, $before);
	if (!$ok) {
		# Always store last Certbot error
		&lock_domain($d);
		$d->{'letsencrypt_last_failure'} = time();
		$d->{'letsencrypt_last_err'} = $cert;
		$d->{'letsencrypt_last_err'} =~ s/\r?\n/\t/g;
		&save_domain($d);
		&unlock_domain($d);
		&$second_print(&text('letsencrypt_failed', $cert));
		}
	else {
		$info = &cert_file_info($cert);
		@gotnames = &unique($info->{'cn'}, @{$info->{'alt'}});
		if (scalar(@gotnames) == scalar(@dnames)) {
			&$second_print(&text('letsencrypt_done'));
			}
		else {
			&$second_print(&text('letsencrypt_done2',
				join(", ", map { "<tt>$_</tt>" } @gotnames)));
			}

		# Figure out which services (webmin, postfix, etc)
		# were using the old cert
		@beforecerts = &get_all_domain_service_ssl_certs($d);

		# Worked .. copy to the domain
		&obtain_lock_ssl($d);
		&$first_print($text{'newkey_apache'});
		&install_letsencrypt_cert($d, $cert, $key, $chain);

		# Save renewal state
		$d->{'letsencrypt_dname'} = $custom_dname;
		$d->{'letsencrypt_dwild'} = $in{'dwild'};
		$d->{'letsencrypt_renew'} = $in{'renew'};
		$d->{'letsencrypt_ctype'} = $in{'ctype'} =~ /^ec/ ? "ecdsa" : "rsa";
		$d->{'letsencrypt_last'} = time();
		$d->{'letsencrypt_last_success'} = time();
		$d->{'letsencrypt_nodnscheck'} = !$in{'dnscheck'};
		$d->{'letsencrypt_subset'} = $in{'subset'};
		$d->{'letsencrypt_email'} = $in{'email'};
		$d->{'letsencrypt_id'} = $acme->{'id'} if ($acme);
		delete($d->{'letsencrypt_last_err'});
		&refresh_ssl_cert_expiry($d);
		&save_domain($d);
		&$second_print($text{'setup_done'});

		# Update other services using the cert
		&$first_print($text{'cert_updatesvcs'});
		&update_all_domain_service_ssl_certs($d, \@beforecerts);
		&$second_print($text{'setup_done'});

		# For domains that were using the SSL cert on this domain
		# originally but can no longer due to the cert hostname
		# changing, break the linkage
		&break_invalid_ssl_linkages($d);

		# Copy SSL directives to domains using same cert
		foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
			next if (!&domain_has_ssl_cert($od));
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

		# Run the after command
		&set_domain_envs($d, "SSL_DOMAIN");
		local $merr = &made_changes();
		&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
			if (defined($merr));
		&reset_domain_envs($d);

		&run_post_actions();
		&webmin_log("letsencrypt", "domain", $d->{'dom'}, $d);
		}

	FAILED:
	&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
		&domain_footer_link($d),
			 "", $text{'index_return'});
	}

