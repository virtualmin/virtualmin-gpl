#!/usr/local/bin/perl
# Set up regular validation

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newvalidate_err2'});
&can_edit_templates() || &error($text{'newvalidate_ecannot'});

# Validate inputs
$oldjob = $job = &find_validate_job();
$job ||= { 'user' => 'root',
	   'active' => 1,
	   'command' => $validate_cron_cmd };
if ($in{'sched'}) {
	$in{'email'} =~ /^\S+\@\S+$/ || &error($text{'newquotas_eemail'});
	&virtualmin_ui_parse_cron_time("sched", $job, \%in);
	}
if ($in{'sched'} == 0) {
	delete($config{'validate_sched'});
	}
elsif ($in{'sched'} == 1) {
	$config{'validate_sched'} = '@'.$job->{'special'};
	}
else {
	$config{'validate_sched'} =
		join(" ", $job->{'mins'}, $job->{'hours'}, $job->{'days'},
			  $job->{'months'}, $job->{'weekdays'});
	}
$config{'validate_email'} = $in{'email'};
$config{'validate_config'} = $in{'config'};
$config{'validate_always'} = $in{'always'};
if ($in{'servers_def'}) {
	delete($config{'validate_servers'});
	}
else {
	$in{'servers'} || &error($text{'newvalidate_edoms'});
	$config{'validate_servers'} = join(" ", split(/\0/, $in{'servers'}));
	}
if ($in{'features_def'}) {
	delete($config{'validate_features'});
	}
else {
	$in{'features'} || &error($text{'newvalidate_efeatures'});
	$config{'validate_features'} = join(" ", split(/\0/, $in{'features'}));
	}

# Setup the Cron job
if ($oldjob) {
	&lock_file(&cron::cron_file($oldjob));
	&cron::delete_cron_job($oldjob);
	&unlock_file(&cron::cron_file($oldjob));
	}
&cron::create_wrapper($validate_cron_cmd, $module_name, "validate.pl");
if ($in{'sched'}) {
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}

# Save configuration
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&webmin_log("validate");
&redirect("");

