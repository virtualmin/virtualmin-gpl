#!/usr/local/bin/perl
# Set up regular quota monitoring

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newquotas_err'});
&can_edit_templates() || &error($text{'newquotas_ecannot'});

# Validate inputs
$oldjob = $job = &find_quotas_job();
$job ||= { 'user' => 'root',
	   'active' => 1,
	   'command' => $quotas_cron_cmd };
if ($in{'sched'}) {
	$in{'email'} =~ /^\S+\@\S+$/ || &error($text{'newquotas_eemail'});
	$in{'warn_def'} || $in{'warn'} > 0 && $in{'warn'} < 100 ||
		&error($text{'newquotas_ewarn'});
	&cron::parse_times_input($job, \%in);
	}
$config{'quota_email'} = $in{'email'};
$config{'quota_warn'} = $in{'warn_def'} ? undef : $in{'warn'};
&cron::delete_cron_job($oldjob) if ($oldjob);
&cron::create_wrapper($quotas_cron_cmd, $module_name, "quotas.pl");
if ($in{'sched'}) {
	&cron::create_cron_job($job);
	}
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&save_module_config();
&redirect("");

