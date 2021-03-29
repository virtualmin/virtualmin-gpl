#!/usr/local/bin/perl
# Save website options options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'phpmode_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$can || &error($text{'phpmode_ecannot'});
&require_apache();
$p = &domain_has_website($d);

# Validate HTML directory
if (!$d->{'alias'} && $d->{'public_html_dir'} !~ /\.\./ &&
    defined($in{'htmldir'})) {
	$in{'htmldir'} =~ /^[a-z0-9\.\-\_\/]+$/i ||
		&error($text{'phpmode_ehtmldir'});
	$in{'htmldir'} !~ /^\// && $in{'htmldir'} !~ /\/$/ ||
		&error($text{'phpmode_ehtmldir2'});
	$in{'htmldir'} !~ /\.\./ ||
		&error($text{'phpmode_ehtmldir3'});
	$in{'htmldir'} !~ /^domains(\/\S*)$/i ||
		&error($text{'phpmode_ehtmldir4'});
	}

# Validate SSI suffix
if ($in{'ssi'} == 1) {
	$in{'suffix'} =~ /^\.([a-z0-9\.\_\-]+)$/i ||
		&error($text{'phpmode_essisuffix'});
	}

# Start telling the user what is being done
&ui_print_unbuffered_header(&domain_in($d), $text{'phpmode_title'}, "");
&obtain_lock_web($d);
&obtain_lock_dns($d);
&obtain_lock_logrotate($d) if ($d->{'logrotate'});

# Save Ruby execution mode
if (defined($in{'rubymode'}) && &get_domain_ruby_mode($d) ne $in{'rubymode'} &&
    $can == 2) {
	&$first_print(&text('phpmode_rmoding',
			    $text{'phpmode_'.$in{'rubymode'}}));
	&save_domain_ruby_mode($d, $in{'rubymode'});
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

# Save SSI mode
($oldssi, $oldsuffix) =  &get_domain_web_ssi($d);
if (defined($in{'ssi'}) && ($in{'ssi'} != $oldssi ||
			    $in{'ssi'} == 1 && $in{'suffix'} ne $oldsuffix)) {
	if ($in{'ssi'}) {
		&$first_print(&text('phpmode_ssion', $in{'suffix'}));
		$err = &save_domain_web_ssi($d, $in{'suffix'});
		}
	else {
		&$first_print(&text('phpmode_ssioff'));
		$err = &save_domain_web_ssi($d, undef);
		}
	if ($err) {
		&$second_print(&text('phpmode_ssierr', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
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
	$logchanged = 0;
	if ($oldalog && defined($in{'alog'}) && $oldalog ne $in{'alog'}) {
		&$first_print($text{'phpmode_setalog'});
		$err = &change_access_log($d, $in{'alog'});
		&$second_print(!$err ? $text{'setup_done'}
				     : &text('phpmode_logerr', $err));
		$anything++;
		$logchanged++;
		}

	# Error log
	$oldelog = &get_website_log($d, 1);
	if ($oldelog && defined($in{'elog'}) && $oldelog ne $in{'elog'}) {
		&$first_print($text{'phpmode_setelog'});
		$err = &change_error_log($d, $in{'elog'});
		&$second_print(!$err ? $text{'setup_done'}
				     : &text('phpmode_logerr', $err));
		$anything++;
		$logchanged++;
		}

	# Update Webmin permissions
	if ($logchanged) {
		&refresh_webmin_user($d);
		}
	}

# Update SSL redirect
if (&domain_has_ssl($d) && &can_edit_redirect() && &has_web_redirects($d)) {
	my @redirects = map { &remove_wellknown_redirect($_) }
			    &list_redirects($d);
	my ($defredir) = grep { $_->{'path'} eq '/' &&
			        $_->{'http'} && !$_->{'https'} } @redirects;
	if ($defredir && !$in{'sslredir'}) {
		&$first_print($text{'phpmode_ssloff'});
		$defredir = &add_wellknown_redirect($defredir);
		my $err = &delete_redirect($d, $defredir);
		&$second_print($err ? $err : $text{'setup_done'});
		$anything++;
		}
	elsif (!$defredir && $in{'sslredir'}) {
		&$first_print($text{'phpmode_sslon'});
		my $err = &create_redirect($d, &get_redirect_to_ssl($d));
		&$second_print($err ? $err : $text{'setup_done'});
		$anything++;
		}
	}

# Change HTML directory
if (defined($in{'htmldir'}) &&
    !$d->{'alias'} && $d->{'public_html_dir'} !~ /\.\./ &&
    $d->{'public_html_dir'} ne $in{'htmldir'}) {
	&$first_print($text{'phpmode_setdir'});
	$err = &set_public_html_dir($d, $in{'htmldir'}, $in{'htmlrename'});
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
&webmin_log("website", "domain", $d->{'dom'});
&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

