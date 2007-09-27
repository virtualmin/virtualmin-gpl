#!/usr/local/bin/perl
# Update both enabled core features and plugin modules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'features_ecannot'});
&ReadParse();

# Validate features

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

# Work out which ones are not on by default
%active = map { $_, 1 } split(/\0/, $in{'active'});
foreach $p (split(/\0/, $in{'allplugins'})) {
	push(@inactive, $p) if (!$active{$p});
	}

# Update module config
$config{'plugins'} = join(" ", @newplugins);
$config{'plugins_inactive'} = join(" ", @inactive);

# Validate new settings with a config check
# XXX

# Save the config
&lock_file($module_config_file);
if ($config{'last_check'} < time()) {
	$config{'last_check'} = time()+1;
	}
&save_module_config();
&unlock_file($module_config_file);

&webmin_log("features");
&redirect("");

