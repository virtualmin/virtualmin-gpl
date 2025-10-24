#!/usr/local/bin/perl
# domain_form.cgi
# Display a form for setting up a new virtual domain

require './virtual-server-lib.pl';
&ReadParse();

if ($in{'import'}) {
	# Redirect to the import form
	&redirect("import_form.cgi");
	return;
	}
elsif ($in{'migrate'}) {
	# Redirect to the migration form
	&redirect("migrate_form.cgi");
	return;
	}
elsif ($in{'batch'}) {
	# Redirect to the batch creation
	&redirect("mass_create_form.cgi");
	return;
	}
elsif ($in{'delete'}) {
	# Redirect to the mass server deletion form
	@d = split(/\0/, $in{'d'});
	&redirect("pro/mass_delete_domains.cgi?".join("&", map { "d=$_" } @d));
	return;
	}
elsif ($in{'mass'}) {
	# Redirect to the mass server update form
	@d = split(/\0/, $in{'d'});
	&redirect("pro/mass_domains_form.cgi?".join("&", map { "d=$_" } @d));
	return;
	}
elsif ($in{'disable'}) {
	# Redirect to mass disable form
	@d = split(/\0/, $in{'d'});
	&redirect("pro/mass_disable.cgi?".join("&", map { "d=$_" } @d));
	return;
	}
elsif ($in{'enable'}) {
	# Redirect to mass enable form
	@d = split(/\0/, $in{'d'});
	&redirect("pro/mass_enable.cgi?".join("&", map { "d=$_" } @d));
	return;
	}


# Can this user even create servers?
&can_create_master_servers() || &can_create_sub_servers() ||
	&error($text{'form_ecannot'});

# Get parent settings
if ($in{'to'}) {
	# Creating an alias domain
	$aliasdom = &get_domain($in{'to'});
	$parentdom = $aliasdom->{'parent'} ?
		&get_domain($aliasdom->{'parent'}) : $aliasdom;
	$parentuser = $parentdom->{'user'};
	}
elsif (!&can_create_master_servers()) {
	# This user can only create a sub-server
	if ($access{'admin'}) {
		$parentdom = &get_domain($access{'admin'});
		$parentuser = $parentdom->{'user'};
		}
	else {
		$parentuser = $remote_user;
		}
	}
elsif ($in{'parentuser1'} || $in{'parentuser2'}) {
	# Creating sub-server explicitly
	$parentuser = $in{'add1'} ? $in{'parentuser1'} : $in{'parentuser2'};
	}
if ($parentuser && !$parentdom) {
	$parentdom = &get_domain_by("user", $parentuser, "parent", "");
	$parentdom || &error(&text('form_eparent', $parentuser));
	}
if ($in{'subdom'}) {
	# Creating a sub-domain
	$subdom = &get_domain($in{'subdom'});
	$subdom || &error(&text('form_esubdom', $in{'subdom'}));
	}
my $subhead = $aliasdom || $parentdom ? &domain_in($aliasdom || $parentdom) : "";
&ui_print_header($subhead, $aliasdom ? $text{'form_title3'} :
			   $subdom ? $text{'form_title4'} :
			   $parentdom ? $text{'form_title2'} :
				        $text{'form_title'}, "",
			   $aliasdom ? "create_alias" :
			   $subdom ? "create_subdom" :
			   $parentdom ? "create_subserver" : "create_form");
# Show user friendly info
my ($tdleft, $tdreason, $tdmax) = &count_domains("topdoms");
if (!$tdleft && $tdreason == 3) {
	print &ui_alert_box(
		&text('setup_emax', $tdmax, $virtualmin_account_subscriptions),
		'warn', undef, undef, '');
	}

# Form header
@tds = ( "width=30%" );
print &ui_form_start("domain_setup.cgi", "post");
print &ui_hidden("parentuser", $parentuser),"\n";
print &ui_hidden("to", $in{'to'}),"\n";
print &ui_hidden("subdom", $in{'subdom'}),"\n";
print &ui_hidden_table_start($text{'form_header'}, "width=100%", 2,
			     "basic", 1);

# Domain name
if ($subdom) {
	# Under top-level domain
	print &ui_table_row(&hlink($text{'form_domain'}, "domainname"),
		&vui_noauto_textbox("dom", undef, 20).".$subdom->{'dom'}",
		undef, \@tds);
	}
else {
	# Full domain name
	local $force = $access{'forceunder'} && $parentdom ?
			".$parentdom->{'dom'}" :
		       $access{'subdom'} ? ".$access{'subdom'}" : undef;
	print &ui_table_row(&hlink($text{'form_domain'}, "domainname"),
	      &vui_noauto_textbox("dom", $force, 50, 0, undef,
				  "onBlur='domain_change(this)'"),
	      undef, \@tds);

	# Javascript to append domain name if needed
	print "<script>\n";
	print "function domain_change(field)\n";
	print "{\n";
	if ($parentdom && !$aliasdom) {
		print "if (field.value.indexOf('.') < 0) {\n";
		print "    field.value += '.".$parentdom->{'dom'}."';\n";
		print "    }\n";
		}
	print "}\n";
	print "</script>\n";
	}

# Description / owner
print &ui_table_row(&hlink($text{'form_owner'}, "ownersname"),
		    &vui_noauto_textbox("owner", undef, 50),
		    undef, \@tds);

if (!$parentuser) {
	# Password
	print &ui_table_row(&hlink($text{'form_pass'}, "password"),
		&new_password_input("vpass"),
		undef, \@tds);

	# SSH public key for Unix user
	print &ui_table_row(&hlink($text{'form_sshkey'}, "sshkey"),
		&ui_radio("sshkey_mode", 0,
			  [ [ 0, $text{'form_sshkey0'} ],
			    [ 1, $text{'form_sshkey1'} ],
			    [ 2, $text{'form_sshkey2'} ] ])."<br>\n".
		&ui_textarea("sshkey", undef, 3, 60), undef, \@tds);
	}

# Generate Javascript for template change
@availtmpls = &list_available_templates($parentdom, $aliasdom);
if ($aliasdom || $parentdom) {
	# Alias and sub-servers should inherit parent template, if possible
	$deftmplid = $aliasdom ? $aliasdom->{'template'}
			       : $parentdom->{'template'};
	($deftmpl) = grep { $_->{'id'} == $deftmplid } @availtmpls;
	}
if (!$deftmpl) {
	$deftmplid = &get_init_template($parentdom);
	($deftmpl) = grep { $_->{'id'} == $deftmplid } @availtmpls;
	}
$deftmpl ||= $availtmpls[0];
$js = "<script>\n";
$js .= "function select_template(num)\n";
$js .= "{\n";
$js .= "var domain_form_target = document.querySelectorAll('form[action*=\"domain_setup.cgi\"]');\n";
foreach $t (@availtmpls) {
	local $tmpl = &get_template($t->{'id'});
	if (!$parentdom && &can_choose_ugroup()) {
		# Set group for unix user
		$js .= "if (num == $tmpl->{'id'}) {\n";
		$num = $tmpl->{'ugroup'} eq "none" ? 0 : 1;
		$val = $tmpl->{'ugroup'} eq "none" ? "" : $tmpl->{'ugroup'};
		$js .= "    domain_form_target[0].group_def[$num].checked = true;\n";
		$js .= "    domain_form_target[0].group.value = \"$val\";\n";
		$js .= "    }\n";
		}
	}
$js .= "}\n";
$js .= "</script>\n";
print $js;

# Work out which features are enabled by default
@dom_features = $aliasdom ? @opt_alias_features :
		$subdom ? @opt_subdom_features : @opt_features;
%plugins_inactive = map { $_, 1 } @plugins_inactive;
if ($config{'plan_auto'}) {
	@def_features = grep { $config{$_} == 1 || $config{$_} == 3 }
			     @dom_features;
	@fplugins = &list_feature_plugins();
	push(@def_features, grep { !$plugins_inactive{$_} } @fplugins);
	}

# Generate Javascript for plan change
@availplans = sort { $a->{'name'} cmp $b->{'name'} } &list_available_plans();
$defplan = &get_default_plan();
$js = "<script>\n";
$js .= "function select_plan(num)\n";
$js .= "{\n";
$js .= "var domain_form_target = document.querySelectorAll('form[action*=\"domain\"][action*=\".cgi\"]');\n";
foreach $plan (@availplans) {
	$js .= "if (num == $plan->{'id'}) {\n";
	if (!$config{'template_auto'}) {
		# Limits are only set if the fields exists

		# Set quotas
		$js .= &quota_javascript("quota", $plan->{'quota'}, "home", 1);
		$js .= &quota_javascript("uquota", $plan->{'uquota'}, "home",1);

		# Set limits
		$js .= &quota_javascript("mailboxlimit",$plan->{'mailboxlimit'},
					 "none", 1);
		$js .= &quota_javascript("aliaslimit", $plan->{'aliaslimit'},
					 "none", 1);
		$js .= &quota_javascript("dbslimit", $plan->{'dbslimit'},
					 "none", 1);
		if ($config{'bw_active'}) {
			$js .= &quota_javascript("bwlimit", $plan->{'bwlimit'},
						 "bw", 1);
			}
		$num = $plan->{'domslimit'} eq "" ? 1 :
		       $plan->{'domslimit'} eq "0" ? 0 : 2;
		$val = $num == 2 ? $plan->{'domslimit'} : "";
		$js .= "    var f = domain_form_target[0];\n";
		$js .= "    f.domslimit_def[$num].checked = true;\n";
		$js .= "    f.domslimit.value = \"$val\";\n";

		# Set no database name
		$js .= "    f.nodbname[".int($plan->{'nodbname'}).
		       "].checked = true;\n";
		}

	# Set features if configured
	if ($config{'plan_auto'}) {
		local @fl = $plan->{'featurelimits'} ?
				split(/\s+/, $plan->{'featurelimits'}) :
				@def_features;
		foreach $f (@dom_features, @fplugins) {
			$js .= "    if (domain_form_target[0]['$f']) {\n";
			$js .= "        domain_form_target[0]['$f'].checked = ".
			       (&indexof($f, @fl) >= 0 ? 1 : 0).";\n";
			$js .= "    }\n";
			}
		}
	$js .= "    }\n";
	}
$js .= "}\n";
$js .= "</script>\n";
print $js;

# Show template selection field
foreach $t (&list_available_templates($parentdom, $aliasdom)) {
	push(@opts, [ $t->{'id'}, $t->{'name'} ]);
	push(@cantmpls, $t);
	}
print &ui_table_row(&hlink($text{'form_template'},"template"),
	&ui_select("template", $deftmpl->{'id'}, \@opts, 1, 0,
		   0, 0, $config{'template_auto'} ? "" :
		"onChange='select_template(options[selectedIndex].value)'"),
	undef, \@tds);

# Show plan selection field, for top-level domains
if (!$parentdom) {
	foreach $p (sort { $a->{'name'} cmp $b->{'name'} }
			 &list_available_plans()) {
		push(@popts, [ $p->{'id'}, &html_escape($p->{'name'}) ]);
		}
	print &ui_table_row(&hlink($text{'form_plan'}, "plan"),
		&ui_select("plan", $defplan->{'id'}, \@popts, 1, 0, 0, 0,
			"onChange='select_plan(options[selectedIndex].value)'"),
		undef, \@tds);
	}

if ($aliasdom) {
	# Show destination of alias
	print &ui_table_row(&hlink($text{'form_aliasdom'}, "aliasdom"),
		"<a href='edit_domain.cgi?dom=$parentdom->{'id'}'>".
		"$aliasdom->{'dom'}</a>",
		undef, \@tds);
	}
elsif ($parentdom) {
	# Show parent domain
	print &ui_table_row(&hlink($text{'form_parentdom'}, "parentdom"),
		"<a href='edit_domain.cgi?dom=$parentdom->{'id'}'>".
		"$parentdom->{'dom'}</a> (<tt>$parentuser</tt>)",
		undef, \@tds);
	}

if (!$parentuser) {
	# Unix username
	print &ui_table_row(&hlink($text{'form_user'}, "unixusername"),
		&ui_opt_textbox("vuser", undef, 15,
				$text{'form_auto'}, $text{'form_nwuser'}),
		undef, \@tds);
	}

if (!$parentuser && $config{'force_email'}) {
	# Contact email address (if manadatory)
	print &ui_table_row(&hlink($text{'form_email'}, "ownersemail"),
		&ui_textbox("email", $config{'contact_email'}, 40),
		undef, \@tds);
	}

print &ui_hidden_table_end("basic");

# Start of advanced section
$has_advanced = $aliasdom ? 0 : 1;
if ($has_advanced) {
	print &ui_hidden_table_start($text{'form_advanced'}, "width=100%", 2,
				     "advanced", 0);
	}

# These settings are not needed for a sub-domain, as they come from the owner
if (!$parentuser) {
	# Contact email address (if optional)
	if (!$config{'force_email'}) {
		print &ui_table_row(&hlink($text{'form_email'}, "ownersemail"),
			&ui_opt_textbox("email", $config{'contact_email'}, 30,
					$text{'form_email_def'},
					$text{'form_email_set'}),
			undef, \@tds);
		}

	# Mail group name
	print &ui_table_row(&hlink($text{'form_mgroup'}, "mailgroupname"),
		&ui_opt_textbox("mgroup", undef, 15,
				$text{'form_auto'}, $text{'form_nwgroup'}),
		undef, \@tds);

	if (&can_choose_ugroup()) {
		# Group for Unix user
		local $ug = $deftmpl->{'ugroup'};
		$ug = "" if ($ug eq "none");
		print &ui_table_row(&hlink($text{'form_group'},"unixgroupname"),
			&ui_opt_textbox("group", $ug, 15,
					$text{'form_crgroup'},
					$text{'form_exgroup'}).
			&group_chooser_button("group"),
			undef, \@tds);
		}
	}

if (!$aliasdom) {
	# Show input for mail username prefix
	print &ui_table_row(&hlink($text{'form_prefix'}, "prefixname"),
		&ui_opt_textbox("prefix", undef, 15,
				$text{'form_auto'}),
		undef, \@tds);
	}
else {
	print &ui_hidden("prefix_def", 1),"\n";
	}

if (!$aliasdom && &database_feature() && &can_edit_databases() && !$subdom) {
	# Show database name field, iff this is not an alias or sub domain
	print &ui_table_row(&hlink($text{'form_dbname'},"dbname"),
		&ui_opt_textbox("db", undef, 15,
				$text{'form_auto'}),
		undef, \@tds);
	}

# Show reseller selection field
if (&can_edit_templates() && defined(&list_resellers) && !$parentdom) {
	@resels = &list_resellers();
	if (@resels) {
		 print &ui_table_row(&hlink($text{'form_reseller'},"dreseller"),
			&ui_select("reseller", undef,
				[ [ '', $text{'form_noreseller'} ],
				  map { $_->{'name'} } @resels ]));
		}
	}

# Show remote MySQL field
if (&can_edit_templates() && $config{'mysql'} && !$aliasdom && !$parentdom) {
	my @mymods = grep { !$_->{'config'}->{'virtualmin_provision'} }
			  &list_remote_mysql_modules();
	if (@mymods > 1) {
		print &ui_table_row(&hlink($text{'form_rmysql'}, "rmysql"),
		   &ui_select("rmysql",
			&get_default_mysql_module(),
			[ map { [ $_->{'minfo'}->{'dir'},
				  $_->{'desc'} ] } @mymods ]));
		}
	}

if ($has_advanced) {
	print &ui_hidden_table_end("advanced");
	}

# Show hidden section for limits
if (!$parentuser && !$config{'template_auto'}) {
	print &ui_hidden_table_start($text{'form_limits'}, "width=100%", 2,
				     "limits", 0);
	}

# Only display quota inputs if enabled, and if not creating a subdomain
if (&has_home_quotas() && !$parentuser && !$config{'template_auto'}) {
	print &ui_table_row(&hlink($text{'form_quota'}, "websitequota"),
		&opt_quota_input("quota", $defplan->{'quota'}, "home"),
		undef, \@tds);

	print &ui_table_row(&hlink($text{'form_uquota'}, "unixuserquota"),
		&opt_quota_input("uquota", $defplan->{'uquota'}, "home"),
		undef, \@tds);
	}

if (!$parentdom && $config{'bw_active'} && !$config{'template_auto'}) {
	# Show bandwidth limit field
	print &ui_table_row(&hlink($text{'edit_bw'}, "bwlimit"),
			    &bandwidth_input("bwlimit", $defplan->{'bwlimit'}),
			    undef, \@tds);
	}

if (!$parentuser && !$config{'template_auto'}) {
	# Show input for limit on number of mailboxes, aliases and DBs
	foreach $l ("mailbox", "alias", "dbs") {
		print &ui_table_row(
			&hlink($text{'form_'.$l.'limit'}, $l.'limit'),
			&ui_opt_textbox($l.'limit',
					$defplan->{$l.'limit'},
					4, $text{'form_unlimit'},
					$text{'form_atmost'}),
			undef, \@tds);
		}

	# Show input for restriction of number of sub-domains this domain
	# owner can create
	local $dlm = $defplan->{'domslimit'} eq '' ? 2 :
		     $defplan->{'domslimit'} eq '0' ? 1 : 2;
	print &ui_table_row(&hlink($text{'form_domslimit'}, "domslimit"),
		&ui_radio("domslimit_def", $dlm,
			  [ [ 1, $text{'form_nocreate'} ],
			    [ 2, $text{'form_unlimit'} ],
			    [ 0, $text{'form_atmost'} ] ])."\n".
		&ui_textbox("domslimit",
			    $dlm == 0 ? $config{'defdomslimit'} : "", 4),
		undef, \@tds);

	# Show input for default database name limit
	print &ui_table_row(&hlink($text{'limits_nodbname'}, "nodbname"),
		&ui_radio("nodbname", $defplan->{'nodbname'},
			  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]),
		undef, \@tds);
	}

if (!$parentuser && !$config{'template_auto'}) {
	print &ui_hidden_table_end("limits");
	}

# Show section for custom fields, if any
$fields = &show_custom_fields(undef, \@tds);
if ($fields) {
	print &ui_hidden_table_start($text{'edit_customsect'}, "width=100%", 2,
				     "custom", 1);
	print $fields;
	print &ui_hidden_table_end("custom");
	}

# Show checkboxes for features
print &ui_hidden_table_start($text{'edit_featuresect'}, "width=100%", 2,
			     "feature", 1);
@grid = ( );
@grid_order_initial = ( );
$i = 0;
$can_website = 0;
foreach $f (@dom_features) {
	# Don't allow access to features that this user hasn't been
	# granted for his subdomains.
	next if (!&can_use_feature($f));
	next if ($parentdom && $f eq "webmin");
	next if ($parentdom && $f eq "unix");
	next if ($aliasdom && !$aliasdom->{$f});
	next if (!$config{$f} && defined($config{$f}));		# Not enabled
	$can_feature{$f}++;
	$can_website = 1 if ($f eq 'web');

	if (&can_chained_feature($f, 1)) {
		# This feature is always on when some other feature is, so
		# don't show it
		next;
		}
	if (($f eq "dir" || $f eq "unix") && $config{$f} == 3) {
		# These features are always on for new domains
		print &ui_hidden($f, 1);
		next;
		}

	my $ftxt = $aliasdom ? $text{'form_alias'.$f} :
		   $parentdom ? $text{'form_sub'.$f} : undef;
	my $fhelp = $f;
	$fhelp = $f."_alias" if ($aliasdom && $ftxt);
	$ftxt ||= $text{'form_'.$f};
	push(@grid_order_initial, $f);
	push(@grid, &ui_checkbox($f, 1, "",
		$config{$f} == 1 && $in{'nofeat'} ne $f,
		&feature_check_chained_javascript($f)).
		    " <b>".&hlink($ftxt, $fhelp)."</b>");
	}

# Show checkboxes for plugins
@input_plugins = ( );
@fplugins = &list_feature_plugins() if (!$config{'plan_auto'});
foreach $f (@fplugins) {
	next if (!&plugin_call($f, "feature_suitable",
				$parentdom, $aliasdom, $subdom));
	next if (!&can_use_feature($f));
	$can_website = 1 if (&plugin_call($f, "feature_provides_web"));

	if (&can_chained_feature($f, 1)) {
		# This feature is always on when some other feature is, so
		# don't show it
		next;
		}

	$label = &plugin_call($f, "feature_label", 0);
	$label = " <b>$label</b>";
	$hlink = &plugin_call($f, "feature_hlink");
	$label = &hlink($label, $hlink, $f) if ($hlink);
	push(@grid_order_initial, $f);
	push(@grid, &ui_checkbox($f, 1, "", !$plugins_inactive{$f},
		&feature_check_chained_javascript($f)).$label);
	if (&plugin_call($f, "feature_inputs_show", undef)) {
		push(@input_plugins, $f);
		}
	}
features_sort(\@grid, \@grid_order_initial);
print &ui_table_row(undef, &vui_features_sorted_grid(\@grid), 4);
print &ui_hidden_table_end("feature");

# Show section for extra plugin options
if (@input_plugins) {
	print &ui_hidden_table_start($text{'form_inputssect'}, "width=100%", 2,
				     "inputs", 0, [ "width=30%" ]);
	foreach $f (@input_plugins) {
		&plugin_call($f, "load_theme_library");
		print &plugin_call($f, "feature_inputs", undef);
		}
	print &ui_hidden_table_end("inputs");
	}

# Start section for proxy and IP
print &ui_hidden_table_start($text{'form_proxysect'}, "width=100%", 2,
			     "proxy", 0, [ "width=30%" ]);

# Show inputs for setting up a proxy-only virtual server
if ($can_website && $config{'proxy_pass'} && !$aliasdom) {
	print &frame_fwd_input();
	}

# Show field for mail forwarding
if ($can_feature{'mail'} && !$aliasdom && !$subdom && &can_edit_catchall()) {
	print &ui_table_row(&hlink($text{'form_fwdto'}, "fwdto"),
		&ui_opt_textbox("fwdto", undef, 30, $text{'form_fwdto_none'}),
		undef, \@tds);
	}

# Show IP address allocation section
$resel = $parentdom ? $parentdom->{'reseller'} :
	 &reseller_admin() ? $base_remote_user : undef;
$defip = &get_default_ip($resel);
if ($aliasdom) {
	print &ui_table_row($text{'edit_ip'}, $aliasdom->{'ip'});
	}
elsif (!&can_select_ip()){
	print &ui_table_row($text{'edit_ip'},
		$access{'ipfollow'} && $parentdom ? $parentdom->{'ip'}
						  : $defip);
	}
else {
	my ($imode, $iip);
	if ($parentdom && &indexof($parentdom->{'ip'}, &list_shared_ips()) >= 0) {
		$imode = 3;
		$iip = $parentdom->{'ip'};
		}
	print &ui_table_row(&hlink($text{'form_iface'}, "iface"),
		&virtual_ip_input(\@cantmpls, $resel, undef, $imode, $iip),
		undef, \@tds);
	}

# Show IPv6 address allocation section
$defip6 = &get_default_ip6($resel);
if (!&supports_ip6()) {
	# Not supported
	print &ui_table_row($text{'edit_ip6'}, $text{'edit_noip6support'});
	}
elsif ($aliasdom) {
	# From alias domain
	print &ui_table_row($text{'edit_ip6'}, $aliasdom->{'ip6'} ||
					       $text{'edit_virt6off'});
	}
elsif (!&can_select_ip6()) {
	# User isn't allowed to select v6 address
	print &ui_table_row($text{'edit_ip6'},
		$access{'ipfollow'} && $parentdom ? $parentdom->{'ip6'} :
		$config{'ip6enabled'} && $defip6 ? $defip6 :
			$text{'edit_virt6off'});
	}
else {
	# Can select addres or allocate one
	print &ui_table_row(&hlink($text{'form_iface6'}, "iface6"),
		&virtual_ip6_input(\@cantmpls, $resel, 0,
				   $config{'ip6enabled'} ? 0 : -2),
		undef, \@tds);
	}

# Show DNS IPv4 address field
if (&can_dnsip()) {
	my $def_dns_ip4 = &get_external_ip_address(undef, 4) ||
			  &get_dns_ip($resel, 4);
	my $dns_ip4 = $parentdom ? $parentdom->{'dns_ip'} : undef;
	$dns_ip4 = undef if ($dns_ip4 eq $def_dns_ip4);
	my @opts;
	if ($def_dns_ip4) {
		push(@opts, [ 1, $text{'spf_default3'}, $def_dns_ip4 ]);
		push(@opts, [ 2, $text{'spf_default2'} ]);
		}
	else {
		push(@opts, [ 1, $text{'spf_default2'} ]);
		}
	push(@opts, [ 0, $text{'spf_custom'},
		      &ui_textbox("dns_ip", $dns_ip4, 20) ]);
	print &ui_table_row(&hlink($text{'edit_dnsip'}, "edit_dnsip"),
		&ui_radio_table("dns_ip_def", $dns_ip4 ? 0 : 1, \@opts));
	}

# Show DNS IPv6 address field
if (&can_dnsip() && &supports_ip6()) {
	my $def_dns_ip6 = &get_external_ip_address(undef, 6) ||
			  &get_dns_ip($resel, 6);
	my $dns_ip6 = $parentdom ? $parentdom->{'dns_ip6'} : undef;
	$dns_ip6 = undef if ($dns_ip6 eq $def_dns_ip6);
	my @opts;
	if ($def_dns_ip6) {
		push(@opts, [ 1, $text{'spf_default3'}, $def_dns_ip6 ]);
		push(@opts, [ 2, $text{'spf_default2'} ]);
		}
	else {
		push(@opts, [ 1, $text{'spf_default2'} ]);
		}
	push(@opts, [ 0, $text{'spf_custom'},
		      &ui_textbox("dns_ip6", $dns_ip6, 40) ]);
	print &ui_table_row($text{'edit_dnsip6'},
		&ui_radio_table("dns_ip6_def", $dns_ip6 ? 0 : 1, \@opts));
	}

print &ui_hidden_table_end();

if ($can_website && !$aliasdom && $virtualmin_pro &&
    $deftmpl->{'content_web'} == 3) {
	# Show field for initial content
	print &ui_hidden_table_start($text{'form_park'}, "width=100%", 2,
				     "park", 0);

	# Initial content
	print &ui_table_row(&hlink($text{'form_content'},"form_content"),
			    &ui_radio("content_def", 2,
				      [ [ 1, $text{'form_content1'} ],
					[ 2, $text{'form_content2'} ],
					[ 0, $text{'form_content0'} ] ])."<br>".
			    &ui_textarea("content", undef, 5, 70),
			    3, \@tds);

	print &ui_hidden_table_end();
	}
print &ui_form_end([ [ "ok", $text{'form_ok'} ] ]);
if (!$config{'template_auto'}) {
	print "<script data-nocache>select_template($deftmpl->{'id'});</script>\n";
	}
if (!$parentdom) {
	print "<script data-nocache>select_plan($defplan->{'id'});</script>\n";
	}

&ui_print_footer("", $text{'index_return'});
