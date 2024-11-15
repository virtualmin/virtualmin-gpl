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
	$script || &error($text{'scripts_emissing'});
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
	$script || &error($text{'scripts_emissing'});
	$script->{'avail'} || &error($text{'scripts_eavail'});
	&can_script_version($script, $ver) || &error($text{'scripts_eavail'});
	&ui_print_header(&domain_in($d), $text{'scripts_intitle'}, "");
	}

# Check if the script can be installed
if (script_migrated_disallowed($script->{'migrated'})) {
	&error($text{'scripts_eavail'});
	}

# Validate version number
$ver =~ /^\S+$/ || &error($text{'scripts_eversion'});
&indexof($ver, @{$script->{'versions'}}) >= 0 ||
	&indexof($ver, @{$script->{'install_versions'}}) >= 0 ||
	&can_unsupported_scripts() ||
		&error($text{'scripts_eversion2'});

# Check that the domain has a PHP version
$ok = 1;
if (&indexof("php", @{$script->{'uses'}}) >= 0) {
	@gotvers = grep { local $v = $_; local $_;
			  &check_php_version($d, $v) }
			&expand_php_versions($d, [5]);
	@gotvers = sort { &get_php_version($b, $d) <=>
                          &get_php_version($a, $d) } @gotvers;
	if (!@gotvers) {
		&error($text{'scripts_ephpvers2'});
		$ok = 0;
		}
	}

if ($ok) {
	# Check if abandoned
	$afunc = $script->{'abandoned_func'};
	$abandoned = defined(&$afunc) && &$afunc($ver);
	if ($abandoned == 2) {
		print &ui_alert_box($text{'scripts_abandoned2'}, 'warn');
		}
	elsif ($abandoned == 1) {
		print &ui_alert_box(&text('scripts_abandoned1', $ver), 'warn');
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
	print &ui_table_row($text{'scripts_iinstver'},
		"$script->{'release'}&nbsp;".
			&ui_help("$text{'scripts_iinstdate'}: ".
				&filetimestamp_to_date($script->{'filename'})))
		if ($script->{'release'});
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
			&script_link($script->{'site'}));
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
		($passmode, $passlenreq, $passpattern) = &{$script->{'passmode_func'}}($d, $ver);
		}

	my $dompass = $d->{'pass'};
	my $dompass_bad = 0;

	# If script has password length requirement
	if ($passlenreq && length($dompass) < $passlenreq) {
		# If password length doesn't fit, generate new one
		$dompass_bad = 1;
		$dompass = &random_password($passlenreq);

		# If script has password pattern requirement
		# and generated password doesn't fit, try
		# generating a new one
		if ($passpattern) {
			my $regex = qr/$passpattern/;
			if ($dompass !~ $regex) {
				for (my $i = 0; $i < 100; $i++) {
					my $password = &random_password($passlenreq);
					if ($password =~ $regex) {
						$dompass = $password;
						last;
						}
					}
				}
			}
		}

	
	# If there is a pattern set, test it and pass to HTML5 tag
	if ($passpattern) {
		my $regex = qr/$passpattern/;
		$dompass_bad = 1 if ($dompass !~ $regex);
		$passpattern = " pattern=\"".&quote_escape($passpattern, '"')."\"";
		}

	# If password length requirement is set
	my $dompass_req;
	if ($passlenreq) {
		$dompass_req = " required minlength=\"".int($passlenreq)."\"$passpattern";
		}
	my $passmodepassfield =
		$dompass_bad ?
			&ui_textbox("passmodepass", $dompass, 20, undef, undef, $dompass_req) :
			&ui_textbox("passmodepass", $dompass, undef, undef, $dompass_req);
	if ($passmode == 1) {
		if ($dompass_bad) {
			# Can choose login and password (with requirements)
			print &ui_table_row($text{'scripts_passmode'},
			      &ui_textbox("passmodeuser", $d->{'user'}, 20) .
				  $passmodepassfield);
			}
		else {
			# Can choose login and password
			print &ui_table_row($text{'scripts_passmode'},
			      &ui_radio("passmode_def", 1,
				[ [ 1, $text{'scripts_passmodedef1'}."<br>" ],
				  [ 0, &text('scripts_passmode1',
				     &ui_textbox("passmodeuser", $d->{'user'}, 20),
				     $passmodepassfield) ]
				]));
			}
		}
	elsif ($passmode == 2) {
		if ($dompass_bad) {
			# Can choose only password (with requirements)
			print &ui_table_row($text{'scripts_passmode4'}, $passmodepassfield);
			}
		else {
			# Can choose only password
			print &ui_table_row($text{'scripts_passmode'},
			      &ui_radio("passmode_def", 1,
				[ [ 1, $text{'scripts_passmodedef2'}."<br>" ],
				  [ 0, &text('scripts_passmode2',
				     $passmodepassfield) ]
				]));
			}
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

