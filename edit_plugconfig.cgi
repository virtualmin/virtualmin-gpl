#!/usr/local/bin/perl
# Display a form for editing the configuration of a plugin

require './virtual-server-lib.pl';
require "$root_directory/config-lib.pl";
&can_edit_templates() || &error($text{'newplugin_ecannot'});
&ReadParse();
$m = $in{'mod'};
%module_info = &get_module_info($m);
&ui_print_header(&text('plugconfig_dir', $module_info{'desc'}),
		 $text{'plugconfig_title'}, "");

print &ui_form_start("save_plugconfig.cgi", "post");
print &ui_hidden("module", $m),"\n";
print &ui_table_start(&text('config_header', $module_info{'desc'}),
		      "width=100%", 2);
&read_file("$config_directory/$m/config", \%pconfig);

$mdir = defined(&module_root_directory) ? &module_root_directory($m)
					: "$root_directory/$m";
if (-r "$mdir/config_info.pl") {
	# Module has a custom config editor
	&foreign_require($m, "config_info.pl");
	local $fn = "${m}::config_form";
	if (defined(&$fn)) {
		$func++;
		&foreign_call($m, "config_form", \%pconfig);
		}
	}
if (!$func) {
	# Use config.info to create config inputs
	&generate_config(\%pconfig, "$mdir/config.info", $m);
	}
print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("edit_newfeatures.cgi", $text{'features_return'},
		 "", $text{'index_return'});

