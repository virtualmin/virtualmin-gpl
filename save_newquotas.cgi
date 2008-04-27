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
	if (!$in{'warn_def'}) {
		$in{'warn'} || &error($text{'newquotas_ewarn2'});
		$in{'warn'} =~ s/,/ /g;		# Allow commas
		foreach $w (split(/\s+/, $in{'warn'})) {
			$w =~ /^\d+$/ && $w > 0 && $w < 100 ||
				&error($text{'newquotas_ewarn3'});
			}
		}
	&cron::parse_times_input($job, \%in);
	}
$config{'quota_email'} = $in{'email'};
$config{'quota_warn'} = $in{'warn_def'} ? undef : $in{'warn'};
if ($in{'interval_def'}) {
	delete($config{'quota_interval'});
	}
else {
	$in{'interval'} =~ /^[1-9]\d*$/ || &error($text{'newquotas_einterval'});
	$config{'quota_interval'} = $in{'interval'};
	}
&cron::delete_cron_job($oldjob) if ($oldjob);
&cron::create_wrapper($quotas_cron_cmd, $module_name, "quotas.pl");
if ($in{'sched'}) {
	&cron::create_cron_job($job);
	}
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&save_module_config();
&redirect("");

