
sub init_ssl
{
$feature_depends{'ssl'} = [ 'web', 'dir' ];
$default_web_sslport = $config{'web_sslport'} || 443;
}

# check_warnings_ssl(&dom, &old-domain)
# An SSL website should have either a private IP, or private port, UNLESS
# the clashing domain's cert can be used for this domain.
sub check_warnings_ssl
{
local ($d, $oldd) = @_;
&require_apache();
local $tmpl = &get_template($d->{'template'});
local $defport = $tmpl->{'web_sslport'} || 443;
local $port = $d->{'web_sslport'} || $defport;

# Check if Apache supports SNI, which makes clashing certs not so bad
local $sni = &has_sni_support($d);

if ($port != $defport) {
	# Has a private port
	return undef;
	}
elsif ($sni) {
	# Web server and clients can handle multiple SSL certs on
	# the same IP address
	return undef;
	}
else {
	# Neither .. but we can still do SSL, if there are no other domains
	# with SSL on the same IPv4 address
	local ($sslclash) = grep { $_->{'ip'} eq $d->{'ip'} &&
				   $_->{'ssl'} &&
				   $_->{'id'} ne $d->{'id'}} &list_domains();
	if (!$d->{'virt'} && $sslclash && (!$oldd || !$oldd->{'ssl'})) {
		# Clash .. but is the cert OK?
		if (!&check_domain_certificate($d->{'dom'}, $sslclash)) {
			local @certdoms = &list_domain_certificate($sslclash);
			return &text('setup_edepssl5', $d->{'ip'},
				join(", ", map { "<tt>$_</tt>" } @certdoms),
				$sslclash->{'dom'});
			}
		else {
			return undef;
			}
		}
	# Check for <virtualhost> on the IP, if we are turning on SSL
	if (!$oldd || !$oldd->{'ssl'}) {
		&require_apache();
		local $conf = &apache::get_config();
		foreach my $v (&apache::find_directive_struct("VirtualHost",
							      $conf)) {
			foreach my $w (@{$v->{'words'}}) {
				local ($vip, $vport) = split(/:/, $w);
				if ($vip eq $d->{'ip'} && $vport == $port) {
					return &text('setup_edepssl4',
						     $d->{'ip'}, $port);
					}
				}
			}
		}

	# Perform the same check on IPv6
	local ($sslclash6) = grep { $_->{'ip6'} &&
				    $_->{'ip6'} eq $d->{'ip6'} &&
				    $_->{'ssl'} &&
				    $_->{'id'} ne $d->{'id'}} &list_domains();
	if (!$d->{'virt6'} && $sslclash6 && (!$oldd || !$oldd->{'ssl'})) {
		# Clash .. but is the cert OK?
		if (!&check_domain_certificate($d->{'dom'}, $sslclash)) {
			local @certdoms = &list_domain_certificate($sslclash);
			return &text('setup_edepssl5', $d->{'ip6'},
				join(", ", map { "<tt>$_</tt>" } @certdoms),
				$sslclash->{'dom'});
			}
		else {
			return undef;
			}
		}
	# Check for <virtualhost> on the IPv6 address, if we are turning on SSL
	if (!$oldd || !$oldd->{'ssl'}) {
		&require_apache();
		local $conf = &apache::get_config();
		foreach my $v (&apache::find_directive_struct("VirtualHost",
							      $conf)) {
			foreach my $w (@{$v->{'words'}}) {
				$w =~ /^\[([^\/]+)\]/ || next;
				local $vip = $1;
				if ($vip eq $d->{'ip6'} && $vport == $port) {
					return &text('setup_edepssl4',
						     $d->{'ip6'}, $port);
					}
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
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $web_sslport = $d->{'web_sslport'} || $tmpl->{'web_sslport'} || 443;
&require_apache();
&obtain_lock_web($d);
local $conf = &apache::get_config();
$d->{'letsencrypt_renew'} = 2;		# Default let's encrypt renewal

# Find out if this domain will share a cert with another
&find_matching_certificate($d);
local $chained = $d->{'ssl_chain'};

# Create a self-signed cert and key, if needed
my $generated = &generate_default_certificate($d);

# Add NameVirtualHost if needed, and if there is more than one SSL site on
# this IP address
local $nvstar = &add_name_virtual($d, $conf, $web_sslport, 1, $d->{'ip'});
local $nvstar6; 
if ($d->{'ip6'}) {                                
        $nvstar6 = &add_name_virtual($d, $conf, $web_sslport, 1,
                                     "[".$d->{'ip6'}."]");
        }       

# Add a Listen directive if needed
&add_listen($d, $conf, $web_sslport);

# Find directives in the non-SSL virtualhost, for copying
&$first_print($text{'setup_ssl'});
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_port'});
if (!$virt) {
	&$second_print($text{'setup_esslcopy'});
	return 0;
	}
local $srclref = &read_file_lines($virt->{'file'});

# Double-check cert and key
local $certdata = &read_file_contents($d->{'ssl_cert'});
local $keydata = &read_file_contents($d->{'ssl_key'});
local $err = &validate_cert_format($certdata, 'cert');
if ($err) {
	&$second_print(&text('setup_esslcert', $err));
	return 0;
	}
local $err = &validate_cert_format($keydata, 'key');
if ($err) {
	&$second_print(&text('setup_esslkey', $err));
	return 0;
	}
if ($d->{'ssl_ca'}) {
	local $cadata = &read_file_contents($d->{'ssl_ca'});
	local $err = &validate_cert_format($cadata, 'ca');
	if ($err) {
		&$second_print(&text('setup_esslca', $err));
		return 0;
		}
	}
local $err = &check_cert_key_match($certdata, $keydata);
if ($err) {
	&$second_print(&text('setup_esslmatch', $err));
	return 0;
	}

# Add the actual <VirtualHost>
local $f = $virt->{'file'};
local $lref = &read_file_lines($f);
local @ssldirs = &apache_ssl_directives($d, $tmpl);
push(@$lref, "<VirtualHost ".&get_apache_vhost_ips($d, 0, 0, $web_sslport).">");
push(@$lref, @$srclref[$virt->{'line'}+1 .. $virt->{'eline'}-1]);
push(@$lref, @ssldirs);
push(@$lref, "</VirtualHost>");
&flush_file_lines($f);

# Update the non-SSL virtualhost to include the port number, to fix old
# hosts that were missing the :80
local $lref = &read_file_lines($virt->{'file'});
if (!$d->{'name'} && $lref->[$virt->{'line'}] !~ /:\d+/) {
	$lref->[$virt->{'line'}] =
		"<VirtualHost $d->{'ip'}:$d->{'web_port'}>";
	&flush_file_lines($virt->{'file'});
	}
undef(@apache::get_config_cache);

# Add this IP and cert to Webmin/Usermin's SSL keys list
if ($tmpl->{'web_webmin_ssl'}) {
	&setup_ipkeys($d, \&get_miniserv_config, \&put_miniserv_config,
		      \&restart_webmin_fully);
	}
if ($tmpl->{'web_usermin_ssl'} && &foreign_installed("usermin")) {
	&foreign_require("usermin");
	&setup_ipkeys($d, \&usermin::get_usermin_miniserv_config,
		      \&usermin::put_usermin_miniserv_config,
		      \&restart_usermin);
	}

# Copy chained CA cert in from domain with same IP, if any
$d->{'web_sslport'} = $web_sslport;
if ($chained) {
	&save_website_ssl_file($d, 'ca', $chained);
	}
$d->{'web_urlsslport'} = $tmpl->{'web_urlsslport'};

# Setup in Dovecot
&sync_dovecot_ssl_cert($d, 1);

# Update DANE DNS records
&sync_domain_tlsa_records($d);

# Redirect HTTP to HTTPS
if ($config{'auto_redirect'}) {
	my $redir = { 'path' => '^/(?!.well-known)',
		      'dest' => 'https://'.$d->{'dom'}.'/$1',
		      'alias' => 0,
		      'regexp' => 1,
		      'http' => 1,
		      'https' => 0 };
	&create_redirect($d, $redir);
	}

&release_lock_web($d);
&$second_print($text{'setup_done'});
if ($d->{'virt'}) {
	&register_post_action(\&restart_apache, 1);
	}
else {
	&register_post_action(\&restart_apache);
	}

# Try to request a Let's Encrypt cert when enabling SSL post-creation for
# the first time
if (!$d->{'creating'} && $generated && $d->{'auto_letsencrypt'} &&
    !$d->{'disabled'}) {
	&create_initial_letsencrypt_cert($d);
	}

return 1;
}

# modify_ssl(&domain, &olddomain)
sub modify_ssl
{
local ($d, $oldd) = @_;
local $rv = 0;
&require_apache();
&obtain_lock_web($d);

# Get objects for SSL and non-SSL virtual hosts
local ($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
                                                   $oldd->{'web_sslport'});
local ($nonvirt, $nonvconf) = &get_apache_virtual($d->{'dom'},
						  $d->{'web_port'});
local $tmpl = &get_template($d->{'template'});

if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'ip6'} ne $oldd->{'ip6'} ||
    $d->{'virt6'} != $oldd->{'virt6'} ||
    $d->{'name6'} != $oldd->{'name6'} ||
    $d->{'web_sslport'} != $oldd->{'web_sslport'}) {
	# IP address or port has changed .. update VirtualHost
	&$first_print($text{'save_ssl'});
	if (!$virt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local $nvstar = &add_name_virtual($d, $conf,
					  $d->{'web_sslport'}, 0,
					  $d->{'ip'});
	local $nvstar6;
	if ($d->{'ip6'}) {
		$nvstar6 = &add_name_virtual(
			$d, $conf, $d->{'web_sslport'}, 0,
			"[".$d->{'ip6'}."]");
		}
	&add_listen($d, $conf, $d->{'web_sslport'});
	local $lref = &read_file_lines($virt->{'file'});
	$lref->[$virt->{'line'}] =
		"<VirtualHost ".
		&get_apache_vhost_ips($d, $nvstar, $nvstar6,
				      $d->{'web_sslport'}).">";
	&flush_file_lines();
	$rv++;
	undef(@apache::get_config_cache);
	($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
					      	     $oldd->{'web_sslport'});
	&$second_print($text{'setup_done'});
	}
if ($d->{'home'} ne $oldd->{'home'}) {
	# Home directory has changed .. update any directives that referred
	# to the old directory
	&$first_print($text{'save_ssl3'});
	if (!$virt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local $lref = &read_file_lines($virt->{'file'});
	for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
		$lref->[$i] =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
		}
	&flush_file_lines();
	$rv++;
	undef(@apache::get_config_cache);
	($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
					      	     $oldd->{'web_sslport'});
	&$second_print($text{'setup_done'});
	}
if ($d->{'proxy_pass_mode'} == 1 &&
    $oldd->{'proxy_pass_mode'} == 1 &&
    $d->{'proxy_pass'} ne $oldd->{'proxy_pass'}) {
	# This is a proxying forwarding website and the URL has
	# changed - update all Proxy* directives
	&$first_print($text{'save_ssl6'});
	if (!$virt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local $lref = &read_file_lines($virt->{'file'});
	for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
		if ($lref->[$i] =~ /^\s*ProxyPass(Reverse)?\s/) {
			$lref->[$i] =~ s/$oldd->{'proxy_pass'}/$d->{'proxy_pass'}/g;
			}
		}
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($d->{'proxy_pass_mode'} != $oldd->{'proxy_pass_mode'}) {
	# Proxy mode has been enabled or disabled .. copy all directives from
	# non-SSL site
	local $mode = $d->{'proxy_pass_mode'} ||
		      $oldd->{'proxy_pass_mode'};
	&$first_print($mode == 2 ? $text{'save_ssl8'}
				 : $text{'save_ssl9'});
	if (!$virt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local $lref = &read_file_lines($virt->{'file'});
	local $nonlref = &read_file_lines($nonvirt->{'file'});
	local $tmpl = &get_template($d->{'tmpl'});
	local @dirs = @$nonlref[$nonvirt->{'line'}+1 .. $nonvirt->{'eline'}-1];
	push(@dirs, &apache_ssl_directives($d, $tmpl));
	splice(@$lref, $virt->{'line'} + 1,
	       $virt->{'eline'} - $virt->{'line'} - 1, @dirs);
	&flush_file_lines($virt->{'file'});
	$rv++;
	undef(@apache::get_config_cache);
	($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
					      	     $oldd->{'web_sslport'});
	&$second_print($text{'setup_done'});
	}
if ($d->{'user'} ne $oldd->{'user'}) {
	# Username has changed .. copy suexec directives from parent
	&$first_print($text{'save_ssl10'});
	if (!$virt || !$nonvirt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local @vals = &apache::find_directive("SuexecUserGroup", $nonvconf);
	&apache::save_directive("SuexecUserGroup", \@vals, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($d->{'dom'} ne $oldd->{'dom'}) {
        # Domain name has changed .. fix up Apache config by copying relevant
        # directives from the real domain
        &$first_print($text{'save_ssl2'});
	if (!$virt || !$nonvirt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	foreach my $dir ("ServerName", "ServerAlias",
			 "ErrorLog", "TransferLog", "CustomLog",
			 "RewriteCond", "RewriteRule") {
		local @vals = &apache::find_directive($dir, $nonvconf);
		&apache::save_directive($dir, \@vals, $vconf, $conf);
		}
        &flush_file_lines($virt->{'file'});
        $rv++;
        &$second_print($text{'setup_done'});
        }

# Code after here still works even if SSL virtualhost is missing
VIRTFAILED:
if ($d->{'ip'} ne $oldd->{'ip'} && $oldd->{'ssl_same'}) {
	# IP has changed - maybe clear ssl_same field
	local ($sslclash) = grep { $_->{'ip'} eq $d->{'ip'} &&
				   $_->{'ssl'} &&
				   $_->{'id'} ne $d->{'id'} &&
				   !$_->{'ssl_same'} } &list_domains();
	local $oldsslclash = &get_domain($oldd->{'ssl_same'});
	if ($sslclash && $oldd->{'ssl_same'} eq $sslclash->{'id'}) {
		# No need to change
		}
	elsif ($sslclash &&
	       &check_domain_certificate($d->{'dom'}, $sslclash)) {
		# New domain with same cert
		$d->{'ssl_cert'} = $sslclash->{'ssl_cert'};
		$d->{'ssl_key'} = $sslclash->{'ssl_key'};
		$d->{'ssl_same'} = $sslclash->{'id'};
		$chained = &get_website_ssl_file($sslclash, 'ca');
		$d->{'ssl_chain'} = $chained;
		}
	else {
		# No domain has the same cert anymore - copy the one from the
		# old sslclash domain
		&break_ssl_linkage($d, $oldsslclash);
		}
	}
if ($d->{'home'} ne $oldd->{'home'}) {
	# Fix SSL cert file locations
	foreach my $k ('ssl_cert', 'ssl_key', 'ssl_chain') {
		$d->{$k} =~ s/\Q$oldd->{'home'}\E\//$d->{'home'}\//;
		}
	}
if ($d->{'dom'} ne $oldd->{'dom'} && &self_signed_cert($d) &&
    !&check_domain_certificate($d->{'dom'}, $d)) {
	# Domain name has changed .. re-generate self-signed cert
	&$first_print($text{'save_ssl11'});
	local $info = &cert_info($d);
	&lock_file($d->{'ssl_cert'});
	&lock_file($d->{'ssl_key'});
	local @newalt = $info->{'alt'} ? @{$info->{'alt'}} : ( );
	foreach my $a (@newalt) {
		if ($a eq $oldd->{'dom'}) {
			$a = $d->{'dom'};
			}
		elsif ($a =~ /^([^\.]+)\.(\S+)$/ && $2 eq $oldd->{'dom'}) {
			$a = $1.".".$d->{'dom'};
			}
		}
	local $err = &generate_self_signed_cert(
		$d->{'ssl_cert'}, $d->{'ssl_key'},
		undef,
		1825,
		$info->{'c'},
		$info->{'st'},
		$info->{'l'},
		$info->{'o'},
		$info->{'ou'},
		"*.$d->{'dom'}",
		$d->{'emailto_addr'},
		\@newalt,
		$d,
		);
	&unlock_file($d->{'ssl_key'});
	&unlock_file($d->{'ssl_cert'});
	if ($err) {
		&$second_print(&text('setup_eopenssl', $err));
		}
	else {
		$rv++;
		&$second_print($text{'setup_done'});
		}
	}

# Changes for Webmin and Usermin
if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'dom'} ne $oldd->{'dom'} ||
    $d->{'home'} ne $oldd->{'home'}) {
        # IP address or domain name has changed .. fix per-IP/per-domain SSL cert
	&modify_ipkeys($d, $oldd, \&get_miniserv_config,
		       \&put_miniserv_config,
		       \&restart_webmin_fully);
	if (&foreign_installed("usermin")) {
		&foreign_require("usermin");
		&modify_ipkeys($d, $oldd,
			       \&usermin::get_usermin_miniserv_config,
			       \&usermin::put_usermin_miniserv_config,
			       \&restart_usermin);
		}
	}

# If anything has changed that would impact the Dovecot cert, re-set it up
if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'home'} ne $oldd->{'home'}) {
	&sync_dovecot_ssl_cert($oldd, 0);
	&sync_postfix_ssl_cert($oldd, 0);
	&sync_dovecot_ssl_cert($d, 1);
	&sync_postfix_ssl_cert($d, $d->{'virt'});
	}

# Update DANE DNS records
&sync_domain_tlsa_records($d);

&release_lock_web($d);
&register_post_action(\&restart_apache, 1) if ($rv);
return $rv;
}

# delete_ssl(&domain)
# Deletes the SSL virtual server from the Apache config
sub delete_ssl
{
local ($d) = @_;

&require_apache();
&$first_print($text{'delete_ssl'});
&obtain_lock_web($d);
local $conf = &apache::get_config();

# Remove the custom Listen directive added for the domain, if any
&remove_listen($d, $conf, $d->{'web_sslport'} || $default_web_sslport);

# Remove the <virtualhost>
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
			    $d->{'web_sslport'} || $default_web_sslport);
local $tmpl = &get_template($d->{'template'});
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
&delete_ipkeys($d, \&get_miniserv_config,
	       \&put_miniserv_config,
	       \&restart_webmin_fully);
if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	&delete_ipkeys($d, \&usermin::get_usermin_miniserv_config,
		      \&usermin::put_usermin_miniserv_config,
		      \&restart_usermin);
	}

# If any other domains were using this one's SSL cert or key, break the linkage
foreach my $od (&get_domain_by("ssl_same", $d->{'id'})) {
	&break_ssl_linkage($od, $d);
	&save_domain($od);
	}

# If this domain was sharing a cert with another, forget about it now
if ($d->{'ssl_same'}) {
	delete($d->{'ssl_cert'});
	delete($d->{'ssl_key'});
	delete($d->{'ssl_chain'});
	delete($d->{'ssl_same'});
	}

# Remove from Dovecot
&sync_dovecot_ssl_cert($d, 0);

# Update DANE DNS records
&sync_domain_tlsa_records($d);

&release_lock_web($d);
return 1;
}

# clone_ssl(&domain, &old-domain)
# Since the non-SSL website has already been cloned and modified, just copy
# its directives and add SSL-specific options.
sub clone_ssl
{
local ($d, $oldd) = @_;
local $tmpl = &get_template($d->{'template'});
&$first_print($text{'clone_ssl'});
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_sslport'});
local ($ovirt, $ovconf) = &get_apache_virtual($oldd->{'dom'},
					      $oldd->{'web_sslport'});
if (!$ovirt) {
	&$second_print($text{'clone_webold'});
	return 0;
	}
if (!$virt) {
	&$second_print($text{'clone_webnew'});
	return 0;
	}

# Fix up all the Apache directives
&clone_web_domain($oldd, $d, $ovirt, $virt, $d->{'web_sslport'});

# Is the linked SSL cert still valid for the new domain? If not, break the
# linkage by copying over the cert.
if ($d->{'ssl_same'} && !&check_domain_certificate($d->{'dom'}, $d)) {
	local $oldsame = &get_domain($d->{'ssl_same'});
	&break_ssl_linkage($d, $oldsame);
	}

&release_lock_web($d);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_apache, 1);
return 1;
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

# Check IP addresses
if ($d->{'virt'}) {
	local $ipp = $d->{'ip'}.":".$d->{'web_sslport'};
	&indexof($ipp, @{$virt->{'words'}}) >= 0 ||
		return &text('validate_ewebip', $ipp);
	}
if ($d->{'virt6'}) {
	local $ipp = "[".$d->{'ip6'}."]:".$d->{'web_sslport'};
	&indexof($ipp, @{$virt->{'words'}}) >= 0 ||
		return &text('validate_ewebip6', $ipp);
	}

# Make sure cert file exists
local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
if (!$cert) {
	return &text('validate_esslcert');
	}
elsif (!-r $cert) {
	return &text('validate_esslcertfile', "<tt>$cert</tt>");
	}

# Make sure key exists
local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf, 1);
if ($key && !-r $key) {
	return &text('validate_esslkeyfile', "<tt>$key</tt>");
	}

# Make sure this domain or www.domain matches cert. Include aliases, because
# in some cases the alias may be the externally visible domain
my $match = 0;
foreach my $cd ($d, &get_domain_by("alias", $d->{'id'})) {
	$match++ if (&check_domain_certificate($cd->{'dom'}, $d));
	}
if (!$match) {
	return &text('validate_essldom',
		     "<tt>".$d->{'dom'}."</tt>",
		     "<tt>"."www.".$d->{'dom'}."</tt>",
		     join(", ", map { "<tt>$_</tt>" }
			            &list_domain_certificate($d)));
	}

# Make sure the cert isn't expired
local $info = &cert_info($d);
if ($info && $info->{'notafter'}) {
	local $notafter = &parse_notafter_date($info->{'notafter'});
	if ($notafter < time()) {
		return &text('validate_esslexpired', &make_date($notafter));
		}
	}

# Make sure the first virtualhost on this IP serves the same cert, unless
# SNI is enabled
&require_apache();
local $conf = &apache::get_config();
local $firstcert;
foreach my $v (&apache::find_directive_struct("VirtualHost",
					      $conf)) {
	local ($vip, $vport) = split(/:/, $v->{'words'}->[0]);
	if ($vip eq $d->{'ip'} && $vport == $d->{'web_sslport'}) {
		# Found first one .. is it's cert OK?
		$firstcert = &apache::find_directive("SSLCertificateFile",
			$v->{'members'}, 1);
		last;
		}
	}

return undef;
}

# check_ssl_clash(&domain, [field])
# Returns 1 if an SSL Apache webserver already exists for some domain, or if
# port 443 on the domain's IP is in use by Webmin or Usermin
sub check_ssl_clash
{
local $tmpl = &get_template($_[0]->{'template'});
local $web_sslport = $tmpl->{'web_sslport'} || 443;
if (!$_[1] || $_[1] eq 'dom') {
	# Check for <virtualhost> clash by domain name
	local ($cvirt, $cconf) = &get_apache_virtual($_[0]->{'dom'},
						     $web_sslport);
	return 1 if ($cvirt);
	}
if (!$_[1] || $_[1] eq 'ip') {
	# Check for clash by IP and port with Webmin or Usermin
	local $err = &check_webmin_port_clash($_[0], $web_sslport);
	return $err if ($err);
	}
return 0;
}

# check_webmin_port_clash(&domain, port)
# Returns 1 if Webmin or Usermin is using some IP and port
sub check_webmin_port_clash
{
my ($d, $port) = @_;
foreign_require("webmin");
my @checks;
my %miniserv;
&get_miniserv_config(\%miniserv);
push(@checks, [ \%miniserv, "Webmin" ]);
if (&foreign_installed("usermin")) {
	my %uminiserv;
	foreign_require("usermin");
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	push(@checks, [ \%uminiserv, "Usermin" ]);
	}
foreach my $c (@checks) {
	my @sockets = &webmin::get_miniserv_sockets($c->[0]);
	foreach my $s (@sockets) {
		if (($s->[0] eq '*' || $s->[0] eq $d->{'ip'}) &&
		    $s->[1] == $port) {
			return &text('setup_esslportclash',
				     $d->{'ip'}, $port, $c->[1]);
			}
		}
	}
return undef;
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
	return 1;
        }
else {
        &$second_print($text{'delete_noapache'});
	return 0;
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
	return 1;
        }
else {
        &$second_print($text{'delete_noapache'});
	return 0;
        }
}

# backup_ssl(&domain, file)
# Save the SSL virtual server's Apache config as a separate file
sub backup_ssl
{
local ($d, $file) = @_;
&$first_print($text{'backup_sslcp'});

# Save the apache directives
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_sslport'});
if ($virt) {
	local $lref = &read_file_lines($virt->{'file'});
	&open_tempfile_as_domain_user($d, FILE, ">$file");
	foreach my $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile_as_domain_user($d, FILE);

	# Save the cert and key, if any
	local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
	if ($cert) {
		&copy_write_as_domain_user($d, $cert, $file."_cert");
		}
	local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf,1);
	if ($key && $key ne $cert) {
		&copy_write_as_domain_user($d, $key, $file."_key");
		}
	local $ca = &apache::find_directive("SSLCACertificateFile", $vconf,1);
	if ($ca) {
		&copy_write_as_domain_user($d, $ca, $file."_ca");
		}

	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	return 0;
	}
}

# restore_ssl(&domain, file, &options)
# Update the SSL virtual server's Apache configuration from a file. Does not
# change the actual <Virtualhost> lines!
sub restore_ssl
{
&$first_print($text{'restore_sslcp'});
&obtain_lock_web($_[0]);
my $rv = 1;

# Restore the Apache directives
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_sslport'});
if ($virt) {
	local $srclref = &read_file_lines($_[1], 1);
	local $dstlref = &read_file_lines($virt->{'file'});
	splice(@$dstlref, $virt->{'line'}+1,
	       $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);

	if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
		# Fix up any DocumentRoot or other file-related directives
		local $i;
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~
			    s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
			}
		}
	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);

	# Copy suexec-related directives from non-SSL virtual host
	($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					      $_[0]->{'web_sslport'});
	local ($nvirt, $nvconf) = &get_apache_virtual($_[0]->{'dom'},
						      $_[0]->{'web_port'});
	if ($nvirt && $virt) {
		local @vals = &apache::find_directive("SuexecUserGroup",
						      $nvconf);
		if (@vals) {
			&apache::save_directive("SuexecUserGroup", \@vals,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			}
		}

	# Restore the cert and key, if any and if saved
	local $cert = &apache::find_directive("SSLCertificateFile", $vconf, 1);
	if ($cert && -r "$_[1]_cert") {
		&lock_file($cert);
		&set_ownership_permissions(
			$_[0]->{'uid'}, undef, undef, "$_[1]_cert");
		&copy_source_dest_as_domain_user($_[0], "$_[1]_cert", $cert);
		&unlock_file($cert);
		}
	local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf,1);
	if ($key && -r "$_[1]_key" && $key ne $cert) {
		&lock_file($key);
		&set_ownership_permissions(
			$_[0]->{'uid'}, undef, undef, "$_[1]_key");
		&copy_source_dest_as_domain_user($_[0], "$_[1]_key", $key);
		&unlock_file($key);
		}
	local $ca = &apache::find_directive("SSLCACertificateFile", $vconf, 1);
	if ($ca && -r "$_[1]_ca") {
		&lock_file($ca);
		&set_ownership_permissions(
			$_[0]->{'uid'}, undef, undef, "$_[1]_ca");
		&copy_source_dest_as_domain_user($_[0], "$_[1]_ca", $ca);
		&unlock_file($ca);
		}

	# Re-setup any SSL passphrase
	&save_domain_passphrase($_[0]);

	# Re-save PHP mode, in case it changed
	&save_domain_php_mode($_[0], &get_domain_php_mode($_[0]));

	# Add Require all granted directive if this system is Apache 2.4
	&add_require_all_granted_directives($_[0], $_[0]->{'web_sslport'});

	# Fix Options lines
	my ($virt, $vconf, $conf) = &get_apache_virtual($_[0]->{'dom'},
							$_[0]->{'web_sslport'});
	if ($virt) {
		&fix_options_directives($vconf, $conf, 0);
		}

	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_noapache'});
	$rv = 0;
	}

&release_lock_web($_[0]);
&register_post_action(\&restart_apache);
return $rv;
}

# cert_info(&domain)
# Returns a hash of details of a domain's cert
sub cert_info
{
return &cert_file_info($_[0]->{'ssl_cert'}, $_[0]);
}

# cert_file_info(file, &domain)
# Returns a hash of details of a cert in some file
sub cert_file_info
{
local ($file, $d) = @_;
return undef if (!-r $file);
local %rv;
local $_;
local $cmd = "openssl x509 -in ".quotemeta($file)." -issuer -subject -enddate -startdate -text";
if ($d && &is_under_directory($d->{'home'}, $file)) {
	open(OUT, &command_as_user($d->{'user'}, 0, $cmd)." |");
	}
else {
	open(OUT, $cmd." |");
	}
while(<OUT>) {
	s/\r|\n//g;
	s/http:\/\//http:\|\|/g;	# So we can parse with regexp
	if (/subject=.*C\s*=\s*([^\/]+)/) {
		$rv{'c'} = $1;
		}
	if (/subject=.*ST\s*=\s*([^\/]+)/) {
		$rv{'st'} = $1;
		}
	if (/subject=.*L\s*=\s*([^\/]+)/) {
		$rv{'l'} = $1;
		}
	if (/subject=.*O\s*=\s*([^\/]+)/) {
		$rv{'o'} = $1;
		}
	if (/subject=.*OU\s*=\s*([^\/]+)/) {
		$rv{'ou'} = $1;
		}
	if (/subject=.*CN\s*=\s*([^\/]+)/) {
		$rv{'cn'} = $1;
		}
	if (/subject=.*emailAddress\s*=\s*([^\/]+)/) {
		$rv{'email'} = $1;
		}

	if (/issuer=.*C\s*=\s*([^\/]+)/) {
		$rv{'issuer_c'} = $1;
		}
	if (/issuer=.*ST\s*=\s*([^\/]+)/) {
		$rv{'issuer_st'} = $1;
		}
	if (/issuer=.*L\s*=\s*([^\/]+)/) {
		$rv{'issuer_l'} = $1;
		}
	if (/issuer=.*O\s*=\s*([^\/]+)/) {
		$rv{'issuer_o'} = $1;
		}
	if (/issuer=.*OU\s*=\s*([^\/]+)/) {
		$rv{'issuer_ou'} = $1;
		}
	if (/issuer=.*CN\s*=\s*([^\/]+)/) {
		$rv{'issuer_cn'} = $1;
		}
	if (/issuer=.*emailAddress\s*=\s*([^\/]+)/) {
		$rv{'issuer_email'} = $1;
		}
	if (/notAfter\s*=\s*(.*)/) {
		$rv{'notafter'} = $1;
		}
	if (/notBefore\s*=\s*(.*)/) {
		$rv{'notbefore'} = $1;
		}
	if (/Subject\s+Alternative\s+Name/i) {
		local $alts = <OUT>;
		$alts =~ s/^\s+//;
		foreach my $a (split(/[, ]+/, $alts)) {
			if ($a =~ /^DNS:(\S+)/) {
				push(@{$rv{'alt'}}, $1);
				}
			}
		}
	if (/RSA\s+Public\s+Key:\s+\((\d+)\s+bit/) {
		$rv{'size'} = $1;
		}
	if (/Modulus\s*\(.*\):/ || /Modulus:/) {
		$inmodulus = 1;
		}
	if (/^\s+([0-9a-f:]+)\s*$/ && $inmodulus) {
		$rv{'modulus'} .= $1;
		}
	if (/Exponent:\s*(\d+)/) {
		$rv{'exponent'} = $1;
		$inmodulus = 0;
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

# parse_notafter_date(str)
# Parse a date string like "Nov 30 07:46:00 2016 GMT" into a Unix time
sub parse_notafter_date
{
my ($str) = @_;
&foreign_require("mailboxes");
return &mailboxes::parse_mail_date($str);
}

# same_cert_file(file1, file2)
# Checks if the certs in some files are the same. This means either the
# same file, or the same modulus and expiry date.
sub same_cert_file
{
local ($file1, $file2) = @_;
return 1 if (!$file1 && !$file2);
return 0 if ($file1 && !$file2 || !$file1 && $file2);
local $info1 = &cert_file_info($file1);
local $info2 = &cert_file_info($file2);
return &same_file($file1, $file2) ||
       $info1->{'modulus'} && $info2->{'modulus'} &&
       $info1->{'modulus'} eq $info2->{'modulus'} &&
       $info1->{'notafter'} eq $info2->{'notafter'};
}

# check_passphrase(key-data, passphrase)
# Returns 0 if a passphrase is needed by not given, 1 if not needed, 2 if OK
sub check_passphrase
{
local ($newkey, $pass) = @_;
local $temp = &transname();
&open_tempfile(KEY, ">$temp", 0, 1);
&set_ownership_permissions(undef, undef, 0700, $temp);
&print_tempfile(KEY, $newkey);
&close_tempfile(KEY);
local $rv = &execute_command("openssl rsa -in ".quotemeta($temp).
			     " -text -passin pass:NONE");
if (!$rv) {
	return 1;
	}
if ($pass) {
	local $rv = &execute_command("openssl rsa -in ".quotemeta($temp).
				     " -text -passin pass:".quotemeta($pass));
	if (!$rv) {
		return 2;
		}
	}
return 0;
}

# get_key_size(file)
# Given an SSL key file, returns the size in bits
sub get_key_size
{
local ($file) = @_;
local $out = &backquote_command(
	"openssl rsa -in ".quotemeta($file)." -text 2>&1 </dev/null");
if ($out =~ /Private-Key:\s+\((\d+)/i) {
	return $1;
	}
return undef;
}

# save_domain_passphrase(&domain)
# Configure Apache to use the right passphrase for a domain, if one is needed.
# Otherwise, remove the passphrase config.
sub save_domain_passphrase
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne "web") {
	return &plugin_call($p, "feature_save_web_passphrase", $d);
	}
local $pass_script = "$ssl_passphrase_dir/$d->{'id'}";
&lock_file($pass_script);
local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
                                                   $d->{'web_sslport'});
return "SSL virtual host not found" if (!$vconf);
local @pps = &apache::find_directive("SSLPassPhraseDialog", $conf);
local @pps_str = &apache::find_directive_struct("SSLPassPhraseDialog", $conf);
&lock_file(@pps_str ? $pps_str[0]->{'file'} : $conf->[0]->{'file'});
local ($pps) = grep { $_ eq "exec:$pass_script" } @pps;
if ($d->{'ssl_pass'}) {
	# Create script, add to Apache config
	if (!-d $ssl_passphrase_dir) {
		&make_dir($ssl_passphrase_dir, 0700);
		}
	&open_tempfile(SCRIPT, ">$pass_script");
	&print_tempfile(SCRIPT, "#!/bin/sh\n");
	&print_tempfile(SCRIPT, "echo ".quotemeta($d->{'ssl_pass'})."\n");
	&close_tempfile(SCRIPT);
	&set_ownership_permissions(undef, undef, 0700, $pass_script);
	push(@pps, "exec:$pass_script");
	}
else {
	# Remove script and from Apache config
	if ($pps) {
		@pps = grep { $_ ne $pps } @pps;
		}
	&unlink_file($pass_script);
	}
&lock_file(@pps_str ? $pps_str[0]->{'file'} : $conf->[0]->{'file'});
&apache::save_directive("SSLPassPhraseDialog", \@pps, $conf, $conf);
&flush_file_lines();
&register_post_action(\&restart_apache, 1);
}

# check_cert_key_match(cert-text, key-text)
# Checks if the modulus for a cert and key match and are valid. Returns undef 
# on success or an error message on failure.
sub check_cert_key_match
{
local ($certtext, $keytext) = @_;
local $certfile = &transname();
local $keyfile = &transname();
foreach $tf ([ $certtext, $certfile ], [ $keytext, $keyfile ]) {
	&open_tempfile(CERTOUT, ">$tf->[1]", 0, 1);
	&print_tempfile(CERTOUT, $tf->[0]);
	&close_tempfile(CERTOUT);
	}
# Get certificate modulus
local $certmodout = &backquote_command(
	"openssl x509 -noout -modulus -in $certfile 2>&1");
$certmodout =~ /Modulus=([A-F0-9]+)/i ||
	return "Certificate data is not valid : $certmodout";
local $certmod = $1;

# Get key modulus
local $keymodout = &backquote_command(
	"openssl rsa -noout -modulus -in $keyfile 2>&1");
$keymodout =~ /Modulus=([A-F0-9]+)/i ||
	return "Key data is not valid : $keymodout";
local $keymod = $1;

# Make sure they match
$certmod eq $keymod ||
	return "Certificate and private key do not match";

return undef;
}

# validate_cert_format(data|file, type)
# Checks if some file or string contains valid cert or key data, and returns
# an error message if not. The type can be one of 'key', 'cert', 'ca' or 'csr'
sub validate_cert_format
{
local ($data, $type) = @_;
if ($data =~ /^\//) {
	$data = &read_file_contents($data);
	}
local %headers = ( 'key' => '(RSA )?PRIVATE KEY',
		   'cert' => 'CERTIFICATE',
		   'ca' => 'CERTIFICATE',
		   'csr' => 'CERTIFICATE REQUEST',
		   'newkey' => '(RSA ?)PRIVATE KEY' );
local $h = $headers{$type};
$h || return "Unknown SSL file type $type";
local @lines = grep { /\S/ } split(/\r?\n/, $data);
local $begin = quotemeta("-----BEGIN ").$h.quotemeta("-----");
local $end = quotemeta("-----END ").$h.quotemeta("-----");
$lines[0] =~ /^$begin$/ || return "Data does not start with line ".
				  "-----BEGIN $h-----";
$lines[$#lines] =~ /^$end$/ || return "Data does not end with line ".
				      "-----END $h-----";
for(my $i=1; $i<$#lines; $i++) {
	$lines[$i] =~ /^[A-Za-z0-9\+\/=]+\s*$/ ||
	    ($type eq 'ca' && ($lines[$i] =~ /^$begin$/ ||
			       $lines[$i] =~ /^$end$/)) ||
		return "Line ".($i+1)." does not look like PEM format";
	}
@lines > 4 || return "Data only has ".scalar(@lines)." lines";
return undef;
}

# cert_pem_data(&domain)
# Returns a domain's cert in PEM format
sub cert_pem_data
{
local ($d) = @_;
local $data = &read_file_contents_as_domain_user($d, $d->{'ssl_cert'});
if ($data =~ /(-----BEGIN\s+CERTIFICATE-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+CERTIFICATE-----)/) {
	return $1;
	}
return undef;
}

# key_pem_data(&domain)
# Returns a domain's key in PEM format
sub key_pem_data
{
local ($d) = @_;
local $data = &read_file_contents_as_domain_user($d, $d->{'ssl_key'} ||
						     $d->{'ssl_cert'});
if ($data =~ /(-----BEGIN\s+RSA\s+PRIVATE\s+KEY-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+RSA\s+PRIVATE\s+KEY-----)/) {
	return $1;
	}
elsif ($data =~ /(-----BEGIN\s+PRIVATE\s+KEY-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+PRIVATE\s+KEY-----)/) {
	return $1;
	}
return undef;
}

# cert_pkcs12_data(&domain)
# Returns a domain's cert in PKCS12 format
sub cert_pkcs12_data
{
local ($d) = @_;
local $cmd = "openssl pkcs12 -in ".quotemeta($d->{'ssl_cert'}).
             " -inkey ".quotemeta($_[0]->{'ssl_key'}).
	     " -export -passout pass: -nokeys";
open(OUT, &command_as_user($d->{'user'}, 0, $cmd)." |");
while(<OUT>) {
	$data .= $_;
	}
close(OUT);
return $data;
}

# key_pkcs12_data(&domain)
# Returns a domain's key in PKCS12 format
sub key_pkcs12_data
{
local ($d) = @_;
local $cmd = "openssl pkcs12 -in ".quotemeta($d->{'ssl_cert'}).
             " -inkey ".quotemeta($_[0]->{'ssl_key'}).
	     " -export -passout pass: -nocerts";
open(OUT, &command_as_user($d->{'user'}, 0, $cmd)." |");
while(<OUT>) {
	$data .= $_;
	}
close(OUT);
return $data;
}

# setup_ipkeys(&domain, &miniserv-getter, &miniserv-saver, &post-action)
# Add the per-IP/domain SSL key for some domain
sub setup_ipkeys
{
local ($d, $getfunc, $putfunc, $postfunc) = @_;
&foreign_require("webmin");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
local @ips;
if ($d->{'virt'}) {
	push(@ips, $d->{'ip'});
	}
if (&get_webmin_version() >= 1.834) {
	push(@ips, $d->{'dom'}, "*.$d->{'dom'}");
	}
if (@ips) {
	push(@ipkeys, { 'ips' => \@ips,
			'key' => $d->{'ssl_key'},
			'cert' => $d->{'ssl_cert'},
			'extracas' => $d->{'ssl_ca'}, });
	&webmin::save_ipkeys(\%miniserv, \@ipkeys);
	&$putfunc(\%miniserv);
	&register_post_action($postfunc);
	}
return 1;
}

# delete_ipkeys(&domain, &miniserv-getter, &miniserv-saver, &post-action)
# Remove the per-IP/domain SSL key for some domain
sub delete_ipkeys
{
local ($d, $getfunc, $putfunc, $postfunc) = @_;
&foreign_require("webmin");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
local @newipkeys;
foreach my $ipk (@ipkeys) {
	my $search = $d->{'virt'} ? $d->{'ip'} : $d->{'dom'};
	if (&indexof($search, @{$ipk->{'ips'}}) < 0) {
		push(@newipkeys, $ipk);
		}
	}
if (@ipkeys != @newipkeys) {
	&webmin::save_ipkeys(\%miniserv, \@newipkeys);
	&$putfunc(\%miniserv);
	&register_post_action($postfunc);
	return 1;
	}
return 0;
}

# modify_ipkeys(&domain, &olddomain, &miniserv-getter, &miniserv-saver,
# 		&post-action)
# Remove and then re-add the per-IP SSL key for a domain, to pick up any
# IP or home directory change
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
&require_apache();
local @dirs;
push(@dirs, "SSLEngine on");
push(@dirs, "SSLCertificateFile $d->{'ssl_cert'}");
push(@dirs, "SSLCertificateKeyFile $d->{'ssl_key'}");
if ($d->{'ssl_chain'}) {
	push(@dirs, "SSLCACertificateFile $d->{'ssl_chain'}");
	}
if ($tmpl->{'web_sslprotos'}) {
	push(@dirs, "SSLProtocol ".$tmpl->{'web_sslprotos'});
	}
else {
	local @tls = ( "SSLv2", "SSLv3" );
	if ($apache::httpd_modules{'core'} >= 2.4) {
		push(@tls, "TLSv1");
		if (&get_openssl_version() >= 1) {
			push(@tls, "TLSv1.1");
			}
		}
	push(@dirs, "SSLProtocol ".join(" ", "all", map { "-".$_ } @tls));
	}
return @dirs;
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
elsif ($out !~ /subject=.*(CN|O)=/) {
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
$mode = "ca" if ($mode eq "chain");
return $config{$mode.'_tmpl'} ?
	    &absolute_domain_path($d,
	     &substitute_domain_template($config{$mode.'_tmpl'}, $d)) :
	    "$d->{'home'}/ssl.".$mode;
}

# set_certificate_permissions(&domain, file)
# Set permissions on a cert file so that Apache can read them.
sub set_certificate_permissions
{
local ($d, $file) = @_;
&set_permissions_as_domain_user($d, 0700, $file);
}

# check_domain_certificate(domain-name, &domain-with-cert|&cert-info)
# Returns 1 if some virtual server's certificate can be used for a particular
# domain, 0 if not. Based on the common names, including wildcards and UCC
sub check_domain_certificate
{
local ($dname, $d_or_info) = @_;
local $info = $d_or_info->{'dom'} ? &cert_info($d_or_info) : $d_or_info;
foreach my $check ($dname, "www.".$dname) {
	if (lc($info->{'cn'}) eq lc($check)) {
		# Exact match
		return 1;
		}
	elsif ($info->{'cn'} =~ /^\*\.(\S+)$/ &&
	       (lc($check) eq lc($1) || $check =~ /^([^\.]+)\.\Q$1\E$/i)) {
		# Matches wildcard
		return 1;
		}
	elsif ($info->{'cn'} eq '*') {
		# Cert is for * , which matches everything
		return 1;
		}
	else {
		# Check for subjectAltNames match (as seen in UCC certs)
		foreach my $a (@{$info->{'alt'}}) {
			if (lc($a) eq $check ||
			    $a =~ /^\*\.(\S+)$/ &&
			    (lc($check) eq lc($1) ||
			     $check =~ /([^\.]+)\.\Q$1\E$/i)) {
				return 1;
				}
			}
		}
	}
return 0;
}

# list_domain_certificate(&domain|&cert-info)
# Returns a list of domain names that are in the cert for a domain
sub list_domain_certificate
{
local ($d_or_info) = @_;
local $info = $d_or_info->{'dom'} ? &cert_info($d_or_info) : $d_or_info;
local @rv;
push(@rv, $info->{'cn'});
push(@rv, @{$info->{'alt'}});
return &unique(@rv);
}

# self_signed_cert(&domain)
# Returns 1 if some domain has a self-signed certificate
sub self_signed_cert
{
local ($d) = @_;
local $info = &cert_info($d);
return $info->{'issuer_cn'} eq $info->{'cn'} &&
       $info->{'issuer_o'} eq $info->{'o'};
}

# find_openssl_config_file()
# Returns the full path to the OpenSSL config file, or undef if not found
sub find_openssl_config_file
{
&foreign_require("webmin");
return &webmin::find_openssl_config_file();
}

# generate_self_signed_cert(certfile, keyfile, size, days, country, state,
# 			    city, org, orgunit, commonname, email, &altnames,
# 			    &domain, [cert-type])
# Generates a new self-signed cert, and stores it in the given cert and key
# files. Returns undef on success, or an error message on failure.
sub generate_self_signed_cert
{
local ($certfile, $keyfile, $size, $days, $country, $state, $city, $org,
       $orgunit, $common, $email, $altnames, $d, $ctype) = @_;
$ctype ||= $config{'default_ctype'};
&foreign_require("webmin");
$size ||= $webmin::default_key_size;
$days ||= 1825;

# Prepare for SSL alt names
local @cnames = ( $common );
push(@cnames, @$altnames) if ($altnames);
local $conf = &webmin::build_ssl_config(\@cnames);
local $subject = &webmin::build_ssl_subject($country, $state, $city, $org,
					    $orgunit, \@cnames, $email);

# Call openssl and write to temp files
local $outtemp = &transname();
local $keytemp = &transname();
local $certtemp = &transname();
local $ctypeflag = $ctype eq "sha2" ? "-sha256" : "";
local $out = &backquote_logged(
	"openssl req $ctypeflag -reqexts v3_req -newkey rsa:$size ".
	"-x509 -nodes -out $certtemp -keyout $keytemp ".
	"-days $days -config $conf -subj ".quotemeta($subject)." -utf8 2>&1");
local $rv = $?;
if (!-r $certtemp || !-r $keytemp || $rv) {
	# Failed .. return error
	return &text('csr_ekey', "<pre>$out</pre>");
	}

# Save as domain owner
&open_tempfile_as_domain_user($d, CERT, ">$certfile");
&print_tempfile(CERT, &read_file_contents($certtemp));
&close_tempfile_as_domain_user($d, CERT);
&open_tempfile_as_domain_user($d, KEY, ">$keyfile");
&print_tempfile(KEY, &read_file_contents($keytemp));
&close_tempfile_as_domain_user($d, KEY);

return undef;
}

# generate_certificate_request(csrfile, keyfile, size, country, state,
# 			       city, org, orgunit, commonname, email, &altnames,
# 			       &domain, [cert-type])
# Generates a new self-signed cert, and stores it in the given csr and key
# files. Returns undef on success, or an error message on failure.
sub generate_certificate_request
{
local ($csrfile, $keyfile, $size, $country, $state, $city, $org,
       $orgunit, $common, $email, $altnames, $d, $ctype) = @_;
$ctype ||= $config{'cert_type'};
&foreign_require("webmin");
$size ||= $webmin::default_key_size;

# Generate the key
local $keytemp = &transname();
local $out = &backquote_command("openssl genrsa -out ".quotemeta($keytemp)." $size 2>&1 </dev/null");
local $rv = $?;
if (!-r $keytemp || $rv) {
	return &text('csr_ekey', "<pre>$out</pre>");
	}

# Generate the CSR
local @cnames = ( $common );
push(@cnames, @$altnames) if ($altnames);
local ($ok, $csrtemp) = &webmin::generate_ssl_csr($keytemp, $country, $state, $city, $org, $orgunit, \@cnames, $email, $ctype);
if (!$ok) {
	return &text('csr_ecsr', "<pre>$csrtemp</pre>");
	}

# Copy into place
&open_tempfile_as_domain_user($d, KEY, ">$keyfile");
&print_tempfile(KEY, &read_file_contents($keytemp));
&close_tempfile_as_domain_user($d, KEY);

&open_tempfile_as_domain_user($d, CERT, ">$csrfile");
&print_tempfile(CERT, &read_file_contents($csrtemp));
&close_tempfile_as_domain_user($d, CERT);
return undef;
}

# obtain_lock_ssl(&domain)
# Lock the Apache config file for some domain, and the Webmin config
sub obtain_lock_ssl
{
local ($d) = @_;
return if (!$config{'ssl'});
&obtain_lock_anything($d);
&obtain_lock_web($d) if ($d->{'web'});
if ($main::got_lock_ssl == 0) {
	local @sfiles = ($ENV{'MINISERV_CONFIG'} ||
		         "$config_directory/miniserv.conf",
		        $config_directory =~ /^(.*)\/webmin$/ ?
		         "$1/usermin/miniserv.conf" :
			 "/etc/usermin/miniserv.conf");
	foreach my $k ('ssl_cert', 'ssl_key', 'ssl_chain') {
		push(@sfiles, $d->{$k}) if ($d->{$k});
		}
	@sfiles = &unique(@sfiles);
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
&release_lock_web($d) if ($d->{'web'});
if ($main::got_lock_ssl == 1) {
	foreach my $f (@main::got_lock_ssl_files) {
		&unlock_file($f);
		}
	}
$main::got_lock_ssl-- if ($main::got_lock_ssl);
&release_lock_anything($d);
}

# find_matching_certificate(&domain)
# For a domain with SSL being enabled, check if another domain on the same IP
# already has a matching cert. If so, update the domain hash's cert file
sub find_matching_certificate
{
local ($d) = @_;
local @sslclashes = grep { $_->{'ip'} eq $d->{'ip'} &&
			   $_->{'ssl'} &&
			   $_->{'id'} ne $d->{'id'} &&
			   !$_->{'ssl_same'} } &list_domains();
foreach my $sslclash (@sslclashes) {
	if (&check_domain_certificate($d->{'dom'}, $sslclash)) {
		# Found a match, so add a link to it
		$d->{'ssl_cert'} = $sslclash->{'ssl_cert'};
		$d->{'ssl_key'} = $sslclash->{'ssl_key'};
		$d->{'ssl_same'} = $sslclash->{'id'};
		$d->{'ssl_chain'} = &get_website_ssl_file($sslclash, 'ca');
		last;
		}
	}
}

# generate_default_certificate(&domain)
# If a domain doesn't have a cert file set, pick one and generate a self-signed
# cert if needed. May print stuff.
sub generate_default_certificate
{
local ($d) = @_;
$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
if (!-r $d->{'ssl_cert'} && !-r $d->{'ssl_key'}) {
	# Need to do it
	local $temp = &transname();
	&$first_print($text{'setup_openssl'});
	&lock_file($d->{'ssl_cert'});
	&lock_file($d->{'ssl_key'});
	local $err = &generate_self_signed_cert(
		$d->{'ssl_cert'}, $d->{'ssl_key'}, undef, 1825,
		undef, undef, undef, $d->{'owner'}, undef,
		"*.$d->{'dom'}", $d->{'emailto_addr'}, [ $d->{'dom'} ], $d);
	if ($err) {
		&$second_print(&text('setup_eopenssl', $err));
		return 0;
		}
	else {
		&set_certificate_permissions($d, $d->{'ssl_cert'});
		&set_certificate_permissions($d, $d->{'ssl_key'});
		if (&has_command("chcon")) {
			&execute_command("chcon -R -t httpd_config_t ".quotemeta($d->{'ssl_cert'}).">/dev/null 2>&1");
			&execute_command("chcon -R -t httpd_config_t ".quotemeta($d->{'ssl_key'}).">/dev/null 2>&1");
			}
		&$second_print($text{'setup_done'});
		}
	&unlock_file($d->{'ssl_cert'});
	&unlock_file($d->{'ssl_key'});
	return 1;
	}
return 0;
}

# break_ssl_linkage(&domain, &old-same-domain)
# If domain was using the SSL cert from old-same-domain before, break the link
# by copying the cert into the default location for domain and updating the
# domain and Apache config to match
sub break_ssl_linkage
{
local ($d, $samed) = @_;
foreach my $k ('cert', 'key', 'chain') {
	if ($d->{'ssl_'.$k}) {
		$d->{'ssl_'.$k} = &default_certificate_file($d, $k);
		if ($d->{'user'} eq $samed->{'user'}) {
			&copy_source_dest_as_domain_user(
				$d, $samed->{'ssl_'.$k}, $d->{'ssl_'.$k});
			}
		else {
			&copy_source_dest($samed->{'ssl_'.$k}, $d->{'ssl_'.$k});
			}
		}
	}
delete($d->{'ssl_same'});
if ($d->{'web'}) {
	local ($ovirt, $ovconf, $conf) = &get_apache_virtual(
		$d->{'dom'}, $d->{'web_sslport'});
	if ($ovirt) {
		&apache::save_directive("SSLCertificateFile",
			[ $d->{'ssl_cert'} ], $ovconf, $conf);
		&apache::save_directive("SSLCertificateKeyFile",
			$d->{'ssl_key'} ? [ $d->{'ssl_key'} ] : [ ],
			$ovconf, $conf);
		&apache::save_directive("SSLCACertificateFile",
			$d->{'ssl_chain'} ? [ $d->{'ssl_chain'} ] : [ ],
			$ovconf, $conf);
		&flush_file_lines($ovirt->{'file'});
		}
	}
}

# break_invalid_ssl_linkages(&domain, [&new-cert])
# Find all domains that link to this domain's SSL cert, and if their domain
# names are no longer legit for the cert, break the link.
sub break_invalid_ssl_linkages
{
local ($d, $newcert) = @_;
foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
	if (!&check_domain_certificate($od->{'dom'}, $newcert || $d)) {
		&obtain_lock_ssl($d);
		&break_ssl_linkage($od, $d);
		&save_domain($od);
		&release_lock_ssl($d);
		}
	}
}

# sync_dovecot_ssl_cert(&domain, [enable-or-disable])
# If supported, configure Dovecot to use this domain's SSL cert for its IP
sub sync_dovecot_ssl_cert
{
local ($d, $enable) = @_;

# Check if dovecot is installed and supports this feature
return undef if (!$config{'dovecot_ssl'});
return undef if (!&foreign_installed("dovecot"));
&foreign_require("dovecot");
my $ver = &dovecot::get_dovecot_version();
return undef if ($ver < 2);

# Check if dovecot is using SSL globally
my $conf = &dovecot::get_config();
my $sslyn = &dovecot::find_value("ssl", $conf);
return undef if ($sslyn !~ /yes|required/i);
my $ssldis = &dovecot::find_value("ssl_disable", $conf);
return undef if ($ssldis =~ /yes/i);

my $cfile = &dovecot::get_config_file();
&lock_file($cfile);

if ($d->{'virt'}) {
	# Domain has it's own IP

	# Find the existing block for the IP
	my @loc = grep { $_->{'name'} eq 'local' &&
			 $_->{'section'} } @$conf;
	my ($l) = grep { $_->{'value'} eq $d->{'ip'} } @loc;
	my $imap;
	if ($l) {
		($imap) = grep { $_->{'name'} eq 'protocol' &&
				 $_->{'value'} eq 'imap' &&
				 $_->{'enabled'} &&
				 $_->{'sectionname'} eq 'local' &&
				 $_->{'sectionvalue'} eq $d->{'ip'} } @$conf;
		}

	if ($enable) {
		# Needs a cert for the IP
		local $chain = &get_website_ssl_file($d, "ca");
		if (!$l) {
			$l = { 'name' => 'local',
			       'value' => $d->{'ip'},
			       'members' => [],
			       'file' => $cfile };
			my $lref = &read_file_lines($l->{'file'}, 1);
			$l->{'line'} = $l->{'eline'} = scalar(@$lref);
			&dovecot::save_section($conf, $l);
			push(@$conf, $l);
			}
		if (!$imap) {
			$imap = { 'name' => 'protocol',
				  'value' => 'imap',
				  'members' => [
					{ 'name' => 'ssl_cert',
					  'value' => "<".$d->{'ssl_cert'} },
					{ 'name' => 'ssl_key',
					  'value' => "<".$d->{'ssl_key'} },
					],
				  'indent' => 1,
				  'file' => $l->{'file'},
				  'line' => $l->{'line'} + 1,
				  'eline' => $l->{'line'} };
			if ($chain) {
				push(@{$imap->{'members'}},
				     { 'name' => 'ssl_ca',
				       'value' => "<".$chain });
				}
			&dovecot::save_section($conf, $imap);
			push(@{$l->{'members'}}, $imap);
			}
		else {
			eval {
				local $main::error_must_die = 1;
				&dovecot::save_directive($l->{'members'},
					"ssl_cert", "<".$d->{'ssl_cert'},
					"protocol", "imap");
				&dovecot::save_directive($l->{'members'},
					"ssl_key", "<".$d->{'ssl_key'},
					"protocol", "imap");
				if ($chain) {
					&dovecot::save_directive(
						$l->{'members'}, "ssl_ca",
						"<".$chain, "protocol", "imap");
					}
				}
			}
		&flush_file_lines($imap->{'file'});
		}
	else {
		# Doesn't need one, either because SSL isn't enabled or the
		# domain doesn't have a private IP. So remove the local block.
		if ($l) {
			my $lref = &read_file_lines($l->{'file'});
			splice(@$lref, $l->{'line'},
			       $l->{'eline'}-$l->{'line'}+1);
			&flush_file_lines($l->{'file'});
			undef(@dovecot::get_config_cache);
			}
		}
	}
else {
	# Domain has no IP, but Dovecot supports SNI in version 2
	my @loc = grep { $_->{'name'} eq 'local_name' &&
			 $_->{'section'} } @$conf;
	my @sslnames = &get_hostnames_for_ssl($d);
	my %sslnames = map { $_, 1 } @sslnames;
	my @myloc = grep { $sslnames{$_->{'value'}} } @loc;
	if ($enable && !@myloc) {
		# Need to add
		foreach my $n (@sslnames) {
			my $l = { 'name' => 'local_name',
				  'value' => $n,
				  'members' => [
					{ 'name' => 'ssl_cert',
					  'value' => "<".$d->{'ssl_cert'} },
					{ 'name' => 'ssl_key',
					  'value' => "<".$d->{'ssl_key'} },
					],
				  'file' => $cfile };
			if ($chain) {
				push(@{$l->{'members'}},
				     { 'name' => 'ssl_ca',
				       'value' => '<'.$chain });
				}
			my $lref = &read_file_lines($l->{'file'}, 1);
			$l->{'line'} = $l->{'eline'} = scalar(@$lref);
			&dovecot::save_section($conf, $l);
			push(@$conf, $l);
			}
		}
	elsif (!$enable && @myloc) {
		# Need to remove
		foreach my $l (reverse(@myloc)) {
			my $lref = &read_file_lines($l->{'file'});
			splice(@$lref, $l->{'line'},
			       $l->{'eline'}-$l->{'line'}+1);
			&flush_file_lines($l->{'file'});
			}
		undef(@dovecot::get_config_cache);
		}
	elsif ($enable && @myloc) {
		# May need to update paths
		foreach my $l (@myloc) {
			&dovecot::save_directive($l->{'members'},
                                        "ssl_cert", "<".$d->{'ssl_cert'});
			&dovecot::save_directive($l->{'members'},
                                        "ssl_key", "<".$d->{'ssl_key'});
			}
		}
	}
&unlock_file($cfile);
if ($changed) {
	&dovecot::apply_configuration();
	}
}

# get_dovecot_ssl_cert(&domain)
# Returns the path to the cert, key and CA cert, and optionally domain and IP
# in the Dovecot config for a domain, if any
sub get_dovecot_ssl_cert
{
my ($d) = @_;
return ( ) if (!&foreign_installed("dovecot"));
&foreign_require("dovecot");
my $ver = &dovecot::get_dovecot_version();
return ( ) if ($ver < 2);
my $conf = &dovecot::get_config();
my @rv = &get_dovecot_ssl_cert_name($d, $conf);
@rv = &get_dovecot_ssl_cert_ip($d, $conf) if (!@rv);
return @rv;
}

# get_dovecot_ssl_cert_ip(&domain, &conf)
# Lookup a domain's Dovecot cert by IP address
sub get_dovecot_ssl_cert_ip
{
my ($d, $conf) = @_;
my @loc = grep { $_->{'name'} eq 'local' &&
		 $_->{'section'} } @$conf;
my ($l) = grep { $_->{'value'} eq $d->{'ip'} } @loc;
return ( ) if (!$l);
my ($imap) = grep { $_->{'name'} eq 'protocol' &&
		    $_->{'value'} eq 'imap' &&
		    $_->{'enabled'} &&
		    $_->{'sectionname'} eq 'local' &&
		    $_->{'sectionvalue'} eq $d->{'ip'} } @$conf;
return ( ) if (!$imap);
my %mems = map { $_->{'name'}, $_->{'value'} } @{$imap->{'members'}};
return ( ) if (!$mems{'ssl_cert'});
my @rv = ( $mems{'ssl_cert'}, $mems{'ssl_key'}, undef, $d->{'ip'}, undef );
foreach my $r (@rv) {
	$r =~ s/^<//;
	}
return @rv;
}

# get_dovecot_ssl_cert_name(&domain, &conf)
# Lookup a domain's Dovecot cert by domain name
sub get_dovecot_ssl_cert_name
{
my ($d, $conf) = @_;
my @loc = grep { $_->{'name'} eq 'local_name' &&
		 $_->{'section'} } @$conf;
my ($l) = grep { $_->{'value'} eq $d->{'dom'} } @loc;
return ( ) if (!$l);
my %mems = map { $_->{'name'}, $_->{'value'} } @{$l->{'members'}};
return ( ) if (!$mems{'ssl_cert'});
my @rv = ( $mems{'ssl_cert'}, $mems{'ssl_key'}, undef, undef, $d->{'dom'} );
foreach my $r (@rv) {
	$r =~ s/^<//;
	}
return @rv;
}

# sync_postfix_ssl_cert(&domain, enable)
# Configure Postfix to use a domain's SSL cert for connections on its IP
sub sync_postfix_ssl_cert
{
local ($d, $enable) = @_;

# Check if Postfix is in use
return undef if ($config{'mail_system'} != 0);
return undef if (!$config{'postfix_ssl'});

# Check if using SSL globally
&foreign_require("postfix");
local $cfile = &postfix::get_real_value("smtpd_tls_cert_file");
local $kfile = &postfix::get_real_value("smtpd_tls_key_file");
local $cafile = &postfix::get_real_value("smtpd_tls_CAfile");
return undef if ($enable && (!$cfile || !$kfile));

# Find the existing master file entry
&lock_file($postfix::config{'postfix_master'});
local $master = &postfix::get_master_config();
local $defip = &get_default_ip();

# Work out which flags are needed
local $chain = $s->{'ssl'} ? &get_website_ssl_file($d, 'ca') : $cafile;
local @flags = ( [ "smtpd_tls_cert_file",
		   $d->{'ssl'} ? $d->{'ssl_cert'} : $cfile ],
		 [ "smtpd_tls_key_file",
		   $d->{'ssl'} ? $d->{'ssl_key'} : $kfile ] );
push(@flags, [ "smtpd_tls_CAfile", $chain ]) if ($chain);

local $changed = 0;
foreach my $pfx ('smtp', 'submission') {
	# Find the existing entry for the IP, and for the default service
	local $already;
	local $smtp;
	local @others;
	local $lsmtp;
	foreach my $m (@$master) {
		if ($m->{'name'} eq $d->{'ip'}.':'.$pfx && $m->{'enabled'} &&
		    $d->{'ip'} ne $defip) {
			# Entry for service for the domain
			$already = $m;
			}
		if (($m->{'name'} eq $pfx || $m->{'name'} eq $defip.':'.$pfx) &&
		    $m->{'type'} eq 'inet' && $m->{'enabled'}) {
			# Entry for default service
			$smtp = $m;
			}
		if ($m->{'name'} =~ /^([0-9\.]+):\Q$pfx\E$/ &&
		    $m->{'enabled'} && $1 ne $d->{'ip'} && $1 ne $defip) {
			# Entry for some other domain
			if ($1 eq "127.0.0.1") {
				$lsmtp = $m;
				}
			else {
				push(@others, $m);
				}
			}
		}
	next if (!$smtp);

	if ($enable) {
		# Create or update the entry
		if (!$already) {
			# Create based on smtp inet entry
			$already = { %$smtp };
			delete($already->{'line'});
			delete($already->{'uline'});
			$already->{'name'} = $d->{'ip'}.':'.$pfx;
			foreach my $f (@flags) {
				$already->{'command'} .=
					" -o ".$f->[0]."=".$f->[1];
				}
			&postfix::create_master($already);
			$changed = 1;

			# If the primary smtp entry isn't bound to an IP, fix it
			# to prevent IP clashes
			if ($smtp->{'name'} eq $pfx) {
				$smtp->{'name'} = $defip.':'.$pfx;
				&postfix::modify_master($smtp);

				# Also add an entry to listen on 127.0.0.1
				if (!$lsmtp) {
					$lsmtp = { %$smtp };
					delete($lsmtp->{'line'});
					delete($lsmtp->{'uline'});
					$lsmtp->{'name'} = '127.0.0.1:'.$pfx;
					&postfix::create_master($lsmtp);
					}
				}
			}
		else {
			# Update cert file paths
			local $oldcommand = $already->{'command'};
			foreach my $f (@flags) {
				($already->{'command'} =~
				  s/-o\s+\Q$f->[0]\E=(\S+)/-o $f->[0]=$f->[1]/)
				||
				  ($already->{'command'} .=
				   " -o ".$f->[0]."=".$f->[1]);
				}
			if ($oldcommand ne $already->{'command'}) {
				&postfix::modify_master($already);
				$changed = 1;
				}
			}
		}
	else {
		# Remove the entry
		if ($already) {
			&postfix::delete_master($already);
			$changed = 1;
			}
		if (!@others && $smtp->{'name'} ne $pfx) {
			# If the default service has an IP but this is no longer
			# needed, remove it
			$smtp->{'name'} = $pfx;
			&postfix::modify_master($smtp);
			$changed = 1;

			# Also remove 127.0.0.1 entry
			if ($lsmtp) {
				&postfix::delete_master($lsmtp);
				}
			}
		}
	}
&unlock_file($postfix::config{'postfix_master'});

if ($changed) {
	&register_post_action(\&restart_mail_server);
	}
}

# get_postfix_ssl_cert(&domain)
# Returns the path to the cert, key and CA cert in the Postfix config for
# a domain, if any
sub get_postfix_ssl_cert
{
my ($d) = @_;
return ( ) if ($config{'mail_system'} != 0);
&foreign_require("postfix");
local $master = &postfix::get_master_config();
foreach my $m (@$master) {
	if ($m->{'name'} eq $d->{'ip'}.':smtp' && $m->{'enabled'}) {
		if ($m->{'command'} =~ /smtpd_tls_cert_file=(\S+)/) {
			my @rv = ( $1 );
			push(@rv, $m->{'command'} =~ /smtpd_tls_key_file=(\S+)/
					? $1 : undef);
			push(@rv, $m->{'command'} =~ /smtpd_tls_CAfile=(\S+)/
					? $1 : undef);
			push(@rv, $d->{'ip'});
			return @rv;
			}
		}
	}
return ( );
}

# get_hostnames_for_ssl(&domain)
# Returns a list of names that should be used in an SSL cert, based on their
# IP address and whether Apache is configured to accept them.
sub get_hostnames_for_ssl
{
my ($d) = @_;
my @rv = ( $d->{'dom'} );
my $defvirt;
my $p = &domain_has_website($d);
return @rv if (!$p);
if ($p eq "web") {
	$defvirt = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
	}
else {
	$defvirt = &plugin_call($p, "feature_get_domain_web_config",
				$d->{'dom'}, $d->{'web_port'});
	}
return @rv if (!$defvirt);
foreach my $full ("www.".$d->{'dom'}, "mail.".$d->{'dom'},
		  &get_autoconfig_hostname($d)) {
	my $virt;
	if ($p eq "web") {
		$virt = &get_apache_virtual($full, $d->{'web_port'});
		}
	else {
		$virt = &plugin_call($p, "feature_get_domain_web_config",
				     $full, $d->{'web_port'});
		}
	next if (!$virt || $virt ne $defvirt);
	if ($d->{'dns'}) {
		my $recs = &get_domain_dns_records($d);
		my ($r) = grep { $_->{'name'} eq $full."." } @$recs;
		push(@rv, $full);
		}
	elsif (&to_ipaddress($full)) {
		push(@rv, $full);
		}
	}
if (!$d->{'alias'}) {
	# Add aliases of this domain that have SSL enabled
	foreach my $alias (&get_domain_by("alias", $d->{'id'})) {
		if (&domain_has_website($alias)) {
			push(@rv, &get_hostnames_for_ssl($alias));
			}
		}
	}
return &unique(@rv);
}

# apply_letsencrypt_cert_renewals()
# Check all domains that need a new Let's Encrypt cert
sub apply_letsencrypt_cert_renewals
{
foreach my $d (&list_domains()) {
	# Does the domain have SSL enabled and a renewal policy?
	next if (!&domain_has_ssl($d) || !$d->{'letsencrypt_renew'});

	# Is the domain enabled?
	next if ($d->{'disabled'});

	# Get the cert and date
	my $info = &cert_info($d);
	next if (!$info);
	my $expiry = &parse_notafter_date($info->{'notafter'});

	# Is the current cert even from Let's Encrypt?
	next if ($info->{'issuer_cn'} !~ /Let's\s+Encrypt/i);

	# Figure out when the cert was last renewed. This is the max of the
	# date in the cert and the time recorded in Virtualmin
	my $ltime = &parse_notafter_date($info->{'notbefore'});
	$ltime = $d->{'letsencrypt_last'}
		if ($d->{'letsencrypt_last'} > $ltime);

	# If an attempt was made in the last hour, skip for now to prevent
	# hammering the Let's Encrypt serivce
	next if (time() - $d->{'letsencrypt_last'} < 60*60);

	# Is it time? Either the user-chosen number of months has passed, or
	# the cert is within 5 days of expiry
	my $age = time() - $ltime;
	if ($age >= $d->{'letsencrypt_renew'} * 30 * 24 * 60 * 60 ||
	    $expiry && $expiry - time() < 5 * 24 * 60 * 60) {

		# Run the before command
		&set_domain_envs($d, "SSL_DOMAIN");
		my $merr = &making_changes();
		&reset_domain_envs($d);
	
		# Time to do it!
		my $phd = &public_html_dir($d);
		my ($ok, $cert, $key, $chain);
		my @dnames;
		if ($d->{'letsencrypt_dname'}) {
			@dnames = split(/\s+/, $d->{'letsencrypt_dname'});
			}
		else {
			@dnames = &get_hostnames_for_ssl($d);
			}
		&foreign_require("webmin");
		if ($merr) {
			# Pre-command failed
			$ok = 0;
			$cert = $merr;
			}
		else {
			($ok, $cert, $key, $chain) =
				&request_domain_letsencrypt_cert($d, \@dnames);
			}

		my ($subject, $body);
		if (!$ok) {
			# Failed! Tell the user
			$subject = $text{'letsencrypt_sfailed'};
			$body = &text('letsencrypt_bfailed',
				      join(", ",@dnames), $cert);
			$d->{'letsencrypt_last'} = time();
			$d->{'letsencrypt_last_failure'} = time();
			$cert =~ s/\r?\n/\t/g;
			$d->{'letsencrypt_last_err'} = $cert;
			&save_domain($d);
			}
		else {
			# Figure out which services (webmin, postfix, etc)
			# were using the old cert
			my @before;
			foreach my $svc (&get_all_service_ssl_certs($d, 0)) {
				if (&same_cert_file(
				    $d->{'ssl_cert'}, $svc->{'cert'})) {
					push(@before, $svc);
					}
				}

			# Copy into place
			&obtain_lock_ssl($d);
			&install_letsencrypt_cert($d, $cert, $key, $chain);
			$d->{'letsencrypt_last'} = time();
			$d->{'letsencrypt_last_success'} = time();
			delete($d->{'letsencrypt_last_err'});
			&save_domain($d);
			&release_lock_ssl($d);

			# Apply any per-domain cert to Dovecot and Postfix
			&sync_dovecot_ssl_cert($d, 1);
			if ($d->{'virt'}) {
				&sync_postfix_ssl_cert($d, 1);
				}

			# Update DANE DNS records
			&sync_domain_tlsa_records($d);

			# Update services that were using the old cert
			foreach my $svc (@before) {
				&push_all_print();
				&set_all_null_print();
				my $func = "copy_".$svc->{'id'}."_ssl_service";
				&$func($d);
				&pop_all_print();
				}

			# Call the post command
			&set_domain_envs($d, "SSL_DOMAIN");
			&made_changes();
			&reset_domain_envs($d);

			# Tell the user
			$subject = $text{'letsencrypt_sdone'};
			$body = &text('letsencrypt_bdone', join(", ", @dnames));
			}

		# Send email
		my $from = &get_global_from_address($d);
		&send_notify_email($from, [$d], $d, $subject, $body);
		}
	}
}

# install_letsencrypt_cert(&domain, certfile, keyfile, chainfile)
# Update the current cert and key for a domain
sub install_letsencrypt_cert
{
my ($d, $cert, $key, $chain) = @_;

# Copy and save the cert
$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
$cert_text = &read_file_contents($cert);
&lock_file($d->{'ssl_cert'});
&unlink_file($d->{'ssl_cert'});
&open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_cert'}");
&print_tempfile(CERT, $cert_text);
&close_tempfile_as_domain_user($d, CERT);
&set_certificate_permissions($d, $d->{'ssl_cert'});
&unlock_file($d->{'ssl_cert'});
&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});

# And the key
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
$key_text = &read_file_contents($key);
&lock_file($d->{'ssl_key'});
&unlink_file($d->{'ssl_key'});
&open_tempfile_as_domain_user($d, CERT, ">$d->{'ssl_key'}");
&print_tempfile(CERT, $key_text);
&close_tempfile_as_domain_user($d, CERT);
&set_certificate_permissions($d, $d->{'ssl_key'});
&unlock_file($d->{'ssl_key'});
&save_website_ssl_file($d, "key", $d->{'ssl_key'});

# Let's encrypt certs have no passphrase
$d->{'ssl_pass'} = undef;
&save_domain_passphrase($d);

# And the chained file
if ($chain) {
	$chainfile = &default_certificate_file($d, 'ca');
	$chain_text = &read_file_contents($chain);
	&lock_file($chainfile);
	&unlink_file_as_domain_user($d, $chainfile);
	&open_tempfile_as_domain_user($d, CERT, ">$chainfile");
	&print_tempfile(CERT, $chain_text);
	&close_tempfile_as_domain_user($d, CERT);
	&set_permissions_as_domain_user($d, 0755, $chainfile);
	&unlock_file($chainfile);
	$err = &save_website_ssl_file($d, 'ca', $chainfile);
	$d->{'ssl_chain'} = $chainfile;
	}
}

# get_openssl_version()
# Returns the version of the installed OpenSSL command
sub get_openssl_version
{
my $out = &backquote_command("openssl version 2>/dev/null");
if ($out =~ /OpenSSL\s+([0-9\.a-z]+)/i) {
	return $1;
	}
return undef;
}

# before_letsencrypt_website(&domain)
# If there is any proxy setup that would block /.well-known, add a negative
# path to ensure direct access
sub before_letsencrypt_website
{
local ($d) = @_;
local $rv = { };
&push_all_print();
&set_all_null_print();
&setup_noproxy_path($d, { 'uses' => [ 'proxy' ] }, undef,
		    { 'path' => '/.well-known' });
if (&has_web_redirects($d)) {
	# Remove redirects that may block let's encrypt
	local @redirs;
	foreach my $r (&list_redirects($d)) {
		if ($r->{'path'} eq '/' && $r->{'http'}) {
			# Possible problem redirect
			&delete_redirect($d, $r);
			push(@redirs, { %$r });
			}
		}
	if (@redirs) {
		&run_post_actions();
		$rv->{'redirs'} = \@redirs;
		}
	}
&pop_all_print();
return $rv;
}

# after_letsencrypt_website(&domain, &before-rv)
# Undoes changes made by before_letsencrypt_website
sub after_letsencrypt_website
{
local ($d, $before) = @_;
&push_all_print();
&set_all_null_print();
if ($before->{'redirs'}) {
	foreach my $r (@{$before->{'redirs'}}) {
		&create_redirect($d, $r);
		}
	&run_post_actions();
	}
&pop_all_print();
}

# request_domain_letsencrypt_cert(&domain, &dnames, [staging], [size])
# Attempts to request a Let's Encrypt cert for a domain, trying both web and
# DNS modes if possible
sub request_domain_letsencrypt_cert
{
my ($d, $dnames, $staging, $size) = @_;
$size ||= $config{'key_size'};
&foreign_require("webmin");
my $phd = &public_html_dir($d);
my ($ok, $cert, $key, $chain);
my @errs;
if (&domain_has_website($d)) {
	# Try using website first
	($ok, $cert, $key, $chain) = &webmin::request_letsencrypt_cert(
		$dnames, $phd, $d->{'emailto'}, $size, "web", $staging);
	push(@errs, &text('letsencrypt_eweb', $cert)) if (!$ok);
	}
if (!$ok && &get_webmin_version() >= 1.834 && $d->{'dns'}) {
	# Fall back to DNS
	($ok, $cert, $key, $chain) = &webmin::request_letsencrypt_cert(
		$dnames, undef, $d->{'emailto'}, $size, "dns", $staging);
	push(@errs, &text('letsencrypt_edns', $cert)) if (!$ok);
	}
elsif (!$ok) {
	if (!$cert) {
		$cert = "Domain has no website, ".
			"and DNS-based validation is not possible";
		push(@errs, $cert);
		}
	}
if (!$ok) {
	return ($ok, join("\n", @errs), $key, $chain);
	}
else {
	return ($ok, $cert, $key, $chain);
	}
}

$done_feature_script{'ssl'} = 1;

1;

