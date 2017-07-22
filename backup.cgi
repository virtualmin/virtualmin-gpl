#!/usr/local/bin/perl
# Do an immediate virtual server backup

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'backup_err'});
$cbmode = &can_backup_domain();
$cbmode || &error($text{'backup_ecannot'});
if ($in{'oneoff'} || $in{'bg'}) {
	($sched) = grep { $_->{'id'} eq $in{'oneoff'} &&
			  &can_backup_sched($_) } &list_scheduled_backups();
	$sched || &error($text{'backup_egone'});
	$runsched = $sched;
	}

if ($in{'bg'}) {
	# Background backup of previous scheduled request .. launch it
	&ui_print_unbuffered_header(undef, $text{'backup_title'}, "");

	@dests = &get_scheduled_backup_dests($sched);
	$nice = join(", ", map { &nice_backup_url($_) } @dests);
	&$first_print(&text('backup_starting', $nice));
	$cmd = "$backup_cron_cmd --id $sched->{'id'} --force-email";
	&clean_environment();
	&execute_command("$cmd >/dev/null 2>&1 </dev/null &");
	&reset_environment();
	if ($sched->{'email'}) {
		&$second_print(&text('backup_started', $sched->{'email'}));
		}
	else {
		&$second_print($text{'backup_started2'});
		}

	&ui_print_footer("list_sched.cgi", $text{'sched_return'});
	exit;
	}

# Validate inputs
$acluser = $sched ? $sched->{'owner'} : undef;
if ($in{'all'} == 1) {
	# All domains
	@doms = grep { &can_backup_domain($_, $acluser) } &list_domains();
	}
elsif ($in{'all'} == 2) {
	# All except selected
	%exc = map { $_, 1 } split(/\0/, $in{'doms'});
	@doms = grep { &can_backup_domain($_, $acluser) &&
		       !$exc{$_->{'id'}} } &list_domains();
	if ($in{'parent'}) {
		@doms = grep { !$_->{'parent'} || !$exc{$_->{'parent'}} } @doms;
		}
	}
else {
	# Only selected
	foreach $did (split(/\0/, $in{'doms'})) {
		local $dinfo = &get_domain($did);
		if ($dinfo && &can_backup_domain($dinfo, $acluser)) {
			push(@doms, $dinfo);
			if (!$dinfo->{'parent'} && $in{'parent'}) {
				push(@doms, &get_domain_by("parent", $did));
				}
			}
		}
	@doms = grep { !$donedom{$_->{'id'}}++ } @doms;
	}

# Limit to those on some plan, if given
if ($in{'plan'} && !$in{'plan_def'} && &can_edit_plans()) {
	%plandoms = map { $_->{'id'}, 1 }
	  grep { &indexof($_->{'plan'}, split(/\s+/, $in{'plan'})) >= 0 } @doms;
	@doms = grep { $plandoms{$_->{'id'}} ||
		       $plandoms{$_->{'parent'}} } @doms;
	}

# Work out the current user's main domain, if needed
if ($cbmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
	}
elsif ($cbmode == 3 && $in{'dest_mode'} == 0) {
	# A reseller running a backup to a local file, created by one of
	# his domains.
	$sid = $in{'sched'} || $in{'oneoff'};
	($sched) = grep { $_->{'id'} eq $sid &&
			  &can_backup_sched($_) } &list_scheduled_backups();
	if ($sched && $sched->{'owner'}) {
		$d = &get_domain($sched->{'owner'});
		}
	}

if ($in{'feature_all'}) {
	@do_features = ( &get_available_backup_features(), &list_backup_plugins() );
	}
else {
	@do_features = split(/\0/, $in{'feature'});
	}
@do_features || &error($text{'backup_efeatures'});

# Parse destinations
for($i=0; defined($in{"dest".$i."_mode"}); $i++) {
	next if ($in{"dest".$i."_mode"} == 0 &&
                 !$in{"dest".$i."_file"});
	$dest = &parse_backup_destination("dest".$i, \%in, $cbmode == 3, $d,
					  $in{'fmt'});
	push(@dests, $dest);
	$anydownload++ if ($dest eq "download:");
	}
@dests || &error($text{'backup_edests'});
$anydownload && $in{'fmt'} && &error($text{'backup_edownloadfmt'});
$anydownload && @dests > 1 && &error($text{'backup_edownloadmany'});

@strfdests = $in{'strftime'} ? map { &backup_strftime($_) } @dests
			     : @dests;

# Get the backup key
$key = undef;
if (defined(&get_backup_key) && $in{'key'}) {
	$key = &get_backup_key($in{'key'});
	$key || &error($text{'backup_ekey'});
	&can_backup_key($key) || &error($text{'backup_ekeycannot'});
	}

# Parse option inputs
foreach $f (@do_features) {
	local $ofunc = "parse_backup_$f";
	if (&indexof($f, &list_backup_plugins()) < 0 &&
	    defined(&$ofunc)) {
		$options{$f} = &$ofunc(\%in);
		}
	elsif (&indexof($f, &list_backup_plugins()) >= 0 &&
	       &plugin_defined($f, "feature_backup_parse")) {
		$options{$f} = &plugin_call($f, "feature_backup_parse", \%in);
		}
	}
$options{'dir'}->{'exclude'} = join("\t", split(/\r?\n/, $in{'exclude'}));

# Parse Virtualmin feature inputs
if (&can_backup_virtualmin()) {
	@vbs = split(/\0/, $in{'virtualmin'});
	}
else {
	@vbs = ( );
	}
@doms || @vbs || &error($text{'backup_edoms'});

# Flag backup as started
if (!$runsched) {
	# Fake up schedule object
	$runsched = { 'id' => 'backup.cgi.'.time() };
	for(my $i=0; $i<@dests; $i++) {
		$runsched->{'dest'.$i} = $dests[$i];
		}
	if ($in{'all'}) {
		$runsched->{'all'} = 1;
		}
	elsif (@doms) {
		$runsched->{'doms'} = join(" ", map { $_->{'id'} } @doms);
		}
	$runsched->{'virtualmin'} = join(" ", @vbs);
	}
&start_running_backup($runsched);

if ($dests[0] eq "download:") {
	# Special case .. we backup to a temp file and output in the browser
	$temp = &transname().($config{'compression'} == 0 ? ".tar.gz" :
			      $config{'compression'} == 1 ? ".tar.bz2" :".tar");
	if (@doms) {
		# Pre-create temp file with correct permissions
		foreach $t ($temp, $temp.".info", $temp.".dom") {
			&open_tempfile(TEMP, ">$t", 0, 1);
			&close_tempfile(TEMP);
			&set_ownership_permissions(
				$doms[0]->{'uid'}, $doms[0]->{'gid'}, 0700, $t);
			}
		}
	&set_all_null_print();
	($ok, $size) = &backup_domains([ $temp ], \@doms, \@do_features,
				       $in{'fmt'}, $in{'errors'}, \%options,
				       $in{'fmt'} == 2, \@vbs, $in{'mkdir'},
				       $in{'onebyone'}, $cbmode == 2,
				       undef, $in{'increment'}, 0, $key);
	&cleanup_backup_limits(0, 1);
	unlink($temp.".info");
	unlink($temp.".dom");
	&run_post_actions();
	if ($ok) {
		@st = stat($temp);
		print "Content-type: application/octet-stream\n";
		print "Content-length: $st[7]\n";
		print "\n";
		open(TEMP, $temp);
		unlink($temp);
		while(read(TEMP, $buf, 1024) > 0) {
			print $buf;
			}
		close(TEMP);
		}
	else {
		unlink($temp);
		&error($text{'backup_edownloadfailed'});
		}
	}
else {
	&ui_print_unbuffered_header(undef, $text{'backup_title'}, "");

	# Run any before command
	$start_time = time();
	if ($in{'oneoff'} && $sched->{'before'}) {
		&$first_print($text{'backup_brun'});
		$out .= &backquote_logged(
			"($sched->{'before'}) 2>&1 </dev/null");
		print "<pre>".&html_escape($out)."</pre>";
		if ($?) {
			&$second_print($text{'backup_brunfailed'});
			goto PREFAILED;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	# Start backup and show progress
	$nice = join(", ", map { &nice_backup_url($_) } @dests);
	if (@doms) {
		print &text('backup_doing', scalar(@doms), $nice),"<p>\n";
		}
	else {
		print &text('backup_doing2', scalar(@vbs), $nice),"<p>\n";
		}
	&start_print_capture();
	($ok, $size, $errdoms) = &backup_domains(
				       \@strfdests, \@doms, \@do_features,
				       $in{'fmt'}, $in{'errors'}, \%options,
				       $in{'fmt'} == 2, \@vbs, $in{'mkdir'},
				       $in{'onebyone'}, $cbmode == 2,
				       undef, $in{'increment'}, undef, $key);
	$output = &stop_print_capture();
	&cleanup_backup_limits(0, 1);
	foreach $dest (@strfdests) {
		&write_backup_log(\@doms, $dest, $in{'increment'}, $start_time,
				  $size, $ok, "cgi", $output, $errdoms,
				  undef, $key, $sched ? $sched->{'id'} : undef,
				  $in{'fmt'});
		}
	&run_post_actions();
	if (!$ok) {
		print "<p>",$text{'backup_failed'},"<p>\n";
		}
	else {
		print "<p>",&text('backup_done', &nice_size($size)),"<p>\n";
		}

	# If purging old backups, do that now
	if (($ok || $in{'errors'}) && $in{'oneoff'}) {
		@purges = &get_scheduled_backup_purges($sched);
		$i = 0;
		$asd = $cbmode == 2 ? &get_backup_as_domain(\@doms) : undef;
		foreach $dest (@dests) {
			if ($purges[$i]) {
				$current_id = undef;
				$pok = &purge_domain_backups(
					$dest, $purges[$i], $start_time, $asd);
				}
			$i++;
			}
		}

	# Run any after command
	if ($in{'oneoff'} && $sched->{'after'}) {
		&$first_print($text{'backup_arun'});
		$out = &backquote_command(
			"($sched->{'after'}) 2>&1 </dev/null");
		print "<pre>".&html_escape($out)."</pre>";
		if ($?) {
			&$second_print($text{'backup_arunfailed'});
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	PREFAILED:
	if ($ok) {
		&webmin_log("backup", $dests[0], undef,
			    { 'doms' => [ map { $_->{'dom'} } @doms ] });
		}

	&ui_print_footer("/$module_name/list_sched.cgi", $text{'sched_return'});
	}

# Flag backup as done
&stop_running_backup($runsched);
