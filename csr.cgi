#!/usr/local/bin/perl
# Generate a CSR and private key for this domain, or generate a self-signed cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin", "webmin-lib.pl");

# Validate inputs
&error_setup($text{'csr_err'});
$in{'commonName'} =~ /^[A-Za-z0-9\.\-\*]+$/ ||
	&error($webmin::text{'newkey_ecn'});
$in{'size_def'} || $in{'size'} =~ /^\d+$/ ||
	&error($webmin::text{'newkey_esize'});
$in{'days'} =~ /^\d+$/ || &error($webmin::text{'newkey_edays'});
$size = $in{'size_def'} ? undef : $in{'size'};

# Copy openssl.cnf if needed to add alternate names field
if ($in{'subjectAltName'}) {
	# Verify alternate names
	@alts = split(/\s+/, $in{'subjectAltName'});
	foreach $a (@alts) {
		$a =~ /^(\*\.)?([a-z0-9\.\_\-]+)$/i ||
			&error(&text('cert_ealt', $a));
		}
	push(@alts, $in{'commonName'});
	}

if (!$in{'self'}) {
	# Generate the private key and CSR
	&ui_print_header(&domain_in($d), $text{'csr_title'}, "");

	# Break SSL linkages that no longer work with this cert
	$newcert = { 'cn' => $in{'commonName'},
		     'alt' => \@alts };
	&break_invalid_ssl_linkages($d, $newcert);

	&$first_print($text{'csr_selfing'});
	&obtain_lock_ssl($d);
	$d->{'ssl_csr'} ||= &default_certificate_file($d, "csr");
	$d->{'ssl_newkey'} ||= &default_certificate_file($d, "newkey");
	&lock_file($d->{'ssl_csr'});
	&lock_file($d->{'ssl_newkey'});
	$err = &generate_certificate_request(
		$d->{'ssl_csr'}, $d->{'ssl_newkey'}, $size, $in{'days'},
		$in{'countryName'},
		$in{'stateOrProvinceName'},
		$in{'cityName'},
		$in{'organizationName'},
		$in{'organizationalUnitName'},
		$in{'commonName'},
		$in{'emailAddress'},
		\@alts,
		$d);
	&error($err) if ($err);
	&set_certificate_permissions($d, $d->{'ssl_newkey'});
	&set_certificate_permissions($d, $d->{'ssl_csr'});
	&unlock_file($d->{'ssl_newkey'});
	&unlock_file($d->{'ssl_csr'});
	&release_lock_ssl($d);
	&$second_print($text{'setup_done'});

	# Save the domain
	&save_domain($d);
	&run_post_actions();
	&webmin_log("newcsr", "domain", $d->{'dom'}, $d);

	print "$text{'csr_done'}<p>\n";

	print &text('csr_csr', "<tt>$d->{'ssl_csr'}</tt>"),"\n";
	print "<pre>",&html_escape(
			&read_file_contents($d->{'ssl_csr'})),"</pre>\n";

	print &text('csr_key', "<tt>$d->{'ssl_newkey'}</tt>"),"\n";
	print "<pre>",&html_escape(
			&read_file_contents($d->{'ssl_newkey'})),"</pre>\n";
	}
else {
	# Create key and cert files
	&ui_print_header(&domain_in($d), $text{'csr_title2'}, "");

	&$first_print($text{'csr_selfing'});
	&obtain_lock_ssl($d);
	$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
	$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
	$err = &generate_self_signed_cert(
				   $d->{'ssl_cert'}, $d->{'ssl_key'},
				   $size, $in{'days'},
				   $in{'countryName'},
				   $in{'stateOrProvinceName'},
				   $in{'cityName'},
				   $in{'organizationName'},
				   $in{'organizationalUnitName'},
				   $in{'commonName'},
				   $in{'emailAddress'},
				   \@alts,
				   $d);
	&error($err) if ($err);
	&$second_print($text{'setup_done'});
	
	# Make sure Apache is setup to use the right key files
	&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});
	&save_website_ssl_file($d, "key", $d->{'ssl_key'});

	# Remove any SSL passphrase
	$d->{'ssl_pass'} = undef;
	&save_domain_passphrase($d);

	# Apply any per-domain cert to Dovecot and Postfix
	if ($d->{'virt'}) {
		&sync_dovecot_ssl_cert($d, 1);
		&sync_postfix_ssl_cert($d, 1);
		}

	# Set permissions
	&set_certificate_permissions($d, $d->{'ssl_cert'});
	&set_certificate_permissions($d, $d->{'ssl_key'});
	&release_lock_ssl($d);

	# Copy to other domains using same cert. Only the password needs to be
	# copied though, as the cert file isn't changing
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		next if (!&domain_has_ssl($od));
		&obtain_lock_ssl($od);
		$od->{'ssl_pass'} = undef;
		&save_domain_passphrase($od);
		&save_domain($od);
		&release_lock_ssl($od);
		}

	&save_domain($d);
	&run_post_actions();
	&webmin_log("newself", "domain", $d->{'dom'}, $d);
	}

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	&domain_footer_link($d),
	"", $text{'index_return'});
