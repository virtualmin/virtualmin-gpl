#!/usr/local/bin/perl
# Create multiple virtual servers at once

require './virtual-server-lib.pl';
&ReadParseMime();
&error_setup($text{'cmass_err'});
&can_create_master_servers() || &can_create_sub_servers() ||
	&error($text{'form_ecannot'});
&can_create_batch() || &error($text{'cmass_ecannot'});
&require_useradmin();

# Validate source file
if ($in{'file_def'} == 1) {
	# Server-side file
	&master_admin() || &error($text{'cmass_elocal'});
	open(LOCAL, $in{'local'}) || &error($text{'cmass_elocal2'});
	while(<LOCAL>) {
		$source .= $_;
		}
	close(LOCAL);
	$src = "<tt>$in{'local'}</tt>";
	}
elsif ($in{'file_def'} == 0) {
	# Uploaded file
	$in{'upload'} =~ /\S/ || &error($text{'cmass_eupload'});
	$source = $in{'upload'};
	$src = $text{'cmass_uploaded'};
	}
elsif ($in{'file_def'} == 2) {
	# Pasted text
	$in{'text'} =~ /\S/ || &error($text{'cmass_etext'});
	$source = $in{'text'};
	$src = $text{'cmass_texted'};
	}
$source =~ s/\r//g;

# Work out the reseller
if (&master_admin()) {
	$defresel = $in{'resel'};
	}
elsif (&reseller_admin()) {
	$defresel = $base_remote_user;
	}
else {
	$mydom = &get_domain_by("user", $base_remote_user, "parent", undef);
	$defresel = $mydom->{'resel'};
	}

&ui_print_unbuffered_header(undef, $text{'cmass_title'}, "", "cmass");

print &text('cmass_doing', $src),"<p>\n";

# Split into lines, and process each one
@lines = split(/\n+/, $source);
$lnum = 0;
$count = $ecount = 0;
$sep = $in{'separator'};
$sep = "\t" if ($sep eq "tab");
foreach $line (@lines) {
	$lnum++;
	next if ($line !~ /\S/);
	local ($dname, $owner, $pass, $user, $pname, $ip, $aname) = split($sep, $line, -1);
	$dname = lc(&parse_domain_name($dname));
	$user = lc($user);

	# Validate domain details
	if (!$dname || !$owner) {
		&line_error($text{'cmass_edname'});
		next;
		}
	$err = &valid_domain_name($dname);
	if ($err) {
		&line_error($err);
		next;
		}
	if ($owner =~ /:/) {
		&line_error($text{'setup_eowner'});
		next;
		}
	if (&domain_name_clash($dname)) {
		&line_error($text{'setup_edomain4'});
		next;
		}
	local $parentdom;
	if ($pname) {
		$parentdom = &get_domain_by("dom", $pname);
		if (!$parentdom) {
			&line_error(&text('cmass_eparent', $pname));
			next;
			}
		&can_config_domain($parentdom) ||
		    &line_error(&text('cmass_ecanparent', $parentdom->{'dom'}));
		$parentdom->{'parent'} &&
		    &line_error(&text('cmass_eparpar', $parentdom->{'dom'}));
		}
	elsif (!&can_create_master_servers()) {
		&line_error($text{'cmass_emustparent'});
		}
	local $aliasdom;
	if ($aname) {
		$aliasdom = &get_domain_by("dom", $aname);
		if (!$aliasdom) {
			&line_error(&text('cmass_ealias', $aname));
			next;
			}
		&can_config_domain($aliasdom) ||
		    &line_error(&text('cmass_ecanparent', $aliasdom->{'dom'}));
		$parentdom ||= $aliasdom;
		}

	# Get the reseller
	local $resel = $parentdom ? $parentdom->{'reseller'} : $defresel;

	# Get the template
	local $tmpl = &get_template($parentdom ? $in{'stemplate'}
					       : $in{'ptemplate'});

	# Validate IP address
	local $defip = &get_default_ip($resel);
	local $defip6 = &get_default_ip6($resel);
	local ($virt, $virtalready, $ip6, $virt6, $allocated);
	if ($aliasdom) {
		$ip = $aliasdom->{'ip'};
		$ip6 = $aliasdom->{'ip6'};
		}
	elsif ($ip) {
		if (!&check_ipaddress($ip) && $ip ne 'allocate') {
			&line_error($text{'cmass_eip'});
			next;
			}
		if (!&can_use_feature("virt")) {
			&line_error($text{'cmass_evirt'});
			next;
			}
		if ($config{'all_namevirtual'}) {
			# Name-based, but with different IP
			$virt = 1;
			$virtalready = 1;
			}
		elsif ($ip eq 'allocate') {
			# Need to allocate
			%racl = $resel ? &get_reseller_acl($resel) : ();
			if ($racl{'ranges'}) {
				# Allocating from reseller's range
				($ip, $netmask) = &free_ip_address(\%racl);
				if (!$ip) {
					&line_error($text{'cmass_eipresel'});
					next;
					}
				}
			else {
				# Allocating from template
				if ($tmpl->{'ranges'} eq "none") {
					&line_error($text{'cmass_eiptmpl'});
					next;
					}
				($ip, $netmask) = &free_ip_address($tmpl);
				if (!$ip) {
					&line_error($text{'cmass_eipalloc'});
					next;
					}
				}
			$virt = 1;
			$virtalready = 0;
			$allocated = 1;
			}
		else {
			# IP specified manually
			if ($tmpl->{'ranges'} ne "none" &&
			    !$config{'all_namevirtual'}) {
				&line_error($text{'cmass_eipmust'});
				next;
				}
			$virt = 1;
			$virtalready = 0;
			}
		}
	else {
		$virt = 0;
		$virtalready = 1;
		$ip = $defip;
		}

	# Pick an IPv6 address
	if (&supports_ipv()) {
		if ($allocated) {
			# IPv4 allocation was requested, assume the same for V6
			%racl = $resel ? &get_reseller_acl($resel) : ();
			if ($racl{'ranges6'}) {
				# Allocating from reseller's range
				($ip6, $netmask6) = &free_ip6_address(\%racl);
				if (!$ip6) {
					&line_error($text{'cmass_eipresel'});
					next;
					}
				}
			else {
				# Allocating from template
				if ($tmpl->{'ranges6'} eq "none") {
					&line_error($text{'cmass_eiptmpl'});
					next;
					}
				($ip6, $netmask6) = &free_ip6_address($tmpl);
				if (!$ip6) {
					&line_error($text{'cmass_eipalloc'});
					next;
					}
				}
			$virt6 = 1;
			$name6 = 0;
			}
		elsif ($config{'ip6enabled'}) {
			# Use default shared IPv6
			$ip6 = $defip6;
			$virt6 = 0;
			}
		else {
			# No IPv6 at all
			}
		}

	# Work out username
	local $group;
	if (!$parentdom) {
		if (!$user) {
			# Select a username
			($user, $try1, $try2) = &unixuser_name($dname);
			if (!$user) {
				&line_error(&text('setup_eauto', $try1, $try2));
				next;
				}
			}
		else {
			# Check supplied username
			if ($user !~ /^[^\t :]+$/) {
				&line_error($text{'setup_euser2'});
				next;
				}
			if (defined(getpwnam($user))) {
				&line_error($text{'setup_euser'});
				next;
				}
			}

		# Work out mailboxes group name
		($group, $gtry1, $gtry2) = &unixgroup_name($dname, $user);
		if (!$group) {
			&line_error(&text('setup_eauto2',
					  $gtry1, $gtry2));
			next;
			}

		# Check username restrictions
		local $uerr = &useradmin::check_username_restrictions($user);
		if ($uerr) {
			&line_error(&text('setup_eusername', $user, $uerr));
			next;
			}
		}

	# Check if domains limit has been exceeded
	local ($dleft, $dreason, $dmax) =
		&count_domains($aliasdom ? "aliasdoms" : "realdoms");
	if ($dleft == 0) {
		&line_error(&text('setup_emax', $dmax));
		next;
		}

	# Make sure domain is under parent, if required
	if ($parentdom) {
		local $derr = &allowed_domain_name($parentdom, $dname);
		if ($derr) {
			&line_error($derr);
			next;
			}
		}

	local (%gtaken, %ggtaken, %taken, %utaken);
	local ($gid, $ugid, $uid);
	if ($parentdom) {
		# User and group IDs come from parent
		$gid = $parentdom->{'gid'};
		$ugid = $parentdom->{'ugid'};
		$user = $parentdom->{'user'};
		$group = $parentdom->{'group'};
		$uid = $parentdom->{'uid'};
		}
	else {
		# User and group IDs are allocated in setup_unix
		$gid = $gid = $uid = undef;
		$ugroup = $group;
		}
	local $prefix = &compute_prefix($dname, $group, $parentdom, 1);

	# Work out the plan
	if ($parentdom) {
		$plan = &get_plan($parentdom->{'plan'});
		}
	elsif (defined($in{'plan'})) {
		$plan = &get_plan($in{'plan'});
		&can_use_plan($plan) || &error($text{'setup_eplan'});
		}
	else {
		$plan = &get_default_plan();
		}

	# Build up domain object
	local %dom;
	%dom = ( 'id', &domain_id(),
		 'dom', $dname,
		 'user', $user,
		 'group', $group,
		 'prefix', $prefix,
		 'ugroup', $ugroup,
		 $parentdom ?
			( 'pass', $parentdom->{'pass'} ) :
			( 'pass', $pass ),
		 'uid', $uid,
		 'gid', $gid,
		 'ugid', $ugid,
		 'owner', $owner,
		 'email', $parentdom ? $parentdom->{'email'} : undef,
		 'name', !$virt,
		 'name6', !$virt6,
		 'ip', $ip,
		 'ip6', $ip6,
		 'netmask', $netmask,
		 'netmask6', $netmask6,
		 'dns_ip', $virt || $config{'all_namevirtual'} ? undef :
			   &get_dns_ip($resel),
		 'virt', $virt,
		 'virt6', $virt6,
		 'virtalready', $virtalready,
		 'source', 'mass_create.cgi',
		 'proxy_pass_mode', 0,
		 'parent', $parentdom ? $parentdom->{'id'} : "",
		 'alias', $aliasdom ? $aliasdom->{'id'} : "",
		 'template', $tmpl->{'id'},
		 'plan', $plan->{'id'},
		 'reseller', $resel,
		);
	$dom{'emailto'} = $dom{'email'} ||
			  $dom{'user'}.'@'.&get_system_hostname();
	$dom{'db'} = &database_name(\%dom);
	my $f;
	foreach $f (@features, &list_feature_plugins()) {
		next if ($parentdom && ($f eq 'webmin' || $f eq 'unix'));
		next if ($f eq 'dir' && $config{$f} == 3 && $aliasdom &&
			 $tmpl->{'aliascopy'});
		if (&indexof($f, &list_feature_plugins()) >= 0) {
			# Check if plugin is suitable for domain
			next if (!&plugin_call($f, "feature_suitable",
                                 $parentdom, $aliasdom, $subdom));
			}
		if ($aliasdom) {
			# Check if feature is suitable for aliases
			next if (&indexof($f, @opt_alias_features) < 0);
			}
		$dom{$f} = &can_use_feature($f) && int($in{$f});
		}
	&set_limits_from_plan(\%dom, $plan);
	&set_featurelimits_from_plan(\%dom, $plan);
	&set_chained_features(\%dom, undef);
	&set_provision_features(\%dom);
	&set_capabilities_from_plan(\%dom, $plan);
	$dom{'home'} = &server_home_directory(\%dom, $parentdom);
	&generate_domain_password_hashes(\%dom, 1);
	&complete_domain(\%dom);

	# Check for various clashes
	local $derr = &virtual_server_depends(\%dom);
	if ($derr) {
		&line_error($derr);
		next;
		}
	local $cerr = &virtual_server_clashes(\%dom);
	if ($cerr) {
		&line_error($cerr);
		next;
		}

	# Check if this new domain would exceed any limits
	local $lerr = &virtual_server_limits(\%dom);
	if ($lerr) {
		&line_error($lerr);
		next;
		}

	# Actually do it!
	&set_all_null_print();
	local $err = &create_virtual_server(\%dom, $parentdom,
			      $parentdom ? $parentdom->{'user'} : undef, 0, 1,
			      $parentdom ? undef : $pass);
	if ($err) {
		&line_error($err);
		next;
		}
	else {
		print "<font color=#00aa00>",
		      &text('cmass_done', "<tt>$dname</tt>"),"</font><br>\n";
		$count++;
		}

	# Call any theme post command
	if (defined(&theme_post_save_domain) &&
	    !defined(&theme_post_save_domains)) {
		&theme_post_save_domain(\%dom, 'create');
		}
	else {
		push(@das, \%dom, 'create');
		}
	}

# Run post-create commands
&run_post_actions();
if (defined(&theme_post_save_domains)) {
	&theme_post_save_domains(@das);
	}

print "<p>\n";
print &text('cmass_complete', $count, $ecount),"<br>\n";
&webmin_log("create", "domains", $count);

&ui_print_footer("", $text{'index_return'});

sub line_error
{
local ($msg) = @_;
print "<font color=#ff0000>";
if (!$dname) {
	print &text('cmass_eline', $lnum, $msg);
	}
else {
	print &text('cmass_eline2', $lnum, $msg, "<tt>$dname</tt>");
	}
print "</font><br>\n";
$ecount++;
}

