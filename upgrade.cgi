#!/usr/local/bin/perl
# Upgrade from Virtualmin GPL to Pro

require './virtual-server-lib.pl';
&foreign_require("webmin", "webmin-lib.pl");
&foreign_require("cron", "cron-lib.pl");
&can_edit_templates() || &error($text{'upgrade_ecannot'});
&error_setup($text{'upgrade_err'});
&ReadParse();

# Make sure the serial and key are valid, by trying a HTTP request
$in{'serial'} =~ /^\S+$/ || &error($text{'upgrade_eserial'});
$in{'key'} =~ /^\S+$/ || &error($text{'upgrade_ekey'});
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

&ui_print_unbuffered_header(undef, $text{'upgrade_title'}, "");

$SIG{'TERM'} = 'IGNORE';	# Stop process from being killed on upgrade

# Write out the licence file
&$first_print($text{'upgrade_file'});
&lock_file($virtualmin_license_file);
%lfile = ( 'SerialNumber' => $in{'serial'},
	   'LicenseKey' => $in{'key'} );
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
&$second_print($text{'setup_done'});

# Download all the Pro modules, and install them
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
	if (%info && ($info{'version'} > $ver ||
		      $info{'version'} == $ver && $info{'version'} !~ /gpl/)) {
		&$second_print(&text('upgrade_gotver', $info{'version'}));
		next;
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
	$progress_callback_url = ($mssl ? "https://" : "http://").$mhost.$mpage;
	&http_download($mhost, $mport, $mpage, $mtemp, \$merror,
		       \&progress_callback, $mssl, $in{'serial'}, $in{'key'});
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
@job = &cron::list_cron_jobs();
$upjob = &webmin::find_cron_job(\@jobs);
if ($upjob) {
	&$second_print($text{'upgrade_schedok'});
	}
else {
	&$second_print(&text('upgrade_schednot', "../webmin/edit_upgrade.cgi",
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

PAGEEND:
if ($errors) {
	print "<b>$text{'upgrade_problems'}</b><p>\n";
	}
else {
	print "<b>$text{'upgrade_complete'}</b><p>\n";
	}

&webmin_log("upgrade");
&ui_print_footer("", $text{'index_return'});

