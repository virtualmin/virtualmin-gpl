#!/usr/local/bin/perl
# Update the list of shared IP addresses

require './virtual-server-lib.pl';
&foreign_require("net", "net-lib.pl");
&error_setup($text{'sharedips_err'});
&can_edit_templates() || &error($text{'sharedips_ecannot'});
&ReadParse();

# Validate inputs, and check for clashes
$defip = &get_default_ip();
@ips = split(/\s+/, $in{'ips'});
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

# Check if one taken away was in use
@oldips = &list_shared_ips();
foreach $ip (@oldips) {
	if (&indexof($ip, @ips) < 0 && $ip ne $defip) {
		$d = &get_domain_by("ip", $ip);
		$d && &error(&text('sharedips_eaway', $ip, $d->{'dom'}));
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
&unlock_file($module_config_file);

&webmin_log("sharedips");
&redirect("");

