#!/usr/local/bin/perl
# Show a form for restoring a single virtual server, or a bunch

require './virtual-server-lib.pl';
&ReadParse();

if ($in{'delete'}) {
	# Redirect to backup deletion page
	&redirect("delete_backup.cgi?id=".&urlize($in{'log'}).
		  "&search=".&urlize($in{'search'}).
		  "&plugin=".&urlize($in{'plugin'}).
		  "&return=".&urlize($in{'return'}));
	return;
	}

$crmode = &can_restore_domain();
$crmode || &error($text{'restore_ecannot'});
$safe_backup = $crmode == 1 ? 1 : 0;	# 1 means this backup can be trusted
&ui_print_header(undef, $text{'restore_title'}, "");

if ($in{'sched'}) {
	# Get the schedule being restored from
	($sched) = grep { $_->{'id'} eq $in{'sched'} &&
			  &can_backup_sched($_) } &list_scheduled_backups();
	$sched || &error($text{'restore_esched'});
	}
elsif ($in{'log'}) {
	# Restoring from a logged backup
	$log = &get_backup_log($in{'log'});
	$log || &error($text{'viewbackup_egone'});
	&can_backup_log($log) || &error($text{'viewbackup_ecannot'});
	$sched = { 'feature_all' => 1,
		   'key' => $log->{'key'},
		   'dest' => $log->{'dest'} };
	$safe_backup = &can_trust_backup($log);
	}
else {
	# Sensible defaults
	$sched = { 'feature_all' => 1 };
	if ($crmode == 2) {
		$sched->{'dest'} = "upload:";
		}
	}
$dest = $sched->{'dest'};
if ($sched->{'strftime'}) {
	$dest = &backup_strftime($dest);
	}

# Work out the current user's main domain, if needed
if ($crmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
	}

@tds = ( "width=30%" );
print &ui_form_start("restore.cgi", "form-data");
print &ui_hidden("log", $in{'log'});
print &ui_hidden_table_start($text{'restore_sourceheader'}, "width=100%", 2,
			     "source", 1, \@tds);

# Show source file field
if ($dest eq "download:") {
	$dest = "upload:";
	}
if ($in{'log'}) {
	# Source is fixed
	print &ui_table_row($text{'restore_src'},
		&nice_backup_url($dest, 1));

	print &ui_table_row($text{'restore_madeat'},
		&make_date($log->{'start'}));

	# Show domains to include
	my @dnames = &backup_log_own_domains($log);
	print &ui_table_row($text{'restore_doms'},
	    join(" ", map { "<tt>".&show_domain_name($_)."</tt>" } @dnames));
	}
else {
	# Can select restore source
	print &ui_table_row($text{'restore_src'},
		&show_backup_destination("src", $dest, $crmode == 2, $d, 1, 0,
					 undef, $sched));
	}

# Show decryption key field
@allkeys = defined(&list_backup_keys) ?  &list_backup_keys() : ( );
if (@allkeys) {
	@cankeys = grep { &can_backup_key($_) } @allkeys;
	if ($log && $log->{'key'}) {
		# Always use the key from the log
		$key = &get_backup_key($log->{'key'});
		print &ui_table_row($text{'restore_key'},
			$key ? $key->{'desc'} : $log->{'key'});
		}
	elsif (@cankeys) {
		# Allow selection of usable keys
		print &ui_table_row($text{'restore_key'},
			&ui_select("key", $sched->{'key'},
			   [ [ "", "&lt;$text{'restore_nokey'}&gt;" ],
			     map { [ $_->{'id'}, $_->{'desc'} ] } @cankeys ],
			   1, 0, 1));
		}
	}

print &ui_hidden_table_end("source");

# Show feature selection boxes
print &ui_hidden_table_start($text{'restore_headerfeatures'}, "width=100%", 2,
			     "features", 0, \@tds);
$ftable = "";
$ftable .= &ui_radio("feature_all", int($sched->{'feature_all'}),
		[ [ 1, $text{'restore_allfeatures'} ],
		  [ 0, $text{'backup_selfeatures'} ] ])."<br>\n";
@links = ( &select_all_link("feature"), &select_invert_link("feature") );
$ftable .= &ui_links_row(\@links);
foreach $f (&get_available_backup_features(!$safe_backup)) {
	$ftable .= &ui_checkbox("feature", $f,
		$text{'backup_feature_'.$f} || $text{'feature_'.$f},
		$sched->{'feature_'.$f},
		"onClick='form.feature_all[1].checked = true'");
	local $ofunc = "show_restore_$f";
	local %opts = map { split(/=/, $_) }
			split(/,/, $sched->{'opts_'.$f});
	local $ohtml;
	if (defined(&$ofunc) && ($ohtml = &$ofunc(\%opts)) && $ohtml) {
		$ftable .= "<table><tr><td>\n";
		$ftable .= ("&nbsp;" x 5);
		$ftable .= "</td> <td>\n";
		$ftable .= $ohtml;
		$ftable .= "</td></tr></table>\n";
		}
	else {
		$ftable .= "<br>\n";
		}
	}

# Add boxes for plugins which are known to be safe
foreach $f (&list_backup_plugins()) {
	if ($safe_backup || &plugin_call($f, "feature_backup_safe")) {
		$ftable .= &ui_checkbox("feature", $f,
			&plugin_call($f, "feature_backup_name") ||
			    &plugin_call($f, "feature_name"),
			$sched->{'feature_'.$f},
			"onClick='form.feature_all[1].checked = true'")."\n";
		$ftable .= "<br>\n";
		}
	}
$ftable .= &ui_links_row(\@links);
print &ui_table_row($text{'restore_features'}, $ftable);
print &ui_hidden_table_end("features");

if (&can_backup_virtualmin()) {
	# Show virtualmin object backup options
	print &ui_hidden_table_start($text{'backup_headerfeatures2'},
		"width=100%", 2, "features2", 0, \@tds);
	$vtable = "";
	%virts = map { $_, 1 } split(/\s+/, $sched->{'virtualmin'});
	foreach $vo (@virtualmin_backups) {
		$vtable .= &ui_checkbox("virtualmin", $vo,
				$text{'backup_v'.$vo}, $virts{$vo})."<br>\n";
		}
	@links = ( &select_all_link("virtualmin"),
		   &select_invert_link("virtualmin") );
	$vtable .= &ui_links_row(\@links);
	print &ui_table_row($text{'restore_virtualmin'}, $vtable);
	print &ui_hidden_table_end("features2");
	}

if ($crmode == 1) {
	# Creation options
	print &ui_hidden_table_start($text{'restore_headeropts'}, "width=100%",
				     2, "opts", 0, \@tds);

	# Re-allocate UIDs
	print &ui_table_row(&hlink($text{'restore_reuid'}, "restore_reuid"),
			    &ui_yesno_radio("reuid", 1));

	# Re-allocate user and group
	print &ui_table_row(&hlink($text{'restore_reuser'}, "restore_reuser"),
			    &ui_yesno_radio("reuser", 0));

	# Just re-import, to fix missing domains file
	print &ui_table_row(&hlink($text{'restore_fix'}, "restore_fix"),
			    &ui_yesno_radio("fix", 0));

	# Delete before restoring
	print &ui_table_row(&hlink($text{'restore_delete'}, "restore_delete"),
			    &ui_yesno_radio("delete_existing", 0));

	# IP address for restored domains
	@cantmpls = ( &get_template(0) );
	if (&can_select_ip()) {
		print &ui_table_row(&hlink($text{'restore_newip'},
					   "restore_newip"),
				&virtual_ip_input(\@cantmpls, undef, 1, 5));
		}
	if (&can_select_ip6() && &supports_ip6()) {
		print &ui_table_row(&hlink($text{'restore_newip6'},
					   "restore_newip6"),
				&virtual_ip6_input(\@cantmpls, undef, 1, 5));
		}

	print &ui_hidden_table_end("opts");
	}

print &ui_form_end([ [ "", $text{'restore_now'} ] ]);

&ui_print_footer("", $text{'index_return'});

