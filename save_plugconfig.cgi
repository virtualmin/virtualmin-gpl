#!/usr/local/bin/perl
# Save inputs from config.cgi

require './virtual-server-lib.pl';
require '../config-lib.pl';
&ReadParse();
$m = $in{'module'};
&error_setup($text{'config_err'});

&make_dir("$config_directory/$m", 0700);
&lock_file("$config_directory/$m/config");
&read_file("$config_directory/$m/config", \%pconfig);

$mdir = defined(&module_root_directory) ? &module_root_directory($m)
					: "$root_directory/$m";
if (-r "$mdir/config_info.pl") {
	# Module has a custom config editor
	&foreign_require($m, "config_info.pl");
	local $fn = "${m}::config_form";
	if (defined(&$fn)) {
		$func++;
		&foreign_call($m, "config_save", \%pconfig);
		}
	}
if (!$func) {
	# Use config.info to parse config inputs
	&parse_config(\%pconfig, "$mdir/config.info", $m);
	}
&write_file("$config_directory/$m/config", \%pconfig);
&unlock_file("$config_directory/$m/config");
&webmin_log("_config_", undef, undef, \%in, $m);
&redirect("edit_newfeatures.cgi");

