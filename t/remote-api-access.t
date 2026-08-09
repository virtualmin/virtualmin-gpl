#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile($root, 'commands-lib.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

my %expected_commands = (
	'create-admin' => 'can_edit_admins',
	'create-alias' => 'can_edit_aliases',
	'create-database' => 'can_edit_databases',
	'create-domain' => 'can_create_sub_servers',
	'create-proxy' => 'can_edit_forward',
	'create-redirect' => 'can_edit_redirect',
	'create-simple-alias' => 'can_edit_aliases',
	'backup-domain' => 'can_backup_domain',
	'check-connectivity' => 'can_edit_domain',
	'clone-domain' => 'can_create_sub_servers',
	'create-scheduled-backup' => 'can_backup_domain',
	'create-user' => 'can_edit_users',
	'delete-admin' => 'can_edit_admins',
	'delete-alias' => 'can_edit_aliases',
	'delete-backup' => 'can_backup_log',
	'delete-database' => 'can_edit_databases',
	'delete-domain' => 'can_delete_domain',
	'delete-php-directory' => 'can_edit_phpver',
	'delete-scheduled-backup' => 'can_backup_sched',
	'delete-proxy' => 'can_edit_forward',
	'delete-redirect' => 'can_edit_redirect',
	'delete-script' => 'can_edit_scripts',
	'delete-user' => 'can_edit_users',
	'detect-scripts' => 'can_edit_scripts',
	'disable-domain' => 'can_disable_domain',
	'disable-feature' => 'can_config_domain',
	'disconnect-database' => 'can_remote_import_databases',
	'enable-domain' => 'can_disable_domain',
	'enable-feature' => 'can_config_domain',
	'generate-acme-cert' => 'can_remote_edit_acme',
	'fix-domain-permissions' => 'can_config_domain',
	'fix-domain-quota' => 'can_edit_quotas',
	'generate-cert' => 'can_edit_ssl',
	'generate-letsencrypt-cert' => 'can_remote_edit_acme',
	'get-command' => 'can_use_remote_api',
	'get-dns' => 'can_edit_records',
	'get-logs' => 'can_remote_read_logs',
	'get-ssl' => 'can_edit_ssl',
	'import-database' => 'can_remote_import_databases',
	'install-cert' => 'can_edit_ssl',
	'install-script' => 'can_edit_scripts',
	'list-admins' => 'can_edit_admins',
	'list-aliases' => 'can_edit_aliases',
	'list-available-scripts' => 'can_edit_scripts',
	'list-available-shells' => 'can_edit_users',
	'list-backup-keys' => 'can_backup_keys',
	'list-bandwidth' => 'can_remote_read_bandwidth',
	'list-certs' => 'can_edit_ssl',
	'list-certs-expiry' => 'can_edit_ssl',
	'list-commands' => 'can_use_remote_api',
	'list-custom' => 'can_edit_domain',
	'list-databases' => 'can_edit_databases',
	'list-domains' => 'can_edit_domain',
	'list-features' => 'can_edit_domain',
	'list-backup-logs' => 'can_backup_log',
	'list-mailbox' => 'can_remote_read_mailbox',
	'list-php-directories' => 'can_edit_phpver',
	'list-php-ini' => 'can_edit_phpmode',
	'list-php-versions' => 'can_edit_phpver',
	'list-ports' => 'can_edit_domain',
	'list-proxies' => 'can_edit_forward',
	'list-redirects' => 'can_edit_redirect',
	'list-scheduled-backups' => 'can_backup_sched',
	'list-scripts' => 'can_edit_scripts',
	'list-service-certs' => 'can_edit_ssl',
	'list-simple-aliases' => 'can_edit_aliases',
	'list-users' => 'can_edit_users',
	'modify-admin' => 'can_edit_admins',
	'modify-custom' => 'can_config_domain',
	'modify-domain' => 'can_config_domain',
	'modify-database-hosts' => 'can_remote_edit_database_hosts',
	'modify-database-pass' => 'can_edit_databases',
	'modify-database-user' => 'can_edit_databases',
	'modify-dns' => 'can_remote_edit_dns',
	'modify-mail' => 'can_edit_mail',
	'modify-php-ini' => 'can_edit_phpmode',
	'modify-proxy' => 'can_edit_forward',
	'modify-scheduled-backup' => 'can_backup_sched',
	'modify-spam' => 'can_edit_spam',
	'modify-user' => 'can_edit_users',
	'modify-web' => 'can_remote_edit_web',
	'resend-email' => 'can_edit_users',
	'reset-feature' => 'can_config_domain',
	'restore-domain' => 'can_restore_domain',
	'rename-domain' => 'can_rename_domains',
	'reset-pass' => 'can_edit_users',
	'search-maillogs' => 'can_view_maillog',
	'set-php-directory' => 'can_edit_phpver',
	'start-stop-script' => 'can_edit_scripts',
	'syncmx-domain' => 'can_edit_mail',
	'unalias-domain' => 'can_config_domain',
	'unsub-domain' => 'can_config_domain',
	'validate-domains' => 'can_use_validation',
	);

{
	no warnings qw(once redefine);
	local @main::plugins = ();
	local %main::access = ();
	my $reseller = 0;
	local *main::master_admin = sub { 0 };
	local *main::reseller_admin = sub { $reseller };
	ok(!&can_use_remote_api(),
		'remote API access is denied by default');
	ok(!&can_remote_as_user('list-databases'),
		'allowed commands remain denied without API permission');
	ok(!&can_remote_as_user('configure-script'),
		'existing user API commands also require permission');
	$main::access{'edit_remote_api'} = 1;
	ok(&can_use_remote_api(),
		'domain owner can use the remote API when granted permission');
	ok(&can_remote_as_user('configure-script'),
		'existing user API commands remain available when permitted');
	foreach my $command (sort keys %expected_commands) {
		ok(&can_remote_as_user($command),
			"$command is allowed for permitted non-master API users");
		is(&get_user_remote_api_command($command.'.pl'),
			$expected_commands{$command},
			"$command has its audited capability");
		}
	ok(!&can_remote_as_user('modify-limits'),
		'unaudited core commands remain denied');
	delete($main::access{'edit_remote_api'});
	$reseller = 1;
	ok(&can_use_remote_api(),
		'reseller remote API behavior remains unchanged');
	}

{
	no warnings qw(once redefine);
	local %main::access = ( 'edit_remote_api' => 1 );
	local *main::master_admin = sub { 0 };
	local *main::reseller_admin = sub { 0 };
	local *main::can_edit_domain = sub { $_[0]->{'allowed'} };
	local *main::can_edit_databases = sub { 1 };
	local *main::can_edit_users = sub { 1 };
	local *main::text = sub {
		my ($key, $domain) = @_;
		return $key eq 'remote_ecannotcap' ?
			"You are not allowed to run this command for virtual server $domain" :
			"Virtual server $domain does not exist";
		};

	ok(&remote_api_can_domain(
		{ 'allowed' => 1 }, 'list-databases.pl'),
		'owned domain passes its command capability check');
	ok(!&remote_api_can_domain(
		{ 'allowed' => 0 }, 'list-databases.pl'),
		'foreign domain is denied');
	ok(&remote_api_can_domain(
		{ 'allowed' => 1 }, 'modify-user.pl'),
		'owned domain passes the user modification capability check');

	local *main::can_edit_databases = sub { 0 };
	ok(!&remote_api_can_domain(
		{ 'allowed' => 1 }, 'list-databases.pl'),
		'owned domain is denied without the required capability');
	ok(!&remote_api_can_domain(
		{ 'allowed' => 1 }, 'modify-limits.pl'),
		'unaudited command is denied at the domain boundary');

	local *main::can_edit_users = sub { 0 };
	ok(!&remote_api_can_domain(
		{ 'allowed' => 1 }, 'modify-user.pl'),
		'owned domain is denied without user management capability');

	local $0 = File::Spec->catfile($root, 'list-databases.pl');
	my ($status, $out) = &run_domain_guard(
		{ 'allowed' => 1 }, 'example.test', undef);
	ok($status, 'missing capability exits with a failure');
	is($out,
		"You are not allowed to run this command for virtual server example.test\n",
		'current API program is taken from $0');

	($status, $out) = &run_domain_guard(
		{ 'allowed' => 0 }, 'foreign.test', 'list-databases.pl');
	ok($status, 'foreign domain exits with a failure');
	is($out, "Virtual server foreign.test does not exist\n",
		'foreign domain remains hidden');
	}

{
	no warnings qw(redefine);
	local *main::master_admin = sub { 1 };
	ok(&remote_api_can_domain(undef, 'not-allowed.pl'),
		'master API and standalone root behavior remains unrestricted');
	}

{
	no warnings qw(once redefine);
	local %main::access = ( 'edit_remote_api' => 1 );
	my ($import, $hosts) = (0, 0);
	local *main::master_admin = sub { 0 };
	local *main::reseller_admin = sub { 0 };
	local *main::can_edit_domain = sub { 1 };
	local *main::can_edit_databases = sub { 1 };
	local *main::can_import_servers = sub { $import };
	local *main::can_allowed_db_hosts = sub { $hosts };
	my $domain = { 'dom' => 'example.test' };
	ok(!&remote_api_can_domain($domain, 'import-database'),
		'database imports require import permission');
	$import = 1;
	ok(&remote_api_can_domain($domain, 'import-database'),
		'database imports pass with both permissions');
	ok(!&remote_api_can_domain($domain, 'modify-database-hosts'),
		'database host changes require allowed-host permission');
	$hosts = 1;
	ok(&remote_api_can_domain($domain, 'modify-database-hosts'),
		'database host changes pass with both permissions');
	ok(&remote_api_can_domain($domain, 'modify-database-user'),
		'database login changes require database permission only');
	}

{
	no warnings qw(once redefine);
	local %main::access = ( 'edit_remote_api' => 1 );
	local %main::config = ( 'bw_active' => 0 );
	my ($logs, $bandwidth) = (0, 0);
	local *main::master_admin = sub { 0 };
	local *main::reseller_admin = sub { 0 };
	local *main::can_edit_domain = sub { 1 };
	local *main::foreign_available = sub {
		return $_[0] eq 'logviewer' && $logs;
		};
	local *main::can_monitor_bandwidth = sub { $bandwidth };
	my $domain = { 'dom' => 'example.test' };
	ok(!&remote_api_can_domain($domain, 'get-logs'),
		'web logs require access to the log viewer module');
	$logs = 1;
	ok(&remote_api_can_domain($domain, 'get-logs'),
		'web logs pass when the log viewer is available');
	ok(!&remote_api_can_domain($domain, 'list-bandwidth'),
		'bandwidth data is denied when monitoring is disabled');
	$main::config{'bw_active'} = 1;
	ok(!&remote_api_can_domain($domain, 'list-bandwidth'),
		'bandwidth data is denied for an unmonitored domain');
	$bandwidth = 1;
	# Isolate the bw_active gate: monitoring available but accounting off
	$main::config{'bw_active'} = 0;
	ok(!&remote_api_can_domain($domain, 'list-bandwidth'),
		'bandwidth data is denied when accounting is turned off');
	$main::config{'bw_active'} = 1;
	ok(&remote_api_can_domain($domain, 'list-bandwidth'),
		'bandwidth data passes for a monitored domain');
	}

{
	no warnings qw(once redefine);
	local %main::access = ( 'edit_remote_api' => 1 );
	local %main::text = (
		'remote_ecannotcmd' => 'You are not allowed to run this command',
		);
	local *main::master_admin = sub { 0 };
	local *main::reseller_admin = sub { 0 };
	local *main::can_edit_scripts = sub { 1 };
	my ($status, $out) =
		&run_command_guard('list-available-scripts.pl');
	ok(!$status, 'domainless command passes its capability check');
	is($out, '', 'allowed domainless command produces no guard output');
	local *main::can_edit_scripts = sub { 0 };
	($status, $out) = &run_command_guard('list-available-scripts.pl');
	ok($status, 'domainless command is denied without its capability');
	is($out, "You are not allowed to run this command\n",
		'domainless command denial has a clear error');
	($status, $out) = &run_command_guard('modify-limits.pl');
	ok($status, 'unregistered domainless command is denied');
	is($out, "You are not allowed to run this command\n",
		'unregistered domainless command has a clear error');
	}

{
	no warnings qw(once redefine);
	my @guard;
	my $domain = { 'dom' => 'example.test' };
	local *main::get_domain_by = sub {
		is_deeply(\@_, [ 'dom', 'example.test' ],
			'remote domain helper performs one lookup');
		return $domain;
		};
	local *main::require_remote_api_domain = sub { @guard = @_ };
	is(&get_remote_api_domain('dom', 'example.test'), $domain,
		'remote domain helper returns the resolved domain');
	is($guard[0], $domain, 'resolved domain is authorized');
	is($guard[1], 'example.test', 'requested domain is preserved');
	is(scalar(@guard), 2,
		'remote domain helper leaves program detection to the guard');
	}

{
	no warnings qw(once redefine);
	my @checked;
	my @domains = (
		{ 'dom' => 'owned.test', 'allowed' => 1 },
		{ 'dom' => 'foreign.test', 'allowed' => 0 },
		);
	local *main::master_admin = sub { 0 };
	local *main::can_edit_domain = sub { $_[0]->{'allowed'} };
	local *main::require_remote_api_domain = sub { push(@checked, $_[0]) };
	my @filtered = &get_remote_api_domains(\@domains, 1, 'list-domains');
	is_deeply(\@filtered, [ $domains[0] ],
		'all-domain requests are limited to visible domains');
	is_deeply(\@checked, [ $domains[0] ],
		'filtered domains are authorized without another lookup');
	@checked = ( );
	my @explicit = &get_remote_api_domains([ $domains[0] ], 0,
		'list-domains');
	is_deeply(\@explicit, [ $domains[0] ],
		'explicit domain requests preserve their targets');
	is_deeply(\@checked, [ $domains[0] ],
		'explicit targets use the same authorization boundary');
	}

my %pro_only = map { $_, 1 } &list_pro_only_api_commands();
my %object_capabilities = map { $_, 1 }
	qw(can_backup_log can_backup_sched can_view_maillog);
my %object_commands = (
	'delete-backup' => 'can_backup_log',
	'search-maillogs' => 'can_view_maillog',
	'list-backup-logs' => 'can_backup_log',
	'list-scheduled-backups' => 'can_backup_sched',
	'delete-scheduled-backup' => 'can_backup_sched',
	'modify-scheduled-backup' => 'can_backup_sched',
	);
my %domainless_commands = map { $_, 1 }
	qw(get-command list-available-scripts list-available-shells list-backup-keys
	   list-certs-expiry list-commands);
foreach my $command (sort keys %expected_commands) {
	my $path = File::Spec->catfile($root, $command.'.pl');
	if ($object_capabilities{$expected_commands{$command}}) {
		ok($object_commands{$command},
			"$command uses an object capability and is declared as ".
			"an object command");
		}
	if (!-f $path) {
		# Commands that ship only in the Pro edition live in a
		# separate repository, checked out alongside this one
		my $propath = File::Spec->catfile(
			dirname($root), 'virtualmin-pro', $command.'.pl');
		if ($pro_only{$command.'.pl'} && !-f $propath) {
			ok(1, "$command is a Pro command, not checked out");
			next;
			}
		ok($pro_only{$command.'.pl'},
			"$command is missing here so must be a Pro command");
		$path = $propath;
		}
	ok(-f $path, "$command script exists");
	open(my $fh, '<', $path) || die "Cannot read $path: $!";
	local $/ = undef;
	my $source = <$fh>;
	close($fh);
	if ($domainless_commands{$command}) {
		like($source, qr/require_remote_api_command\s*\(/,
			"$command uses the shared command boundary");
		if ($command eq 'list-certs-expiry') {
			like($source, qr/get_remote_api_domains\s*\(/,
				"$command limits certificate collection by domain");
			unlike($source, qr/`virtualmin\s+list-certs/,
				"$command does not bypass ACLs through the root CLI");
			}
		elsif ($command eq 'list-backup-keys') {
			like($source, qr/can_use_backup_key\s*\(/,
				"$command includes keys shared for creating backups");
			}
		}
	elsif ($object_commands{$command}) {
		# Their capability takes an object, so they must not resolve a
		# domain through the shared boundary with it
		unlike($source, qr/get_remote_api_domain(?:s)?\s*\(/,
			"$command does not mix an object capability with a ".
			"domain boundary");
		# These authorize their own object or scope rather than a domain
		like($source, qr/$object_commands{$command}\s*\(/,
			"$command checks its own object permission");
		}
	elsif ($command eq 'restore-domain') {
		# Its targets come from inside the archive, so it authorizes
		# each one directly and limits what may be restored
		like($source, qr/can_restore_domain\s*\(/,
			"$command checks the restore permission");
		like($source, qr/can_edit_domain\s*\(\s*\$dinfo\s*\)/,
			"$command checks ownership of each restored domain");
		like($source, qr/safe_backup_features/,
			"$command limits non-master restores to safe features");
		}
	elsif ($command eq 'create-domain') {
		# Creation has no target domain yet, so it authorizes the
		# parent that the new sub-server will be created under
		like($source, qr/can_create_sub_servers\s*\(/,
			"$command checks the sub-server creation permission");
		like($source, qr/can_edit_domain\s*\(\s*\$parent\s*\)/,
			"$command checks ownership of the parent domain");
		like($source, qr/allowed_domain_name\s*\(\s*\$parent\s*,/,
			"$command checks name restrictions against the parent");
		like($source,
			qr/elsif \(\$a eq "--pre-command"\) \{\s*\$is_master \|\|/s,
			"$command keeps pre-creation commands master-only");
		like($source,
			qr/elsif \(\$a eq "--post-command"\) \{\s*\$is_master \|\|/s,
			"$command keeps post-creation commands master-only");
		like($source,
			qr/if \(!\$skipwarnings \|\| !\$is_master\) \{\s*\$err = &valid_domain_name/s,
			"$command always validates owner-supplied domain names");
		like($source,
			qr/if \(!\$skipwarnings \|\| !\$is_master\) \{\s*foreach my \$ff \(&forbidden_domain_features/s,
			"$command does not let owners skip forbidden features");
		like($source, qr/defined\(\$jail\).*master administrator/s,
			"$command keeps jail selection master-only");
		like($source, qr/\(\$myserver \|\| \$pgserver\).*master administrator/s,
			"$command keeps database server selection master-only");
		like($source, qr/defined\(\$dns_ip\).*can_dnsip/s,
			"$command requires DNS IP permission");
		like($source, qr/\$fwdto.*can_edit_catchall/s,
			"$command requires catch-all permission");
		like($source, qr/defined\(\$content\).*can_edit_html/s,
			"$command requires website content permission");
		like($source, qr/\$proxy_pass_mode.*can_edit_forward/s,
			"$command requires proxy permission");
		like($source,
			qr/\$proxy_pass !~ \/\^\(http\|https\).*Proxy URLs must start/s,
			"$command validates owner-supplied proxy URLs");
		like($source, qr/defined\(\$aliasredir\).*can_edit_redirect/s,
			"$command requires redirect permission");
		}
	else {
		like($source, qr/get_remote_api_domain(?:s)?\s*\(/,
			"$command uses a shared domain boundary");
		if ($command eq 'modify-domain') {
			like($source, qr/check_password_restrictions\s*\(/,
				"$command enforces the domain password policy");
			like($source, qr/virtual_server_limits\s*\(/,
				"$command enforces domain plan limits");
			}
		elsif ($command eq 'enable-feature') {
			like($source,
				qr/!\$skipwarnings \|\| !\$is_master.*\@forbidden_domain_features/s,
				"$command does not let owners skip forbidden features");
			}
		elsif ($command eq 'backup-domain' ||
		       $command eq 'create-scheduled-backup') {
			like($source, qr/can_use_backup_key\s*\(/,
				"$command permits keys shared for creating backups");
			}
		}
	}

done_testing();

# run_domain_guard(&domain, requested-domain, program-name)
# Runs the terminating domain guard in a child and returns its status and output.
sub run_domain_guard
{
my ($domain, $requested, $program) = @_;
pipe(my $reader, my $writer) || die "pipe failed: $!";
my $pid = fork();
defined($pid) || die "fork failed: $!";
if (!$pid) {
	close($reader);
	open(STDOUT, '>&', $writer) || die "redirect failed: $!";
	close($writer);
	&require_remote_api_domain($domain, $requested, $program);
	exit(0);
	}
close($writer);
local $/ = undef;
my $output = <$reader>;
close($reader);
waitpid($pid, 0);
return ($?, $output);
}

# run_command_guard(program-name)
# Runs the terminating command guard in a child and returns status and output.
sub run_command_guard
{
my ($program) = @_;
pipe(my $reader, my $writer) || die "pipe failed: $!";
my $pid = fork();
defined($pid) || die "fork failed: $!";
if (!$pid) {
	close($reader);
	open(STDOUT, '>&', $writer) || die "redirect failed: $!";
	close($writer);
	&require_remote_api_command($program);
	exit(0);
	}
close($writer);
local $/ = undef;
my $output = <$reader>;
close($reader);
waitpid($pid, 0);
return ($?, $output);
}
