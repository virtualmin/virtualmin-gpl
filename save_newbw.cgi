#!/usr/local/bin/perl
# save_newbw.cgi
# Update bandwidth limit settings

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newbw_ecannot'});
&error_setup($text{'newbw_err'});

# Validate inputs
$in{'bw_past'} || $in{'bw_period'} =~ /^\d+$/ && $in{'bw_period'} > 0 || 
	&error($text{'newbw_eperiod'});
$in{'bw_step'} =~ /^\d+$/ && $in{'bw_step'} > 0 && $in{'bw_step'} <= 24 ||
	&error($text{'newbw_estep'});
$in{'bw_maxdays_def'} ||
    $in{'bw_maxdays'} =~ /^\d+$/ && $in{'bw_maxdays'} > 0 ||
	&error($text{'newbw_emaxdays'});
$in{'bw_notify'} =~ /^\d+$/ && $in{'bw_notify'} > 0 || 
	&error($text{'newbw_enotify'});
!$in{'bw_warn'} || ($in{'bw_warnlevel'} > 0 && $in{'bw_warnlevel'} <= 100) ||
	&error($text{'newbw_ewarn'});
$in{'ftplog_def'} || -r $in{'ftplog'} ||
	&error($text{'newbw_eftplog'});
$in{'maillog_def'} != 0 || -r $in{'maillog'} ||
	&error($text{'newbw_emaillog'});
if ($in{'serversmode'}) {
	@servers = split(/\0/, $in{'servers'});
	@servers || &error($text{'newbw_eservers'});
	}

# Save configuration and create cron job
$config{'bw_active'} = $in{'bw_active'};
$config{'bw_step'} = $in{'bw_step'};
$config{'bw_past'} = $in{'bw_past'};
$config{'bw_period'} = $in{'bw_period'};
$config{'bw_maxdays'} = $in{'bw_maxdays_def'} ? undef : $in{'bw_maxdays'};
$config{'bw_notify'} = $in{'bw_notify'};
$config{'bw_owner'} = $in{'bw_owner'};
$config{'bw_email'} = $in{'bw_email'};
$config{'bw_disable'} = $in{'bw_disable'};
$config{'bw_enable'} = $in{'bw_enable'};
$config{'bw_warn'} = $in{'bw_warn'} ? $in{'bw_warnlevel'} : undef;
$config{'bw_ftplog'} = $in{'ftplog_def'} ? undef : $in{'ftplog'};
$config{'bw_ftplog_rotated'} = $in{'ftplog_rotated'};
$config{'bw_maillog'} = $in{'maillog_def'} == 1 ? undef :
			$in{'maillog_def'} == 2 ? "auto" : $in{'maillog'};
$config{'bw_maillog_rotated'} = $in{'maillog_rotated'};
$config{'bw_servers'} = $in{'serversmode'} == 0 ? "" :
			$in{'serversmode'} == 1 ? join(" ", @servers) :
						  "!".join(" ", @servers);
$config{'bw_nomailout'} = $in{'nomailout'};
$config{'bw_mail_all'} = $in{'mailall'};
&lock_file($module_config_file);
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&save_module_config();
&unlock_file($module_config_file);

# Save main template
$file = $config{'bw_template'};
$file = "$module_config_directory/bw-template" if ($file eq 'default');
$in{'bw_template'} =~ s/\r//g;
&open_lock_tempfile(FILE, ">$file", 1) ||
	&error(&text('efilewrite', $file, $!));
&print_tempfile(FILE, $in{'bw_template'});
&close_tempfile(FILE);

# Save warning template
$file = $config{'warnbw_template'};
$file = "$module_config_directory/warnbw-template" if ($file eq 'default');
$in{'warnbw_template'} =~ s/\r//g;
&open_tempfile(FILE, ">$file", 1) ||
	&error(&text('efilewrite', $file, $!));
&print_tempfile(FILE, $in{'warnbw_template'});
&close_tempfile(FILE);

# Setup the cron job
&setup_bandwidth_job($in{'bw_active'}, $in{'bw_step'});
&unlock_all_files();

&run_post_actions_silently();
&webmin_log("newbw");
&redirect("");

