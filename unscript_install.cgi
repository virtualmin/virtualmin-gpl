#!/usr/local/bin/perl
# Actually un-install some script, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});

if ($in{'upgrade'}) {
	# Just redirect to the install form, in upgrade mode
	&redirect("script_form.cgi?dom=$in{'dom'}&script=$in{'script'}&version=$in{'version'}&upgrade=1");
	exit;
	}
elsif ($in{'stop'}) {
	# Redirect to Rails server stop form
	&redirect("stop_script.cgi?dom=$in{'dom'}&script=$in{'script'}");
	}
elsif ($in{'start'}) {
	# Redirect to Rails server start form
	&redirect("start_script.cgi?dom=$in{'dom'}&script=$in{'script'}");
	}
elsif ($in{'restart'}) {
	# Redirect to Rails server restart form
	&redirect("restart_script.cgi?dom=$in{'dom'}&script=$in{'script'}");
	}

# Get the script being removed
@got = &list_domain_scripts($d);
($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
$sinfo || &error($text{'scripts_egone'});
$script = &get_script($sinfo->{'name'});

if ($in{'confirm'}) {
	# Do it
	&error_setup($text{'scripts_uerr'});

	&ui_print_unbuffered_header(&domain_in($d), $text{'scripts_utitle'}, "");

	# Get locks
	&obtain_lock_web($d);
	&obtain_lock_cron($d);

	# Call the un-install function
	&$first_print(&text('scripts_uninstalling', $script->{'desc'},
						    $sinfo->{'version'}));
	($ok, $msg) = &{$script->{'uninstall_func'}}($d, $sinfo->{'version'},
							 $sinfo->{'opts'});
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

		&run_post_actions();

		&webmin_log("uninstall", "script", $sinfo->{'name'},
			    { 'ver' => $sinfo->{'version'},
			      'desc' => $sinfo->{'desc'},
			      'dom' => $d->{'dom'} });
		}
	else {
		&$second_print($text{'scripts_failed'});
		}

	&release_lock_web($d);
	&release_lock_cron($d);
	}
else {
	# Ask first
	&ui_print_header(&domain_in($d), $text{'scripts_utitle'}, "");

	print "<center>\n";
	print &ui_form_start("unscript_install.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("script", $in{'script'}),"\n";

	$opts = $sinfo->{'opts'};
	$sz = &nice_size(&disk_usage_kb($opts->{'dir'})*1024);
	print &text('scripts_rusure', $script->{'desc'}, $sinfo->{'version'}, $opts->{'dir'}, $sz),"\n";
	if ($opts->{'db'}) {
		($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
		print &text('scripts_rusuredb',
			    $text{'databases_'.$dbtype}, $dbname),"\n";
		}
	print "<p>\n";
	if ($opts->{'dir'} eq &public_html_dir($d)) {
		# Show extra warning about public_html
		print &text('scripts_rusurehome',
			    &public_html_dir($d, 1)),"<p>\n";
		}
	print &ui_submit($text{'scripts_uok2'}, "confirm"),"<br>\n";
	print &ui_form_end();
	print "</center>\n";
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

