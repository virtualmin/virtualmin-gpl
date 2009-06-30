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

	# Save the domain
	&save_domain($d);
	&run_post_actions();
	&webmin_log("newcsr", "domain", $d->{'dom'}, $d);

	# Show the output
	&ui_print_header(&domain_in($d), $text{'csr_title'}, "");

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

	&ui_print_header(&domain_in($d), $text{'csr_title2'}, "");
	
	# Make sure Apache is setup to use the right key files
	&obtain_lock_ssl($d);
	&require_apache();
	$conf = &apache::get_config();
	($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					      $d->{'web_sslport'});
	&apache::save_directive("SSLCertificateFile", [ $d->{'ssl_cert'} ],
				$vconf, $conf);
	&apache::save_directive("SSLCertificateKeyFile", [ $d->{'ssl_key'} ],
				$vconf, $conf);
	&flush_file_lines();
	&release_lock_ssl($d);

	# Remove any SSL passphrase
	$d->{'ssl_pass'} = undef;
	&save_domain_passphrase($d);

	# Set permissions
	&set_certificate_permissions($d, $d->{'ssl_cert'});
	&set_certificate_permissions($d, $d->{'ssl_key'});

	# Copy to other domains using same cert. Only the password needs to be
	# copied though, as the cert file isn't changing
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		&obtain_lock_ssl($od);
		$od->{'ssl_pass'} = undef;
		&save_domain_passphrase($od);
		&save_domain($od);
		&release_lock_ssl($od);
		}

	# Re-start Apache
	&register_post_action(\&restart_apache, 1);
	&save_domain($d);
	&run_post_actions();
	&webmin_log("newself", "domain", $d->{'dom'}, $d);
	}

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	&domain_footer_link($d),
	"", $text{'index_return'});
