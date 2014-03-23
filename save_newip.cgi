#!/usr/local/bin/perl
# Update the IP for one server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$tmpl = &get_template($d->{'template'});
&can_change_ip($d) && &can_edit_domain($d) || &error($text{'newip_ecannot'});

if ($in{'convert'}) {
	# Special mode - adding a new shared IP
	$oldd = { %$d };
	($d->{'virt'} || $d->{'virt6'}) && &can_edit_templates() ||
		&error($text{'newip_ecannot'});

	# Turn off virt mode for the domain
	if ($d->{'virt'}) {
		$d->{'virt'} = 0;
		$d->{'name'} = 1;
		}
	if ($d->{'virt6'}) {
		$d->{'virt6'} = 0;
		$d->{'name6'} = 1;
		}
	&set_domain_envs($d, "MODIFY_DOMAIN", $d);
	$merr = &making_changes();
	&error($merr) if ($merr);
	&reset_domain_envs($d);
	&save_domain($d);
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
	&made_changes();
	&reset_domain_envs($d);

	# Add to shared IPs list
	&lock_file($module_config_file);
	if ($oldd->{'virt'}) {
		@ips = &list_shared_ips();
		@ips = &unique(@ips, $d->{'ip'});
		&save_shared_ips(@ips);
		}
	if ($oldd->{'virt6'}) {
		@ips = &list_shared_ip6s();
		@ips = &unique(@ips, $d->{'ip6'});
		&save_shared_ip6s(@ips);
		}
	&unlock_file($module_config_file);

	&webmin_log("newipshared", "domain", $d->{'dom'}, $d);
	&redirect("newip_form.cgi?dom=$d->{'id'}");
	return;
	}

# Validate inputs
&error_setup($text{'newip_err'});
@r = split(/\s+/, $d->{'reseller'});
%racl = @r ? &get_reseller_acl($r[0]) : ();
if (!&can_use_feature("virt")) {
	# Cannot change anything, so no validation needed
	}
elsif ($in{'mode'} == 0 || $config{'all_namevirtual'}) {
	# Switching to shared address
	$ip = $in{'ip'};
	&check_ipaddress($ip) || &error($text{'setup_eip'});
	$virt = 0;
	}
elsif ($in{'mode'} == 1) {
	# Sticking with private IP
	$ip = $d->{'ip'};
	$virtalready = $d->{'virtalready'};
	$virt = 1;
	}
elsif ($in{'mode'} == 2) {
	# Allocate a new IP
	if ($racl{'ranges'}) {
		# Try allocating IP from reseller's range
		($ip, $netmask) = &free_ip_address(\%racl);
		$ip || &error(&text('setup_evirtalloc2'));
		}
	elsif ($tmpl->{'ranges'} ne "none") {
		# Try allocating IP from template range
		($ip, $netmask) = &free_ip_address($tmpl);
		$ip || &error(&text('setup_evirtalloc'));
		}
	else {
		&error(&text('setup_evirtalloc3'));
		}
	$virt = 1;
	$virtalready = 0;
	}
elsif ($in{'mode'} == 3) {
	# Validate manually entered IP
	$ip = $in{'virt'};
	$virtalready = $in{'virtalready'};
	&check_ipaddress($ip) ||
		&error($text{'setup_eip'});
	$clash = &check_virt_clash($ip);
	if (!$virtalready) {
		# Make sure the IP isn't assigned yet
		$clash && &error(&text('setup_evirtclash'));
		}
	elsif ($virtalready) {
		# Make sure the IP is assigned already, but
		# not to any domain
		$clash || &error(&text('setup_evirtclash2', $ip));
		$already = &get_domain_by("ip", $ip);
		$already && &error(&text('setup_evirtclash4',
					 $already->{'dom'}));
		}
	$virt = 1;
	}

if (!&supports_ip6() || !&can_use_feature("virt6")) {
	# Cannot use or change IPv6, so no validation needed
	}
elsif ($in{'mode6'} == -2) {
	# Turning off IPv6 address
	$virt6 = 0;
	$ip6 = undef;
	}
elsif ($in{'mode6'} == 0) {
	# Switching to shared address
	$ip6 = $in{'ip6'};
	&check_ip6address($ip6) || &error($text{'setup_eip'});
	$virt6 = 0;
	}
elsif ($in{'mode6'} == 1) {
	# Sticking with private IP
	$ip6 = $d->{'ip6'};
	$virtalready6 = $d->{'virtalready6'};
	$virt6 = 1;
	}
elsif ($in{'mode6'} == 2) {
	# Allocate a new IP
	if ($racl{'ranges6'}) {
		# Try allocating IPv6 address from reseller's range
		($ip6, $netmask6) = &free_ip6_address(\%racl);
		$ip6 || &error(&text('setup_evirt6alloc2'));
		}
	elsif ($tmpl->{'ranges6'} ne "none") {
		# Try allocating IP from template range
		($ip6, $netmask6) = &free_ip6_address($tmpl);
		$ip6 || &error(&text('setup_evirt6alloc'));
		}
	else {
		&error(&text('setup_evirt6alloc3'));
		}
	$virt6 = 1;
	$virtalready6 = 0;
	}
elsif ($in{'mode6'} == 3) {
	# Validate manually entered IP
	$ip6 = $in{'virt6'};
	$virtalready6 = $in{'virtalready6'};
	&check_ip6address($ip6) ||
		&error($text{'setup_eip6'});
	$clash = &check_virt6_clash($ip6);
	if (!$virtalready6) {
		# Make sure the IPv6 address isn't assigned yet
		$clash && &error(&text('setup_evirt6clash'));
		}
	elsif ($virtalready6) {
		# Make sure the IP is assigned already, but
		# not to any domain
		$clash || &error(&text('setup_evirt6clash2', $ip6));
		$already = &get_domain_by("ip6", $ip6);
		$already && &error(&text('setup_evirt6clash4',
					 $already->{'dom'}));
		}
	$virt6 = 1;
	}

if (&domain_has_website($d)) {
	# Changing webserver port
	foreach $p ("port", "sslport") {
		$in{$p} =~ /^\d+$/ && $in{$p} > 0 && $in{$p} < 65536 ||
			&error($text{'newip_e'.$p});
		$in{"url".$p."_def"} || $in{"url".$p} =~ /^\d+$/ ||
			&error($text{'newip_e'.$p});
		}
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'newip_title'}, "");

# Update domain object for IP change
$oldd = { %$d };
if (!&can_use_feature("virt")) {
	# Cannot change anything, so do nothing
	}
elsif ($config{'all_namevirtual'}) {
	# Can only set IP
	$d->{'ip'} = $ip;
	}
elsif ($virt && !$d->{'virt'}) {
	# Bringing up IP
	$d->{'ip'} = $ip;
	$d->{'netmask'} = $netmask;
	$d->{'virt'} = 1;
	$d->{'name'} = 0;
	$d->{'virtalready'} = $virtalready;
	delete($d->{'dns_ip'});
	delete($d->{'defip'});
	}
elsif (!$virt && $d->{'virt'}) {
	# Taking down private IP
	$d->{'ip'} = $ip;
	$d->{'netmask'} = undef;
	$d->{'defip'} = $ip eq &get_default_ip();
	$d->{'virt'} = 0;
	$d->{'virtalready'} = 0;
	$d->{'name'} = 1;
	delete($d->{'dns_ip'});
	}
elsif (!$virt && !$d->{'virt'} && $d->{'ip'} ne $ip) {
	# Changing shared IP
	$d->{'ip'} = $ip;
	}
elsif ($virt && $d->{'virt'} && $d->{'ip'} ne $ip) {
	# Changing private IP
	$d->{'ip'} = $ip;
	$d->{'netmask'} = $netmask;
	$d->{'virtalready'} = $virtalready;
	}

# Update for IPv6 change
if (!&supports_ip6() || !&can_use_feature("virt6")) {
	# Not allowed
	}
elsif ($virt6 && !$d->{'virt6'}) {
	# Bringing up IPv6 interface
	$d->{'ip6'} = $ip6;
	$d->{'netmask6'} = $netmask6;
	$d->{'virt6'} = 1;
	$d->{'name6'} = 0;
	$d->{'virt6already'} = $virt6already;
	}
elsif (!$virt6 && $d->{'virt6'}) {
	# Taking down IPv6 interface, revert to shared
	$d->{'ip6'} = $ip6;
	$d->{'netmask6'} = undef;
	$d->{'virt6'} = 0;
	$d->{'name6'} = 1;
	$d->{'virt6already'} = 0;
	}
elsif (!$virt6 && !$d->{'virt6'} && $d->{'ip6'} ne $ip6) {
	# Changing shared IPv6 address
	$d->{'ip6'} = $ip6;
	}
elsif ($virt6 && $d->{'virt6'} && $d->{'ip6'} ne $ip6) {
	# Changing private IPv6 address
	$d->{'ip6'} = $ip6;
	$d->{'netmask6'} = $netmask6;
	$d->{'virtalready6'} = $virtalready6;
	}

# Update for web ports
if (&domain_has_website($d)) {
	$d->{'web_port'} = $in{'port'};
	$d->{'web_sslport'} = $in{'sslport'};
	$d->{'web_urlport'} =
		$in{'urlport_def'} ? undef : $in{'urlport'};
	$d->{'web_urlsslport'} =
		$in{'urlsslport_def'} ? undef : $in{'urlsslport'};
	}

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($d);
&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Update the primary domain
&$first_print(&text($ip6 ? 'newip_dom6' : 'newip_dom', $d->{'dom'}, $ip, $ip6));
&$indent_print();

if ($d->{'virt'} && !$oldd->{'virt'}) {
	# Bring up IP
	&setup_virt($d);
	}
elsif (!$d->{'virt'} && $oldd->{'virt'}) {
	# Take down IP
	&delete_virt($oldd);
	}
elsif ($d->{'virt'} && $oldd->{'virt'}) {
	# Change IP, if needed
	&modify_virt($d, $oldd);
	}

if ($d->{'virt6'} && !$oldd->{'virt6'}) {
	# Bring up IPv6
	&setup_virt6($d);
	}
elsif (!$d->{'virt6'} && $oldd->{'virt6'}) {
	# Take down IPv6
	&delete_virt6($oldd);
	}
elsif ($d->{'virt6'} && $oldd->{'virt6'}) {
	# Change IPv6, if needed
	&modify_virt6($d, $oldd);
	}

# Update features and plugins
foreach $f (@features) {
	local $mfunc = "modify_$f";
	if ($config{$f} && $d->{$f}) {
		&try_function($f, $mfunc, $d, $oldd);
		}
	}
foreach $f (&list_feature_plugins()) {
	if ($d->{$f}) {
		&try_plugin_call($f, "feature_modify", $d, $oldd);
		}
	}

# Save new domain details
print $text{'save_domain'},"<br>\n";
&save_domain($d);
print $text{'setup_done'},"<p>\n";

&$outdent_print();

# Get and update all alias domains
@doms = &get_domain_by("alias", $d->{'id'});
foreach $sd (@doms) {
	&$first_print(&text('newip_dom2', $sd->{'dom'}, $d->{'ip'}));
	&$indent_print();
	$oldsd = { %$sd };

	# Alias domain IP follows target
	$sd->{'ip'} = $d->{'ip'};
	$sd->{'defip'} = $sd->{'ip'} eq &get_default_ip();
	if ($d->{'virt6'} && &supports_ip6()) {
		$sd->{'ip6'} = $d->{'ip6'};
		}
	if (&domain_has_website($sd)) {
		$sd->{'web_port'} = $in{'port'};
		$sd->{'web_sslport'} = $in{'sslport'};
		}

	foreach $f (@features) {
		local $mfunc = "modify_$f";
		if ($config{$f} && $sd->{$f}) {
			&try_function($f, $mfunc, $sd, $oldsd);
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($sd->{$f}) {
			&try_plugin_call($f, "feature_modify", $sd, $oldsd);
			}
		}
	if ($sd->{'virt6'} && &supports_ip6()) {
		&try_function("virt6", "modify_virt6", $sd, $oldsd);
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	&save_domain($sd);
	print $text{'setup_done'},"<p>\n";
	&$outdent_print();
	}

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);
&webmin_log("newip", "domain", $d->{'dom'}, $d);

&ui_print_footer(&domain_footer_link($d));
