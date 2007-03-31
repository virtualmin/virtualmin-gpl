
$feature_depends{'webalizer'} = [ 'web' ];

sub require_webalizer
{
return if ($require_webalizer++);
&foreign_require("webalizer", "webalizer-lib.pl");
%wconfig = &foreign_config("webalizer");
}

# setup_webalizer(&domain)
# Setup the Webalizer module for this domain, and create a Cron job to run it
sub setup_webalizer
{
&$first_print($text{'setup_webalizer'});
&require_webalizer();

local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
if (!$alog) {
	&$second_print($text{'setup_nolog'});
	return;
	}

# Create directory for stats
local $tmpl = &get_template($_[0]->{'template'});
local $hdir = &public_html_dir($_[0]);
local $stats;
if ($tmpl->{'web_stats_hdir'}) {
	$stats = "$_[0]->{'home'}/$tmpl->{'web_stats_hdir'}";
	}
elsif ($tmpl->{'web_stats_dir'}) {
	$stats = "$hdir/$tmpl->{'web_stats_dir'}";
	}
else {
	$stats = "$hdir/stats";
	}
if (!-d $stats) {
	&system_logged("mkdir '$stats' 2>/dev/null");
	&system_logged("chmod 755 '$stats'");
	&system_logged("chown $_[0]->{'uid'}:$_[0]->{'ugid'} '$stats'");
	}

local $htaccess_file = "$stats/.htaccess";
local $passwd_file = "$_[0]->{'home'}/.stats-htpasswd";
if ($tmpl->{'web_stats_pass'} && !-r $htaccess_file) {
	# Setup .htaccess file for directory
	&open_tempfile(HTACCESS, ">$htaccess_file");
	&print_tempfile(HTACCESS, "AuthName \"$_[0]->{'dom'} statistics\"\n");
	&print_tempfile(HTACCESS, "AuthType Basic\n");
	&print_tempfile(HTACCESS, "AuthUserFile $passwd_file\n");
	&print_tempfile(HTACCESS, "require valid-user\n");
	&print_tempfile(HTACCESS, "<Files .htpasswd>\n");
	&print_tempfile(HTACCESS, "deny from all\n");
	&print_tempfile(HTACCESS, "</Files>\n");
	&close_tempfile(HTACCESS);
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'},
				   undef, $htaccess_file);
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
&lock_file($lcn);
local $cfile = &webalizer::config_file_name($alog);
&lock_file($cfile);
if (!-r $lcn) {
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
		&execute_command("cp $wconfig{'webalizer_conf'} $cfile");
		local $wconf = &webalizer::get_config($alog);
		&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
		&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
		&webalizer::save_directive($wconf, "Incremental", "yes");
		&webalizer::save_directive($wconf, "LogFile", $alog);
		&webalizer::save_directive($wconf, "HostName", $_[0]->{'dom'});
		&webalizer::save_directive($wconf, "HideReferrer", "*.$_[0]->{'dom'}");
		&flush_file_lines();
		}
	local $group = $_[0]->{'group'} || $_[0]->{'ugroup'};
	&system_logged("chown $_[0]->{'user'}:$group $cfile");
	}
else {
	# Already exists .. but update
	$lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} = $stats;
	&webalizer::save_log_config($alog, $lconf);
	local $wconf = &webalizer::get_config($alog);
	&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
	&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
	&flush_file_lines();
	}
&unlock_file($lcn);
&unlock_file($cfile);

&foreign_require("cron", "cron-lib.pl");
local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
		    &cron::list_cron_jobs();
if (!$job) {
	# Create a Cron job to process the log
	&setup_webalizer_cron($lconf, $alog);
	}
&$second_print($text{'setup_done'});
}

# setup_webalizer_cron(&lconf, access-log)
sub setup_webalizer_cron
{
local ($lconf, $alog) = @_;
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
	&lock_file($webalizer::cron_cmd);
	&cron::create_wrapper($webalizer::cron_cmd,
			      "webalizer", "webalizer.pl");
	&unlock_file($webalizer::cron_cmd);
	}
if (!$config{'webalizer_nocron'}) {
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}
}

# modify_webalizer(&domain, &olddomain)
sub modify_webalizer
{
&require_webalizer();
local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Update Webalizer configuration to use new log file
	&$first_print($text{'save_webalizerlog'});

	# Rename the .conf file, which is in Webalizer config format. Also
	# update any directives that use the old path.
	local $oldalog = $alog;
	$oldalog =~ s/$_[0]->{'home'}/$_[1]->{'home'}/;	# because it will
							# have been renamed
	local $oldcfile = &webalizer::config_file_name($oldalog);
	local $cfile = &webalizer::config_file_name($alog);
	&rename_logged($oldcfile, $cfile);
	&lock_file($cfile);
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
	&unlock_file($cfile);

	# Rename the .log file, which is in Webmin format. Also update the
	# dir= line in that file
	local $oldlcn = &webalizer::log_config_name($oldalog);
	local $lcn = &webalizer::log_config_name($alog);
	&rename_logged($oldlcn, $lcn);
	&lock_file($lcn);
	local $lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} =~ s/\Q$_[1]->{'home'}\E/$_[0]->{'home'}/g;
	&webalizer::save_log_config($alog, $lconf);
	&unlock_file($lcn);

	# Change the log file path in the Cron job
	&foreign_require("cron", "cron-lib.pl");
	local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $oldalog" }
			    &cron::list_cron_jobs();
	if ($job) {
		$job->{'command'} = "$webalizer::cron_cmd $alog";
		&lock_file(&cron::cron_file($job));
		&cron::change_cron_job($job);
		&unlock_file(&cron::cron_file($job));
		}
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Update hostname in Webalizer configuration
	&$first_print($text{'save_webalizer'});
	local $cfile = &webalizer::config_file_name($alog);
	&lock_file($cfile);
	local $wconf = &webalizer::get_config($alog);
	&webalizer::save_directive($wconf, "HostName", $_[0]->{'dom'});
	&webalizer::save_directive($wconf, "HideReferrer", "*.$_[0]->{'dom'}");
	&flush_file_lines();
	&unlock_file($cfile);
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'user'} ne $_[1]->{'user'}) {
	# Update Unix user Webliazer is run as
	&$first_print($text{'save_webalizeruser'});
	local $lcn = &webalizer::log_config_name($alog);
	&lock_file($lcn);
	local $lconf = &webalizer::get_log_config($alog);
	$lconf->{'user'} = $_[0]->{'user'};
	&webalizer::save_log_config($alog, $lconf);
	&unlock_file($lcn);
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'stats_pass'}) {
	# Update password for stats dir
	&update_create_htpasswd($_[0], $_[0]->{'stats_pass'}, $_[1]->{'user'});
	}
}

# delete_webalizer(&domain)
# Delete the Webalizer config files and Cron job
sub delete_webalizer
{
&$first_print($text{'delete_webalizer'});
&require_webalizer();
local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
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
&foreign_require("cron", "cron-lib.pl");
local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
		    &cron::list_cron_jobs();
if ($job) {
	&lock_file(&cron::cron_file($job));
	&cron::delete_cron_job($job);
	&unlock_file(&cron::cron_file($job));
        }
&$second_print($text{'setup_done'});
}

# validate_webalizer(&domain)
# Returns an error message if Webalizer is not configured properly
sub validate_webalizer
{
local ($d) = @_;
&require_webalizer();
local $alog = &get_apache_log($d->{'dom'}, $d->{'web_port'});
return &text('validate_elogfile', "<tt>$d->{'dom'}</tt>") if (!$alog);
local $cfile = &webalizer::config_file_name($alog);
return &text('validate_ewebalizer', "<tt>$cfile</tt>") if (!-r $cfile);
if (!$config{'webalizer_nocron'}) {
	&foreign_require("cron", "cron-lib.pl");
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
&$first_print($text{'backup_webalizercp'});
&require_webalizer();
local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
if (!$alog) {
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	local $lcn = &webalizer::log_config_name($alog);
	&execute_command("cp ".quotemeta($lcn)." ".quotemeta($_[1]));

	local $cfile = &webalizer::config_file_name($alog);
	&execute_command("cp ".quotemeta($cfile)." ".quotemeta($_[1])."_conf");
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
local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
if (!$alog) {
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	# Copy the Webmin config for webalizer, and update the home directory
	local $lcn = &webalizer::log_config_name($alog);
	&lock_file($lcn);
	&copy_source_dest($_[1], $lcn);
	if ($_[5] && $_[0]->{'home'} ne $_[5]->{'home'}) {
		local $lconf = &webalizer::get_log_config($alog);
		$lconf->{'dir'} =~ s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
		&webalizer::save_log_config($alog, $lconf);
		}
	&unlock_file($lcn);

	# Copy the actual Webalizer config file, and update home directory
	local $cfile = &webalizer::config_file_name($alog);
	&lock_file($cfile);
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
	&unlock_file($cfile);

	# Delete and re-create the cron job
	&foreign_require("cron", "cron-lib.pl");
	local ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
			    &cron::list_cron_jobs();
	if ($job) {
		&lock_file(&cron::cron_file($job));
		&cron::delete_cron_job($job);
		}
	local $lcn = &webalizer::log_config_name($alog);
	local $lconf;
	if (!-r $lcn) {
		&lock_file($lcn);
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
		&unlock_file($lcn);
		}
	else {
		$lconf = &webalizer::get_log_config($alog);
		}
	&setup_webalizer_cron($lconf, $alog);
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# update_create_htpasswd(&domain, file, old-user)
sub update_create_htpasswd
{
local $pass;
if ($_[0]->{'parent'}) {
	$pass = &get_domain($_[0]->{'parent'})->{'pass'};
	}
else {
	$pass = $_[0]->{'pass'};
	}
&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
local $users = &htaccess_htpasswd::list_users($_[1]);
local ($user) = grep { $_->{'user'} eq $_[2] } @$users;
if ($user) {
	$user->{'user'} = $_[0]->{'user'};
	$user->{'pass'} = &htaccess_htpasswd::encrypt_password($pass);
	&htaccess_htpasswd::modify_user($user);
	}
else {
	$user = { 'enabled' => 1,
		  'user' => $_[0]->{'user'},
		  'pass' => &htaccess_htpasswd::encrypt_password($pass) };
	&htaccess_htpasswd::create_user($user, $_[1]);
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'}, undef,$_[1]);
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
if ($config{'avail_webalizer'}) {
	local $log = &resolve_links(&get_apache_log($d->{'dom'}, $d->{'web_port'}));
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
	}
return ( );
}

$done_feature_script{'webalizer'} = 1;

1;

