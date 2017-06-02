# Functions for copying SSL certs to other servers

# get_all_service_ssl_certs(&domain, include-per-ip-certs)
# Returns a list of all SSL certs used by global services like Postfix
# XXX include per-IP webmin and usermin certs
sub get_all_service_ssl_certs
{
my ($d, $perip) = @_;
my @svcs;

&foreign_require("webmin");
my %miniserv;
&get_miniserv_config(\%miniserv);
if ($miniserv{'ssl'}) {
	my ($cfile, $chain, $ip, $dom);
	if ($perip) {
		# Check for per-IP or per-domain cert first
		my @ipkeys = &webmin::get_ipkeys(\%miniserv);
		($cfile, $chain, $ip, $dom) =
			&ipkeys_to_domain_cert($d, \@ipkeys);
		}
	if (!$cfile) {
		# Fall back to global config
		$cfile = $miniserv{'certfile'};
		$chain = $miniserv{'extracas'};
		}
	push(@svcs, { 'id' => 'webmin',
		      'cert' => $cfile,
		      'ca' => $chain,
		      'ip' => $ip,
		      'dom' => $dom,
		      'prefix' => 'admin',
		      'port' => $miniserv{'port'} });
	}

if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	my %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	if ($uminiserv{'ssl'}) {
		my ($cfile, $chain, $ip, $dom);
		if ($perip) {
			# Check for per-IP or per-domain cert first
			my @ipkeys = &webmin::get_ipkeys(\%uminiserv);
			($cfile, $chain, $ip, $dom) =
				&ipkeys_to_domain_cert($d, \@ipkeys);
			}
		if (!$cfile) {
			# Fall back to global config
			$cfile = $uminiserv{'certfile'};
			$chain = $uminiserv{'extracas'};
			}
		push(@svcs, { 'id' => 'usermin',
			      'cert' => $cfile,
			      'ca' => $chain,
			      'ip' => $ip,
			      'dom' => $dom,
			      'prefix' => 'webmail',
			      'port' => $uminiserv{'port'} });
		}
	}
if (&foreign_installed("dovecot")) {
	my ($cfile, $kfile, $ip, $dom);
	if ($perip) {
		# Try per-IP cert first
		($cfile, $kfile, undef, $ip, $dom) = &get_dovecot_ssl_cert($d);
		}
	if (!$cfile) {
		# Fall back to global Dovecot cert
		&foreign_require("dovecot");
		my $conf = &dovecot::get_config();
		$cfile = &dovecot::find_value("ssl_cert_file", $conf) ||
			 &dovecot::find_value("ssl_cert", $conf, 0, "");
		$cfile =~ s/^<//;
		}
	if ($cfile) {
		push(@svcs, { 'id' => 'dovecot',
			      'cert' => $cfile,
			      'ca' => 'none',
			      'prefix' => 'mail',
			      'port' => 993,
			      'ip' => $ip,
			      'dom' => $dom, });
		}
	}
if ($config{'mail_system'} == 0) {
	my ($cfile, $kfile, $cafile, $ip);
	if ($perip) {
		# Try per-IP cert first
		($cfile, $kfile, $cafile, $ip) = &get_postfix_ssl_cert($d);
		}
	if (!$cfile) {
		&foreign_require("postfix");
		$cfile = &postfix::get_real_value("smtpd_tls_cert_file");
		$cafile = &postfix::get_real_value("smtpd_tls_CAfile");
		}
	if ($cfile) {
		push(@svcs, { 'id' => 'postfix',
			      'cert' => $cfile,
			      'ca' => $cafile,
			      'prefix' => 'mail',
			      'port' => 587,
			      'ip' => $ip, });
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

# ipkeys_to_domain_cert(&domain, &ipkeys)
# Returns the cert, chain file, IP and domain for a matching ipkeys entry
sub ipkeys_to_domain_cert
{
my ($d, $ipkeys) = @_;
foreach my $k (@$ipkeys) {
	if (&indexof($d->{'dom'}, @{$k->{'ips'}}) >= 0) {
		return ($k->{'cert'}, $k->{'extracas'}, undef, $d->{'dom'});
		}
	if ($d->{'virt'} &&
	    &indexof($d->{'ip'}, @{$k->{'ips'}}) >= 0) {
		return ($k->{'cert'}, $k->{'extracas'}, $d->{'ip'}, undef);
		}
	}
return ( );
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
$cfile =~ s/^<//;
$kfile =~ s/^<//;
if ($cfile =~ /snakeoil/) {
	# Hack to not use shared cert file on Ubuntu / Debian
	$cfile = $kfile = $cafile = undef;
	}
$cfile ||= "$dovedir/dovecot.cert.pem";
$kfile ||= "$dovedir/dovecot.key.pem";

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
if ($cadata) {
	&print_tempfile(CERT, $cadata,"\n");
	}
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0750, $cfile);
&open_lock_tempfile(KEY, ">$kfile");
&print_tempfile(KEY, $kdata,"\n");
&close_tempfile(KEY);
&set_ownership_permissions(undef, undef, 0750, $kfile);

# Update config with correct files
if (&dovecot::find_value("ssl_cert", $conf, 2)) {
	# 2.0 and later format
	&dovecot::save_directive($conf, "ssl_cert", "<".$cfile);
	&dovecot::save_directive($conf, "ssl_key", "<".$kfile);
	}
else {
	# Pre-2.0 format
	&dovecot::save_directive($conf, "ssl_cert_file", $cfile);
	&dovecot::save_directive($conf, "ssl_key_file", $kfile);
	}
&$second_print(&text($cadata ? 'copycert_dsaved2' : 'copycert_dsaved',
		     "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

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

# copy_postfix_ssl_service(&domain)
# Copy a domain's SSL cert to Postfix
sub copy_postfix_ssl_service
{
my ($d) = @_;

# Get the Postfix config and cert files
&foreign_require("postfix");
my $cfile = &postfix::get_real_value("smtpd_tls_cert_file");
my $kfile = &postfix::get_real_value("smtpd_tls_key_file");
my $cafile = &postfix::get_real_value("smtpd_tls_CAfile");
my $cdir = &postfix::guess_config_dir();
if ($cfile =~ /snakeoil/) {
	# Hack to not use shared cert file on Ubuntu / Debian
	$cfile = $kfile = $cafile = undef;
	}
$cfile ||= "$cdir/postfix.cert.pem";
$kfile ||= "$cdir/postfix.key.pem";
$cafile ||= "$cdir/postfix.ca.pem";

# Copy cert into those files
my $casrcfile = &get_website_ssl_file($d, "ca");
&$first_print($casrcfile ? $text{'copycert_psaving2'}
			 : $text{'copycert_psaving'});
my $cdata = &cert_pem_data($d);
my $kdata = &key_pem_data($d);
my $cadata = $casrcfile ? &read_file_contents($casrcfile) : undef;
$cdata || &error($text{'copycert_ecert'});
$kdata || &error($text{'copycert_ekey'});
&open_lock_tempfile(CERT, ">$cfile");
&print_tempfile(CERT, $cdata,"\n");
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0700, $cfile);
if ($cfile eq $kfile) {
	&open_lock_tempfile(KEY, ">>$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	}
else {
	&open_lock_tempfile(KEY, ">$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	&set_ownership_permissions(undef, undef, 0700, $kfile);
	}
if ($cadata) {
	&open_lock_tempfile(CA, ">$cafile");
	&print_tempfile(CA, $cadata,"\n");
	&close_tempfile(CA);
	&set_ownership_permissions(undef, undef, 0750, $cafile);
	}

# Update config with correct files
&postfix::set_current_value("smtpd_tls_cert_file", $cfile);
&postfix::set_current_value("smtpd_tls_key_file", $kfile);
&postfix::set_current_value("smtpd_tls_CAfile", $cadata ? $cafile : undef);
&$second_print(&text('copycert_dsaved', "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_penabling'});
if ($postfix::postfix_version >= 2.3) {
	&postfix::set_current_value("smtpd_tls_security_level", "may");
	}
else {
	&postfix::set_current_value("smtpd_use_tls", "yes");
	}
&postfix::set_current_value("smtpd_tls_mandatory_protocols", "SSLv3, TLSv1");
&postfix::set_current_value("smtpd_tls_mandatory_ciphers", "high");
&lock_file($postfix::config{'postfix_master'});
my $master = &postfix::get_master_config();
my ($smtps) = grep { $_->{'name'} eq 'smtps' } @$master;
my ($smtp) = grep { $_->{'name'} eq 'smtp' } @$master;
if ($smtps && !$smtps->{'enabled'}) {
	# Enable existing entry
	$smtps->{'enabled'} = 1;
	&postfix::modify_master($smtps);
	}
elsif (!$smtps && $smtp) {
	# Add new smtps entry, cloned from smtp
	$smtps = { %$smtp };
	$smtps->{'name'} = 'smtps';
	$smtps->{'command'} .= " -o smtpd_tls_wrappermode=yes";
	&postfix::create_master($smtps);
	}
&unlock_file($postfix::config{'postfix_master'});
&$second_print($text{'setup_done'});

# Apply Postfix config
&postfix::reload_postfix();
}

# copy_proftpd_ssl_service(&domain)
# Copy a domain's SSL cert to Proftpd
sub copy_proftpd_ssl_service
{
my ($d) = @_;

# Get the ProFTPd config and cert files
&foreign_require("proftpd");
&proftpd::lock_proftpd_files();
my $conf = &proftpd::get_config();
my $cfile = &proftpd::find_directive("TLSRSACertificateFile", $conf);
my $kfile = &proftpd::find_directive("TLSRSACertificateKeyFile", $conf);
my $cafile = &proftpd::find_directive("TLSCACertificateFile", $conf);
my $cdir = $proftpd::config{'proftpd_conf'};
$cdir =~ s/\/[^\/]+$//;
$cfile ||= "$cdir/proftpd.cert";
$kfile ||= "$cdir/proftpd.key";
$cafile ||= "$cdir/proftpd.ca";

# Copy cert into those files
my $casrcfile = &get_website_ssl_file($d, "ca");
&$first_print($casrcfile ? $text{'copycert_fsaving2'}
			 : $text{'copycert_fsaving'});
my $cdata = &cert_pem_data($d);
my $kdata = &key_pem_data($d);
my $cadata = $casrcfile ? &read_file_contents($casrcfile) : undef;
$cdata || &error($text{'copycert_ecert'});
$kdata || &error($text{'copycert_ekey'});
&open_lock_tempfile(CERT, ">$cfile");
&print_tempfile(CERT, $cdata,"\n");
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0700, $cfile);
if ($cfile eq $kfile) {
	&open_lock_tempfile(KEY, ">>$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	}
else {
	&open_lock_tempfile(KEY, ">$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	&set_ownership_permissions(undef, undef, 0700, $kfile);
	}
if ($cadata) {
	&open_lock_tempfile(CA, ">$cafile");
	&print_tempfile(CA, $cadata,"\n");
	&close_tempfile(CA);
	&set_ownership_permissions(undef, undef, 0750, $cafile);
	}

# Update config with correct files
&proftpd::save_directive("TLSRSACertificateFile", [ $cfile ], $conf, $conf);
&proftpd::save_directive("TLSRSACertificateKeyFile", [ $kfile ], $conf, $conf);
&proftpd::save_directive("TLSCACertificateFile", $cadata ? [ $cafile ] : [ ],
			 $conf, $conf);
&$second_print(&text('copycert_dsaved', "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_fenabling'});
&proftpd::save_directive("TLSEngine", [ "on" ], $conf, $conf);
&flush_file_lines();
&proftpd::unlock_proftpd_files();
&register_post_action(\&restart_proftpd);
&$second_print($text{'setup_done'});
}

# copy_webmin_ssl_service(&domain)
# Copy a domain's SSL cert to Webmin
sub copy_webmin_ssl_service
{
my ($d) = @_;
my $homecert = &is_under_directory($d->{'home'}, $d->{'ssl_cert'});

# Copy to appropriate config dir
my $dir = $config_directory;
&$first_print(&text('copycert_webmindir', "<tt>$dir</tt>"));
my $certfile;
if ($homecert) {
	$certfile = "$dir/$d->{'dom'}.cert";
	&lock_file($certfile);
	&copy_source_dest($d->{'ssl_cert'}, $certfile);
	&unlock_file($certfile);
	}
else {
	$certfile = $d->{'ssl_cert'};
	}
if ($d->{'ssl_key'}) {
	if ($homecert) {
		$keyfile = "$dir/$d->{'dom'}.key";
		&lock_file($keyfile);
		&copy_source_dest($d->{'ssl_key'}, $keyfile);
		&unlock_file($keyfile);
		}
	else {
		$keyfile = $d->{'ssl_key'};
		}
	}
if ($d->{'ssl_chain'}) {
	if ($homecert) {
		$chainfile = "$dir/$d->{'dom'}.chain";
		&lock_file($chainfile);
		&copy_source_dest($d->{'ssl_chain'}, $chainfile);
		&unlock_file($chainfile);
		}
	else {
		$chainfile = $d->{'ssl_chain'};
		}
	}
&$second_print($text{'setup_done'});

# Configure Webmin to use it
&$first_print($text{'copycert_webminconfig'});
&lock_file($ENV{'MINISERV_CONFIG'});
&get_miniserv_config(\%miniserv);
$miniserv{'certfile'} = $certfile;
$miniserv{'keyfile'} = $keyfile;
$miniserv{'extracas'} = $chainfile;
&put_miniserv_config(\%miniserv);
&unlock_file($ENV{'MINISERV_CONFIG'});
&restart_miniserv();
&$second_print($text{'setup_done'});

# Tell the user if not in SSL mode
if (!$miniserv{'ssl'}) {
	&$second_print(&text('copycert_webminnot',
			     "../webmin/edit_ssl.cgi"));
	}
}

# copy_usermin_ssl_service(&domain)
# Copy a domain's SSL cert to Usermin
sub copy_usermin_ssl_service
{
my ($d) = @_;

# Copy to appropriate config dir
&foreign_require("usermin");
my $dir = $usermin::config{'usermin_dir'};
&$first_print(&text('copycert_webmindir', "<tt>$dir</tt>"));
$certfile = "$dir/$d->{'dom'}.cert";
&lock_file($certfile);
&copy_source_dest($d->{'ssl_cert'}, $certfile);
&unlock_file($certfile);
if ($d->{'ssl_key'}) {
	$keyfile = "$dir/$d->{'dom'}.key";
	&lock_file($keyfile);
	&copy_source_dest($d->{'ssl_key'}, $keyfile);
	&unlock_file($keyfile);
	}
if ($d->{'ssl_chain'}) {
	$chainfile = "$dir/$d->{'dom'}.chain";
	&lock_file($chainfile);
	&copy_source_dest($d->{'ssl_chain'}, $chainfile);
	&unlock_file($chainfile);
	}
&$second_print($text{'setup_done'});

# Configure Usermin to use it
&$first_print($text{'copycert_userminconfig'});
&lock_file($usermin::usermin_miniserv_config);
&usermin::get_usermin_miniserv_config(\%miniserv);
$miniserv{'certfile'} = $certfile;
$miniserv{'keyfile'} = $keyfile;
$miniserv{'extracas'} = $chainfile;
&usermin::put_usermin_miniserv_config(\%miniserv);
&unlock_file($usermin::usermin_miniserv_config);
&usermin::restart_usermin_miniserv();
&$second_print($text{'setup_done'});

# Tell the user if not in SSL mode
if (!$miniserv{'ssl'}) {
	&$second_print(&text('copycert_userminnot',
			     "../usermin/edit_ssl.cgi"));
	}
}

1;
