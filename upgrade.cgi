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
	       $upgrade_virtualmin_testpage, \$out, \$error, undef, 1,
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
	$lref = &read_file_lines($virtualmin_apt_repo);
	$found = 0;
	foreach $l (@$lref) {
		if ($l =~ /^deb(.*?)(http|https):\/\/$upgrade_virtualmin_host/) {
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
	&$first_print($text{'upgrade_addrepo'});
	# GPL YUM repo. Replace it with the Pro version
	local $found;
	local $lref = &read_file_lines($virtualmin_yum_repo);
	foreach my $l (@$lref) {
		# New repos have GPL in title too
		if ($l =~ /^name=/ && $l =~ /Virtualmin\s+\d+\s+GPL/) {
			$l =~ s/(GPL)/Professional/;
		}
		# New repo format such as /vm/7/gpl/rpm/noarch/
		elsif ($l =~ /noarch/ && $l =~ /^baseurl=.*\/(vm\/(?|([7-9])|([0-9]{2,4}))\/(gpl)(\/.*))/) {
			my $path = $1;
			$path =~ s/(gpl)/pro/;
			$l = "baseurl=https://$in{'serial'}:$in{'key'}\@$upgrade_virtualmin_host/$path";
			$found++;
			}
		elsif ($l =~ /^baseurl=.*\.com(\/.*)\/gpl(\/.*)/ || 
			$l =~ /^baseurl=.*\/gpl(\/.*)/) {
			$l = "baseurl=https://$in{'serial'}:$in{'key'}\@$upgrade_virtualmin_host$1$2";
			$found++;
			}

		# If restarting upgrade which failed before for whatever reason
		elsif ($l =~ /^baseurl=https:\/\/$in{'serial'}:$in{'key'}/) {
			$found++;
			}
		}
	&flush_file_lines($virtualmin_yum_repo);
	&$second_print($text{'setup_done'});
	$found || &error(&text('upgrade_eyumfile',
			       "<tt>$virtualmin_yum_repo</tt>"));

	# Clean package manager cache
	if (&foreign_available("package-updates")) {
		&foreign_require("package-updates");
		&$first_print($package_updates::text{'refresh_clearing'});
		&package_updates::flush_package_caches();
		&package_updates::clear_repository_cache();
		&$second_print($package_updates::text{'refresh_done'});
		}

	# Update Virtualmin to Pro, and install support module
	my @packages = ('wbm-virtual-server', 'wbm-virtualmin-support');

	# Run the upgrade
	my $upgrade_to_pro_output;
	&$first_print($text{'upgrade_to_pro'});
	&clean_environment();
	open(YUM, "yum -y install ".join(" ", @packages)." 2>&1 |");
	while(<YUM>) {
		$upgrade_to_pro_output .= &html_escape($_);
		}
	close(YUM);
	$errors++ if ($?);
	&reset_environment();
	if ($?) {
		&$second_print($text{'setup_failed'});
		print "<pre>";
		print $upgrade_to_pro_output;
		print "</pre>";
		}
	else {
		&$second_print($text{'setup_done'});
		&$second_print($text{'upgrade_success'});
		}
	}
elsif ($itype eq "deb") {
	# GPL APT repo .. change to use the Pro one
	&$first_print($text{'upgrade_addrepo'});
	my $apt_old_auth = !-d $virtualmin_apt_auth_dir ? "$in{'serial'}:$in{'key'}\@" : "";
	$lref = &read_file_lines($virtualmin_apt_repo);
	foreach $l (@$lref) {
		# New Virtualmin 7 repos
		if ($l =~ /^deb(.*?)(http|https):\/\/$upgrade_virtualmin_host\/(vm\/(?|([7-9])|([0-9]{2,4}))\/(gpl)(\/.*))/) {
			my $gpgkey = $1;
			my $rrepo = $3;
			$rrepo =~ s/(gpl)/pro/;
			$l = "deb${gpgkey}https://$apt_old_auth$upgrade_virtualmin_host/$rrepo";
		}
		elsif ($l =~ /^deb(.*?)(http|https):\/\/$upgrade_virtualmin_host\/gpl\/(.*)/) {
			my $gpgkey = $1;
			my $rrepo = $3;
			$l = "deb${gpgkey}https://$apt_old_auth$upgrade_virtualmin_host/$rrepo";
			}
		elsif ($l =~ /^deb(.*?)(http|https):\/\/$upgrade_virtualmin_host\/vm\/(\d)\/gpl\/(.*)/) {
			my $gpgkey = $1;
			my $vmver = $3;
			my $rrepo = $4;
			$l = "deb${gpgkey}https://$apt_old_auth$upgrade_virtualmin_host/vm/$vmver/$rrepo";
			}
		}
	&flush_file_lines($virtualmin_apt_repo);

	# Add auth credentials for Pro repos in a separate dedicated file
	if (-d $virtualmin_apt_auth_dir) {
		&write_file_contents(
		    "$virtualmin_apt_auth_dir/virtualmin.conf",
		    "machine $upgrade_virtualmin_host login $in{'serial'} password $in{'key'}\n");
		}
	&$second_print($text{'setup_done'});

	# Clean package manager cache
	if (&foreign_available("package-updates")) {
		&foreign_require("package-updates");
		&$first_print($package_updates::text{'refresh_clearing'});
		&package_updates::flush_package_caches();
		&package_updates::clear_repository_cache();
		&$second_print($package_updates::text{'refresh_done'});
		}

	# Force refresh of packages
	&$first_print($text{'upgrade_update_pkgs'});
	my $upgrade_update_pkgs_output;
	&system_logged("apt-get -y install ca-certificates >/dev/null 2>&1");
	&open_execute_command(YUM, "apt-get update", 2);
	while(<YUM>) {
		$upgrade_update_pkgs_output .= &html_escape($_);
		}
	close(YUM);
	if ($?) {
		&$second_print($text{'setup_failed'});
		print "<pre>";
		print $upgrade_update_pkgs_output;
		print "</pre><br data-x-br>";
		}
	else {
		&$second_print($text{'setup_done'});
		}

	&$first_print($text{'upgrade_to_pro'});

	# Update all Virtualmin-related packages
	my @packages;
	&foreign_require("software");
	foreach $p (&software::update_system_available()) {
		if ($p->{'name'} eq 'webmin-virtual-server') {
			# For the Virtualmin package, select pro
			# version explicitly so that the GPL is
			# replaced.
			local ($ver) = grep { !/\.gpl/ }
				&apt_package_versions($p->{'name'});
                            push(@packages, $ver ? $p->{'name'}."=".$ver
					     : $p->{'name'});
			}
		}
	if (!@packages) {
		&$second_print($text{'setup_failed'});
		print &ui_alert_box($text{'upgrade_problems'}, 'danger');
		goto PAGEEND;
		} 

	# Add Virtualmin support module
	push(@packages, 'webmin-virtualmin-support');

	# Run the upgrade
	my $upgrade_to_pro_output;
	&clean_environment();
	open(YUM, "apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages -f install ".join(" ", @packages)." 2>&1 |");
	while(<YUM>) {
		$upgrade_to_pro_output .= &html_escape($_);
		}
	close(YUM);
	$errors++ if ($?);
	&reset_environment();
	if ($?) {
		&$second_print($text{'setup_failed'});
		print "<pre>";
		print $upgrade_to_pro_output;
		print "</pre>";
		}
	else {
		&$second_print($text{'setup_done'});
		&$second_print($text{'upgrade_success'});
		}
	}
else {
	# Assume wbm.gz install. Download all the Pro modules, and install them
	&$first_print($text{'upgrade_mods'});
	&$indent_print();
	&http_download($upgrade_virtualmin_host, $upgrade_virtualmin_port,
		       $upgrade_virtualmin_updates, \$uout, undef, undef, 1,
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
					$upgrade_virtualmin_updates, 1);
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
		"https://$upgrade_virtualmin_host:$upgrade_virtualmin_port$upgrade_virtualmin_updates",
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
	print "<br>" . &ui_alert_box($text{'upgrade_problems'}, 'danger');
	}
else {
	if (defined(&theme_post_save_domains)) {
		&theme_post_save_domains();
		}
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

