#!/usr/local/bin/perl
# Show web and PHP options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpmode($d) || &error($text{'phpmode_ecannot'});

&ui_print_header(&domain_in($d), $text{'phpmode_title'}, "");

print &ui_form_start("save_phpmode.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_hidden_table_start($text{'phpmode_header'}, undef, 2, "phpmode", 1);

if (!$d->{'alias'}) {
	# Use suexec
	print &ui_table_row(&hlink($text{'phpmode_suexec'}, "phpmode_suexec"),
			    &ui_yesno_radio("suexec", &get_domain_suexec($d)));
	}

if (!$d->{'alias'}) {
	# PHP execution mode
	@modes = &supported_php_modes($d);
	print &ui_table_row(&hlink($text{'phpmode_mode'}, "phpmode"),
			    &ui_radio("mode", &get_domain_php_mode($d),
			      [ map { [ $_, $text{'phpmode_'.$_}."<br>" ] }
				    @modes ]));
	}

# PHP fcgi sub-processes
if (!$d->{'alias'} && &indexof("fcgid", @modes) >= 0) {
	$children = &get_domain_php_children($d);
	if ($children >= 0) {
		print &ui_table_row(&hlink($text{'phpmode_children'},
					   "phpmode_children"),
				    &ui_opt_textbox("children", $children || '',
					 5, $text{'tmpl_phpchildrennone'}));
		}
	}

# PHP max execution time, for fcgi mode
if (!$d->{'alias'} && &indexof("fcgid", @modes) >= 0) {
	$max = &get_fcgid_max_execution_time($d);
	print &ui_table_row(&hlink($text{'phpmode_maxtime'}, "phpmode_maxtime"),
			    &ui_opt_textbox("maxtime", $max, 5,
					    $text{'form_unlimit'})." ".
			    $text{'rfile_secs'});
	}

# Ruby execution mode
@rubys = &supported_ruby_modes($d);
if (!$d->{'alias'} && @rubys) {
	print &ui_table_row(&hlink($text{'phpmode_rubymode'}, "rubymode"),
		    &ui_radio("rubymode", &get_domain_ruby_mode($d),
			      [ [ "", $text{'phpmode_noruby'}."<br>" ],
				map { [ $_, $text{'phpmode_'.$_}."<br>" ] }
				    @rubys ]));
	}

# Write logs via program
if (!$d->{'alias'} || $d->{'alias_mode'} != 1) {
	print &ui_table_row(
		&hlink($text{'newweb_writelogs'}, "template_writelogs"),
		&ui_yesno_radio("writelogs", &get_writelogs_status($d)));
	}

# Match all sub-domains
print &ui_table_row(&hlink($text{'phpmode_matchall'}, "matchall"),
		    &ui_yesno_radio("matchall", &get_domain_web_star($d)));

print &ui_hidden_table_end();

# Show PHP information
if (defined(&list_php_modules) && !$d->{'alias'}) {
	print &ui_hidden_table_start($text{'phpmode_header2'}, undef,
				     2, "phpinfo", 0);

	# PHP modules for the domain
	foreach $phpver (&list_available_php_versions($d)) {
		@mods = &list_php_modules($d, $phpver->[0], $phpver->[1]);
		@mods = sort { lc($a) cmp lc($b) } @mods;
		print &ui_table_row(&text('phpmode_mods', $phpver->[0]),
			&ui_grid_table([ map { "<tt>$_</tt>" } @mods ],
				       6, 100));
		}

	# Pear modules
	if (&foreign_check("php-pear")) {
		&foreign_require("php-pear", "php-pear-lib.pl");
		@allmods = ( );
		if (defined(&php_pear::list_installed_pear_modules)) {
			@allmods = &php_pear::list_installed_pear_modules();
			}
		foreach $cmd (&php_pear::get_pear_commands()) {
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

