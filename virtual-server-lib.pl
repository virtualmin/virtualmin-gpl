# virtual-server-lib.pl
# Common functions for Virtualmin

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
use Time::Local;
%access = &get_module_acl();
if (!defined($access{'feature_unix'})) {
	$access{'feature_unix'} = 1;
	}
if (!defined($access{'feature_dir'})) {
	$access{'feature_dir'} = 1;
	}
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
$single_domain_mode = $access{'domains'} =~ /^\d+$/ &&
		      !$access{'edit'} && !$access{'create'} &&
		      !$access{'stop'} && !$access{'local'} ?
			$access{'domains'} : undef;

if (!&master_admin()) {
	# Allowed alias types are set by module config
	%can_alias_types = map { $_, 1 } split(/,/, $config{'alias_types'});
	}
else {
	# All types are allowed
	%can_alias_types = map { $_, 1 } (0 .. 11);
	}

# Only set defaults if not already set
if (!defined($first_print)) {
	$first_print = \&first_html_print;
	$second_print = \&second_html_print;
	$indent_print = \&indent_html_print;
	$outdent_print = \&outdent_html_print;
	}

# hlink(text, page, [module], [width], [height])
# This is an override for the standard hlink function which checks if the
# file really exists.
sub checked_hlink
{
local ($text, $page, $mod, $width, $height) = @_;
$mod ||= $module_name;
if (!-r &help_file($mod, $page)) {
	return $text;
	}
else {
	$width ||= $tconfig{'help_width'} || $gconfig{'help_width'} || 400;
	$height ||= $tconfig{'help_height'} || $gconfig{'help_height'} || 300;
	return "<a onClick='window.open(\"$gconfig{'webprefix'}/help.cgi/$mod/$_[1]\", \"help\", \"toolbar=no,menubar=no,scrollbars=yes,width=$width,height=$height,resizable=yes\"); return false' href=\"$gconfig{'webprefix'}/help.cgi/$mod/$_[1]\">$_[0]</a>";
	}
}

$virtualmin_pro = $module_info{'virtualmin'} eq 'pro' ? 1 : 0;
if (!$virtualmin_pro) {
	$config{'status'} = 0;
	$config{'spam'} = 0;
	$config{'virus'} = 0;
	$original_hlink = $main::{'hlink'} ||
			  $virtual_server::{'hlink'} ||
			  $gpl_virtual_server::{'hlink'};
	$main::{'hlink'} = \&checked_hlink;
	$virtual_server::{'hlink'} = \&checked_hlink;
	$gpl_virtual_server::{'hlink'} = \&checked_hlink;
	}

@used_webmin_modules = ( "acl", "apache", "bind8", "cron", "htaccess-htpasswd",
			 "init", "ldap-useradmin", "logrotate", "mailboxes",
			 "mount", "mysql", "net", "postfix", "postgresql",
			 "proc", "procmail", "qmailadmin", "quota", "sendmail",
			 "servers", "software",
			 $virtualmin_pro ? ( "spam", "status", "phpini" ) : ( ),
			 "syslog", "useradmin", "usermin", "webalizer",
			 "webmin", "filter" );
@confplugins = split(/\s+/, $config{'plugins'});
@opt_features = ( 'dir', 'unix', 'mail', 'dns', 'web', 'webalizer', 'ssl',
		  'logrotate', 'mysql', 'postgres', 'ftp',
		  $virtualmin_pro ? ( 'spam', 'virus', 'status' ) : ( ),
		  'webmin' );
@vital_features = ( 'dir', 'unix' );
@features = ( @opt_features );
@backup_features = ( 'virtualmin', @features );
@opt_alias_features = ( 'dir', 'mail', 'dns', 'web' );
@opt_subdom_features = ( 'dir', 'dns', 'web', 'ssl' );
@alias_features = ( @opt_alias_features );
@database_features = ( 'mysql', 'postgres' );
@template_features = ( 'basic', 'limits', @features, 'virt',
		       $virtualmin_pro ? ( 'virtualmin' ) : ( ),
		       'plugins',
		       $virtualmin_pro ? ( 'scripts', 'phpwrappers' ) : ( ) );
@template_features_effecting_webmin = ( 'web', 'webmin' );
foreach my $fname (@features, "virt") {
	if (!$done_feature_script{$fname} || $force_load_features) {
		do "$module_root_directory/feature-$fname.pl";
		}
	local $ifunc = "init_$fname";
	&$ifunc() if (defined(&$ifunc));
	}
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
@migration_types = ( "cpanel", "ensim", "plesk" );
@allow_features = (@opt_features, "virt", @feature_plugins);
@startstop_features = ("web", "dns", "mail", "ftp", "unix", "mysql","postgres");
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

@all_cron_commands = ( $backup_cron_cmd, $bw_cron_cmd, $licence_cmd,
		       $licence_status, $quotas_cron_cmd, $spamclear_cmd,
		       $dynip_cron_cmd, $ratings_cron_cmd, $collect_cron_cmd,
		       $fcgiclear_cron_cmd, $maillog_cron_cmd,
		       $spamconfig_cron_cmd, $scriptwarn_cron_cmd );

$custom_fields_file = "$module_config_directory/custom-fields";
$custom_links_file = "$module_config_directory/custom-links";
$custom_link_categories_file = "$module_config_directory/custom-link-cats";

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

@all_template_files = ( "domain-template", "subdomain-template",
			"user-template", "local-template", "bw-template",
			"warnbw-template", "framefwd-template",
			"update-template",
			$virtualmin_pro ? ( "reseller-template" ) : ( ) );

$initial_users_dir = "$module_config_directory/initial";

@edit_limits = ('domain', 'users', 'aliases', 'dbs', 'scripts',
	        'ip', 'ssl', 'forward', 'admins', 'spam', 'phpver', 'backup',
		'sharedips', 'catchall', 'html', 'disable', 'delete');
if (!$virtualmin_pro) {
	@edit_limits = grep { $_ ne 'scripts' && $_ ne 'admins' &&
			      $_ ne 'spam' && $_ ne 'phpver' } @edit_limits;
	}

@virtualmin_backups = ( 'config', 'templates',
			$virtualmin_pro ? ( 'resellers' ) : ( ),
			'email', 'custom',
			$virtualmin_pro ? ( 'scripts', 'styles' ) : ( ) );

@limit_types = ("mailboxlimit", "aliaslimit", "dbslimit", "domslimit",
            	"aliasdomslimit", "realdomslimit");

$bandwidth_dir = "$module_config_directory/bandwidth";
$plainpass_dir = "$module_config_directory/plainpass";

$template_scripts_dir = "$module_config_directory/template-scripts";

$domains_dir = "$module_config_directory/domains";
$templates_dir = "$module_config_directory/templates";
$domainnames_dir = "$module_config_directory/names";
$spamclear_file = "$module_config_directory/spamclear";

$extra_admins_dir = "$module_config_directory/admins";
@all_possible_php_versions = (4, 5);
@php_wrapper_templates = ("php4cgi", "php5cgi", "php4fcgi", "php5fcgi");
@s3_perl_modules = ( "S3::AWSAuthConnection", "S3::QueryStringAuthGenerator" );
$max_php_fcgid_children = 20;
$default_php_fcgid_children = 4;

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

$upgrade_virtualmin_host = "software.virtualmin.com";
$upgrade_virtualmin_port = 80;
$upgrade_virtualmin_testpage = "/licence-test.txt";
$upgrade_virtualmin_updates = "/wbm/updates.txt";

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

