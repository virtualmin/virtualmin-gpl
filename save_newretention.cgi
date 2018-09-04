#!/usr/local/bin/perl
# Save global cleanup rules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'retention_ecannot'});
&error_setup($text{'retention_err'});
&ReadParse();

# Validate inputs
if ($in{'policy'} == 1) {
	$in{'days'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'retention_edays'});
	}
elsif ($in{'policy'} == 2) {
	$in{'size'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'retention_edays'});
	}

# Update config file
&lock_file($module_config_file);
$config{'retention_policy'} = $in{'policy'};
delete($config{'retention_days'});
delete($config{'retention_size'});
if ($in{'policy'} == 1) {
	$config{'retention_days'} = $in{'days'};
	}
elsif ($in{'policy'} == 2) {
	$config{'retention_size'} = $in{'size'}*$in{'size_units'};
	}
$config{'retention_mode'} = $in{'mode'};
$config{'retention_doms'} = join(" ", split(/\0/, $in{'doms'}));
$config{'retention_folders'} = $in{'folders'};
&save_module_config();
&unlock_file($module_config_file);

# Enable cron job
&setup_spamclear_cron_job();

&webmin_log("retention");
&redirect("");

