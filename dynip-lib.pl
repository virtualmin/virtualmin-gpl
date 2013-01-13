# Functions for updating a dynamic IP address

# list_dynip_services()
# Returns a list of supported dynamic DNS services
sub list_dynip_services
{
return ( { 'name' => 'dyndns',
	   'desc' => $text{'dynip_dyndns'} },
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

# get_external_ip_address()
# Returns the IP address of this system, as seen by other hosts on the Internet.
sub get_external_ip_address
{
local $url = "http://software.virtualmin.com/cgi-bin/ip.cgi";
local ($host, $port, $page, $ssl) = &parse_http_url($url);
local ($out, $error);
&http_download($host, $port, $page, \$out, \$error, undef, $ssl,
	       undef, undef, 5, 0, 1);
$out =~ s/\r|\n//g;
return $error ? undef : $out;
}

# update_dynip_service()
# Talk to the configured dynamic DNS service, and return the set IP address
# and an error message (if any)
sub update_dynip_service
{
local $ip = $config{'dynip_auto'} ? &get_external_ip_address()
				  : &get_default_ip();
if ($config{'dynip_service'} eq 'dyndns') {
	# Update DynDNS
	local $host = "members.dyndns.org";
	local $port = 80;
	local $page = "/nic/update?".
		      "system=dyndns&".
		      "hostname=".&urlize($config{'dynip_host'})."&".
		      "myip=$ip&".
		      "wildcard=NOCHG&".
		      "mx=NOCHG&".
		      "backmx=NOCHG";
	local ($out, $error);
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

