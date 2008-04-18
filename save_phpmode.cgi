#!/usr/local/bin/perl
# Save PHP options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpmode($d) || &error($text{'phpmode_ecannot'});

# Check for option clashes
if (($in{'mode'} eq 'cgi' || $in{'mode'} eq 'fcgid') && !$in{'suexec'}) {
	&error($text{'phpmode_esuexec'});
	}
&require_apache();
if ($in{'suexec'} && $apache::httpd_modules{'core'} >= 2.0 &&
    !$apache::httpd_modules{'mod_suexec'}) {
	&error($text{'phpmode_emodsuexec'});
	}
if (defined($in{'children'}) && !$in{'children_def'} &&
    ($in{'children'} < 1 || $in{'children'} > $max_php_fcgid_children)) {
	&error(&text('phpmode_echildren', $max_php_fcgid_children));
	}

# Start telling the user what is being done
&ui_print_unbuffered_header(&domain_in($d), $text{'phpmode_title'}, "");
&obtain_lock_web($d);

# Save PHP execution mode
$oldmode = &get_domain_php_mode($d);
if ($oldmode ne $in{'mode'}) {
	&$first_print(&text('phpmode_moding', $text{'phpmode_'.$in{'mode'}}));
	&save_domain_php_mode($d, $in{'mode'});
	&$second_print($text{'setup_done'});
	$anything++;
	}

# Save PHP fcgi children
$nc = $in{'children_def'} ? 0 : $in{'children'};
if (defined($in{'children'}) &&
    $nc != &get_domain_php_children($d)) {
	&$first_print($nc ? &text('phpmode_kidding', $in{'children'})
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

if (!$anything) {
	&$first_print($text{'phpmode_nothing'});
	}

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

