# Functions for IPv6 address management

# Returns 1 if this system supports IPv6 addresses. Currently only true on
# Linux where the ifconfig command reports v6 addresses
sub supports_ip6
{
if (!defined($supports_ip6_cache)) {
	if ($gconfig{'os_type'} =~ /^(debian|redhat)-linux$/) {
		local $out = &backquote_command(
			"LC_ALL='' LANG='' ifconfig -a");
		$supports_ip6_cache = $out =~ /inet6 addr:/ ? 1 : 0;
		}
	else {
		$supports_ip6_cache = 0;
		}
	}
return $supports_ip6_cache;
}

# setup_virt6(&domain)
# Adds an IPv6 address to the system for a domain
sub setup_virt6
{
local ($d) = @_;
&obtain_lock_virt($d);
if (!$d->{'virtalready'}) {
	# Save and bring up the IPv6 interface
	&$first_print(&text('setup_virt6', $d->{'ip6'}));
	local $virt = { 'name' => $config{'iface6'} || $config{'iface'},
		        'netmask' => $config{'netmask6'} || 64,
			'address' => $d->{'ip6'} };
	&save_ip6_interface($virt);
	&activate_ip6_interface($virt);
	&$second_print(&text('setup_virt6done', $virt->{'name'}));
	}
&release_lock_virt($d);
}

# modify_virt6(&domain, &old-domain)
# Changes the IPv6 address for a domain, if needed
sub modify_virt6
{
local ($d, $oldd) = @_;
if ($d->{'ip6'} ne $oldd->{'ip6'} && !$d->{'virtalready'}) {
	# Remove and re-add the IPv6 interface
	&delete_virt6($oldd);
	&setup_virt6($d);
	}
}

# delete_virt6(&domain)
# Removes the IPv6 interface for a domain
sub delete_virt6
{
local ($d) = @_;
&obtain_lock_virt($d);
if (!$d->{'virtalready'}) {
	# Bring down and delete the IPv6 interface
	&$first_print(&text('delete_virt6', $d->{'ip6'}));
	local ($active) = grep { $_->{'address'} eq $d->{'ip6'} }
			       &active_ip6_interfaces();
	local ($boot) = grep { $_->{'address'} eq $d->{'ip6'} }
			     &boot_ip6_interfaces();
	&deactivate_ip6_interface($active) if ($active);
	&delete_ip6_interface($boot) if ($boot);
	local $any = $active || $boot;
	if ($any) {
		&$second_print(&text('delete_virt6done', $any->{'name'}));
		}
	else {
		&$second_print(&text('delete_noiface', $d->{'ip6'}));
		}
	}
&release_lock_virt($d);
}

# check_virt6_clash(ip)
# Returns 1 if some IPv6 is already in use, 0 if not
sub check_virt6_clash
{
local ($ip6) = @_;

# Check interfaces
foreach my $i (&active_ip6_interfaces(), &boot_ip6_interfaces()) {
	return 1 if ($i->{'address'} eq $ip6);
	}

# Do a quick ping test
if (&has_command("ping6")) {
	local $pingcmd = "ping6 -c 1 -t 1";
	local ($out, $timed_out) = &backquote_with_timeout(
					$pingcmd." ".$ip6." 2>&1", 2, 1);
	return 1 if (!$timed_out && !$?);
	}

return 0;
}

# active_ip6_interfaces()
# Returns a list of IPv6 addresses currently active
sub active_ip6_interfaces
{
local @rv;
local $out = &backquote_command("ifconfig -a 2>/dev/null");
local $ifacename;
foreach my $l (split(/\r?\n/, $out)) {
	if ($l =~ /^(\S+)/) {
		# Start of a new interface
		$ifacename = $1;
		}
	if ($l =~ /inet6\s+addr:\s+(\S+)\/(\d+)/i && $ifacename) {
		# Found an IPv6 address
		push(@rv, { 'name' => $ifacename,
			    'address' => $1,
			    'netmask' => $2 });
		}
	}
return @rv;
}

# boot_ip6_interfaces()
# Returns a list of IPv6 addresses activated at boot
sub boot_ip6_interfaces
{
# XXX Debian and Redhat
local @rv;
return @rv;
}

# activate_ip6_interface(&iface)
# Activate an IPv6 address right now. Calls error on failure.
sub activate_ip6_interface
{
local ($iface) = @_;
local $cmd = "ifconfig ".quotemeta($iface->{'name'})." inet6 add ".
	     quotemeta($iface->{'address'})."/".$iface->{'netmask'};
local $out = &backquote_logged("$cmd 2>&1 </dev/null");
&error("<tt>".&html_escape($cmd)."</tt> failed : ".
       "<tt>".&html_escape($out)."</tt>") if ($?);
return undef;
}

# save_ip6_interface(&iface)
# Record an IPv6 address for activation at boot time
sub save_ip6_interface
{
local ($iface) = @_;
# XXX
}

# deactivate_ip6_interface(&iface)
# Removes an IPv6 address that is currently active. Calls error on failure.
sub deactivate_ip6_interface
{
local ($iface) = @_;
local $cmd = "ifconfig ".quotemeta($iface->{'name'})." inet6 del ".
	     quotemeta($iface->{'address'})."/".$iface->{'netmask'};
local $out = &backquote_logged("$cmd 2>&1 </dev/null");
&error("<tt>".&html_escape($cmd)."</tt> failed : ".
       "<tt>".&html_escape($out)."</tt>") if ($?);
return undef;
}

# delete_ip6_interface(&iface)
# Removes an IPv6 address that is activated at boot time
sub delete_ip6_interface
{
local ($iface) = @_;
# XXX
}

1;

