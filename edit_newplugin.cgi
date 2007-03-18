#!/usr/local/bin/perl
# Display currently enabled plugin modules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newplugin_ecannot'});
&ui_print_header(undef, $text{'newplugin_title'}, "", "plugin");

print &ui_form_start("save_newplugin.cgi", "post");
print "$text{'newplugin_desc'}<p>\n";
print "$text{'newplugin_desc2'}<p>\n";

# Show active plugins
%plugins = map { $_, 1 } @plugins;
@confplugins = ( );
foreach $m (sort { $a->{'desc'} cmp $b->{'desc'} } &get_all_module_infos()) {
	$mdir = defined(&module_root_directory) ?
			&module_root_directory($m->{'dir'}) :
			"$root_directory/$m->{'dir'}";
	if (-r "$mdir/virtual_feature.pl") {
		&foreign_require($m->{'dir'}, "virtual_feature.pl");
		push(@opts, [ $m->{'dir'},
			&plugin_call($m->{'dir'}, "feature_name").
			($m->{'version'} ? " (v $m->{'version'})" : "") ]);
		push(@allplugins, $m->{'dir'});
		if (-r "$mdir/config.info") {
			push(@confplugins, $m);
			}
		}
	}
print &ui_select("mods", \@plugins, \@opts, 10, 1);

print &ui_form_end([ [ "save", $text{'save'} ] ]);

# Show links to configure plugins
if (@confplugins) {
	print "<hr>\n";
	print &ui_form_start("edit_plugconfig.cgi");
	print &hlink($text{'newplugin_configdesc'},"plugin_mod_config"),"<p>\n";
	print &ui_submit($text{'newplugin_config'});
	print &ui_select("mod", undef,
		[ map { [ $_->{'dir'},
			  &plugin_call($_->{'dir'}, "feature_name")." (".
			   $_->{'desc'}.")" ] } @confplugins ]);
	print &ui_form_end();
	}

&ui_print_footer("", $text{'index_return'});
