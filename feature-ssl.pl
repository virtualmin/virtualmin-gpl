
sub init_ssl
{
$feature_depends{'ssl'} = [ 'web', 'dir' ];
$default_web_sslport = $config{'web_sslport'} || 443;
}

# check_depends_ssl(&dom)
# An SSL website requires either a private IP, or private port
sub check_depends_ssl
{
local ($d, $oldd) = @_;
local $tmpl = &get_template($d->{'template'});
local $defport = $tmpl->{'web_sslport'} || 443;
local $port = $d->{'web_sslport'} || $defport;
if ($d->{'virt'}) {
	# Has a private IP
	return undef;
	}
elsif ($port != $defport) {
	# Has a private port
	return undef;
	}
else {
	# Neither .. but we can still do SSL, if there are no other domains
	# with SSL on the same IP
	local ($sslclash) = grep { $_->{'ip'} eq $d->{'ip'} &&
				   $_->{'ssl'} &&
				   $_->{'id'} ne $d->{'id'}} &list_domains();
	if ($sslclash) {
		return &text('setup_edepssl3', $d->{'ip'});
		}
	# Check for <virtualhost> on the IP, if we are turning on SSL
	if (!$oldd || !$oldd->{'ssl'}) {
		&require_apache();
		local $conf = &apache::get_config();
		foreach my $v (&apache::find_directive_struct("VirtualHost",
							      $conf)) {
			local ($vip, $vport) = split(/:/, $v->{'words'}->[0]);
			if ($vip eq $d->{'ip'} && $vport == $port) {
				return &text('setup_edepssl4',
					     $d->{'ip'}, $port);
				}
			}
		}
	return undef;
	}
}

# setup_ssl(&domain)
# Creates a website with SSL enabled, and a private key and cert it to use.
sub setup_ssl
{
local $tmpl = &get_template($_[0]->{'template'});
local $web_sslport = $_[0]->{'web_sslport'} || $tmpl->{'web_sslport'} || 443;
&require_apache();
&obtain_lock_web($_[0]);
local $conf = &apache::get_config();
local $f = &get_website_file($_[0]);

# Create a self-signed cert and key, if needed
$_[0]->{'ssl_cert'} ||= &default_certificate_file($_[0], 'cert');
$_[0]->{'ssl_key'} ||= &default_certificate_file($_[0], 'key');
if (!-r $_[0]->{'ssl_cert'} && !-r $_[0]->{'ssl_key'}) {
	# Need to do it
	&foreign_require("webmin", "webmin-lib.pl");
	local $temp = &transname();
	&$first_print($text{'setup_openssl'});
	&lock_file($_[0]->{'ssl_cert'});
	&lock_file($_[0]->{'ssl_key'});
	local $size = $config{'key_size'} || $webmin::default_key_size;
	&open_execute_command(CA, "openssl req -newkey rsa:$size -x509 -nodes -out $_[0]->{'ssl_cert'} -keyout $_[0]->{'ssl_key'} -days 1825 >$temp 2>&1", 0);
	print CA ".\n";
	print CA ".\n";
	print CA ".\n";
	print CA "$_[0]->{'owner'}\n";
	print CA ".\n";
	print CA "*.$_[0]->{'dom'}\n";
	print CA ($_[0]->{'email'} || "."),"\n";
	close(CA);
	local $rv = $?;
	local $out = `cat $temp`;
	unlink($temp);
	if (!-r $_[0]->{'ssl_cert'} || !-r $_[0]->{'ssl_key'} || $?) {
		&$second_print(&text('setup_eopenssl', "<pre>$out</pre>"));
		return 0;
		}
	else {
		&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'ugid'}, 0755, $_[0]->{'ssl_cert'}, $_[0]->{'ssl_key'});
		if (&has_command("chcon")) {
			&execute_command("chcon -R -t httpd_config_t ".quotemeta($_[0]->{'ssl_cert'}).">/dev/null 2>&1");
			&execute_command("chcon -R -t httpd_config_t ".quotemeta($_[0]->{'ssl_key'}).">/dev/null 2>&1");
			}
		&$second_print($text{'setup_done'});
		}
	&unlock_file($_[0]->{'ssl_cert'});
	&unlock_file($_[0]->{'ssl_key'});
	}

# Add a Listen directive if needed
&add_listen($_[0], $conf, $web_sslport);

# Find directives in the non-SSL virtualhost, for copying
&$first_print($text{'setup_ssl'});
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_port'});
if (!$virt) {
	&$second_print($text{'setup_esslcopy'});
	return 0;
	}
local $srclref = &read_file_lines($virt->{'file'});

# Add the actual <VirtualHost>
local $lref = &read_file_lines($f);
local @ssldirs = &apache_ssl_directives($_[0], $tmpl);
push(@$lref, "<VirtualHost $_[0]->{'ip'}:$web_sslport>");
push(@$lref, @$srclref[$virt->{'line'}+1 .. $virt->{'eline'}-1]);
push(@$lref, @ssldirs);
push(@$lref, "</VirtualHost>");
&flush_file_lines($f);

# Update the non-SSL virtualhost to include the port number, to fix old
# hosts that were missing the :80
local $lref = &read_file_lines($virt->{'file'});
if (!$_[0]->{'name'} && $lref->[$virt->{'line'}] !~ /:\d+/) {
	$lref->[$virt->{'line'}] =
		"<VirtualHost $_[0]->{'ip'}:$_[0]->{'web_port'}>";
	&flush_file_lines();
	}
undef(@apache::get_config_cache);

# Add this IP and cert to Webmin/Usermin's SSL keys list
if ($tmpl->{'web_webmin_ssl'} && $d->{'virt'}) {
	&setup_ipkeys($_[0], \&get_miniserv_config, \&put_miniserv_config,
		      \&restart_webmin);
	}
if ($tmpl->{'web_usermin_ssl'} && &foreign_installed("usermin") &&
    $d->{'virt'}) {
	&foreign_require("usermin", "usermin-lib.pl");
	&setup_ipkeys($_[0], \&usermin::get_usermin_miniserv_config,
		      \&usermin::put_usermin_miniserv_config,
		      \&restart_usermin);
	}

&release_lock_web($_[0]);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_apache, 1);
$_[0]->{'web_sslport'} = $web_sslport;
}

# modify_ssl(&domain, &olddomain)
sub modify_ssl
{
local $rv = 0;
&require_apache();
&obtain_lock_web($_[0]);
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($_[1]->{'dom'},
                                            $_[1]->{'web_sslport'});
local $tmpl = &get_template($_[0]->{'template'});
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Home directory has changed .. update any directives that referred
	# to the old directory
	&$first_print($text{'save_ssl3'});
	local $lref = &read_file_lines($virt->{'file'});
	for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
		$lref->[$i] =~ s/$_[1]->{'home'}/$_[0]->{'home'}/g;
		}
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
        # Domain name has changed
        &$first_print($text{'save_ssl2'});
        &apache::save_directive("ServerName", [ $_[0]->{'dom'} ], $vconf,$conf);
        local @sa = map { s/$_[1]->{'dom'}/$_[0]->{'dom'}/g; $_ }
                        &apache::find_directive("ServerAlias", $vconf);
        &apache::save_directive("ServerAlias", \@sa, $vconf, $conf);
        &flush_file_lines();
        $rv++;
        &$second_print($text{'setup_done'});
        }
if ($_[0]->{'ip'} ne $_[1]->{'ip'} ||
    $_[0]->{'web_sslport'} != $_[1]->{'web_sslport'}) {
	# IP address or port has changed .. update VirtualHost
	&$first_print($text{'save_ssl'});
	local $conf = &apache::get_config();
	&add_listen($_[0], $conf, $_[0]->{'web_sslport'});
	local $lref = &read_file_lines($virt->{'file'});
	$lref->[$virt->{'line'}] =
		"<VirtualHost $_[0]->{'ip'}:$_[1]->{'web_sslport'}>";
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'proxy_pass_mode'} == 1 &&
    $_[1]->{'proxy_pass_mode'} == 1 &&
    $_[0]->{'proxy_pass'} ne $_[1]->{'proxy_pass'}) {
	# This is a proxying forwarding website and the URL has
	# changed - update all Proxy* directives
	&$first_print($text{'save_ssl6'});
	local $lref = &read_file_lines($virt->{'file'});
	for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
		if ($lref->[$i] =~ /^\s*ProxyPass(Reverse)?\s/) {
			$lref->[$i] =~ s/$_[1]->{'proxy_pass'}/$_[0]->{'proxy_pass'}/g;
			}
		}
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'proxy_pass_mode'} != $_[1]->{'proxy_pass_mode'}) {
	# Proxy mode has been enabled or disabled .. copy all directives from
	# non-SSL site
	local $mode = $_[0]->{'proxy_pass_mode'} ||
		      $_[1]->{'proxy_pass_mode'};
	&$first_print($mode == 2 ? $text{'save_ssl8'}
				 : $text{'save_ssl9'});
	local ($nonvirt, $nonvconf) = &get_apache_virtual($_[1]->{'dom'},
						          $_[1]->{'web_port'});
	local $lref = &read_file_lines($virt->{'file'});
	local $nonlref = &read_file_lines($nonvirt->{'file'});
	local $tmpl = &get_template($_[0]->{'tmpl'});
	local @dirs = @$nonlref[$nonvirt->{'line'}+1 .. $nonvirt->{'eline'}-1];
	push(@dirs, &apache_ssl_directives($_[0], $tmpl));
	splice(@$lref, $virt->{'line'} + 1,
	       $virt->{'eline'} - $virt->{'line'} - 1, @dirs);
	&flush_file_lines($virt->{'file'});
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'ip'} ne $_[1]->{'ip'}) {
        # IP address has changed .. fix per-IP SSL cert
	if ($tmpl->{'web_webmin_ssl'}) {
		&modify_ipkeys($_[0], $_[1], \&get_miniserv_config,
			       \&put_miniserv_config,
			       \&restart_webmin);
		}
	if ($tmpl->{'web_usermin_ssl'} && &foreign_installed("usermin")) {
		&foreign_require("usermin", "usermin-lib.pl");
		&modify_ipkeys($_[0], $_[1], \&usermin::get_usermin_miniserv_config,
			      \&usermin::put_usermin_miniserv_config,
			      \&restart_usermin);
		}
	}
&release_lock_web($_[0]);
&register_post_action(\&restart_apache, 1) if ($rv);
return $rv;
}

# delete_ssl(&domain)
# Deletes the SSL virtual server from the Apache config
sub delete_ssl
{
&require_apache();
&$first_print($text{'delete_ssl'});
&obtain_lock_web($_[0]);
local $conf = &apache::get_config();

# Remove the custom Listen directive added for the domain
&remove_listen($d, $conf, $d->{'web_sslport'});

# Remove the <virtualhost>
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
local $tmpl = &get_template($_[0]->{'template'});
if ($virt) {
	&delete_web_virtual_server($virt);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache, 1);
	}
else {
	&$second_print($text{'delete_noapache'});
	}
undef(@apache::get_config_cache);

# Delete per-IP SSL cert
if ($tmpl->{'web_webmin_ssl'}) {
	&delete_ipkeys($_[0], \&get_miniserv_config,
		       \&put_miniserv_config,
		       \&restart_webmin);
	}
if ($tmpl->{'web_usermin_ssl'} && &foreign_installed("usermin")) {
	&foreign_require("usermin", "usermin-lib.pl");
	&delete_ipkeys($_[0], \&usermin::get_usermin_miniserv_config,
		      \&usermin::put_usermin_miniserv_config,
		      \&restart_usermin);
	}
&release_lock_web($_[0]);
}

# validate_ssl(&domain)
# Returns an error message if no SSL Apache virtual host exists, or if the
# cert files are missing.
sub validate_ssl
{
local ($d) = @_;
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_sslport'});
return &text('validate_essl', "<tt>$d->{'dom'}</tt>") if (!$virt);

local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
if (!$cert) {
	return &text('validate_esslcert');
	}
elsif (!-r $cert) {
	return &text('validate_esslcertfile', "<tt>$cert</tt>");
	}

local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf, 1);
if ($key && !-r $key) {
	return &text('validate_esslkeyfile', "<tt>$key</tt>");
	}
return undef;
}

# check_ssl_clash(&domain, [field])
# Returns 1 if an SSL Apache webserver already exists for some domain
sub check_ssl_clash
{
if (!$_[1] || $_[1] eq 'dom') {
	local $tmpl = &get_template($_[0]->{'template'});
	local $web_sslport = $tmpl->{'web_sslport'} || 443;
	local ($cvirt, $cconf) = &get_apache_virtual($_[0]->{'dom'}, $web_sslport);
	return $cvirt ? 1 : 0;
	}
return 0;
}

# disable_ssl(&domain)
# Adds a directive to force all requests to show an error page
sub disable_ssl
{
&$first_print($text{'disable_ssl'});
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
if ($virt) {
        &create_disable_directives($virt, $vconf, $_[0]);
        &$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
        }
else {
        &$second_print($text{'delete_noapache'});
        }
}

# enable_ssl(&domain)
sub enable_ssl
{
&$first_print($text{'enable_ssl'});
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
if ($virt) {
        &remove_disable_directives($virt, $vconf, $_[0]);
        &$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
        }
else {
        &$second_print($text{'delete_noapache'});
        }
}

# backup_ssl(&domain, file)
# Save the SSL virtual server's Apache config as a separate file
sub backup_ssl
{
&$first_print($text{'backup_sslcp'});

# Save the apache directives
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
local $lref = &read_file_lines($virt->{'file'});
local $l;
&open_tempfile(FILE, ">$_[1]");
foreach $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
	&print_tempfile(FILE, "$l\n");
	}
&close_tempfile(FILE);

# Save the cert and key, if any
local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
if ($cert) {
	&execute_command("cp ".quotemeta($cert)." ".quotemeta("$_[1]_cert"));
	}
local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf, 1);
if ($key && $key ne $cert) {
	&execute_command("cp ".quotemeta($key)." ".quotemeta("$_[1]_key"));
	}

&$second_print($text{'setup_done'});
return 1;
}

# restore_ssl(&domain, file, &options)
# Update the SSL virtual server's Apache configuration from a file. Does not
# change the actual <Virtualhost> lines!
sub restore_ssl
{
&$first_print($text{'restore_sslcp'});
&obtain_lock_web($_[0]);

# Restore the Apache directives
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
local $srclref = &read_file_lines($_[1]);
local $dstlref = &read_file_lines($virt->{'file'});
splice(@$dstlref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1,
       @$srclref[1 .. @$srclref-2]);
# Fix ip address in <Virtualhost> section (if needed)
if ($dstlref->[$virt->{'line'}] =~
    /^(.*<Virtualhost\s+)([0-9\.]+)(.*)$/i) {
	$dstlref->[$virt->{'line'}] = $1.$_[0]->{'ip'}.$3;
	}
if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
	# Fix up any DocumentRoot or other file-related directives
	local $i;
	foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
		$dstlref->[$i] =~ s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
		}
	}
&flush_file_lines();
undef(@apache::get_config_cache);

# Copy suexec-related directives from non-SSL virtual host
($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
				      $_[0]->{'web_sslport'});
local ($nvirt, $nvconf) = &get_apache_virtual($_[0]->{'dom'},
					      $_[0]->{'web_port'});
if ($nvirt) {
	foreach my $dir ("User", "Group", "SuexecUserGroup") {
		local @vals = &apache::find_directive($dir, $nvconf);
		&apache::save_directive($dir, \@vals, $vconf, $conf);
		}
	&flush_file_lines();
	}

# Restore the cert and key, if any and if saved
local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
if ($cert && -r "$_[1]_cert") {
	&lock_file($cert);
	&copy_source_dest("$_[1]_cert", $cert);
	&unlock_file($cert);
	}
local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf, 1);
if ($key && -r "$_[1]_key" && $key ne $cert) {
	&lock_file($key);
	&copy_source_dest("$_[1]_key", $key);
	&unlock_file($key);
	}

&$second_print($text{'setup_done'});

&release_lock_web($_[0]);
&register_post_action(\&restart_apache);
return 1;
}

# cert_info(&domain)
# Returns a hash of details of a domain's cert
sub cert_info
{
return &cert_file_info($_[0]->{'ssl_cert'});
}

# cert_file_info(file)
# Returns a hash of details of a cert in some file
sub cert_file_info
{
local ($file) = @_;
local %rv;
local $_;
open(OUT, "openssl x509 -in ".quotemeta($file)." -issuer -subject -enddate |");
while(<OUT>) {
	s/\r|\n//g;
	s/http:\/\//http:\|\|/g;	# So we can parse with regexp
	if (/subject=.*CN=([^\/]+)/) {
		$rv{'cn'} = $1;
		}
	if (/subject=.*O=([^\/]+)/) {
		$rv{'o'} = $1;
		}
	if (/issuer=.*CN=([^\/]+)/) {
		$rv{'issuer_cn'} = $1;
		}
	if (/issuer=.*O=([^\/]+)/) {
		$rv{'issuer_o'} = $1;
		}
	if (/notAfter=(.*)/) {
		$rv{'notafter'} = $1;
		}
	}
close(OUT);
foreach my $k (keys %rv) {
	$rv{$k} =~ s/http:\|\|/http:\/\//g;
	}
$rv{'type'} = $rv{'o'} eq $rv{'issuer_o'} ? $text{'cert_typeself'}
					  : $text{'cert_typereal'};
return \%rv;
}

# cert_pem_data(&domain)
# Returns a domain's cert in PEM format
sub cert_pem_data
{
local ($d) = @_;
local $data = &read_file_contents($d->{'ssl_cert'});
if ($data =~ /(-----BEGIN\s+CERTIFICATE-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+CERTIFICATE-----)/) {
	return $1;
	}
return undef;
}

# cert_pkcs12_data(&domain)
# Returns a domain's cert in PKCS12 format
sub cert_pkcs12_data
{
local ($d) = @_;
open(OUT, "openssl pkcs12 -in ".quotemeta($d->{'ssl_cert'}).
          " -inkey ".quotemeta($_[0]->{'ssl_key'}).
	  " -export -passout pass: -nokeys |");
while(<OUT>) {
	$data .= $_;
	}
close(OUT);
return $data;
}

# setup_ipkeys(&domain, &miniserv-getter, &miniserv-saver, &post-action)
sub setup_ipkeys
{
local ($dom, $getfunc, $putfunc, $postfunc) = @_;
&foreign_require("webmin", "webmin-lib.pl");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
push(@ipkeys, { 'ips' => [ $_[0]->{'ip'} ],
		'key' => $_[0]->{'ssl_key'},
		'cert' => $_[0]->{'ssl_cert'} });
&webmin::save_ipkeys(\%miniserv, \@ipkeys);
&$putfunc(\%miniserv);
&register_post_action($postfunc);
return 1;
}

# delete_ipkeys(&domain, &miniserv-getter, &miniserv-saver, &post-action)
sub delete_ipkeys
{
local ($dom, $getfunc, $putfunc, $postfunc) = @_;
&foreign_require("webmin", "webmin-lib.pl");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
local @newipkeys = grep { $_->{'ips'}->[0] ne $_[0]->{'ip'} } @ipkeys;
if (@ipkeys != @newipkeys) {
	&webmin::save_ipkeys(\%miniserv, \@newipkeys);
	&$putfunc(\%miniserv);
	&register_post_action($postfunc);
	return 1;
	}
return 0;
}

# modify_ipkeys(&domain, &olddomain, &miniserv-getter, &miniserv-saver, &post-action)
sub modify_ipkeys
{
local ($dom, $olddom, $getfunc, $putfunc, $postfunc) = @_;
if (&delete_ipkeys($olddom, $getfunc, $putfunc, $postfunc)) {
	&setup_ipkeys($dom, $getfunc, $putfunc, $postfunc);
	}
}

# apache_ssl_directives(&domain, template)
# Returns extra Apache directives needed for SSL
sub apache_ssl_directives
{
local ($d, $tmpl) = @_;
local @dirs;
push(@dirs, "SSLEngine on");
push(@dirs, "SSLCertificateFile $d->{'ssl_cert'}");
push(@dirs, "SSLCertificateKeyFile $d->{'ssl_key'}");
return @dirs;
}

# get_chained_certificate_file(&domain)
# Returns the file used for the chained cert, or undef if not set
sub get_chained_certificate_file
{
local ($d) = @_;
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_sslport'});
return undef if (!$virt);
local ($cert) = &apache::find_directive("SSLCACertificateFile", $vconf);
return $cert;
}

# save_chained_certificate_file(&domain, [file])
# Updates the chained cert file, or removed it if file is undef
sub save_chained_certificate_file
{
local ($d, $file) = @_;
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_sslport'});
return undef if (!$virt);
&lock_file($virt->{'file'});
&apache::save_directive("SSLCACertificateFile", $file ? [ $file ] : [ ],
			$vconf,$conf);
&flush_file_lines($virt->{'file'});
&unlock_file($virt->{'file'});
&register_post_action(\&restart_apache);
}

# check_certificate_data(data)
# Checks if some data looks like a valid cert. Returns undef if OK, or an error
# message if not
sub check_certificate_data
{
local ($data) = @_;
local $temp = &transname();
&open_tempfile(CERTDATA, ">$temp", 0, 1);
&print_tempfile(CERTDATA, $data);
&close_tempfile(CERTDATA);
local $out = &backquote_command("openssl x509 -in ".quotemeta($temp)." -issuer -subject -enddate 2>&1");
local $ex = $?;
&unlink_file($temp);
if ($ex) {
	return "<tt>".&html_escape($out)."</tt>";
	}
elsif ($out !~ /subject=.*CN=/) {
	return $text{'cert_esubject'};
	}
else {
	return undef;
	}
}

# default_certificate_file(&domain, "cert"|"key"|"ca")
# Returns the default path that should be used for a cert, key or CA file
sub default_certificate_file
{
local ($d, $mode) = @_;
return $config{$mode.'_tmpl'} ?
	    &absolute_domain_path($d,
	     &substitute_domain_template($config{$mode.'_tmpl'}, $d)) :
	    "$d->{'home'}/ssl.".$mode;
}

# obtain_lock_ssl(&domain)
# Lock the Apache config file for some domain, and the Webmin config
sub obtain_lock_ssl
{
local ($d) = @_;
return if (!$config{'ssl'});
&obtain_lock_anything($d);
&obtain_lock_web($d);
if ($main::got_lock_ssl == 0) {
	local @sfiles = ($ENV{'MINISERV_CONFIG'} ||
		         "$config_directory/miniserv.conf",
		        $config_directory =~ /^(.*)\/webmin$/ ?
		         "$1/usermin/miniserv.conf" :
			 "/etc/usermin/miniserv.conf");
	foreach my $f (@sfiles) {
		&lock_file($f);
		}
	@main::got_lock_ssl_files = @sfiles;
	}
$main::got_lock_ssl++;
}

# release_lock_web(&domain)
# Un-lock the Apache config file for some domain, and the Webmin config
sub release_lock_ssl
{
local ($d) = @_;
return if (!$config{'ssl'});
&release_lock_web($d);
if ($main::got_lock_ssl == 1) {
	foreach my $f (@main::got_lock_ssl_files) {
		&unlock_file($f);
		}
	}
$main::got_lock_ssl-- if ($main::got_lock_ssl);
&release_lock_anything($d);
}

$done_feature_script{'ssl'} = 1;

1;

