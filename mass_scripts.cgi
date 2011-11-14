#!/usr/local/bin/perl
# Upgrade some script on multiple servers at once

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massscript_err'});

# Parse inputs
($sname, $ver) = split(/\s+/, $in{'script'});
if ($in{'servers_def'}) {
	@doms = &list_domains();
	}
else {
	foreach my $s (&unique(split(/\0/, $in{'servers'}))) {
		push(@doms, &get_domain($s));
		}
	@doms || &error($text{'massscript_enone'});
	}
foreach my $d (@doms) {
	&can_edit_domain($d) && &can_edit_scripts() ||
		&error($text{'edit_ecannot'});
	}

# Work out who has it
$script = &get_script($sname);
$canupfunc = $script->{'can_upgrade_func'};
foreach my $d (@doms) {
	@got = &list_domain_scripts($d);
	@dsinfos = grep { $_->{'name'} eq $sname &&
			  &compare_versions($_->{'version'}, $ver,
					    $script) < 0 } @got;
	push(@sinfos_anyver, grep { $_->{'name'} eq $sname } @got);
	if (defined(&$canupfunc)) {
		# Limit to allowable upgrades
		@dsinfos = grep { &$canupfunc($_, $ver) } @dsinfos;
		}
	foreach $sinfo (@dsinfos) {
		$sinfo->{'dom'} = $d;
		}
	push(@sinfos, @dsinfos);
	}
@sinfos || @sinfos_anyver || &error($text{'massscript_enone2'});
@sinfos || &error($text{'massscript_enone3'});

&ui_print_unbuffered_header(undef, $text{'massscript_title'}, "");

if ($in{'confirm'}) {
	# Doing the upgrade
	print &text('massstart_start', $script->{'desc'},
				       $ver, scalar(@sinfos)),"<p>\n";

	# Do each server that has it
	foreach $sinfo (@sinfos) {
		$d = $sinfo->{'dom'};
		&$first_print(&text('massscript_doing', &show_domain_name($d),
				    $sinfo->{'version'}, $sinfo->{'desc'}));
		&$indent_print();

		# Fetch needed files
		my %gotfiles;
		$ferr = &fetch_script_files($sinfos[0]->{'dom'}, $ver,
					    $sinfos[0]->{'opts'},
					    $sinfos[0], \%gotfiles, 1);
		if ($ferr) {
			&$outdent_print();
			&$second_print(&text('massscript_efetch', $ferr));
			next;
			}

		$opts = $sinfo->{'opts'};
		if (&compare_versions($sinfo->{'version'}, $ver,
				      $script) >= 0) {
			# Already got it
			&$second_print(&text('massscript_ever',
					     $sinfo->{'version'}));
			}
		elsif ($derr = &check_script_depends($script,
						     $d, $ver, $sinfo)) {
			# Failed depends
			&$second_print(&text('massscript_edep', $derr));
			}
		else {
			# Get locks
			&obtain_lock_web($d);
			&obtain_lock_cron($d);

			# Setup PHP version
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

			# Install needed PHP/perl/ruby modules
			&setup_script_requirements($d, $script, $ver, $phpver,
						   $opts) || next;

			# Work out login and password
			$domuser = $sinfo->{'user'} || $d->{'user'};
			$dompass = $sinfo->{'pass'} || $d->{'pass'};

			# Go ahead and do it
			($ok, $msg, $desc, $url) = &{$script->{'install_func'}}(
				$d, $ver, $sinfo->{'opts'}, \%gotfiles, $sinfo,
				$domuser, $dompass);
			print $msg,"<br>\n";
			&$outdent_print();
			&release_lock_web($d);
			&release_lock_cron($d);
			if ($ok) {
				# Worked .. record it
				&$second_print($text{'setup_done'});
				&remove_domain_script($d, $sinfo);
				&add_domain_script($d, $sname, $ver,
					   $sinfo->{'opts'},
					   $desc, $url,
					   $sinfo->{'user'}, $sinfo->{'pass'});
				}
			else {
				&$second_print($text{'scripts_failed'});
				last if ($in{'fail'});
				}

			# Clean up any temp files from this script
			&cleanup_tempnames();
			}
		}
	&run_post_actions();
	&webmin_log("upgrade", "scripts", scalar(@sinfos));
	}
else {
	# Tell the user which domains will be done, and let him select

	# Build table data
	@table = ( );
	foreach my $sinfo (@sinfos) {
		$path = $sinfo->{'opts'}->{'path'};
		$utype = &indexof($sinfo->{'version'},
				  @{$script->{'versions'}}) > 0 ?
		    $text{'massscript_upgrade'} : $text{'massscript_update'}; 
		push(@table, [
			{ 'type' => 'checkbox',
			  'name' => 'servers',
			  'value' => $sinfo->{'dom'}->{'id'},
			  'checked' => 1 },
			&show_domain_name($sinfo->{'dom'}),
			$sinfo->{'version'},
			$sinfo->{'url'} ?
			    "<a href='$sinfo->{'url'}' target=_blank/g>$path</a>" :
			    $path,
			$utype,
			]);
		}

	# Output the table of scripts
	print &text('massscript_rusure', $script->{'desc'}, $ver),"<p>\n";
	print &ui_form_columns_table(
		"mass_scripts.cgi",
		[ [ "confirm", $text{'massscript_ok'} ] ],
		0,
		undef,
		[ [ "script", $sname." ".$ver ] ],
		[ "", $text{'massscript_dom'},
		  $text{'massscript_ver'},
		  $text{'massscript_path'},
		  $text{'massscript_utype'} ],
		100,
		\@table,
		);
	}

&ui_print_footer("", $text{'index_return'});


