#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $feature = File::Spec->catfile($root, 'feature-mysql.pl');
my $loaded = do $feature;
die $@ if ($@);
die "Failed to load $feature: $!" if (!defined($loaded));
my $backups = File::Spec->catfile($root, 'backups-lib.pl');
$loaded = do $backups;
die $@ if ($@);
die "Failed to load $backups: $!" if (!defined($loaded));

my $dom = { 'id' => 1, 'dom' => 'example.com' };

{
	no warnings qw(once redefine);
	local %main::mysql_binlog_enabled_cache;
	local %main::mysql_source_data_support_cache;
	local %main::config = ( 'single_tx' => 1 );
	my $binlog = 'ON';
	my $binlog_calls = 0;
	my $help_calls = 0;
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::execute_dom_sql = sub {
		$binlog_calls++;
		return { 'data' => [ [ 'log_bin', $binlog ] ] };
		};
	local *main::backquote_command = sub {
		$help_calls++;
		return $_[0] =~ /^mysql-new / ?
			"  --source-data[=#]  Write source coordinates\n" :
			"  --master-data[=#]  Write source coordinates\n";
		};

	is(&get_mysql_binlog_coords_flag($dom, 'mysql-new'),
		'--source-data=2',
		'binlog enabled with a new dump client uses --source-data');
	is(&get_mysql_binlog_coords_flag($dom, 'mysql-old'),
		'--master-data=2',
		'an older dump client falls back to --master-data');
	is(&get_mysql_binlog_coords_flag($dom, 'mariadb-dump'),
		'--master-data=2',
		'a MariaDB dump client uses --master-data');
	is(&get_mysql_binlog_coords_flag($dom, undef),
		'--master-data=2',
		'a missing dump command safely falls back to --master-data');
	is($binlog_calls, 1, 'binary log state is checked only once per module');
	is($help_calls, 3, 'each configured dump command is checked only once');

	%main::mysql_binlog_enabled_cache = ( );
	$binlog = 'OFF';
	ok(!defined(&get_mysql_binlog_coords_flag($dom, 'mysql-new')),
		'coordinates are omitted when binary logging is disabled');

	%main::mysql_binlog_enabled_cache = ( );
	$binlog = 'ON';
	local $main::config{'single_tx'} = 0;
	ok(!defined(&get_mysql_binlog_coords_flag($dom, 'mysql-new')),
		'coordinates are omitted without a single-transaction dump');
	}

{
	no warnings qw(once redefine);
	local %main::mysql_binlog_enabled_cache;
	local %main::mysql_source_data_support_cache;
	local %main::config = (
		'gzip_mysql' => 0,
		'single_tx' => 1,
		);
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	local *main::require_mysql = sub { };
	local *main::get_template = sub { return { }; };
	local *main::substitute_domain_template = sub { return undef; };
	local *main::list_all_mysql_databases = sub { return ('appdb'); };
	local *main::unique = sub { return @_; };
	local *main::get_backup_db_excludes = sub { return ( ); };
	local *main::get_mysql_allowed_hosts = sub { return ( ); };
	local *main::get_domain_mysql_module = sub {
		return { 'config' => {
			'host' => 'localhost',
			'mysqldump' => 'mysql-new',
			} };
		};
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::execute_dom_sql = sub {
		return { 'data' => [ [ 'log_bin', 'ON' ] ] };
		};
	local *main::backquote_command = sub {
		return "  --source-data[=#]  Write source coordinates\n";
		};
	my @defined_calls;
	local *main::foreign_defined = sub {
		push(@defined_calls, [ @_ ]);
		return $_[1] eq 'get_character_set' ||
		       $_[1] eq 'get_collation_order';
		};
	my %written_info;
	local *main::write_as_domain_user = sub { $_[1]->(); };
	local *main::write_file = sub { %written_info = %{$_[1]}; };
	local *main::validate_mysql_backup = sub { return undef; };
	local *main::text = sub { return $_[0]; };
	my @foreign_calls;
	local *main::foreign_call = sub {
		push(@foreign_calls, [ @_ ]);
		return 'utf8mb4' if ($_[1] eq 'get_character_set');
		return 'utf8mb4_unicode_ci'
			if ($_[1] eq 'get_collation_order');
		return undef;
		};

	my $ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok($ok, 'mock MySQL backup succeeds');
	my ($backup_call) = grep { $_->[1] eq 'backup_database' }
				 @foreign_calls;
	is($backup_call->[1], 'backup_database',
		'Virtualmin calls the Webmin MySQL backup API');
	is($backup_call->[-1], '--source-data=2',
		'coordinates parameter is passed through to Webmin automatically');
	is_deeply([ map { $_->[0] } @defined_calls ], [ 'mysql', 'mysql' ],
		'backup metadata capability checks use the module name');
	is($written_info{'charset_appdb'}, 'utf8mb4',
		'database character set is recorded in backup metadata');
	is($written_info{'collate_appdb'}, 'utf8mb4_unicode_ci',
		'database collation is recorded in backup metadata');
	}

{
	# Verify options for the config-based backup schedule
	no warnings qw(once redefine);
	local %main::config = (
		'backup_dest' => '/tmp/legacy-backup',
		'backup_feature_dir' => 1,
		'backup_opts_dir' => 'include=public_html',
		);
	local $main::scheduled_backups_dir = tempdir(CLEANUP => 1);
	local *main::get_available_backup_features = sub { return ('dir'); };
	local *main::list_backup_plugins = sub { return ( ); };
	local *main::foreign_require = sub { };
	local *cron::list_cron_jobs = sub { return ( ); };
	local *webmincron::list_webmin_crons = sub { return ( ); };

	my ($sched) = grep { $_->{'id'} == 1 } &list_scheduled_backups();
	is($sched->{'backup_opts_dir'}, 'include=public_html',
		'the config-based schedule exposes feature options');

	# Verify options can be saved back to the module config
	local $main::module_config_file = '/tmp/unused-virtualmin-config';
	local $main::backup_cron_cmd = '/tmp/unused-virtualmin-backup';
	local $main::module_name = 'virtual-server';
	local *main::indexof = sub { return $_[0] eq $_[1] ? 0 : -1; };
	local *main::lock_file = sub { };
	local *main::save_module_config = sub { };
	local *main::unlock_file = sub { };
	local *main::find_cron_script = sub { return ( ); };
	local *cron::create_wrapper = sub { };
	&save_scheduled_backup({
		'id' => 1,
		'features' => 'dir',
		'backup_opts_dir' => 'exclude=tmp',
		'enabled' => 0,
		});
	is($main::config{'backup_opts_dir'}, 'exclude=tmp',
		'the config-based schedule saves feature options');
	}

{
	# Verify parsing of binary log coordinates from dump files
	my $dir = tempdir(CLEANUP => 1);
	my $dump = File::Spec->catfile($dir, 'dump.sql');
	open(my $fh, '>', $dump) || die $!;
	print $fh "-- MariaDB dump\n";
	print $fh "-- CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000042', ".
		  "MASTER_LOG_POS=1234;\n";
	print $fh "CREATE TABLE t (id int);\n";
	close($fh);
	my ($logfile, $logpos) = &get_mysql_dump_coordinates($dump);
	is($logfile, 'mysql-bin.000042', 'MariaDB dump coordinates file');
	is($logpos, 1234, 'MariaDB dump coordinates position');

	open($fh, '>', $dump) || die $!;
	print $fh "-- MySQL dump\n";
	print $fh "-- CHANGE REPLICATION SOURCE TO ".
		  "SOURCE_LOG_FILE='binlog.000007', SOURCE_LOG_POS=99;\n";
	close($fh);
	($logfile, $logpos) = &get_mysql_dump_coordinates($dump);
	is($logfile, 'binlog.000007', 'MySQL dump coordinates file');
	is($logpos, 99, 'MySQL dump coordinates position');

	open($fh, '>', $dump) || die $!;
	print $fh "-- Plain dump without coordinates\n";
	close($fh);
	ok(!defined(&get_mysql_dump_coordinates($dump)),
		'a dump without coordinates returns nothing');

	# Compressed dumps are read via gunzip
	no warnings qw(once redefine);
	local *main::get_gunzip_command = sub { return 'gunzip'; };
	my $gzdump = File::Spec->catfile($dir, 'dump2.sql.gz');
	open($fh, '|-', "gzip -c > ".quotemeta($gzdump)) || die $!;
	print $fh "-- CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000009', ".
		  "MASTER_LOG_POS=77;\n";
	close($fh);
	my ($gzfile, $gzpos) = &get_mysql_dump_coordinates($gzdump);
	is($gzfile, 'mysql-bin.000009', 'gzipped dump coordinates file');
	is($gzpos, 77, 'gzipped dump coordinates position');
	}

{
	# Verify binary log file selection from the server list
	no warnings qw(once redefine);
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::execute_dom_sql = sub {
		my ($d, $db, $sql) = @_;
		return $sql =~ /binary logs/ ?
			{ 'data' => [ [ 'mysql-bin.000001', 100 ],
				      [ 'mysql-bin.000002', 200 ],
				      [ 'mysql-bin.000003', 300 ] ] } :
			{ 'data' => [ [ 'log_bin_basename',
					'/var/lib/mysql/mysql-bin' ] ] };
		};
	local *main::text = sub { return join(' ', @_); };

	my ($files, $err) = &get_mysql_binlog_files({ }, 'mysql-bin.000002');
	is_deeply($files,
		[ '/var/lib/mysql/mysql-bin.000002',
		  '/var/lib/mysql/mysql-bin.000003' ],
		'binary logs are selected from the dump coordinates onwards');
	ok(!$err, 'no error selecting binary logs');

	($files, $err) = &get_mysql_binlog_files({ }, 'mysql-bin.000001',
						 'mysql-bin.000002');
	is_deeply($files,
		[ '/var/lib/mysql/mysql-bin.000001',
		  '/var/lib/mysql/mysql-bin.000002' ],
		'binary logs after the replay boundary are excluded');

	($files, $err) = &get_mysql_binlog_files({ }, 'mysql-bin.000001',
						 'mysql-bin.000099');
	ok(!$files && $err,
		'a missing replay boundary binary log is reported as an error');

	($files, $err) = &get_mysql_binlog_files({ }, 'mysql-bin.000099');
	ok(!$files && $err, 'a purged binary log file is reported as an error');
	}

{
	# Verify replay safety checks against the backup metadata
	no warnings qw(once redefine);
	my %vars = (
		'hostname' => 'db1.example.com',
		'server_uuid' => 'abc-123',
		'server_id' => 1,
		'binlog_format' => 'ROW',
		);
	local *main::get_domain_mysql_module = sub {
		return { 'config' => { 'host' => 'localhost' } };
		};
	local *main::require_dom_mysql = sub { return 'mysql'; };
	my $module_support = 1;
	my $module_local = 1;
	my (@defined_modules, @called_modules);
	local *main::foreign_defined = sub {
		push(@defined_modules, $_[0]);
		return $module_support;
		};
	local *main::foreign_call = sub {
		push(@called_modules, $_[0]);
		return $module_local if ($_[1] eq 'is_mysql_local');
		return $module_support;
		};
	local *main::execute_dom_sql = sub {
		my ($d, $db, $sql) = @_;
		my ($v) = $sql =~ /like '(\S+)'/;
		return { 'data' => defined($vars{$v}) ?
				[ [ $v, $vars{$v} ] ] : [ ] };
		};
	local *main::text = sub { return join(' ', @_); };
	local %main::text = (
		'restore_mysqlreplaynoid' => 'no identity recorded',
		'restore_mysqlreplayremote' => 'remote server',
		'restore_mysqlreplaymodule' => 'module lacks safe logging support',
		'restore_mysqlreplayowner' => 'owner login cannot disable logging',
		);
	my %goodinfo = (
		'binlog_hostname' => 'db1.example.com',
		'binlog_server_uuid' => 'abc-123',
		'binlog_server_id' => 1,
		'binlog_format' => 'ROW',
		);

	ok(!defined(&check_mysql_replay_safety({ }, { %goodinfo })),
		'replay is allowed for a matching row-format backup');
	is($defined_modules[-1], 'mysql',
		'replay support detection uses the module name');
	is($called_modules[-1], 'mysql',
		'replay support invocation uses the module name');
	is(&check_mysql_replay_safety({ }, { %goodinfo }, 1),
		'owner login cannot disable logging',
		'replay is refused when restoring as the domain owner');
	$module_local = 0;
	is(&check_mysql_replay_safety({ }, { %goodinfo }),
		'remote server',
		'replay is refused when the module considers MySQL remote');
	$module_local = 1;
	$module_support = 0;
	is(&check_mysql_replay_safety({ }, { %goodinfo }),
		'module lacks safe logging support',
		'replay is refused without safe session logging support');
	$module_support = 1;
	ok(&check_mysql_replay_safety({ }, { }),
		'replay is refused for a backup without server identity');
	ok(&check_mysql_replay_safety({ }, { %goodinfo,
		'binlog_hostname' => 'other.example.com' }),
		'replay is refused for a backup from another server');
	ok(&check_mysql_replay_safety({ }, { %goodinfo,
		'binlog_format' => 'MIXED' }),
		'replay is refused for a backup taken with mixed logging');
	local $vars{'binlog_format'} = 'STATEMENT';
	ok(&check_mysql_replay_safety({ }, { %goodinfo }),
		'replay is refused when the current format is not row-based');
	}

done_testing();
