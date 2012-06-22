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
	$in{'email_def'} || $in{'email'} =~ /^\S+\@\S+$/ ||
		&error($text{'newquotas_eemail'});
	if (!$in{'warn_def'}) {
		$in{'warn'} || &error($text{'newquotas_ewarn2'});
		$in{'warn'} =~ s/,/ /g;		# Allow commas
		foreach $w (split(/\s+/, $in{'warn'})) {
			$w =~ /^\d+$/ && $w > 0 && $w < 100 ||
				&error($text{'newquotas_ewarn3'});
			}
		}
	&virtualmin_ui_parse_cron_time("sched", $job, \%in);
	}
$config{'quota_email'} = $in{'email_def'} ? undef : $in{'email'};
$config{'quota_mailbox'} = $in{'mailbox'};
$config{'quota_mailbox_send'} = $in{'mailbox_send'};
$config{'quota_users'} = $in{'users'};
$config{'quota_warn'} = $in{'warn_def'} ? undef : $in{'warn'};
if ($in{'interval_def'}) {
	delete($config{'quota_interval'});
	}
else {
	$in{'interval'} =~ /^[1-9]\d*$/ || &error($text{'newquotas_einterval'});
	$config{'quota_interval'} = $in{'interval'};
	}
$in{'msg'} =~ s/\r//g;
$in{'msg'} =~ /\S/ || &error($text{'newquotas_emsg'});

# Setup the cron job
if ($oldjob) {
	&lock_file(&cron::cron_file($oldjob));
	&cron::delete_cron_job($oldjob);
	&unlock_file(&cron::cron_file($oldjob));
	}
&cron::create_wrapper($quotas_cron_cmd, $module_name, "quotas.pl");
if ($in{'sched'}) {
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}

# Save configuration
&lock_file($module_config_file);
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&save_module_config();
&unlock_file($module_config_file);
&lock_file($user_quota_msg_file);
&save_quotas_message($in{'msg'});
&unlock_file($user_quota_msg_file);
&run_post_actions_silently();
&webmin_log("quotas");
&redirect("");

