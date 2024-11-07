#!/usr/local/bin/perl
# save_domain.cgi
# Update or delete a domain

require './virtual-server-lib.pl';
&require_bind() if ($config{'dns'});
&require_useradmin();
&require_mail() if ($config{'mail'});
&ReadParse();
&licence_status();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
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

# Check if the prefix has been changed
if (defined($in{'prefix'})) {
	$in{'prefix'} =~ /^[a-z0-9\.\-\_]+$/i ||
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

# Check email format
if (!$in{'email_def'} && !$d->{'parent'}) {
	&extract_address_parts($in{'email'}) || &error($text{'setup_eemail3'});
	}

# Check domain for use in links
if ($in{'linkdom'}) {
	$linkd = &get_domain($in{'linkdom'});
	$linkd || &error($text{'edit_elinkdom'});
	$linkd->{'alias'} eq $d->{'id'} ||
		&error($text{'edit_elinkdom2'});
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
my @forbidden_domain_features = &forbidden_domain_features($d);
if (!$d->{'disabled'}) {
	foreach $f (@dom_features, &list_feature_plugins()) {
		if ($in{$f}) {
			if (grep {$_ eq $f} @forbidden_domain_features) {
				&error(&text('setup_efeatforbidhostdef',
					"<tt>@{[&html_escape($f)]}</tt>"));
				}
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
	foreach my $r (split(/\s+/, $d->{'reseller'})) {
		$rinfo = &get_reseller($r);
		next if (!$rinfo);
		if (!$d->{'parent'} &&
		    ($newdom{'quota'} eq '' || $newdom{'quota'} eq '0') &&
		    $rinfo->{'acl'}->{'max_quota'}) {
			&error(&text('save_erquota', $r));
			}
		if (!$d->{'parent'} &&
		    ($newdom{'bw_limit'} eq '' || $newdom{'bw_limit'} eq '0') &&
		    $rinfo->{'acl'}->{'max_bw'}) {
			&error(&text('save_erbw', $r));
			}
		}
	}

# Check if any features are being deleted, and if so ask the user if
# he is sure
if (!$in{'confirm'} && !$d->{'disabled'}) {
	# Collect features and plugins being disabled
	local (@alosing, @losing, @plosing);
	foreach $f (@dom_features) {
		if ($config{$f} && $d->{$f} && !$newdom{$f}) {
			push(@alosing, $f);
			if (!&can_chained_feature($f, 1)) {
				push(@losing, $f);
				}
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($d->{$f} && !$newdom{$f}) {
			if (!&can_chained_feature($f, 1)) {
				push(@plosing, $f);
				}
			}
		}

	# Check if any alias domains use a feature being disabled
	local @ausers;
	foreach my $ad (&get_domain_by("alias", $d->{'id'})) {
		foreach $f (@alosing) {
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
		features_sort(\@losing, \@losing) if (@losing);
		foreach $f (@losing) {
			my $msg = $d->{'parent'} ? $text{"sublosing_$f"}
						 : undef;
			my $msuf = $f eq 'dir' && $d->{'alias'} ? 4 : 
				   $f eq 'dir' && $d->{'parent'} ? 2 : "";
			$msg ||= $text{"losing_$f$msuf"};
			print "<li>",$text{'feature_'.$f}," - ",$msg,"<br>\n";
			}
		features_sort(\@plosing, \@plosing) if (@plosing);
		foreach $f (@plosing) {
			print "<li>",&plugin_call($f, "feature_name")," - ",
			     &plugin_call($f, "feature_losing"),"<br>\n";
			}
		print "</ul>\n";

		print &check_clicks_function();
		print "<center>";
		print &ui_form_start("save_domain.cgi", "post");
		foreach $k (keys %in) {
			foreach $v (split(/\0/, $in{$k})) {
				print "<input type=hidden name=$k value='",
				      &html_escape($v),"'>\n";
				}
			}

		print &ui_form_end(
			[ [ "confirm",
		        $text{'save_dok_rmfeatures'},
		        undef, undef,
		        "onClick='check_clicks(form)'" ]
		    ]);
		print "</center>\n";

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
	
	# Password was changed and we need to
	# check if passwords should be hashed
	my $hashmode = $in{'hashpass_enable'} ? 1 : 0;
	my $updated_domain_hashpass = &update_domain_hashpass($d, $hashmode);

	$d->{'pass'} = $in{'passwd'};
	$d->{'pass_set'} = 1;	# indicates that the password has been changed
	&generate_domain_password_hashes($d, 0);

	# Clean after hashpass switch
	if ($updated_domain_hashpass) {
		&post_update_domain_hashpass($d, $hashmode, $in{'passwd'});
		}
	}
else {
	$d->{'pass_set'} = 0;
	}
if (!$d->{'parent'}) {
	$d->{'email'} = $in{'email_def'} ? undef : $in{'email'};
	&compute_emailto($d);
	}

# Set domain protection if allowed
if (&master_admin() || (&reseller_admin() && !$access{'nodelete'}) ||
    $access{'edit_delete'} || $access{'edit_disable'}) {
	my $protected_status = $in{'protected'} ? 1 : 0;
	if (defined($d->{'protected'}) &&
	    $d->{'protected'} ne $in{'protected'}) {
		&$first_print($text{"save_protected$protected_status"});
		&$second_print($text{'setup_done'});
		}
	$d->{'protected'} = $protected_status;
	}

# Update quotas in domain object
if (&has_home_quotas() && !$d->{'parent'} && &can_edit_quotas($d)) {
	$d->{'uquota'} = $newdom{'uquota'};
	$d->{'quota'} = $newdom{'quota'};
	}

# Update password and email in subdomains
foreach $sd (&get_domain_by("parent", $d->{'id'})) {
	$sd->{'pass'} = $d->{'pass'};
	$sd->{'email'} = $d->{'email'};
	$sd->{'emailto'} = $d->{'emailto'};
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
	&set_plan_on_children($d);
	&$second_print($text{'setup_done'});
	}

# Update prefix
if (defined($in{'prefix'}) && $in{'prefix'} ne $d->{'prefix'}) {
	$d->{'prefix'} = $in{'prefix'};
	}

# Update domain for use in links
if (defined($in{'linkdom'})) {
	$d->{'linkdom'} = $in{'linkdom'};
	}

if (!$d->{'disabled'}) {
	# Enable or disable features
	my $f;
	my $oldcount = 0;
	my $newcount = 0;
	foreach $f (@dom_features) {
		if ($config{$f}) {
			$oldcount++ if ($d->{$f});
			$d->{$f} = $newdom{$f};
			$newcount++ if ($d->{$f});
			}
		}
	foreach $f (&list_feature_plugins()) {
		$oldcount++ if ($d->{$f});
		$d->{$f} = $newdom{$f};
		$newcount++ if ($d->{$f});
		}
	my @of = &list_ordered_features($d);
	if ($oldcount > $newcount) {
		# Features were removed, so call the setup/delete functions
		# in reverse order
		@of = reverse(@of);
		}
	foreach $f (@of) {
		&call_feature_func($f, $d, $oldd);
		}
	}
else {
	# Only modify unix if domain is disabled
	if ($d->{'unix'}) {
		&modify_unix($d, $oldd);
		}
	}

# Update the parent user
&refresh_webmin_user($d);

# Update custom fields
&parse_custom_fields($d, \%in);

# Save new domain details
print $text{'save_domain'},"<br>\n";
&save_domain($d);
&$second_print($text{'setup_done'});

# If the IP has changed, update any alias domains too
if ($d->{'ip'} ne $oldd->{'ip'} ||
    $d->{'ip6'} ne $oldd->{'ip6'}) {
	&update_alias_domain_ips($d, $oldd);
	}

# If the template has changed, update secondary groups
if ($d->{'template'} ne $oldd->{'template'}) {
	&update_domain_owners_group(undef, $oldd);
	&update_domain_owners_group($d, undef);
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

