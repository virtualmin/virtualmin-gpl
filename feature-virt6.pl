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
if (!$d->{'virt6already'}) {
	# Save and bring up the IPv6 interface
	&$first_print(&text('setup_virt6', $d->{'ip6'}));
	local $virt = { 'name' => $config{'iface6'} || $config{'iface'},
		        'netmask' => $d->{'netmask6'} ||
				     $config{'netmask6'} || 64,
			'address' => $d->{'ip6'} };
	&save_ip6_interface($virt);
	&activate_ip6_interface($virt);
	$d->{'iface6'} = $virt->{'name'};
	&$second_print(&text('setup_virt6done', $virt->{'name'}));
	}
&release_lock_virt($d);

# Add IPv6 reverse entry, if possible
if ($config{'dns'} && !$d->{'provision_dns'}) {
	&require_bind();
	local $ip6 = $d->{'ip6'};
	local ($revconf, $revfile, $revrec) = &bind8::find_reverse($ip6);
	if ($revconf && $revfile && !$revrec) {
		&lock_file(&bind8::make_chroot($revfile));
		&bind8::create_record($revfile,
			&bind8::net_to_ip6int($d->{'ip6'}),
			undef, "IN", "PTR", $d->{'dom'}.".");
		local @rrecs = &bind8::read_zone_file(
			$revfile, $revconf->{'name'});
		&bind8::bump_soa_record($revfile, \@rrecs);
		&unlock_file(&bind8::make_chroot($revfile));
		&register_post_action(\&restart_bind);
		}
	}

return 1;
}

# modify_virt6(&domain, &old-domain)
# Changes the IPv6 address for a domain, if needed
sub modify_virt6
{
local ($d, $oldd) = @_;
if ($d->{'ip6'} ne $oldd->{'ip6'} && !$d->{'virt6already'}) {
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
if (!$d->{'virt6already'}) {
	# Bring down and delete the IPv6 interface
	&$first_print(&text('delete_virt6', $d->{'ip6'}));
	local ($active) = grep { &canonicalize_ip6($_->{'address'}) eq
				 &canonicalize_ip6($d->{'ip6'}) }
			       &active_ip6_interfaces();
	local ($boot) = grep { &canonicalize_ip6($_->{'address'}) eq
			       &canonicalize_ip6($d->{'ip6'}) }
			     &boot_ip6_interfaces();
	&deactivate_ip6_interface($active) if ($active);
	&delete_ip6_interface($boot) if ($boot);
	local $any = $active || $boot;
	if ($any) {
		&$second_print(&text('delete_virt6done', $any->{'name'}));
		}
	else {
		&$second_print(&text('delete_noiface6', $d->{'ip6'}));
		}
	}
&release_lock_virt($d);

# Remove IPv6 reverse address, if defined
if ($config{'dns'} && !$d->{'provision_dns'}) {
	&require_bind();
	local $ip6 = $d->{'ip6'};
	local ($revconf, $revfile, $revrec) = &bind8::find_reverse($ip6);
	if ($revconf && $revfile && $revrec &&
	    $revrec->{'values'}->[0] eq $d->{'dom'}.".") {
		&lock_file(&bind8::make_chroot($revrec->{'file'}));
		&bind8::delete_record($revfile, $revrec);
		&unlock_file(&bind8::make_chroot($revrec->{'file'}));
		&register_post_action(\&restart_bind);
		}
	}
}

# clone_virt6(&domain, &old-domain)
# No need to do anything here, as an IP address doesn't have any settings that
# need copying
sub clone_virt6
{
return 1;
}

# validate_virt6(&domain)
# Check for boot-time and active IP6 network interfaces
sub validate_virt6
{
local ($d) = @_;
if (!$_[0]->{'virt6already'}) {
	# Only check boot-time interface if added by Virtualmin
	local @boots = map { &canonicalize_ip6($_) } &bootup_ip_addresses();
	if (&indexoflc(&canonicalize_ip6($d->{'ip6'}), @boots) < 0) {
		return &text('validate_evirt6b', $d->{'ip6'});
		}
	}
local @acts = map { &canonicalize_ip6($_) } &active_ip_addresses();
if (&indexoflc(&canonicalize_ip6($d->{'ip6'}), @acts) < 0) {
	return &text('validate_evirt6a', $d->{'ip6'});
	}
return undef;
}

# check_virt6_clash(ip)
# Returns 1 if some IPv6 is already in use, 0 if not
sub check_virt6_clash
{
local ($ip6) = @_;

# Check interfaces
foreach my $i (&active_ip6_interfaces(), &boot_ip6_interfaces()) {
	return 1 if (&canonicalize_ip6($i->{'address'}) eq
		     &canonicalize_ip6($ip6));
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
local @rv;
&foreign_require("net", "net-lib.pl");
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Read /etc/network/interfaces for inet6 blocks
	local @defs = &net::get_interface_defs();
	foreach my $i (grep { $_->[1] eq 'inet6' } @defs) {
		foreach my $o (@{$i->[3]}) {
			if ($o->[0] eq 'address') {
				# Primary address
				local ($mask) = grep { $_->[0] eq 'netmask' }
						     @{$i->[3]};
				push(@rv, { 'name' => $i->[0],
					    'address' => $o->[1],
					    'netmask' => $mask ? $mask->[1]
							       : 64 });
				}
			elsif ($o->[0] eq 'up' &&
			       $o->[1] =~ /ifconfig\s+(\S+)\s+inet6\s+add\s+([a-f0-9:]+)\/(\d+)/ &&
			       $1 eq $i->[0]) {
				# Extra address
				push(@rv, { 'name' => $i->[0],
					    'address' => $2,
					    'netmask' => $3 });
				}
			}
		}
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Read ifcfg-* files for IPV6ADDR and IPV6ADDR_SECONDARIES
	foreach my $b (grep { $_->{'virtual'} eq '' } &net::boot_interfaces()) {
		local %conf;
		&read_env_file($b->{'file'}, \%conf);
		foreach my $a ($conf{'IPV6ADDR'},
			       split(/\s+/, $conf{'IPV6ADDR_SECONDARIES'})) {
			local ($addr, $mask) = split(/\//, $a);
			if ($addr) {
				$mask ||= $config{'netmask6'} || 64;
				push(@rv, { 'name' => $b->{'name'},
					    'address' => $addr,
					    'netmask' => $mask });
				}
			}
		}
	}
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
&foreign_require("net", "net-lib.pl");
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Add to inet6 block in /etc/network/interfaces
	local @defs = &net::get_interface_defs();
	local ($boot) = grep { $_->[1] eq 'inet6' &&
			       $_->[0] eq $iface->{'name'} } @defs;
	local $ifconfig = &has_command("ifconfig");
	if ($boot) {
		# Add extra IP to this interface
		push(@{$boot->[3]},
		     [ "up", "$ifconfig $iface->{'name'} inet6 add ".
			     "$iface->{'address'}/$iface->{'netmask'}" ]);
		&net::modify_interface_def($boot->[0], $boot->[1],
					   $boot->[2], $boot->[3], 0);
		}
	else {
		# Need to add a new interface
		&net::new_interface_def($iface->{'name'}, "inet6", "static",
					[ [ "address", $iface->{'address'} ],
					  [ "netmask", $iface->{'netmask'} ],
					  [ "post-up", "sleep 3" ] ]);
		}
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Add to ifcfg-* file in IPV6ADDR_SECONDARIES line
	local ($boot) = grep { $_->{'fullname'} eq $iface->{'name'} }
			     &net::boot_interfaces();
	$boot || &error("No interface file found for $iface->{'name'}");
	local %conf;
	&read_env_file($boot->{'file'}, \%conf);
	if (!$conf{'IPV6ADDR'}) {
		# Set primary IPv6 address
		$conf{'IPV6ADDR'} = $iface->{'address'}."/".$iface->{'netmask'};
		}
	else {
		# Append to secondary
		local @secs = split(/\s+/, $conf{'IPV6ADDR_SECONDARIES'});
		push(@secs, $iface->{'address'}."/".$iface->{'netmask'});
		$conf{'IPV6ADDR_SECONDARIES'} = join(" ", @secs);
		}
	$conf{'IPV6INIT'} = 'yes' if (lc($conf{'IPV6INIT'}) ne 'yes');
	&write_env_file($boot->{'file'}, \%conf);
	}
else {
	&error("Unsupported operating system for IPv6");
	}
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
&foreign_require("net", "net-lib.pl");
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Remove from inet6 block in /etc/network/interfaces
	local @defs = &net::get_interface_defs();
	local ($boot) = grep { $_->[1] eq 'inet6' &&
			       $_->[0] eq $iface->{'name'} } @defs;
	$boot || &error("No interface block found for $iface->{'name'}");
	local @opts;
	foreach my $o (@{$boot->[3]}) {
		if ($o->[0] ne 'up' || $o->[1] !~ /ifconfig\s+(\S+)\s+inet6\s+add\s+([a-f0-9:]+)\/(\d+)/ || $2 ne $iface->{'address'}) {
			push(@opts, $o);
			}
		if ($o->[0] eq 'address' &&
		    &canonicalize_ip6($o->[1]) eq
		     &canonicalize_ip6($iface->{'address'})) {
			&error("Not removing primary IPv6 interface");
			}
		}
	&net::modify_interface_def($boot->[0], $boot->[1],
				   $boot->[2], \@opts, 0);
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Remove from ifcfg-* file in IPV6ADDR_SECONDARIES line
	local ($boot) = grep { $_->{'fullname'} eq $iface->{'name'} }
			     &net::boot_interfaces();
	$boot || &error("No interface file found for $iface->{'name'}");
	local %conf;
	&read_env_file($boot->{'file'}, \%conf);
	local $full = $iface->{'address'}."/".$iface->{'netmask'};
	if (&canonicalize_ip6($conf{'IPV6ADDR'}) eq &canonicalize_ip6($full)) {
		&error("Not removing primary IPv6 interface");
		}
	local @secs = split(/\s+/, $conf{'IPV6ADDR_SECONDARIES'});
	@secs = grep { &canonicalize_ip6($_) ne &canonicalize_ip6($full) }
		     @secs;
	$conf{'IPV6ADDR_SECONDARIES'} = join(" ", @secs);
	&write_env_file($boot->{'file'}, \%conf);
	}
else {
	&error("Unsupported operating system for IPv6");
	}
}

# ip6_interfaces_file()
# Returns the file in which IPv6 interfaces are stored, for locking purposes,
# if it is separate from the primary interfaces file
sub ip6_interfaces_file
{
if ($gconfig{'os_type'} eq 'redhat-linux') {
	# On redhat, this is typically the ifcfg-eth0 file
	local $ifacename = $config{'iface6'} || $config{'iface'};
	local ($boot) = grep { $_->{'fullname'} eq $ifacename }
			     &net::boot_interfaces();
	return $boot->{'file'} if ($boot);
	}
return undef;
}

# canonicalize_ip6(address)
# Converts an address to its full long form. Ie. 2001:db8:0:f101::20 to
# 2001:0db8:0000:f101:0000:0000:0000:0020
sub canonicalize_ip6
{
my ($addr) = @_;
return $addr if (!&check_ip6address($addr));
my @w = split(/:/, $addr);
my $idx = &indexof("", @w);
if ($idx >= 0) {
	# Expand ::
	my $mis = 8 - scalar(@w);
	my @nw = @w[0..$idx];
	for(my $i=0; $i<$mis; $i++) {
		push(@nw, 0);
		}
	push(@nw, @w[$idx+1 .. $#w]);
	@w = @nw;
	}
foreach my $w (@w) {
	while(length($w) < 4) {
		$w = "0".$w;
		}
	}
return lc(join(":", @w));
}

1;

