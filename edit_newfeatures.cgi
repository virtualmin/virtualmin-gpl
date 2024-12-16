#!/usr/local/bin/perl
# Display all supported plugins and features

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'features_ecannot'});
&ui_print_header(undef, $text{'features_title'}, "", "features");

# Work out who uses what features
@doms = &list_domains();
foreach $f (@features, @plugins) {
	@pdoms = grep { $_->{$f} } @doms;
	$fcount{$f} = scalar(@pdoms);
	}

print &ui_form_start("save_newfeatures.cgi", "post");
print "$text{'features_desc'}<p>\n";

# Add rows for core features
@table_order_initial = ( );
foreach $f (@features) {
	# Skip features for modules that aren't enabled in Webmin
	my $cfunc = "check_module_".$f;
	if (!$config{$f} && defined(&$cfunc) && !&$cfunc()) {
		next;
		}

	local @acts;
	push(@acts, ui_link("search.cgi?field=$f&what=1",
		                $text{'features_used'}));
	my $vital = &indexof($f, @vital_features) >= 0;
	my $deprecated = &indexof($f, @deprecated_features) >= 0;
	my $always = &indexof($f, @can_always_features) >= 0;
	if ($vital) {
		# Some features are *never* disabled, but may be not checked
		# by default
		push(@table_order_initial, $f);
		push(@table, [
			{ 'type' => 'checkbox', 'checked' => 1, 'disabled' => 1 },
			$text{'feature_'.$f},
			$text{'features_feature'},
			get_module_version_and_type(),
			$fcount{$f} || 0,
			{ 'type' => 'checkbox', 'name' => 'factive',
			  'value' => $f, 'checked' => $config{$f} == 3 },
			&ui_links_row(\@acts)
			]);
		}
	elsif ($deprecated && !$config{$f} &&
	       &check_feature_depends($f)) {
		# Some features are now hidden unless already enabled
		next;
		}
	else {
		# Other features can be disabled
		push(@table_order_initial, $f);
		push(@table, [
			{ 'type' => 'checkbox', 'name' => 'fmods',
			  'value' => $f, 'checked' => $config{$f} != 0,
			  'tags' => "onClick='this.closest(\"tr\").querySelector(\"td:nth-child(6) input\").disabled = !this.checked;'",
			},
			$text{'feature_'.$f},
			$text{'features_feature'},
			get_module_version_and_type(),
			$fcount{$f} || 0,
			{ 'type' => 'checkbox', 'name' => 'factive',
			  'value' => $f, 'checked' => $config{$f} != 2,
			  'disabled' => $config{$f} == 0 },
			&ui_links_row(\@acts)
			]);
		}
	}

# Add rows for all plugins
%plugins = map { $_, 1 } @plugins;
%inactive = map { $_, 1 } @plugins_inactive;
foreach $m (sort { $a->{'desc'} cmp $b->{'desc'} } &get_all_module_infos()) {
	$mdir = &module_root_directory($m->{'dir'});
	if (-r "$mdir/virtual_feature.pl") {
		&foreign_require($m->{'dir'}, "virtual_feature.pl");
		local @acts;
		if (-r "$mdir/config.info") {
			push(@acts, ui_link("edit_plugconfig.cgi?mod=$m->{'dir'}",
                                $text{'newplugin_conf'}));
			}
		if (!$m->{'hidden'}) {
			push(@acts, ui_link("../$m->{'dir'}/",
                                $text{'newplugin_open'}));
			}
		if (!$donesep++) {
			print &ui_columns_row([ "<hr>" ],
					      [ "colspan=".(scalar(@tds)+1) ]);
			}
		push(@table_order_initial, $m->{'dir'});
		push(@table, [
			{ 'type' => 'checkbox', 'name' => 'mods',
			  'value' => $m->{'dir'},
			  'checked' => $plugins{$m->{'dir'}},
			  'tags' => "onClick='this.closest(\"tr\").querySelector(\"td:nth-child(6) input\").disabled = !this.checked;'",
			},
			&plugin_call($m->{'dir'}, "feature_name") ||
			  $m->{'dir'},
			$text{'features_plugin'},
			$m->{'version'},
			$fcount{$m->{'dir'}} ? $fcount{$m->{'dir'}} :
			  &plugin_defined($m->{'dir'}, "feature_setup") ? 0
									: "-",
			{ 'type' => 'checkbox', 'name' => 'active',
			  'value' => $m->{'dir'},
			  'disabled' => !$plugins{$m->{'dir'}},
			  'checked' => !$inactive{$m->{'dir'}},
			},
			&ui_links_row(\@acts)
			]);
		push(@hiddens, [ "allplugins", $m->{'dir'} ]);
		}
	}

# Actually generate the table
features_sort(\@table, \@table_order_initial);
print &ui_form_columns_table(
	"save_newfeatures.cgi",
	[ [ "save", $text{'save'} ] ],
	0,
	undef,
	\@hiddens,
	[ "", $text{'features_name'}, $text{'features_type'},
	      $text{'newplugin_version'}, $text{'newplugin_count'},
	      $text{'newplugin_def'}, $text{'newplugin_acts'} ],
	100,
	\@table,
	undef,
	1);

&ui_print_footer("", $text{'index_return'});
