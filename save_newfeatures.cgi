#!/usr/local/bin/perl
# Update both enabled core features and plugin modules

require './virtual-server-lib.pl';
&error_setup($text{'features_err'});
&can_edit_templates() || &error($text{'features_ecannot'});
&ReadParse();

# Validate plugins
@newplugins = split(/\0/, $in{'mods'});
foreach $p (@newplugins) {
	&foreign_require($p, "virtual_feature.pl");
	$err = &plugin_call($p, "feature_check");
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
	else {
		# Other features may be active, active but not selected by
		# default, or disabled
		if (!$fselected{$f}) {
			# Totally disabled
			$config{$f} = 0;
			}
		elsif ($factive{$f}) {
			# Enabled by default
			if ($f eq "logrotate" && $config{$f} != 1) {
				# For logrotate, use always mode unless the user
				# had it on enabled but optional
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
&set_all_null_print();
$cerr = &check_virtual_server_config();
&error($cerr) if ($cerr);

# Update the procmail setting for default delivery
if ($config{'spam'}) {
	&setup_default_delivery();
	}

# Save the config
&lock_file($module_config_file);
if ($config{'last_check'} < time()) {
	$config{'last_check'} = time()+1;
	}
&save_module_config();
&unlock_file($module_config_file);

# Update the miniserv preload list, which includes plugins
if ($virtualmin_pro && $oldplugins ne $config{'plugins'}) {
	&update_miniserv_preloads($config{'preload_mode'});
	&restart_miniserv();
	}

&webmin_log("features");
&redirect("");

