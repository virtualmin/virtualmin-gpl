#!/usr/local/bin/perl
# Upgrade a bunch of scripts to their latest versions

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
&error_setup($text{'massg_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'massg_enone'});

# Get the scripts being upgraded, and for each work out a new version
@got = &list_domain_scripts($d);
foreach $id (@d) {
	($sinfo) = grep { $_->{'id'} eq $id } @got;
	if ($sinfo) {
		push(@sinfos, $sinfo);
		$script = &get_script($sinfo->{'name'});
		@vers = grep { &can_script_version($script, $_) }
			     @{$script->{'versions'}};
		@better = grep { &compare_versions($_,
					$sinfo->{'version'}) > 0 } @vers;
		$ver = @better ? $better[$#better] : undef;
		$scriptmap{$sinfo->{'id'}} = $script;
		$vermap{$sinfo->{'id'}} = $ver;
		}
	}

if ($in{'confirm'}) {
	# Do it
	&ui_print_unbuffered_header(&domain_in($d), $text{'massg_title'}, "");

	# Upgrade each script, if a new version exists
	foreach $sinfo (@sinfos) {
		$script = $scriptmap{$sinfo->{'id'}};
		$ver = $vermap{$sinfo->{'id'}};
		$opts = $sinfo->{'opts'};
		&$first_print(&text('massg_doing', $script->{'desc'}, $ver));
		if (&compare_versions($sinfo->{'version'}, $ver) >= 0) {
			# Already got it
			&$second_print(&text('massscript_ever',
					     $sinfo->{'version'}));
			}
		elsif ($derr = &{$script->{'depends_func'}}($d, $ver, $sinfo)) {
			# Failed depends
			&$second_print(&text('massscript_edep', $derr));
			}
		elsif (@missing = &check_script_required_commands($d, $script,
					$ver, $sinfo->{'opts'})) {
			# Missing commands
			&$second_print(&text('massscript_ecommands',
					     join(" ", @missing)));
			}
		else {
			# Setup PHP version
			&$indent_print();
			$phpvfunc = $script->{'php_vers_func'};
			local $phpver;
			if (defined(&$phpvfunc)) {
				@vers = &$phpvfunc($d, $ver);
				$phpver = &setup_php_version($d, \@vers,
							     $opts->{'path'});
				if (!$phpver) {
					&error(&text('scripts_ephpvers',
						     join(" ", @vers)));
					}
				}

			# Install needed PHP modules
			&setup_script_requirements($d, $script, $ver, $phpver,
						   $opts) || next;

			# Fetch needed files
			$ferr = &fetch_script_files($sinfo->{'dom'}, $ver,$opts,
						    $sinfo, \%gotfiles);
			&error($ferr) if ($ferr);

			# Work out username and password
			$domuser = $sinfo->{'user'} || $d->{'user'};
			$dompass = $sinfo->{'pass'} || $d->{'pass'};

			# Go ahead and do it
			($ok, $msg, $desc, $url) = &{$script->{'install_func'}}(
				$d, $ver, $opts, \%gotfiles, $sinfo,
				$domuser, $dompass);
			print $msg,"<br>\n";
			&$outdent_print();
			if ($ok) {
				# Worked .. record it
				&$second_print($text{'setup_done'});
				&remove_domain_script($d, $sinfo);
				&add_domain_script($d, $sinfo->{'name'}, $ver,
					$opts, $desc, $url,
					$sinfo->{'user'}, $sinfo->{'pass'});
				}
			else {
				&$second_print($text{'scripts_failed'});
				last if ($in{'fail'});
				}
			}
		}

	&webmin_log("upgrade", "scripts", scalar(@d));
	}
else {
	# Ask first
	&ui_print_header(&domain_in($d), $text{'massg_title'}, "");

	print "<center>\n";
	print &ui_form_start("mass_upgrade.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	foreach $id (@d) {
		print &ui_hidden("d", $id),"\n";
		}
	print &text('massg_rusure', scalar(@d)),"<p>\n";
	print "<table>\n";
	foreach $sinfo (@sinfos) {
		$script = $scriptmap{$sinfo->{'id'}};
		$ver = $vermap{$sinfo->{'id'}};
		print "<tr>\n";
		print "<td>$script->{'desc'}</td>\n";
		print "<td>&nbsp;-&nbsp;</td>\n";
		if ($ver) {
			print "<td>",&text('massg_fromto',
					   $sinfo->{'version'}, $ver),"</td>\n";
			}
		else {
			print "<td>",&text('massg_stay',
					   $sinfo->{'version'}),"</td>\n";
			}
		print "</tr>\n";
		}
	print "</table>\n";
	print &ui_submit($text{'massg_ok'}, "confirm"),"<br>\n";
	print &ui_form_end();
	print "</center>\n";
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

