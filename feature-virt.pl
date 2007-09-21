# Functions for setting up a virtual IP interface

# setup_virt(&domain)
# Bring up an interface for a domain, if the IP isn't already enabled
sub setup_virt
{
&foreign_require("net", "net-lib.pl");
local @boot = &net::active_interfaces();
if (!$config{'iface_manual'} && !$_[0]->{'virtalready'}) {
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
	local $virt = { 'address' => $_[0]->{'ip'},
			'netmask' => $net::virtual_netmask || $iface->{'netmask'},
			'broadcast' =>
				$net::virtual_netmask eq "255.255.255.255" ?
					$_[0]->{'ip'} : $iface->{'broadcast'},
			'name' => $iface->{'name'},
			'virtual' => $vmax+1,
			'up' => 1 };
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
}

# delete_virt(&domain)
# Take down the network interface for a domain
sub delete_virt
{
if (!$config{'iface_manual'} && !$_[0]->{'virtalready'}) {
	&$first_print($text{'delete_virt'});
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
	}
delete($_[0]->{'iface'});
}

# modify_virt(&domain, &old)
# Change the virtual IP address for a domain
sub modify_virt
{
if ($_[0]->{'ip'} ne $_[1]->{'ip'} && $_[0]->{'virt'} &&
    !$config{'iface_manual'} && !$_[0]->{'virtalready'}) {
	&$first_print($text{'save_virt'});
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
	}
}

# validate_virt(&domain)
# Check for boot-time and active network interfaces
sub validate_virt
{
local ($d) = @_;
&foreign_require("net", "net-lib.pl");
return undef if ($config{'iface_manual'});	# manually setup
if (!$_[0]->{'virtalready'}) {
	# Only check boot-time interface if added by Virtualmin
	local ($biface) = grep { $_->{'address'} eq $d->{'ip'} }
			       &net::boot_interfaces();
	return &text('validate_evirtb', $d->{'ip'}) if (!$biface);
	}
local ($aiface) = grep { $_->{'address'} eq $d->{'ip'} }
		       &net::active_interfaces();
return &text('validate_evirta', $d->{'ip'}) if (!$aiface);
return undef;
}

# check_virt_clash(ip)
# Returns the interface if some IP is already in use
sub check_virt_clash
{
return undef if ($config{'iface_manual'});	# no clash for manual mode

# Check active and boot-time interfaces
&foreign_require("net", "net-lib.pl");
local @boot = &net::boot_interfaces();
local ($boot) = grep { $_->{'address'} eq $_[0] } @boot;
local @active = &net::active_interfaces();
local ($active) = grep { $_->{'address'} eq $_[0] } @active;
return 1 if ($active || $boot);

# Do a quick ping test
local $pingcmd = $gconfig{'os_type'} =~ /-linux$/ ?
			"ping -c 1 -t 1" : "ping";
local ($out, $timed_out) = &backquote_with_timeout(
				$pingcmd." ".$_[0]." 2>&1", 2, 1);
return 1 if (!$timed_out && !$?);

return 0;
}

# virtual_ip_input(&templates, [reseller])
# Returns HTML for selecting a virtual IP mode for a new server, or not
sub virtual_ip_input
{
local ($tmpls, $resel) = @_;
local $defip = &get_default_ip($resel);
if ($config{'all_namevirtual'}) {
	# Always name-based, but on varying IP
	return &ui_textbox("ip", $defip, 20);
	}
else {
	# An IP can be selected, perhaps private, shared or default
	local ($t, $anyalloc, $anychoose, $anyzone);
	if (&running_in_zone() ||
	    (defined(&running_in_vserver) && &running_in_vserver())) {
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
	local @opts = ( [ 0, &text('form_shared', $defip)."<br>" ] );
	local @shared = &list_shared_ips();
	if (@shared && &can_edit_sharedips()) {
		# Can select from extra shared list
		push(@opts, [ 3, $text{'form_shared2'}." ".
				 &ui_select("sharedip", undef,
					[ map { [ $_ ] } @shared ])."<br>" ]);
		}
	if ($anyalloc) {
		# Can allocate
		push(@opts, [ 2, &text('form_alloc')."<br>" ]);
		}
	if ($anychoose) {
		# Can enter arbitrary IP
		push(@opts, [ 1, $text{'form_vip'}." ".
			 &ui_textbox("ip", undef, 20)." (".
			 &ui_checkbox("virtalready", 1,
				      $text{'form_virtalready'}).")<br>" ]);
		}
	if ($anyzone) {
		# Can select an existing active IP
		&foreign_require("net", "net-lib.pl");
		local @act = grep { $_->{'virtual'} ne '' }
				  &net::active_interfaces();
		if (@act) {
			push(@opts, [ 4, $text{'form_activeip'}." ".
				 &ui_select("zoneip", undef,
				  [ map { [ $_->{'address'} ] } @act ]) ]);
			}
		else {
			push(@opts, [ 4, $text{'form_activeip'}." ".
					 &ui_textbox("zoneip", undef, 20) ]);
			}
		}
	return &ui_radio("virt", 0, \@opts);
	}
}

# parse_virtual_ip(&template, reseller)
# Parses the virtual IP input field, and returns the IP to use and virt flag.
# May call &error if the input is invalid.
sub parse_virtual_ip
{
local ($tmpl, $resel) = @_;
if ($config{'all_namevirtual'}) {
	# Make sure the IP *is* assigned
	&check_ipaddress($in{'ip'}) || &error($text{'setup_eip'});
	if (!&check_virt_clash($in{'ip'})) {
		&error(&text('setup_evirtclash2'));
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
			local $ip = &free_ip_address(\%acl);
			$ip || &error(&text('setup_evirtalloc'));
			return ($ip, 1);
			}
		}
	$tmpl->{'ranges'} ne "none" || &error(&text('setup_evirttmpl'));
	local $ip = &free_ip_address($tmpl);
	$ip || &error(&text('setup_evirtalloc'));
	return ($ip, 1, 0);
	}
elsif ($in{'virt'} == 1) {
	# Manual IP allocation chosen
	$tmpl->{'ranges'} eq "none" ||&error(&text('setup_evirttmpl2'));
	&check_ipaddress($in{'ip'}) || &error($text{'setup_eip'});
	local $clash = &check_virt_clash($in{'ip'});
	if ($in{'virtalready'}) {
		# Fail if the IP isn't yet active, or if claimed by another
		# virtual server
		$clash || &error(&text('setup_evirtclash2'));
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
elsif ($in{'virt'} == 4 && (&running_in_zone() ||
		    defined(&running_in_vserver) && &running_in_vserver())) {
	# On an active IP on a virtual machine that cannot bring up its
	# own IP.
	&check_ipadress($in{'zoneip'}) || &error($text{'setup_eip'});
	local $clash = &check_virt_clash($in{'zoneip'});
	$clash || &error(&text('setup_evirtclash2'));
	local $already = &get_domain_by("ip", $in{'ip'});
	$already && &error(&text('setup_evirtclash4',
				 $already->{'dom'}));
	return ($in{'zoneip'}, 1, 1);
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

# IP allocation range
@ranges = &parse_ip_ranges($tmpl->{'ranges'})
	if ($tmpl->{'ranges'} ne "none");
local @rfields = map { ("ranges_start_".$_, "ranges_end_".$_) }
		     (0..scalar(@ranges)+1);
$rtable = &none_def_input("ranges", $tmpl->{'ranges'},
			 $text{'tmpl_rangesbelow'}, 0, 0, undef, \@rfields);
$rtable .= &ui_columns_start([ $text{'tmpl_ranges_start'},
			  $text{'tmpl_ranges_end'} ]);
$i = 0;
foreach $r (@ranges, [ ], [ ]) {
	$rtable .= &ui_columns_row([
		&ui_textbox("ranges_start_$i", $r->[0], 20),
		&ui_textbox("ranges_end_$i", $r->[1], 20),
		]);
	$i++;
	}
$rtable .= &ui_columns_end();
print &ui_table_row(&hlink($text{'tmpl_ranges'},"template_ranges_mode"),
		    $rtable);
}

# parse_template_virt(&tmpl)
# Updates virtual IP related template options from %in
sub parse_template_virt
{
local ($tmpl) = @_;

# Save IP allocation ranges
if ($in{'ranges_mode'} == 0) {
	$tmpl->{'ranges'} = "none";
	}
elsif ($in{'ranges_mode'} == 1) {
	$tmpl->{'ranges'} = undef;
	}
else {
	for($i=0; defined($start = $in{"ranges_start_$i"}); $i++) {
		next if (!$start);
		$end = $in{"ranges_end_$i"};
		&check_ipaddress($start) ||
			&error(&text('tmpl_eranges_start', $start));
		&check_ipaddress($end) ||
			&error(&text('tmpl_eranges_end', $start));
		@start = split(/\./, $start);
		@end = split(/\./, $end);
		$start[0] == $end[0] && $start[1] == $end[1] &&
		    $start[2] == $end[2] ||
			&error(&text('tmpl_eranges_net', $start));
		$start[3] <= $end[3] ||
			&error(&text('tmpl_eranges_lower', $start));
		push(@ranges, [ $start, $end ]);
		}
	@ranges || &error($text{'tmpl_eranges'});
	$tmpl->{'ranges'} = &join_ip_ranges(\@ranges);
	}
}

$done_feature_script{'virt'} = 1;

1;

