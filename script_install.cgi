#!/usr/local/bin/perl
# Actually install some script

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$ENV{'HTTP_REFERER'} = "list_scripts.cgi?dom=$in{'dom'}";
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
&domain_has_website($d) && $d->{'dir'} || &error($text{'scripts_eweb'});

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

# Validate user and pass
if ($in{'upgrade'}) {
	# Same as before
	$domuser = $sinfo->{'user'} || $d->{'user'};
	$dompass = $sinfo->{'pass'} || $d->{'pass'};
	}
else {
	$domuser = $d->{'user'};
	$dompass = $d->{'pass'} || &random_password(8);
	if ($in{'passmode'} && !$in{'passmode_def'}) {
		if ($in{'passmode'} == 1 || $in{'passmode'} == 3) {
			# Check username
			$in{'passmodeuser'} =~ /^[a-z0-9\.\-\_]+$/i ||
				&error($text{'scripts_epassmodeuser'});
			$domuser = $in{'passmodeuser'};
			}
		if ($in{'passmode'} == 1 || $in{'passmode'} == 2) {
			$dompass = $in{'passmodepass'};
			}
		}
	}

# Re-check the public html directory
&find_html_cgi_dirs($d);
&save_domain($d);

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

# Check for files in the script's directory
$found = 0;
if (-d $opts->{'dir'} && !$sinfo && !$in{'confirm'}) {
	opendir(DESTDIR, $opts->{'dir'});
	foreach $f (readdir(DESTDIR)) {
		if ($f ne "." && $f ne ".." && $f !~ /^(index|welcome)\./) {
			$fcount++;
			}
		}
	closedir(DESTDIR);
	}

&ui_print_unbuffered_header(&domain_in($d),
	$sinfo ? $text{'scripts_uptitle'} : $text{'scripts_intitle'}, "");

if (!$fcount) {
	# Install needed packages (unless we are going to prompt for
	# overwrite confirmation)
	&setup_script_packages($script, $d);
	}

# Check depends again
$derr = &check_script_depends($script, $d, $ver, $sinfo);
&error(&text('scripts_edep', $derr)) if ($derr);

# Check for install into non-empty directory, unless upgrading
if ($fcount > 0) {
	# Has some files already .. ask the user if he is sure
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

# Get locks
&obtain_lock_web($d);
&obtain_lock_cron($d);

# Setup PHP version
$phpvfunc = $script->{'php_vers_func'};
if (defined(&$phpvfunc)) {
	@vers = &$phpvfunc($d, $ver);
	$phpver = &setup_php_version($d, \@vers, $opts->{'path'});
	if (!$phpver) {
		&error(&text('scripts_ephpvers', join(" ", @vers)));
		}
	$opts->{'phpver'} = $phpver;
	}

# First fetch needed files
$ferr = &fetch_script_files($d, $ver, $opts, $sinfo, \%gotfiles);
&error($ferr) if ($ferr);
print "<br>\n";

# Install needed PHP and Perl modules
if (!&setup_script_requirements($d, $script, $ver, $phpver, $opts)) {
	&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}",
			 $text{'scripts_return'}, &domain_footer_link($d));
	exit;
	}

# Disable PHP timeouts
$t = &disable_script_php_timeout($d);

# Restart Apache now if needed
&run_post_actions();

# Call the install function
&$first_print(&text('scripts_installing', $script->{'desc'}, $ver));
($ok, $msg, $desc, $url, $suser, $spass) =
	&{$script->{'install_func'}}($d, $ver, $opts, \%gotfiles, $sinfo,
				     $domuser, $dompass);
&$indent_print();
print $msg,"<p>\n";
if ($ok && $script->{'site'}) {
	print &text('scripts_sitelink', $script->{'site'}),"<p>\n";
	}
if ($ok > 0 && !$sinfo) {
	# Show login details
	if ($suser && $spass) {
		print &text('scripts_userpass',
			    "<tt>$suser</tt>", "<tt>$spass</tt>"),"<p>\n";
		}
	elsif ($suser) {
		print &text('scripts_useronly', "<tt>$suser</tt>"),"<p>\n";
		}
	elsif ($spass) {
		print &text('scripts_passonly', "<tt>$spass</tt>"),"<p>\n";
		}
	}
&$outdent_print();

# Re-enable script PHP timeout
&enable_script_php_timeout($d, $t);

if ($ok) {
	&$second_print($ok < 0 ? $text{'scripts_epartial'}
			       : $text{'setup_done'});

	# Record script install in domain
	if ($sinfo) {
		&remove_domain_script($d, $sinfo);
		}
	$sinfo = &add_domain_script($d, $sname, $ver, $opts, $desc, $url,
			   $sinfo ? ( $sinfo->{'user'}, $sinfo->{'pass'} )
				  : ( $suser, $spass ),
			   $ok < 0 ? $msg : undef);
	&run_post_actions();

	&webmin_log("install", "script", $sname, { 'ver' => $ver,
						   'desc' => $desc,
						   'dom' => $d->{'dom'},
						   'url' => $url });
	}
else {
	&$second_print($text{'scripts_failed'});
	&run_post_actions();
	}

&release_lock_web($d);
&release_lock_cron($d);

&ui_print_footer(
	$sinfo ? ( "edit_script.cgi?dom=$in{'dom'}&script=$sinfo->{'id'}",
		   $text{'scripts_ereturn'} ) : ( ),
	"list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
	&domain_footer_link($d));

