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
$size = $in{'size_def'} ? $webmin::default_key_size : $in{'size'};

if (!$in{'self'}) {
	# Generate the private key
	$d->{'ssl_csr'} ||= "$d->{'home'}/ssl.csr";
	$d->{'ssl_newkey'} ||= "$d->{'home'}/ssl.newkey";
	&lock_file($d->{'ssl_newkey'});
	&unlink_file($d->{'ssl_newkey'});
	$out = &backquote_logged("openssl genrsa -out ".quotemeta($d->{'ssl_newkey'})." $size 2>&1 </dev/null");
	$rv = $?;
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755, $d->{'ssl_newkey'});
	&unlock_file($d->{'ssl_newkey'});
	if (!-r $d->{'ssl_newkey'} || $rv) {
		&error(&text('csr_ekey', "<pre>$out</pre>"));
		}

	# Generate the CSR
	$outtemp = &transname();
	&lock_file($d->{'ssl_csr'});
	&unlink_file($d->{'ssl_csr'});
	&open_execute_command(CA, "openssl req -new -key ".quotemeta($d->{'ssl_newkey'})." -out ".quotemeta($d->{'ssl_csr'})." >$outtemp 2>&1", 0);
	print CA ($in{'countryName'} || "."),"\n";
	print CA ($in{'stateOrProvinceName'} || "."),"\n";
	print CA ($in{'cityName'} || "."),"\n";
	print CA ($in{'organizationName'} || "."),"\n";
	print CA ($in{'organizationalUnitName'} || "."),"\n";
	print CA ($in{'commonName_def'} ? "*" : $in{'commonName'}),"\n";
	print CA ($in{'emailAddress'} || "."),"\n";
	print CA ".\n";
	print CA ".\n";
	close(CA);
	$rv = $?;
	$out = `cat $outtemp`;
	unlink($outtemp);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0750,
				   $d->{'ssl_csr'});
	&unlock_file($d->{'ssl_csr'});
	if (!-r $d->{'ssl_csr'} || $rv) {
		&error(&text('csr_ecsr', "<pre>$out</pre>"));
		}

	# Save the domain
	&save_domain($d);
	&run_post_actions();

	# Show the output
	&ui_print_header(&domain_in($d), $text{'csr_title'}, "");

	print "$text{'csr_done'}<p>\n";

	print &text('csr_csr', "<tt>$d->{'ssl_csr'}</tt>"),"\n";
	print "<pre>",`cat $d->{'ssl_csr'}`,"</pre>\n";

	print &text('csr_key', "<tt>$d->{'ssl_newkey'}</tt>"),"\n";
	print "<pre>",`cat $d->{'ssl_newkey'}`,"</pre>\n";
	}
else {
	# Create key file
	$ctemp = &transname();
	$ktemp = &transname();
	$outtemp = &transname();
	&open_execute_command(CA, "openssl req -newkey rsa:$size -x509 -nodes -out $ctemp -keyout $ktemp -days $in{'days'} >$outtemp 2>&1", 0);
	print CA ($in{'countryName'} || "."),"\n";
	print CA ($in{'stateOrProvinceName'} || "."),"\n";
	print CA ".\n";
	print CA ($in{'organizationName'} || "."),"\n";
	print CA ($in{'organizationalUnitName'} || "."),"\n";
	print CA ($in{'commonName_def'} ? "*" : $in{'commonName'}),"\n";
	print CA ($in{'emailAddress'} || "."),"\n";
	close(CA);
	$rv = $?;
	$out = `cat $outtemp`;
	unlink($outtemp);
	if (!-r $ctemp || !-r $ktemp || $?) {
		&error(&text('csr_ekey', "<pre>$out</pre>"));
		}

	&ui_print_header(&domain_in($d), $text{'csr_title2'}, "");
	
	# Make sure Apache is setup to use the right key files
	&require_apache();
	$conf = &apache::get_config();
	($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					      $d->{'web_sslport'});
	$d->{'ssl_cert'} ||= "$d->{'home'}/ssl.cert";
	$d->{'ssl_key'} ||= "$d->{'home'}/ssl.key";
	&lock_file($virt->{'file'});
	&apache::save_directive("SSLCertificateFile", [ $d->{'ssl_cert'} ],
				$vconf, $conf);
	&apache::save_directive("SSLCertificateKeyFile", [ $d->{'ssl_key'} ],
				$vconf, $conf);
	&flush_file_lines();
	&unlock_file($virt->{'file'});

	# Save the cert and private keys
	&$first_print($text{'newkey_saving'});
	&unlink_logged($d->{'ssl_cert'});
	&lock_file($d->{'ssl_cert'});
	&system_logged("mv ".quotemeta($ctemp)." ".quotemeta($d->{'ssl_cert'}));
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0750, $d->{'ssl_cert'});
	&unlock_file($d->{'ssl_cert'});

	&unlink_logged($d->{'ssl_key'});
	&lock_file($d->{'ssl_key'});
	&system_logged("mv ".quotemeta($ktemp)." ".quotemeta($d->{'ssl_key'}));
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0750, $d->{'ssl_key'});
	&unlock_file($d->{'ssl_key'});
	&$second_print($text{'setup_done'});

	# Re-start Apache
	&register_post_action(\&restart_apache, 1);
	&run_post_actions();
	&webmin_log("newself", "domain", $d->{'dom'}, $d);
	}

&ui_print_footer("cert_form.cgi?dom=$in{'dom'}", $text{'cert_return'},
	&domain_footer_link($d),
	"", $text{'index_return'});
