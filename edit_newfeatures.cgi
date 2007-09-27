#!/usr/local/bin/perl
# Display all supported plugins and features
# XXX support all config modes (what about logrotate mode 3? Force on?)
# XXX saving
# XXX remove from Module Config
# XXX do config check after saving

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'features_ecannot'});
&ui_print_header(undef, $text{'features_title'}, "", "features");

print &ui_form_start("save_newfeatures.cgi", "post");
print "$text{'features_desc'}<p>\n";

# Start the table
@tds = ( "width=5 align=center", "width=65%", "width=10%", undef, "width=5%",
	 "width=10% nowrap" );
print &ui_columns_start([ "",
			  $text{'features_name'},
			  $text{'features_type'},
			  $text{'newplugin_version'},
			  $text{'newplugin_def'},
			  $text{'newplugin_acts'} ], 100, 0, \@tds);
$tds[4] .= " align=center";

# Add rows for core features
foreach $f (@features) {
	local @acts;
	push(@acts, "<a href='search.cgi?field=$f&what=1'>".
		    "$text{'features_used'}</a>");
	$vital = &indexof($f, @vital_features) >= 0;
	$always = &indexof($f, @can_always_features) >= 0;
	if ($vital) {
		# Some features are *never* disabled, but may be not checked
		# by default
		print &ui_columns_row([
			"<img src=images/tick.gif>",
			$text{'feature_'.$f},
			$text{'features_feature'},
			undef,
			&ui_checkbox("factive", $f, "", $config{$f} != 2),
			&ui_links_row(\@acts)
			], \@tds);
		}
	else {
		# Other features can be disabled
		print &ui_checked_columns_row([
			$text{'feature_'.$f},
			$text{'features_feature'},
			undef,
			&ui_checkbox("factive", $f, "", $config{$f} != 2),
			&ui_links_row(\@acts)
			], \@tds, "mods", $f, $config{$f} != 0);
		}
	}

# Show rows for all plugins
%plugins = map { $_, 1 } @plugins;
%inactive = map { $_, 1 } split(/\s+/, $config{'plugins_inactive'});
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
		if (!$donesep++) {
			print &ui_columns_row([ "<hr>" ],
					      [ "colspan=".(scalar(@tds)+1) ]);
			}
		print &ui_checked_columns_row([
			&plugin_call($m->{'dir'}, "feature_name"),
			$text{'features_plugin'},
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
