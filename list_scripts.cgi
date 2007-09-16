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
	$ratings = &get_script_ratings();
	$upcount = 0;
	print $text{'scripts_desc3'},"<p>\n";
	@tds = ( "width=5", undef, undef, undef, undef, "nowrap" );
	print &ui_form_start("mass_uninstall.cgi", "post");
	print &ui_hidden("dom", $in{'dom'});
	@links = ( &select_all_link("d"), &select_invert_link("d") );
	print &ui_links_row(\@links);
	print &ui_columns_start([ "",
				  $text{'scripts_name'},
				  $text{'scripts_ver'},
				  $text{'scripts_path'},
				  $text{'scripts_db'},
				  $text{'scripts_status'},
				  $text{'scripts_rating'} ], undef, 0, \@tds);
	foreach $sinfo (sort { lc($smap{$a->{'name'}}->{'desc'}) cmp
			       lc($smap{$b->{'name'}}->{'desc'}) } @got) {
		# Check if a newer version exists
		$script = $smap{$sinfo->{'name'}};
		@vers = grep { &can_script_version($script, $_) }
			     @{$script->{'versions'}};
		if (&indexof($sinfo->{'version'}, @vers) < 0) {
			@better = grep { &compare_versions($_, $sinfo->{'version'}) > 0 } @vers;
			if (@better) {
				$status = "<font color=#ffaa00>".
				  &text('scripts_newer', $better[$#better]).
				  "</font>";
				$upcount++;
				}
			else {
				$status = $text{'scripts_nonewer'};
				}
			}
		else {
			$status = "<font color=#00aa00>".
				  $text{'scripts_newest'}."</font>";
			}
		$path = $sinfo->{'opts'}->{'path'};
		($dbtype, $dbname) = split(/_/, $sinfo->{'opts'}->{'db'}, 2);
		if ($dbtype) {
			$dbdesc = &text('scripts_idbname2',
			      "edit_database.cgi?dom=$in{'dom'}&type=$dbtype&".
				"name=$dbname",
			      $text{'databases_'.$dbtype}, "<tt>$dbname</tt>");
			}
		else {
			$dbdesc = "<i>$text{'scripts_nodb'}</i>";
			}
		print &ui_checked_columns_row([
			"<a href='edit_script.cgi?dom=$in{'dom'}&".
			"script=$sinfo->{'id'}'>$script->{'desc'}</a>",
			$script->{'vdesc'}->{$sinfo->{'version'}} ||
			  $sinfo->{'version'},
			$sinfo->{'url'} ? 
			  "<a href='$sinfo->{'url'}'>$path</a>" :
			  $path,
			$dbdesc,
			$status,
			&virtualmin_ui_rating_selector(
				$sinfo->{'name'}, $ratings->{$sinfo->{'name'}},
				5, "rate_script.cgi?dom=$in{'dom'}")
			], \@tds, "d", $sinfo->{'id'});
		}
	print &ui_columns_end();
	print &ui_links_row(\@links);
	print &ui_form_end([
		     [ "uninstall", $text{'scripts_uninstalls'} ],
		     $upcount ? ( [ "upgrade", $text{'scripts_upgrades'} ] )
			      : ( ) ]);
	}
else {
	print "<b>$text{'scripts_noexisting'}</b><p>\n";
	}
print &ui_tabs_end_tab();

# Show table for installing scripts, by category
print &ui_tabs_start_tab("scriptsmode", "new");
if (@scripts) {
	# Show search form
	print &ui_form_start("list_scripts.cgi");
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("scriptsmode", "new");
	print "<b>$text{'scripts_find'}</b> ",
	      &ui_textbox("search", $in{'search'}, 30)," ",
	      &ui_submit($text{'scripts_findok'});
	print &ui_form_end();

	if ($in{'search'}) {
		# Limit to matches
		$search = $in{'search'};
		@scripts = grep { $_->{'desc'} =~ /\Q$search\E/i ||
				  $_->{'longdesc'} =~ /\Q$search\E/i ||
				  $_->{'category'} =~ /\Q$search\E/i } @scripts;
		}

	if (@scripts) {
		# Show table of available
		print &ui_form_start("script_form.cgi");
		print &ui_hidden("dom", $in{'dom'}),"\n";
		@tds = ( "width=5", "nowrap", undef, undef, "nowrap" );
		print &ui_columns_start([ "",
					  $text{'scripts_name'},
					  $text{'scripts_ver'},
					  $text{'scripts_longdesc'},
					  $text{'scripts_overall'} ],
					undef, 0, \@tds);
		foreach $script (@scripts) {
			$script->{'sortcategory'} = $script->{'category'} ||
						    "zzz";
			}
		$overall = &get_overall_script_ratings();
		foreach $script (sort { $a->{'sortcategory'} cmp
						$b->{'sortcategory'} ||
					lc($a->{'desc'}) cmp lc($b->{'desc'}) }
				      @scripts) {
			$cat = $script->{'category'} || $text{'scripts_nocat'};
			@vers = grep { &can_script_version($script, $_) }
				     @{$script->{'versions'}};
			next if (!@vers);	# No allowed versions!
			if ($cat ne $lastcat) {
				print &ui_columns_row([ "<b>$cat</b>" ],
						      [ "colspan=5" ]);
				$lastcat = $cat;
				}
			if (@vers > 1) {
				$vsel = &ui_select("ver_".$script->{'name'},
				    undef,
				    [ map { [ $_, $script->{'vdesc'}->{$_} ] }
				          @vers ]);
				}
			else {
				$vsel = ($script->{'vdesc'}->{$vers[0]} ||
					 $vers[0]).
					&ui_hidden("ver_".$script->{'name'},
						   $vers[0]);
				}
			$r = $overall->{$script->{'name'}};
			print &ui_radio_columns_row([
			    $script->{'desc'},
			    $vsel,
			    $script->{'longdesc'},
			    $r ? &virtualmin_ui_rating_selector(undef, $r, 5)
			       : "",
			    ], \@tds, "script", $script->{'name'},
			       $in{'search'} && @scripts == 1);
			}
		print &ui_columns_end();
		print &ui_submit($text{'scripts_ok'});
		print &ui_form_end();
		print &ui_tabs_end_tab();
		}
	else {
		print "<b>$text{'scripts_nomatch'}</b><p>\n";
		}
	}
else {
	print "<b>$text{'scripts_nonew'}</b><p>\n";
	}
print &ui_tabs_end_tab();

print &ui_tabs_end(1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

