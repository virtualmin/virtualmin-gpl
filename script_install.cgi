#!/usr/local/bin/perl
# Actually install some script

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
$d->{'web'} && $d->{'dir'} || &error($text{'scripts_eweb'});

$sname = $in{'script'};
$ver = $in{'version'};
$script = &get_script($sname);
@got = &list_domain_scripts($d);
if ($in{'upgrade'}) {
	($sinfo) = grep { $_->{'id'} eq $in{'upgrade'} } @got;
	}
else {
	$script->{'avail'} || &error($text{'scripts_eavail'});
	&can_script_version($script, $ver) || &error($text{'scripts_eavail'});
	}
&error_setup($text{'scripts_ierr'});

# Check depends again
$derr = &{$script->{'depends_func'}}($d, $ver);
&error(&text('scripts_edep', $derr)) if ($derr);

# Parse inputs
%incopy = %in;
$opts = &{$script->{'parse_func'}}($d, $ver, \%incopy, $sinfo);
if ($opts && !ref($opts)) {
	&error($opts);
	}

# Check for a clash, unless upgrading
if (!$sinfo) {
	($clash) = grep { $_->{'opts'}->{'path'} eq $opts->{'path'} } @got;
	$clash && &error(&text('scripts_eclash', "<tt>$opts->{'dir'}</tt>"));
	}

# Check options, unless upgrading
if (defined(&{$script->{'check_func'}}) && !$sinfo) {
	$oerr = &{$script->{'check_func'}}($d, $ver, $opts, $sinfo);
	if ($oerr) {
		&error($oerr);
		}
	}

# Check for install into non-empty directory, unless upgrading
if (-d $opts->{'dir'} && !$sinfo && !$in{'confirm'}) {
	opendir(DESTDIR, $opts->{'dir'});
	foreach $f (readdir(DESTDIR)) {
		if ($f ne "." && $f ne ".." && $f !~ /^(index|welcome)\./) {
			$fcount++;
			}
		}
	closedir(DESTDIR);
	if ($fcount > 0) {
		# Has some files already .. ask the user if he is sure
		&ui_print_header(&domain_in($d), $text{'scripts_intitle'}, "");
		print "<center>\n";
		print &ui_form_start("script_install.cgi", "post");
		foreach my $i (keys %in) {
			print &ui_hidden($i, $in{$i}),"\n";
			}
		print &text('scripts_rusurei', $script->{'desc'},
			    "<tt>$opts->{'dir'}</tt>", $fcount,
			    &nice_size(&disk_usage_kb($opts->{'dir'})*1024)),
		      "<p>\n";
		print &ui_form_end([ [ "confirm", $text{'scripts_iok'} ] ]);
		print "</center>\n";
		&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}",
				 $text{'scripts_return'},
				 &domain_footer_link($d));
		exit;
		}
	}

# Setup PHP version
$phpvfunc = $script->{'php_vers_func'};
if (defined(&$phpvfunc)) {
	@vers = &$phpvfunc($d, $ver);
	$phpver = &setup_php_version($d, \@vers, $opts->{'path'});
	if (!$phpver) {
		&error(&text('scripts_ephpvers', join(" ", @vers)));
		}
	}

&ui_print_unbuffered_header(&domain_in($d),
	$sinfo ? $text{'scripts_uptitle'} : $text{'scripts_intitle'}, "");

# First fetch needed files
$ferr = &fetch_script_files($d, $ver, $opts, $sinfo, \%gotfiles);
&error($ferr) if ($ferr);
print "<br>\n";

# Install needed PHP and Perl modules
$modok = &setup_php_modules($d, $script, $ver, $phpver, $opts);
if ($modok) {
	$modok = &setup_pear_modules($d, $script, $ver, $phpver, $opts);
	}
if ($modok) {
	$modok = &setup_perl_modules($d, $script, $ver, $opts);
	}
if (!$modok) {
	&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}",
			 $text{'scripts_return'},
			 &domain_footer_link($d));
	exit;
	}

# Call the install program
&$first_print(&text('scripts_installing', $script->{'desc'}, $ver));
($ok, $msg, $desc, $url) = &{$script->{'install_func'}}($d, $ver, $opts, \%gotfiles, $sinfo);
&$indent_print();
print $msg,"<br>\n";
&$outdent_print();
if ($ok) {
	&$second_print($text{'setup_done'});

	# Record script install in domain
	if ($sinfo) {
		&remove_domain_script($d, $sinfo);
		}
	&add_domain_script($d, $sname, $ver, $opts, $desc, $url);

	# Config web server for PHP
	if (&indexof("php", @{$script->{'uses'}}) >= 0) {
		&$first_print($text{'scripts_apache'});
		if (&setup_web_for_php($d, $script)) {
			&$second_print($text{'setup_done'});
			&restart_apache();
			}
		else {
			&$second_print($text{'scripts_aalready'});
			}
		}

	&run_post_actions();

	&webmin_log("install", "script", $sname, { 'ver' => $ver,
						   'desc' => $desc,
						   'dom' => $d->{'dom'},
						   'url' => $url });
	}
else {
	&$second_print($text{'scripts_failed'});
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

