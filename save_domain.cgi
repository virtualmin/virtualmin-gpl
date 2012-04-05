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
$tmpl = defined($in{'template'}) ? &get_template($in{'template'})
				 : &get_template($d->{'template'});

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
	if (!&master_admin() && !&reseller_admin() && !$tmpl->{'for_users'} ||
	    !&can_use_template($tmpl)) {
		# Cannot use this template!
		&error($text{'save_etemplate'});
		}
	}
$in{'owner'} =~ /:/ && &error($text{'setup_eowner'});
if (!$d->{'parent'} && defined($in{'plan'})) {
	$plan = &get_plan($in{'plan'});
	&can_use_plan($plan) || &error($text{'setup_eplan'});
	}

# Check external IP
if (&can_dnsip()) {
	$in{'dns_ip_def'} || &check_ipaddress($in{'dns_ip'}) ||
		&error($text{'save_ednsip'});
	}

# Check if the prefix has been changed
if (defined($in{'prefix'})) {
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
		&error($text{'setup_eprefix'});
	if ($in{'prefix'} ne $d->{'prefix'}) {
		$pclash = &get_domain_by("prefix", $in{'prefix'});
                $pclash && &error($text{'setup_eprefix2'});
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

# Work around possible clashing 'db' name, if domain was renamed after
# creation and then a DB was enabled
if (!$d->{'mysql'} && $in{'mysql'} &&
    &check_mysql_database_clash($d, $d->{'db'})) {
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
	foreach $f (@dom_features, &list_feature_plugins()) {
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
$derr = &virtual_server_depends(\%newdom, undef, $oldd);
&error($derr) if ($derr);
$cerr = &virtual_server_clashes(\%newdom, \%check);
&error($cerr) if ($cerr);
$lerr = &virtual_server_limits(\%newdom, $oldd);
&error($lerr) if ($lerr);

# Check if quota makes sense for reseller
if ($d->{'reseller'} && defined(&get_reseller)) {
	$r = &get_reseller($d->{'reseller'});
	if (!$d->{'parent'} &&
	    ($newdom{'quota'} eq '' || $newdom{'quota'} eq '0') &&
	    $r && $r->{'acl'}->{'max_quota'}) {
		&error(&text('save_erquota', $d->{'reseller'}));
		}
	if (!$d->{'parent'} &&
	    ($newdom{'bw_limit'} eq '' || $newdom{'bw_limit'} eq '0') &&
	    $r && $r->{'acl'}->{'max_bw'}) {
		&error(&text('save_erbw', $d->{'reseller'}));
		}
	}


# Check if any features are being deleted, and if so ask the user if
# he is sure
if (!$in{'confirm'} && !$d->{'disabled'}) {
	# Collect features and plugins being disabled
	local (@losing, @plosing);
	foreach $f (@dom_features) {
		if ($config{$f} && $d->{$f} && !$newdom{$f}) {
			push(@losing, $f);
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($d->{$f} && !$newdom{$f}) {
			push(@plosing, $f);
			}
		}

	# Check if any alias domains use a feature being disabled
	local @ausers;
	foreach my $ad (&get_domain_by("alias", $d->{'id'})) {
		foreach $f (@losing) {
			if ($ad->{$f}) {
				push(@ausers, $ad);
				}
			}
		}
	if (@ausers) {
		&error(&text('save_aliasusers',
			join(" ", map { &show_domain_name($_) } @ausers)));
		}

	# Ask for confirmation
	if (@losing || @plosing) {
		&ui_print_header(&domain_in($d), $text{'save_title'}, "");

		print "<p>",&text('save_rusure',"<tt>$d->{'dom'}</tt>"),"<p>\n";
		print "<ul>\n";
		foreach $f (@losing) {
			my $msg = $d->{'parent'} ? $text{"sublosing_$f"}
						 : undef;
			$msg ||= $text{"losing_$f"};
			print "<li>",$text{'feature_'.$f}," - ",$msg,"<br>\n";
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

# Check if this change would trigger any warnings
if (&show_virtual_server_warnings(\%newdom, $oldd, \%in)) {
	&ui_print_footer("", $text{'index_return'});
	return;
	}

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN", \%newdom);
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
	&generate_domain_password_hashes($d, 0);
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

# Update plan if changed
if ($plan && $plan->{'id'} ne $d->{'plan'}) {
	if ($in{'applyplan'}) {
		print &text('save_applyplan',
			    &html_escape($plan->{'name'})),"<br>\n";
		&set_limits_from_plan($d, $plan);
		&set_featurelimits_from_plan($d, $plan);
		&set_capabilities_from_plan($d, $plan);
		}
	else {
		print &text('save_plan',
			    &html_escape($plan->{'name'})),"<br>\n";
		}
	$d->{'plan'} = $plan->{'id'};
	print $text{'setup_done'},"<p>\n";
	}

# Update DNS IP
if (&can_dnsip()) {
	if ($in{'dns_ip_def'}) {
		delete($d->{'dns_ip'});
		}
	else {
		$d->{'dns_ip'} = $in{'dns_ip'};
		}
	}

# Update prefix
if (defined($in{'prefix'}) && $in{'prefix'} ne $d->{'prefix'}) {
	$d->{'prefix'} = $in{'prefix'};
	}

if (!$d->{'disabled'}) {
	# Enable or disable features
	my $f;
	foreach $f (@dom_features) {
		if ($config{$f}) {
			$d->{$f} = $newdom{$f};
			}
		}
	foreach $f (&list_feature_plugins()) {
		$d->{$f} = $newdom{$f};
		}
	foreach $f (&list_ordered_features($d)) {
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
else {
	&refresh_webmin_user($d);
	}

# Update custom fields
&parse_custom_fields($d, \%in);

# Save new domain details
print $text{'save_domain'},"<br>\n";
&save_domain($d);
print $text{'setup_done'},"<p>\n";

# If the IP has changed, update any alias domains too
if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'ip6'} ne $oldd->{'ip6'}) {
	&update_alias_domain_ips($d, $oldd);
	}

# If the template has changed, update secondary groups
if ($d->{'template'} ne $oldd->{'template'}) {
	&update_secondary_groups($d);
	}

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);
&webmin_log("modify", "domain", $d->{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

&ui_print_footer("edit_domain.cgi?dom=$in{'dom'}", $text{'edit_return'},
	"", $text{'index_return'});

