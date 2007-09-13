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
	$parentuser = $remote_user;
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
$in{'dom'} =~ /^[A-Za-z0-9\.\-]+$/ || &error($text{'setup_edomain'});
$in{'dom'} =~ /^\./ && &error($text{'setup_edomain'});
$in{'dom'} =~ /\.$/ && &error($text{'setup_edomain'});
$in{'dom'} = lc($in{'dom'});
&lock_domain_name($in{'dom'});
if ($subdom) {
	# Append super-domain
	$in{'dom'} =~ /^[A-Za-z0-9\-]+$/ || &error($text{'setup_esubdomain'});
	$subprefix = $in{'dom'};
	$in{'dom'} .= ".$subdom->{'dom'}";
	}
$in{'owner'} =~ s/\r|\n//g;
$in{'owner'} =~ /:/ && &error($text{'setup_eowner'});
foreach $d (&list_domains()) {
	&error($text{'setup_edomain2'}) if (lc($d->{'dom'}) eq lc($in{'dom'}));
	}
$tmpl = &get_template($in{'template'});
if (!$parentuser) {
	# Validate user and password-related inputs for top-level domain
	$in{'email_def'} || $in{'email'} =~ /\S/ ||
		&error($text{'setup_eemail'});
	if (!$in{'unix'}) {
		$tmpl->{'mail_on'} eq "none" || !$in{'email_def'} ||
			&error($text{'setup_eemail2'});
		}
	if ($in{'unix'} || $in{'webmin'}) {
		$pass = &parse_new_password("vpass", 0);
		}

	# Parse admin/unix username
	if ($in{'vuser_def'}) {
		($user, $try1, $try2) = &unixuser_name($in{'dom'});
		$user || &error(&text('setup_eauto', $try1, $try2));
		}
	else {
		$in{'vuser'} = lc($in{'vuser'});
		$user = $in{'vuser'};
		$user =~ /^[^\t :]+$/ || &error($text{'setup_euser2'});
		defined(getpwnam($user)) && &error($text{'setup_euser'});
		}
	&indexof($user, @banned_usernames) < 0 ||
		&error(&text('setup_eroot', 'root'));

	# Parse mail group name
	if ($in{'mgroup_def'}) {
		($group, $gtry1, $gtry2) = &unixuser_name($in{'dom'});
		$group || &error(&text('setup_eauto2', $try1, $try2));
		}
	else {
		$in{'mgroup'} = lc($in{'mgroup'});
		$group = $in{'mgroup'};
		$group =~ /^[^\t :]+$/ || &error($text{'setup_egroup2'});
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
		if ($in{'quota'} == -1) { $in{'quota'} = $in{'otherquota'} };
		if ($in{'uquota'} == -1) { $in{'uquota'} = $in{'otheruquota'} }; 
		$in{'quota'} =~ /^[0-9\.]+$/ ||  &error($text{'setup_equota'});
		$in{'uquota'} =~ /^[0-9\.]+$/ ||  &error($text{'setup_euquota'});
		$quota = &quota_parse('quota', "home");
		$uquota = &quota_parse('uquota', "home");
		}
	if (!$config{'template_auto'}) {
		if ($config{'bw_active'} && !$config{'template_auto'}) {
			$bw = &parse_bandwidth("bwlimit", $text{'setup_ebwlimit'});
			}
		$in{'mailboxlimit_def'} ||
		   $in{'mailboxlimit'} =~ /^[1-9]\d*$/ ||
			&error($text{'setup_emailboxlimit'});
		$mailboxlimit = $in{'mailboxlimit_def'} ? undef :
				 $in{'mailboxlimit'};
		$in{'aliaslimit_def'} || $in{'aliaslimit'} =~ /^[1-9]\d*$/ ||
			&error($text{'setup_ealiaslimit'});
		$aliaslimit = $in{'aliaslimit_def'} ? undef : $in{'aliaslimit'};
		$in{'dbslimit_def'} || $in{'dbslimit'} =~ /^[1-9]\d*$/ ||
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
	if ($config{'proxy_pass'} && $in{'web'} && !$in{'proxy_def'}) {
		($proxy = $in{'proxy'}) =~ /^(http|https):\/\/\S+$/ ||
			&error($text{'setup_eproxy'});
		}
	if (!$in{'prefix_def'}) {
		$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
			&error($text{'setup_eprefix'});
		$pclash = &get_domain_by("prefix", $in{'prefix'});
		$pclash && &error($text{'setup_eprefix2'});
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
if (defined($in{'content'}) && !$in{'content_def'}) {
	$in{'content'} =~ /\S/ || &error($text{'setup_econtent'});
	}

# Work out the virtual IP
$resel = $parentdom ? $parentdom->{'reseller'} :
	 &reseller_admin() ? $base_remote_user : undef;
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
	($ip, $virt, $virtalready) = &parse_virtual_ip($tmpl, $resel);
	}

# Make sure domain is under parent, if required
local $derr = &valid_domain_name($parentdom, $in{'dom'});
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
	&build_group_taken(\%gtaken, \%ggtaken);
	$gid = &allocate_gid(\%gtaken);
	$ugid = $in{'group_def'} || !&can_choose_ugroup() ?
			$gid : getgrnam($in{'group'});
	$ugroup = $in{'group_def'} || !&can_choose_ugroup() ?
			$group : $in{'group'};
	&build_taken(\%taken, \%utaken);
	$uid = &allocate_uid(\%taken);
	}
$prefix = $in{'prefix_def'} ? &compute_prefix($in{'dom'}, $group, $parentdom)
			    : $in{'prefix'};

# Build up domain object
%dom = ( 'id', &domain_id(),
	 'dom', $in{'dom'},
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
	 'dns_ip', $virt || $config{'all_namevirtual'} ? undef :
		   $config{'dns_ip'},
	 'virt', $virt,
	 'virtalready', $virtalready,
	 'source', 'domain_setup.cgi',
	 'proxy_pass', $proxy,
	 'proxy_pass_mode', $proxy ? $config{'proxy_pass'} : 0,
	 'parent', $parentdom ? $parentdom->{'id'} : "",
	 'template', $in{'template'},
	 'reseller', $resel,
	);
if (!$parentuser) {
	# Set initial limits
	if ($config{'template_auto'}) {
		# From template
		&set_limits_from_template(\%dom, $tmpl);
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
		$dom{'norename'} = $tmpl->{'norename'};	# No input for this
		}
	&set_capabilities_from_template(\%dom, $tmpl);
	}
$dom{'emailto'} = $parentdom ? $parentdom->{'emailto'} :
		  $dom{'email'} ? $dom{'email'} :
		  $dom{'mail'} ? $dom{'user'}.'@'.$dom{'dom'} :
		  		 $dom{'user'}.'@'.&get_system_hostname();
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
my $f;
foreach $f (@features, @feature_plugins) {
	$dom{$f} = &can_use_feature($f) && int($in{$f});
	}
&set_featurelimits_from_template(\%dom, $tmpl);
&set_chained_features(\%dom);
$dom{'home'} = &server_home_directory(\%dom, $parentdom);
&complete_domain(\%dom);

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

$err = &create_virtual_server(\%dom, $parentdom, $parentuser);
&error($err) if ($err);

# Create default mail forward
if ($add_fwdto) {
	&$first_print(&text('setup_fwding', $in{'fwdto'}));
	&create_domain_forward(\%dom, $in{'fwdto'});
	&$second_print($text{'setup_done'});
	}

# Copy initial website style
if (defined($in{'content'}) && !$in{'content_def'} && $dom{'web'}) {
	($style) = grep { $_->{'name'} eq $in{'style'} }
			&list_available_content_styles();
	if ($style) {
		&$first_print(&text('setup_styleing', $style->{'desc'}));
		$in{'content'} =~ s/\r//g;
		&apply_content_style(\%dom, $style, $in{'content'});
		&$second_print($text{'setup_done'});
		}
	}

&webmin_log("create", "domain", $dom{'dom'}, \%dom);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain(\%dom, 'create');
	}

&ui_print_footer("edit_domain.cgi?dom=$dom{'id'}", $text{'edit_return'},
		 "", $text{'index_return'});

