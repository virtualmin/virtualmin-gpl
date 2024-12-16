#!/usr/local/bin/perl
# Update both enabled core features and plugin modules

require './virtual-server-lib.pl';
&error_setup($text{'features_err'});
&can_edit_templates() || &error($text{'features_ecannot'});
&ReadParse();
&licence_status();
%lastconfig = %config;

# Work out which features and plugins are now active
@newplugins = split(/\0/, $in{'mods'});
@neweverything = ( @newplugins, @vital_features,
		   split(/\0/, $in{'fmods'}) );

# Validate plugins
&set_all_null_print();
foreach $p (@newplugins) {
	&foreign_require($p, "virtual_feature.pl");
	$err = &plugin_call($p, "feature_check", \@neweverything);
	$name = &plugin_call($p, "feature_name");
	if ($err) {
		&error(&text('newplugin_emod', $name, $err));
		}
	}

# Work out which plugins are not on by default
%active = map { $_, 1 } split(/\0/, $in{'active'});
foreach $p (split(/\0/, $in{'allplugins'})) {
	push(@inactive, $p) if (!$active{$p});
	}

# Update module config with features and plugins
%factive = map { $_, 1 } split(/\0/, $in{'factive'});
%fselected = map { $_, 1 } split(/\0/, $in{'fmods'});
foreach $f (@features) {
	if (&indexof($f, @vital_features) >= 0) {
		# Features that are never disabled can only be switched
		# to be not selected by default
		$config{$f} = $factive{$f} ? 3 : 1;
		}
	elsif (&indexof($f, @deprecated_features) >= 0 && !$config{$f} &&
	       &check_feature_depends($f)) {
		# Some features are now hidden unless already enabled
		next;
		}
	else {
		# Other features may be active, active but not selected by
		# default, or disabled
		if (!$fselected{$f}) {
			# Totally disabled
			$config{$f} = 0;
			}
		elsif ($factive{$f}) {
			# Enabled by default
			if (&can_chained_feature($f) && $config{$f} != 1) {
				# For these features, use chain mode unless
				# the user had it on enabled but optional
				$config{$f} = 3;
				}
			else {
				$config{$f} = 1;
				}
			}
		else {
			# Enabled, but not on by default
			$config{$f} = 2;
			}
		}
	}
$oldplugins = $config{'plugins'};
$config{'plugins'} = join(" ", @newplugins);
$config{'plugins_inactive'} = join(" ", @inactive);

# Validate new settings with a config check
@plugins = @newplugins;
$cerr = &check_virtual_server_config(\%lastconfig);
&error($cerr) if ($cerr);

# Update the procmail setting for default delivery, turn on logging, and 
# create cron job to link up files
if ($config{'spam'}) {
	if (!$config{'no_lookup_domain_daemon'}) {
		&setup_lookup_domain_daemon();
		}
	&setup_default_delivery();
	&enable_procmail_logging();
	&setup_spam_config_job();
	}

# Fix up old procmail scripts that don't call the clam wrapper
if ($config{'virus'}) {
	&copy_clam_wrapper();
	&fix_clam_wrapper();
	&create_clamdscan_remote_wrapper_cmd();
	}

# Re-generate helper script, for plugins
&create_virtualmin_api_helper_command();

# Save the config
&lock_file($module_config_file);
if ($config{'last_check'} < time()) {
	$config{'last_check'} = time()+1;
	}
&save_module_config();
&unlock_file($module_config_file);

# Update the miniserv preload list, which includes plugins
if ($oldplugins ne $config{'plugins'}) {
	&update_miniserv_preloads($config{'preload_mode'});
	&restart_miniserv();
	}

# Clear cache of links
&clear_links_cache();

&setvar('navigation-reload', 1);

&run_post_actions_silently();
&webmin_log("features");
&redirect("");

