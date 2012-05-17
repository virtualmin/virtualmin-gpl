#!/usr/local/bin/perl
# domain_setup.cgi
# Create a new virtual domain

require './virtual-server-lib.pl';
&can_create_master_servers() || &can_create_sub_servers() ||
	&error($text{'form_ecannot'});
&require_bind() if ($config{'dns'});
&require_useradmin();
&require_mail() if ($config{'mail'});
&require_mysql() if ($config{'mysql'});
&require_postgres() if ($config{'postgres'});
&require_acl();
&ReadParse();
&error_setup($text{'setup_err'});

# Get parent settings
if ($in{'to'}) {
	$aliasdom = &get_domain($in{'to'});
	$aliasdom || &error($text{'form_ealiasdom'});
	$parentdom = $aliasdom->{'parent'} ?
		&get_domain($aliasdom->{'parent'}) : $aliasdom;
	$parentuser = $parentdom->{'user'};
	&can_edit_domain($aliasdom) || &error($text{'form_ecannot'});
	}
elsif (!&can_create_master_servers()) {
	if ($access{'admin'}) {
		$parentdom = &get_domain($access{'admin'});
		$parentuser = $parentdom->{'user'};
		}
	else {
		$parentuser = $remote_user;
		}
	}
elsif ($in{'parentuser'}) {
	$parentuser = $in{'parentuser'};
	}
if ($parentuser && !$parentdom) {
	$parentdom = &get_domain_by("user", $parentuser, "parent", "");
	$parentdom || &error(&text('form_eparent', $parentuser));
	}
if ($in{'subdom'}) {
	$subdom = &get_domain($in{'subdom'});
	$subdom || &error(&text('form_esubdom', $in{'subdom'}));
	}

# Check if domains limit has been exceeded
($dleft, $dreason, $dmax) = &count_domains($aliasdom ? "aliasdoms" :"realdoms");
&error(&text('setup_emax', $dmax)) if ($dleft == 0);

# Validate inputs (check domain name to see if in use)
$dname = lc(&parse_domain_name($in{'dom'}));
$err = &valid_domain_name($dname);
&error($err) if ($err);
&lock_domain_name($dname);
if ($subdom) {
	# Append super-domain
	$dname =~ /^[A-Za-z0-9\-]+$/ || &error($text{'setup_esubdomain'});
	$subprefix = $dname;
	$dname .= ".$subdom->{'dom'}";
	}
$in{'owner'} =~ s/\r|\n//g;
$in{'owner'} =~ /:/ && &error($text{'setup_eowner'});
&domain_name_clash($dname) && &error($text{'setup_edomain4'});
$tmpl = &get_template($in{'template'});
if (!$parentdom) {
	$plan = &get_plan($in{'plan'});
	$plan && &can_use_plan($plan) || &error($text{'setup_eplan'});
	}
else {
	$plan = &get_plan($parentdom->{'plan'});
	}
if (!$parentuser) {
	# Validate user and password-related inputs for top-level domain
	if (!$in{'email_def'}) {
		$in{'email'} =~ /\S/ || &error($text{'setup_eemail'});
		&extract_address_parts($in{'email'}) ||
			&usage($text{'setup_eemail3'});
		}
	if (!$in{'unix'}) {
		$tmpl->{'mail_on'} eq "none" || !$in{'email_def'} ||
			&error($text{'setup_eemail2'});
		}
	if ($in{'unix'} || $in{'webmin'}) {
		$pass = &parse_new_password("vpass", 0);
		}

	# Parse admin/unix username
	if ($in{'vuser_def'}) {
		# Automatic
		($user, $try1, $try2) = &unixuser_name($dname);
		$user || &error(&text('setup_eauto', $try1, $try2));
		}
	else {
		# Selected by user
		$in{'vuser'} = lc($in{'vuser'});
		$user = $in{'vuser'};
		&valid_mailbox_name($user) && &error($text{'setup_euser2'});
		defined(getpwnam($user)) && &error($text{'setup_euser'});
		}
	&indexof($user, @banned_usernames) < 0 ||
		&error(&text('setup_eroot', join(" ", @banned_usernames)));

	# Parse mail group name
	if ($in{'mgroup_def'}) {
		if ($in{'vuser_def'}) {
			# Automatic
			($group, $gtry1, $gtry2) =
				&unixgroup_name($dname, $user);
			$group || &error(&text('setup_eauto2', $try1, $try2));
			}
		else {
			# Same as admin user
			$group = $user;
			defined(getgrnam($group)) &&
				&error(&text('setup_egroup', $group));
			}
		}
	else {
		# Selected by user
		$in{'mgroup'} = lc($in{'mgroup'});
		$group = $in{'mgroup'};
		&valid_mailbox_name($group) && &error($text{'setup_egroup2'});
		}

	# Parse special group for Unix user
	if (!$in{'group_def'} && &can_choose_ugroup()) {
		$in{'group'} = lc($in{'group'});
		$in{'group'} eq $group && &error(&text('setup_egroup3', $group));
		local ($sg) = &get_domain_by("group", $in{'group'});
		$sg && &error(&text('setup_egroup4', $sg->{'dom'}));
		}
	$home_base || &error($text{'setup_ehomebase'});
	$uerr = &useradmin::check_username_restrictions($user);
	if ($uerr) {
		&error(&text('setup_eusername', $user, $uerr));
		}
	if (&has_home_quotas() && !$config{'template_auto'}) {
		$in{'quota_def'} || $in{'quota'} =~ /^[0-9\.]+$/ ||
			&error($text{'setup_equota'});
		$in{'uquota_def'} || $in{'uquota'} =~ /^[0-9\.]+$/ ||
			&error($text{'setup_euquota'});
		$quota = $in{'quota_def'} ? '' :
				&quota_parse('quota', "home");
		$uquota = $in{'uquota_def'} ? '' :
				&quota_parse('uquota', "home");
		}
	if (!$config{'template_auto'}) {
		if ($config{'bw_active'} && !$config{'template_auto'}) {
			$bw = &parse_bandwidth("bwlimit", $text{'setup_ebwlimit'});
			}
		$in{'mailboxlimit_def'} ||
		   $in{'mailboxlimit'} =~ /^\d+$/ ||
			&error($text{'setup_emailboxlimit'});
		$mailboxlimit = $in{'mailboxlimit_def'} ? undef :
				 $in{'mailboxlimit'};
		$in{'aliaslimit_def'} || $in{'aliaslimit'} =~ /^\d+$/ ||
			&error($text{'setup_ealiaslimit'});
		$aliaslimit = $in{'aliaslimit_def'} ? undef : $in{'aliaslimit'};
		$in{'dbslimit_def'} || $in{'dbslimit'} =~ /^\d+$/ ||
			&error($text{'setup_edbslimit'});
		$dbslimit = $in{'dbslimit_def'} ? undef : $in{'dbslimit'};
		$in{'doms_def'} || $in{'doms'} =~ /^\d*$/ ||
			&error($text{'setup_edomslimit'});
		$domslimit = $in{'domslimit_def'} == 1 ? undef :
			  $in{'domslimit_def'} == 2 ? "*" : $in{'domslimit'};
		$nodbname = $in{'nodbname'};
		}

	# Check password restrictions
	if (defined($pass)) {
		local $fakeuser = { 'user' => $user, 'plainpass' => $pass };
		$err = &check_password_restrictions($fakeuser, $in{'webmin'});
		&error($err) if ($err);
		}
	}
if (!$aliasdom) {
	# Validate non-alias domain inputs
	if ($config{'proxy_pass'} && !$in{'proxy_def'} &&
	    defined($in{'proxy'})) {
		($proxy = $in{'proxy'}) =~ /^(http|https):\/\/\S+$/ ||
			&error($text{'setup_eproxy'});
		}
	if (!$in{'prefix_def'}) {
		$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
			&error($text{'setup_eprefix'});
		}
	if (&database_feature() && &can_edit_databases() && !$in{'db_def'} &&
	    !$subdom) {
		$in{'db'} =~ /^[a-z0-9\-\_]+$/i ||
			&error($text{'setup_edbname'});
		}
	if (defined($in{'fwdto'}) && !$in{'fwdto_def'} && !$subdom &&
	    &can_edit_catchall()) {
		$in{'mail'} ||
			&error($text{'setup_efwdtomail'});
		$in{'fwdto'} =~ /^\S+\@\S+$/ ||
			&error($text{'setup_efwdto'});
		$add_fwdto = 1;
		}
	}

# Validate initial style
if (defined($in{'content'})) {
	($style) = grep { $_->{'name'} eq $in{'style'} }
		&list_available_content_styles();
	if (!$in{'content_def'}) {
		$in{'content'} =~ /\S/ || $style->{'nocontent'} ||
			&error($text{'setup_econtent'});
		}
	}

# Work out the virtual IP
$resel = $parentdom ? $parentdom->{'reseller'} :
	 &reseller_admin() ? $base_remote_user : $in{'reseller'};
$defip = &get_default_ip($resel);
if ($aliasdom) {
	$ip = $aliasdom->{'ip'};
	$virt = 0;
	}
elsif (!&can_select_ip()) {
	$ip = $defip;
	$virt = 0;
	}
else {
	($ip, $virt, $virtalready, $netmask) =
		&parse_virtual_ip($tmpl, $resel);
	}

# Work out the IPv6 address
if ($aliasdom) {
	$ip6 = $aliasdom->{'ip6'};
	$virt6 = 0;
	}
elsif (&can_use_feature("virt") && &supports_ip6()) {
	if ($in{'virt6'} == 1) {
		# Manually entered
		$tmpl->{'ranges6'} eq 'none' ||
			&error(&text('setup_evirt6tmpl2'));
		&check_ip6address($in{'ip6'}) || &error($text{'setup_eip6'});
		$clash = &check_virt6_clash($in{'ip6'});
		if ($in{'virt6already'}) {
			# Fail if the IPv6 address isn't yet active, or if
			# claimed by another virtual server
			local $already = &get_domain_by("ip", $in{'ip'});
			$already && &error(&text('setup_evirt6clash4',
						 $already->{'dom'}));
			}
		else {
			# Fail if the IPv6 address *is* already active
			$clash && &error(&text('setup_evirt6clash'));
			}
		$virt6already = $in{'virt6already'};
		$ip6 = $in{'ip6'};
		$virt6 = 1;
		}
	elsif ($in{'virt6'} == 2) {
		# Allocated
		$tmpl->{'ranges6'} ne "none" ||
			&error(&text('setup_evirt6tmpl'));
		($ip6, $netmask6) = &free_ip6_address($tmpl);
		$ip6 || &text('setup_evirt6alloc');
		$virt6 = 1;
		}
	}

# Validate the DNS IP
if (&can_dnsip()) {
	if (!$in{'dns_ip_def'}) {
		&check_ipaddress($in{'dns_ip'}) || &error($text{'save_ednsip'});
		}
	}

# Make sure domain is under parent, if required
local $derr = &allowed_domain_name($parentdom, $dname);
&error($derr) if ($derr);

if ($parentuser) {
	# User and group IDs come from parent
	$gid = $parentdom->{'gid'};
	$ugid = $parentdom->{'ugid'};
	$user = $parentdom->{'user'};
	$group = $parentdom->{'group'};
	$uid = $parentdom->{'uid'};
	}
else {
	# Work out user and group IDs
	$uid = undef;
	$gid = undef;
	if ($in{'group_def'} || !&can_choose_ugroup()) {
		$ugid = undef;
		$ugroup = $group;
		}
	else {
		$ugid = getgrnam($in{'group'});
		$ugroup = $in{'group'};
		}
	}
$prefix = $in{'prefix_def'} ? &compute_prefix($dname, $group, $parentdom, 1)
			    : $in{'prefix'};
$pclash = &get_domain_by("prefix", $prefix);
$pclash && &error(&text('setup_eprefix3', $prefix, $pclash->{'dom'}));

# Build up domain object
%dom = ( 'id', &domain_id(),
	 'dom', $dname,
	 'user', $user,
	 'group', $group,
	 'prefix', $prefix,
	 'ugroup', $ugroup,
	 $parentuser ?
		( 'pass', $parentdom->{'pass'} ) :
		( 'pass', $pass ),
	 'alias', $aliasdom ? $aliasdom->{'id'} : undef,
	 'subdom', $subdom ? $subdom->{'id'} : undef,
	 'subprefix', $subprefix,
	 'uid', $uid,
	 'gid', $gid,
	 'ugid', $ugid,
	 'owner', $in{'owner'},
	 'email', $parentdom ? $parentdom->{'email'} :
		  !$in{'email_def'} ? $in{'email'} : undef,
	 'name', !$virt,
	 'ip', $ip,
	 'netmask', $netmask,
	 'ip6', $ip6,
	 'netmask6', $netmask6,
	 'dns_ip', !$in{'dns_ip_def'} && &can_dnsip() ? $in{'dns_ip'} :
		   $virt || $config{'all_namevirtual'} ? undef
						       : &get_dns_ip(),
	 'virt', $virt,
	 'virt6', $virt6,
	 'virtalready', $virtalready,
	 'virt6already', $virt6already,
	 'source', 'domain_setup.cgi',
	 'proxy_pass', $proxy,
	 'proxy_pass_mode', $proxy ? $config{'proxy_pass'} : 0,
	 'parent', $parentdom ? $parentdom->{'id'} : "",
	 'template', $in{'template'},
	 'plan', $plan->{'id'},
	 'reseller', $resel,
	);
if (!$parentuser) {
	# Set initial limits
	if ($config{'template_auto'}) {
		# From template
		&set_limits_from_plan(\%dom, $plan);
		}
	else {
		# From user inputs
		$dom{'mailboxlimit'} = $mailboxlimit;
		$dom{'aliaslimit'} = $aliaslimit;
		$dom{'dbslimit'} = $dbslimit;
		$dom{'bw_limit'} = $bw;
		$dom{'domslimit'} = $domslimit;
		$dom{'nodbname'} = $nodbname;
		$dom{'quota'} = $quota;
		$dom{'uquota'} = $uquota;
		$dom{'norename'} = $plan->{'norename'};	# No input for this

		# No fields for these, so set from plan
		$d->{'aliasdomslimit'} = $plan->{'aliasdomslimit'} eq '' ? '*' :
					  $plan->{'aliasdomslimit'};
		$d->{'realdomslimit'} = $plan->{'realdomslimit'} eq '' ? '*' :
					 $plan->{'realdomslimit'};
		}
	&set_capabilities_from_plan(\%dom, $plan);
	}
$dom{'emailto'} = $parentdom ? $parentdom->{'emailto'} :
		  $dom{'email'} ? $dom{'email'} :
		  $dom{'mail'} ? $dom{'user'}.'@'.$dom{'dom'} :
		  		 $dom{'user'}.'@'.&get_system_hostname();

# Set selected features in domain object
# Special magic - if the dir feature is enabled by default and this is an alias
# domain, don't set it
foreach my $f (@features, &list_feature_plugins()) {
	next if ($f eq 'dir' && $config{$f} == 3 && $aliasdom &&
                 $tmpl->{'aliascopy'});
	$dom{$f} = &can_use_feature($f) && int($in{$f});
	}

if ($in{'db_def'} || !&database_feature() || !&can_edit_databases() ||
    $aliasdom || $subdom) {
	# Database name is automatic (or not even used, in the case of alias
	# and sub-domains)
	$dom{'db'} = &database_name(\%dom);
	}
else {
	# Make sure manual DB name has allowed prefix
	$dom{'db'} = &database_name(\%dom);	# For template
	if ($tmpl->{'mysql_suffix'} ne "none") {
		$prefix = &substitute_domain_template(
				$tmpl->{'mysql_suffix'}, \%dom);
		if ($in{'db'} !~ /^\Q$prefix\E/) {
			&error(&text('setup_edbname2', $prefix));
			}
		}
	$dom{'db'} = $in{'db'};
	}

if (!$parentdom) {
	&set_featurelimits_from_plan(\%dom, $plan);
	}
&set_chained_features(\%dom, undef);
&set_provision_features(\%dom);
$dom{'home'} = &server_home_directory(\%dom, $parentdom);
&generate_domain_password_hashes(\%dom, 1);
&complete_domain(\%dom);

# Parse extra feature inputs
foreach $f (&list_feature_plugins()) {
	if ($dom{$f}) {
		$err = &plugin_call($f, "feature_inputs_parse", \%dom, \%in);
		&error($err) if ($err);
		}
	}

# Check for various clashes
$derr = &virtual_server_depends(\%dom);
&error($derr) if ($derr);
$cerr = &virtual_server_clashes(\%dom);
&error($cerr) if ($cerr);

# Check if this new domain would exceed any limits
$lerr = &virtual_server_limits(\%dom);
&error($lerr) if ($lerr);

# Update custom fields
&parse_custom_fields(\%dom, \%in);

&ui_print_unbuffered_header(&domain_in(\%dom), $text{'setup_title'}, "");

# Check for and show any warnings
if (&show_virtual_server_warnings(\%dom, undef, \%in)) {
	&ui_print_footer("", $text{'index_return'});
	return;
	}

$err = &create_virtual_server(\%dom, $parentdom, $parentuser,
			      0, 0, $parentdom ? undef : $pass);
&error($err) if ($err);

# Create default mail forward
if ($add_fwdto) {
	&$first_print(&text('setup_fwding', $in{'fwdto'}));
	&create_domain_forward(\%dom, $in{'fwdto'});
	&$second_print($text{'setup_done'});
	}

# Copy initial website style
if (defined($in{'content'}) && !$in{'content_def'} &&
    &domain_has_website(\%dom)) {
	if ($style) {
		&$first_print(&text('setup_styleing', $style->{'desc'}));
		$in{'content'} =~ s/\r//g;
		&apply_content_style(\%dom, $style, $in{'content'});
		&$second_print($text{'setup_done'});
		}
	}

&run_post_actions();
&webmin_log("create", "domain", $dom{'dom'}, \%dom);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain(\%dom, 'create');
	}

&ui_print_footer("edit_domain.cgi?dom=$dom{'id'}", $text{'edit_return'},
		 "", $text{'index_return'});

