#!/usr/local/bin/perl
# Enable or disable the cron job for downloading the latest script installers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ReadParse();
&error_setup($text{'newscripts_lerr'});

# Update config
if ($in{'scripts_def'}) {
	$config{'scriptlatest'} = '';
	}
else {
	@snames = split(/\0/, $in{'scripts'});
	@snames || &error($text{'newscripts_elnone'});
	$config{'scriptlatest'} = join(' ', @snames);
	}
$config{'scriptlatest_enabled'} = $in{'enabled'};
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

# Create or remove cron job
&setup_scriptlatest_job($in{'enabled'});

# If enabled, do one run now
if ($in{'enabled'}) {
	&system_logged("$scriptlatest_cron_cmd >/dev/null 2>&1 </dev/null");
	}

# Return
&run_post_actions_silently();
&webmin_log("latest", "scripts");
&redirect("edit_newscripts.cgi?mode=latest");


