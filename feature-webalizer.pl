
sub require_webalizer
{
return if ($require_webalizer++);
&foreign_require("webalizer");
%wconfig = &foreign_config("webalizer");
}

sub check_depends_webalizer
{
local ($d) = @_;
if (!&domain_has_website($d)) {
	return $text{'setup_edepwebalizer'};
	}
return undef;
}

# setup_webalizer(&domain)
# Setup the Webalizer module for this domain, and create a Cron job to run it
sub setup_webalizer
{
&$first_print($text{'setup_webalizer'});
&require_webalizer();

# Create the stats directory now, as the lock function needs it
local $tmpl = &get_template($_[0]->{'template'});
local $stats = &webalizer_stats_dir($_[0]);
if (!-d $stats) {
	&make_dir_as_domain_user($_[0], $stats, 0755);
	}

&obtain_lock_webalizer($_[0]);
&obtain_lock_cron($_[0]);
local $alog = &get_website_log($_[0]);
if (!$alog) {
	&release_lock_webalizer($_[0]);
	&$second_print($text{'setup_nolog'});
	return;
	}

local $htaccess_file = "$stats/.htaccess";
local $passwd_file = "$_[0]->{'home'}/.stats-htpasswd";
if ($tmpl->{'web_stats_pass'} && !-r $htaccess_file) {
	# Setup .htaccess file for directory
	&create_webalizer_htaccess($_[0], $htaccess_file, $passwd_file);

	# Add to list of protected dirs
	&foreign_require("htaccess-htpasswd");
	&lock_file($htaccess_htpasswd::directories_file);
	local @dirs = &htaccess_htpasswd::list_directories();
	push(@dirs, [ $stats, $passwd_file, 0, 0, undef ]);
	&htaccess_htpasswd::save_directories(\@dirs);
	&unlock_file($htaccess_htpasswd::directories_file);
	}
if ($tmpl->{'web_stats_pass'}) {
	&update_create_htpasswd($_[0], $passwd_file, $_[0]->{'user'});
	$_[0]->{'stats_pass'} = $passwd_file;
	}
else {
	delete($_[0]->{'stats_pass'});
	}

# Set up config for log in Webalizer module
local $lcn = &webalizer::log_config_name($alog);
local $cfile = &webalizer::config_file_name($alog);
if (!-r $lcn || !-r $cfile) {
	$lconf = { 'dir' => $stats,
		   'sched' => 1,
		   'type' => 0,
		   'over' => 0,
		   'clear' => 0,
		   'user' => $_[0]->{'user'},
		   'mins' => int(rand()*60),
		   'hours' => int(rand()*6),
		   'days' => '*',
		   'months' => '*',
		   'weekdays' => '*' };
	&webalizer::save_log_config($alog, $lconf);

	# Create a custom webalizer.conf for the site
	if ($tmpl->{'webalizer'} && -r $tmpl->{'webalizer'}) {
		# Read the specified file and do substitution
		local $wt = `cat $tmpl->{'webalizer'}`;
		local %subs = %{$_[0]};
		$subs{'stats'} = $stats;
		$subs{'log'} = $alog;
		$wt = &substitute_domain_template($wt, \%subs);
		&open_tempfile(FILE, ">$cfile");
		&print_tempfile(FILE, $wt);
		&close_tempfile(FILE);
		}
	else {
		# Copy webalizer.conf into place for site, and update
		&copy_source_dest($wconfig{'webalizer_conf'}, $cfile);
		local $wconf = &webalizer::get_config($alog);
		&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
		&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
		&webalizer::save_directive($wconf, "Incremental", "yes");
		&webalizer::save_directive($wconf, "LogFile", $alog);
		&webalizer::save_directive($wconf, "HostName", $_[0]->{'dom'});
		&webalizer::save_directive($wconf, "HideReferrer", "*.$_[0]->{'dom'}");
		&flush_file_lines($cfile);
		}
	local $group = $_[0]->{'group'} || $_[0]->{'ugroup'};
	&set_ownership_permissions($_[0]->{'user'}, $group, undef, $cfile);
	}
else {
	# Already exists .. but update
	$lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} = $stats;
	&webalizer::save_log_config($alog, $lconf);
	local $wconf = &webalizer::get_config($alog);
	&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
	&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
	&flush_file_lines($cfile);
	}

# If webserver for domain isn't apache, add log to Webalizer module's log list
local $p = &domain_has_website($d);
if ($p ne 'web') {
	local @custom = &webalizer::read_custom_logs();
	push(@custom, { 'file' => $alog,
			'type' => 'combined' });
	&webalizer::write_custom_logs(@custom);
	}

local $job = &find_module_cron_job("$webalizer::cron_cmd $alog");
if (!$job) {
	# Create a Cron job to process the log
	&setup_webalizer_cron($lconf, $alog);
	}

&release_lock_webalizer($_[0]);
&release_lock_cron($_[0]);
&$second_print($text{'setup_done'});
return 1;
}

# setup_webalizer_cron(&lconf, access-log)
sub setup_webalizer_cron
{
local ($lconf, $alog) = @_;
&foreign_require("cron");
local $job = { 'user' => 'root',
	       'active' => 1,
	       'mins' => $lconf->{'mins'},
	       'hours' => $lconf->{'hours'},
	       'days' => $lconf->{'days'},
	       'months' => $lconf->{'months'},
	       'weekdays' => $lconf->{'weekdays'},
	       'special' => $lconf->{'special'},
	       'command' => "$webalizer::cron_cmd $alog" };
if (!-r $webalizer::cron_cmd) {
	&cron::create_wrapper($webalizer::cron_cmd,
			      "webalizer", "webalizer.pl");
	}
if (!$config{'webalizer_nocron'}) {
	&cron::create_cron_job($job);
	}
}

# modify_webalizer(&domain, &olddomain)
sub modify_webalizer
{
&require_webalizer();
&obtain_lock_webalizer($_[0]);
&obtain_lock_cron($_[0]);

# Work out the old and new Webalizer log files
local $alog = &get_website_log($_[0]);
local $oldalog = &get_old_website_log($alog, $_[0], $_[1]);

if ($alog ne $oldalog) {
	# Log file has been renamed - fix up Webmin Webalizer config files
	&$first_print($text{'save_webalizerlog'});
	local $oldcfile = &webalizer::config_file_name($oldalog);
	local $cfile = &webalizer::config_file_name($alog);
	if ($oldcfile ne $cfile) {
		&rename_logged($oldcfile, $cfile);
		}
	local $oldlcn = &webalizer::log_config_name($oldalog);
	local $lcn = &webalizer::log_config_name($alog);
	if ($oldlcn ne $lcn) {
		&rename_logged($oldlcn, $lcn);
		}

	# Change log file path in .conf file
	local $conf = &webalizer::get_config($alog);
	local $changed;
	foreach my $c (@$conf) {
		if ($c->{'value'} =~ /\Q$oldalog\E/) {
			$c->{'value'} =~ s/\Q$oldalog\E/$alog/g;
			&webalizer::save_directive($conf, $c->{'name'},
						   $c->{'value'});
			$changed = $c->{'file'};
			}
		}
	&flush_file_lines($changed) if ($changed);

	# Change the log file path in the Cron job
	&foreign_require("cron");
	local ($job) = grep
		{ $_->{'command'} eq "$webalizer::cron_cmd $oldalog" }
		&cron::list_cron_jobs();
	if ($job) {
		$job->{'command'} = "$webalizer::cron_cmd $alog";
		&cron::change_cron_job($job);
		}

	# Rename in custom logs list
	local @custom = &webalizer::read_custom_logs();
	foreach my $c (@custom) {
		if ($c->{'file'} eq $oldalog) {
			$c->{'file'} = $alog;
			}
		}
	&webalizer::write_custom_logs(@custom);

	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Change home directory is Webalizer config files
	&$first_print($text{'save_webalizerhome'});

	# Change home in .conf file
	local $conf = &webalizer::get_config($alog);
	local $changed;
	foreach my $c (@$conf) {
		if ($c->{'value'} =~ /\Q$_[1]->{'home'}\E/) {
			$c->{'value'} =~ s/\Q$_[1]->{'home'}\E/$_[0]->{'home'}/g;
			&webalizer::save_directive($conf, $c->{'name'},
						   $c->{'value'});
			$changed = $c->{'file'};
			}
		}
	&flush_file_lines($changed) if ($changed);

	# Change home in .log file
	local $lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} =~ s/\Q$_[1]->{'home'}\E/$_[0]->{'home'}/g;
	&webalizer::save_log_config($alog, $lconf);

	# Change password file path in stats/.htpassswd file
	local $htaccess_file = &webalizer_stats_dir($_[0])."/.htaccess";
	if (!-r $htaccess_file) {
		# Try old location, as home may not have moved yet
		$htaccess_file = &webalizer_stats_dir($_[1])."/.htaccess";
		}
	if (-r $htaccess_file) {
		local $lref = &read_file_lines($htaccess_file);
		foreach my $l (@$lref) {
			$l =~ s/\Q$_[1]->{'home'}\E/$_[0]->{'home'}/g;
			}
		&flush_file_lines($htaccess_file);
		}

	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Update domain name in Webalizer configuration
	&$first_print($text{'save_webalizer'});
	local $conf = &webalizer::get_config($alog);
	&webalizer::save_directive($conf, "HostName", $_[0]->{'dom'});
	&webalizer::save_directive($conf, "HideReferrer", "*.$_[0]->{'dom'}");
	&flush_file_lines();
	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'user'} ne $_[1]->{'user'}) {
	# Update Unix user Webliazer is run as
	&$first_print($text{'save_webalizeruser'});
	local $lcn = &webalizer::log_config_name($alog);
	local $lconf = &webalizer::get_log_config($alog);
	$lconf->{'user'} = $_[0]->{'user'};
	&webalizer::save_log_config($alog, $lconf);
	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'stats_pass'}) {
	# Update password for stats dir
	&update_create_htpasswd($_[0], $_[0]->{'stats_pass'}, $_[1]->{'user'});
	}
&release_lock_webalizer($_[0]);
&release_lock_cron($_[0]);
}

# delete_webalizer(&domain)
# Delete the Webalizer config files and Cron job
sub delete_webalizer
{
&$first_print($text{'delete_webalizer'});
&obtain_lock_webalizer($_[0]);
&obtain_lock_cron($_[0]);
&require_webalizer();
local $stats = &webalizer_stats_dir($_[0]);
local $alog = &get_website_log($_[0]);
if (!$alog && -r "$_[0]->{'home'}/logs/access_log") {
	# Website may have been already deleted, so we don't know the log
	# file path! Try the template default.
	$alog = &get_apache_template_log($_[0]);
	}
if (!$alog) {
	&$second_print($text{'delete_webalizerno'});
	return;
	}

if ($_[0]->{'deleting'}) {
	# Delete config files
	local $lfile = &webalizer::log_config_name($alog);
	unlink($lfile);
	local $cfile = &webalizer::config_file_name($alog);
	unlink($cfile);
	}
 
# Turn off cron job for webalizer config
&foreign_require("cron");
local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
		    &cron::list_cron_jobs();
if ($job) {
	&cron::delete_cron_job($job);
        }
&release_lock_webalizer($_[0]);
&release_lock_cron($_[0]);

# Remove from list of protected dirs
&foreign_require("htaccess-htpasswd");
&lock_file($htaccess_htpasswd::directories_file);
local @dirs = &htaccess_htpasswd::list_directories();
@dirs = grep { $_->[0] ne $stats } @dirs;
&htaccess_htpasswd::save_directories(\@dirs);
&unlock_file($htaccess_htpasswd::directories_file);

# Remove from custom logs list
local @custom = &webalizer::read_custom_logs();
@custom = grep { $_->{'file'} ne $alog } @custom;
&webalizer::write_custom_logs(@custom);

&$second_print($text{'setup_done'});
return 1;
}

# clone_webalizer(&domain, &old-domain)
# Copy Weblizer config files for some domain
sub clone_webalizer
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_webalizer'});
local $alog = &get_website_log($d);
local $oalog = &get_website_log($oldd);
if (!$alog) {
	&$second_print($text{'clone_webalizernewlog'});
	return 0;
	}
if (!$oalog) {
	&$second_print($text{'clone_webalizeroldlog'});
	return 0;
	}
&obtain_lock_webalizer($d);

# Copy .conf file, change log file path, home directory and domain name
local $cfile = &webalizer::config_file_name($alog);
local $ocfile = &webalizer::config_file_name($oalog);
&copy_source_dest($ocfile, $cfile);
local $conf = &webalizer::get_config($alog);
foreach my $c (@$conf) {
	if ($c->{'value'} =~ /\Q$oalog\E/) {
		$c->{'value'} =~ s/\Q$oalog\E/$alog/g;
		&webalizer::save_directive($conf, $c->{'name'},
					   $c->{'value'});
		}
	if ($c->{'value'} =~ /\Q$oldd->{'home'}\E/) {
		$c->{'value'} =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
		&webalizer::save_directive($conf, $c->{'name'},
					   $c->{'value'});
		}
	}
&webalizer::save_directive($conf, "HostName", $d->{'dom'});
&webalizer::save_directive($conf, "HideReferrer", "*.$d->{'dom'}");
&flush_file_lines($cfile);

# Re-generate password file
local $stats = &webalizer_stats_dir($d);
local $htaccess_file = "$stats/.htaccess";
local $passwd_file = "$d->{'home'}/.stats-htpasswd";
if (-r $htaccess_file) {
	&create_webalizer_htaccess($d, $htaccess_file, $passwd_file);
	&update_create_htpasswd($d, $passwd_file, $oldd->{'user'});
	}

&release_lock_webalizer($d);
&$second_print($text{'setup_done'});
return 1;
}

# validate_webalizer(&domain)
# Returns an error message if Webalizer is not configured properly
sub validate_webalizer
{
local ($d) = @_;
&require_webalizer();
local $alog = &get_website_log($d);
return &text('validate_elogfile', "<tt>$d->{'dom'}</tt>") if (!$alog);
local $cfile = &webalizer::config_file_name($alog);
return &text('validate_ewebalizer', "<tt>$cfile</tt>") if (!-r $cfile);
if (!$config{'webalizer_nocron'}) {
	&foreign_require("cron");
	local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
			    &cron::list_cron_jobs();
	return &text('validate_ewebalizercron') if (!$job);
	}
return undef;
}

# check_webalizer_clash()
# Does nothing, because the web clash check is all that is needed
sub check_webalizer_clash
{
return 0;
}

sub enable_webalizer
{
# Does nothing yet
}

sub disable_webalizer
{
# Does nothing yet
}

# backup_webalizer(&domain, file)
# Saves the server's Webalizer config file, module config file and schedule
sub backup_webalizer
{
local ($d, $file) = @_;
&$first_print($text{'backup_webalizercp'});
&require_webalizer();
local $alog = &get_website_log($d);
if (!$alog) {
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	local $lcn = &webalizer::log_config_name($alog);
	&copy_write_as_domain_user($d, $lcn, $file);
	local $cfile = &webalizer::config_file_name($alog);
	&copy_write_as_domain_user($d, $cfile, $file."_conf");
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# restore_webalizer(&domain, file, &options, &all-options, home-format, &olddomain)
# Copies back the server's Webalizer config files, and re-sets up the Cron job
sub restore_webalizer
{
&$first_print($text{'restore_webalizercp'});
&require_webalizer();
&obtain_lock_webalizer($_[0]);
local $alog = &get_website_log($_[0]);
if (!$alog) {
	&release_lock_webalizer($_[0]);
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	# Copy the Webmin config for webalizer, and update the home directory
	local $lcn = &webalizer::log_config_name($alog);
	&copy_source_dest($_[1], $lcn);
	if ($_[5] && $_[0]->{'home'} ne $_[5]->{'home'}) {
		local $lconf = &webalizer::get_log_config($alog);
		$lconf->{'dir'} =~ s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
		&webalizer::save_log_config($alog, $lconf);
		}

	# Copy the actual Webalizer config file, and update home directory
	local $cfile = &webalizer::config_file_name($alog);
	&copy_source_dest($_[1]."_conf", $cfile);
	if ($_[5] && $_[0]->{'home'} ne $_[5]->{'home'}) {
		local $conf = &webalizer::get_config($alog);
		local $changed;
		foreach my $c (@$conf) {
			if ($c->{'value'} =~ /\Q$_[5]->{'home'}\E/) {
				$c->{'value'} =~ s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
				&webalizer::save_directive($conf, $c->{'name'},
							   $c->{'value'});
				$changed = $c->{'file'};
				}
			}
		&flush_file_lines($changed) if ($changed);
		}

	# Delete and re-create the cron job
	&obtain_lock_cron($_[0]);
	&foreign_require("cron");
	local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
			    &cron::list_cron_jobs();
	if ($job) {
		&cron::delete_cron_job($job);
		}
	local $lcn = &webalizer::log_config_name($alog);
	local $lconf;
	if (!-r $lcn) {
		$lconf = { 'dir' => $stats,
		   'sched' => 1,
		   'type' => 0,
		   'over' => 0,
		   'clear' => 0,
		   'user' => $_[0]->{'user'},
		   'mins' => int(rand()*60),
		   'hours' => 0,
		   'days' => '*',
		   'months' => '*',
		   'weekdays' => '*' };
		&webalizer::save_log_config($alog, $lconf);
		}
	else {
		$lconf = &webalizer::get_log_config($alog);
		}
	&setup_webalizer_cron($lconf, $alog);
	&release_lock_webalizer($_[0]);
	&release_lock_cron($_[0]);
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# update_create_htpasswd(&domain, file, old-user)
# Update or add the domain's user in a .htpasswd file
sub update_create_htpasswd
{
my ($d, $file, $olduser) = @_;
local ($pass, $encpass);
&foreign_require("htaccess-htpasswd");
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	$pass = $parent->{'pass'};
	$encpass = $pass ? &htaccess_htpasswd::encrypt_password($pass)
			 : $parent->{'crypt_enc_pass'};
	}
else {
	$pass = $d->{'pass'};
	$encpass = $pass ? &htaccess_htpasswd::encrypt_password($pass)
			 : $d->{'crypt_enc_pass'};
	}
local $users = &htaccess_htpasswd::list_users($file);
local ($user) = grep { $_->{'user'} eq $olduser } @$users;
if ($user) {
	$user->{'user'} = $d->{'user'};
	$user->{'pass'} = $encpass;
	&write_as_domain_user($d,
		sub { &htaccess_htpasswd::modify_user($user) });
	}
else {
	$user = { 'enabled' => 1,
		  'user' => $d->{'user'},
		  'pass' => $encpass };
	&write_as_domain_user($d,
		sub { &htaccess_htpasswd::create_user($user, $file); });
	}
}

# sysinfo_webalizer()
# Returns the Webalizer
sub sysinfo_webalizer
{
&require_webalizer();
local $vers = &webalizer::get_webalizer_version();
return ( [ $text{'sysinfo_webalizer'}, $vers ] );
}

sub links_webalizer
{
local ($d) = @_;
&require_webalizer();
local $log = &get_website_log($d);
local $cfg = &webalizer::config_file_name($log);
if (!-r $cfg) {
	$log = &resolve_links($log);
	}
local %waccess = &get_module_acl(undef, "webalizer");
if ($waccess{'view'}) {
	# Can view report only
	return ( { 'mod' => 'webalizer',
		   'desc' => $text{'links_webalizer2'},
		   'page' => 'view_log.cgi/'.&urlize(&urlize($log)).
					     '/index.html',
		   'cat' => 'logs',
		  });
	}
else {
	# Can edit report
	return ( { 'mod' => 'webalizer',
		   'desc' => $text{'links_webalizer'},
		   'page' => 'edit_log.cgi?file='.
			&urlize($log).'&type=1',
		   'cat' => 'logs',
		 });
	}
return ( );
}

# webalizer_stats_dir(&domain)
# Returns the full directory for Webalizer stats files
sub webalizer_stats_dir
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $hdir = &public_html_dir($d);
local $stats;
if ($tmpl->{'web_stats_hdir'}) {
	$stats = "$d->{'home'}/$tmpl->{'web_stats_hdir'}";
	}
elsif ($tmpl->{'web_stats_dir'}) {
	$stats = "$hdir/$tmpl->{'web_stats_dir'}";
	}
else {
	$stats = "$hdir/stats";
	}
return $stats;
}

# create_webalizer_htaccess(&domain, htaccess-file, htpasswd-file)
# Create a new .htaccess file for a domain
sub create_webalizer_htaccess
{
local ($d, $htaccess_file, $passwd_file) = @_;
&open_tempfile_as_domain_user($d, HTACCESS, ">$htaccess_file");
&print_tempfile(HTACCESS, "AuthName \"$d->{'dom'} statistics\"\n");
&print_tempfile(HTACCESS, "AuthType Basic\n");
&print_tempfile(HTACCESS, "AuthUserFile $passwd_file\n");
&print_tempfile(HTACCESS, "require valid-user\n");
&print_tempfile(HTACCESS, "<Files .stats-htpasswd>\n");
&print_tempfile(HTACCESS, "deny from all\n");
&print_tempfile(HTACCESS, "</Files>\n");
&close_tempfile_as_domain_user($d, HTACCESS);
}

# obtain_lock_webalizer(&domain)
# Lock a domain's Webalizer config files, and password protection files
sub obtain_lock_webalizer
{
local ($d) = @_;
return if (!$config{'webalizer'});
&obtain_lock_anything($d);

if ($main::got_lock_webalizer_dom{$d->{'id'}} == 0) {
	&require_webalizer();
	local $alog = &get_website_log($d);
	local $stats = &webalizer_stats_dir($d);
	if ($alog) {
		&lock_file(&webalizer::log_config_name($alog));
		&lock_file(&webalizer::config_file_name($alog));
		&lock_file("$stats/.htaccess");
		&lock_file("$d->{'home'}/.stats-htpasswd");
		}
	$main::got_lock_webalizer_stats{$d->{'id'}} = $stats;
	$main::got_lock_webalizer_alog{$d->{'id'}} = $alog;
	}
$main::got_lock_webalizer_dom{$d->{'id'}}++;
}

# release_lock_webalizer(&domain)
# Unlock a domain's Webalizer config files
sub release_lock_webalizer
{
local ($d) = @_;
return if (!$config{'webalizer'});

if ($main::got_lock_webalizer_dom{$d->{'id'}} == 1) {
	local $alog = $main::got_lock_webalizer_alog{$d->{'id'}};
	local $stats = $main::got_lock_webalizer_alog{$d->{'id'}};
	if ($alog) {
		&unlock_file(&webalizer::log_config_name($alog));
		&unlock_file(&webalizer::config_file_name($alog));
		&unlock_file("$stats/.htaccess");
		&unlock_file("$d->{'home'}/.stats-htpasswd");
		}
	}
$main::got_lock_webalizer_dom{$d->{'id'}}--
	if ($main::got_lock_webalizer_dom{$d->{'id'}});
&release_lock_anything($d);
}

$done_feature_script{'webalizer'} = 1;

1;

