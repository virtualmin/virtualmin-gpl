#!/usr/local/bin/perl
# Show web and PHP options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$canv = &can_edit_phpver($d);
$can || $canv || &error($text{'phpmode_ecannot'});
if (!$d->{'alias'}) {
	@modes = &supported_php_modes($d);
	$mode = &get_domain_php_mode($d);
	}
$p = &domain_has_website($d);

&ui_print_header(&domain_in($d), $text{'phpmode_title2'}, "");

print &ui_form_start("save_phpmode.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_hidden_table_start($text{'phpmode_header'}, "width=100%", 2,
			     "phpmode", 1, [ "width=30%" ]);

if ($can) {
	if (!$d->{'alias'} && $can == 2 &&
	    ($p eq 'web' || &plugin_defined($p, "feature_get_web_php_mode"))) {
		# PHP execution mode
		push(@modes, $mode) if ($mode && &indexof($mode, @modes) < 0);
		print &ui_table_row(&hlink($text{'phpmode_mode'}, "phpmode"),
				    &ui_radio_table("mode", $mode,
				      [ map { [ $_, $text{'phpmode_'.$_} ] }
					    @modes ]));
		}

	# PHP fcgi sub-processes
	if (!$d->{'alias'} && &indexof("fcgid", @modes) >= 0 && $can == 2 &&
	    ($p eq 'web' || &plugin_defined($p, "feature_get_web_php_children"))) {
		$children = &get_domain_php_children($d);
		if ($children > 0) {
			print &ui_table_row(&hlink($text{'phpmode_children'},
						   "phpmode_children"),
				    &ui_opt_textbox("children", $children || '',
					 5, $text{'tmpl_phpchildrennone'}));
			}
		}

	# PHP max execution time, for fcgi mode
	if (!$d->{'alias'} &&
	    (&indexof("fcgid", @modes) >= 0 || &indexof("fpm", @modes) >= 0) &&
	    ($p eq 'web' ||
	     &plugin_defined($p, "feature_get_fcgid_max_execution_time"))) {
		$max = $mode eq "fcgid" ? &get_fcgid_max_execution_time($d)
					: &get_php_max_execution_time($d);
		print &ui_table_row(
			&hlink($text{'phpmode_maxtime'}, "phpmode_maxtime"),
			&ui_opt_textbox("maxtime", $max == 0 ? undef : $max,
					5, $text{'form_unlimit'})." ".
				    	$text{'rfile_secs'});
		}
	}

# PHP versions
if ($canv && !$d->{'alias'} && $mode ne "mod_php") {
	# Build versions list
	my @avail = &list_available_php_versions($d, $mode);
	my @vlist = ( );
	foreach my $v (@avail) {
		if ($v->[1]) {
			my $fullver = &get_php_version($v->[1], $d);
			push(@vlist, [ $v->[0], $fullver ]);
			}
		else {
			push(@vlist, $v->[0]);
			}
		}

	# Get current versions and directories
	@dirs = &list_domain_php_directories($d);
	$pub = &public_html_dir($d);

	if (@avail <= 1) {
		# System has only one version
		$fullver = $avail[0]->[1] ? &get_php_version($avail[0]->[1], $d)
					  : $avail[0]->[0];
		print &ui_table_row($text{'phpmode_version'}, $fullver);
		}
	elsif ($mode eq "fpm" && @dirs == 1) {
		# Only one version can be set
		print &ui_table_row(
			&hlink($text{'phpmode_version'}, "phpmode_version"),
			&ui_select("ver_0", $dirs[0]->{'version'}, \@vlist));
		print &ui_hidden("dir_0", $dirs[0]->{'dir'});
		print &ui_hidden("d", $dirs[0]->{'dir'});
		}
	else {
		# Multiple versions can be selected for different directories
		$i = 0;
		@table = ( );
		$anydelete = 0;
		foreach $dir (sort { $a->{'dir'} cmp $b->{'dir'} } @dirs) {
			$ispub = $dir->{'dir'} eq $pub;
			$sel = &ui_select("ver_$i", $dir->{'version'}, \@vlist);
			print &ui_hidden("dir_$i", $dir->{'dir'});
			print &ui_hidden("oldver_$i", $dir->{'version'});
			if ($ispub) {
				# Can only change version for public html
				push(@table, [
					{ 'type' => 'checkbox', 'name' => 'd',
					  'value' => $i,
					  'disabled' => 1,
					  'checked' => 1, },
					"<i>$text{'phpver_pub'}</i>",
					$sel
					]);
				}
			elsif (substr($dir->{'dir'}, 0, length($pub)) eq $pub) {
				# Show directory relative to public_html
				push(@table, [
					{ 'type' => 'checkbox', 'name' => 'd',
					  'value' => $i,
					  'checked' => 1, },
					"<tt>".substr($dir->{'dir'}, length($pub)+1)."</tt>",
					$sel
					]);
				$anydelete++;
				}
			else {
				# Show full path
				push(@table, [
					{ 'type' => 'checkbox', 'name' => 'd',
					  'value' => $i,
					  'checked' => 1, },
					"<tt>$dir->{'dir'}</tt>",
					$sel
					]);
				$anydelete++;
				}
			$i++;
			}
		push(@table, [ { 'type' => 'checkbox', 'name' => 'd',
				 'value' => "new", },
			       &ui_textbox("dir_new", undef, 30),
			       &ui_select("ver_new", undef, \@vlist),
			     ]);
		@heads = ( $text{'phpmode_enabled'},, $text{'phpver_dir'},
			   $text{'phpver_ver'} );
		print &ui_table_row(
			&hlink($text{'phpmode_versions'}, "phpmode_versions"),
			&ui_columns_table(\@heads, 100, \@table));

		# Warn if changing mode would remove per-dir versions
		if ($mode eq "cgi" || $mode eq "fcgid") {
			@dirs = &list_domain_php_directories($d);
			if (@dirs > 1) {
				print &ui_table_row("", &ui_text_color($text{'phpmode_dirswarn'}, 'warn'));
				}
			}
		}
	}

print &ui_hidden_table_end();

# Show PHP information
if (defined(&list_php_modules) && !$d->{'alias'}) {
	print &ui_hidden_table_start($text{'phpmode_header2'}, "width=100%",
				     2, "phpinfo", 0, [ "width=30%" ]);

	# PHP versions
	my @vlist = ( );
	foreach $phpver (&list_available_php_versions($d)) {
		my $fullver = $phpver->[1] ? &get_php_version($phpver->[1], $d)
					   : $phpver->[0];
		push(@vlist, $fullver);
		}
	print &ui_table_row($text{'phpmode_vers'},
		@vlist ? join(", ", @vlist) : $text{'phpmode_novers'});

	# PHP errors for the domain
	foreach $phpver (&list_available_php_versions($d)) {
		$errs = &check_php_configuration($d, $phpver->[0],$phpver->[1]);
		if ($errs) {
			print &ui_table_row(&text('phpmode_errs', $phpver->[0]),
				&ui_text_color($errs, 'danger'));
			}
		}

	# PHP modules for the domain
	foreach $phpver (&list_available_php_versions($d)) {
		@mods = &list_php_modules($d, $phpver->[0], $phpver->[1]);
		@mods = sort { lc($a) cmp lc($b) } @mods;
		if (@mods) {
			print &ui_table_row(&text('phpmode_mods', $phpver->[0]),
				&ui_grid_table([ map { "<tt>$_</tt>" } @mods ],
					       6, 100));
			}
		}

	# Pear modules
	if (&foreign_check("php-pear")) {
		&foreign_require("php-pear");
		@allmods = ( );
		if (defined(&php_pear::list_installed_pear_modules)) {
			@allmods = &php_pear::list_installed_pear_modules();
			}
		@cmds = ( );
		if (defined(&php_pear::get_pear_commands)) {
			@cmds = &php_pear::get_pear_commands();
			}
		foreach $cmd (@cmds) {
			@mods = grep { $_->{'pear'} == $cmd->[1] } @allmods;
			@mods = sort { lc($a->{'name'}) cmp lc($b->{'name'}) }
				     @mods;
			if (@mods) {
				print &ui_table_row(
				    &text('phpmode_pears', $cmd->[1]),
				    &ui_grid_table(
				      [ map { "<tt>$_->{'name'}</tt>" } @mods ], 6, 100));
				}
			}
		}

	print &ui_hidden_table_end();
	}

print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

