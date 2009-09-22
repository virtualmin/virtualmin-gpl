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
if ($in{'serversmode'} == 0) {
	delete($config{'scriptwarn_servers'});
	}
elsif ($in{'serversmode'} == 2) {
	$config{'scriptwarn_servers'} =
		"!".join(" ", split(/\0/, $in{'servers'}));
	}
else {
	$config{'scriptwarn_servers'} =
		join(" ", split(/\0/, $in{'servers'}));
	}
$config{'scriptwarn_email'} = join(" ", @email);
$config{'scriptwarn_notify'} = $in{'wnotify'};
$config{'scriptwarn_enabled'} = $in{'enabled'} ? 1 : 0;
$config{'scriptwarn_wsched'} = $in{'wsched'};
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

# Create or remove cron job
&setup_scriptwarn_job($in{'enabled'}, $in{'wsched'});

# Return
&webmin_log("warn", "scripts");
&redirect("edit_newscripts.cgi?mode=warn");


