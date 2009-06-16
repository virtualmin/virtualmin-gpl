#!/usr/local/bin/perl
# Uninstall a bunch of scripts from some virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
if ($in{'upgrade'}) {
	# Just go to mass upgrade page
	&redirect("mass_upgrade.cgi?$in");
	exit;
	}

&error_setup($text{'massu_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'masse_enone'});

# Get the scripts being removed
@got = &list_domain_scripts($d);
foreach $id (@d) {
	($sinfo) = grep { $_->{'id'} eq $id } @got;
	if ($sinfo) {
		push(@del, $sinfo);
		}
	}

if ($in{'confirm'}) {
	# Do it
	&ui_print_unbuffered_header(&domain_in($d), $text{'massu_title'}, "");

	# Get locks
	&obtain_lock_web($d);
	&obtain_lock_cron($d);

	foreach $sinfo (@del) {
		# Call the un-install function
		$script = &get_script($sinfo->{'name'});
		&$first_print(&text('scripts_uninstalling',
			$script->{'desc'}, $sinfo->{'version'}));
		($ok, $msg) = &{$script->{'uninstall_func'}}(
			$d, $sinfo->{'version'}, $sinfo->{'opts'});
		&$indent_print();
		print $msg,"<br>\n";
		&$outdent_print();
		if ($ok) {
			&$second_print($text{'setup_done'});

			# Remove any custom PHP directory
			&clear_php_version($d, $sinfo);

			# Remove custom proxy path
			&delete_noproxy_path($d, $script, $sinfo->{'version'},
					     $sinfo->{'opts'});

			# Record script un-install in domain
			&remove_domain_script($d, $sinfo);
			}
		else {
			&$second_print($text{'scripts_failed'});
			}
		&run_post_actions();
		}

	&release_lock_web($d);
	&release_lock_cron($d);
	&webmin_log("uninstall", "scripts", scalar(@d));
	}
else {
	# Ask first
	&ui_print_header(&domain_in($d), $text{'massu_title'}, "");

	print "<center>\n";
	print &ui_form_start("mass_uninstall.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	foreach $id (@d) {
		print &ui_hidden("d", $id),"\n";
		}
	$sz = $dbcount = 0;
	@descs = ( );
	foreach $sinfo (@del) {
		$script = &get_script($sinfo->{'name'});
		$opts = $sinfo->{'opts'};
		$sz += &disk_usage_kb($opts->{'dir'})*1024;
		if ($opts->{'db'}) {
			if (!$donedb{$opts->{'db'}}++) {
				$dbcount++;
				}
			}
		if ($opts->{'dir'} eq &public_html_dir($d)) {
			$delhtml = 1;
			}
		push(@descs, $script->{'desc'}." ".$sinfo->{'version'});
		}
	print &text('massu_rusure', scalar(@d), &nice_size($sz)),"\n";
	if ($dbcount) {
		print &text('massu_rusuredb', $dbcount),"\n";
		}
	print "<p>\n";
	if ($delhtml) {
		print &text('massu_rusurehome', &public_html_dir($d, 1)),
		      "<p>\n";
		}
	print &ui_submit($text{'scripts_uok2'}, "confirm"),"<p>\n";
	print &text('massu_sel', join(", ", @descs)),"<br>\n";
	print &ui_form_end(),"<br>\n";
	print "</center>\n";
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

