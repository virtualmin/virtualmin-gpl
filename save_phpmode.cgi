#!/usr/local/bin/perl
# Save PHP options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpmode($d) || &error($text{'phpmode_ecannot'});
&require_apache();

# Check for option clashes
if (!$d->{'alias'}) {
	if (($in{'mode'} eq 'cgi' || $in{'mode'} eq 'fcgid') &&
	    !$in{'suexec'}) {
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

# Start telling the user what is being done
&ui_print_unbuffered_header(&domain_in($d), $text{'phpmode_title'}, "");
&obtain_lock_web($d);
&obtain_lock_dns($d);

# Save PHP execution mode
$oldmode = &get_domain_php_mode($d);
if (defined($in{'mode'}) && $oldmode ne $in{'mode'}) {
	&$first_print(&text('phpmode_moding', $text{'phpmode_'.$in{'mode'}}));
	&save_domain_php_mode($d, $in{'mode'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save PHP fcgi children
$nc = $in{'children_def'} ? 0 : $in{'children'};
if (defined($in{'children_def'}) &&
    $nc != &get_domain_php_children($d)) {
	&$first_print($nc ? &text('phpmode_kidding', $nc)
			  : $text{'phpmode_nokids'});
	&save_domain_php_children($d, $nc);
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save Ruby execution mode
if (defined($in{'rubymode'}) && &get_domain_ruby_mode($d) ne $in{'rubymode'}) {
	&$first_print(&text('phpmode_rmoding',
			    $text{'phpmode_'.$in{'rubymode'}}));
	&save_domain_ruby_mode($d, $in{'rubymode'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save suexec mode
if (defined($in{'suexec'}) && $in{'suexec'} != &get_domain_suexec($d)) {
	&$first_print($in{'suexec'} ? $text{'phpmode_suexecon'}
				    : $text{'phpmode_suexecoff'});
	&save_domain_suexec($d, $in{'suexec'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save log writing mode
if (defined($in{'writelogs'})) {
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

if (!$anything) {
	&$first_print($text{'phpmode_nothing'});
	}

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

