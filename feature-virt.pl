# Functions for setting up a virtual IP interface

# setup_virt(&domain)
# Bring up an interface for a domain, if the IP isn't already enabled
sub setup_virt
{
&obtain_lock_virt($_[0]);
&foreign_require("net", "net-lib.pl");
local @boot = &net::active_interfaces();
if (!$_[0]->{'virtalready'}) {
	# Actually bring up
	&$first_print(&text('setup_virt', $_[0]->{'ip'}));
	local ($iface) = grep { $_->{'fullname'} eq $config{'iface'} } @boot;
	if (!$iface) {
		# Interface doesn't really exist!
		&$second_print(&text('setup_virtmissing', $config{'iface'}));
		return 0;
		}
	local $b;
	local $vmax = $config{'iface_base'} || int($net::min_virtual_number);
	foreach $b (@boot) {
		$vmax = $b->{'virtual'}
			if ($b->{'name'} eq $iface->{'name'} &&
			    $b->{'virtual'} > $vmax);
		}
	local $netmask = $_[0]->{'netmask'} || $net::virtual_netmask ||
			 $iface->{'netmask'};
	local $virt = { 'address' => $_[0]->{'ip'},
			'netmask' => $netmask,
			'broadcast' => &net::compute_broadcast($_[0]->{'ip'},
							       $netmask),
			'name' => $iface->{'name'},
			'virtual' => $vmax+1,
			'up' => 1,
			'desc' => "Virtualmin server $_[0]->{'dom'}",
		      };
	$virt->{'fullname'} = $virt->{'name'}.":".$virt->{'virtual'};
	&net::save_interface($virt);
	&net::activate_interface($virt);
	$_[0]->{'iface'} = $virt->{'fullname'};
	&$second_print(&text('setup_virtdone', $_[0]->{'iface'}));
	}
else {
	# Just guess the interface
	&$first_print(&text('setup_virt2', $_[0]->{'ip'}));
	local ($virt) = grep { $_->{'address'} eq $_[0]->{'ip'} } @boot;
	$_[0]->{'iface'} = $virt ? $virt->{'fullname'} : undef;
	if ($_[0]->{'iface'}) {
		&$second_print(&text('setup_virtdone2', $_[0]->{'iface'}));
		}
	else {
		&$second_print(&text('setup_virtnotdone', $_[0]->{'ip'}));
		}
	}
&build_local_ip_list();
&release_lock_virt($_[0]);
&register_post_action(\&restart_bind) if ($config{'dns'});
return 1;
}

# delete_virt(&domain)
# Take down the network interface for a domain
sub delete_virt
{
if (!$_[0]->{'virtalready'}) {
	&$first_print($text{'delete_virt'});
	&obtain_lock_virt($_[0]);
	&foreign_require("net", "net-lib.pl");
	local ($biface) = grep { $_->{'address'} eq $_[0]->{'ip'} }
			       &net::boot_interfaces();
	local ($aiface) = grep { $_->{'address'} eq $_[0]->{'ip'} }
			       &net::active_interfaces();
	if (!$biface) {
		&$second_print(&text('delete_noiface', $_[0]->{'iface'}));
		}
	elsif ($biface->{'virtual'} ne '') {
		&net::delete_interface($biface);
		&net::deactivate_interface($aiface)
			if ($aiface && $aiface->{'virtual'} ne '');
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('delete_novirt', $biface->{'fullname'}));
		}
	&build_local_ip_list();
	&release_lock_virt($_[0]);
	}
delete($_[0]->{'iface'});
}

# modify_virt(&domain, &old)
# Change the virtual IP address for a domain
sub modify_virt
{
if ($_[0]->{'ip'} ne $_[1]->{'ip'} && $_[0]->{'virt'} &&
    !$_[0]->{'virtalready'}) {
	# Change IP on virtual interface
	&$first_print($text{'save_virt'});
	&obtain_lock_virt($_[0]);
	&foreign_require("net", "net-lib.pl");
	local ($biface) = grep { $_->{'address'} eq $_[1]->{'ip'} }
			       &net::boot_interfaces();
	local ($aiface) = grep { $_->{'address'} eq $_[1]->{'ip'} }
			       &net::active_interfaces();
	if ($biface && $aiface) {
		if ($biface->{'virtual'} ne '') {
			$biface->{'address'} = $_[0]->{'ip'};
			&net::save_interface($biface);
			}
		if ($aiface->{'virtual'} ne '') {
			$aiface->{'address'} = $_[0]->{'ip'};
			&net::activate_interface($aiface);
			}
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('delete_novirt', $_[1]->{'iface'}));
		}
	&build_local_ip_list();
	&release_lock_virt($_[0]);
	&register_post_action(\&restart_bind) if ($config{'dns'});
	}
}

# clone_virt(&domain, &old-domain)
# No need to do anything here, as an IP address doesn't have any settings that
# need copying
sub clone_virt
{
return 1;
}

# validate_virt(&domain)
# Check for boot-time and active network interfaces
sub validate_virt
{
local ($d) = @_;
if (!$_[0]->{'virtalready'}) {
	# Only check boot-time interface if added by Virtualmin
	local @boots = &bootup_ip_addresses();
	if (&indexof($d->{'ip'}, @boots) < 0) {
		return &text('validate_evirtb', $d->{'ip'});
		}
	}
local @acts = &active_ip_addresses();
if (&indexof($d->{'ip'}, @acts) < 0) {
	return &text('validate_evirta', $d->{'ip'});
	}
return undef;
}

# check_virt_clash(ip)
# Returns 1 if some IP is already in use, 0 if not
sub check_virt_clash
{
# Check active and boot-time interfaces
local %allips = &interface_ip_addresses();
return 1 if ($allips{$_[0]});

# Do a quick ping test
local $pingcmd = $gconfig{'os_type'} =~ /-linux$/ ?
			"ping -c 1 -t 1" : "ping";
local ($out, $timed_out) = &backquote_with_timeout(
				$pingcmd." ".$_[0]." 2>&1", 2, 1);
return 1 if (!$timed_out && !$?);

return 0;
}

# virtual_ip_input(&templates, [reseller], [show-original], [default-mode])
# Returns HTML for selecting a virtual IP mode for a new server, or not
sub virtual_ip_input
{
local ($tmpls, $resel, $orig, $mode) = @_;
$mode ||= 0;
local $defip = &get_default_ip($resel);
if ($config{'all_namevirtual'}) {
	# Always name-based, but on varying IP
	return &ui_textbox("ip", $defip, 20);
	}
else {
	# An IP can be selected, perhaps private, shared or default
	local ($t, $anyalloc, $anychoose, $anyzone);
	if (&running_in_zone() || &running_in_vserver()) {
		# When running in a Solaris zone or VServer, you MUST select an
		# existing active IP, as they are controlled from the host.
		$anyzone = 1;
		}
	elsif (&can_use_feature("virt")) {
		# Check if private IPs are allocated or manual, if we are
		# allowed to choose them.
		foreach $t (@$tmpls) {
			local $tmpl = &get_template($t->{'id'});
			if ($tmpl->{'ranges'} ne "none") { $anyalloc++; }
			else { $anychoose++; }
			}
		}
	local @opts;
	if ($orig) {
		# For restores - option to use original IP
		push(@opts, [ -1, $text{'form_origip'} ]);
		}
	push(@opts, [ 0, &text('form_shared', $defip) ]);
	local @shared = &list_shared_ips();
	if (@shared && &can_edit_sharedips()) {
		# Can select from extra shared list
		push(@opts, [ 3, $text{'form_shared2'},
				 &ui_select("sharedip", undef,
					[ map { [ $_ ] } @shared ]) ]);
		}
	if ($anyalloc) {
		# Can allocate
		push(@opts, [ 2, &text('form_alloc') ]);
		}
	if ($anychoose) {
		# Can enter arbitrary IP
		push(@opts, [ 1, $text{'form_vip'},
			 &ui_textbox("ip", undef, 20)." ".
			 &ui_checkbox("virtalready", 1,
				      $text{'form_virtalready'}) ]);
		}
	if ($anyzone) {
		# Can select an existing active IP
		&foreign_require("net", "net-lib.pl");
		local @act = grep { $_->{'virtual'} ne '' }
				  &net::active_interfaces();
		if (@act) {
			push(@opts, [ 4, $text{'form_activeip'},
				 &ui_select("zoneip", undef,
				  [ map { [ $_->{'address'} ] } @act ]) ]);
			}
		else {
			push(@opts, [ 4, $text{'form_activeip'},
					 &ui_textbox("zoneip", undef, 20) ]);
			}
		}
	if ($mode == 5 && $anyalloc) {
		# Use shared or allocated (for restores only)
		push(@opts, [ 5, &text('form_allocmaybe') ]);
		}
	if (&indexof($mode, map { $_->[0] } @opts) < 0) {
		# Mode is not on the list .. use shared mode
		$mode = 0;
		}
	return &ui_radio_table("virt", $mode, \@opts, 1);
	}
}

# parse_virtual_ip(&template, reseller)
# Parses the virtual IP input field, and returns the IP to use, virt flag,
# already flag and netmask. May call &error if the input is invalid.
sub parse_virtual_ip
{
local ($tmpl, $resel) = @_;
if ($config{'all_namevirtual'}) {
	# Make sure the IP *is* assigned
	&check_ipaddress($in{'ip'}) || &error($text{'setup_eip'});
	if (!&check_virt_clash($in{'ip'})) {
		&error(&text('setup_evirtclash2', $in{'ip'}));
		}
	return ($in{'ip'}, 0, 1);
	}
elsif ($in{'virt'} == 2) {
	# Automatic IP allocation chosen .. select one from either the
	# reseller's range, or the template
	if ($resel) {
		# Creating by or under a reseller .. use his range, if any
		local %acl = &get_reseller_acl($resel);
		if ($acl{'ranges'}) {
			local ($ip, $netmask) = &free_ip_address(\%acl);
			$ip || &error(&text('setup_evirtalloc'));
			return ($ip, 1, 0, $netmask);
			}
		}
	$tmpl->{'ranges'} ne "none" || &error(&text('setup_evirttmpl'));
	local ($ip, $netmask) = &free_ip_address($tmpl);
	$ip || &error(&text('setup_evirtalloc'));
	return ($ip, 1, 0, $netmask);
	}
elsif ($in{'virt'} == 1) {
	# Manual IP allocation chosen
	$tmpl->{'ranges'} eq "none" ||&error(&text('setup_evirttmpl2'));
	&check_ipaddress($in{'ip'}) || &error($text{'setup_eip'});
	local $clash = &check_virt_clash($in{'ip'});
	if ($in{'virtalready'}) {
		# Fail if the IP isn't yet active, or if claimed by another
		# virtual server
		$clash || &error(&text('setup_evirtclash2', $in{'ip'}));
		local $already = &get_domain_by("ip", $in{'ip'});
		$already && &error(&text('setup_evirtclash4',
					 $already->{'dom'}));
		}
	else {
		# Fail if the IP *is* already active
		$clash && &error(&text('setup_evirtclash'));
		}
	return ($in{'ip'}, 1, $in{'virtalready'});
	}
elsif ($in{'virt'} == 3 && &can_edit_sharedips()) {
	# On a shared virtual IP
	&indexof($in{'sharedip'}, &list_shared_ips()) >= 0 ||
		&error(&text('setup_evirtnoshared'));
	return ($in{'sharedip'}, 0, 0);
	}
elsif ($in{'virt'} == 4 && (&running_in_zone() || &running_in_vserver())) {
	# On an active IP on a virtual machine that cannot bring up its
	# own IP.
	&check_ipaddress($in{'zoneip'}) || &error($text{'setup_eip'});
	local $clash = &check_virt_clash($in{'zoneip'});
	$clash || &error(&text('setup_evirtclash2', $in{'zoneip'}));
	local $already = &get_domain_by("ip", $in{'ip'});
	$already && &error(&text('setup_evirtclash4',
				 $already->{'dom'}));
	return ($in{'zoneip'}, 1, 1);
	}
elsif ($in{'virt'} == 5) {
	# Allocate if needed, shared otherwise
	local ($ip, $netmask) = &free_ip_address($tmpl);
	return ($ip, 1, 0, $netmask);
	}
else {
	# Global shared IP
	local $defip = &get_default_ip($resel);
	return ($defip, 0, 0);
	}
}

# show_template_virt(&tmpl)
# Outputs HTML for editing virtual IP related template options
sub show_template_virt
{
local ($tmpl) = @_;

# IP allocation ranges (v4 and possibly v6)
foreach my $ranges ("ranges", &supports_ip6() ? ( "ranges6" ) : ( )) {
	local @ranges;
	@ranges = &parse_ip_ranges($tmpl->{$ranges})
		if ($tmpl->{$ranges} ne "none");
	local @rfields = map { ($ranges."_start_".$_, $ranges."_end_".$_) }
			     (0..scalar(@ranges)+1);
	local $rtable = &none_def_input($ranges, $tmpl->{$ranges},
			 $text{'tmpl_rangesbelow'}, 0, 0, undef, \@rfields);
	local @table;
	local $i = 0;
	local $s = $ranges eq "ranges" ? 20 : 6;
	foreach my $r (@ranges, [ ], [ ]) {
		push(@table, [ &ui_textbox($ranges."_start_$i", $r->[0], 20),
			       &ui_textbox($ranges."_end_$i", $r->[1], 20),
			       &ui_opt_textbox($ranges."_mask_$i", $r->[2], $s,
					       $text{'default'}) ]);
		$i++;
		}
	$rtable .= &ui_columns_table(
		[ $text{'tmpl_ranges_start'}, $text{'tmpl_ranges_end'},
		  $text{'tmpl_ranges_mask'} ],
		undef,
		\@table,
		undef,
		1);
	print &ui_table_row(&hlink($text{'tmpl_'.$ranges},
				   "template_".$ranges."_mode"), $rtable);
	}
}

# parse_template_virt(&tmpl)
# Updates virtual IP related template options from %in
sub parse_template_virt
{
local ($tmpl) = @_;

# Save IPv4 and possibly v6 allocation ranges
foreach my $ranges ("ranges", &supports_ip6() ? ( "ranges6" ) : ( )) {
	if ($in{$ranges.'_mode'} == 0) {
		$tmpl->{$ranges} = "none";
		}
	elsif ($in{$ranges.'_mode'} == 1) {
		$tmpl->{$ranges} = undef;
		}
	else {
		local (@ranges, $start, $end);
		for(my $i=0; defined($start = $in{$ranges."_start_$i"}); $i++) {
			next if (!$start);
			$end = $in{$ranges."_end_$i"};
			$mask = $in{$ranges."_mask_${i}_def"} ? undef :
				  $in{$ranges."_mask_$i"};
			if ($ranges eq "ranges") {
				# IPv4 verification
				&check_ipaddress($start) ||
				    &error(&text('tmpl_eranges_start', $start));
				&check_ipaddress($end) ||
				    &error(&text('tmpl_eranges_end', $start));
				local @start = split(/\./, $start);
				local @end = split(/\./, $end);
				$start[0] == $end[0] && $start[1] == $end[1] &&
				    $start[2] == $end[2] ||
					&error(&text('tmpl_eranges_net',
						     $start));
				$start[3] <= $end[3] ||
					&error(&text('tmpl_eranges_lower',
						     $start));
				!$mask || &check_ipaddress($mask) ||
				    &error(&text('tmpl_eranges_mask', $start));
				}
			else {
				# v6 verification
				&check_ip6address($start) ||
				    &error(&text('tmpl_eranges6_start',$start));
				&check_ip6address($end) ||
				    &error(&text('tmpl_eranges6_end', $end));
				!$mask || $mask =~ /^\d+$/ ||
				    &error(&text('tmpl_eranges_mask', $start));
				}
			push(@ranges, [ $start, $end, $mask ]);
			}
		@ranges || &error($text{'tmpl_e'.$ranges});
		$tmpl->{$ranges} = &join_ip_ranges(\@ranges);
		}
	}
}

# build_local_ip_list()
# Create a local cache file of IPs on this system
sub build_local_ip_list
{
&foreign_require("net", "net-lib.pl");
&open_lock_tempfile(IPCACHE, ">$module_config_directory/localips");
foreach my $a (&net::active_interfaces()) {
	if ($a->{'address'}) {
		&print_tempfile(IPCACHE, $a->{'address'},"\n");
		}
	}
&close_tempfile(IPCACHE);
}

# obtain_lock_virt(&domain)
# Signal that we are locking virtual IPs
sub obtain_lock_virt
{
# Lock the network config directory or file
&obtain_lock_anything();
if ($main::got_lock_virt == 0) {
	&foreign_require("net", "net-lib.pl");
	$main::got_lock_virt_file = $net::network_interfaces_config ||
				    $net::network_config ||
				    "$module_config_directory/virtlock";
	&lock_file($main::got_lock_virt_file);
	if (&supports_ip6()) {
		# Also lock file for IPv6
		$main::got_lock_virt6_file = &ip6_interfaces_file();
		&lock_file($main::got_lock_virt6_file)
			if ($main::got_lock_virt6_file);
		}
	}
$main::got_lock_virt++;
}

# Release virtual IPs lock
sub release_lock_virt
{
# Unlock the network config directory or file
if ($main::got_lock_virt == 1) {
	&unlock_file($main::got_lock_virt6_file)
		if ($main::got_lock_virt6_file);
	&unlock_file($main::got_lock_virt_file);
	}
$main::got_lock_virt-- if ($main::got_lock_virt);
&release_lock_anything();
}

$done_feature_script{'virt'} = 1;

1;

