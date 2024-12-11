
$force_load_features = 1;	# so that the latest feature-* files are used
$done_virtual_server_lib_funcs = 0;
do 'virtual-server-lib.pl';

sub module_install
{
&foreign_require("cron");
local $need_restart;
&lock_file($module_config_file);

# Update last post-install time
$config{'lastpost'} = time();
&save_module_config();

# Convert all existing cron jobs to WebminCron, except existing backups
foreach my $script (@all_cron_commands) {
	if ($script ne $backup_cron_cmd) {
		&convert_cron_script($script);
		}
	}

# Convert all templates to plans, if needed
local @oldplans = &list_plans(1);
if (!@oldplans) {
	&convert_plans();
	}

# If this is a new install, set dns_ip to * by default to use the externally
# detected IP for DNS records, and cache it.
if (!$config{'first_version'} && !$config{'dns_ip'}) {
	$config{'dns_ip'} = '*';
	&save_module_config();
	}

# If this is a new install, use the new SSL cert paths
if (!$config{'first_version'}) {
	my @tmpls = &list_templates();
	my ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
	if (!$tmpl->{'cert_key_tmpl'}) {
		$tmpl->{'cert_key_tmpl'} = $ssl_certificate_dir."/ssl.key";
		$tmpl->{'cert_cert_tmpl'} = 'auto';
		$tmpl->{'cert_ca_tmpl'} = 'auto';
		$tmpl->{'cert_combined_tmpl'} = 'auto';
		$tmpl->{'cert_everything_tmpl'} = 'auto';
		&save_template($tmpl);
		}
	}

# If this is a new install, put Webalizer stats data files outside public_html
if (!$config{'first_version'} && !$config{'stats_dir'} &&
    !$config{'stats_hdir'}) {
	$config{'stats_hdir'} = 'stats';
	}

# Fix invalid sysinfo
if ($config{'show_sysinfo'} == 0 || $config{'show_sysinfo'} == 3) {
	$config{'show_sysinfo'} = 1;
	&save_module_config();
	}

# Remember the first version we installed, to avoid showing new features
# from before it
$config{'first_version'} ||= &get_base_module_version();

# Store the domain name of the default domain
if (!$config{'defaultdomain_name'}) {
	my $defd;
	foreach my $d (&list_domains()) {
		$defd = $d if ($d->{'defaultdomain'});
		}
	$config{'defaultdomain_name'} = $defd ? $defd->{'dom'} : 'none';
	&save_module_config();
	}

# Make sure the remote.cgi page is accessible in non-session mode
local %miniserv;
&get_miniserv_config(\%miniserv);
local @sa = split(/\s+/, $miniserv{'sessiononly'});
if (&indexof("/$module_name/remote.cgi", @sa) < 0) {
	# Need to add
	push(@sa, "/$module_name/remote.cgi");
	$miniserv{'sessiononly'} = join(" ", @sa);
	&put_miniserv_config(\%miniserv);
	}

# Setup the default templates
foreach my $tf (@all_template_files) {
	&ensure_template($tf);
	}

# Perform a module config check, to ensure that quota and interface settings
# are correct.
&set_all_null_print();
$cerr = &html_tags_to_text(&check_virtual_server_config());
#if ($cerr) {
#	print STDERR "Warning: Module Configuration problem detected: $cerr\n";
#	}

# Set resellers on sub-servers
if (defined(&sync_parent_resellers)) {
	&sync_parent_resellers();
	}

# Force update of all Webmin users, to set new ACL options
&modify_all_webmin();
if ($virtualmin_pro) {
	&modify_all_resellers();
	}

# Setup the licence cron job
&setup_licence_cron();

# Fix up Procmail default delivery
if ($config{'spam'}) {
	&setup_default_delivery();
	}

# Enable logging in Procmail, if we are using it
if ($config{'spam'}) {
	&enable_procmail_logging();

	# And setup cron job to periodically process mail logs
	# Disabled, as it is generating too much load on big sites
	#local $job = &find_module_cron_job($maillog_cron_cmd);
	#if (!$job) {
	#	# Create, and run for the first time
	#	$job = { 'mins' => int(rand()*60),
	#		 'hours' => '0',
	#		 'days' => '*',
	#		 'months' => '*',
	#		 'weekdays' => '*',
	#		 'user' => 'root',
	#		 'active' => 1,
	#		 'command' => $maillog_cron_cmd };
	#	&setup_cron_script($job);
	#	}
	}

# Setup Cron job to periodically re-sync links in domains' spamassassin config
# directories, and to clean up old /tmp/clamav-* files
if ($config{'spam'}) {
	&setup_spam_config_job();
	}

# Fix up old procmail scripts that don't call the clam wrapper
if ($config{'virus'}) {
	&copy_clam_wrapper();
	&fix_clam_wrapper();
	&create_clamdscan_remote_wrapper_cmd();
	}

# Save the current default IP address if we don't currently know it
$config{'old_defip'} ||= &get_default_ip();
$config{'old_defip6'} ||= &get_default_ip6();

# Decide whether to preload, and then do it
if ($gconfig{'no_virtualmin_preload'}) {
	$config{'preload_mode'} = 0;
	}
elsif ($config{'preload_mode'} eq '') {
	$config{'preload_mode'} = 2;
	}
&save_module_config();
&update_miniserv_preloads($config{'preload_mode'});
$need_restart = 1 if ($config{'preload_mode'});		# To apply .pl changes

# Restart Webmin if needed
local %miniserv;
&get_miniserv_config(\%miniserv);
if (&check_pid_file($miniserv{'pidfile'}) && $need_restart) {
	&restart_miniserv();
	}

# Setup lookup domain daemon
if ($config{'spam'} && !$config{'no_lookup_domain_daemon'}) {
	&setup_lookup_domain_daemon();
	}

# Add procmail rule to bounce messages if quota is full
if ($config{'spam'}) {
	&setup_quota_full_bounce();
	}

# Force a restart of Apache, to apply writelogs.pl changes
if ($config{'web'}) {
	&require_apache();
	&restart_apache();
	}

# Make sure autoreply.pl exists
&set_alias_programs();

if ($virtualmin_pro && !$config{'done_fix_autoreplies'}) {
	# Create links for existing autoreply aliases
	foreach my $d (&list_domains()) {
		if ($d->{'mail'}) {
			&create_autoreply_alias_links($d);
			}
		}
	$config{'done_fix_autoreplies'} = 1;
	&save_module_config();
	}

# If installing for the first time, enable backup of all features by default
local @doms = &list_domains();
if (!@doms && !defined($config{'backup_feature_all'})) {
	$config{'backup_feature_all'} = 1;
	&save_module_config();
	}

# Build quick domain-lookup maps
&build_domain_maps();

# If supported by OpenSSH, create a group of users to deny SSH for
if (&foreign_installed("sshd") && !$config{'nodeniedssh'}) {
	# Add to SSHd config
	&foreign_require("sshd");
	local $conf = &sshd::get_sshd_config();
	local @denyg = &sshd::find_value("DenyGroups", $conf);
	local $commas = $sshd::version{'type'} eq 'ssh' &&
			$sshd::version{'number'} >= 3.2;
	if ($commas) {
		@denyg = split(/,/, $denyg[0]);
		}
	if (&indexof($denied_ssh_group, @denyg) < 0) {
		push(@denyg, $denied_ssh_group);
		&sshd::save_directive("DenyGroups", $conf,
				       join($commas ? "," : " ", @denyg));
		&flush_file_lines($sshd::config{'sshd_config'});
		&sshd::restart_sshd();
		}

	# Create the actual group, if missing
	&require_useradmin();
	&obtain_lock_unix();
	local @allgroups = &list_all_groups();
	local ($group) = grep { $_->{'group'} eq $denied_ssh_group } @allgroups;
	if (!$group) {
		local (%gtaken, %ggtaken);
		&build_group_taken(\%gtaken, \%ggtaken, \@allgroups);
		$group = { 'group' => $denied_ssh_group,
			   'members' => '',
			   'gid' => &allocate_gid(\%gtaken) };
		&foreign_call($usermodule, "set_group_envs", $group,
							     'CREATE_GROUP');
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "create_group", $group);
		&foreign_call($usermodule, "made_changes");
		}
	&release_lock_unix();
	}
&build_denied_ssh_group();

# Delete the old cron job for sending in script ratings
&delete_cron_script($ratings_cron_cmd);

# Create the cron job for collecting system info
&setup_collectinfo_job();

# Decide if sub-domains should be allowed, by checking if any exist
if ($config{'allow_subdoms'} eq '') {
	local @subdoms = grep { $_->{'subdom'} } &list_domains();
	$config{'allow_subdoms'} = @subdoms ? 1 : 0;
	&save_module_config();
	}

# Remove old cron job for killing orphan php*-cgi processes
&delete_cron_script($fcgiclear_cron_cmd);

# Add ftp user to the groups for all domains that have FTP enabled
&obtain_lock_unix();
foreach my $d (&list_domains()) {
	if ($d->{'ftp'}) {
		local $ftp_user = &get_proftpd_user($d);
		if ($ftp_user) {
			&add_user_to_domain_group($d, $ftp_user, undef);
			}
		}
	}
&release_lock_unix();

# If the default template uses a PHP or CGI mode that isn't supported, change it
my $mmap = &php_mode_numbers_map();
my @supp = &supported_php_modes();
my @cgimodes = &has_cgi_support();
foreach my $tmpl (grep { $_->{'standard'} } &list_templates()) {
	my %cannums = map { $mmap->{$_}, 1 } @supp;
	if ($tmpl->{'web_php_suexec'} ne '' &&
	    !$cannums{int($tmpl->{'web_php_suexec'})} && @supp) {
		# Default PHP mode cannot be used .. change to first that can
		my @goodsupp = grep { $_ ne 'none' } @supp;
		@goodsupp = @supp if (!@goodsupp);
		$tmpl->{'web_php_suexec'} = $mmap->{$goodsupp[0]};
		&save_template($tmpl);
		}
	if (@cgimodes) {
		if (!$tmpl->{'web_cgimode'}) {
			# No CGI mode set at all, so use the first one
			$tmpl->{'web_cgimode'} = $cgimodes[0];
			&save_template($tmpl);
			}
		elsif ($tmpl->{'web_cgimode'} ne 'none' &&
		       &indexof($tmpl->{'web_cgimode'}, @cgimodes) < 0) {
			# Default CGI mode cannot be used
			$tmpl->{'web_cgimode'} = $cgimodes[0];
			&save_template($tmpl);
			}
		}
	elsif (!$tmpl->{'web_cgimode'}) {
		# If no CGI nodes are available and no mode was set,
		# explicitly disable CGIs
		$tmpl->{'web_cgimode'} = 'none';
		&save_template($tmpl);
		}
	}

# Cache current PHP modes and error log files
foreach my $d (grep { &domain_has_website($_) && !$_->{'alias'} }
		    &list_domains()) {
	&lock_domain($d);
	if (!$d->{'php_mode'}) {
		$d->{'php_mode'} = &get_domain_php_mode($d);
		&save_domain($d);
		}
	if (!defined($d->{'php_error_log'})) {
		$d->{'php_error_log'} = &get_domain_php_error_log($d) || "";
		&save_domain($d);
		}
	&unlock_domain($d);
	}
foreach my $d (grep { $_->{'alias'} } &list_domains()) {
	&lock_domain($d);
	my $dd = &get_domain($d->{'alias'});
	if ($dd && $dd->{'php_mode'}) {
		$d->{'php_mode'} = $dd->{'php_mode'};
		&save_domain($d);
		}
	&unlock_domain($d);
	}

# Enable checking for latest scripts
if ($config{'scriptlatest_enabled'} eq '') {
	$config{'scriptlatest_enabled'} = 1;
	&save_module_config();
	&setup_scriptlatest_job(1);
	}

# Prevent an un-needed module config check
if (!$cerr) {
	$config{'last_check'} = time()+1;
	&save_module_config();
	&write_file("$module_config_directory/last-config", \%config);
	}

# Make all domains' .acl files non-world-readable
foreach my $d (grep { !$_->{'parent'} && $_->{'webmin'} } &list_domains()) {
	local @aclfiles = glob("$config_directory/*/$d->{'user'}.acl");
	foreach my $f (@aclfiles) {
		&set_ownership_permissions(undef, undef, 0600, $f);
		}
	}

# Make some module config files containing passwords non-world-readable.
# This is to fix an old Webmin bug that could expose passwords in
# /etc/webmin/*/config files
foreach my $m ("mysql", "postgresql", "ldap-client", "ldap-server",
	       "ldap-useradmin", $module_name) {
	local $mdir = "$config_directory/$m";
	if (-d $mdir) {
		&set_ownership_permissions(undef, undef, 0711,
					   $mdir, "$mdir/config");
		}
	}

# Always update outdated (lower than v3.3)
# Virtualmin default default page
my $readdir = sub {
    my ($dir) = @_;
    my @hdirs;
    return @hdirs if (!-d $dir);
    opendir(my $udir, $dir);
    @hdirs = map { &simplify_path("$dir/$_") }
	         grep {$_ ne '.' && $_ ne '..'} readdir($udir);
    closedir($udir);
    return @hdirs;
    };
foreach my $d (@doms) {
	my $dpubdir = $d->{'public_html_path'};
	next if (!-d $dpubdir);
	my @dpubifiles = &$readdir($dpubdir);
	@dpubifiles = grep { /^$dpubdir\/(index\.html|disabled_by_virtualmin\.html)$/ } @dpubifiles;
	foreach my $dpubifile (@dpubifiles) {
		my $dpubifilelines = &read_file_lines($dpubifile, 1);
		my $lims           = 256;
		my $efix;
		my $line;
		foreach my $l (@{$dpubifilelines}) {
			# If the file is larger than 256 lines, skip the rest
			last if ($line++ > $lims);

			# Get beginning of the string for speed and run
			# extra check to make sure we have a needed file
			$l = substr($l, 0, $lims);

			# Test to make sure that given file is Virtualmin website default page
			$efix++ if (!$efix && $l =~ /iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAABGdBTUEAALGPC/);
			if ($efix == 1 &&
				$l =~ /\*\s(Virtualmin\sLanding|Website\sDefault\sPage|Virtualmin\s+Default\s+Page)\sv([\d+\.]+)$/) {
				my $tmplver = $2;
				$efix++ if ($tmplver && &compare_version_numbers($tmplver, '<=', '3.2'));
				}
			$efix++ if ($efix == 2 && $l =~ /\*\sCopyright\s+[\d]{4}\sVirtualmin(?:,\s+Inc\.)?$/);
			$efix++ if ($efix == 3 && $l =~ /\*\sLicensed\sunder\sMIT$/);
			}

		# After existing file is read and verified to be old
		# Virtualmin default page replace it with new one
		if ($efix == 4) {
			my $domtmplfile = "$default_content_dir/index.html";
			next if (!-r $domtmplfile);
			my $cont = &read_file_contents($domtmplfile);
			my %hashtmp = %$d;
			my %domtmp = %$d;

			# Preserve page type
			$domtmp{'disabled_time'} =
				$dpubifile =~ /index\.html/ ? 0 : 1;

			# Substitute and replace
			%hashtmp = &populate_default_index_page(
					\%domtmp, %hashtmp);
			$cont = &replace_default_index_page(
					\%domtmp, $cont);
			$cont = &substitute_virtualmin_template(
					$cont, \%hashtmp);
			my $fh;
			&open_tempfile_as_domain_user($d, $fh, ">$dpubifile",1);
			&print_tempfile($fh, $cont);
			&close_tempfile_as_domain_user($d, $fh);
			&set_permissions_as_domain_user($d, 0644, $dpubifile);
			}
		}
	}

# Create API helper script /usr/bin/virtualmin
&create_virtualmin_api_helper_command();

# If resource limits are supported, make sure the Apache user isn't limited
if (defined(&supports_resource_limits) &&
    &supports_resource_limits()) {
	&obtain_lock_unix();
	&setup_apache_resource_unlimited();
	&release_lock_unix();
	}

# Update IP list cache
&build_local_ip_list();

# Clear left-side links caches, in case new features are available
&clear_links_cache();

# If no domains yet, fix symlink perms in templates
if (!@doms && $config{'allow_symlinks'} ne '1') {
	&fix_symlink_templates();
	}

# Print warning if PHP or symlink settings have not been checked
local $warn;
if ($config{'allow_symlinks'} eq '') {
	local @fixdoms = &fix_symlink_security(undef, 1);
	$warn++ if (@fixdoms);
	}
if ($warn) {
	print STDERR "WARNING: Potential security problems detected. Login to Virtualmin at\n";
	print STDERR &get_virtualmin_url()," to fix them.\n";
	}

# Fix rate limiting noauth setting
if (!&check_ratelimit() && &is_ratelimit_enabled()) {
	my $conf = &get_ratelimit_config();
	($noauth) = grep { $_->{'name'} eq 'noauth' } @$conf;
	if (!$noauth) {
		&save_ratelimit_directive($conf, undef,
			{ 'name' => 'noauth',
			  'values' => [] });
		&flush_file_lines(&get_ratelimit_config_file());
		}
	}

if (!&check_dkim()) {
	# Cache the DKIM status
	my $dkim = &get_dkim_config();
	$config{'dkim_enabled'} = $dkim && $dkim->{'enabled'} ? 1 : 0;

	if ($dkim) {
		# Replace the list of excluded DKIM domains with a new field
		foreach my $e (@{$dkim->{'exclude'}}) {
			my $d = &get_domain_by("dom", $e);
			if ($d) {
				&lock_domain($d);
				$d->{'dkim_enabled'} = 0;
				&save_domain($d);
				&unlock_domain($d);
				}
			}
		delete($config{'dkim_exclude'});

		# Replace the list of extra DKIM domains with a new field, as
		# long as they are Virtualmin domains
		my @newextra;
		foreach my $e (@{$dkim->{'extra'}}) {
			my $d = &get_domain_by("dom", $e);
			if ($d) {
				&lock_domain($d);
				$d->{'dkim_enabled'} = 1;
				&save_domain($d);
				&unlock_domain($d);
				}
			else {
				push(@newextra, $e);
				}
			}
		$config{'dkim_extra'} = join(' ', @newextra);
		}
	&save_module_config();
	}

# If there are no domains yet, enable shared logrotate
if (!@doms && !$config{'logrotate_shared'}) {
	$config{'logrotate_shared'} = 'yes';
	&save_module_config();
	}

# Lock down transfer hosts file
my $hfile = "$module_config_directory/transfer-hosts";
&set_ownership_permissions(undef, undef, 0600, $hfile);

# Create combined cert files for domains with SSL
foreach my $d (&list_domains()) {
	if (&domain_has_ssl_cert($d)) {
		&sync_combined_ssl_cert($d);
		}
	}

# Update any domains with a new autoconfig.cgi script
&update_all_autoconfig_cgis();

# Fill in any missing quota cache files
if (&has_home_quotas()) {
	foreach my $d (&list_domains()) {
		my $qfile = $quota_cache_dir."/".$d->{'id'};
		next if (-r $qfile);
		my @users = &list_domain_users($d, 1, 1, 0, 1);
		&update_user_quota_cache($d, \@users, 0);
		}
	}

# Try to determine the maximum MariaDB/MySQL username size
if ($config{'mysql_user_size_auto'} != 1) {
	&require_mysql();
	eval {
		local $main::error_must_die = 1;
		my @str = &mysql::table_structure($mysql::master_db, "user");
		my ($ufield) = grep { lc($_->{'field'}) eq 'user' } @str;
		if ($ufield && $ufield->{'type'} =~ /\((\d+)\)/) {
			$config{'mysql_user_size'} = $1;
			}
		};
	$config{'mysql_user_size_auto'} = 1;
	&save_module_config();
	}

# Create S3 account entries from scheduled backups
&create_s3_accounts_from_backups();

# Unlock config now we're done with it
&unlock_file($module_config_file);

# Run any needed actions, like server restarts
&run_post_actions_silently();

# Record the install time for this version
local %itimes;
&read_file($install_times_file, \%itimes);
local $basever = &get_base_module_version();
if (!$itimes{$basever}) {
	$itimes{$basever} = time();
	&write_file($install_times_file, \%itimes);
	}

&webmin_log("postinstall");
}

