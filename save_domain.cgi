#!/usr/local/bin/perl
# save_domain.cgi
# Update or delete a domain

require './virtual-server-lib.pl';
&require_bind() if ($config{'dns'});
&require_useradmin();
&require_mail() if ($config{'mail'});
&ReadParse();
$d = &get_domain($in{'dom'});
&can_config_domain($d) || &error($text{'edit_ecannot'});
$oldd = { %$d };
$tmpl = &get_template($in{'template'});

# Validate inputs
&error_setup($text{'save_err'});
if (&has_home_quotas() && !$d->{'parent'} && &can_edit_quotas($d)) {
	if ($in{'quota'} eq -1) { $in{'quota'} = $in{'otherquota'} };
	if ($in{'uquota'} eq -1) { $in{'uquota'} = $in{'otheruquota'} };
	$in{'quota_def'} || $in{'quota'} =~ /^[0-9\.]+$/ ||
		&error($text{'save_equota'});
	$in{'uquota_def'} || $in{'uquota'} =~ /^[0-9\.]+$/ ||
		&error($text{'save_euquota'});
	}
if ($config{'bw_active'} && !$d->{'parent'} && &can_edit_bandwidth()) {
	$d->{'bw_limit'} = &parse_bandwidth("bw", $text{'save_ebwlimit'});
	if ($config{'bw_disable'}) {
		$d->{'bw_no_disable'} = $in{'bw_no_disable'};
		}
	}
$d->{'db'} = &database_name($d) if (!$d->{'db'});
if ($d->{'template'} != $tmpl->{'id'}) {
	$d->{'template'} = $tmpl->{'id'};
	if (!&master_admin() && !&reseller_admin() && !$t->{'for_users'} ||
	    !&can_use_template($t)) {
		# Cannot use this template!
		&error($text{'save_etemplate'});
		}
	}
$in{'owner'} =~ /:/ && &error($text{'setup_eowner'});

# Check if the prefix has been changed
if (defined($in{'prefix'})) {
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
		&error($text{'setup_eprefix'});
	if ($in{'prefix'} ne $d->{'prefix'}) {
		$pclash = &get_domain_by("prefix", $in{'prefix'});
                $pclash && &error($text{'setup_eprefix2'});
		$d->{'prefix'} = $in{'prefix'};
		}
	}

# Check if the password was changed, and if so is it valid
if (!$d->{'parent'} && !$in{'passwd_def'}) {
	local $fakeuser = { 'user' => $d->{'user'},
			    'plainpass' => $in{'passwd'} };
	$err = &check_password_restrictions($fakeuser, $d->{'webmin'});
	&error($err) if ($err);
	}

# Work out which features are relevant
@dom_features = &domain_features($d);

# Work around possible bad 'db' name
if (!$d->{'mysql'} && $in{'mysql'} && &check_mysql_clash($d, 'db')) {
	$d->{'db'} = &database_name($d);
	}

# Check for various clashes
%newdom = %$d;
if (&has_home_quotas() && !$d->{'parent'} && &can_edit_quotas($d)) {
	$newdom{'uquota'} = $in{'uquota_def'} ? undef :
				&quota_parse('uquota', "home");
	$newdom{'quota'} = $in{'quota_def'} ? undef :
				&quota_parse('quota', "home");
	}
if (!$d->{'disabled'}) {
	foreach $f (@dom_features, @feature_plugins) {
		if ($in{$f}) {
			$newdom{$f} = 1;
			if (!$d->{$f}) {
				$check{$f}++;
				}
			}
		else {
			$newdom{$f} = 0;
			}
		}
	&set_chained_features(\%newdom, $d);
	}
if (!$config{'all_namevirtual'} && !$d->{'alias'} && &can_use_feature("virt")) {
	$newdom{'virt'} = $in{'virt'};
	}
$derr = &virtual_server_depends(\%newdom);
&error($derr) if ($derr);
$cerr = &virtual_server_clashes(\%newdom, \%check);
&error($cerr) if ($cerr);
$lerr = &virtual_server_limits(\%newdom, $oldd);
&error($lerr) if ($lerr);

if (!$d->{'alias'} && &can_use_feature("virt")) {
	if ($config{'all_namevirtual'}) {
		# Make sure any new IP *is* assigned
		&check_ipaddress($in{'ip'}) || &error($text{'setup_eip'});
		if ($d->{'ip'} ne $in{'ip'} && !&check_virt_clash($in{'ip'})) {
			&error(&text('setup_evirtclash2'));
			}
		}
	elsif ($in{'virt'} && !$d->{'virt'}) {
		# An IP is being added
		local %racl = $d->{'reseller'} ?
			&get_reseller_acl($d->{'reseller'}) : ();
		if ($racl{'ranges'}) {
			# Allocate the IP from the server's reseller's range
			$in{'ip'} = &free_ip_address(\%racl);
			$in{'ip'} || &text('setup_evirtalloc2');
			}
		elsif ($tmpl->{'ranges'} ne "none") {
			# Allocate the IP from the template
			$in{'ip'} = &free_ip_address($tmpl);
			$in{'ip'} || &text('setup_evirtalloc');
			}
		else {
			# Make sure the IP isn't assigned yet
			&check_ipaddress($in{'ip'}) ||
				&error($text{'setup_eip'});
			if (&check_virt_clash($in{'ip'})) {
				&error(&text('setup_evirtclash'));
				}
			}
		}
	}

# Check if any features are being deleted, and if so ask the user if
# he is sure
if (!$in{'confirm'} && !$d->{'disabled'}) {
	local @losing;
	foreach $f (@dom_features) {
		if ($config{$f} && $d->{$f} && !$newdom{$f}) {
			push(@losing, $f);
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f} && !$newdom{$f}) {
			push(@plosing, $f);
			}
		}
	if (@losing || @plosing) {
		&ui_print_header(&domain_in($d), $text{'save_title'}, "");

		print "<p>",&text('save_rusure',"<tt>$d->{'dom'}</tt>"),"<p>\n";
		print "<ul>\n";
		local $pfx = $d->{'parent'} ? "sublosing_" : "losing_";
		foreach $f (@losing) {
			print "<li>",$text{'feature_'.$f}," - ",
				     $text{$pfx.$f},"<br>\n";
			}
		foreach $f (@plosing) {
			print "<li>",&plugin_call($f, "feature_name")," - ",
			     &plugin_call($f, "feature_losing"),"<br>\n";
			}
		print "</ul>\n";

		print &check_clicks_function();
		print "<center><form action=save_domain.cgi>\n";
		foreach $k (keys %in) {
			foreach $v (split(/\0/, $in{$k})) {
				print "<input type=hidden name=$k value='",
				      &html_escape($v),"'>\n";
				}
			}
		print "<input type=submit name=confirm ",
		      "value='$text{'save_dok'}' ",
		      "onClick='check_clicks(form)'>\n";
		print "</form></center>\n";

		&ui_print_footer(&domain_footer_link($d),
			"", $text{'index_return'});
		exit;
		}
	}

# Make the changes
&ui_print_unbuffered_header(&domain_in($d), $text{'save_title'}, "");

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN");
$merr = &making_changes();
&reset_domain_envs($d);
&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Update description, password and quotas in domain object
$d->{'owner'} = $in{'owner'};
if (!$in{'passwd_def'}) {
	if ($d->{'disabled'}) {
		# Clear any saved passwords, as they should
		# be reset at this point
		$d->{'disabled_mysqlpass'} = undef;
		$d->{'disabled_postgrespass'} = undef;
		}
	$d->{'pass'} = $in{'passwd'};
	$d->{'pass_set'} = 1;	# indicates that the password has been changed
	}
else {
	$d->{'pass_set'} = 0;
	}
$d->{'email'} = $in{'email_def'} ? undef : $in{'email'};

# Update quotas in domain object
if (&has_home_quotas() && !$d->{'parent'} && &can_edit_quotas($d)) {
	$d->{'uquota'} = $newdom{'uquota'};
	$d->{'quota'} = $newdom{'quota'};
	}

# Update password and email in subdomains
foreach $sd (&get_domain_by("parent", $d->{'id'})) {
	$sd->{'pass'} = $d->{'pass'};
	$sd->{'email'} = $d->{'email'};
	}

if (&can_use_feature("virt")) {
	if ($config{'all_namevirtual'} && !$d->{'alias'}) {
		# Possibly changing IP
		$d->{'ip'} = $in{'ip'};
		$d->{'defip'} = $d->{'ip'} eq &get_default_ip();
		delete($d->{'dns_ip'});
		}
	elsif ($in{'virt'} && !$d->{'virt'}) {
		# Need to bring up IP
		$d->{'ip'} = $in{'ip'};
		$d->{'virt'} = 1;
		$d->{'name'} = 0;
		$d->{'virtalready'} = 0;
		delete($d->{'dns_ip'});
		delete($d->{'defip'});
		&setup_virt($d);
		}
	elsif (!$in{'virt'} && $d->{'virt'}) {
		# Need to take down IP, and revert to default
		$d->{'ip'} = &get_default_ip($d->{'reseller'});
		$d->{'defip'} = $d->{'ip'} eq &get_default_ip();
		$d->{'virt'} = 0;
		$d->{'virtalready'} = 0;
		$d->{'name'} = 1;
		delete($d->{'dns_ip'});
		&delete_virt($d);
		}
	if ($d->{'alias'} && !$d->{'ip'}) {
		# IP lost bug to bug! Fix it up ..
		$aliasdom = &get_domain($d->{'alias'});
		$d->{'ip'} = $aliasdom->{'ip'};
		}
	}

if (!$d->{'disabled'}) {
	# Enable or disable features
	my $f;
	foreach $f (@dom_features) {
		if ($config{$f}) {
			$d->{$f} = $newdom{$f};
			}
		}
	foreach $f (@feature_plugins) {
		$d->{$f} = $newdom{$f};
		}
	foreach $f (@dom_features, @feature_plugins) {
		&call_feature_func($f, $d, $oldd);
		}
	}
else {
	# Only modify unix if disabled
	if ($d->{'unix'}) {
		&modify_unix($d, $oldd);
		}
	}

# Update the parent user
if ($d->{'parent'}) {
	&refresh_webmin_user(&get_domain($d->{'parent'}));
	}

# Update custom fields
&parse_custom_fields($d, \%in);

# Update alias copy mode
# Save new domain details
print $text{'save_domain'},"<br>\n";
&save_domain($d);
print $text{'setup_done'},"<p>\n";

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN");
&made_changes();
&reset_domain_envs($d);
&webmin_log("modify", "domain", $d->{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

&ui_print_footer("edit_domain.cgi?dom=$in{'dom'}", $text{'edit_return'},
	"", $text{'index_return'});

