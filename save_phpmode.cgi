#!/usr/local/bin/perl
# Save PHP options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err2'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$can || &error($text{'phpmode_ecannot'});
&require_apache();
$p = &domain_has_website($d);

# Check for option clashes
if (!$d->{'alias'} && $can == 2) {
	if (defined($in{'children_def'}) && !$in{'children_def'} &&
	    ($in{'children'} < 1 ||
	     $in{'children'} > $max_php_fcgid_children)) {
		&error(&text('phpmode_echildren', $max_php_fcgid_children));
		}
	}
if (!$d->{'alias'}) {
	if (defined($in{'maxtime_def'}) && !$in{'maxtime_def'} &&
	    $in{'maxtime'} !~ /^[1-9]\d*$/ && $in{'maxtime'} < 86400) {
		&error($text{'phpmode_emaxtime'});
		}
	}

# Check for working Apache suexec for PHP
if (!$d->{'alias'} && ($in{'mode'} eq 'cgi' || $in{'mode'} eq 'fcgid') &&
    $can == 2 && $p eq 'web') {
	$tmpl = &get_template($d->{'template'});
	$err = &check_suexec_install($tmpl);
	&error($err) if ($err);
	}

# Start telling the user what is being done
&ui_print_unbuffered_header(&domain_in($d), $text{'phpmode_title'}, "");
&obtain_lock_web($d);
&obtain_lock_dns($d);
&obtain_lock_logrotate($d) if ($d->{'logrotate'});

# Save PHP execution mode
$mode = $oldmode = &get_domain_php_mode($d);
if (defined($in{'mode'}) && $oldmode ne $in{'mode'} && $can == 2) {
	&$first_print(&text('phpmode_moding', $text{'phpmode_'.$in{'mode'}}));
	my $err = &save_domain_php_mode($d, $in{'mode'});
	if ($err) {
		&$second_print(&text('phpmode_emoding', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		$mode = $in{'mode'};
		}
	$anything++;
	}

# Save PHP fcgi children
$nc = $in{'children_def'} ? 0 : $in{'children'};
if (defined($in{'children_def'}) &&
    $nc != &get_domain_php_children($d) && $can == 2) {
	&$first_print($nc ? &text('phpmode_kidding', $nc)
			  : $text{'phpmode_nokids'});
	&save_domain_php_children($d, $nc);
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save max PHP run time (in both Apache and PHP configs)
$max = $in{'maxtime_def'} ? 0 : $in{'maxtime'};
if (defined($in{'maxtime_def'}) &&
    &get_fcgid_max_execution_time($d) != $max) {
	&$first_print($max ? &text('phpmode_maxing', $max)
			   : $text{'phpmode_nomax'});
	&set_fcgid_max_execution_time($d, $max);
	&set_php_max_execution_time($d, $max);
	&$second_print($text{'setup_done'});
        $anything++;
	}

# Update PHP versions
@avail = &list_available_php_versions($d, $mode);
if (&can_edit_phpver($d) && !$d->{'alias'} && $mode && $mode ne "mod_php" &&
    @avail > 1) {
	my %enabled = map { $_, 1 } split(/\0/, $in{'d'});
	my $phd = &public_html_dir($d);
	for(my $i=0; defined($in{"dir_".$i}); $i++) {
		my $sd = $in{"dir_".$i};
		$sd =~ s/^\Q$phd\E\///;
		if (!$enabled{$i} && $i != 0) {
			# This directory can be disabled
			&$first_print(&text('phpmode_deldir',
				"<tt>".&html_escape($sd)."</tt>"));
			&delete_domain_php_directory($d, $in{"dir_".$i});
			&$second_print($text{'setup_done'});
			$anything++;
			}
		elsif ($in{"ver_$i"} ne $in{"oldver_$i"}) {
			# Directory version can be updated
			&$first_print(&text('phpmode_savedir',
				"<tt>".&html_escape($sd)."</tt>",
				$in{"ver_$i"}));
			$err = &save_domain_php_directory(
				$d, $in{"dir_$i"}, $in{"ver_$i"});
			&error($err) if ($err);
			&$second_print($text{'setup_done'});
			$anything++;
			}
		}
	if ($enabled{'new'}) {
		# Directory to add
                $in{'dir_new'} =~ /^[^\/]\S+$/ ||
                        &error($text{'phpver_enewdir'});
                $in{'dir_new'} =~ /^(http|https|ftp):/ &&
                        &error($text{'phpver_enewdir'});
		&$first_print(&text('phpmode_adddir',
			"<tt>".&html_escape($in{"dir_new"})."</tt>",
			$in{'ver_new'}));
                $err = &save_domain_php_directory(
			$d, $phd."/".$in{'dir_new'}, $in{'ver_new'});
                &error($err) if ($err);
		&$second_print($text{'setup_done'});
		$anything++;
		}
	}

if (!$anything) {
	&$first_print($text{'phpmode_nothing'});
	}

&save_domain($d);
&release_lock_logrotate($d) if ($d->{'logrotate'});
&release_lock_dns($d);
&release_lock_web($d);
&clear_links_cache($d);
&run_post_actions();

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

# All done
&webmin_log("phpmode", "domain", $d->{'dom'});
&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

