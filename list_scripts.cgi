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

# Show table of installed scripts (if any)
if (@got) {
	print &ui_subheading($text{'scripts_installed'});
	print $text{'scripts_desc3'},"\n";
	@tds = ( "width=5" );
	print &ui_form_start("mass_uninstall.cgi", "post");
	print &ui_hidden("dom", $in{'dom'});
	print &ui_columns_start([ "",
				  $text{'scripts_name'},
				  $text{'scripts_ver'},
				  $text{'scripts_path'} ], undef, 0, \@tds);
	foreach $sinfo (sort { lc($smap{$a->{'name'}}->{'desc'}) cmp
			       lc($smap{$b->{'name'}}->{'desc'}) } @got) {
		$script = $smap{$sinfo->{'name'}};
		print &ui_checked_columns_row([
			"<a href='edit_script.cgi?dom=$in{'dom'}&".
			"script=$sinfo->{'id'}'>$script->{'desc'}</a>",
			$script->{'vdesc'}->{$sinfo->{'version'}} ||
			  $sinfo->{'version'},
			$sinfo->{'url'} ? 
			  "<a href='$sinfo->{'url'}'>$sinfo->{'desc'}</a>" :
			  $sinfo->{'desc'}
			], \@tds, "d", $sinfo->{'id'});
		}
	print &ui_columns_end();
	print &ui_form_end([ [ "uninstall", $text{'scripts_uninstalls'} ] ]);
	print "<hr>\n";
	}

# Show table for installing scripts, by category
if (@scripts) {
	print &ui_subheading($text{'scripts_available'});
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
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

