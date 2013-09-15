#!/usr/local/bin/perl
# Update the list of shared IP addresses

require './virtual-server-lib.pl';
&foreign_require("net", "net-lib.pl");
&error_setup($text{'sharedips_err'});
&can_edit_templates() || &error($text{'sharedips_ecannot'});
&ReadParse();

# Validate inputs, and check for clashes
$defip = &get_default_ip();
$defip6 = &get_default_ip6();
@ips = split(/\s+/, $in{'ips'});
@ip6s = split(/\s+/, $in{'ip6s'});
if (defined(&list_resellers)) {
	%rips = map { $_->{'acl'}->{'defip'}, $_ }
		    grep { $_->{'acl'}->{'defip'} } &list_resellers();
	}
@active = &active_ip_addresses();
foreach $ip (@ips) {
	&check_ipaddress($ip) || &error(&text('sharedips_eip', $ip));
	$ip ne $defip || &error(&text('sharedips_edef', $ip));
	$rips{$ip} && &error(&text('sharedips_erip',
				   $ip, $rips{$ip}->{'name'}));
	$d = &get_domain_by("ip", $ip, "virt", 1);
	$d && error(&text('sharedips_edom', $ip, $d->{'dom'}));
	@users = &get_domain_by("ip", $ip);
	&indexof($ip, @active) >= 0 || @users ||
		&error(&text('sharedips_eactive', $ip));
	}
foreach $ip6 (@ip6s) {
	&check_ip6address($ip6) || &error(&text('sharedips_eip6', $ip6));
	$ip6 ne $defip6 || &error(&text('sharedips_edef', $ip6));
	$rips{$ip} && &error(&text('sharedips_erip',
				   $ip, $rips{$ip}->{'name'}));
	$d = &get_domain_by("ip6", $ip6, "virt", 1);
	$d && error(&text('sharedips_edom', $ip6, $d->{'dom'}));
	@users = &get_domain_by("ip6", $ip6);
	&indexof($ip6, @active) >= 0 || @users ||
		&error(&text('sharedips_eactive', $ip6));
	}

# Check if one taken away was in use
@oldips = &list_shared_ips();
foreach $ip (@oldips) {
	if (&indexof($ip, @ips) < 0 && $ip ne $defip) {
		$d = &get_domain_by("ip", $ip);
		$d && &error(&text('sharedips_eaway', $ip, $d->{'dom'}));
		}
	}
@oldip6s = &list_shared_ip6s();
foreach $ip6 (@oldip6s) {
	if (&indexof($ip6, @ip6s) < 0 && $ip6 ne $defip6) {
		$d = &get_domain_by("i6p", $ip6);
		$d && &error(&text('sharedips_eaway', $ip6, $d->{'dom'}));
		}
	}

# If requested, allocate a new one and bring it up
if ($in{'alloc'}) {
	&obtain_lock_virt();
	$tmpl = &get_template(&get_init_template(0));
	($newip, $newnetmask) = &free_ip_address($tmpl);
	$newip || &error(&text('sharedips_ealloc', $tmpl->{'ranges'}));
	$err = &activate_shared_ip($newip, $newnetmask);
	&error($err) if ($err);
	push(@ips, $newip);
	&release_lock_virt();
	}

# Save them
&lock_file($module_config_file);
&save_shared_ips(@ips);
&save_shared_ip6s(@ip6s);
&unlock_file($module_config_file);

&run_post_actions_silently();
&webmin_log("sharedips");
&redirect("");

