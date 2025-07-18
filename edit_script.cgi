#!/usr/local/bin/perl
# Show options for upgrading or un-installing some script

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
@got = &list_domain_scripts($d);
($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
$script = &get_script($sinfo->{'name'});
$script || &error($text{'scripts_emissing'});
$opts = $sinfo->{'opts'};

# Gather content first, because kits can have unbuffered conditional output
my $content = '';

# Script Kit
my $kit_func = $script->{'kit_func'};
my $extra_submits;
my $have_kit = 0;
my $has_header = 0;
my $can_upgrade = 0;
if (defined(&$kit_func)) {
	my $rows = &{$script->{'kit_func'}}($d, $script, $sinfo, 1);
	if ($rows) {
		$have_kit = 1;
		my $kit_func_desc = $script->{'kit_func_desc'};
		if (defined &$kit_func_desc) {
			$kit_desc = &{$kit_func_desc}($d, $script, $sinfo);
			if ($kit_desc) {
				$content .=
					&ui_tag('p', $kit_desc,
						{ class => 'kit-func-desc' });
				}
			}
		$content .= &ui_hidden_table_start(
			&text('scripts_kit',
			      $script->{'tmdesc'} || $script->{'desc'}),
			      undef, 4, 'script_kit', 1);
		if (ref($rows) eq 'ARRAY') {
			foreach my $td (@$rows) {
				$content .= &ui_table_row(
					$td->{'desc'}, $td->{'value'});
				}
			}
		elsif (ref($rows) eq 'HASH') {
			$extra_submits = $rows->{'extra_submits'};
			$can_upgrade = $rows->{'can_upgrade'};
			$has_header = $rows->{'has_header'};
			$content .= &ui_table_row(undef, $rows->{'data'}, 2);
			}
		else {
			$content .= &ui_table_row(undef, $rows, 2);
			}
		$content .= &ui_hidden_table_end();
		}
	}

# Show script info if not using a kit
if (!$have_kit) {
	$content .= "$text{'scripts_udesc'}<p>";
	$content .= &ui_table_start($text{'scripts_uheader'}, undef, 2);
	
	# Show script description
	$content .= &ui_table_row($text{'scripts_iinstver'},
		"$script->{'release'}&nbsp;".
			&ui_help("$text{'scripts_iinstdate'}: ".
				&filetimestamp_to_date($script->{'filename'})))
					if ($script->{'release'});
	$content .= &ui_table_row($text{'scripts_iname'}, $script->{'desc'});
	$content .= &ui_table_row($text{'scripts_iversion2'},
		$script->{'vdesc'}->{$sinfo->{'version'}} || $sinfo->{'version'});
	
	# Show original website
	if ($script->{'site'}) {
		$content .= &ui_table_row($text{'scripts_isite'},
					  &script_link($script->{'site'}));
		}
	
	# Show error, if any
	if ($sinfo->{'partial'}) {
		$content .= &ui_table_row($text{'scripts_ipartial'},
			"<font color=#ff0000>$sinfo->{'partial'}</font>");
		}
	if ($sinfo->{'deleted'}) {
		$content .= &ui_table_row($text{'scripts_idstatus'},
			"<font color=#ff0000>$text{'scripts_ideleted'}</font>");
		}
	
	# Show install URL
	my $slink = &get_script_link($d, $sinfo, 1);
	if ($slink) {
		$content .= &ui_table_row($text{'scripts_iurl'}, $slink);
		}
	$content .= &ui_table_row($text{'scripts_itime'}, &make_date($sinfo->{'time'}));
	
	# Show directory
	if ($opts->{'dir'}) {
		$content .= &ui_table_row($text{'scripts_idir'},
					  "<tt>$opts->{'dir'}</tt>");
	
		# Show actual PHP version for the script's directory
		@dirs = &list_domain_php_directories($d);
		foreach my $dir (sort { length($a->{'dir'}) cmp length($b->{'dir'}) } @dirs) {
			if (&is_under_directory($dir->{'dir'}, $opts->{'dir'}) ||
			    $dir->{'dir'} eq $opts->{'dir'}) {
				$bestdir = $dir;
				}
			}
		if ($bestdir) {
			$mode = &get_domain_php_mode($d);
			$fullver = &get_php_version($bestdir->{'version'}, $d) ||
				   $bestdir->{'version'};
			$content .= &ui_table_row($text{'scripts_iphpver'},
				$fullver." (".$text{'phpmode_short_'.$mode}.")".
					&get_php_info_link($d->{'id'}, 'label'));
			}
		}
	
	# Show DB, if we have it
	($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	if ($dbtype && $script->{'name'} !~ /^php(\S+)admin$/i) {
		$content .= &ui_table_row($opts->{'dbtbpref'}
		    ? $text{'scripts_idb2'}
		    : $text{'scripts_idb'},
			&text('scripts_idbname',
			      "edit_database.cgi?dom=$in{'dom'}&type=$dbtype&".
			      "name=$dbname", $text{'databases_'.$dbtype},
			      "<tt>$dbname</tt>" . 
			      	($opts->{'dbtbpref'}
					? " $text{'scripts_idbtbpref'} ".
						"<tt>$opts->{'dbtbpref'}</tt>"
					: "")).
			($opts->{'newdb'}
				? &ui_help($text{'scripts_inewdb'})
				: ""));
		}
	
	# Show login, if we have it
	if ($sinfo->{'user'}) {
		$content .= &ui_table_row($text{'scripts_iuser'},
			&text('scripts_ipass', "<tt>$sinfo->{'user'}</tt>",
					       "<tt>$sinfo->{'pass'}</tt>"));
		}
	
	$sfunc = $script->{'status_server_func'};
	# Show link to service
	if (defined(&$sfunc)) {
		&foreign_require('init');
		my $service_name = "$sinfo->{'name'}-$d->{'dom'}-$opts->{'port'}";
		if (&init::action_status($service_name)) {
			my $service_link = $service_name;
			if ($init::init_mode eq "systemd" &&
			    &foreign_available('init')) {
				$service_link =
				  &ui_link(&get_webprefix_safe().
				  	"/init/edit_systemd.cgi?name=".
					    &urlize($service_name).".service",
				        $service_name.".service");
				}
			$content .= &ui_table_row($text{'scripts_iservice'},
						  "<tt>$service_link</tt>");
			}
		}
	# Show port
	if ($opts->{'port'}) {
		@ports = split(/\s+/, $opts->{'port'});
		$content .= &ui_table_row($text{'scripts_iport'},
					  join(", ", @ports));
		}
	# Show current status
	if (defined(&$sfunc)) {
		@pids = &$sfunc($d, $opts);
		if ($pids[0] >= 0) {
			$content .= &ui_table_row($text{'scripts_istatus'},
			    @pids ?
			      &ui_text_color($text{'scripts_istatus1'},
			      		     "success") :
			      &ui_text_color($text{'scripts_istatus0'},
			      		     "danger"));
			$gotstatus = 1;
			}
		}
	$content .= &ui_table_end();
	}

# Show install options form
$content .= &ui_form_start("unscript_install.cgi", "post");
$content .= &ui_hidden("dom", $in{'dom'});
$content .= &ui_hidden("script", $in{'script'});
if ($extra_submits) {
	foreach my $submit (@$extra_submits) {
		$content .= $submit;
		}
	}

# Show un-install and upgrade buttons
$content .= &ui_submit($text{'scripts_uok'}, "uninstall");
# Reinstall dependencies
$content .= &ui_submit($text{'scripts_rdeps'}, "reinstall_deps");

# Show upgrade options
if (!$can_upgrade && !script_migrated_disallowed($script->{'migrated'})) {
	@vers = sort { $a <=> $b }
	    grep { &compare_versions($_, $sinfo->{'version'}, $script) > 0 &&
	           &can_script_version($script, $_) } @{$script->{'versions'}};
	$canupfunc = $script->{'can_upgrade_func'};
	if (!$sinfo->{'deleted'}) {
		if (defined(&$canupfunc)) {
			@vers = grep { &$canupfunc($sinfo, $_) > 0 } @vers;
			}
		if (@vers) {
			# Upgrade button
			$content .= "&nbsp;&nbsp;<span data-button-group>";
			$content .= &ui_submit($text{'scripts_upok'}, "upgrade");
			$content .= &ui_select("version", $vers[$#vers],
					 [ map { [ $_ ] } @vers ])."</span>";
			}
		elsif (&can_unsupported_scripts()) {
			# Upgrade to un-supported version
			$content .= "&nbsp;&nbsp;<span data-button-group>";
			$content .= &ui_submit($text{'scripts_upok2'}, "upgrade");
			$content .= &ui_textbox("version", undef, 15)."</span>";
			}
		}
	}
if (!$sinfo->{'deleted'}) {
	if ($gotstatus) {
		$content .= "&nbsp;&nbsp;";
		if (@pids) {
			$content .= &ui_submit($text{'scripts_ustop'}, "stop");
			$content .= &ui_submit($text{'scripts_urestart'},
					       "restart");
			}
		else {
			$content .= &ui_submit($text{'scripts_ustart'},
					       "start");
			}
		}
	}
$content .= &ui_form_end();

# Print head and content
&ui_print_header(&domain_in($d), &text('scripts_etitle', $script->{'desc'}), "")
	if (!$has_header);
print $content;

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

