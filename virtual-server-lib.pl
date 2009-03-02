# virtual-server-lib.pl
# Common functions for Virtualmin

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	# Old Webmin version
	do '../web-lib.pl';
	do '../ui-lib.pl';
	}

&init_config();
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

@used_webmin_modules = ( "acl", "apache", "bind8", "cron", "htaccess-htpasswd",
			 "init", "ldap-useradmin", "logrotate", "mailboxes",
			 "mount", "mysql", "net", "postfix", "postgresql",
			 "proc", "procmail", "qmailadmin", "quota", "sendmail",
			 "servers", "software", "spam",
			 $virtualmin_pro ? ( "status", "phpini" ) : ( ),
			 "syslog", "useradmin", "usermin", "webalizer",
			 "webmin", "filter" );
&generate_plugins_list($no_virtualmin_plugins ? '' : $config{'plugins'});
@opt_features = ( 'unix', 'dir', 'mail', 'dns', 'web', 'webalizer', 'ssl',
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
@subdom_features = ( @opt_subdom_features );
@database_features = ( 'mysql', 'postgres' );
@template_features = ( 'basic', 'resources', @features, 'virt',
		       $virtualmin_pro ? ( 'virtualmin' ) : ( ),
		       'plugins',
		       $virtualmin_pro ? ( 'scripts', 'phpwrappers' ) : ( ) );
@template_features_effecting_webmin = ( 'web', 'webmin' );
@can_always_features = ( 'dir', 'unix', 'logrotate' );
foreach my $fname (@features, "virt") {
	if (!$done_feature_script{$fname} || $force_load_features) {
		do "$module_root_directory/feature-$fname.pl";
		}
	local $ifunc = "init_$fname";
	&$ifunc() if (defined(&$ifunc));
	}
@migration_types = ( "cpanel", "ensim", "plesk", "psa" );
@allow_features = (@opt_features, "virt", @feature_plugins);
@startstop_features = ("web", "dns", "mail", "ftp", "unix", "virus",
		       "mysql", "postgres");
@all_database_types = ( ($config{'mysql'} ? ("mysql") : ( )),
		        ($config{'postgres'} ? ("postgres") : ( )),
		        @database_plugins );
@banned_usernames = ( 'root' );

$backup_cron_cmd = "$module_config_directory/backup.pl";
$bw_cron_cmd = "$module_config_directory/bw.pl";
$licence_cmd = "$module_config_directory/licence.pl";
$licence_status = "$module_config_directory/licence-status";
$quotas_cron_cmd = "$module_config_directory/quotas.pl";
$spamclear_cmd = "$module_config_directory/spamclear.pl";
$dynip_cron_cmd = "$module_config_directory/dynip.pl";
$ratings_cron_cmd = "$module_config_directory/sendratings.pl";
$collect_cron_cmd = "$module_config_directory/collectinfo.pl";
$fcgiclear_cron_cmd = "$module_config_directory/fcgiclear.pl";
$maillog_cron_cmd = "$module_config_directory/maillog.pl";
$spamconfig_cron_cmd = "$module_config_directory/spamconfig.pl";
$scriptwarn_cron_cmd = "$module_config_directory/scriptwarn.pl";
$spamtrap_cron_cmd = "$module_config_directory/spamtrap.pl";

@all_cron_commands = ( $backup_cron_cmd, $bw_cron_cmd, $licence_cmd,
		       $licence_status, $quotas_cron_cmd, $spamclear_cmd,
		       $dynip_cron_cmd, $ratings_cron_cmd, $collect_cron_cmd,
		       $fcgiclear_cron_cmd, $maillog_cron_cmd,
		       $spamconfig_cron_cmd, $scriptwarn_cron_cmd,
		       $spamtrap_cron_cmd );

$custom_fields_file = "$module_config_directory/custom-fields";
$custom_links_file = "$module_config_directory/custom-links";
$custom_link_categories_file = "$module_config_directory/custom-link-cats";
$custom_shells_file = "$module_config_directory/custom-shells";

@scripts_directories = ( "$module_config_directory/scripts",
			 "$module_root_directory/scripts",
		       );
$script_log_directory = "$module_config_directory/scriptlog";
$scripts_unavail_file = "$module_config_directory/scriptsunavail";

@styles_directories = ( "$module_config_directory/styles",
			"$module_root_directory/styles",
		      );
$styles_unavail_file = "$module_config_directory/stylesunavail";

@reseller_maxes = ("doms", "aliasdoms", "realdoms", "quota", "mailboxes", "aliases", "dbs", "bw");
@plan_maxes = ("mailbox", "alias", "dbs", "doms", "aliasdoms", "realdoms", "bw",
               $virtualmin_pro ? ( "mongrels" ) : ( ));
@plan_restrictions = ('nodbname', 'norename', 'forceunder');

@reseller_modules = ("webminlog", "mailboxes");

@all_template_files = ( "domain-template", "subdomain-template",
			"user-template", "local-template", "bw-template",
			"warnbw-template", "framefwd-template",
			"update-template",
			$virtualmin_pro ? ( "reseller-template" ) : ( ) );

$initial_users_dir = "$module_config_directory/initial";

@edit_limits = ('domain', 'users', 'aliases', 'dbs', 'scripts',
	        'ip', 'ssl', 'forward', 'admins', 'spam', 'phpver', 'mail',
	 	'backup', 'sched', 'restore', 'sharedips', 'catchall', 'html',
		'allowedhosts', 'disable', 'delete');
if (!$virtualmin_pro) {
	@edit_limits = grep { $_ ne 'scripts' && $_ ne 'html' &&
			      $_ ne 'phpver' } @edit_limits;
	}

@virtualmin_backups = ( 'config', 'templates',
			$virtualmin_pro ? ( 'resellers' ) : ( ),
			'email', 'custom',
			$virtualmin_pro ? ( 'scripts', 'styles' ) : ( ),
		        'scheds',
			&has_ftp_chroot() ? ( 'chroot' ) : ( ) );

@limit_types = ("mailboxlimit", "aliaslimit", "dbslimit", "domslimit",
            	"aliasdomslimit", "realdomslimit");
if ($virtualmin_pro) {
	push(@limit_types, "mongrelslimit");
	}

$bandwidth_dir = "$module_config_directory/bandwidth";
$plainpass_dir = "$module_config_directory/plainpass";
$nospam_dir = "$module_config_directory/nospam";

$template_scripts_dir = "$module_config_directory/template-scripts";

$domains_dir = "$module_config_directory/domains";
$templates_dir = "$module_config_directory/templates";
$domainnames_dir = "$module_config_directory/names";
$spamclear_file = "$module_config_directory/spamclear";
$plans_dir = "$module_config_directory/plans";

$extra_admins_dir = "$module_config_directory/admins";
@all_possible_php_versions = (4, 5);
@php_wrapper_templates = ("php4cgi", "php5cgi", "php4fcgi", "php5fcgi");
@s3_perl_modules = ( "S3::AWSAuthConnection", "S3::QueryStringAuthGenerator" );
$max_php_fcgid_children = 20;

%get_domain_by_maps = ( 'user' => "$module_config_directory/map.user",
			'gid' => "$module_config_directory/map.gid",
			'dom' => "$module_config_directory/map.dom",
			'parent' => "$module_config_directory/map.parent",
			'alias' => "$module_config_directory/map.alias",
			'subdom' => "$module_config_directory/map.subdom",
			'reseller' => "$module_config_directory/map.reseller",
		       );

$denied_ssh_group = "deniedssh";

$script_ratings_dir = "$module_config_directory/ratings";
$script_ratings_overall = "$module_config_directory/overall-ratings";
$script_ratings_host = "software.virtualmin.com";
$script_ratings_port = 80;
$script_ratings_page = "/cgi-bin/sendratings.cgi";
$script_fetch_ratings_page = "/cgi-bin/getratings.cgi";
$script_download_host = "scripts.virtualmin.com";
$script_download_port = 80;
$script_download_dir = "/";
$script_warnings_file = "$module_config_directory/script-warnings-sent";

$upgrade_virtualmin_host = "software.virtualmin.com";
$upgrade_virtualmin_port = 80;
$upgrade_virtualmin_testpage = "/licence-test.txt";
$upgrade_virtualmin_updates = "/wbm/updates.txt";

$connectivity_check_host = "software.virtualmin.com";
$connectivity_check_port = 80;
$connectivity_check_page = "/cgi-bin/connectivity.cgi";

$virtualmin_license_file = "/etc/virtualmin-license";
$virtualmin_yum_repo = "/etc/yum.repos.d/virtualmin.repo";

$collected_info_file = "$module_config_directory/collected";
$historic_info_dir = "$module_config_directory/history";
@historic_graph_colors = ( '#393939', '#c01627', '#27c016', '#167cc0',
			   '#e6d42d', '#5a16c0', '#16c0af' );

$procmail_log_file = "/var/log/procmail.log";
$procmail_log_cmd = "$module_config_directory/procmail-logger.pl";
$procmail_log_cache = "$ENV{'WEBMIN_VAR'}/procmail.cache";
$procmail_log_times = "$ENV{'WEBMIN_VAR'}/procmail.times";

@newfeatures_dirs = ( "$module_root_directory/newfeatures-all",
		      $virtualmin_pro ? "$module_root_directory/newfeatures-pro"
				      : "$module_root_directory/newfeatures-gpl" );
$newfeatures_seen_dir = "$module_config_directory/seenfeatures";
$install_times_file = "$module_config_directory/installtimes";

$disabled_website = "$module_config_directory/disabled.html";
$disabled_website_dir = "$module_config_directory/disabledweb";

$linux_limits_config = "/etc/security/limits.conf";

$scheduled_backups_dir = "$module_config_directory/backups";

$incremental_backups_dir = "$module_config_directory/incremental";

$global_template_variables_file = "$module_config_directory/globals";

$everyone_alias_dir = "$module_config_directory/everyone";

$ssl_passphrase_dir = "$module_config_directory/sslpass";

$trap_base_dir = "/var/virtualmin-traps";
$spam_alias_dir = "$trap_base_dir/spam";
$ham_alias_dir = "$trap_base_dir/ham";

$user_quota_warnings_file = "$module_config_directory/quotas-warnings";

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
		&foreign_require($pname, "virtual_feature.pl");
		push(@plugins, $pname);
		}
	}
@feature_plugins = grep { &plugin_defined($_, "feature_setup") } @plugins;
@mail_plugins = grep { &plugin_defined($_, "mailbox_inputs") } @plugins;
@database_plugins = grep { &plugin_defined($_, "database_name") } @plugins;
@startstop_plugins = grep { &plugin_defined($_, "feature_startstop") } @plugins;
@backup_plugins = grep { &plugin_defined($_, "feature_backup") } @plugins;
@script_plugins = grep { &plugin_defined($_, "scripts_list") } @plugins;
@style_plugins = grep { &plugin_defined($_, "styles_list") } @plugins;
}

1;

