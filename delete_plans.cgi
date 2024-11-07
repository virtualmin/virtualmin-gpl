#!/usr/local/bin/perl
# Delete one or more selected plans

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($in{'default'} ? $text{'dplans_err2'} : $text{'dplans_err'});
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});

@d = split(/\0/, $in{'d'});
@d || &error($text{'dplans_enone'});

if ($in{'delete'}) {
	# Get the plans and remove them
	@plans = &list_editable_plans();
	@allplans = &list_plans();
	foreach $d (@d) {
		($plan) = grep { $_->{'id'} eq $d } @plans;
		if ($plan) {
			@allplans = grep { $_->{'id'} ne $d } @allplans;
			@allplans || &error($text{'dplans_eall'});
			&delete_plan($plan);
			}
		}

	# Log and return
	&run_post_actions_silently();
	&webmin_log("delete", "plans", scalar(@d));
	}
else {
	# Get the selected plan and make it the default
	$plan = &get_plan($d[0]);
	$plan && !$plan->{'deleted'} && &can_use_plan($plan) ||
                &error($text{'plans_esetdef'});
	&set_default_plan($plan);
	&run_post_actions_silently();
	&webmin_log("default", "plan", $plan->{'id'}, $plan);
	}
&redirect("edit_newplan.cgi");

