# virtual-server-lib.pl
# Common functions for Virtualmin

BEGIN { push(@INC, ".."); };
use WebminCore;

&init_config();
if (&indexof($module_root_directory, @INC) < 0) {
	push(@INC, $module_root_directory);
	}
use Time::Local;
%access = &get_module_acl();

if (!defined($config{'init_template'})) {
	$config{'init_template'} = 0;
	}
if (!defined($config{'initsub_template'})) {
	$config{'initsub_template'} = 1;
	}

if (!$done_virtual_server_lib_funcs) {
	do 'virtual-server-lib-funcs.pl';
	}

# Can this user only view mailboxes in one domain? If so, we use a special UI
$single_domain_mode = !$main::nosingledomain_virtualmin_mode &&
		      $current_theme ne "virtual-server-theme" &&
		      $access{'domains'} =~ /^\d+$/ &&
		      !$access{'edit'} && !$access{'create'} &&
		      !$access{'stop'} && !$access{'local'} ?
			$access{'domains'} : undef;

if (!&master_admin()) {
	# Allowed alias types are set by module config
	%can_alias_types = map { $_, 1 } split(/,/, $config{'alias_types'});
	}
else {
	# All types are allowed
	%can_alias_types = map { $_, 1 } (0 .. 13);
	}

# Only set defaults if not already set
if (!defined($first_print)) {
	$first_print = \&first_html_print;
	$second_print = \&second_html_print;
	$indent_print = \&indent_html_print;
	$outdent_print = \&outdent_html_print;
	}

# For the GPL version, force some features off.
$virtualmin_pro = $module_info{'virtualmin'} eq 'pro' ? 1 : 0;
if (!$virtualmin_pro) {
	$config{'status'} = 0;
	}

# The virtual IP features are always active
$config{'virt'} = 1;
$config{'virt6'} = 1;

&generate_plugins_list($no_virtualmin_plugins ? '' : $config{'plugins'});
@opt_features = ( 'unix', 'dir', 'dns', 'mail', 'web', 'webalizer', 'ssl',
		  'logrotate', 'mysql', 'postgres', 'ftp', 'spam', 'virus',
		  $virtualmin_pro ? ( 'status' ) : ( ),
		  'webmin' );
@vital_features = ( 'dir', 'unix' );
@features = ( @opt_features );
@backup_features = ( 'virtualmin', @features );
@safe_backup_features = ( 'dir', 'mysql', 'postgres' );
@opt_alias_features = ( 'dir', 'mail', 'dns', 'web' );
@opt_subdom_features = ( 'dir', 'dns', 'web', 'ssl' );
@alias_features = ( @opt_alias_features );
@aliasmail_features = ( @opt_alias_features, 'spam', 'virus' );
@subdom_features = ( @opt_subdom_features );
@database_features = ( 'mysql', 'postgres' );
@template_features = ( 'basic', 'resources', @features, 'virt', 'virtualmin',
		       'plugins', 'scripts', 'autoconfig',
		       'phpwrappers', 'avail' );
@template_features_effecting_webmin = ( 'web', 'webmin', 'avail' );
@can_always_features = ( 'dir', 'unix', 'logrotate' );
@validate_features = ( @features, "virt", "virt6" );
foreach my $fname (@features, "virt", "virt6") {
	if (!$done_feature_script{$fname} || $force_load_features) {
		do "$module_root_directory/feature-$fname.pl";
		}
	local $ifunc = "init_$fname";
	&$ifunc() if (defined(&$ifunc));
	}
@migration_types = ( "cpanel", "ensim", "psa", "plesk", "plesk9", "lxadmin",
		     "directadmin" );
@startstop_features = ("web", "dns", "mail", "ftp", "unix", "virus", "spam",
		       "mysql", "postgres");
@bandwidth_features = ( @features, "backup", "restore" );
@config_features = grep { $config{$_} } @features;
@banned_usernames = ( 'root', 'resellers' );

$backup_cron_cmd = "$module_config_directory/backup.pl";
$bw_cron_cmd = "$module_config_directory/bw.pl";
$licence_cmd = "$module_config_directory/licence.pl";
$quotas_cron_cmd = "$module_config_directory/quotas.pl";
$spamclear_cmd = "$module_config_directory/spamclear.pl";
$dynip_cron_cmd = "$module_config_directory/dynip.pl";
$ratings_cron_cmd = "$module_config_directory/sendratings.pl";
$collect_cron_cmd = "$module_config_directory/collectinfo.pl";
$fcgiclear_cron_cmd = "$module_config_directory/fcgiclear.pl";
$maillog_cron_cmd = "$module_config_directory/maillog.pl";
$spamconfig_cron_cmd = "$module_config_directory/spamconfig.pl";
$scriptwarn_cron_cmd = "$module_config_directory/scriptwarn.pl";
$scriptlatest_cron_cmd = "$module_config_directory/scriptlatest.pl";
$spamtrap_cron_cmd = "$module_config_directory/spamtrap.pl";
$validate_cron_cmd = "$module_config_directory/validate.pl";

@all_cron_commands = ( $backup_cron_cmd, $bw_cron_cmd, $licence_cmd,
		       $quotas_cron_cmd, $spamclear_cmd,
		       $dynip_cron_cmd, $ratings_cron_cmd, $collect_cron_cmd,
		       $fcgiclear_cron_cmd, $maillog_cron_cmd,
		       $spamconfig_cron_cmd, $scriptwarn_cron_cmd,
		       $scriptlatest_cron_cmd, $spamtrap_cron_cmd,
		       $validate_cron_cmd, );

$licence_status = &cache_file_path("licence-status");

$custom_fields_file = "$module_config_directory/custom-fields";
$custom_links_file = "$module_config_directory/custom-links";
$custom_link_categories_file = "$module_config_directory/custom-link-cats";
$custom_shells_file = "$module_config_directory/custom-shells";

@scripts_directories = ( &cache_file_path("scripts"),
			 &cache_file_path("latest-scripts"),
			 "$module_root_directory/scripts",
		       );
$script_log_directory = &cache_file_path("scriptlog");
$scripts_unavail_file = &cache_file_path("scriptsunavail");

@styles_directories = ( "$module_config_directory/styles",
			"$module_root_directory/styles",
		      );
$styles_unavail_file = "$module_config_directory/stylesunavail";

@reseller_maxes = ("doms", "aliasdoms", "realdoms", "quota", "mailboxes", "aliases", "dbs", "bw");
@plan_maxes = ("mailbox", "alias", "dbs", "doms", "aliasdoms", "realdoms", "bw",
               $virtualmin_pro ? ( "mongrels" ) : ( ));
@plan_restrictions = ('nodbname', 'norename', 'forceunder', 'safeunder');

@reseller_modules = ("webminlog", "mailboxes", "bind8", "syslog");

$reseller_group_name = "resellers";

@all_template_files = ( "domain-template", "subdomain-template",
			"user-template", "local-template", "bw-template",
			"warnbw-template", "framefwd-template",
			"update-template",
			$virtualmin_pro ? ( "reseller-template" ) : ( ) );

$initial_users_dir = "$module_config_directory/initial";

$saved_aliases_dir = &cache_file_path("saved-aliases");

@edit_limits = ('domain', 'users', 'aliases', 'dbs', 'scripts',
	        'ip', 'dnsip', 'ssl', 'forward', 'redirect', 'admins',
		'spam', 'phpver', 'phpmode',
		'mail', 'backup', 'sched', 'restore', 'sharedips', 'catchall',
		'html', 'allowedhosts', 'passwd', 'spf', 'records',
		'disable', 'delete');
if (!$virtualmin_pro) {
	@edit_limits = grep { $_ ne 'html' } @edit_limits;
	}

@virtualmin_backups = ( 'config', 'templates',
			$virtualmin_pro ? ( 'resellers' ) : ( ),
			'email', 'custom', 'scripts',
			$virtualmin_pro ? ( 'styles' ) : ( ),
		        'scheds',
			&has_ftp_chroot() ? ( 'chroot' ) : ( ),
			'mailserver' );

@limit_types = ("mailboxlimit", "aliaslimit", "dbslimit", "domslimit",
            	"aliasdomslimit", "realdomslimit");
if ($virtualmin_pro) {
	push(@limit_types, "mongrelslimit");
	}

$bandwidth_dir = &cache_file_path("bandwidth");
$plainpass_dir = &cache_file_path("plainpass");
$hashpass_dir = &cache_file_path("hashpass");
$nospam_dir = "$module_config_directory/nospam";
@hashpass_types = ( 'md5', 'crypt', 'unix', 'mysql', 'digest' );

$template_scripts_dir = "$module_config_directory/template-scripts";

$domains_dir = "$module_config_directory/domains";
$templates_dir = "$module_config_directory/templates";
$domainnames_dir = "$module_config_directory/names";
$spamclear_file = "$module_config_directory/spamclear";
$plans_dir = "$module_config_directory/plans";

$extra_admins_dir = "$module_config_directory/admins";
@all_possible_php_versions = (4, 5, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9,
			      "7.0");
@php_wrapper_templates = ("php4cgi", "php5cgi", "php4fcgi", "php5fcgi");
@s3_perl_modules = ( "S3::AWSAuthConnection", "S3::QueryStringAuthGenerator" );
$max_php_fcgid_children = 20;
$s3_upload_tries = $config{'upload_tries'} || 3;
$rs_upload_tries = $config{'upload_tries'} || 3;
$ftp_upload_tries = $config{'upload_tries'} || 3;
$gcs_upload_tries = $config{'upload_tries'} || 3;
$dropbox_upload_tries = $config{'upload_tries'} || 3;

%get_domain_by_maps = ( 'user' => "$module_config_directory/map.user",
			'gid' => "$module_config_directory/map.gid",
			'dom' => "$module_config_directory/map.dom",
			'parent' => "$module_config_directory/map.parent",
			'alias' => "$module_config_directory/map.alias",
			'subdom' => "$module_config_directory/map.subdom",
			'reseller' => "$module_config_directory/map.reseller",
		       );

$denied_ssh_group = "deniedssh";

$script_ratings_dir = &cache_file_path("ratings");
$script_ratings_overall = &cache_file_path("overall-ratings");
$script_ratings_host = "software.virtualmin.com";
$script_ratings_port = 80;
$script_ratings_page = "/cgi-bin/sendratings.cgi";
$script_fetch_ratings_page = "/cgi-bin/getratings.cgi";
$script_download_host = "scripts.virtualmin.com";
$script_download_port = 80;
$script_download_dir = "/";
$script_warnings_file = &cache_file_path("script-warnings-sent");
$osdn_website_host = "sourceforge.net";
$osdn_website_port = 80;

$script_latest_host = "latest-scripts.virtualmin.com";
$script_latest_port = 80;
if ($virtualmin_pro) {
	$script_latest_dir = "/";
	}
else {
	$script_latest_dir = "/gpl/";
	}
$script_latest_file = "scripts.txt";
$script_latest_key = "latest-scripts\@virtualmin.com";

$upgrade_virtualmin_host = "software.virtualmin.com";
$upgrade_virtualmin_port = 80;
$upgrade_virtualmin_testpage = "/licence-test.txt";
$upgrade_virtualmin_updates = "/wbm/updates.txt";

$connectivity_check_host = "software.virtualmin.com";
$connectivity_check_port = 80;
$connectivity_check_page = "/cgi-bin/connectivity.cgi";

$resolve_check_host = "software.virtualmin.com";
$resolve_check_port = 80;
$resolve_check_page = "/cgi-bin/resolve.cgi";

$virtualmin_license_file = "/etc/virtualmin-license";
$virtualmin_yum_repo = "/etc/yum.repos.d/virtualmin.repo";

$collected_info_file = &cache_file_path("collected");
$historic_info_dir = &cache_file_path("history");
@historic_graph_colors = ( '#393939', '#c01627', '#27c016', '#167cc0',
			   '#e6d42d', '#5a16c0', '#16c0af' );

$procmail_log_file = "/var/log/procmail.log";
$procmail_log_cmd = "$module_config_directory/procmail-logger.pl";
$procmail_log_cache = "$ENV{'WEBMIN_VAR'}/procmail.cache";
$procmail_log_times = "$ENV{'WEBMIN_VAR'}/procmail.times";

$mail_login_file = &cache_file_path("mailbox-logins");

@newfeatures_dirs = ( "$module_root_directory/newfeatures-all",
		      $virtualmin_pro ? "$module_root_directory/newfeatures-pro"
				      : "$module_root_directory/newfeatures-gpl" );
$newfeatures_seen_dir = &cache_file_path("seenfeatures");
$install_times_file = &cache_file_path("installtimes");

$disabled_website = "$module_config_directory/disabled.html";
$disabled_website_dir = "$module_config_directory/disabledweb";

$linux_limits_config = "/etc/security/limits.conf";

$scheduled_backups_dir = "$module_config_directory/backups";

$backup_locks_dir = &cache_file_path("backuplocks");

$backup_maxes_file = &cache_file_path("backupsrunning");

$backup_keys_dir = "$module_config_directory/bkeys";

$incremental_backups_dir = &cache_file_path("incremental");

$backups_log_dir = &cache_file_path("backuplogs");

$backups_running_dir = &cache_file_path("backuprunnings");

$global_template_variables_file = "$module_config_directory/globals";

$everyone_alias_dir = "$module_config_directory/everyone";

$ssl_passphrase_dir = "$module_config_directory/sslpass";

@cert_attributes = ('cn', 'o', 'issuer_cn', 'issuer_o', 'notafter',
		    'type', 'alt', 'modulus', 'exponent');

$trap_base_dir = "/var/virtualmin-traps";
$spam_alias_dir = "$trap_base_dir/spam";
$ham_alias_dir = "$trap_base_dir/ham";

$user_quota_warnings_file = "$module_config_directory/quotas-warnings";
$user_quota_msg_file = "$module_config_directory/quotas-template";

@automatic_dns_records = ( "@", "www", "ftp", "localhost", "m");

$links_cache_dir = &cache_file_path("links-cache");

$cloudmin_provisioning_server = "provisioning.virtualmin.com";
$cloudmin_provisioning_port = 10000;
$cloudmin_provisioning_ssl = 1;

$old_uids_file = &cache_file_path("old-uids");
$old_gids_file = &cache_file_path("old-gids");

$recommended_theme = 'authentic-theme';

# generate_plugins_list([list])
# Creates the confplugins, plugins and other arrays based on the module config
# or given space-separated string.
sub generate_plugins_list
{
local $str = defined($_[0]) ? $_[0] : $config{'plugins'};
@confplugins = split(/\s+/, $str);
@plugins = ( );
foreach my $pname (@confplugins) {
	if (&foreign_check($pname)) {
		push(@plugins, $pname);
		}
	}
}

# cache_file_path(name)
# Returns a path in the /var directory unless the file already exists under
# /etc/webmin
sub cache_file_path
{
my ($name) = @_;
if (-e "$module_config_directory/$name" || !$module_var_directory) {
	return "$module_config_directory/$name";
	}
return "$module_var_directory/$name";
}

1;

