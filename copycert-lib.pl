# Functions for copying SSL certs to other servers

# get_all_service_ssl_certs()
# Returns a list of all SSL certs used by global services like Postfix
sub get_all_service_ssl_certs
{
my %miniserv;
&get_miniserv_config(\%miniserv);
my @svcs;
if ($miniserv{'ssl'}) {
	push(@svcs, { 'id' => 'webmin',
		      'cert' => $miniserv{'certfile'},
		      'ca' => $miniserv{'extracas'},
		      'prefix' => 'admin',
		      'port' => $miniserv{'port'} });
	}
if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	my %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	if ($uminiserv{'ssl'}) {
		push(@svcs, { 'id' => 'usermin',
			      'cert' => $uminiserv{'certfile'},
			      'ca' => $uminiserv{'extracas'},
			      'prefix' => 'webmail',
			      'port' => $uminiserv{'port'} });
		}
	}
if (&foreign_installed("dovecot")) {
	&foreign_require("dovecot");
	my $conf = &dovecot::get_config();
	my $cfile = &dovecot::find_value("ssl_cert_file", $conf) ||
		    &dovecot::find_value("ssl_cert", $conf, 0, "");
	$cfile =~ s/^<//;
	my $cafile = &dovecot::find_value("ssl_ca_file", $conf) ||
		     &dovecot::find_value("ssl_ca", $conf, 0, "");
	$cafile =~ s/^<//;
	if ($cfile) {
		push(@svcs, { 'id' => 'dovecot',
			      'cert' => $cfile,
			      'ca' => $cafile,
			      'prefix' => 'mail',
			      'port' => 993, });
		}
	}
if ($config{'mail_system'} == 0) {
	&foreign_require("postfix");
	my $cfile = &postfix::get_real_value("smtpd_tls_cert_file");
	my $cafile = &postfix::get_real_value("smtpd_tls_CAfile");
	if ($cfile) {
		push(@svcs, { 'id' => 'postfix',
			      'cert' => $cfile,
			      'ca' => $cafile,
			      'prefix' => 'mail',
			      'port' => 587 });
		}
	}
if ($config{'ftp'}) {
	&foreign_require("proftpd");
	my $conf = &proftpd::get_config();
	my $cfile = &proftpd::find_directive(
			"TLSRSACertificateFile", $conf);
	my $cafile = &proftpd::find_directive(
			"TLSCACertificateFile", $conf);
	if ($cfile) {
		push(@svcs, { 'id' => 'proftpd',
			      'cert' => $cfile,
			      'ca' => $cafile,
			      'prefix' => 'ftp',
			      'port' => 990, });
		}
	}
return @svcs;
}

# copy_dovecot_ssl_service(&domain)
# Copy a domain's SSL cert to Dovecot
sub copy_dovecot_ssl_service
{
my ($d) = @_;

# Get the Dovecot config and cert files
&foreign_require("dovecot");
my $configfile = &dovecot::get_config_file();
&lock_file($configfile);
my $dovedir = $cfile;
$dovedir =~ s/\/([^\/]+)$//;
my $conf = &dovecot::get_config();
my $cfile = &dovecot::find_value("ssl_cert_file", $conf) ||
	 &dovecot::find_value("ssl_cert", $conf, 0, "");
my $kfile = &dovecot::find_value("ssl_key_file", $conf) ||
	 &dovecot::find_value("ssl_key", $conf, 0, "");
my $cafile = &dovecot::find_value("ssl_ca_file", $conf) ||
	  &dovecot::find_value("ssl_ca", $conf, 0, "");
$cfile =~ s/^<//;
$kfile =~ s/^<//;
$cafile =~ s/^<//;
if ($cfile =~ /snakeoil/) {
	# Hack to not use shared cert file on Ubuntu / Debian
	$cfile = $kfile = $cafile = undef;
	}
$cfile ||= "$dovedir/dovecot.cert.pem";
$kfile ||= "$dovedir/dovecot.key.pem";
$cafile ||= "$dovedir/dovecot.ca.pem";

# Copy cert into those files
&$first_print($text{'copycert_dsaving'});
my $cdata = &cert_pem_data($d);
my $kdata = &key_pem_data($d);
my $casrcfile = &get_website_ssl_file($d, "ca");
$cadata = $casrcfile ? &read_file_contents($casrcfile) : undef;
$cdata || &error($text{'copycert_ecert'});
$kdata || &error($text{'copycert_ekey'});
&open_lock_tempfile(CERT, ">$cfile");
&print_tempfile(CERT, $cdata,"\n");
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0750, $cfile);
&open_lock_tempfile(KEY, ">$kfile");
&print_tempfile(KEY, $kdata,"\n");
&close_tempfile(KEY);
&set_ownership_permissions(undef, undef, 0750, $kfile);
if ($cadata) {
	&open_lock_tempfile(CA, ">$cafile");
	&print_tempfile(CA, $cadata,"\n");
	&close_tempfile(CA);
	&set_ownership_permissions(undef, undef, 0750, $cafile);
	}

# Update config with correct files
if (&dovecot::find_value("ssl_cert", $conf, 2)) {
	# 2.0 and later format
	&dovecot::save_directive($conf, "ssl_cert", "<".$cfile);
	&dovecot::save_directive($conf, "ssl_key", "<".$kfile);
	if ($cadata) {
		&dovecot::save_directive($conf, "ssl_ca", "<".$cafile);
		}
	else {
		&dovecot::save_directive($conf, "ssl_ca", undef);
		}
	}
else {
	# Pre-2.0 format
	&dovecot::save_directive($conf, "ssl_cert_file", $cfile);
	&dovecot::save_directive($conf, "ssl_key_file", $kfile);
	if ($cadata) {
		&dovecot::save_directive($conf, "ssl_ca_file", $cafile);
		}
	else {
		&dovecot::save_directive($conf, "ssl_ca_file", undef);
		}
	}
&$second_print(&text($cadata ? 'copycert_dsaved2' : 'copycert_dsaved',
		     "<tt>$cfile</tt>", "<tt>$kfile</tt>", "<tt>$cafile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_denabling'});
if (&dovecot::find("ssl_disable", $conf, 2)) {
	&dovecot::save_directive($conf, "ssl_disable", "no");
	}
else {
	&dovecot::save_directive($conf, "ssl", "yes");
	}
if (&dovecot::get_dovecot_version() < 2) {
	# Add imaps and pop3s protocols ..
	$protos = &dovecot::find_value("protocols", $conf);
	@protos = split(/\s+/, $protos);
	%protos = map { $_, 1 } @protos;
	push(@protos, "imaps") if (!$protos{'imaps'} && $protos{'imap'});
	push(@protos, "pop3s") if (!$protos{'pop3s'} && $protos{'pop3'});
	&dovecot::save_directive($conf, "protocols", join(" ", @protos));
	}

# Enable PCI-compliant ciphers
&foreign_require("webmin");
if (!&dovecot::find_value("ssl_cipher_list", $conf)) {
	&dovecot::save_directive($conf, "ssl_cipher_list",
				 $webmin::strong_ssl_ciphers ||
				   "HIGH:MEDIUM:+TLSv1:!SSLv2:+SSLv3");
	}

&flush_file_lines();
&unlock_file($configfile);
&$second_print($text{'setup_done'});

# Apply Dovecot config
&dovecot::apply_configuration();
}

1;
