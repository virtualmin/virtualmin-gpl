#!/usr/local/bin/perl
# Save PHP options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$can || &error($text{'phpmode_ecannot'});
&require_apache();
$p = &domain_has_website($d);

# Check for option clashes
if (!$d->{'alias'} && $can == 2) {
	if (($in{'mode'} eq 'cgi' || $in{'mode'} eq 'fcgid') &&
	    defined($in{'suexec'}) && !$in{'suexec'}) {
		&error($text{'phpmode_esuexec'});
		}
	if ($in{'suexec'} && $apache::httpd_modules{'core'} >= 2.0 &&
	    !$apache::httpd_modules{'mod_suexec'}) {
		&error($text{'phpmode_emodsuexec'});
		}
	if (defined($in{'children_def'}) && !$in{'children_def'} &&
	    ($in{'children'} < 1 ||
	     $in{'children'} > $max_php_fcgid_children)) {
		&error(&text('phpmode_echildren', $max_php_fcgid_children));
		}
	}
if (!$d->{'alias'}) {
	if (defined($in{'maxtime_def'}) && !$in{'maxtime_def'} &&
	    $in{'maxtime'} !~ /^[1-9]\d*$/) {
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

# Validate HTML directory
if (!$d->{'alias'} && $d->{'public_html_dir'} !~ /\.\./ &&
    defined($in{'htmldir'})) {
	$in{'htmldir'} =~ /^[a-z0-9\.\-\_\/]+$/ ||
		&error($text{'phpmode_ehtmldir'});
	$in{'htmldir'} !~ /^\// && $in{'htmldir'} !~ /\/$/ ||
		&error($text{'phpmode_ehtmldir2'});
	$in{'htmldir'} !~ /\.\./ ||
		&error($text{'phpmode_ehtmldir3'});
	$in{'htmldir'} !~ /^domains(\/\S*)$/i ||
		&error($text{'phpmode_ehtmldir4'});
	}

# Start telling the user what is being done
&ui_print_unbuffered_header(&domain_in($d), $text{'phpmode_title'}, "");
&obtain_lock_web($d);
&obtain_lock_dns($d);
&obtain_lock_logrotate($d) if ($d->{'logrotate'});

# Save PHP execution mode
$oldmode = &get_domain_php_mode($d);
if (defined($in{'mode'}) && $oldmode ne $in{'mode'} && $can == 2) {
	&$first_print(&text('phpmode_moding', $text{'phpmode_'.$in{'mode'}}));
	&save_domain_php_mode($d, $in{'mode'});
	&$second_print($text{'setup_done'});
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

# Save Ruby execution mode
if (defined($in{'rubymode'}) && &get_domain_ruby_mode($d) ne $in{'rubymode'} &&
    $can == 2) {
	&$first_print(&text('phpmode_rmoding',
			    $text{'phpmode_'.$in{'rubymode'}}));
	&save_domain_ruby_mode($d, $in{'rubymode'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save suexec mode
if (defined($in{'suexec'}) && $in{'suexec'} != &get_domain_suexec($d) &&
    $can == 2) {
	&$first_print($in{'suexec'} ? $text{'phpmode_suexecon'}
				    : $text{'phpmode_suexecoff'});
	&save_domain_suexec($d, $in{'suexec'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save log writing mode
if (defined($in{'writelogs'}) && $can == 2) {
	$wl = &get_writelogs_status($d);
	if ($in{'writelogs'} && !$wl) {
		&setup_writelogs($d);
		&enable_writelogs($d);
		$anything++;
		}
	elsif (!$in{'writelogs'} && $wl) {
		&disable_writelogs($d);
		$anything++;
		}
	}

# Save match-all mode
$oldmatchall = &get_domain_web_star($d);
if (defined($in{'matchall'}) && $in{'matchall'} != $oldmatchall) {
	# Turn on or off
	&$first_print($in{'matchall'} ? $text{'phpmode_matchallon'}
				      : $text{'phpmode_matchalloff'});
	&save_domain_web_star($d, $in{'matchall'});
	if ($d->{'dns'}) {
		&save_domain_matchall_record($d, $in{'matchall'});
		}
	&$second_print($text{'setup_done'});
        $anything++;
	}

# Change default website
if (&can_default_website($d) && $in{'defweb'}) {
	&$first_print($text{'phpmode_defwebon'});
	$err = &set_default_website($d);
	if ($err) {
		&$second_print(&text('phpmode_defweberr', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	# Clear all left-frame links caches, as links to Apache may no
	# longer be valid
	&clear_links_cache();
        $anything++;
	}

# Change log file locations
if (defined($in{'alog'}) && !$d->{'alias'} && &can_log_paths()) {
	# Access log
	$oldalog = &get_website_log($d, 0);
	if ($oldalog && defined($in{'alog'}) && $oldalog ne $in{'alog'}) {
		&$first_print($text{'phpmode_setalog'});
		$err = &change_access_log($d, $in{'alog'});
		&$second_print(!$err ? $text{'setup_done'}
				     : &text('phpmode_logerr', $err));
		$anything++;
		}

	# Error log
	$oldelog = &get_website_log($d, 1);
	if ($oldelog && defined($in{'elog'}) && $oldelog ne $in{'elog'}) {
		&$first_print($text{'phpmode_setelog'});
		$err = &change_error_log($d, $in{'elog'});
		&$second_print(!$err ? $text{'setup_done'}
				     : &text('phpmode_logerr', $err));
		$anything++;
		}
	}

# Change HTML directory
if (defined($in{'htmldir'}) &&
    !$d->{'alias'} && $d->{'public_html_dir'} !~ /\.\./ &&
    $d->{'public_html_dir'} ne $in{'htmldir'}) {
	&$first_print($text{'phpmode_setdir'});
	$err = &set_public_html_dir($d, $in{'htmldir'});
	&$second_print(!$err ? $text{'setup_done'}
                             : &text('phpmode_htmldirerr', $err));
	$anything++;
	}

if (!$anything) {
	&$first_print($text{'phpmode_nothing'});
	}

&save_domain($d);
&release_lock_logrotate($d) if ($d->{'logrotate'});
&release_lock_dns($d);
&release_lock_web($d);
&run_post_actions();

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

# All done
&webmin_log("phpmode", "domain", $d->{'dom'});
&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

