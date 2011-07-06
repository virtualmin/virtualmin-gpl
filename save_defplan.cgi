#!/usr/local/bin/perl
# Just set the default plan for the current user

require './virtual-server-lib.pl';
&ReadParse();
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});

if ($in{'plan'} eq '') {
	&set_default_plan(undef);
	&webmin_log("nodefault", "plan");
	}
else {
	$plan = &get_plan($in{'plan'});
	$plan && !$plan->{'deleted'} && &can_use_plan($plan) ||
		&error($text{'plans_esetdef'});
	&set_default_plan($plan);
	&webmin_log("default", "plan", $plan->{'id'}, $plan);
	}
&run_post_actions_silently();
&redirect("edit_newplan.cgi");

