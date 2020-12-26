#!/usr/local/bin/perl
# Show web and PHP options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$can || &error($text{'phpmode_ecannot'});
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

if (!$d->{'alias'} && $can == 2 &&
    ($p eq 'web' || &plugin_defined($p, "feature_get_web_php_mode"))) {
	# PHP execution mode
	print &ui_table_row(&hlink($text{'phpmode_mode'}, "phpmode"),
			    &ui_radio_table("mode", $mode,
			      [ map { [ $_, $text{'phpmode_'.$_} ] }
				    @modes ]));

	# Warn if changing mode would remove per-dir versions
	if ($mode eq "cgi" || $mode eq "fcgid") {
		@dirs = &list_domain_php_directories($d);
		if (@dirs > 1) {
			print &ui_table_row("", $text{'phpmode_dirswarn'});
			}
		}
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
	print &ui_table_row(&hlink($text{'phpmode_maxtime'}, "phpmode_maxtime"),
			    &ui_opt_textbox("maxtime", $max, 5,
					    $text{'form_unlimit'})." ".
			    $text{'rfile_secs'});
	}

print &ui_hidden_table_end();

# Show PHP information
if (defined(&list_php_modules) && !$d->{'alias'}) {
	print &ui_hidden_table_start($text{'phpmode_header2'}, "width=100%",
				     2, "phpinfo", 0, [ "width=30%" ]);

	# PHP versions
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
			    "<font color=red>".&html_escape($errs)."</font>");
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

