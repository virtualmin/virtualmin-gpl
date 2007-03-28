#!/usr/local/bin/perl
# Show available and installed scripts for this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
$d->{'web'} && $d->{'dir'} || &error($text{'scripts_eweb'});
@got = &list_domain_scripts($d);

&ui_print_header(&domain_in($d), $text{'scripts_title'}, "", "scripts");
@allscripts = map { &get_script($_) } &list_scripts();
@scripts = grep { $_->{'avail'} } @allscripts;
%smap = map { $_->{'name'}, $_ } @allscripts;

# Start tabs for listing and installing
@tabs = ( [ "existing", $text{'scripts_tabexisting'},
	    "list_scripts.cgi?dom=$in{'dom'}&scriptsmode=existing" ],
	  [ "new", $text{'scripts_tabnew'},
	    "list_scripts.cgi?dom=$in{'dom'}&scriptsmode=new" ] );
print &ui_tabs_start(\@tabs, "scriptsmode",
	$in{'scriptsmode'} ? $in{'scriptsmode'} : @got ? "existing" : "new", 1);

# Show table of installed scripts (if any)
print &ui_tabs_start_tab("scriptsmode", "existing");
if (@got) {
	print $text{'scripts_desc3'},"<p>\n";
	@tds = ( "width=5" );
	print &ui_form_start("mass_uninstall.cgi", "post");
	print &ui_hidden("dom", $in{'dom'});
	@links = ( &select_all_link("d"), &select_invert_link("d") );
	print &ui_links_row(\@links);
	print &ui_columns_start([ "",
				  $text{'scripts_name'},
				  $text{'scripts_ver'},
				  $text{'scripts_path'},
				  $text{'scripts_status'} ], undef, 0, \@tds);
	foreach $sinfo (sort { lc($smap{$a->{'name'}}->{'desc'}) cmp
			       lc($smap{$b->{'name'}}->{'desc'}) } @got) {
		# Check if a newer version exists
		$script = $smap{$sinfo->{'name'}};
		@vers = grep { &can_script_version($script, $_) }
			     @{$script->{'versions'}};
		if (&indexof($sinfo->{'version'}, @vers) < 0) {
			@better = grep { &compare_versions($_, $sinfo->{'version'}) > 0 } @vers;
			$status = "<font color=#ffaa00>".
				  &text('scripts_newer', $better[$#better]).
				  "</font>";
			}
		else {
			$status = "<font color=#00aa00>".
				  $text{'scripts_newest'}."</font>";
			}
		
		print &ui_checked_columns_row([
			"<a href='edit_script.cgi?dom=$in{'dom'}&".
			"script=$sinfo->{'id'}'>$script->{'desc'}</a>",
			$script->{'vdesc'}->{$sinfo->{'version'}} ||
			  $sinfo->{'version'},
			$sinfo->{'url'} ? 
			  "<a href='$sinfo->{'url'}'>$sinfo->{'desc'}</a>" :
			  $sinfo->{'desc'},
			$status,
			], \@tds, "d", $sinfo->{'id'});
		}
	print &ui_columns_end();
	print &ui_links_row(\@links);
	print &ui_form_end([ [ "uninstall", $text{'scripts_uninstalls'} ] ]);
	}
else {
	print "<b>$text{'scripts_noexisting'}</b><p>\n";
	}
print &ui_tabs_end_tab();

# Show table for installing scripts, by category
print &ui_tabs_start_tab("scriptsmode", "new");
if (@scripts) {
	print &ui_form_start("script_form.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	@tds = ( "width=5", "nowrap" );
	print &ui_columns_start([ "",
				  $text{'scripts_name'},
				  $text{'scripts_ver'},
				  $text{'scripts_longdesc'} ], undef, 0, \@tds);
	foreach $script (@scripts) {
		$script->{'sortcategory'} = $script->{'category'} || "zzz";
		}
	foreach $script (sort { $a->{'sortcategory'} cmp $b->{'sortcategory'} ||
				lc($a->{'desc'}) cmp lc($b->{'desc'}) }
			      @scripts) {
		$cat = $script->{'category'} || $text{'scripts_nocat'};
		@vers = grep { &can_script_version($script, $_) }
			     @{$script->{'versions'}};
		next if (!@vers);	# No allowed versions!
		if ($cat ne $lastcat) {
			print &ui_columns_row([ "<b>$cat</b>" ],
					      [ "colspan=4]" ]);
			$lastcat = $cat;
			}
		if (@vers > 1) {
			$vsel = &ui_select("ver_".$script->{'name'}, undef,
				   [ map { [ $_, $script->{'vdesc'}->{$_} ] }
				   @vers ]);
			}
		else {
			$vsel = ($script->{'vdesc'}->{$vers[0]} || $vers[0]).
				&ui_hidden("ver_".$script->{'name'}, $vers[0]);
			}
		if (defined(&ui_radio_columns_row)) {
			print &ui_radio_columns_row([
			    $script->{'desc'},
			    $vsel,
			    $script->{'longdesc'}
			    ], \@tds, "script", $script->{'name'});
			}
		else {
			# Old function without highlighting
			print &ui_columns_row([
			    &ui_oneradio("script", $script->{'name'}),
			    $script->{'desc'},
			    $vsel,
			    $script->{'longdesc'}
			    ], \@tds);
			}
		}
	print &ui_columns_end();
	print &ui_submit($text{'scripts_ok'});
	print &ui_form_end();
	print &ui_tabs_end_tab();
	}
else {
	print "<b>$text{'scripts_nonew'}</b><p>\n";
	}
print &ui_tabs_end_tab();

print &ui_tabs_end(1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

