#!/usr/local/bin/perl
# Save PHP options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpmode($d) || &error($text{'phpmode_ecannot'});
&set_all_null_print();

# Check for option clashes
if (($in{'mode'} eq 'cgi' || $in{'mode'} eq 'fcgid') && !$in{'suexec'}) {
	&error($text{'phpmode_esuexec'});
	}
&require_apache();
if ($in{'suexec'} && $apache::httpd_modules{'core'} >= 2.0 &&
    !$apache::httpd_modules{'mod_suexec'}) {
	&error($text{'phpmode_emodsuexec'});
	}
if (defined($in{'children'}) &&
    ($in{'children'} < 1 || $in{'children'} > $max_php_fcgid_children)) {
	&error(&text('phpmode_echildren', $max_php_fcgid_children));
	}

# Save PHP execution mode
&save_domain_php_mode($d, $in{'mode'});

# Save PHP fcgi children
if (defined($in{'children'})) {
	&save_domain_php_children($d, $in{'children'});
	}

# Save Ruby execution mode
&save_domain_ruby_mode($d, $in{'rubymode'});

# Save suexec mode
&save_domain_suexec($d, $in{'suexec'});

# Save log writing mode
$wl = &get_writelogs_status($d);
if ($in{'writelogs'} && !$wl) {
	&setup_writelogs($d);
	&enable_writelogs($d);
	}
elsif (!$in{'writelogs'} && $wl) {
	&disable_writelogs($d);
	}

&run_post_actions();

# All done
&webmin_log("phpmode", "domain", $d->{'dom'});
&domain_redirect($d);

