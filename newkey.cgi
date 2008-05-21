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
$newkey = $in{'newkey'} || $in{'newkeyupload'};
$cert =~ /BEGIN CERTIFICATE/ &&
  $cert =~ /END CERTIFICATE/ || &error($text{'newkey_ecert'});
$newkey =~ /BEGIN RSA PRIVATE KEY/ &&
  $newkey =~ /END RSA PRIVATE KEY/ || &error($text{'newkey_enewkey'});

&ui_print_header(&domain_in($d), $text{'newkey_title'}, "");

# Make sure Apache is setup to use the right key files
&require_apache();
$conf = &apache::get_config();
($virt, $vconf) = &get_apache_virtual($d->{'dom'},
                                      $d->{'web_sslport'});

$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
&lock_file($virt->{'file'});
&apache::save_directive("SSLCertificateFile", [ $d->{'ssl_cert'} ],
			$vconf, $conf);
&apache::save_directive("SSLCertificateKeyFile", [ $d->{'ssl_key'} ],
			$vconf, $conf);
&flush_file_lines();
&unlock_file($virt->{'file'});

# Save the cert and private keys
&$first_print($text{'newkey_saving'});
&lock_file($d->{'ssl_cert'});
&unlink_file($d->{'ssl_cert'});
&open_tempfile(CERT, ">$d->{'ssl_cert'}");
$cert =~ s/\r//g;
&print_tempfile(CERT, $cert);
&close_tempfile(CERT);
&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0750, $d->{'ssl_cert'});
&unlock_file($d->{'ssl_cert'});

&lock_file($d->{'ssl_key'});
&unlink_file($d->{'ssl_key'});
&open_tempfile(CERT, ">$d->{'ssl_key'}");
$newkey =~ s/\r//g;
&print_tempfile(CERT, $newkey);
&close_tempfile(CERT);
&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0750, $d->{'ssl_key'});
&unlock_file($d->{'ssl_key'});
&$second_print($text{'setup_done'});

# Remove the new private key we just installed
if ($d->{'ssl_newkey'}) {
	$newkeyfile = &read_file_contents($d->{'ssl_newkey'});
	if ($newkeyfile eq $newkey) {
		&unlink_logged($d->{'ssl_newkey'});
		delete($d->{'ssl_newkey'});
		&save_domain($d);
		}
	}

# Re-start Apache
&register_post_action(\&restart_apache, 1);
&run_post_actions();
&webmin_log("newkey", "domain", $d->{'dom'}, $d);

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	 	 &domain_footer_link($d),
		 "", $text{'index_return'});

