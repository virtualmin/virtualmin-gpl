#!/usr/local/bin/perl
# newkey.cgi
# Install a new SSL cert and key

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});

# Validate inputs
&error_setup($text{'newkey_err'});
$cert = $in{'cert'} || $in{'certupload'};
if ($in{'newkey_def'}) {
	$newkey = &read_file_contents($d->{'ssl_key'});
	}
else {
	$newkey = $in{'newkey'} || $in{'newkeyupload'};
	}
$cert =~ s/\r//g;
$newkey =~ s/\r//g;
$err = &validate_cert_format($cert, "cert");
$err && &error(&text('newkey_ecert2', $err));
$err = &validate_cert_format($newkey, "key");
$err && &error(&text('newkey_enewkey2', $err));

# Check if a passphrase is needed
$passok = &check_passphrase($newkey, $in{'pass_def'} ? undef : $in{'pass'});
$passok || &error($text{'newkey_epass'});

# Check that the cert and key match
$certerr = &check_cert_key_match($cert, $newkey);
$certerr && &error(&text('newkey_ematch', $certerr));

&ui_print_header(&domain_in($d), $text{'newkey_title'}, "");

# Break SSL linkages that no longer work with this cert
$temp = &transname();
&open_tempfile(TEMP, ">$temp", 0, 1);
&print_tempfile(TEMP, $cert);
&close_tempfile(TEMP);
$newcertinfo = &cert_file_info($temp);
&break_invalid_ssl_linkages($d, $newcertinfo);
&unlink_file($temp);

# Make sure Apache is setup to use the right key files
&obtain_lock_ssl($d);
$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});
&save_website_ssl_file($d, "key", $d->{'ssl_key'});

# If a passphrase is needed, add it to the top-level Apache config. This is
# done by creating a small script that outputs the passphrase
$d->{'ssl_pass'} = $passok == 2 ? $in{'pass'} : undef;
&save_domain_passphrase($d);

# Save the cert and private keys
&$first_print($text{'newkey_saving'});
&lock_file($d->{'ssl_cert'});
&unlink_file($d->{'ssl_cert'});
&open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_cert'}");
&print_tempfile(CERT, $cert);
&close_tempfile_as_domain_user($d, CERT);
&set_certificate_permissions($d, $d->{'ssl_cert'});
&unlock_file($d->{'ssl_cert'});

&lock_file($d->{'ssl_key'});
&unlink_file($d->{'ssl_key'});
&open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_key'}");
&print_tempfile(CERT, $newkey);
&close_tempfile_as_domain_user($d, CERT);
&set_certificate_permissions($d, $d->{'ssl_key'});
&unlock_file($d->{'ssl_key'});
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

# For domains that were using the SSL cert on this domain originally but
# can no longer due to the cert hostname changing, break the linkage
&break_invalid_ssl_linkages($d);

# Copy SSL directives to domains using same cert
foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
	$od->{'ssl_cert'} = $d->{'ssl_cert'};
	$od->{'ssl_key'} = $d->{'ssl_key'};
	$od->{'ssl_newkey'} = $d->{'ssl_newkey'};
	$od->{'ssl_csr'} = $d->{'ssl_csr'};
	$od->{'ssl_pass'} = $d->{'ssl_pass'};
	&save_domain_passphrase($od);
	&save_domain($od);
	}

&run_post_actions();
&webmin_log("newkey", "domain", $d->{'dom'}, $d);

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	 	 &domain_footer_link($d),
		 "", $text{'index_return'});

