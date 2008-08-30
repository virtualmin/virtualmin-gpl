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
if ($in{'wurl_def'}) {
	delete($config{'scriptwarn_url'});
	}
else {
	$in{'wurl'} =~ /^(http|https):\/\/\S+$/ ||
		&error($text{'newscripts_ewurl'});
	$config{'scriptwarn_url'} = $in{'wurl'};
	}
$config{'scriptwarn_notify'} = $in{'wnotify'};
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
		 'active' => 1 };
	&apply_warning_schedule($job, $in{'wsched'} || 'daily');
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}
elsif ($job && $in{'enabled'} && $in{'wsched'} &&
       $in{'wsched'} ne $in{'old_wsched'}) {
	# Update schedule if possible
	&apply_warning_schedule($job, $in{'wsched'});
	&lock_file(&cron::cron_file($job));
	&cron::change_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}
&cron::create_wrapper($scriptwarn_cron_cmd, $module_name,
		      "scriptwarn.pl");

# Return
&webmin_log("warn", "scripts");
&redirect("edit_newscripts.cgi?mode=warn");

# Set the schedule based on the user's selections
sub apply_warning_schedule
{
my ($job, $sched) = @_;
$job->{'mins'} = int(rand()*60);
$job->{'hours'} = 0;
if ($sched eq 'daily') {
	$job->{'days'} = $job->{'months'} = $job->{'weekdays'} = '*';
	}
elsif ($sched eq 'weekly') {
	$job->{'weekdays'} = '1';
	$job->{'months'} = $job->{'days'} = '*';
	}
elsif ($sched eq 'monthly') {
	$job->{'days'} = '1';
	$job->{'months'} = $job->{'weekdays'} = '*';
	}
}

