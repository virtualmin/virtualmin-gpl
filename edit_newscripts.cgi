#!/usr/local/bin/perl
# Show a form for installing new third-party scripts, and a list of those
# currently installed

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ui_print_header(undef, $text{'newscripts_title'}, "");

# Show form for installing a script
print "$text{'newscripts_desc'}<p>\n";
print &ui_form_start("add_script.cgi", "form-data");
print &ui_table_start($text{'newscripts_header'}, undef, 2);

print &ui_table_row($text{'newscripts_srcinst'},
	&ui_radio("source", 0,
  [ [ 0, &text('newscripts_src0', &ui_textbox("local", undef, 40))."<br>" ],
    [ 1, &text('newscripts_src1', &ui_upload("upload"))."<br>" ],
    [ 2, &text('newscripts_src2', &ui_textbox("url", undef, 40))."<br>" ] ]));

print &ui_table_end();
print &ui_form_end([ [ "install", $text{'newscripts_install'} ] ]);

# Display a list of those currently available, with checkboxes for enabling
print "<hr>\n";
print &ui_form_start("disable_scripts.cgi", "post");
print &ui_columns_start([ "",
			  $text{'newscripts_name'},
			  $text{'newscripts_longdesc'},
			  $text{'newscripts_src'},
			  $text{'newscripts_minver'} ]);
foreach $s (&list_scripts()) {
	$script = &get_script($s);
	$script->{'sortcategory'} = $script->{'category'} || "zzz";
	push(@scripts, $script);
	}
foreach $script (sort { $a->{'sortcategory'} cmp $b->{'sortcategory'} ||
			lc($a->{'desc'}) cmp lc($b->{'desc'}) }
		      @scripts) {
	$cat = $script->{'category'} || $text{'scripts_nocat'};
	if ($cat ne $lastcat) {
		print &ui_columns_row([ "<b>$cat</b>" ],
				      [ "colspan=5]" ]);
		$lastcat = $cat;
		}
	@v = @{$script->{'versions'}};
	print &ui_checked_columns_row([
		$script->{'desc'},
		$script->{'longdesc'},
		$script->{'dir'} eq "$module_root_directory/scripts" ?
			$text{'newscripts_inc'} : $text{'newscripts_third'},
		@v > 1 ? &ui_select($script->{'name'}."_minversion",
				$script->{'minversion'},
				[ [ undef, $text{'newscripts_any'} ],
				  map { [ $_, ">$_" ] } @v ],
				1, 0, 1) : "",
		], undef, "d", $script->{'name'}, $script->{'avail'});
	}
print &ui_columns_end();
print &ui_form_end([ [ "save", $text{'newscripts_save'} ] ]);

# Show form to mass upgrade scripts
print "<hr>\n";
print &ui_form_start("mass_scripts.cgi", "post");
print &ui_table_start($text{'newscripts_mheader'}, undef, 2);

# Script to upgrade to
@scripts = &list_available_scripts();
foreach $sname (@scripts) {
	$script = &get_script($sname);
	foreach $v (@{$script->{'versions'}}) {
		push(@opts, [ "$sname $v", "$script->{'desc'} $v" ]);
		}
	}
@opts = sort { lc($a->[1]) cmp lc($b->[1]) } @opts;
print &ui_table_row($text{'newscripts_script'},
		    &ui_select("script", undef, \@opts));

# Servers to upgrade
@doms = &list_domains();
print &ui_table_row($text{'newscripts_servers'},
		    &ui_radio("servers_def", 1,
			[ [ 1, $text{'newips_all'} ],
			  [ 0, $text{'newips_sel'} ] ])."<br>\n".
		    &servers_input("servers", [ ], \@doms));

print &ui_table_row($text{'newscripts_fail'},
		    &ui_yesno_radio("fail", 1));

print &ui_table_end();
print &ui_form_end([ [ "upgrade", $text{'newscripts_upgrade'} ] ]);

&ui_print_footer("", $text{'index_return'});

