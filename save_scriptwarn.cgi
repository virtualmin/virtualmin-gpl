#!/usr/local/bin/perl
# Enable or disable the cron job for sending script upgrade notifications

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ReadParse();
&error_setup($text{'newscripts_werr'});

# Validate and save inputs
%email = map { $_, 1 } split(/\0/, $in{'wemail'});
push(@email, "owner") if ($email{'owner'});
push(@email, "reseller") if ($email{'reseller'});
if ($email{'other'}) {
	$in{'wother'} =~ /^\S+\@\S+$/ || &error($text{'newscripts_ewother'});
	push(@email, $in{'wother'});
	}
if ($in{'enabled'}) {
	@email || &error($text{'newscripts_ewnone'});
	}
$config{'scriptwarn_email'} = join(" ", @email);
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

# Create or remove cron job
&foreign_require("cron", "cron-lib.pl");
$job = &find_scriptwarn_job();
if ($job && !$in{'enabled'}) {
	# Delete job
	&lock_file(&cron::cron_file($job));
	&cron::delete_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}
elsif (!$job && $in{'enabled'}) {
	# Create daily job
	$job = { 'user' => 'root',
		 'command' => $scriptwarn_cron_cmd,
		 'active' => 1,
		 'mins' => int(rand()*60),
		 'hours' => 0,
		 'days' => '*',
		 'months' => '*',
		 'weekdays' => '*' };
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	&cron::create_wrapper($scriptwarn_cron_cmd, $module_name,
			      "scriptwarn.pl");
	}

# Return
&webmin_log("warn", "scripts");
&redirect("edit_newscripts.cgi?mode=warn");

