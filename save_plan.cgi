#!/usr/local/bin/perl
# Create, update or delete a plan

require './virtual-server-lib.pl';
&ReadParse();
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});
&error_setup($text{'plan_err'});

# Get the plan being edited
if (!$in{'new'}) {
	@plans = &list_editable_plans();
	($plan) = grep { $_->{'id'} eq $in{'id'} } @plans;
	$plan || &error($text{'plan_ecannot'});
	}
else {
	$plan = { };
	if ($canplans == 1) {
		$plan->{'owner'} = $base_remote_user;
		}
	}

if ($in{'delete'}) {
	# Just remove this plan
	&delete_plan($plan);
	&webmin_log("delete", "plan", $plan->{'id'}, $plan);
	}
else {
	# Validate and store inputs
	$in{'name'} =~ /\S/ || &error($text{'plan_ename'});
	$plan->{'name'} = $in{'name'};

	# Save quota limits
	if ($in{'quota_def'} == 1) {
		$plan->{'quota'} = undef;
		}
	else {
		$in{'quota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_equota'});
		$plan->{'quota'} = &quota_parse("quota", "home");
		}
	if ($in{'uquota_def'} == 1) {
		$plan->{'uquota'} = undef;
		}
	else {
		$in{'uquota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_euquota'});
		$plan->{'uquota'} = &quota_parse("uquota", "home");
		}

	# Save limits on various objects
	foreach my $l ("mailbox", "alias", "dbs", "doms", "aliasdoms",
		       "realdoms", $virtualmin_pro ? ( "mongrels" ) : ( )) {
		if ($in{$l."limit_def"}) {
			$plan->{$l.'limit'} = undef;
			}
		else {
			$in{$l.'limit'} =~ /^\d+$/ ||
				&error($text{'plan_e'.$l.'limit'});
			$plan->{$l.'limit'} = $in{$l.'limit'};
			}
		}
	if ($in{"bwlimit_def"} == 1) {
		$plan->{'bwlimit'} = undef;
		}
	else {
		$plan->{'bwlimit'} = &parse_bandwidth("bwlimit",
					$text{'plan_e'.$l.'limit'}, 1);
		}

	# Save no database name and no rename
	$plan->{'nodbname'} = $in{'nodbname'};
	$plan->{'norename'} = $in{'norename'};
	$plan->{'forceunder'} = $in{'forceunder'};

	# Save feature limits
	if ($in{'featurelimits_def'} == 1) {
		# Default
		$plan->{'featurelimits'} = undef;
		}
	else {
		# Explicitly selected
		$in{'featurelimits'} || &error($text{'plan_efeaturelimits'});
		$plan->{'featurelimits'} =
			join(" ", split(/\0/, $in{'featurelimits'}));
		}

	# Save capability limits
	if ($in{'capabilities_def'} == 1) {
		# Default
		$plan->{'capabilities'} = undef;
		}
	else {
		# Explicitly selected
		$plan->{'capabilities'} =
			join(" ", split(/\0/, $in{'capabilities'}));
		}

	# Save resellers it is visible to
	if (defined($in{'resellers_def'})) {
		if ($in{'resellers_def'} == 1) {
			$plan->{'resellers'} = undef;
			}
		elsif ($in{'resellers_def'} == 2) {
			$plan->{'resellers'} = 'none';
			}
		else {
			$plan->{'resellers'} =
				join(' ', split(/\0/, $in{'resellers'}));
			$plan->{'resellers'} ||
				&error($text{'plan_eresellers'});
			}
		}

	# Save the plan object
	&save_plan($plan);

	if (!$in{'new'} && $in{'apply'}) {
		# Apply to all domains on the plan
		&set_all_null_print();
		foreach my $d (&get_domain_by("plan", $plan->{'id'})) {
			next if ($d->{'parent'});
			local $oldd = { %$d };
			&set_limits_from_plan($d, $plan);
			&set_featurelimits_from_plan($d, $plan);
			&set_capabilities_from_plan($d, $plan);
			&modify_webmin($d, $oldd);
			}
		&run_post_actions();
		}

	&webmin_log($in{'new'} ? 'create' : 'modify', 'plan',
		    $plan->{'id'}, $plan);
	}
&redirect("edit_newplan.cgi");

