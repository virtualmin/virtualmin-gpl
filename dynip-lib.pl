# Functions for updating a dynamic IP address

# list_dynip_services()
# Returns a list of supported dynamic DNS services
sub list_dynip_services
{
return ( { 'name' => 'dyndns',
	   'desc' => $text{'dynip_dyndns'} },
	 { 'name' => 'webmin',
	   'desc' => $text{'dynip_webmin'} },
	 { 'name' => 'none',
	   'desc' => $text{'dynip_none'} },
	 { 'name' => 'external',
	   'desc' => $text{'dynip_external'},
	   'external' => 1, },
       );
}

# get_last_dynip_update(service)
# Returns the IP last sent to this dynamic DNS service, and when it was
# sent (if called in an array context)
sub get_last_dynip_update
{
local ($service) = @_;
local $file = "$module_config_directory/dynip.$service";
local $ip = &read_file_contents($file);
$ip =~ s/\r|\n//g;
local @st = stat($file);
return wantarray ? ( $ip, $st[9] ) : $ip;
}

# set_last_dynip_update(service, ip)
# Stores the IP that was successfully sent to the dynamic DNS service
sub set_last_dynip_update
{
local ($service, $ip) = @_;
local $file = "$module_config_directory/dynip.$service";
if ($ip) {
	&open_tempfile(DYNIP, ">$file");
	&print_tempfile(DYNIP, $ip,"\n");
	&close_tempfile(DYNIP);
	}
else {
	&unlink_file($file);
	}
}

# get_external_ip_address([no-cache], [type])
# Returns the IP address of this system, as seen by other hosts on the Internet.
# If the no-cache flag is set, the IP is always fetched from the network. If the
# type is set to 6 ("ipv6"), an IPv6 address is returned. Default is 4 (IPv4).
# For DNS resolver to work, the config option "dns_resolver" must be set to a
# string like "myip.opendns.com resolver1.opendns.com".
sub get_external_ip_address
{
my ($nocache, $type) = @_;
my ($out, $error);
my $timeout = 5;
# Validate type
$type = 4 if (!$type || ($type != 4 && $type != 6));
# Internal sub to validate an IP address of the correct type
my $ip = sub {
	my $ipaddr = shift;
	return undef if (!$ipaddr);
	$ipaddr =~ s/\r|\n//g;
	return $ipaddr if ($type == 4 && &check_ipaddress($ipaddr));
	return $ipaddr if ($type == 6 && &check_ip6address($ipaddr));
	return undef;
	};
my $now = time();
my $cache_optname = $type == 4 ?
	'external_ip_cache' : 'external_ipv6_cache';
my $cache_time_optname = $cache_optname.'_time';
$nocache = 1 if ($config{"no_$cache_optname"});
if (!$nocache && $config{$cache_optname} &&
    $now - $config{$cache_time_optname} < 24*60*60) {
	# Can use last cached value
	my $ipaddr = $ip->($config{$cache_optname});
	return $ipaddr if ($ipaddr);
	}
# Fetch IP using DNS
if ((my $dig = &has_command("dig")) &&
    $config{'dns_resolver'} =~ /^(?<qname>\S+)\s+(?<nserv>\S+)$/) {
	my $qname = quotemeta($+{qname});
	my $nserv    = quotemeta($+{nserv});
	my $dig_cmd = "$dig +time=$timeout +short -".($type == 6 ? "6" : "4").
		      " $qname \@" . $nserv;
	&execute_command($dig_cmd, undef, \$out, \$error);
	$out = $ip->($out);
	}
# Fetch IP using http
if ($error || !$out) {
	my $url = $config{'ip_lookup_url'} || 
		"http://software.virtualmin.com/cgi-bin/ip.cgi";
	my $url4 = $url;
	my $url6 = $url;
	($url4, $url6) = split(/ /, $url) if ($url =~ / /);
	$url = $type == 4 ? $url4 : $url6;
	my ($host, $port, $page, $ssl) = &parse_http_url($url);
	&http_download($host, $port, $page, \$out, \$error, undef, $ssl,
		undef, undef, $timeout, 0, 1);
	$out = $ip->($out);
	}
if ($error) {
	# Fall back to last cached value
	return $ip->($config{$cache_optname});
	}
# Cache it for future calls
&lock_file($module_config_file);
$config{$cache_optname} = $out;
$config{$cache_time_optname} = $now;
&save_module_config();
&unlock_file($module_config_file);
return $out;
}

# get_any_external_ip_address([no-cache], [prefer-ip-type])
# Returns the IP address of this system, as seen by other hosts on the Internet,
# either IPv4 or IPv6, preferring IPv4 by default.
sub get_any_external_ip_address
{
my ($nocache, $prefer) = shift;
my $ip4 = &get_external_ip_address($nocache, 4) if (!$prefer || $prefer != 6);
my $ip6 = &get_external_ip_address($nocache, 6) if (!$prefer || $prefer != 4);
return $prefer == 4 ? $ip4 : $ip6 || $ip4;
}

# get_any_external_ip_address_cached()
# Returns the cached IP address of this system unless caching is disabled.
sub get_any_external_ip_address_cached
{
my ($ip4txt, $ip6txt) = ('external_ip_cache', 'external_ipv6_cache');
return $config{$ip4txt} if ($config{$ip4txt} && !$config{"no_$ip4txt"});
return $config{$ip6txt} if ($config{$ip6txt} && !$config{"no_$ip6txt"});
return undef;
}

# update_dynip_service(new-ip, old-ip)
# Talk to the configured dynamic DNS service, and return the set IP address
# and an error message (if any)
sub update_dynip_service
{
my ($ip, $oldip) = @_;
if ($config{'dynip_service'} eq 'dyndns') {
	# Update DynDNS
	my $host = "members.dyndns.org";
	my $port = 443;
	my $page = "/nic/update?".
		      "system=dyndns&".
		      "hostname=".&urlize($config{'dynip_host'})."&".
		      "myip=$ip&".
		      "wildcard=NOCHG&".
		      "mx=NOCHG&".
		      "backmx=NOCHG";
	my ($out, $error);
	&http_download($host, $port, $page, \$out, \$error, undef, 0,
		       $config{'dynip_user'},
		       $config{'dynip_pass'},
		       10, 0, 1);
	if ($error =~ /401/) {
		return (undef, "Invalid login or password");
		}
	elsif ($error) {
		return (undef, $error);
		}
	elsif ($out =~ /^(good|nochg)\s+(\S+)/) {
		return ($2, undef);
		}
	elsif ($out =~ /^nohost/) {
		return (undef, "Invalid hostname");
		}
	else {
		return (undef, $out);
		}
	}
elsif ($config{'dynip_service'} eq 'webmin') {
	# Call the Virtualmin remote API
	my ($out, $error);
	my ($host, $dom) = split(/\./, $config{'dynip_host'}, 2);
	my ($whost, $wport) = split(/:/, $config{'dynip_external'});
	$wport ||= 10000;
	&http_download($whost, $wport,
		       "/virtual-server/remote.cgi?program=modify-dns&".
		       "domain=".&urlize($dom)."&".
		       "update-record=".&urlize("$host A\n$host A $newip"),
		       \$out, \$error, undef, 1,
		       $config{'dynip_user'},
		       $config{'dynip_pass'},
		       10, 0, 1);
	if ($error =~ /401/) {
		return (undef, "Invalid login or password");
		}
	elsif ($error) {
		return (undef, $error);
		}
	elsif ($out =~ /does not exist/i) {
		return (undef, "Invalid hostname");
		}
	elsif ($out =~ /Exit\s+status:\s+0/i) {
		return ($newip, undef);
		}
	else {
		return (undef, $out);
		}

	}
elsif ($config{'dynip_service'} eq 'external') {
	# Just run an external script with the IP and hostname as args
	my $cmd = $config{'dynip_external'}." ".quotemeta($ip).
		  " ".quotemeta($config{'dynip_host'}).
		  " ".quotemeta($oldip);
	my $out = &backquote_logged("$cmd 2>&1 </dev/null");
	if ($?) {
		return (undef, "$cmd failed : $out");
		}
	else {
		return ($ip, undef);
		}
	}
elsif ($config{'dynip_service'} eq 'none') {
	# Assume that nothing needs to be run
	return ($ip, undef);
	}
else {
	return (undef, "Unknown dynamic IP service $config{'dynip_service'}");
	}
}

# update_all_domain_ip_addresses(oldip, newip)
# Update any virtual servers using some old IP to the new one. May print stuff.
sub update_all_domain_ip_addresses
{
local ($ip, $oldip) = @_;
local $dc = 0;
foreach my $d (&list_domains()) {
	if (($d->{'ip'} eq $oldip ||
	     $d->{'dns_ip'} eq $oldip) && !$d->{'virt'}) {
		# Need to fix this server ..

		# Update the object
		local $oldd = { %$d };
		$d->{'ip'} = $ip if ($d->{'ip'} eq $oldip);
		$d->{'dns_ip'} = $ip if ($d->{'dns_ip'} eq $oldip);

		# Run the before command
		&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
		$merr = &making_changes();
		&reset_domain_envs(\%oldd);
		&error(&text('save_emaking', "<tt>$merr</tt>"))
			if (defined($merr));

		# Update all features
		foreach my $f (@features) {
			local $mfunc = "modify_$f";
			if ($config{$f} && $d->{$f}) {
				&try_function($f, $mfunc, $d, $oldd);
				}
			}
		foreach my $f (&list_feature_plugins()) {
			if ($d->{$f}) {
				&plugin_call($f, "feature_modify", $d, $oldd);
				}
			}

		# Save new domain details
		&$first_print($text{'save_domain'});
		&save_domain($d);
		&$second_print($text{'setup_done'});

		# Run the after command
		&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
		local $merr = &made_changes();
		&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
			if (defined($merr));
		&reset_domain_envs($d);
		$dc++;
		}
	}
return $dc;
}

1;

