# Functions for copying SSL certs to other servers

# list_service_ssl_cert_types()
# Returns a list of services to which per-domain or per-IP certs can be copied
sub list_service_ssl_cert_types
{
my @rv;
my %miniserv;
&get_miniserv_config(\%miniserv);
push(@rv, {'id' => 'webmin',
	   'dom' => 1,
	   'virt' => 1,
	   'port' => $miniserv{'port'},
	   'short' => '' });
if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	my %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	push(@rv, {'id' => 'usermin',
		   'dom' => 1,
		   'virt' => 1,
		   'port' => $uminiserv{'port'},
		   'short' => 'u' });
	}
if (&foreign_installed("dovecot")) {
	push(@rv, {'id' => 'dovecot',
		   'dom' => 1,
		   'virt' => 1,
		   'short' => 'd' });
	}
if ($config{'mail'} && $mail_system == 0) {
	push(@rv, {'id' => 'postfix',
		   'dom' => &postfix_supports_sni() ? 1 : 0,
		   'virt' => 1,
		   'short' => 'p' });
	}
if ($config{'ftp'} || &foreign_installed("proftpd")) {
	push(@rv, {'id' => 'proftpd',
		   'dom' => 0,
		   'virt' => 1,
		   'short' => 'f' });
	}
if ($config{'mysql'}) {
	push(@rv, {'id' => 'mysql',
		   'dom' => 0,
		   'virt' => 0,
		   'short' => 'm' });
	}
foreach my $rv (@rv) {
	$rv->{'desc'} ||= $text{'cert_service_'.$rv->{'id'}};
	}
return @rv;
}

# get_all_service_ssl_certs(&domain, include-per-ip-certs)
# Returns a list of all SSL certs used by global services like Postfix
sub get_all_service_ssl_certs
{
my ($d, $perip) = @_;
my @svcs;

&foreign_require("webmin");
my %miniserv;
&get_miniserv_config(\%miniserv);
if ($miniserv{'ssl'}) {
	# Check Webmin certificate
	if ($perip) {
		# Check for per-IP or per-domain cert first
		my @ipkeys = &webmin::get_ipkeys(\%miniserv);
		my ($cfile, $chain, $ip, $dom, $kfile) =
			&ipkeys_to_domain_cert($d, \@ipkeys);
		if ($cfile) {
			push(@svcs, { 'id' => 'webmin',
				      'cert' => $cfile,
				      'key' => $kfile,
				      'ca' => $chain,
				      'ip' => $ip,
				      'dom' => $dom,
				      'd' => $d,
				      'prefix' => 'admin',
				      'port' => $miniserv{'port'} });
			}
		}
	# Also add global config
	my $kfile = $miniserv{'keyfile'};
	my $cfile = $miniserv{'certfile'};
	my $chain = $miniserv{'extracas'};
	push(@svcs, { 'id' => 'webmin',
		      'cert' => $cfile,
		      'key' => $kfile,
		      'ca' => $chain,
		      'prefix' => 'admin',
		      'port' => $miniserv{'port'} });
	}

if (&foreign_installed("usermin")) {
	# Check Usermin certificate
	&foreign_require("usermin");
	my %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	if ($uminiserv{'ssl'}) {
		my ($cfile, $chain, $ip, $dom);
		if ($perip) {
			# Check for per-IP or per-domain cert first
			my @ipkeys = &webmin::get_ipkeys(\%uminiserv);
			my ($cfile, $chain, $ip, $dom, $kfile) =
				&ipkeys_to_domain_cert($d, \@ipkeys);
			if ($cfile) {
				push(@svcs, { 'id' => 'usermin',
					      'cert' => $cfile,
					      'key' => $kfile,
					      'ca' => $chain,
					      'ip' => $ip,
					      'dom' => $dom,
					      'd' => $d,
					      'prefix' => 'webmail',
					      'port' => $uminiserv{'port'} });
				}
			}
		# Also add global config
		my $cfile = $uminiserv{'certfile'};
		my $kfile = $uminiserv{'keyfile'};
		my $chain = $uminiserv{'extracas'};
		push(@svcs, { 'id' => 'usermin',
			      'cert' => $cfile,
			      'key' => $kfile,
			      'ca' => $chain,
			      'prefix' => 'webmail',
			      'port' => $uminiserv{'port'} });
		}
	}

if (&foreign_installed("dovecot")) {
	# Check Dovecot certificate
	if ($perip) {
		# Try per-IP cert first
		my ($cfile, $kfile, $cafile, $ip, $dom) =
			&get_dovecot_ssl_cert($d);
		if ($cfile) {
			if (!$cafile && &cert_file_split($cfile) > 1) {
				# CA cert might be in the cert file
				$cafile = $cfile;
				}
			push(@svcs, { 'id' => 'dovecot',
				      'cert' => $cfile,
				      'key' => $kfile,
				      'ca' => $cafile,
				      'prefix' => 'mail',
				      'port' => 993,
				      'sslports' => [ 995 ],
				      'ip' => $ip,
				      'dom' => $dom,
				      'd' => $d, });
			}
		}
	# Also add global Dovecot cert
	&foreign_require("dovecot");
	my $conf = &dovecot::get_config();
	my $cfile = &dovecot::find_value("ssl_cert_file", $conf, 0, "") ||
		    &dovecot::find_value("ssl_cert", $conf, 0, "");
	$cfile =~ s/^<//;
	my $kfile = &dovecot::find_value("ssl_key_file", $conf, 0, "") ||
		    &dovecot::find_value("ssl_key", $conf, 0, "");
	$kfile =~ s/^<//;
	$cafile = &dovecot::find_value("ssl_ca", $conf, 0, "");
	$cafile =~ s/^<//;
	if ($cfile) {
		if (!$cafile && &cert_file_split($cfile) > 1) {
			# CA cert might be in the cert file
			$cafile = $cfile;
			}
		push(@svcs, { 'id' => 'dovecot',
			      'cert' => $cfile,
			      'key' => $kfile,
			      'ca' => $cafile,
			      'prefix' => 'mail',
			      'port' => 993,
			      'sslports' => [ 995 ]});
		}
	}

if ($mail_system == 0) {
	# Check Postfix certificate
	if ($perip) {
		# Try per-IP cert first
		my ($cfile, $kfile, $cafile, $ip, $dom) =
			&get_postfix_ssl_cert($d);
		if ($cfile) {
			push(@svcs, { 'id' => 'postfix',
				      'cert' => $cfile,
				      'key' => $kfile,
				      'ca' => $cafile,
				      'prefix' => 'mail',
				      'port' => 587,
				      'sslports' => [ 25 ],
				      'ip' => $ip,
				      'dom' => $dom,
				      'd' => $d, });
			}
		}
	# Also add global Postfix cert
	&foreign_require("postfix");
	my $cfile = &postfix::get_real_value("smtpd_tls_cert_file");
	my $kfile = &postfix::get_real_value("smtpd_tls_key_file");
	my $cafile = &postfix::get_real_value("smtpd_tls_CAfile");
	if ($cfile) {
		push(@svcs, { 'id' => 'postfix',
			      'cert' => $cfile,
			      'key' => $kfile,
			      'ca' => $cafile,
			      'prefix' => 'mail',
			      'port' => 587,
			      'sslports' => [ 25 ],
			      'ip' => $ip, });
		}
	}

if ($config{'ftp'} || &foreign_installed("proftpd")) {
	# Check ProFTPd per-IP certificate
	&foreign_require("proftpd");
	my $conf = &proftpd::get_config();
	if ($perip) {
		my ($virt, $vconf) = &get_proftpd_virtual($d);
		if ($virt) {
			my $cfile = &proftpd::find_directive(
					"TLSRSACertificateFile", $vconf);
			my $kfile = &proftpd::find_directive(
					"TLSRSACertificateKeyFile", $vconf);
			my $cafile = &proftpd::find_directive(
					"TLSCACertificateFile", $vconf);
			if ($cfile) {
				push(@svcs, { 'id' => 'proftpd',
					      'cert' => $cfile,
					      'key' => $kfile,
					      'ca' => $cafile,
					      'prefix' => 'ftp',
					      'port' => 990,
					      'ip' => $d->{'ip'},
					      'd' => $d,
					    });
				}
			}
		}

	# Check ProFTPd global certificate
	my $cfile = &proftpd::find_directive(
			"TLSRSACertificateFile", $conf);
	my $kfile = &proftpd::find_directive(
			"TLSRSACertificateKeyFile", $conf);
	my $cafile = &proftpd::find_directive(
			"TLSCACertificateFile", $conf);
	if ($cfile) {
		push(@svcs, { 'id' => 'proftpd',
			      'cert' => $cfile,
			      'key' => $kfile,
			      'ca' => $cafile,
			      'prefix' => 'ftp',
			      'port' => 990,
			    });
		}
	}

if ($config{'mysql'}) {
	# Check MySQL certificate
	&foreign_require("mysql");
	my $conf = &mysql::get_mysql_config();
	my ($mysqld) = grep { $_->{'name'} eq 'mysqld' } @$conf;
	my ($cert, $key, $ca);
	if ($mysqld) {
		my $mems = $mysqld->{'members'};
		$cert = &mysql::find_value("ssl_cert", $mems);
		$key = &mysql::find_value("ssl_key", $mems);
		$ca = &mysql::find_value("ssl_ca", $mems);
		}
	if ($cert) {
		push(@svcs, { 'id' => 'mysql',
			      'cert' => $cert,
			      'key' => $key,
			      'ca' => $ca,
			      'prefix' => 'mysql',
			      'port' => 3306, });
		}
	}

return @svcs;
}

# get_all_domain_service_ssl_certs(&domain)
# Returns certs that are using this domain's cert and key
sub get_all_domain_service_ssl_certs
{
my ($d) = @_;
my @rv;
my $chain = &get_website_ssl_file($d, 'ca');
foreach my $svc (&get_all_service_ssl_certs($d, 1)) {
	if ((&same_cert_file($d->{'ssl_cert'}, $svc->{'cert'}) ||
	     &same_cert_file($d->{'ssl_combined'}, $svc->{'cert'})) &&
	    (!$svc->{'ca'} || -s $svc->{'ca'} < 16 || $svc->{'ca'} eq 'none' ||
	     &same_cert_file_any($chain, $svc->{'ca'}))) {
		push(@rv, $svc);
		}
	}
return @rv;
}

# update_all_domain_service_ssl_certs(&domain, &certs-before)
# Updates all services that were using this domain's SSL cert after it has
# changed.
sub update_all_domain_service_ssl_certs
{
my ($d, $before) = @_;
my $tmpl = &get_template($d->{'template'});
&push_all_print();
&set_all_null_print();
foreach my $svc (@$before) {
	if ($tmpl->{'web_'.$svc->{'id'}.'_ssl'}) {
		if ($svc->{'d'}) {
			my $func = "sync_".$svc->{'id'}."_ssl_cert";
			&$func($d, 1) if (defined(&$func));
			}
		else {
			my $func = "copy_".$svc->{'id'}."_ssl_service";
			&$func($d) if (defined(&$func));
			}
		}
	}
&pop_all_print();
}

# enable_domain_service_ssl_certs(&domain)
# To be called when SSL is enabled for a domain, to setup all per-service SSL
# certs configured in the template that can be used.
sub enable_domain_service_ssl_certs
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
foreach my $svc (&list_service_ssl_cert_types()) {
	next if (!$svc->{'dom'} && !$svc->{'virt'});
	next if (!$svc->{'dom'} && !$d->{'virt'});
	if ($tmpl->{'web_'.$svc->{'id'}.'_ssl'}) {
		# Prevent applying service certificate on initial
		# service creation, like when calling 'setup_ssl'
		# for the first time, to prevent application of
		# default, potentially self-signed certificate
		if ($d->{"no_default_service_cert_$svc->{'id'}"}) {
			delete($d->{"no_default_service_cert_$svc->{'id'}"})
				if ($d->{"no_default_service_cert_$svc->{'id'}"} == 2);
			next;
			}
		my $func = "sync_".$svc->{'id'}."_ssl_cert";
		&$func($d, 1) if (defined(&$func));
		}
	}
}

# disable_domain_service_ssl_certs(&domain)
# To be called when SSL is turned off for a domain, to remove all per-service
# SSL certs.
sub disable_domain_service_ssl_certs
{
my ($d) = @_;
foreach my $svc (&get_all_service_ssl_certs($d, 1)) {
	if ($svc->{'d'}) {
		my $func = "sync_".$svc->{'id'}."_ssl_cert";
		&$func($d, 0) if (defined(&$func));
		}
	}
}

# ipkeys_to_domain_cert(&domain, &ipkeys)
# Returns the cert, chain file, IP, domain and key file for a matching
# ipkeys entry
sub ipkeys_to_domain_cert
{
my ($d, $ipkeys) = @_;
foreach my $k (@$ipkeys) {
	if (&indexof($d->{'dom'}, @{$k->{'ips'}}) >= 0) {
		return ($k->{'cert'}, $k->{'extracas'}, undef, $d->{'dom'},
			$k->{'key'});
		}
	if ($d->{'virt'} &&
	    &indexof($d->{'ip'}, @{$k->{'ips'}}) >= 0) {
		return ($k->{'cert'}, $k->{'extracas'}, $d->{'ip'}, undef,
			$k->{'key'});
		}
	}
return ( );
}

# copy_dovecot_ssl_service(&domain)
# Copy a domain's SSL cert to Dovecot for global use
sub copy_dovecot_ssl_service
{
my ($d) = @_;

# Get the Dovecot config and cert files
&foreign_require("dovecot");
my $configfile = &dovecot::get_config_file();
&lock_file($configfile);
my $dovedir = $configfile;
$dovedir =~ s/\/([^\/]+)$//;
my $conf = &dovecot::get_config();
my $v2 = &dovecot::find_value("ssl_cert", $conf, 2, "") ? 1 :
         &dovecot::find_value("ssl_cert_file", $conf, 2, "") ? 0 :
	 &dovecot::get_dovecot_version() >= 2 ? 1 : 0;
my $cfile = &dovecot::find_value("ssl_cert_file", $conf, 0, "") ||
	 &dovecot::find_value("ssl_cert", $conf, 0, "");
my $kfile = &dovecot::find_value("ssl_key_file", $conf, 0, "") ||
	 &dovecot::find_value("ssl_key", $conf, 0, "");
my $cafile = &dovecot::find_value("ssl_ca", $conf, 0, "");
$cfile =~ s/^<//;
$kfile =~ s/^<//;
$cafile =~ s/^<//;
if ($cfile =~ /snakeoil/) {
	# Hack to not use shared cert file on Ubuntu / Debian
	$cfile = $kfile = $cafile = undef;
	}
$cfile ||= "$dovedir/dovecot.cert.pem";
$kfile ||= "$dovedir/dovecot.key.pem";

# Break possible linkage to snakeoil cert and key
foreach my $file ($cfile, $kfile) {
    my $file_link = &resolve_links($file);
    if ($file ne $file_link) {
        &unlink_file($file);
        &copy_source_dest($file_link, $file);
        }
    }

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
if (!$cafile && $cadata) {
	# No CA file is already defined in the config, so just append to the
	# cert file
	&print_tempfile(CERT, $cadata,"\n");
	}
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0750, $cfile);
&open_lock_tempfile(KEY, ">$kfile");
&print_tempfile(KEY, $kdata,"\n");
&close_tempfile(KEY);
&set_ownership_permissions(undef, undef, 0750, $kfile);
if ($cafile && $cadata) {
	# CA file already exists, and should have contents. This mode is
	# deprecated, but can still happen with older configs
	&open_lock_tempfile(KEY, ">$cafile");
	&print_tempfile(KEY, $cadata,"\n");
	&close_tempfile(KEY);
	&set_ownership_permissions(undef, undef, 0750, $cafile);
	}

# Update config with correct files
if ($v2) {
	# 2.0 and later format
	&dovecot::save_directive($conf, "ssl_cert", "<".$cfile, "");
	&dovecot::save_directive($conf, "ssl_key", "<".$kfile, "");
	if ($cafile) {
		&dovecot::save_directive($conf, "ssl_ca", "<".$cafile, "");
		}
	}
else {
	# Pre-2.0 format
	&dovecot::save_directive($conf, "ssl_cert_file", $cfile, "");
	&dovecot::save_directive($conf, "ssl_key_file", $kfile, "");
	}
&$second_print(&text($cadata ? 'copycert_dsaved2' : 'copycert_dsaved',
		     "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_denabling'});
if (&dovecot::find("ssl_disable", $conf, 2)) {
	&dovecot::save_directive($conf, "ssl_disable", "no", "");
	}
else {
	&dovecot::save_directive($conf, "ssl", "yes", "");
	}
if (&dovecot::get_dovecot_version() < 2) {
	# Add imaps and pop3s protocols ..
	$protos = &dovecot::find_value("protocols", $conf, 0, "");
	@protos = split(/\s+/, $protos);
	%protos = map { $_, 1 } @protos;
	push(@protos, "imaps") if (!$protos{'imaps'} && $protos{'imap'});
	push(@protos, "pop3s") if (!$protos{'pop3s'} && $protos{'pop3'});
	&dovecot::save_directive($conf, "protocols", join(" ", @protos), "");
	}

# Enable PCI-compliant ciphers
&foreign_require("webmin");
if (!&dovecot::find_value("ssl_cipher_list", $conf, 0, "")) {
	&dovecot::save_directive($conf, "ssl_cipher_list",
				 $webmin::strong_ssl_ciphers, "");
	}

&flush_file_lines();
&unlock_file($configfile);
&$second_print($text{'setup_done'});

# Apply Dovecot config
if (&dovecot::is_dovecot_running()) {
	&dovecot::stop_dovecot();
	&dovecot::start_dovecot();
	}
}

# copy_postfix_ssl_service(&domain)
# Copy a domain's SSL cert to Postfix for global use
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

# Break possible linkage to snakeoil cert and key
foreach my $file ($cfile, $kfile, $cafile) {
    my $file_link = &resolve_links($file);
    if ($file ne $file_link) {
        &unlink_file($file);
        &copy_source_dest($file_link, $file);
        }
    }

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
if (&compare_version_numbers($postfix::postfix_version, "2.3") >= 0) {
	&postfix::set_current_value("smtpd_tls_security_level", "may");
	if (&compare_version_numbers($postfix::postfix_version, "2.11") >= 0) {
		&postfix::set_current_value("smtp_tls_security_level", "dane");
		&postfix::set_current_value("smtp_dns_support_level", "dnssec", 1);
		&postfix::set_current_value("smtp_host_lookup", "dns", 1);
		}
	else {
		&postfix::set_current_value("smtp_tls_security_level", "may");
		}
	}
&$second_print(&text('copycert_dsaved', "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_penabling'});
if (&compare_version_numbers($postfix::postfix_version, "2.3") >= 0) {
	&postfix::set_current_value("smtpd_tls_security_level", "may");
	}
else {
	&postfix::set_current_value("smtpd_use_tls", "yes");
	}
&postfix::set_current_value("smtpd_tls_mandatory_protocols", 
	&postfix::get_current_value("smtpd_tls_mandatory_protocols", "nodef") || "!SSLv2, !SSLv3, !TLSv1, !TLSv1.1");
&lock_file($postfix::config{'postfix_master'});
my $master = &postfix::get_master_config();
my ($smtps_enabled_prior) = grep {
	($_->{'name'} eq 'smtps' || $_->{'name'} eq '127.0.0.1:smtps') &&
	$_->{'enabled'} } @$master;
my ($smtps) = grep { $_->{'name'} eq 'smtps' ||
		     $_->{'name'} eq '127.0.0.1:smtps' } @$master;
my ($smtp) = grep { $_->{'name'} eq 'smtp' ||
		    $_->{'name'} eq '127.0.0.1:smtp' } @$master;
if (!$smtps_enabled_prior && $smtps && !$smtps->{'enabled'}) {
	# Enable existing entry
	$smtps->{'enabled'} = 1;
	&postfix::modify_master($smtps);
	}
elsif (!$smtps_enabled_prior && !$smtps && $smtp) {
	# Add new smtps entry, cloned from smtp
	$smtps = { %$smtp };
	$smtps->{'name'} = 'smtps';
	$smtps->{'command'} .= " -o smtpd_tls_wrappermode=yes";
	&postfix::create_master($smtps);
	}
&unlock_file($postfix::config{'postfix_master'});
&$second_print($text{'setup_done'});

# Apply Postfix config
if (&postfix::is_postfix_running()) {
	&postfix::stop_postfix();
	&postfix::start_postfix();
	}
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
if ($cadata) {
	&print_tempfile(CERT, $cadata,"\n");
	}
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

# Copy to appropriate config dir
my $dir = $config_directory;
&$first_print(&text('copycert_webmindir', "<tt>$dir</tt>"));
my $certfile;
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
my $dchain = &get_website_ssl_file($d, 'ca');
if ($dchain) {
	$chainfile = "$dir/$d->{'dom'}.ca";
	&lock_file($chainfile);
	&copy_source_dest($dchain, $chainfile);
	&unlock_file($chainfile);
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
&register_post_action(\&restart_webmin_fully);
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
	$chainfile = "$dir/$d->{'dom'}.ca";
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
&register_post_action(\&restart_usermin);
&$second_print($text{'setup_done'});

# Tell the user if not in SSL mode
if (!$miniserv{'ssl'}) {
	&$second_print(&text('copycert_userminnot',
			     "../usermin/edit_ssl.cgi"));
	}
}

# copy_mysql_ssl_service(&domain)
# Copy a domain's SSL cert to MySQL
sub copy_mysql_ssl_service
{
my ($d) = @_;

&foreign_require("mysql");
&$first_print($text{'copycert_mysql'});
my $conf = &mysql::get_mysql_config();
my ($mysqld) = grep { $_->{'name'} eq 'mysqld' } @$conf;
if (!$mysqld) {
	&$second_print($text{'copycert_emysqld'});
	return;
	}

# Lock all configs
my @cfiles = &mysql::get_all_mysqld_files();
foreach my $f (@cfiles) {
	&lock_file($f);
	}

# Figure out where to put files
my $dir = $mysql::config{'my_cnf'};
$dir =~ s/\/([^\/]+)$//;
my $cert = &mysql::find_value("ssl_cert", $mysqld->{'members'});
$cert ||= $dir."/mysql-ssl.cert";
my $key = &mysql::find_value("ssl_key", $mysqld->{'members'});
$key ||= $dir."/mysql-ssl.key";
my $ca = &mysql::find_value("ssl_ca", $mysqld->{'members'});
$ca ||= $dir."/mysql-ssl.ca";
my $myuser = &mysql::find_value("user", $mysqld->{'members'});
$myuser ||= 'mysql';

# Copy them over
&lock_file($cert);
&copy_source_dest($d->{'ssl_cert'}, $cert);
&unlock_file($cert);
&set_ownership_permissions($myuser, undef, 0600, $cert);
&mysql::save_directive($conf, $mysqld, "ssl_cert", [ $cert ]);
if ($d->{'ssl_key'}) {
	&lock_file($key);
	&copy_source_dest($d->{'ssl_key'}, $key);
	&convert_ssl_key_format(undef, $key, "pkcs1");
	&unlock_file($key);
	&set_ownership_permissions($myuser, undef, 0600, $key);
	&mysql::save_directive($conf, $mysqld, "ssl_key", [ $key ]);
	}
if ($d->{'ssl_chain'}) {
	&lock_file($ca);
	&copy_source_dest($d->{'ssl_chain'}, $ca);
	&unlock_file($ca);
	&set_ownership_permissions($myuser, undef, 0600, $ca);
	&mysql::save_directive($conf, $mysqld, "ssl_ca", [ $ca ]);
	}
else {
	&mysql::save_directive($conf, $mysqld, "ssl_ca", [ ]);
	}

# Save all MySQL configs
foreach my $f (@cfiles) {
	&flush_file_lines($f, undef, 1);
	&unlock_file($f);
	}

# Apply the change
if (&mysql::is_mysql_running() > 0) {
	# First try to apply the live config
	my @cmds = ( "set global ssl_key = '$key'",
		     "set global ssl_cert = '$cert'",
		     "set global ssl_ca = '$ca'",
		     "alter instance reload tls" );
	my $failed = 0;
	foreach my $c (@cmds) {
		eval {
			local $main::error_must_die = 1;
			&mysql::execute_sql_logged($mysql::master_db, $c);
			};
		if ($@) {
			$failed = 1;
			last;
			}
		}

	# Fall back to restarting MySQL later
	if ($failed) {
		&register_post_action(\&restart_mysql_server);
		}
	}
&$second_print($text{'setup_done'});
}

1;
