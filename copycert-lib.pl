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

1;
