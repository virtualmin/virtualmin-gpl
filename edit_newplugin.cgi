#!/usr/local/bin/perl
# Display currently enabled plugin modules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newplugin_ecannot'});
&ui_print_header(undef, $text{'newplugin_title'}, "", "plugin");

print &ui_form_start("save_newplugin.cgi", "post");
print "$text{'newplugin_desc'}<p>\n";
print "$text{'newplugin_desc3'}<p>\n";

# Show a table of all plugins
%plugins = map { $_, 1 } @plugins;
%inactive = map { $_, 1 } split(/\s+/, $config{'plugins_inactive'});
@tds = ( "width=5", "width=75%", undef, "width=5%", "width=10% nowrap" );
@links = ( &select_all_link("active"), &select_invert_link("active") );
print &ui_links_row(\@links);
print &ui_columns_start([ "",
			  $text{'newplugin_name'},
			  $text{'newplugin_version'},
			  $text{'newplugin_def'},
			  $text{'newplugin_acts'} ], 100, 0, \@tds);
$tds[3] .= " align=center";
foreach $m (sort { $a->{'desc'} cmp $b->{'desc'} } &get_all_module_infos()) {
	$mdir = &module_root_directory($m->{'dir'});
	if (-r "$mdir/virtual_feature.pl") {
		&foreign_require($m->{'dir'}, "virtual_feature.pl");
		local @acts;
		if (-r "$mdir/config.info") {
			push(@acts, "<a href='edit_plugconfig.cgi?".
				"mod=$m->{'dir'}'>$text{'newplugin_conf'}</a>");
			}
		if (!$m->{'hidden'}) {
			push(@acts, "<a href='../$m->{'dir'}/'>".
				    "$text{'newplugin_open'}</a>");
			}
		print &ui_checked_columns_row([
			&plugin_call($m->{'dir'}, "feature_name"),
			$m->{'version'},
			&ui_checkbox("active", $m->{'dir'}, "",
				     !$inactive{$m->{'dir'}}),
			&ui_links_row(\@acts)
			], \@tds, "mods", $m->{'dir'}, $plugins{$m->{'dir'}}
			);
		print &ui_hidden("allplugins", $m->{'dir'});
		}
	}
print &ui_columns_end();
print &ui_links_row(\@links);
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
