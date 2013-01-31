#!/usr/local/bin/perl
# Show options for installing some script

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'scripts_ierr'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
&domain_has_website($d) && $d->{'dir'} || &error($text{'scripts_eweb'});

if ($in{'upgrade'}) {
	# Upgrading
	@got = &list_domain_scripts($d);
	($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
	$script = &get_script($sinfo->{'name'});
	$sname = $sinfo->{'name'};
	$ver = $in{'version'};
	&ui_print_header(&domain_in($d), $text{'scripts_uptitle'}, "");
	}
else {
	# Installing new
	$sname = $in{'fast'} || $in{'fhidden'} || $in{'script'};
	$sname || &error($text{'scripts_enosel'});
	$ver = $in{'ver_'.$sname} || $in{'ver'};
	$script = &get_script($sname);
	$script->{'avail'} || &error($text{'scripts_eavail'});
	&can_script_version($script, $ver) || &error($text{'scripts_eavail'});
	&ui_print_header(&domain_in($d), $text{'scripts_intitle'}, "");
	}

# Validate version number
$ver =~ /^\S+$/ || &error($text{'scripts_eversion'});
&indexof($ver, @{$script->{'versions'}}) >= 0 ||
	&indexof($ver, @{$script->{'install_versions'}}) >= 0 ||
	&can_unsupported_scripts() ||
		&error($text{'scripts_eversion2'});

# Check PHP version
$ok = 1;
$phpvfunc = $script->{'php_vers_func'};
if (defined(&$phpvfunc)) {
	@vers = &$phpvfunc($d, $ver);
	@gotvers = grep { local $v = $_; local $_;
			  &check_php_version($d, $v) } @vers;
	@gotvers = &expand_php_versions($d, \@gotvers);
	if (!@gotvers) {
		print &text('scripts_ephpvers', join(" or ", @vers)),"<p>\n";
		$ok = 0;
		}
	}

# Check dependencies
$derr = &check_script_depends($script, $d, $ver, $sinfo, $gotvers[0]);
if ($derr) {
	print &text('scripts_edep', $derr),"<p>\n";
	$ok = 0;
	}

if ($ok) {
	# Check if abandoned
	$afunc = $script->{'abandoned_func'};
	$abandoned = defined(&$afunc) && &$afunc($v);
	if ($abandoned == 2) {
		print "<font color=red><b>",
			&text('scripts_abandoned2'),"</b></font><p>\n";
		}
	elsif ($abandoned == 1) {
		print "<font color=red><b>",
			&text('scripts_abandoned1', $v),"</b></font><p>\n";
		}
	
	# Show install options form
	print &ui_form_start("script_install.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("script", $sname),"\n";
	print &ui_hidden("version", $ver),"\n";
	if ($in{'upgrade'}) {
		print &ui_hidden("upgrade", $in{'script'}),"\n";
		}
	print &ui_table_start($text{'scripts_iheader'}, undef, 2);

	# Show script description
	print &ui_table_row($text{'scripts_iname'}, $script->{'desc'});
	print &ui_table_row($text{'scripts_idesc'}, $script->{'longdesc'})
		if ($script->{'longdesc'});
	print &ui_table_row($text{'scripts_iversion'},
			    $script->{'vdesc'}->{$ver} || $ver);
	if ($sinfo) {
		print &ui_table_row($text{'scripts_upversion'},
				    $sinfo->{'version'});
		}

	# Show script type
	$uses = $script->{'uses'}->[0];
	$utext = $text{'scripts_iuses_'.$uses};
	if ($utext) {
		print &ui_table_row($text{'scripts_iuses'}, $utext);
		}

	# Show original website
	if ($script->{'site'}) {
		print &ui_table_row($text{'scripts_isite'},
			"<a href='$script->{'site'}' target=_blank>".
			"$script->{'site'}</a>");
		}

	# Show installer author
	if ($script->{'author'}) {
		print &ui_table_row($text{'scripts_iauthor'}, 
			$script->{'author'});
		}

	# Show parameters
	$opts = &{$script->{'params_func'}}($d, $ver, $sinfo);
	print $opts;

	# Show custom login and password
	if (!$sinfo && defined(&{$script->{'passmode_func'}})) {
		$passmode = &{$script->{'passmode_func'}}($d, $ver);
		}
	if ($passmode == 1) {
		# Can choose login and password
		print &ui_table_row($text{'scripts_passmode'},
		      &ui_radio("passmode_def", 1,
			[ [ 1, $text{'scripts_passmodedef1'}."<br>" ],
			  [ 0, &text('scripts_passmode1',
			     &ui_textbox("passmodeuser", $d->{'user'}, 20),
			     &ui_password("passmodepass", $d->{'pass'}, 20)) ]
			]));
		}
	elsif ($passmode == 2) {
		# Can choose only password
		print &ui_table_row($text{'scripts_passmode'},
		      &ui_radio("passmode_def", 1,
			[ [ 1, $text{'scripts_passmodedef2'}."<br>" ],
			  [ 0, &text('scripts_passmode2',
			     &ui_password("passmodepass", $d->{'pass'}, 20)) ]
			]));
		}
	elsif ($passmode == 3) {
		# Can choose only login
		print &ui_table_row($text{'scripts_passmode'},
		      &ui_radio("passmode_def", 1,
			[ [ 1, $text{'scripts_passmodedef3'}."<br>" ],
			  [ 0, &text('scripts_passmode3',
			     &ui_textbox("passmodeuser", $d->{'user'}, 20)) ],
			]));
		}
	print &ui_hidden("passmode", $passmode);

	print &ui_table_end();
	print &ui_form_end([ [ "install", $text{'scripts_iok'} ] ]);
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

