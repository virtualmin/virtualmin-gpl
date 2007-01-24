#!/usr/local/bin/perl
# Update plugin modules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newplugin_ecannot'});
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

# Save module config
&lock_file($module_config_file);
$config{'plugins'} = join(" ", @newplugins);
if ($config{'last_check'} < time()) {
	$config{'last_check'} = time()+1;
	}
&save_module_config();
&unlock_file($module_config_file);

&webmin_log("plugins");
&redirect("");

