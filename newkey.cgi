#!/usr/local/bin/perl
# newkey.cgi
# Install a new SSL cert and key

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&error_setup($text{'newkey_err'});

$homed = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;

# Validate cert file
if ($in{'cert_mode'} == 0) {
	$cert = $in{'cert'};
	}
elsif ($in{'cert_mode'} == 1) {
	$cert = $in{'certupload'};
	}
elsif ($in{'cert_mode'} == 3) {
	# Use existing cert
	$cert = &read_file_contents($d->{'ssl_cert'});
	}
else {
	&is_under_directory($homed->{'home'}, $in{'certfile'}) ||
	   $in{'certfile'} eq &default_certificate_file($d, "cert") ||
		&error(&text('newkey_ecertfilehome', $in{'certfile'}));
	$cert = &read_file_contents_as_domain_user($d, $in{'certfile'});
	$cert || &error(&text('newkey_ecertfile', $in{'certfile'}));
	}

# Validate key file
if ($in{'newkey_mode'} == 0) {
	# Pasted text
	$newkey = $in{'newkey'};
	}
elsif ($in{'newkey_mode'} == 1) {
	# Uploaded file
	$newkey = $in{'newkeyupload'};
	}
elsif ($in{'newkey_mode'} == 2) {
	# File on server
	&is_under_directory($homed->{'home'}, $in{'newkeyfile'}) ||
	   $in{'newkeyfile'} eq &default_certificate_file($d, "key") ||
		&error(&text('newkey_enewkeyfilehome', $in{'newkeyfile'}));
	$d->{'ssl_newkey'} && $in{'newkeyfile'} eq $d->{'ssl_newkey'} &&
		&error($text{'newkey_ekeysame'});
	$newkey = &read_file_contents_as_domain_user($d, $in{'newkeyfile'});
	$newkey || &error(&text('newkey_enewkeyfile', $in{'newkeyfile'}));
	}
elsif ($in{'newkey_mode'} == 3) {
	# Use existing key
	$newkey = &read_file_contents($d->{'ssl_key'});
	}
elsif ($in{'newkey_mode'} == 4) {
	# Use key from CSR
	-r $d->{'ssl_newkey'} || &error($text{'newkey_enewkeycsr'});
	$newkey = &read_file_contents_as_domain_user($d, $d->{'ssl_newkey'});
	}

# Validate CA cert
if ($in{'newca_mode'} == 0) {
	# Pasted text
	$newca = $in{'newca'};
	}
elsif ($in{'newca_mode'} == 1) {
	# Uploaded file
	$newca = $in{'newcaupload'};
	}
elsif ($in{'newca_mode'} == 2) {
	# File on server
	&is_under_directory($homed->{'home'}, $in{'newcafile'}) ||
	   $in{'newcafile'} eq &default_certificate_file($d, "ca") ||
		&error(&text('newkey_enewcafilehome', $in{'newcafile'}));
	$newca = &read_file_contents_as_domain_user($d, $in{'newcafile'});
	$newca || &error(&text('newkey_enewcafile', $in{'newcafile'}));
	}
elsif ($in{'newca_mode'} == 3) {
	# Use existing CA cert
	$newca = &read_file_contents($d->{'ssl_chain'});
	}
elsif ($in{'newca_mode'} == 4) {
	# No CA cert needed
	$newca = "";
	}

$cert =~ s/\r//g;
$newkey =~ s/\r//g;
$err = &validate_cert_format($cert, "cert");
$err && &error(&text('newkey_ecert2', $err));
$err = &validate_cert_format($newkey, "key");
$err && &error(&text('newkey_enewkey2', $err));
if ($newca) {
	$newca =~ s/\r//g;
	$err = &validate_cert_format($newca, "cert");
	$err && &error(&text('newkey_eca2', $err));
	}

# Check if a passphrase is needed
$passok = &check_passphrase($newkey, $in{'pass_def'} ? undef : $in{'pass'});
$passok || &error($text{'newkey_epass'});

# Check that the cert and key match
$certerr = &check_cert_key_match($cert, $newkey);
$certerr && &error(&text('newkey_ematch', $certerr));

# Check that the CA cert matches
$newcertinfo = &cert_data_info($cert);
if ($newca) {
	$newcainfo = &cert_data_info($newca);
	if ($newcainfo->{'o'} ne $newcertinfo->{'issuer_o'} ||
	    $newcainfo->{'cn'} ne $newcertinfo->{'issuer_cn'}) {
		&error($text{'newkey_ecamatch'});
		}
	}

&ui_print_header(&domain_in($d), $text{'newkey_title'}, "");

# Run the before command
&set_domain_envs($oldd, "SSL_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));
@beforecerts = &get_all_domain_service_ssl_certs($d);

# Break SSL linkages that no longer work with this cert
&break_invalid_ssl_linkages($d, $newcertinfo);

# Make sure Apache is setup to use the right key files
&obtain_lock_ssl($d);
&create_ssl_certificate_directories($d);
&$first_print($text{'newkey_apache'});
if ($in{'newkey_mode'} == 2) {
	$d->{'ssl_key'} = $in{'newkeyfile'};
	}
else {
	$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
	}
if ($in{'cert_mode'} == 2) {
	$d->{'ssl_cert'} = $in{'certfile'};
	}
else {
	$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
	}
if ($in{'ca_mode'} == 2) {
	$d->{'ssl_chain'} = $in{'cafile'};
	}
elsif ($in{'ca_mode'} == 4) {
	$d->{'ssl_chain'} = undef;
	}
else {
	$d->{'ssl_chain'} ||= &default_certificate_file($d, 'ca');
	}
&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});
&save_website_ssl_file($d, "key", $d->{'ssl_key'});
&save_website_ssl_file($d, "ca", $d->{'ssl_chain'});
&refresh_ssl_cert_expiry($d);
&save_domain($d);
&$second_print($text{'setup_done'});

# If a passphrase is needed, add it to the top-level Apache config. This is
# done by creating a small script that outputs the passphrase
$d->{'ssl_pass'} = $passok == 2 ? $in{'pass'} : undef;
&save_domain_passphrase($d);

# Write out the certs and private key
if ($in{'cert_mode'} != 2) {
	&$first_print($text{'newkey_savingcert'});
	&lock_file($d->{'ssl_cert'});
	&write_ssl_file_contents($d, $d->{'ssl_cert'}, $cert);
	&unlock_file($d->{'ssl_cert'});
	&$second_print($text{'setup_done'});
	}

if ($in{'newkey_mode'} != 2) {
	&$first_print($text{'newkey_savingkey'});
	&lock_file($d->{'ssl_key'});
	&write_ssl_file_contents($d, $d->{'ssl_key'}, $newkey);
	&unlock_file($d->{'ssl_key'});
	&$second_print($text{'setup_done'});
	}

if ($in{'newca_mode'} != 2 && $in{'newca_mode'} != 4) {
	&$first_print($text{'newkey_savingca'});
	&lock_file($d->{'ssl_chain'});
	&write_ssl_file_contents($d, $d->{'ssl_chain'}, $newca);
	&unlock_file($d->{'ssl_chain'});
	&$second_print($text{'setup_done'});
	}

# Update other services using the cert
&$first_print($text{'cert_updatesvcs'});
&update_all_domain_service_ssl_certs($d, \@beforecerts);
&$second_print($text{'setup_done'});

# Remove the new private key we just installed
&release_lock_ssl($d);
if ($d->{'ssl_newkey'}) {
	$newkeyfile = &read_file_contents_as_domain_user(
		$d, $d->{'ssl_newkey'});
	if ($newkeyfile eq $newkey) {
		&unlink_logged($d->{'ssl_newkey'});
		delete($d->{'ssl_newkey'});
		delete($d->{'ssl_csr'});
		&save_domain($d);
		}
	}
&sync_combined_ssl_cert($d);

# For domains that were using the SSL cert on this domain originally but
# can no longer due to the cert hostname changing, break the linkage
&break_invalid_ssl_linkages($d);

# Copy SSL directives to domains using same cert
foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
	next if (!&domain_has_ssl_cert($od));
	$od->{'ssl_cert'} = $d->{'ssl_cert'};
	$od->{'ssl_key'} = $d->{'ssl_key'};
	$od->{'ssl_chain'} = $d->{'ssl_chain'};
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

# Turn off any let's encrypt renewal
&disable_letsencrypt_renewal($d);

# Run the after command
&set_domain_envs($d, "SSL_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

&run_post_actions();
&webmin_log("newkey", "domain", $d->{'dom'}, $d);

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	 	 &domain_footer_link($d),
		 "", $text{'index_return'});

