#!/usr/local/bin/perl
# Upgrade from Virtualmin GPL to Pro

require './virtual-server-lib.pl';
&foreign_require("webmin");
&foreign_require("cron");
&can_edit_templates() || &error($text{'upgrade_ecannot'});
&error_setup($text{'upgrade_err'});
&ReadParse();

# Make sure the serial and key are valid, by trying a HTTP request
$in{'serial'} =~ /^\S+$/ || &error($text{'upgrade_eserial'});
$in{'key'} =~ /^\S+$/ || &error($text{'upgrade_ekey'});
$in{'key'} eq 'AMAZON' && &error($text{'upgrade_eamazon'});
$in{'key'} eq 'DEMO' && &error($text{'upgrade_eamazon'});
&http_download($upgrade_virtualmin_host, $upgrade_virtualmin_port,
	       $upgrade_virtualmin_testpage, \$out, \$error, undef, 0,
	       $in{'serial'}, $in{'key'}, undef, 0, 1);
if ($error =~ /401/) {
	&error($text{'upgrade_elogin'});
	}
elsif ($error) {
	&error(&text('upgrade_econnect', $error));
	}
if (&webmin::shared_root_directory()) {
	&error(&text('upgrade_esharedroot', "<tt>$root_directory</tt>"));
	}

# Verify that the install is one we can upgrade
chop($itype = &read_file_contents("$module_root_directory/install-type"));
$witype = &webmin::get_install_type() || "tar.gz";
if ($itype eq "rpm") {
	# Check for repo file
	-r $virtualmin_yum_repo || &error($text{'upgrade_eyumrepo'});

	# Make sure Webmin was also from an RPM
	$witype eq "rpm" ||
		&error(&text('upgrade_etypematch', $itype, $witype));

	# Make sure YUM works
	&foreign_require("software");
	($wvs) = grep { $_->{'name'} eq 'wbm-virtual-server' }
		      &software::update_system_available();
	if (!$wvs) {
		&error(&text('upgrade_eyumlist',
		 	     '<tt>wbm-virtual-server</tt>'));
		}
	}
elsif ($itype eq "deb") {
	# Check for Virtualmin repo in sources.list
	$sources_list = "/etc/apt/sources.list";
	$lref = &read_file_lines($sources_list);
	$found = 0;
	foreach $l (@$lref) {
		if ($l =~ /^deb\s+http:\/\/software\.virtualmin\.com/) {
			$found = 1;
			}
		}
	$found || $text{'upgrade_edebrepo'};

	# Make sure Webmin was also from a Debian package
	$witype eq "deb" ||
		&error(&text('upgrade_etypematch', $itype, $witype));
	}

&ui_print_unbuffered_header(undef, $text{'upgrade_title'}, "");

$SIG{'TERM'} = 'IGNORE';	# Stop process from being killed on upgrade

# Write out the licence file
&$first_print($text{'upgrade_file'});
&lock_file($virtualmin_license_file);
%lfile = ( 'SerialNumber' => $in{'serial'},
	   'LicenseKey' => $in{'key'} );
&write_env_file($virtualmin_license_file, \%lfile);
&set_ownership_permissions(undef, undef, 0700, $virtualmin_license_file);
&unlock_file($virtualmin_license_file);
&$second_print($text{'setup_done'});

# Work out how we were installed. Possible sources are from the wbm.gz files,
# from the GPL YUM repo, and from the GPL Debian repo
if ($itype eq "rpm") {
	# GPL YUM repo. Replace it with the Pro version
	local $found;
	local $lref = &read_file_lines($virtualmin_yum_repo);
	foreach my $l (@$lref) {
		if ($l =~ /^baseurl=.*\/gpl(\/.*)/) {
			$l = "baseurl=http://$in{'serial'}:$in{'key'}\@$upgrade_virtualmin_host$1";
			$found++;
			}
		}
	&flush_file_lines($virtualmin_yum_repo);
	$found || &error(&text('upgrade_eyumfile',
			       "<tt>$virtualmin_yum_repo</tt>"));

	# Clear all YUM caches
	&$first_print($text{'upgrade_yumclear'});
	&execute_command("yum clean all");
	&$second_print($text{'setup_done'});

	# Update all Virtualmin-related packages
	&foreign_require("software");
	foreach $p (&software::update_system_available()) {
		if ($p->{'name'} eq 'wbm-virtualmin-multi-login' &&
		    !&foreign_check('server-manager')) {
			# Requires Cloudmin
			next;
			}
		if ($p->{'name'} eq "webmin" || $p->{'name'} eq "usermin" ||
		    $p->{'name'} =~ /^(wbm|wbt|usm|ust)-/) {
			push(@packages, $p->{'name'});
			}
		}
	&$first_print(&text('upgrade_rpms',
		join(" ", map { "<tt>$_</tt>" } @packages)));
	print "<pre>";
	&clean_environment();
	open(YUM, "yum -y install ".join(" ", @packages)." 2>&1 |");
	while(<YUM>) {
		print &html_escape($_);
		}
	close(YUM);
	$errors++ if ($?);
	&reset_environment();
	&$second_print($text{'setup_done'});
	}
elsif ($itype eq "deb") {
	# GPL APT repo .. change to use the Pro one
	$lref = &read_file_lines($sources_list);
	foreach $l (@$lref) {
		if ($l =~ /^deb\s+http:\/\/software\.virtualmin\.com\/gpl(\/.*)/) {
			$l = "deb http://$in{'serial'}:$in{'key'}\@software.virtualmin.com$1";
			}
		}
	&flush_file_lines($sources_list);

	# Force refresh of packages
	&$first_print($text{'upgrade_update'});
	print "<pre>";
	open(YUM, "apt-get update 2>&1 |");
	while(<YUM>) {
		print &html_escape($_);
		}
	close(YUM);
	&$second_print($text{'setup_done'});

	# Update all Virtualmin-related packages
	&foreign_require("software");
	foreach $p (&software::update_system_available()) {
		if ($p->{'name'} eq 'webmin-virtualmin-multi-login' &&
		    !&foreign_check('server-manager')) {
			# Requires Cloudmin
			next;
			}
		if ($p->{'name'} eq "webmin" || $p->{'name'} eq "usermin" ||
		    $p->{'name'} =~ /^(webmin|usermin)-(virtualmin|virtual-server|security-updates)/) {
			if ($p->{'name'} eq 'webmin-virtual-server') {
				# For the Virtualmin package, select pro
				# version explicitly so that the GPL is
				# replaced.
				local ($ver) = grep { !/\.gpl/ }
					&apt_package_versions($p->{'name'});
                                push(@packages, $ver ? $p->{'name'}."=".$ver
						     : $p->{'name'});
				}
			else {
				push(@packages, $p->{'name'});
				}
			}
		}
	&$first_print(&text('upgrade_debs',
		join(" ", map { "<tt>$_</tt>" } @packages)));
	print "<pre>";
	&clean_environment();
	open(YUM, "apt-get -y --force-yes -f install ".join(" ", @packages)." 2>&1 |");
	while(<YUM>) {
		print &html_escape($_);
		}
	close(YUM);
	$errors++ if ($?);
	&reset_environment();
	&$second_print($text{'setup_done'});
	}
else {
	# Assume wbm.gz install. Download all the Pro modules, and install them
	&$first_print($text{'upgrade_mods'});
	&$indent_print();
	&http_download($upgrade_virtualmin_host, $upgrade_virtualmin_port,
		       $upgrade_virtualmin_updates, \$uout, undef, undef, 0,
		       $in{'serial'}, $in{'key'}, undef, 0, 1);
	foreach $line (split(/\r?\n/, $uout)) {
		($mod, $ver, $path, $os_support, $desc) = split(/\t/, $line);
		next if (!$mod);
		&$first_print(&text('upgrade_mod', $mod, $ver));

		# Check if we have a later version
		local %minfo = &get_module_info($mod);
		local %tinfo = &get_theme_info($mod);
		local %info = %minfo ? %minfo : %tinfo;
		local $current_ver = &round_hundred($info{'version'});
		local $new_ver = &round_hundred($ver);
		if (%info) {
			# Already installed .. but can we upgrade?
			$can_upgrade = 0;
			if ($mod eq "virtual-server" &&
			    $info{'version'} =~ /gpl/i &&
			    $ver !~ /gpl/i) {
				# GPL upgrading to pro - always do it
				$can_upgrade = 1;
				}
			elsif ($new_ver >= $current_ver) {
				# Module from pro repo is higher version or
				# same .. upgrade
				$can_upgrade = 1;
				}
			if (!$can_upgrade) {
				&$second_print(&text('upgrade_gotver',
						     $info{'version'}));
				if ($mod eq "virtual-server") {
					$errors++;
					goto PAGEEND;
					}
				next;
				}
			}

		# Download the file
		($mhost, $mport, $mpage, $mssl) =
			&parse_http_url($path, $upgrade_virtualmin_host,
					$upgrade_virtualmin_port,
					$upgrade_virtualmin_updates, 0);
		($mfile = $mpage) =~ s/^(.*)\///;
		$mtemp = &transname($mfile);
		$merror = undef;
		&$indent_print();
		$progress_callback_url = ($mssl ? "https://" : "http://").
					 $mhost.$mpage;
		&http_download($mhost, $mport, $mpage, $mtemp, \$merror,
			       \&progress_callback, $mssl,
				$in{'serial'}, $in{'key'});
		&$outdent_print();
		if ($merror) {
			&$second_print(&text('upgrade_moderr', $merror));
			$errors++;
			if ($mod eq "virtual-server") {
				goto PAGEEND;
				}
			next;
			}

		# Actually install it
		$irv = &webmin::install_webmin_module($mtemp, 1, 0,
						      [ $base_remote_user ]);
		&set_all_html_print();	# In case changed by postinstall
		if (ref($irv)) {
			# Worked!
			local $dir = $irv->[1]->[0];
			$dir =~ s/^.*\///g;
			local %tinfo = &get_theme_info($dir);
			&$second_print(&text(%tinfo ? 'upgrade_themeok' :
						      'upgrade_modok', $irv->[0]->[0]));
			}
		else {
			# Install failed for some reason
			&$second_print(&text('upgrade_modfailed', $irv));
			$errors++;
			if ($mod eq "virtual-server") {
				goto PAGEEND;
				}
			}
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});

	# Configure the Webmin updates service
	&$first_print($text{'upgrade_sched'});
	@upsource = split(/\t/, $webmin::config{'upsource'});
	@upsource = &unique(@upsource,
		"http://$upgrade_virtualmin_host:$upgrade_virtualmin_port$upgrade_virtualmin_updates",
		"http://$webmin::update_host:$webmin::update_port$webmin::update_page");
	&lock_file($webmin::module_config_file);
	$webmin::config{'upsource'} = join("\t", @upsource);
	$webmin::config{'upthird'} = 1;
	$webmin::config{'upuser'} = $in{'serial'};
	$webmin::config{'uppass'} = $in{'key'};
	$webmin::config{'upshow'} = 0;
	&webmin::save_module_config();
	&unlock_file($webmin::module_config_file);
	@jobs = &cron::list_cron_jobs();
	$upjob = &webmin::find_cron_job(\@jobs);
	if ($upjob) {
		&$second_print($text{'upgrade_schedok'});
		}
	else {
		&$second_print(&text('upgrade_schednot',
				     "../webmin/edit_upgrade.cgi",
				     $webmin::module_info{'desc'}));
		}

	# Use the Virtualmin framed theme
	if ($current_theme ne "virtual-server-theme" &&
	    $current_theme ne "thejax-theme") {
		%tinfo = &get_theme_info("virtual-server-theme");
		if (%tinfo) {
			&$first_print(&text('upgrade_theme', $tinfo{'desc'}));
			&lock_file("$config_directory/config");
			$gconfig{'theme'} = "virtual-server-theme";
			&write_file("$config_directory/config", \%gconfig);
			&unlock_file("$config_directory/config");
			&lock_file($ENV{'MINISERV_CONFIG'});
			&get_miniserv_config(\%miniserv);
			$miniserv{'preroot'} = "virtual-server-theme";
			&put_miniserv_config(\%miniserv);
			&unlock_file($ENV{'MINISERV_CONFIG'});
			&reload_miniserv();
			&$second_print($text{'setup_done'});
			}
		}
	}

# Clear package updates caches, as we now have new updates available
if (&foreign_installed("package-updates")) {
	&foreign_require("package-updates");
	unlink($package_updates::available_cache_file);
	unlink($package_updates::current_cache_file);
	unlink($package_updates::updates_cache_file);
	}

PAGEEND:
&run_post_actions();
if ($errors) {
	print "<b>$text{'upgrade_problems'}</b><p>\n";
	}
else {
	print "<b>$text{'upgrade_complete'}</b><p>\n";
	}

&webmin_log("upgrade");
&ui_print_footer("", $text{'index_return'});

sub apt_package_versions
{
local ($name) = @_;
local @rv;
open(OUT, "apt-cache show ".quotemeta($name)." |");
while(<OUT>) {
	if (/^Version:\s+(\S+)/) {
		push(@rv, $1);
		}
	}
close(OUT);
return sort { $b cmp $a } @rv;
}

# round_hundred(version)
# Given a version line x.yyz, returns x.yy.
# Also strips suffixes like .gpl.
sub round_hundred
{
local ($v) = @_;
if ($v =~ /^(\d+)\.(\d\d)/) {
	return "$1.$2";
	}
elsif ($v =~ /^([0-9\.]+)/) {
	return $1;
	}
else {
	return $v;
	}
}

