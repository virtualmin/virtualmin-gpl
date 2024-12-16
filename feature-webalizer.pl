
sub require_webalizer
{
return if ($require_webalizer++);
&foreign_require("webalizer");
%wconfig = &foreign_config("webalizer");
}

sub check_depends_webalizer
{
my ($d) = @_;
if (!&domain_has_website($d)) {
	return $text{'setup_edepwebalizer'};
	}
return undef;
}

# Make sure Webalizer is installed, and that global directives are OK
sub feature_depends_webalizer
{
my $clink = "edit_newfeatures.cgi";
my $tmpl = &get_template(0);
&domain_has_website() || return &text('check_edepwebalizer', $clink);
&foreign_installed("webalizer", 1) == 2 ||
	return &text('index_ewebalizer', "/webalizer/", $clink);
&foreign_require("webalizer");

# Make sure template config file exists
my $wfile = ($tmpl->{'webalizer'} eq "none" ? "" : $tmpl->{'webalizer'}) ||
	    $webalizer::config{'webalizer_conf'};
if (!-r $wfile) {
	return &text('index_ewebalizerfile', $wfile, "/webalizer/");
	}
return undef;
}

# setup_webalizer(&domain)
# Setup the Webalizer module for this domain, and create a Cron job to run it
sub setup_webalizer
{
my ($d) = @_;
&$first_print($text{'setup_webalizer'});
&require_webalizer();

# Create the stats directory now, as the lock function needs it
my $tmpl = &get_template($d->{'template'});
my $stats = &webalizer_stats_dir($d);
if (!-d $stats) {
	&make_dir_as_domain_user($d, $stats, 0755);
	}

&obtain_lock_webalizer($d);
&obtain_lock_cron($d);
my $alog = &get_website_log($d);
if (!$alog) {
	&release_lock_webalizer($d);
	&$second_print($text{'setup_nolog'});
	return;
	}

my $htaccess_file = "$stats/.htaccess";
my $passwd_file = "$d->{'home'}/.stats-htpasswd";
if ($tmpl->{'web_stats_pass'} && !-r $htaccess_file) {
	# Setup .htaccess file for directory
	&create_webalizer_htaccess($d, $htaccess_file, $passwd_file);

	# Add to list of protected dirs
	&foreign_require("htaccess-htpasswd");
	&lock_file($htaccess_htpasswd::directories_file);
	my @dirs = &htaccess_htpasswd::list_directories();
	push(@dirs, [ $stats, $passwd_file, 0, 0, undef ]);
	&htaccess_htpasswd::save_directories(\@dirs);
	&unlock_file($htaccess_htpasswd::directories_file);
	}
if ($tmpl->{'web_stats_pass'}) {
	&update_create_htpasswd($d, $passwd_file, $d->{'user'});
	$d->{'stats_pass'} = $passwd_file;
	}
else {
	delete($d->{'stats_pass'});
	}

# Set up config for log in Webalizer module
my $lcn = &webalizer::log_config_name($alog);
my $cfile = &webalizer::config_file_name($alog);
if (!-r $lcn || !-r $cfile) {
	$lconf = { 'dir' => $stats,
		   'sched' => 1,
		   'type' => 0,
		   'over' => 0,
		   'clear' => 0,
		   'user' => $d->{'user'},
		   'mins' => int(rand()*60),
		   'hours' => int(rand()*6),
		   'days' => '*',
		   'months' => '*',
		   'weekdays' => '*' };
	&webalizer::save_log_config($alog, $lconf);

	# Create a custom webalizer.conf for the site
	if ($tmpl->{'webalizer'} && -r $tmpl->{'webalizer'}) {
		# Read the specified file and do substitution
		my $wt = `cat $tmpl->{'webalizer'}`;
		my %subs = %{$d};
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
		my $wconf = &webalizer::get_config($alog);
		&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
		&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
		&webalizer::save_directive($wconf, "Incremental", "yes");
		&webalizer::save_directive($wconf, "LogFile", $alog);
		&webalizer::save_directive($wconf, "HostName", $d->{'dom'});
		&webalizer::save_directive($wconf, "HideReferrer", "*.$d->{'dom'}");
		&flush_file_lines($cfile);
		}
	my $group = $d->{'group'} || $d->{'ugroup'};
	&set_ownership_permissions($d->{'user'}, $group, undef, $cfile);
	}
else {
	# Already exists .. but update
	$lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} = $stats;
	&webalizer::save_log_config($alog, $lconf);
	my $wconf = &webalizer::get_config($alog);
	&webalizer::save_directive($wconf, "HistoryName", "$stats/webalizer.hist");
	&webalizer::save_directive($wconf, "IncrementalName", "$stats/webalizer.current");
	&flush_file_lines($cfile);
	}

# If webserver for domain isn't apache, add log to Webalizer module's log list
my $p = &domain_has_website($d);
if ($p ne 'web') {
	my @custom = &webalizer::read_custom_logs();
	push(@custom, { 'file' => $alog,
			'type' => 'combined' });
	&webalizer::write_custom_logs(@custom);
	}

my $job = &find_module_cron_job("$webalizer::cron_cmd $alog");
if (!$job) {
	# Create a Cron job to process the log
	&setup_webalizer_cron($lconf, $alog);
	}

&release_lock_webalizer($d);
&release_lock_cron($d);
&$second_print($text{'setup_done'});
return 1;
}

# setup_webalizer_cron(&lconf, access-log)
sub setup_webalizer_cron
{
my ($lconf, $alog) = @_;
&foreign_require("cron");
my $job = { 'user' => 'root',
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
# Update log file paths
sub modify_webalizer
{
my ($d, $oldd) = @_;

&require_webalizer();
&obtain_lock_webalizer($d);
&obtain_lock_cron($d);

# Work out the old and new Webalizer log files
my $alog = &get_website_log($d);
my $oldalog = &get_old_website_log($alog, $d, $oldd);

if ($alog ne $oldalog) {
	# Log file has been renamed - fix up Webmin Webalizer config files
	&$first_print($text{'save_webalizerlog'});
	my $oldcfile = &webalizer::config_file_name($oldalog);
	my $cfile = &webalizer::config_file_name($alog);
	if ($oldcfile ne $cfile) {
		&rename_logged($oldcfile, $cfile);
		}
	my $oldlcn = &webalizer::log_config_name($oldalog);
	my $lcn = &webalizer::log_config_name($alog);
	if ($oldlcn ne $lcn) {
		&rename_logged($oldlcn, $lcn);
		}

	# Change log file path in .conf file
	my $conf = &webalizer::get_config($alog);
	my $changed;
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
	my ($job) = grep
		{ $_->{'command'} eq "$webalizer::cron_cmd $oldalog" }
		&cron::list_cron_jobs();
	if ($job) {
		$job->{'command'} = "$webalizer::cron_cmd $alog";
		&cron::change_cron_job($job);
		}

	# Rename in custom logs list
	my @custom = &webalizer::read_custom_logs();
	foreach my $c (@custom) {
		if ($c->{'file'} eq $oldalog) {
			$c->{'file'} = $alog;
			}
		}
	&webalizer::write_custom_logs(@custom);

	&$second_print($text{'setup_done'});
	}

if ($d->{'home'} ne $oldd->{'home'}) {
	# Change home directory is Webalizer config files
	&$first_print($text{'save_webalizerhome'});

	# Change home in .conf file
	my $conf = &webalizer::get_config($alog);
	my $changed;
	foreach my $c (@$conf) {
		if ($c->{'value'} =~ /\Q$oldd->{'home'}\E/) {
			$c->{'value'} =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			&webalizer::save_directive($conf, $c->{'name'},
						   $c->{'value'});
			$changed = $c->{'file'};
			}
		}
	&flush_file_lines($changed) if ($changed);

	# Change home in .log file
	my $lconf = &webalizer::get_log_config($alog);
	$lconf->{'dir'} =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
	&webalizer::save_log_config($alog, $lconf);

	# Change password file path in stats/.htpassswd file
	my $htaccess_file = &webalizer_stats_dir($d)."/.htaccess";
	if (!-r $htaccess_file) {
		# Try old location, as home may not have moved yet
		$htaccess_file = &webalizer_stats_dir($oldd)."/.htaccess";
		}
	if (-r $htaccess_file) {
		my $lref = &read_file_lines($htaccess_file);
		foreach my $l (@$lref) {
			$l =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			}
		&flush_file_lines($htaccess_file);
		}

	&$second_print($text{'setup_done'});
	}

if ($d->{'dom'} ne $oldd->{'dom'}) {
	# Update domain name in Webalizer configuration
	&$first_print($text{'save_webalizer'});
	my $conf = &webalizer::get_config($alog);
	&webalizer::save_directive($conf, "HostName", $d->{'dom'});
	&webalizer::save_directive($conf, "HideReferrer", "*.$d->{'dom'}");
	&flush_file_lines();
	&$second_print($text{'setup_done'});
	}

if ($d->{'user'} ne $oldd->{'user'}) {
	# Update Unix user Webliazer is run as
	&$first_print($text{'save_webalizeruser'});
	my $lcn = &webalizer::log_config_name($alog);
	my $lconf = &webalizer::get_log_config($alog);
	$lconf->{'user'} = $d->{'user'};
	&webalizer::save_log_config($alog, $lconf);
	&$second_print($text{'setup_done'});
	}

if ($d->{'stats_pass'}) {
	# Update password for stats dir
	&update_create_htpasswd($d, $d->{'stats_pass'}, $oldd->{'user'});
	}
&release_lock_webalizer($d);
&release_lock_cron($d);
}

# delete_webalizer(&domain)
# Delete the Webalizer config files and Cron job
sub delete_webalizer
{
my ($d) = @_;
&$first_print($text{'delete_webalizer'});
&obtain_lock_webalizer($d);
&obtain_lock_cron($d);
&require_webalizer();
my $stats = &webalizer_stats_dir($d);
my $alog = &get_website_log($d);
if (!$alog) {
	# Website may have been already deleted, so we don't know the log
	# file path! Try the template default.
	$alog = &get_apache_template_log($d);
	}
if (!$alog) {
	&$second_print($text{'delete_webalizerno'});
	return;
	}

if ($d->{'deleting'}) {
	# Delete config files
	my $lfile = &webalizer::log_config_name($alog);
	unlink($lfile);
	my $cfile = &webalizer::config_file_name($alog);
	unlink($cfile);
	}
 
# Turn off cron job for webalizer config
&foreign_require("cron");
my ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
		    &cron::list_cron_jobs();
if ($job) {
	&cron::delete_cron_job($job);
        }
&release_lock_webalizer($d);
&release_lock_cron($d);

# Remove from list of protected dirs
&foreign_require("htaccess-htpasswd");
&lock_file($htaccess_htpasswd::directories_file);
my @dirs = &htaccess_htpasswd::list_directories();
@dirs = grep { $_->[0] ne $stats } @dirs;
&htaccess_htpasswd::save_directories(\@dirs);
&unlock_file($htaccess_htpasswd::directories_file);

# Remove from custom logs list
my @custom = &webalizer::read_custom_logs();
@custom = grep { $_->{'file'} ne $alog } @custom;
&webalizer::write_custom_logs(@custom);

&$second_print($text{'setup_done'});
return 1;
}

# clone_webalizer(&domain, &old-domain)
# Copy Weblizer config files for some domain
sub clone_webalizer
{
my ($d, $oldd) = @_;
&$first_print($text{'clone_webalizer'});
my $alog = &get_website_log($d);
my $oalog = &get_website_log($oldd);
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
my $cfile = &webalizer::config_file_name($alog);
my $ocfile = &webalizer::config_file_name($oalog);
&copy_source_dest($ocfile, $cfile);
my $conf = &webalizer::get_config($alog);
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
my $stats = &webalizer_stats_dir($d);
my $htaccess_file = "$stats/.htaccess";
my $passwd_file = "$d->{'home'}/.stats-htpasswd";
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
my ($d) = @_;
&require_webalizer();
my $alog = &get_website_log($d);
return &text('validate_elogfile', "<tt>$d->{'dom'}</tt>") if (!$alog);
my $cfile = &webalizer::config_file_name($alog);
return &text('validate_ewebalizer', "<tt>$cfile</tt>") if (!-r $cfile);
if (!$config{'webalizer_nocron'}) {
	&foreign_require("cron");
	my ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
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
return 1;
}

sub disable_webalizer
{
# Does nothing yet
return 1;
}

# backup_webalizer(&domain, file)
# Saves the server's Webalizer config file, module config file and schedule
sub backup_webalizer
{
my ($d, $file) = @_;
&$first_print($text{'backup_webalizercp'});
&require_webalizer();
my $alog = &get_website_log($d);
if (!$alog) {
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	my $lcn = &webalizer::log_config_name($alog);
	&copy_write_as_domain_user($d, $lcn, $file);
	my $cfile = &webalizer::config_file_name($alog);
	&copy_write_as_domain_user($d, $cfile, $file."_conf");
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# restore_webalizer(&domain, file, &options, &all-options, home-format, &olddomain)
# Copies back the server's Webalizer config files, and re-sets up the Cron job
sub restore_webalizer
{
my ($d, $file, $opts, $allopts, $homefmt, $oldd) = @_;
&$first_print($text{'restore_webalizercp'});
&require_webalizer();
&obtain_lock_webalizer($d);
my $alog = &get_website_log($d);
if (!$alog) {
	&release_lock_webalizer($d);
	&$second_print($text{'setup_nolog'});
	return 0;
	}
else {
	# Copy the Webmin config for webalizer, and update the home directory
	my $lcn = &webalizer::log_config_name($alog);
	&copy_source_dest($file, $lcn);
	if ($oldd && $d->{'home'} ne $oldd->{'home'}) {
		my $lconf = &webalizer::get_log_config($alog);
		$lconf->{'dir'} =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
		&webalizer::save_log_config($alog, $lconf);
		}

	# Copy the actual Webalizer config file, and update home directory
	my $cfile = &webalizer::config_file_name($alog);
	&copy_source_dest($file."_conf", $cfile);
	if ($oldd && $d->{'home'} ne $oldd->{'home'}) {
		my $conf = &webalizer::get_config($alog);
		my $changed;
		foreach my $c (@$conf) {
			if ($c->{'value'} =~ /\Q$oldd->{'home'}\E/) {
				$c->{'value'} =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
				&webalizer::save_directive($conf, $c->{'name'},
							   $c->{'value'});
				$changed = $c->{'file'};
				}
			}
		&flush_file_lines($changed) if ($changed);
		}

	# Delete and re-create the cron job
	&obtain_lock_cron($d);
	&foreign_require("cron");
	my ($job) = grep { $_->{'command'} eq "$webalizer::cron_cmd $alog" }
			    &cron::list_cron_jobs();
	if ($job) {
		&cron::delete_cron_job($job);
		}
	my $lcn = &webalizer::log_config_name($alog);
	my $lconf;
	if (!-r $lcn) {
		$lconf = { 'dir' => $stats,
		   'sched' => 1,
		   'type' => 0,
		   'over' => 0,
		   'clear' => 0,
		   'user' => $d->{'user'},
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
	&release_lock_webalizer($d);
	&release_lock_cron($d);
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# update_create_htpasswd(&domain, file, old-user)
# Update or add the domain's user in a .htpasswd file
sub update_create_htpasswd
{
my ($d, $file, $olduser) = @_;
my ($pass, $encpass);
&foreign_require("htaccess-htpasswd");
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	$pass = $parent->{'pass'};
	$encpass = ($pass ? &htaccess_htpasswd::encrypt_password($pass)
			 : ($parent->{'enc_pass'} ||
			    $parent->{'md5_enc_pass'} ||
			    $parent->{'crypt_enc_pass'}));
	}
else {
	$pass = $d->{'pass'};
	$encpass = ($pass ? &htaccess_htpasswd::encrypt_password($pass)
			 : ($d->{'enc_pass'} ||
			    $d->{'md5_enc_pass'} ||
			    $d->{'crypt_enc_pass'}));
	}
my $users = &htaccess_htpasswd::list_users($file);
my ($user) = grep { $_->{'user'} eq $olduser } @$users;
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
my $vers = &webalizer::get_webalizer_version();
return ( [ $text{'sysinfo_webalizer'}, $vers ] );
}

sub links_webalizer
{
my ($d) = @_;
&require_webalizer();
my $log = &get_website_log($d);
my $cfg = &webalizer::config_file_name($log);
if (!-r $cfg) {
	$log = &resolve_links($log);
	}
my %waccess = &get_module_acl(undef, "webalizer");
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
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
my $hdir = &public_html_dir($d);
my $stats;
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
my ($d, $htaccess_file, $passwd_file) = @_;
&open_tempfile_as_domain_user($d, HTACCESS, ">$htaccess_file");
&print_tempfile(HTACCESS, "AuthName \"$d->{'dom'} statistics\"\n");
&print_tempfile(HTACCESS, "AuthType Basic\n");
&print_tempfile(HTACCESS, "AuthUserFile $passwd_file\n");
&print_tempfile(HTACCESS, "require valid-user\n");
&print_tempfile(HTACCESS, "<Files .stats-htpasswd>\n");
&require_apache();
if ($apache::httpd_modules{'core'} < 2.4) {
	&print_tempfile(HTACCESS, "Deny from all\n");
	}
else {
	&print_tempfile(HTACCESS, "Require all denied\n");
	}
&print_tempfile(HTACCESS, "</Files>\n");
&close_tempfile_as_domain_user($d, HTACCESS);
}

# obtain_lock_webalizer(&domain)
# Lock a domain's Webalizer config files, and password protection files
sub obtain_lock_webalizer
{
my ($d) = @_;
return if (!$config{'webalizer'});
&obtain_lock_anything($d);

if ($main::got_lock_webalizer_dom{$d->{'id'}} == 0) {
	&require_webalizer();
	my $alog = &get_website_log($d);
	my $stats = &webalizer_stats_dir($d);
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
my ($d) = @_;
return if (!$config{'webalizer'});

if ($main::got_lock_webalizer_dom{$d->{'id'}} == 1) {
	my $alog = $main::got_lock_webalizer_alog{$d->{'id'}};
	my $stats = $main::got_lock_webalizer_stats{$d->{'id'}};
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

