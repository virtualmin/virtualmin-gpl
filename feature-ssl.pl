

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
$d->{'letsencrypt_renew'} = 1;		# Default let's encrypt renewal

# Find out if this domain will share a cert with another
&find_matching_certificate($d);

# Create a self-signed cert and key, if needed
my $generated = &generate_default_certificate($d);
if (!$generated && !-r $d->{'ssl_cert'}) {
	# SSL cert failed, so don't proceed
	return 0;
	}
&refresh_ssl_cert_expiry($d);
local $chained = $d->{'ssl_chain'};
&sync_combined_ssl_cert($d);

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
if ($d->{'ssl_chain'}) {
	local $cadata = &read_file_contents($d->{'ssl_chain'});
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

# Copy chained CA cert in from domain with same IP, if any
$d->{'web_sslport'} = $web_sslport;
if ($chained) {
	&save_website_ssl_file($d, 'ca', $chained);
	}
$d->{'web_urlsslport'} = $tmpl->{'web_urlsslport'};

# Add cert in Webmin, Dovecot, etc..
&enable_domain_service_ssl_certs($d);

# Update DANE DNS records
&sync_domain_tlsa_records($d);

# Redirect HTTP to HTTPS
if ($tmpl->{'web_sslredirect'} || $d->{'auto_redirect'}) {
	&create_redirect($d, &get_redirect_to_ssl($d));
	}

&release_lock_web($d);
&$second_print($text{'setup_done'});
if ($d->{'virt'}) {
	&register_post_action(\&restart_apache, &ssl_needs_apache_restart());
	}
else {
	&register_post_action(\&restart_apache);
	}

# Try to request a Let's Encrypt cert when enabling SSL post-creation for
# the first time
if (!$d->{'creating'} && $generated && $d->{'auto_letsencrypt'} &&
    !$d->{'disabled'}) {
	&create_initial_letsencrypt_cert($d, 1);
	}

return 1;
}

# setup_alias_ssl(&alias-target, &domain)
# Called when a domain with SSL gets an alias
sub setup_alias_ssl
{
my ($aliasd, $d) = @_;
my @certs = &get_all_domain_service_ssl_certs($aliasd);
&update_all_domain_service_ssl_certs($aliasd, \@certs);
}

# delete_alias_ssl(&alias-target, &domain)
# Called when a domain with SSL loses an alias
sub delete_alias_ssl
{
my ($aliasd, $d) = @_;
my @certs = &get_all_domain_service_ssl_certs($aliasd);
&update_all_domain_service_ssl_certs($aliasd, \@certs);
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
if ($d->{'user'} ne $oldd->{'user'}) {
	# Username has changed .. copy suexec directives from parent
	&$first_print($text{'save_ssl10'});
	if (!$virt || !$nonvirt) {
		&$second_print($text{'delete_noapache'});
		goto VIRTFAILED;
		}
	local @vals = &apache::find_directive("SuexecUserGroup", $nonvconf);
	if (@vals) {
		&apache::save_directive(
			"SuexecUserGroup", \@vals, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		}
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
		$d->{'ssl_combined'} = $sslclash->{'ssl_combined'};
		$d->{'ssl_everything'} = $sslclash->{'ssl_everything'};
		}
	else {
		# No domain has the same cert anymore - copy the one from the
		# old sslclash domain
		&break_ssl_linkage($d, $oldsslclash);
		}
	}
if ($d->{'home'} ne $oldd->{'home'}) {
	# Fix SSL cert file locations
	foreach my $k ('ssl_cert', 'ssl_key', 'ssl_chain', 'ssl_combined',
		       'ssl_everything') {
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
	local $email = $info->{'emailAddress'};
	$email =~ s/\@\Q$oldd->{'dom'}\E$/\@$d->{'dom'}/;
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
		$email,
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

if ($d->{'dom'} ne $oldd->{'dom'} &&
    !$d->{'ssl_same'} &&
    &is_letsencrypt_cert($d) &&
    !&check_domain_certificate($d->{'dom'}, $d)) {
	# Domain name has changed ... re-request let's encrypt cert
	&$first_print($text{'save_ssl12'});
	if ($d->{'letsencrypt_dname'}) {
		# Update any explicitly chosen domain names
		my @dnames = split(/\s+/, $d->{'letsencrypt_dname'});
		foreach my $dn (@dnames) {
			$dn = $d->{'dom'} if ($dn eq $oldd->{'dom'});
			$dn =~ s/\.\Q$oldd->{'dom'}\E$/\.$d->{'dom'}/;
			}
		$d->{'letsencrypt_dname'} = join(" ", @dnames);
		}
	my ($ok, $err) = &renew_letsencrypt_cert($d);
	if ($ok) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('save_essl12', $err));
		}
	}

# If anything has changed that would impact the per-domain SSL cert for
# another server like Postfix or Webmin, re-set it up as long as it is supported
# with the new settings
if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'virt'} != $oldd->{'virt'} ||
    $d->{'dom'} ne $oldd->{'dom'} ||
    $d->{'home'} ne $oldd->{'home'}) {
	my %types = map { $_->{'id'}, $_ } &list_service_ssl_cert_types();
	foreach my $svc (&get_all_domain_service_ssl_certs($oldd)) {
		next if (!$svc->{'d'});
		my $t = $types{$svc->{'id'}};
		my $func = "sync_".$svc->{'id'}."_ssl_cert";
		next if (!defined(&$func));
		&$func($oldd, 0);
		if ($t->{'dom'} || $d->{'virt'}) {
			&$func($d, 1);
			}
		}
	}

# Update DANE DNS records
&sync_domain_tlsa_records($d);

&release_lock_web($d);
&register_post_action(\&restart_apache, &ssl_needs_apache_restart()) if ($rv);
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
	&register_post_action(\&restart_apache, &ssl_needs_apache_restart());
	}
else {
	&$second_print($text{'delete_noapache'});
	}
undef(@apache::get_config_cache);

# If any other domains were using this one's SSL cert or key, break the linkage
foreach my $od (&get_domain_by("ssl_same", $d->{'id'})) {
	&break_ssl_linkage($od, $d);
	&save_domain($od);
	}

# Update DANE DNS records
&sync_domain_tlsa_records($d, 2);

# If this domain was sharing a cert with another, forget about it now
if ($d->{'ssl_same'}) {
	delete($d->{'ssl_cert'});
	delete($d->{'ssl_key'});
	delete($d->{'ssl_chain'});
	delete($d->{'ssl_combined'});
	delete($d->{'ssl_everything'});
	delete($d->{'ssl_same'});
	}

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

# If in FPM mode update the port as well
my $mode = &get_domain_php_mode($oldd);
if ($mode eq "fpm") {
	# Force port re-allocation
	delete($d->{'php_fpm_port'});
	&save_domain_php_mode($d, $mode);
	}

# Re-generate combined cert file in case cert changed
&sync_combined_ssl_cert($d);

&release_lock_web($d);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_apache, &ssl_needs_apache_restart());
return 1;
}

# validate_ssl(&domain)
# Returns an error message if no SSL Apache virtual host exists, or if the
# cert files are missing.
sub validate_ssl
{
local ($d) = @_;
local ($virt, $vconf, $conf) = &get_apache_virtual(
				$d->{'dom'}, $d->{'web_sslport'});
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
elsif (!-e $cert) {
	return &text('validate_esslcertfile', "<tt>$cert</tt>");
	}
elsif (-l $cert) {
	return &text('validate_esslcertlink', "<tt>$cert</tt>");
	}
elsif (&is_under_directory($d->{'home'}, $cert) &&
       !&readable_by_domain_user($d, $cert)) {
	return &text('validate_esslcertfile2', "<tt>$cert</tt>");
	}

# Make sure key exists
local $key = &apache::find_directive("SSLCertificateKeyFile", $vconf, 1);
if ($key) {
	if (!-e $key) {
		return &text('validate_esslkeyfile', "<tt>$key</tt>");
		}
	elsif (-l $key) {
		return &text('validate_esslkeylink', "<tt>$key</tt>");
		}
	elsif (&is_under_directory($d->{'home'}, $key) &&
	       !&readable_by_domain_user($d, $key)) {
		return &text('validate_esslkeyfile2', "<tt>$key</tt>");
		}
	}

# Make sure the cert is readable
local $info = &cert_info($d);
if (!$info || !$info->{'cn'}) {
	return &text('validate_esslcertinfo', "<tt>$cert</tt>");
	}
local $err = &validate_cert_format($cert, 'cert');
if ($err) {
	return $err;
	}

# Check the key type
local $type = &get_ssl_key_type($key, $d->{'ssl_pass'});
$type || return &text('validate_esslkeytype', "<tt>$key</tt>");

# Make sure the cert and key match
my $certdata = &read_file_contents($cert);
my $keydata = &read_file_contents($key);
my $err = check_cert_key_match($certdata, $keydata);
if ($err) {
	return $err;
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
if ($info && $info->{'notafter'} && !$d->{'disabled'}) {
	local $notafter = &parse_notafter_date($info->{'notafter'});
	if ($notafter < time()) {
		return &text('validate_esslexpired', &make_date($notafter));
		}
	}

# Make sure the CA matches the cert
my $cafile = &get_website_ssl_file($d, "ca");
if ($cafile && !&self_signed_cert($d)) {
	my $cainfo = &cert_file_info($cafile, $d);
	if (!$cainfo || !$cainfo->{'cn'}) {
		return &text('validate_esslcainfo', "<tt>$cafile</tt>");
		}
	if ($cainfo->{'o'} ne $info->{'issuer_o'} ||
	    $cainfo->{'cn'} ne $info->{'issuer_cn'}) {
		return &text('validate_esslcamatch',
			     $cainfo->{'o'}, $cainfo->{'cn'},
			     $info->{'issuer_o'}, $info->{'issuer_cn'});
		}
	}
	
# If the <virtualhost> address uses a *, make sure that no other
# virtualhost uses the domain's IP
if ($virt->{'words'}->[0] =~ /^\*/) {
	my ($ipclash, $ipclashv);
	VHOST: foreach my $ovirt (&apache::find_directive_struct(
				"VirtualHost", $conf)) {
		foreach my $v (@{$ovirt->{'words'}}) {
			if ($v =~ /^([^:]+)(:(\d+))?/i &&
			    ($1 eq $d->{'ip'}) &&
			    (!$3 || $3 == $d->{'web_port'})) {
				$ipclash = $ovirt;
				$ipclashv = $v;
				last VHOST;
				}
			}
		}
	if ($ipclash) {
		my $sn = &apache::find_directive(
			"ServerName", $ipclash->{'members'});
		return &text('validate_envstar', $virt->{'words'}->[0],
						 $ipclashv, $sn);
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
	if (!$ca) {
		$ca = &apache::find_directive("SSLCertificateChainFile", $vconf,1);
		}
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
local ($d, $file, $opts) = @_;
&$first_print($text{'restore_sslcp'});
&obtain_lock_web($d);
my $rv = 1;

# Restore the Apache directives
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_sslport'});
if ($virt) {
	local $srclref = &read_file_lines($file, 1);
	local $dstlref = &read_file_lines($virt->{'file'});
	splice(@$dstlref, $virt->{'line'}+1,
	       $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);

	if ($_[5]->{'home'} && $_[5]->{'home'} ne $d->{'home'}) {
		# Fix up any DocumentRoot or other file-related directives
		local $i;
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~
			    s/\Q$_[5]->{'home'}\E/$d->{'home'}/g;
			}
		}
	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);

	# Copy suexec-related directives from non-SSL virtual host
	($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					      $d->{'web_sslport'});
	local ($nvirt, $nvconf) = &get_apache_virtual($d->{'dom'},
						      $d->{'web_port'});
	if ($nvirt && $virt) {
		local @vals = &apache::find_directive("SuexecUserGroup",
						      $nvconf);
		if (@vals) {
			&apache::save_directive("SuexecUserGroup", \@vals,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			}
		}

	if (!$d->{'ssl_same'}) {
		# Restore the cert and key, if any and if saved and if not
		# shared with another domain
		local $cert = $d->{'ssl_cert'} ||
		      &apache::find_directive("SSLCertificateFile", $vconf, 1);
		if ($cert && -r $file."_cert") {
			&lock_file($cert);
			&write_ssl_file_contents($d, $cert, $file."_cert");
			&unlock_file($cert);
			&save_website_ssl_file($d, "cert", $cert);
			}
		local $key = $d->{'ssl_key'} ||
		     &apache::find_directive("SSLCertificateKeyFile", $vconf,1);
		if ($key && -r $file."_key" && $key ne $cert) {
			&lock_file($key);
			&write_ssl_file_contents($d, $key, $file."_key");
			&unlock_file($key);
			&save_website_ssl_file($d, "key", $key);
			}
		local $ca = $d->{'ssl_chain'} ||
		    &apache::find_directive("SSLCACertificateFile", $vconf,1) ||
		    &apache::find_directive("SSLCertificateChainFile", $vconf, 1);
		if ($ca && -r $file."_ca") {
			&lock_file($ca);
			&write_ssl_file_contents($d, $ca, $file."_ca");
			&unlock_file($ca);
			&save_website_ssl_file($d, "ca", $ca);
			}
		&refresh_ssl_cert_expiry($d);
		&sync_combined_ssl_cert($d);
		}
	else {
		# Make sure that the Apache config uses the correct SSL path
		&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});
		&save_website_ssl_file($d, "key", $d->{'ssl_key'});
		&save_website_ssl_file($d, "ca", $d->{'ssl_chain'});
		}

	# Re-setup any SSL passphrase
	&save_domain_passphrase($d);

	# Re-save PHP mode, in case it changed
	&save_domain_php_mode($d, &get_domain_php_mode($d));

	# Re-save CGI mode from non-SSL domain
	&save_domain_cgi_mode($d, &get_domain_cgi_mode($d));

	# Add Require all granted directive if this system is Apache 2.4
	&add_require_all_granted_directives($d, $d->{'web_sslport'});

	# If the restored config contains php_value entires but this system
	# doesn't support mod_php, remove them
	&fix_mod_php_directives($d, $d->{'web_sslport'});

	# Fix Options lines
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
							$d->{'web_sslport'});
	if ($virt) {
		&fix_options_directives($vconf, $conf, 0);
		}

	# Handle case where there are DAV directives, but it isn't enabled
	&remove_dav_directives($d, $virt, $vconf, $conf);

	# Re-save CA cert path based on actual config
	if (!$d->{'ssl_same'}) {
		$d->{'ssl_chain'} = &get_website_ssl_file($d, 'ca');

		# Sync cert to Dovecot, Postfix, Webmin, etc..
		&enable_domain_service_ssl_certs($d);
		}

	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_noapache'});
	$rv = 0;
	}

&release_lock_web($d);
&register_post_action(\&restart_apache);
return $rv;
}

# cert_info(&domain)
# Returns a hash of details of a domain's cert
sub cert_info
{
local ($d) = @_;
return &cert_file_info($d->{'ssl_cert'}, $d);
}

# cert_file_split(file|data)
# Returns a list of certs in some file
sub cert_file_split
{
my ($file) = @_;
my $data;
if ($file =~ /^\//) {
	$data = &read_file_contents($file);
	}
else {
	$data = $file;
	}
my @rv;
my @lines = split(/\r?\n/, $data);
foreach my $l (@lines) {
	my $cl = $l;
	$cl =~ s/^#.*//;
	if ($cl =~ /^-----BEGIN/) {
		push(@rv, $cl."\n");
		}
	elsif ($cl =~ /\S/ && @rv) {
		$rv[$#rv] .= $cl."\n";
		}
	}
return @rv;
}

# cert_data_info(data)
# Returns details of a cert in PEM text format
sub cert_data_info
{
local ($data) = @_;
local $temp = &transname();
&open_tempfile(TEMP, ">$temp", 0, 1);
&print_tempfile(TEMP, $data);
&close_tempfile(TEMP);
local $info = &cert_file_info($temp);
&unlink_file($temp);
return $info;
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
	open(OUT, &command_as_user($d->{'user'}, 0, $cmd)." 2>/dev/null |");
	}
else {
	open(OUT, $cmd." 2>/dev/null |");
	}
while(<OUT>) {
	s/\r|\n//g;
	s/http:\/\//http:\|\|/g;	# So we can parse with regexp
	if (/subject=.*C\s*=\s*([^\/,]+)/) {
		$rv{'c'} = $1;
		}
	if (/subject=.*ST\s*=\s*([^\/,]+)/) {
		$rv{'st'} = $1;
		}
	if (/subject=.*L\s*=\s*([^\/,]+)/) {
		$rv{'l'} = $1;
		}
	if (/subject=.*O\s*=\s*"(.*?)"/ || /subject=.*O\s*=\s*([^\/,]+)/) {
		$rv{'o'} = $1;
		}
	if (/subject=.*OU\s*=\s*([^\/,]+)/) {
		$rv{'ou'} = $1;
		}
	if (/subject=.*CN\s*=\s*([^\/,]+)/) {
		$rv{'cn'} = $1;
		}
	if (/subject=.*emailAddress\s*=\s*([^\/,]+)/) {
		$rv{'email'} = $1;
		}

	if (/issuer=.*C\s*=\s*([^\/,]+)/) {
		$rv{'issuer_c'} = $1;
		}
	if (/issuer=.*ST\s*=\s*([^\/,]+)/) {
		$rv{'issuer_st'} = $1;
		}
	if (/issuer=.*L\s*=\s*([^\/,]+)/) {
		$rv{'issuer_l'} = $1;
		}
	if (/issuer=.*O\s*=\s*"(.*?)"/ || /issuer=.*O\s*=\s*([^\/,]+)/) {
		$rv{'issuer_o'} = $1;
		}
	if (/issuer=.*OU\s*=\s*([^\/,]+)/) {
		$rv{'issuer_ou'} = $1;
		}
	if (/issuer=.*CN\s*=\s*([^\/,]+)/) {
		$rv{'issuer_cn'} = $1;
		}
	if (/issuer=.*emailAddress\s*=\s*([^\/,]+)/) {
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
	# Try to detect key algorithm
	if (/Key\s+Algorithm:.*?(rsa|ec)[EP]/) {
		$rv{'algo'} = $1;
		}
	if (/RSA\s+Public\s+Key:\s+\((\d+)\s*bit/) {
		$rv{'size'} = $1;
		}
	elsif (/EC\s+Public\s+Key:\s+\((\d+)\s*bit/) {
		$rv{'size'} = $1;
		}
	elsif (/Public-Key:\s+\((\d+)\s*bit/) {
		$rv{'size'} = $1;
		}
	if (/Modulus\s*\(.*\):/ || /Modulus:/) {
		$inmodulus = 1;
		# RSA algo
		$rv{'algo'} = "rsa" if (!$rv{'algo'});
		}
	elsif (/pub:/) {
		$inmodulus = 1;
		# ECC algo
		$rv{'algo'} = 'ec' if (!$rv{'algo'});
		}
	if (/^\s+([0-9a-f:]+)\s*$/ && $inmodulus) {
		$rv{'modulus'} .= $1;
		}
	# RSA exponent
	if (/Exponent:\s*(\d+)/) {
		$rv{'exponent'} = $1;
		$inmodulus = 0;
		}
	# ECC properties
	elsif (/(ASN1\s+OID):\s*(\S+)/ || /(NIST\s+CURVE):\s*(\S+)/) {
		$inmodulus = 0;
		my $comma = $rv{'exponent'} ? ", " : "";
		$rv{'exponent'} .= "$comma$1: $2";
		}
	}
close(OUT);
foreach my $k (keys %rv) {
	$rv{$k} =~ s/http:\|\|/http:\/\//g;
	}
$rv{'self'} = $rv{'o'} eq $rv{'issuer_o'} ? 1 : 0;
$rv{'type'} = $rv{'self'} ? $text{'cert_typeself'} : $text{'cert_typereal'};
return \%rv;
}

# convert_ssl_key_format(&domain, file, "pkcs1"|"pkcs8", [outfile])
# Convert an SSL key into a different format
sub convert_ssl_key_format
{
my ($d, $file, $fmt, $outfile) = @_;
$outfile ||= $file;
my $cmd;
if ($fmt eq "pkcs1") {
	$cmd = "openssl rsa -in ".quotemeta($file)." -out ".quotemeta($outfile);
	}
elsif ($fmt eq "pkcs8") {
	$cmd = "openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in ".
	       quotemeta($file)." -out ".quotemeta($outfile);
	}
else {
	return "Unknown format $fmt";
	}
if ($d && &is_under_directory($d->{'home'}, $file)) {
	$cmd = &command_as_user($d->{'user'}, 0, $cmd);
	}
my $out = &backquote_logged("$cmd 2>&1 </dev/null");
return $? ? $out : undef;
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
return 1 if (&same_file($file1, $file2));
local $info1 = &cert_file_info($file1);
local $info2 = &cert_file_info($file2);
return 1 if (!$info1 && !$info2);
return 0 if ($info1 && !$info2 || !$info1 && $info2);
return $info1->{'modulus'} && $info2->{'modulus'} &&
       $info1->{'modulus'} eq $info2->{'modulus'} &&
       $info1->{'notafter'} eq $info2->{'notafter'};
}

# same_cert_file_any(file1, file2)
# Checks if the modulus and expiry of the cert in file1 are the same as those
# for any of the certs in file2.
sub same_cert_file_any
{
local ($file1, $file2) = @_;
return 1 if (!$file1 && !$file2);
return 0 if ($file1 && !$file2 || !$file1 && $file2);
return 1 if (&same_file($file1, $file2));
local $info1 = &cert_file_info($file1);
foreach my $sp (&cert_file_split($file2)) {
	local $info2 = &cert_data_info($sp);
	return 1 if ($info1->{'modulus'} && $info2->{'modulus'} &&
		     $info1->{'modulus'} eq $info2->{'modulus'} &&
		     $info1->{'notafter'} eq $info2->{'notafter'});
	}
return 0;
}

# get_ssl_key_type(file, [passphrase])
# Returns 'rsa' or 'ec' depending on the key type
sub get_ssl_key_type
{
my ($key, $pass) = @_;

# First check if it's in the key file format
my $lref = &read_file_lines($key, 1);
foreach my $l (@$lref) {
	if ($l =~ /-----BEGIN\s+(RSA|EC)\s+PRIVATE\s+KEY----/) {
		return lc($1);
		}
	}

# Fallback to seeing if the openssl command can parse it
my $qpass = $pass ? quotemeta($pass) : "NONE";
foreach my $t ('rsa', 'ec') {
	my $ex = &execute_command("openssl $t -in ".quotemeta($key).
				  " -text -passin pass:".$qpass);
	return $t if (!$ex);
	}

return undef;
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
my $type = &get_ssl_key_type($temp, $pass);
local $rv = &execute_command("openssl $type -in ".quotemeta($temp).
			     " -text -passin pass:NONE");
if (!$rv) {
	return 1;
	}
if ($pass) {
	local $rv = &execute_command("openssl $type -in ".quotemeta($temp).
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
my $type = &get_ssl_key_type($file);
local $out = &backquote_command(
	"openssl $type -in ".quotemeta($file)." -text 2>&1 </dev/null");
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
my $pps_file = @pps_str ? $pps_str[0]->{'file'} : $conf->[0]->{'file'};
&lock_file($pps_file);
&apache::save_directive("SSLPassPhraseDialog", \@pps, $conf, $conf);
&flush_file_lines();
&unlock_file($pps_file);
&register_post_action(\&restart_apache, &ssl_needs_apache_restart());
}

# check_cert_key_match(cert-text, key-text)
# Checks if the modulus for a cert and key match and are valid. Returns undef 
# on success or an error message on failure.
sub check_cert_key_match
{
my ($certtext, $keytext) = @_;
my $certfile = &transname();
my $keyfile = &transname();
foreach my $tf ([ $certtext, $certfile ], [ $keytext, $keyfile ]) {
	&open_tempfile(CERTOUT, ">$tf->[1]", 0, 1);
	&print_tempfile(CERTOUT, $tf->[0]);
	&close_tempfile(CERTOUT);
	}
my $type = &get_ssl_key_type($keyfile);

if ($type eq "ec") {
	# Get the public key data from the cert
	my $x;
	my $certpub = &extract_public_key($x=&backquote_command(
		"openssl x509 -noout -text -in ".quotemeta($certfile)." 2>&1"));
	my $keypub = &extract_public_key($x=&backquote_command(
		"openssl ec -noout -text -in ".quotemeta($keyfile)." 2>&1"));
	$certpub eq $keypub ||
		return "Certificate and private key do not match";
	}
else {
	# Get certificate modulus
	my $certmodout = &backquote_command(
	    "openssl x509 -noout -modulus -in ".quotemeta($certfile)." 2>&1");
	$certmodout =~ /Modulus=([A-F0-9]+)/i ||
		return "Certificate data is not valid : $certmodout";
	my $certmod = $1;

	# Get key modulus
	my $keymodout = &backquote_command(
	    "openssl $type -noout -modulus -in ".quotemeta($keyfile)." 2>&1");
	$keymodout =~ /Modulus=([A-F0-9]+)/i ||
		return "Key data is not valid : $keymodout";
	my $keymod = $1;

	# Make sure they match
	$certmod eq $keymod ||
		return "Certificate and private key do not match";
	}

return undef;
}

# extract_public_key(text)
# Given openssl -text output, extract the public key data
sub extract_public_key
{
my ($txt) = @_;
my $found = 0;
my $pub = "";
foreach my $l (split(/\r?\n/, $txt)) {
	if ($l =~ /^\s*pub:\s*$/) {
		$found = 1;
		}
	elsif ($l =~ /^\s+([a-f0-9:]+)\s*$/ && $found) {
		$pub .= $1;
		}
	elsif ($found) {
		last;
		}
	}
return $pub;
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
local %headers = ( 'key' => '(RSA |EC )?PRIVATE KEY',
		   'cert' => 'CERTIFICATE',
		   'ca' => 'CERTIFICATE',
		   'csr' => 'CERTIFICATE REQUEST',
		   'newkey' => '(RSA |EC )?PRIVATE KEY' );
local $h = $headers{$type};
$h || return "Unknown SSL file type $type";
($data) = &extract_cert_parameters($data);
local @lines = grep { /\S/ } split(/\r?\n/, $data);
local $begin = quotemeta("-----BEGIN ").$h.quotemeta("-----");
local $end = quotemeta("-----END ").$h.quotemeta("-----");
$lines[0] =~ /^$begin$/ ||
	return "Data starts with $lines[0] , but expected -----BEGIN $h-----";
$lines[$#lines] =~ /^$end$/ ||
	return "Data ends with $lines[$#lines] , but expected -----END $h-----";
for(my $i=1; $i<$#lines; $i++) {
	$lines[$i] =~ /^[A-Za-z0-9\+\/=]+\s*$/ ||
	$lines[$i] =~ /^$begin$/ ||
	$lines[$i] =~ /^$end$/ ||
		return "Line ".($i+1)." does not look like PEM format";
	}
@lines > 4 || return "Data only has ".scalar(@lines)." lines";
return undef;
}

# extract_cert_parameters(cert-text)
# Given a cert text that might contain a -----BEGIN EC PARAMETERS----- block,
# return the rest of the file and that block if it exists
sub extract_cert_parameters
{
my ($data) = @_;
my @parts = &cert_file_split($data);
my $rv = "";
my $params = "";
foreach my $p (@parts) {
	if ($p =~ /^-----BEGIN\s+(\S+)\s+PARAMETERS-----/) {
		$params .= $p;
		}
	else {
		$rv .= $p;
		}
	}
return ($rv, $params);
}

# cert_pem_data(&domain)
# Returns a domain's cert in PEM format
sub cert_pem_data
{
my ($d) = @_;
my $data;
if (&is_under_directory($d->{'home'}, $d->{'ssl_cert'})) {
	$data = &read_file_contents_as_domain_user($d, $d->{'ssl_cert'});
	}
else {
	$data = &read_file_contents($d->{'ssl_cert'});
	}
$data =~ s/\r//g;
if ($data =~ /(-----BEGIN\s+CERTIFICATE-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+CERTIFICATE-----)/) {
	return $1;
	}
return undef;
}

# key_pem_data(&domain)
# Returns a domain's key in PEM format
sub key_pem_data
{
my ($d) = @_;
my $file = $d->{'ssl_key'} || $d->{'ssl_cert'};
my $data;
if (&is_under_directory($d->{'home'}, $file)) {
	$data = &read_file_contents_as_domain_user($d, $file);
	}
else {
	$data = &read_file_contents($file);
	}
$data =~ s/\r//g;
if ($data =~ /(-----BEGIN\s+RSA\s+PRIVATE\s+KEY-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+RSA\s+PRIVATE\s+KEY-----)/) {
	return $1;
	}
elsif ($data =~ /(-----BEGIN\s+PRIVATE\s+KEY-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+PRIVATE\s+KEY-----)/) {
	return $1;
	}
elsif ($data =~ /(-----BEGIN\s+EC\s+PRIVATE\s+KEY-----\n([A-Za-z0-9\+\/=\n\r]+)-----END\s+EC\s+PRIVATE\s+KEY-----)/) {
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
my ($d, $getfunc, $putfunc, $postfunc) = @_;
my @doms = ( $d, &get_domain_by("alias", $d->{'id'}) );
my @dnames = map { ($_->{'dom'}, "*.".$_->{'dom'}) } @doms;
&foreign_require("webmin");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
local @ips;
if ($d->{'virt'}) {
	push(@ips, $d->{'ip'});
	}
push(@ips, @dnames);
push(@ipkeys, { 'ips' => \@ips,
		'key' => $d->{'ssl_key'},
		'cert' => $d->{'ssl_cert'},
		'extracas' => $d->{'ssl_chain'}, });
&webmin::save_ipkeys(\%miniserv, \@ipkeys);
&$putfunc(\%miniserv);
&register_post_action($postfunc);
return 1;
}

# delete_ipkeys(&domain, &miniserv-getter, &miniserv-saver, &post-action)
# Remove the per-IP/domain SSL key for some domain
sub delete_ipkeys
{
my ($d, $getfunc, $putfunc, $postfunc) = @_;
&foreign_require("webmin");
local %miniserv;
&$getfunc(\%miniserv);
local @ipkeys = &webmin::get_ipkeys(\%miniserv);
local @newipkeys;
foreach my $ipk (@ipkeys) {
	my $del = &indexof($d->{'dom'}, @{$ipk->{'ips'}}) >= 0;
	if ($d->{'virt'} && !$del) {
		$del = &indexof($d->{'ip'}, @{$ipk->{'ips'}}) >= 0;
		}
	if (!$del) {
		push(@newipkeys, $ipk);
		}
	}
if (@ipkeys != @newipkeys) {
	# Some change was found to apply
	&webmin::save_ipkeys(\%miniserv, \@newipkeys);
	&$putfunc(\%miniserv);
	&register_post_action($postfunc);
	return undef;
	}
return $text{'delete_esslnoips'};
}

# apache_combined_cert()
# Returns 1 if Apache should be pointed to the combined SSL cert file
sub apache_combined_cert
{
&require_apache();
if ($config{'combined_cert'} == 2) {
	return 1;
	}
elsif ($config{'combined_cert'} == 1) {
	return 0;
	}
else {
	return &compare_versions($apache::httpd_modules{'core'}, "2.4.8") >= 0;
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
if (&apache_combined_cert()) {
	push(@dirs, "SSLCertificateFile $d->{'ssl_combined'}");
	}
else {
	push(@dirs, "SSLCertificateFile $d->{'ssl_cert'}");
	}
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
		if (&compare_version_numbers(&get_openssl_version(), '>=', '1.0.0')) {
			push(@tls, "TLSv1.1");
			}
		}
	push(@dirs, "SSLProtocol ".join(" ", "all", map { "-".$_ } @tls));
	}
if ($tmpl->{'web_ssl'} ne 'none') {
	local $ssl_dirs = $tmpl->{'web_ssl'};
	$ssl_dirs =~ s/\t/\n/g;
	$ssl_dirs = &substitute_domain_template($ssl_dirs, $d);
	push(@dirs, split(/\n/, $ssl_dirs));
	}
return @dirs;
}

# check_certificate_data(data)
# Checks if some data looks like a valid cert. Returns undef if OK, or an error
# message if not
sub check_certificate_data
{
local ($data) = @_;
my @lines = split(/\r?\n/, $data);
my @certs;
my $inside = 0;
foreach my $l (@lines) {
	if ($l =~ /^-+BEGIN/) {
		push(@certs, $l."\n");
		$inside = 1;
		}
	elsif ($l =~ /^-+END/) {
		$inside || return $text{'cert_eoutside'};
		$certs[$#certs] .= $l."\n";
		$inside = 0;
		}
	elsif ($inside) {
		$certs[$#certs] .= $l."\n";
		}
	}
$inside && return $text{'cert_einside'};
@certs || return $text{'cert_ecerts'};
local $temp = &transname();
foreach my $cdata (@certs) {
	&open_tempfile(CERTDATA, ">$temp", 0, 1);
	&print_tempfile(CERTDATA, $cdata);
	&close_tempfile(CERTDATA);
	local $out = &backquote_command("openssl x509 -in ".quotemeta($temp)." -issuer -subject -enddate 2>&1");
	local $ex = $?;
	&unlink_file($temp);
	if ($ex) {
		return "<tt>".&html_escape($out)."</tt>";
		}
	elsif ($out !~ /subject\s*=\s*.*(CN|O)\s*=/) {
		return $text{'cert_esubject'};
		}
	}
return undef;
}

# default_certificate_file(&domain, "cert"|"key"|"ca"|"combined"|"everything")
# Returns the default path that should be used for a cert, key or CA file
sub default_certificate_file
{
my ($d, $mode) = @_;
$mode = "ca" if ($mode eq "chain");
my $tmpl = &get_template($d->{'template'});
my $file = $tmpl->{'cert_'.$mode.'_tmpl'};
if ($file eq "auto" && $mode ne "key") {
	# Path is relative to the key file
	my $keyfile = $tmpl->{'cert_key_tmpl'};
	if ($keyfile && $keyfile =~ s/\/[^\/]+$//) {
		$file = $keyfile."/ssl.".$mode;
		}
	else {
		$file = undef;
		}
	}
return $file ? &absolute_domain_path($d, &substitute_domain_template($file, $d))
	     : "$d->{'home'}/ssl.".$mode;
}

# relative_certificate_file(file, type)
# Returns a cert path in the same directory as the given file, but of a
# different type.
sub relative_certificate_file
{
my ($file, $mode) = @_;
$mode = "ca" if ($mode eq "chain");
$file =~ s/\/[^\/]+$//;
return $file."/ssl.".$mode;
}

# set_certificate_permissions(&domain, file)
# Set permissions on a cert file so that Apache can read them.
sub set_certificate_permissions
{
local ($d, $file) = @_;
if (&is_under_directory($d->{'home'}, $file)) {
	&set_permissions_as_domain_user($d, 0700, $file);
	}
else {
	&set_ownership_permissions(undef, undef, 0700, $file);
	}
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
my ($certfile, $keyfile, $size, $days, $country, $state, $city, $org,
       $orgunit, $common, $email, $altnames, $d, $ctype) = @_;
$ctype ||= $config{'default_ctype'};
&foreign_require("webmin");
$size ||= $webmin::default_key_size;
$days ||= 1825;

# Prepare for SSL alt names
my @cnames = ( $common );
push(@cnames, @$altnames) if ($altnames);
my $conf = &webmin::build_ssl_config(\@cnames);
my $subject = &webmin::build_ssl_subject($country, $state, $city, $org,
					 $orgunit, \@cnames, $email);

# Call openssl and write to temp files
my $keytemp = &transname();
my $certtemp = &transname();
my $ctypeflag = $ctype eq "sha2" || $ctype =~ /^ec/ ? "-sha256" : "";
my $addtextsup = &compare_version_numbers(&get_openssl_version(), '>=', '1.1.1') ? "-addext extendedKeyUsage=serverAuth" : "";
my $out;
if ($ctype =~ /^ec/) {
	my $pubtemp = &transname();
	$out = &backquote_logged(
		"openssl ecparam -genkey -name prime256v1 ".
		"-noout -out ".quotemeta($keytemp)." 2>&1 && ".
		"openssl ec -in ".quotemeta($keytemp)." -pubout ".
		"-out ".quotemeta($pubtemp)." 2>&1 && ".
		"openssl req -new -x509 -reqexts v3_req -days $days ".
		"-config ".quotemeta($conf)." -subj ".quotemeta($subject).
		" $addtextsup -utf8 -key ".quotemeta($keytemp)." ".
		"-out ".quotemeta($certtemp)." 2>&1");
	}
else {
	$out = &backquote_logged(
		"openssl req $ctypeflag -reqexts v3_req -newkey rsa:$size ".
		"-x509 -nodes -out ".quotemeta($certtemp)." -keyout ".quotemeta($keytemp)." ".
		"-days $days -config ".quotemeta($conf)." -subj ".quotemeta($subject)." $addtextsup -utf8 2>&1");
	}
my $rv = $?;
if (!-r $certtemp || !-r $keytemp || $rv) {
	# Failed .. return error
	return &text('csr_ekey', "<pre>$out</pre>");
	}

# Save as domain owner
&create_ssl_certificate_directories($d);
&write_ssl_file_contents($d, $certfile, &read_file_contents($certtemp));
&write_ssl_file_contents($d, $keyfile, &read_file_contents($keytemp));
&sync_combined_ssl_cert($d);

return undef;
}

# generate_certificate_request(csrfile, keyfile, size, country, state,
# 			       city, org, orgunit, commonname, email, &altnames,
# 			       &domain, [cert-type])
# Generates a new self-signed cert, and stores it in the given csr and key
# files. Returns undef on success, or an error message on failure.
sub generate_certificate_request
{
my ($csrfile, $keyfile, $size, $country, $state, $city, $org,
       $orgunit, $common, $email, $altnames, $d, $ctype) = @_;
$ctype ||= $config{'cert_type'};
&foreign_require("webmin");
$size ||= $webmin::default_key_size;

# Generate the key
my $keytemp = &transname();
my $out;
if ($ctype =~ /^ec/) {
	$out = &backquote_command(
		"openssl ecparam -genkey -name prime256v1 -out ".
		quotemeta($keytemp)." 2>&1 </dev/null");
	}
else {
	$out = &backquote_command(
		"openssl genrsa -out ".quotemeta($keytemp).
		" $size 2>&1 </dev/null");
	}
my $rv = $?;
if (!-s $keytemp || $rv) {
	return &text('csr_ekey', "<pre>$out</pre>");
	}

# Generate the CSR
my @cnames = ( $common );
push(@cnames, @$altnames) if ($altnames);
my ($ok, $csrtemp) = &webmin::generate_ssl_csr($keytemp, $country, $state, $city, $org, $orgunit, \@cnames, $email, $ctype);
if (!$ok) {
	return &text('csr_ecsr', "<pre>$csrtemp</pre>");
	}

# Copy into place
&create_ssl_certificate_directories($d);
&write_ssl_file_contents($d, $keyfile, &read_file_contents($keytemp));
&write_ssl_file_contents($d, $csrfile, &read_file_contents($csrtemp));
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

# find_matching_certificate_domain(&domain)
# Check if another domain on the same IP already has a matching cert, and if so
# return it (or a list of matches)
sub find_matching_certificate_domain
{
local ($d) = @_;
local @sslclashes = grep { $_->{'ip'} eq $d->{'ip'} &&
			   &domain_has_ssl($_) &&
			   $_->{'id'} ne $d->{'id'} &&
			   !$_->{'ssl_same'} } &list_domains();
local @rv;
foreach my $sslclash (@sslclashes) {
	if (&check_domain_certificate($d->{'dom'}, $sslclash)) {
		push(@rv, $sslclash);
		}
	}
return wantarray ? @rv : $rv[0];
}

# find_matching_certificate(&domain)
# For a domain with SSL being enabled, check if another domain on the same IP
# with the same owner already has a matching cert. If so, update the domain
# hash's cert file. This can only be called at domain creation time.
sub find_matching_certificate
{
my ($d) = @_;
my $lnk = $d->{'link_certs'} == 1 ? 1 :
	  $d->{'link_certs'} == 2 ? 2 :
	  $d->{'nolink_certs'} ? 0 :
	  $config{'nolink_certs'} == 1 ? 0 :
	  $config{'nolink_certs'} == 2 ? 2 : 1;
if ($lnk) {
	my @sames = &find_matching_certificate_domain($d);
	if ($lnk != 2) {
		@sames = grep { $_->{'user'} eq $d->{'user'} } @sames;
		}
	if (@sames) {
		my ($same) = grep { !$_->{'parent'} } @sames;
		$same ||= $sames[0];
		if ($same) {
			# Found a match, so add a link to it
			&link_matching_certificate($d, $same, 0);
			}
		}
	}
}

# link_matching_certificate(&domain, &samedomain, [save-actual-config])
# Makes the first domain use SSL cert file owned by the second
sub link_matching_certificate
{
my ($d, $sslclash, $save) = @_;
my @beforecerts = &get_all_domain_service_ssl_certs($d);
$d->{'ssl_cert'} = $sslclash->{'ssl_cert'};
$d->{'ssl_key'} = $sslclash->{'ssl_key'};
$d->{'ssl_same'} = $sslclash->{'id'};
$d->{'ssl_chain'} = &get_website_ssl_file($sslclash, 'ca');
if ($save) {
	&save_website_ssl_file($d, 'cert', $d->{'ssl_cert'});
	&save_website_ssl_file($d, 'key', $d->{'ssl_key'});
	&save_website_ssl_file($d, 'ca', $d->{'ssl_chain'});
	&sync_combined_ssl_cert($d);
	&update_all_domain_service_ssl_certs($d, \@beforecerts);
	}
}

# generate_default_certificate(&domain)
# If a domain doesn't have a cert file set, pick one and generate a self-signed
# cert if needed. May print stuff.
sub generate_default_certificate
{
my ($d) = @_;
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
if (!-r $d->{'ssl_cert'} && !-r $d->{'ssl_key'}) {
	# Need to do it
	my $temp = &transname();
	&$first_print($text{'setup_openssl'});
	&lock_file($d->{'ssl_cert'});
	&lock_file($d->{'ssl_key'});
	my @alts = ( $d->{'dom'}, "localhost",
			&get_system_hostname(0),
			&get_system_hostname(1) );
	@alts = &unique(@alts);
	my $err = &generate_self_signed_cert(
		$d->{'ssl_cert'}, $d->{'ssl_key'}, undef, 1825,
		undef, undef, undef,
		$d->{'default_cert_owner'} ? $d->{'owner'} : undef,
		undef,
		"*.$d->{'dom'}",
		$d->{'default_cert_owner'} ? $d->{'emailto_addr'} : undef,
		\@alts, $d);
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
	delete($d->{'ssl_chain'});	# No longer valid
	&sync_combined_ssl_cert($d);
	return 1;
	}
return 0;
}

sub list_ssl_file_types
{
return ('key', 'cert', 'chain', 'combined', 'everything');
}

# move_website_ssl_file(&domain, type, new-file)
# Move an SSL cert or key file to a new location
sub move_website_ssl_file
{
my ($d, $type, $file) = @_;
my $oldfile = &get_website_ssl_file($d, $type);
return 0 if (!$oldfile || $oldfile eq $file);
&create_ssl_certificate_directories($d);
&write_ssl_file_contents($d, $file, $oldfile);
&lock_file($file);
&save_website_ssl_file($d, $type, $file);
&unlock_file($file);
foreach my $sd (&get_domain_by("ssl_same", $d->{'id'})) {
	&save_website_ssl_file($sd, $type, $file);
	}
&lock_file($oldfile);
if (&is_under_directory($d->{'home'}, $oldfile)) {
	&unlink_file_as_domain_user($d, $oldfile);
	}
else {
	&unlink_file($oldfile);
	}
&unlock_file($oldfile);
return 1;
}

# break_ssl_linkage(&domain, &old-same-domain)
# If domain was using the SSL cert from old-same-domain before, break the link
# by copying the cert into the default location for domain and updating the
# domain and Apache config to match
sub break_ssl_linkage
{
local ($d, $samed) = @_;
my @beforecerts = &get_all_domain_service_ssl_certs($d);

# Copy the cert and key to the new owning domain's directory
&create_ssl_certificate_directories($d);
foreach my $k (&list_ssl_file_types()) {
	if ($d->{'ssl_'.$k}) {
		$d->{'ssl_'.$k} = &default_certificate_file($d, $k);
		&write_ssl_file_contents(
			$d, $d->{'ssl_'.$k}, $samed->{'ssl_'.$k});
		}
	}
delete($d->{'ssl_same'});

# Re-generate any combined cert files
&sync_combined_ssl_cert($d);

# Update webserver config
my $p = &domain_has_website($d);
if ($p) {
	if ($p eq 'web' && &apache_combined_cert()) {
		&save_website_ssl_file($d, "cert", $d->{'ssl_combined'});
		}
	else {
		&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});
		}
	&save_website_ssl_file($d, "key", $d->{'ssl_key'});
	&save_website_ssl_file($d, "ca", $d->{'ssl_chain'});
	}

# Update any service certs for this domain
&update_all_domain_service_ssl_certs($d, \@beforecerts);

# If Let's Encrypt was in use before, copy across renewal fields
$d->{'letsencrypt_renew'} = $samed->{'letsencrypt_renew'};
$d->{'letsencrypt_last'} = $samed->{'letsencrypt_last'};
$d->{'letsencrypt_last_failure'} = $samed->{'letsencrypt_last_failure'};
$d->{'letsencrypt_last_err'} = $samed->{'letsencrypt_last_err'};
$d->{'ssl_cert_expiry'} = $samed->{'ssl_cert_expiry'} if ($samed->{'ssl_cert_expiry'});
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

# disable_letsencrypt_renewal(&domain)
# If Let's Encrypt renewal is enabled for a domain, turn it off
sub disable_letsencrypt_renewal
{
local ($d) = @_;
if ($d->{'letsencrypt_renew'}) {
	delete($d->{'letsencrypt_renew'});
	&save_domain($d);
	}
}

# hostname_under_domain(&domain|&domains, hostname)
# Returns 1 if some hostname belongs to a domain, and not any subdomain
sub hostname_under_domain
{
my ($d, $name) = @_;
if (ref($d) eq 'ARRAY') {
	# Under any of the domains?
	foreach my $dd (@$d) {
		return 1 if (&hostname_under_domain($dd, $name));
		}
	return 0;
	}
else {
	$name =~ s/\.$//;	# In case DNS record
	if ($name eq $d->{'dom'} ||
	    $name eq "*.".$d->{'dom'} ||
	    $name eq ".".$d->{'dom'}) {
		return 1;
		}
	elsif ($name =~ /^([^\.]+)\.(\S+)$/ && $2 eq $d->{'dom'}) {
		# Under the domain, but what if another domain owns it?
		my $o = &get_domain_by("dom", $name);
		return $o ? 0 : 1;
		}
	else {
		return 0;
		}
	}
}

# sync_dovecot_ssl_cert(&domain, [enable-or-disable])
# If supported, configure Dovecot to use this domain's SSL cert for its IP
sub sync_dovecot_ssl_cert
{
local ($d, $enable) = @_;
local $tmpl = &get_template($d->{'template'});

# Check if dovecot is installed and supports this feature
return -1 if (!&foreign_installed("dovecot"));
&foreign_require("dovecot");
my $ver = &dovecot::get_dovecot_version();
return -1 if ($ver < 2);

my $cfile = &dovecot::get_config_file();
&lock_file($cfile);

# Check if dovecot is using SSL globally
my $conf = &dovecot::get_config();
my $sslyn = &dovecot::find_value("ssl", $conf);
if ($sslyn !~ /yes|required/i) {
	&unlock_file($cfile);
	return 0;
	}
my $ssldis = &dovecot::find_value("ssl_disable", $conf);
if ($ssldis =~ /yes/i) {
	&unlock_file($cfile);
	return 0;
	}

# Created combined file if needed
if (!$d->{'ssl_combined'} && !-r $d->{'ssl_combined'}) {
	&sync_combined_ssl_cert($d);
	}

local $chain = &get_website_ssl_file($d, "ca");
local $nochange = 0;
if ($d->{'virt'}) {
	# Domain has it's own IP

	# Find the existing block for the IP
	my @loc = grep { $_->{'name'} eq 'local' &&
			 $_->{'section'} } @$conf;
	my ($l) = grep { $_->{'value'} eq $d->{'ip'} } @loc;
	my ($imap, $pop3);
	if ($l) {
		($imap) = grep { $_->{'name'} eq 'protocol' &&
				 $_->{'value'} eq 'imap' &&
				 $_->{'enabled'} &&
				 $_->{'sectionname'} eq 'local' &&
				 $_->{'sectionvalue'} eq $d->{'ip'} } @$conf;
		($pop3) = grep { $_->{'name'} eq 'protocol' &&
				 $_->{'value'} eq 'pop3' &&
				 $_->{'enabled'} &&
				 $_->{'sectionname'} eq 'local' &&
				 $_->{'sectionvalue'} eq $d->{'ip'} } @$conf;
		}

	if ($enable) {
		# Needs a cert for the IP
		if (!$l) {
			$l = { 'name' => 'local',
			       'value' => $d->{'ip'},
			       'enabled' => 1,
			       'section' => 1,
			       'members' => [],
			       'file' => $cfile };
			&dovecot::create_section($conf, $l);
			push(@$conf, $l);
			&flush_file_lines($l->{'file'}, undef, 1);
			}
		if (!$imap) {
			$imap = { 'name' => 'protocol',
				  'value' => 'imap',
				  'members' => [
					{ 'name' => 'ssl_cert',
					  'value' => "<".$d->{'ssl_combined'},
					},
					{ 'name' => 'ssl_key',
					  'value' => "<".$d->{'ssl_key'},
					},
					],
				  'indent' => 1,
				  'enabled' => 1,
				  'sectionname' => 'local',
				  'sectionvalue' => $d->{'ip'},
				  'file' => $l->{'file'} };
			&dovecot::create_section($conf, $imap, $l);
			push(@{$l->{'members'}}, $imap);
			push(@$conf, $imap);
			$l->{'eline'} = $imap->{'eline'}+1;
			}
		else {
			&dovecot::save_directive($imap->{'members'},
				"ssl_cert", "<".$d->{'ssl_combined'});
			&dovecot::save_directive($imap->{'members'},
				"ssl_key", "<".$d->{'ssl_key'});
			&dovecot::save_directive($imap->{'members'},
				"ssl_ca", undef);
			}
		if (!$pop3) {
			$pop3 = { 'name' => 'protocol',
				  'value' => 'pop3',
				  'members' => [
					{ 'name' => 'ssl_cert',
					  'value' => "<".$d->{'ssl_combined'} },
					{ 'name' => 'ssl_key',
					  'value' => "<".$d->{'ssl_key'} },
					],
				  'indent' => 1,
				  'enabled' => 1,
				  'sectionname' => 'local',
				  'sectionvalue' => $d->{'ip'},
				  'file' => $l->{'file'} };
			&dovecot::create_section($conf, $pop3, $l);
			push(@{$l->{'members'}}, $pop3);
			push(@$conf, $pop3);
			}
		else {
			&dovecot::save_directive($pop3->{'members'},
				"ssl_cert", "<".$d->{'ssl_combined'});
			&dovecot::save_directive($pop3->{'members'},
				"ssl_key", "<".$d->{'ssl_key'});
			&dovecot::save_directive($pop3->{'members'},
				"ssl_ca", undef);
			}
		&flush_file_lines($imap->{'file'}, undef, 1);
		}
	else {
		# Doesn't need one, either because SSL isn't enabled or the
		# domain doesn't have a private IP. So remove the local block.
		if ($l) {
			if (defined(&dovecot::delete_section)) {
				&dovecot::delete_section($conf, $l);
				@$conf = grep { $_ ne $l } @$conf;
				@$conf = grep { $_->{'sectionname'} ne $l->{'name'} ||
						$_->{'sectionvalue'} ne $l->{'value'} } @$conf;
				}
			else {
				# XXX remove this when delete_section
				# is available
				my $lref = &read_file_lines($l->{'file'});
				splice(@$lref, $l->{'line'},
				       $l->{'eline'}-$l->{'line'}+1);
				undef(@dovecot::get_config_cache);
				}
			&flush_file_lines($l->{'file'});
			}
		else {
			# Nothing to add or remove
			$nochange = 1;
			}
		}
	}
else {
	# Domain has no IP, but Dovecot supports SNI in version 2
	my @loc = grep { $_->{'name'} eq 'local_name' &&
			 $_->{'section'} } @$conf;
	my @sslnames = &get_hostnames_from_cert($d);
	my %sslnames = map { $_, 1 } @sslnames;
	my @doms = ( $d, &get_domain_by("alias", $d->{'id'}) );
	my @myloc = grep { &hostname_under_domain(\@doms, $_->{'value'}) } @loc;
	my @dnames = map { ($_->{'dom'}, "*.".$_->{'dom'}) }
			 grep { !$_->{'deleting'} } @doms;
	my @delloc;
	if (!$enable) {
		# All existing local_name blocks are being removed
		@delloc = @myloc;
		}
	else {
		# May need to add or update
		my $pdname = $d->{'dom'};
		$pdname =~ s/^[^\.]+\.//;
		foreach my $n (@dnames) {
			my ($l) = grep { $_->{'value'} eq $n } @loc;
			if ($l) {
				# Already exists, so update paths
				&dovecot::save_directive($l->{'members'},
					"ssl_cert", "<".$d->{'ssl_combined'});
				&dovecot::save_directive($l->{'members'},
					"ssl_key", "<".$d->{'ssl_key'});
				&dovecot::save_directive($l->{'members'},
					"ssl_ca", undef);
				&flush_file_lines($l->{'file'}, undef, 1);
				}
			else {
				# Need to add
				my $l = { 'name' => 'local_name',
					  'value' => $n,
					  'enabled' => 1,
					  'section' => 1,
					  'members' => [
						{ 'name' => 'ssl_cert',
						  'value' => "<".$d->{'ssl_combined'},
						  'enabled' => 1,
						  'file' => $cfile, },
						{ 'name' => 'ssl_key',
						  'value' => "<".$d->{'ssl_key'},
						  'enabled' => 1,
						  'file' => $cfile, },
						],
					  'file' => $cfile };
				my ($plocal) = grep { $_->{'value'} eq $pdname } @loc;
				&dovecot::create_section($conf, $l, undef,
							 $plocal);
				push(@$conf, $l);
				&flush_file_lines($l->{'file'}, undef, 1);
				}
			}
		# Find old entries to remove
		foreach my $l (@myloc) {
			my ($n) =  grep { $l->{'value'} eq $_ } @dnames;
			if (!$n) {
				push(@delloc, $l);
				}
			}
		}
	if (@delloc) {
		# Remove those to delete
		if (defined(&dovecot::delete_section)) {
			foreach my $l (@delloc) {
				&dovecot::delete_section($conf, $l);
				@$conf = grep { $_ ne $l } @$conf;
				@$conf = grep { $_->{'sectionname'} ne $l->{'name'} ||
						$_->{'sectionvalue'} ne $l->{'value'} } @$conf;
				&flush_file_lines($l->{'file'});
				}
			}
		else {
			# Remove when delete_section is available
			foreach my $l (reverse(@delloc)) {
				my $lref = &read_file_lines($l->{'file'});
				splice(@$lref, $l->{'line'},
				       $l->{'eline'}-$l->{'line'}+1);
				&flush_file_lines($l->{'file'});
				}
			undef(@dovecot::get_config_cache);
			}
		}
	}
&unlock_file($cfile);
&dovecot::apply_configuration() if (!$nochange);
#undef(@dovecot::get_config_cache);
return 1;
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
my @rv = ( $mems{'ssl_cert'}, $mems{'ssl_key'}, $mems{'ssl_ca'},
	   $d->{'ip'}, undef );
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
my ($l) = grep { &hostname_under_domain($d, $_->{'value'}) } @loc;
return ( ) if (!$l);
my %mems = map { $_->{'name'}, $_->{'value'} } @{$l->{'members'}};
return ( ) if (!$mems{'ssl_cert'});
my @rv = ( $mems{'ssl_cert'}, $mems{'ssl_key'}, $mems{'ssl_ca'},
	   undef, $d->{'dom'} );
foreach my $r (@rv) {
	$r =~ s/^<//;
	}
return @rv;
}

# postfix_supports_sni()
# Returns 1 if the installed version of Postfix supports name-based SSL certs
sub postfix_supports_sni
{
return 0 if ($mail_system != 0);
&foreign_require("postfix");
return $postfix::postfix_version >= 3.4;
}

# sync_postfix_ssl_cert(&domain, enable)
# Configure Postfix to use a domain's SSL cert for connections on its IP
sub sync_postfix_ssl_cert
{
local ($d, $enable) = @_;
local $tmpl = &get_template($d->{'template'});

# Check if Postfix is in use
return -1 if ($mail_system != 0);

local $changed = 0;
&foreign_require("postfix");
if ($d->{'virt'}) {
	# Setup per-IP cert in master.cf

	# Check if using SSL globally
	local $cfile = &postfix::get_real_value("smtpd_tls_cert_file");
	local $kfile = &postfix::get_real_value("smtpd_tls_key_file");
	local $cafile = &postfix::get_real_value("smtpd_tls_CAfile");
	return 0 if ($enable && (!$cfile || !$kfile) &&
		     !&domain_has_ssl_cert($d));

	# Find the existing master file entry
	&lock_file($postfix::config{'postfix_master'});
	local $master = &postfix::get_master_config();
	local $defip = &get_default_ip();

	# Work out which flags are needed
	local $chain = &domain_has_ssl_cert($d) ?
			&get_website_ssl_file($d, 'ca') : $cafile;
	local @flags = ( [ "smtpd_tls_cert_file",
			   &domain_has_ssl_cert($d) ?
				$d->{'ssl_cert'} : $cfile ],
			 [ "smtpd_tls_key_file",
			   &domain_has_ssl_cert($d) ?
				$d->{'ssl_key'} : $kfile ] );
	push(@flags, [ "smtpd_tls_CAfile", $chain ]) if ($chain);
	push(@flags, [ "smtpd_tls_security_level", "may" ]);
	push(@flags, [ "myhostname", $d->{'dom'} ]);

	foreach my $pfx ('smtp', 'submission', 'smtps') {
		# Find the existing entry for the IP and for the default service
		local $already;
		local $smtp;
		local @others;
		local $lsmtp;
		foreach my $m (@$master) {
			if ($m->{'name'} eq $d->{'ip'}.':'.$pfx &&
			    $m->{'enabled'} &&
			    $d->{'ip'} ne $defip) {
				# Entry for service for the domain
				$already = $m;
				}
			if (($m->{'name'} eq $pfx ||
			     $m->{'name'} eq $defip.':'.$pfx) &&
			    $m->{'type'} eq 'inet' && $m->{'enabled'}) {
				# Entry for default service
				$smtp = $m;
				}
			if ($m->{'name'} =~ /^([0-9\.]+):\Q$pfx\E$/ &&
			    $m->{'enabled'} && $1 ne $d->{'ip'} &&
			    $1 ne $defip) {
				# Entry for some other domain
				if ($1 eq "127.0.0.1") {
					$lsmtp = $m;
					}
				else {
					push(@others, $m);
					}
				}
			}
		next if (!$smtp && $enable);

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
				$already->{'command'} =~ s/-o smtpd_(client|helo|sender)_restrictions=\$mua_client_restrictions\s+//g;
				&postfix::create_master($already);
				$changed = 1;

				# If the primary smtp entry isn't bound to an
				# IP, fix it to prevent IP clashes
				if ($smtp->{'name'} eq $pfx) {
					$smtp->{'name'} = $defip.':'.$pfx;
					&postfix::modify_master($smtp);

					# Also add an entry to listen on
					# 127.0.0.1
					if (!$lsmtp) {
						$lsmtp = { %$smtp };
						delete($lsmtp->{'line'});
						delete($lsmtp->{'uline'});
						$lsmtp->{'name'} =
							'127.0.0.1:'.$pfx;
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
				&postfix::modify_master($already);
				$changed = 1;
				}
			}
		else {
			# Remove the entry
			if ($already) {
				&postfix::delete_master($already);
				$changed = 1;
				}
			if (!@others && $smtp && $smtp->{'name'} ne $pfx) {
				# If the default service has an IP but this is
				# no longer needed, remove it
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
	}
elsif (&postfix_supports_sni()) {
	# Check if Postfix has an SNI map defined
	my $maphash = &postfix::get_current_value("tls_server_sni_maps");
	my $mapfile;
	if (!$maphash) {
		# No, so add it
		$mapfile = &postfix::guess_config_dir()."/sni_map";
		$maphash = &default_postfix_map_type().":".$mapfile;
		&postfix::set_current_value("tls_server_sni_maps", $maphash);
		&postfix::ensure_map("tls_server_sni_maps");
		$changed++;
		}
	else {
		($mapfile) = &postfix::get_maps_files($maphash);
		}

	# Is there an entra for this domain already?
	&lock_file($mapfile);
	my $map = &postfix::get_maps("tls_server_sni_maps");
	my @certs = ( $d->{'ssl_key'}, $d->{'ssl_cert'} );
	push(@certs, $d->{'ssl_chain'}) if ($d->{'ssl_chain'});
	my $certstr = join(",", @certs);
	my @doms = ( $d, &get_domain_by("alias", $d->{'id'}) );
	my @dnames = map { ($_->{'dom'}, ".".$_->{'dom'}) }
			 grep { !$_->{'deleting'} } @doms;
	my @mymaps = grep { &hostname_under_domain(\@doms,$_->{'name'}) } @$map;
	my @delmaps;
	if (!$enable) {
		# Deleting them all
		@delmaps = @mymaps;
		}
	else {
		# Add or update map entries for domain
		my $pdname = $d->{'dom'};
		$pdname =~ s/^[^\.]+\.//;
		foreach my $dname (@dnames) {
			my ($r) = grep { $_->{'name'} eq $dname } @$map;
			my ($pdr) = grep { $_->{'name'} eq $pdname } @$map;
			if (!$r) {
				# Need to add
				&postfix::create_mapping(
				    "tls_server_sni_maps",
				    { 'name' => $dname, 'value' => $certstr },
				    undef, undef, $pdr);
				}
			else {
				# Update existing certs
				$r->{'value'} = $certstr;
				&postfix::modify_mapping(
				    "tls_server_sni_maps", $r, $r);
				}
			}
		# Identify those no longer needed
		foreach my $r (@mymaps) {
			my ($n) =  grep { $r->{'name'} eq $_ } @dnames;
			if (!$n) {
				push(@delmaps, $r);
				}
			}
		}
	if (@delmaps) {
		# Remove un-needed map entries
		foreach my $r (reverse(@delmaps)) {
			&postfix::delete_mapping("tls_server_sni_maps", $r);
			}
		}
	&unlock_file($mapfile);
	&postfix::regenerate_sni_table();
	}
else {
	# Cannot use per-domain or per-IP cert
	return 0;
	}
&register_post_action(\&restart_mail_server);
return 1;
}

# sync_proftpd_ssl_cert(&domain, enable)
# Configure ProFTPd to use a domain's SSL cert for connections on its IP
sub sync_proftpd_ssl_cert
{
my ($d, $enable) = @_;
&foreign_require("proftpd");
&proftpd::lock_proftpd_files();
my ($virt, $vconf, $conf) = &get_proftpd_virtual($d);
return 0 if (!$virt);
if ($enable) {
	# Make proftpd virtualhost use domain's SSL cert files
	my $cfile = &get_website_ssl_file($d, "cert");
	&proftpd::save_directive(
		"TLSRSACertificateFile", [ $cfile ], $vconf, $conf);
	my $kfile = &get_website_ssl_file($d, "key");
	&proftpd::save_directive(
		"TLSRSACertificateKeyFile", [ $kfile ], $vconf, $conf);
	my $cafile = &get_website_ssl_file($d, "ca");
	&proftpd::save_directive(
		"TLSCACertificateFile", $cafile ? [ $cafile ] : [ ], $vconf, $conf);
	&proftpd::save_directive("TLSEngine", [ "on" ], $vconf, $conf);
	&proftpd::save_directive("TLSOptions", [ "NoSessionReuseRequired" ], $vconf, $conf);
	}
else {
	# Remove SSL cert for domain
	&proftpd::save_directive(
		"TLSRSACertificateFile", [ ], $vconf, $conf);
	&proftpd::save_directive(
		"TLSRSACertificateKeyFile", [ ], $vconf, $conf);
	&proftpd::save_directive(
		"TLSCACertificateFile", [ ], $vconf, $conf);
	&proftpd::save_directive("TLSEngine", [ ], $vconf, $conf);
	&proftpd::save_directive("TLSOptions", [ ], $vconf, $conf);
	}
&flush_file_lines($virt->{'file'}, undef, 1);
&proftpd::unlock_proftpd_files();
&register_post_action(\&restart_proftpd);
return 1;
}

# get_postfix_ssl_cert(&domain)
# Returns the path to the cert, key and CA cert in the Postfix config for
# a domain, if any
sub get_postfix_ssl_cert
{
my ($d) = @_;
return ( ) if ($mail_system != 0);
&foreign_require("postfix");

# First check for a per-domain cert
if (&postfix::get_current_value("tls_server_sni_maps")) {
	my $map = &postfix::get_maps("tls_server_sni_maps");
	my ($already) = grep { &hostname_under_domain($d, $_->{'name'}) } @$map;
	if ($already) {
		# Found it!
		my @certs = split(/,/, $already->{'value'});
		return ($certs[1], $certs[0], $certs[2], undef, $d->{'dom'});
		}
	}

# Fall back to checking for a per-IP cert
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
my @webmail;
if ($p eq "web") {
	@webmail = &get_webmail_redirect_directives($d);
	}
my @recs;
if ($d->{'dns'}) {
	@recs = &get_domain_dns_records($d);
	}
foreach my $full ("www.".$d->{'dom'},
		  ($d->{'mail'} ? ("mail.".$d->{'dom'}) : ()),
		  "admin.".$d->{'dom'},
		  "webmail.".$d->{'dom'},
		  &get_autoconfig_hostname($d)) {
	# Is the webserver configured to serve this hostname?
	my $virt;
	if ($p eq "web") {
		$virt = &get_apache_virtual($full, $d->{'web_port'});
		}
	else {
		$virt = &plugin_call($p, "feature_get_domain_web_config",
				     $full, $d->{'web_port'});
		}
	next if (!$virt || $virt ne $defvirt);

	# If Apache, is there an unconditional rewrite for this hostname?
	my $found;
	foreach my $wm (@webmail) {
		if ($wm->[0] eq $full && $wm->[1] eq '^(.*)') {
			$found = 1;
			}
		}
	next if ($found);

	# Is there a DNS entry for this hostname?
	if ($d->{'dns'}) {
		my ($r) = grep { $_->{'name'} eq $full."." } @recs;
		if ($r) {
			push(@rv, $full);
			}
		}
	if (&to_ipaddress($full)) {
		push(@rv, $full);
		}
	}
if (!$d->{'alias'}) {
	# Add aliases of this domain that have SSL enabled
	foreach my $alias (&get_domain_by("alias", $d->{'id'})) {
		if (&domain_has_website($alias) && !$alias->{'disabled'} &&
		    !$alias->{'deleting'}) {
			push(@rv, &get_hostnames_for_ssl($alias));
			}
		}
	}
return &unique(@rv);
}

# get_hostnames_from_cert(&domain)
# Returns a list of hostnames that the domain's cert is valid for
sub get_hostnames_from_cert
{
my $info = &cert_info($d);
return () if (!$info);
my @rv = ( $info->{'cn'} );
push(@rv, @{$info->{'alt'}}) if ($info->{'alt'});
return @rv;
}

# is_letsencrypt_cert(&info|&domain)
# Returns 1 if a cert info looks like it comes from Let's Encrypt
sub is_letsencrypt_cert
{
my ($info) = @_;
if ($info->{'dom'} && $info->{'id'}) {
	# Looks like a virtual server
	$info = &cert_info($info);
	}
return $info && ($info->{'issuer_cn'} =~ /Let's\s+Encrypt/i ||
		 $info->{'issuer_o'} =~ /Let's\s+Encrypt/i);
}

# apply_letsencrypt_cert_renewals()
# Check all domains that need a new Let's Encrypt cert
sub apply_letsencrypt_cert_renewals
{
my $le_max_renewals = 300.0;
my $le_max_time = 3*60*60;	# 3 hours
my $last_renew_time = $config{'last_letsencrypt_mass_renewal'};
my $now = time();

my $done = 0;
foreach my $d (&list_domains()) {
	# Does the domain have SSL enabled and a renewal policy?
	next if (!&domain_has_ssl_cert($d) || !$d->{'letsencrypt_renew'});

	# Does the domain have it's own SSL cert?
	next if ($d->{'ssl_same'});

	# Is the domain enabled?
	next if ($d->{'disabled'});

	# Get the cert and date
	my $info = &cert_info($d);
	next if (!$info);
	my $expiry = &parse_notafter_date($info->{'notafter'});

	# Is the current cert even from Let's Encrypt?
	next if (!&is_letsencrypt_cert($info));

	# Figure out when the cert was last renewed. This is the max of the
	# date in the cert and the time recorded in Virtualmin
	my $ltime = &parse_notafter_date($info->{'notbefore'});
	$ltime = $d->{'letsencrypt_last'}
		if ($d->{'letsencrypt_last'} > $ltime);

	# If an attempt was made in the last hour, skip for now to prevent
	# hammering the Let's Encrypt serivce
	next if (time() - $d->{'letsencrypt_last'} < 60*60);

	# Is it time? Either the user-chosen number of months has passed, or
	# the cert is within 30 days of expiry
	my $before = $config{'renew_letsencrypt'} || 30;
	my $day = 24 * 60 * 60;
	my $age = time() - $ltime;
	my $rf = rand() * 3600;
	my $renew = $expiry && $expiry - time() < $before * $day + $rf;
	next if (!$renew);

	# Don't even attempt now if the lock is being held
	next if (&test_lock($ssl_letsencrypt_lock));

	# Don't exceed the global let's encrypt rate limit
	if ($last_renew_time) {
		my $diff = $now - $last_renew_time;
		if ($done > $le_max_renewals / $le_max_time * $diff / 2) {
			# Done too much this cycle (more than half of the limit)
			last;
			}
		}

	# Find the SSL proivider name
	my $pname;
	if (defined(&list_acme_providers)) {
		my ($acme) = grep { $_->{'id'} eq $d->{'letsencrypt_id'} }
                                  &list_acme_providers();
		if ($acme->{'type'}) {
			my ($prov) = grep { $_->{'id'} eq $acme->{'type'} }
				          &list_known_acme_providers();
			$pname = $prov->{'desc'};
			}
		else {
			$pname = $acme->{'desc'};
			}
		}
	else {
		$pname = $text{'acme_letsencrypt'};
		}

	# Time to attempt the renewal
	$done++;
	my ($ok, $err, $dnames) = &renew_letsencrypt_cert($d);
	my ($subject, $body);
	&lock_domain($d);
	if (!$ok) {
		# Failed! Tell the user
		$subject = $text{'letsencrypt_sfaileda'};
		$body = &text('letsencrypt_bfaileda',
			      join(", ", @$dnames), $err, $pname);
		$d->{'letsencrypt_last'} = time();
		$d->{'letsencrypt_last_failure'} = time();
		$err =~ s/\r?\n/\t/g;
		$d->{'letsencrypt_last_err'} = $err;
		}
	else {
		# Tell the user it worked
		delete($d->{'letsencrypt_last_err'});
		$subject = $text{'letsencrypt_sdonea'};
		$body = &text('letsencrypt_bdonea',
			      join(", ", @$dnames), $pname);
		}
	&save_domain($d);

	# Send email
	my $from = &get_global_from_address($d);
	if ($d->{'letsencrypt_email'} == 0 ||
	    $d->{'letsencrypt_email'} == 1 && !$ok) {
		&send_notify_email($from, [$d], $d, $subject, $body);
		}
	&unlock_domain($d);
	}

$config{'last_letsencrypt_mass_renewal'} = $now;
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

# renew_letsencrypt_cert(&domain)
# Re-request the Let's Encrypt cert for a domain. 
sub renew_letsencrypt_cert
{
my ($d) = @_;

# Work out the hostnames to request
my @dnames;
if ($d->{'letsencrypt_dname'}) {
	@dnames = split(/\s+/, $d->{'letsencrypt_dname'});
	}
else {
	@dnames = &get_hostnames_for_ssl($d);
	}
push(@dnames, "*.".$d->{'dom'}) if ($d->{'letsencrypt_dwild'});
my $fdnames = &filter_ssl_wildcards(\@dnames);
@dnames = @$fdnames;
if (defined($d->{'letsencrypt_nodnscheck'}) &&
    !$d->{'letsencrypt_nodnscheck'}) {
	my @badnames;
	my $fok = &filter_external_dns(\@dnames, \@badnames);
	if (!@dnames) {
		return (0, "None of the hostnames could be resolved", \@badnames);
		}
	}

# Run the before command
&set_domain_envs($d, "SSL_DOMAIN");
my $merr = &making_changes();
&reset_domain_envs($d);
if ($merr) {
	# Pre-command failed
	return (0, $merr, \@dnames);
	}

# Time to do it!
my $phd = &public_html_dir($d);
&foreign_require("webmin");
my $before = &before_letsencrypt_website($d);
my $acme;
if ($d->{'letsencrypt_id'} && defined(&list_acme_providers)) {
	($acme) = grep { $_->{'id'} eq $d->{'letsencrypt_id'} }
		       &list_acme_providers();
	}
my ($ok, $cert, $key, $chain) =
	&request_domain_letsencrypt_cert($d, \@dnames, 0,
	    $d->{'letsencrypt_size'}, undef, $d->{'letsencrypt_ctype'},
	    $acme, $d->{'letsencrypt_subset'});
&after_letsencrypt_website($d, $before);

my ($subject, $body);
if (!$ok) {
	# Failed! Tell the user
	return (0, $cert, \@dnames);
	}

# Figure out which services (webmin, postfix, etc) were using the old cert
my @beforecerts = &get_all_domain_service_ssl_certs($d);

# Copy into place
&obtain_lock_ssl($d);
&install_letsencrypt_cert($d, $cert, $key, $chain);
&lock_domain($d);
$d->{'letsencrypt_last'} = time();
$d->{'letsencrypt_last_success'} = time();
delete($d->{'letsencrypt_last_err'});
&save_domain($d);
&unlock_domain($d);
&release_lock_ssl($d);

# Update DANE DNS records
&sync_domain_tlsa_records($d);

# Update services that were using the old cert, both globally and per-domain
&update_all_domain_service_ssl_certs($d, \@beforecerts);

# Call the post command
&set_domain_envs($d, "SSL_DOMAIN");
&made_changes();
&reset_domain_envs($d);

return (1, undef, \@dnames);
}

# install_letsencrypt_cert(&domain, certfile, keyfile, chainfile)
# Update the current cert and key for a domain
sub install_letsencrypt_cert
{
my ($d, $cert, $key, $chain) = @_;

# Copy and save the cert
$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
my $cert_text = &read_file_contents($cert);
&lock_file($d->{'ssl_cert'});
&create_ssl_certificate_directories($d);
&write_ssl_file_contents($d, $d->{'ssl_cert'}, $cert_text);
&unlock_file($d->{'ssl_cert'});
&save_website_ssl_file($d, "cert", $d->{'ssl_cert'});

# And the key
$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
my $key_text = &read_file_contents($key);
&lock_file($d->{'ssl_key'});
&write_ssl_file_contents($d, $d->{'ssl_key'}, $key_text);
&unlock_file($d->{'ssl_key'});
&save_website_ssl_file($d, "key", $d->{'ssl_key'});

# Let's encrypt certs have no passphrase
$d->{'ssl_pass'} = undef;
&save_domain_passphrase($d);

# And the chained file
if ($chain) {
	$chainfile = $d->{'ssl_chain'} ||
	    &default_certificate_file($d, 'ca');
	$chain_text = &read_file_contents($chain);
	&lock_file($chainfile);
	&write_ssl_file_contents($d, $chainfile, $chain_text);
	&unlock_file($chainfile);
	$err = &save_website_ssl_file($d, 'ca', $chainfile);
	$d->{'ssl_chain'} = $chainfile;
	}

# Create the combined cert file
&sync_combined_ssl_cert($d);

# If the domain has DNS, setup a CAA record
&update_caa_record($d);
}

# update_caa_record(&domain, [force-letsencrypt])
# Update the CAA record for Let's Encrypt if needed
sub update_caa_record
{
my ($d, $letsencrypt_cert) = @_;
&require_bind();
return undef if (!$d->{'dns'});
return undef if (!$d->{'dns_cloud'} &&
		 &compare_version_numbers($bind8::bind_version, "9.9.6") < 0);
my ($recs, $file) = &get_domain_dns_records_and_file($d);
my @caa = grep { $_->{'type'} eq 'CAA' } @$recs;
# At this stage the cert is always self-signed,
# so we need to force it for Let's Encrypt
my $lets = $letsencrypt_cert;
if (!$lets) {
	my $info = &cert_info($d);
	$lets = &is_letsencrypt_cert($info) ? 1 : 0;
	}
# Need delay for DNS propagation
if (!@caa && $lets) {
	# Need to add a Let's Encrypt record
	&pre_records_change($d);
	my $caa = { 'name' => '@',
		    'type' => 'CAA',
		    'values' => [ "0", "issuewild", "letsencrypt.org" ] };
	&create_dns_record($recs, $file, $caa);
	&post_records_change($d, $recs, $file);
	&reload_bind_records($d);
	}
elsif (@caa == 1 &&
       $caa[0]->{'values'}->[1] eq 'issuewild' &&
       $caa[0]->{'values'}->[2] eq 'letsencrypt.org' && !$lets) {
	# Need to remove the record
	&pre_records_change($d);
	&delete_dns_record($recs, $file, $caa[0]);
	&post_records_change($d, $recs, $file);
	&reload_bind_records($d);
	}
}

# sync_combined_ssl_cert(&domain)
# If a domain has a regular cert and a CA cert, combine them into one file
sub sync_combined_ssl_cert
{
my ($d) = @_;
if ($d->{'ssl_same'}) {
	# Assume parent has the combined files
	my $sslclash = &get_domain($d->{'ssl_same'});
	&sync_combined_ssl_cert($sslclash);
	$d->{'ssl_combined'} = $sslclash->{'ssl_combined'};
	$d->{'ssl_everything'} = $sslclash->{'ssl_everything'};
	return;
	}

# Create file of all the certs
my $combfile = $d->{'ssl_combined'} ||
       &default_certificate_file($d, 'combined');
&lock_file($combfile);
&create_ssl_certificate_directories($d);
my $comb = &read_file_contents($d->{'ssl_cert'})."\n";
if (-r $d->{'ssl_chain'}) {
	$comb .= &read_file_contents($d->{'ssl_chain'})."\n";
	}
&write_ssl_file_contents($d, $combfile, $comb);
&unlock_file($combfile);
$d->{'ssl_combined'} = $combfile;

# Create file of all the certs, and the key
my $everyfile = $d->{'ssl_everything'} ||
       &default_certificate_file($d, 'everything');
&lock_file($everyfile);
my $every = &read_file_contents($d->{'ssl_key'})."\n".
	    &read_file_contents($d->{'ssl_cert'})."\n";
if (-r $d->{'ssl_chain'}) {
	$every .= &read_file_contents($d->{'ssl_chain'})."\n";
	}
&write_ssl_file_contents($d, $everyfile, $every);
&unlock_file($everyfile);
$d->{'ssl_everything'} = $everyfile;
}

# get_openssl_version()
# Returns the version of the installed OpenSSL command
sub get_openssl_version
{
my $out = &backquote_command("openssl version 2>/dev/null");
if ($out =~ /OpenSSL\s+(\d\.\d\.\d)/) {
	return $1;
	}
return 0;
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

# filter_ssl_wildcards(&hostnames)
# Returns an array ref of hostnames for an SSL cert request, minus any that
# are redundant due to wildcards
sub filter_ssl_wildcards
{
my ($dnames) = @_;
my @rv;
my %wild;
foreach my $h (@$dnames) {
	if ($h =~ /^\*\.(.*)$/) {
		$wild{$1} = 1;
		}
	}
foreach my $h (@$dnames) {
	next if ($h =~ /^([^\.\*]+)\.(.*)$/ && $wild{$2});
	push(@rv, $h);
	}
return \@rv;
}

# request_domain_letsencrypt_cert(&domain, &dnames, [staging], [size], [mode],
# 				  [key-type], [&acme], [allow-subset])
# Attempts to request a Let's Encrypt cert for a domain, trying both web and
# DNS modes if possible. The key type must be one of 'rsa' or 'ecdsa'
sub request_domain_letsencrypt_cert
{
my ($d, $dnames, $staging, $size, $mode, $ctype, $acme, $subset) = @_;
my ($server, $keytype, $hmac);
if ($acme) {
	defined(&list_acme_providers) ||
	    return (0, "Custom ACME providers are only supported in Virtualmin Pro");
	$keytype = $acme->{'key'};
	$hmac = $acme->{'hmac'};
	if ($acme->{'type'}) {
		my ($prov) = grep { $_->{'id'} eq $acme->{'type'} }
				  &list_known_acme_providers();
		$prov || return (0, "ACME provider $acme->{'type'} does not exist");
		$server = ($staging ? $prov->{'staging_url'} : undef) ||
			  $prov->{'url'};
		}
	else {
		$server = $acme->{'url'};
		}
	}
my ($ok, $cert, $key, $chain, @errs);
$dnames = &filter_ssl_wildcards($dnames);
$size ||= $config{'key_size'};
&foreign_require("webmin");
my $phd = &public_html_dir($d);
my $actype = $ctype =~ /^ec/ ? "ecdsa" : "rsa";
my $dcinfo = &cert_info($d);
my $dclets = &is_letsencrypt_cert($d);
my $dcalgo = $dcinfo->{'algo'};
my $dctype = $dcalgo =~ /^ec/ ? "ecdsa" : "rsa";
my $actype_reuse = $actype eq $dctype ? 1 : 0;
$actype_reuse = -1 if (!$dcalgo || !$dclets);
my @wilds = grep { /^\*\./ } @$dnames;
&lock_file($ssl_letsencrypt_lock);
&disable_quotas($d);
foreach my $try (0, 1) {
	@errs = ();
	if (&domain_has_website($d) && !@wilds && (!$mode || $mode eq "web")) {
		# Try using website first
		($ok, $cert, $key, $chain) = &webmin::request_letsencrypt_cert(
			$dnames, $phd, $d->{'emailto'}, $size, "web", $staging,
			&get_global_from_address(), $actype, $actype_reuse,
			$server, $keytype, $hmac, $subset);
		push(@errs, &text('letsencrypt_eweb', $cert)) if (!$ok);
		}
	if (!$ok && &get_webmin_version() >= 1.834 && $d->{'dns'} &&
		(!$mode || $mode eq "dns")) {
		# Fall back to DNS
		($ok, $cert, $key, $chain) = &webmin::request_letsencrypt_cert(
			$dnames, undef, $d->{'emailto'}, $size, "dns", $staging,
			&get_global_from_address(), $actype, $actype_reuse,
			$server, $keytype, $hmac, $subset);
		push(@errs, &text('letsencrypt_edns', $cert)) if (!$ok);
		}
	elsif (!$ok) {
		if (!$cert) {
			$cert = "Domain has no website, ".
				"and DNS-based validation is not possible";
			push(@errs, $cert);
			}
		}
	if (!$ok && !$try) {
		# Try again after a small delay, which works in 99% of
		# cases, considering initial configuration was correct
		my %webmin_mod_config = &foreign_config("webmin");
		sleep((int($webmin_mod_config{'letsencrypt_dns_wait'}) || 10) * 2);
		}
	else {
		last;
		}
	}
&enable_quotas($d);
&unlock_file($ssl_letsencrypt_lock);
# Return results
if (!$ok) {
	return ($ok, join("&nbsp;&nbsp;&nbsp;", @errs), $key, $chain);
	}
else {
	return ($ok, $cert, $key, $chain);
	}
}

# validate_letsencrypt_config(&domain, [&features])
# Returns a list of validation errors that might prevent Let's Encrypt
sub validate_letsencrypt_config
{
my ($d, $feats) = @_;
my @rv;
$feats ||= ["web", "dns"];
foreach my $f (@$feats) {
	if ($d->{$f} && $config{$f}) {
		my $vfunc = "validate_$f";
		my $err = &$vfunc($d);
		if ($err) {
			push(@rv, { 'desc' => $text{'feature_'.$f},
				    'error' => $err });
			}
		}
	}
return @rv;
}

# letsencrypt_supports_ec()
# Returns 1 if Let's Encrypt client supports EC certificates
sub letsencrypt_supports_ec
{
&foreign_require("webmin");
return 0 if (&webmin::check_letsencrypt());	# Not installed
return 0 if (!$webmin::letsencrypt_cmd);	# Missing native client
my $ver = &webmin::get_certbot_major_version($webmin::letsencrypt_cmd);
return &compare_versions($ver, 2.0) >= 0;
}

# sync_webmin_ssl_cert(&domain, [enable-or-disable])
# Add or remove the SSL cert for Webmin for this domain. Returns 1 on success,
# 0 on failure, or -1 if not supported. Calls restart_webmin_fully on older
# Webmin versions because SSL certs are only loaded by miniserv at startup,
# rather than on a config reload.
sub sync_webmin_ssl_cert
{
my ($d, $enable) = @_;
my %miniserv;
&get_miniserv_config(\%miniserv);
return -1 if (!$miniserv{'ssl'});
my $rfunc = &get_webmin_version() >= 2.001 ? \&restart_webmin
					   : \&restart_webmin_fully;
if ($enable) {
	return &setup_ipkeys(
		$d, \&get_miniserv_config, \&put_miniserv_config, $rfunc);
	}
else {
	return &delete_ipkeys(
		$d, \&get_miniserv_config, \&put_miniserv_config, $rfunc);
	}
}

# sync_usermin_ssl_cert(&domain, [enable-or-disable])
# Add or remove the SSL cert for Usermin for this domain. Returns 1 on success,
# 0 on failure, or -1 if not supported.
sub sync_usermin_ssl_cert
{
my ($d, $enable) = @_;
return -1 if (!&foreign_installed("usermin"));
&foreign_require("usermin");
my %miniserv;
&usermin::get_miniserv_config(\%miniserv);
return -1 if (!$miniserv{'ssl'});
if ($enable) {
	return &setup_ipkeys($d, \&usermin::get_usermin_miniserv_config,
		      \&usermin::put_usermin_miniserv_config,
		      \&restart_usermin);
	}
else {
	return &delete_ipkeys($d, \&usermin::get_usermin_miniserv_config,
		       \&usermin::put_usermin_miniserv_config,
		       \&restart_usermin);
	}
}

# ssl_needs_apache_restart()
# Returns 1 if an SSL cert change needs an Apache restart
sub ssl_needs_apache_restart
{
&require_apache();
return $apache::httpd_modules{'core'} >= 2.4 ? 0 : 1;
}

# ssl_certificate_directories(&domain, [absolute])
# Returns dirs relative to the domain's home needed for SSL certs
sub ssl_certificate_directories
{
my ($d, $abs) = @_;
my @paths;
foreach my $t (&list_ssl_file_types()) {
	push(@paths, &default_certificate_file($d, $t));
	if ($d->{'ssl_'.$t}) {
		push(@paths, $d->{'ssl_'.$t});
		}
	}
my @rv;
foreach my $p (&unique(@paths)) {
	if (!$abs) {
		# Must be relative to home dir
		$p =~ s/^\Q$d->{'home'}\E\/// || next;
		}
	if ($p =~ /^(.*)\//) {
		push(@rv, $1);
		}
	}
return @rv;
}

# create_ssl_certificate_directories(&domain)
# Create all dirs needed for SSL certs
sub create_ssl_certificate_directories
{
my ($d) = @_;
foreach my $dir (&ssl_certificate_directories($d, 1)) {
	if (&is_under_directory($d->{'home'}, $dir)) {
		# Create in the home dir, owned by the user
		&create_standard_directory_for_domain($d, $dir, '700')
			if (!-d $dir);
		}
	else {
		# Create elsewhere if needed. Should *not* be writable by the
		# domain user, to prevent cert deletion.
		if (!-d $dir) {
			&make_dir($dir, 0700, 1);
			}
		}
	}
}

# refresh_ssl_cert_expiry(&domain)
# Update the ssl_cert_expiry field from the actual cert
sub refresh_ssl_cert_expiry
{
my ($d) = @_;
my $cert_info = &cert_info($d);
if ($cert_info) {
	my $expiry = &parse_notafter_date($cert_info->{'notafter'});
	if ($expiry) {
		$d->{'ssl_cert_expiry'} = $expiry;
		}
	}
}

# get_ssl_cert_expiry(&domain)
# Returns the cached SSL cert expiry for a domain
sub get_ssl_cert_expiry
{
my ($d) = @_;
if ($d->{'ssl_same'}) {
	my $s = &get_domain($d->{'ssl_same'});
	return $s ? &get_ssl_cert_expiry($s) : undef;
	}
return $d->{'ssl_cert_expiry'};
}

# can_reset_ssl(&domain)
# Resetting SSL on it's own doesn't make sense, since it's included in the web
# feature reset
sub can_reset_ssl
{
return 0;
}

# show_template_ssl(&tmpl)
# Outputs HTML for editing SSL related template options
sub show_template_ssl
{
local ($tmpl) = @_;

# Default SSL key and cert file paths
foreach my $t ("key", "cert", "ca", "combined", "everything") {
	my $v = $tmpl->{'cert_'.$t.'_tmpl'};
	my $mode = $v eq "auto" ? 2 : $v ? 0 : 1;
	my @opts = ( [ 1, $text{'newweb_cert_def'} ] );
	if ($t ne "key") {
		push(@opts, [ 2, $text{'newweb_cert_auto'} ]);
		}
	push(@opts, [ 0, $text{'newweb_cert_file'},
		      &ui_textbox("web_cert_".$t, $mode == 0 ? $v : "", 50) ]);
	print &ui_table_row(
		&hlink($text{'newweb_cert_'.$t}, "config_".$t."_tmpl"),
		&ui_radio_table("web_certmode_".$t, $mode, \@opts));
	}

# SSL cert provider
if (defined(&list_acme_providers)) {
	print &ui_table_row(
		&hlink($text{'newweb_acme'}, "template_web_acme"),
		&ui_select("web_acme", $tmpl->{'web_acme'},
			   [ [ "", $text{'default'} ],
			     map { [ $_->{'id'}, $_->{'desc'} ] }
				 &list_acme_providers() ]));
	}

print &ui_table_hr();

# Setup matching Webmin/Usermin SSL certs
print &ui_table_row(&hlink($text{'newweb_webmin'},
			   "template_web_webmin_ssl"),
	&ui_yesno_radio("web_webmin_ssl", $tmpl->{'web_webmin_ssl'}));

print &ui_table_row(&hlink($text{'newweb_usermin'},
			   "template_web_usermin_ssl"),
	&ui_yesno_radio("web_usermin_ssl", $tmpl->{'web_usermin_ssl'}));

# Setup Dovecot, Postfix, MySQL and ProFTPd SSL certs
print &ui_table_row(&hlink($text{'newweb_dovecot'},
			   "template_web_dovecot_ssl"),
	&ui_yesno_radio("web_dovecot_ssl", $tmpl->{'web_dovecot_ssl'}));

print &ui_table_row(&hlink($text{'newweb_postfix'},
			   "template_web_postfix_ssl"),
	&ui_yesno_radio("web_postfix_ssl", $tmpl->{'web_postfix_ssl'}));

print &ui_table_row(&hlink($text{'newweb_mysql'},
			   "template_web_mysql_ssl"),
	&ui_yesno_radio("web_mysql_ssl", $tmpl->{'web_mysql_ssl'}));

print &ui_table_row(&hlink($text{'newweb_proftpd'},
			   "template_web_proftpd_ssl"),
	&ui_yesno_radio("web_proftpd_ssl", $tmpl->{'web_proftpd_ssl'}));
}

# parse_template_ssl(&tmpl)
# Updates SSL related template options from %in
sub parse_template_ssl
{
local ($tmpl) = @_;

# Save key file templates
foreach my $t ("key", "cert", "ca", "combined", "everything") {
	my $mode = $in{'web_certmode_'.$t};
	my $v;
	if ($mode == 2) {
		$v = "auto";
		}
	elsif ($mode == 0) {
		$v = $in{'web_cert_'.$t};
		$v =~ /\S/ || &error($text{'newweb_cert_efile'});
		}
	$tmpl->{'cert_'.$t.'_tmpl'} = $v;
	}
if (defined($in{'web_acme'})) {
	$tmpl->{'web_acme'} = $in{'web_acme'};
	}

# Save options to setup per-service SSL certs
$tmpl->{'web_webmin_ssl'} = $in{'web_webmin_ssl'};
$tmpl->{'web_usermin_ssl'} = $in{'web_usermin_ssl'};
$tmpl->{'web_postfix_ssl'} = $in{'web_postfix_ssl'};
$tmpl->{'web_dovecot_ssl'} = $in{'web_dovecot_ssl'};
$tmpl->{'web_mysql_ssl'} = $in{'web_mysql_ssl'};
$tmpl->{'web_proftpd_ssl'} = $in{'web_proftpd_ssl'};
}

# chained_ssl(&domain, [&old-domain])
# SSL is automatically enabled when a website is, if set to always mode
# and if the website is just being turned on now.
sub chained_ssl
{
local ($d, $oldd) = @_;
if ($config{'ssl'} != 3) {
	# Not in auto mode, so don't touch
	return undef;
	}
elsif ($d->{'alias'}) {
	# Aliases never have their own SSL
	return undef;
	}
elsif (&domain_has_website($d)) {
	if (!$oldd || !&domain_has_website($oldd)) {
		# Turning on web, so turn on SSL
		return 1;
		}
	else {
		# Don't do anything
		return undef;
		}
	}
else {
	# Always off when web is
	return 0;
	}
}

# can_chained_ssl()
# Returns the web feature because the SSL feature will be enabled if a
# website is
sub can_chained_ssl
{
return ('web');
}

# write_ssl_file_contents(&domain, file, contents|srcfile)
# Write out an SSL key or cert file with the correct permissions
sub write_ssl_file_contents
{
my ($d, $file, $contents) = @_;
if ($contents =~ /^\// && -r $contents) {
	# Actually copy from a file
	$contents = &read_file_contents($contents);
	}
my $newfile = !-r $file;
if (&is_under_directory($d->{'home'}, $file)) {
	# Assume write can be done as the domain owner
	&disable_quotas($d);
	&open_tempfile_as_domain_user($d, KEY, ">$file");
	&print_tempfile(KEY, $contents);
	&close_tempfile_as_domain_user($d, KEY);
	&set_certificate_permissions($d, $file) if ($newfile);
	&enable_quotas($d);
	}
else {
	# If SSL cert is elsewhere (like /etc/ssl), write as root
	&open_tempfile(KEY, ">$file");
	&print_tempfile(KEY, $contents);
	&close_tempfile(KEY);
	&set_ownership_permissions(undef, undef, 0600, $file);
	}
}

$done_feature_script{'ssl'} = 1;

1;

