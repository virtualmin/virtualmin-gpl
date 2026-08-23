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

{
	no warnings qw(once redefine);
	local %main::mysql_source_data_support_cache;
	local %main::config = ( 'mysql_source_data' => 0 );
	my $help_calls = 0;
	local *main::backquote_command = sub {
		$help_calls++;
		return $_[0] =~ /^mysql-new / ?
			"  --source-data[=#]  Write source coordinates\n" :
			"  --master-data[=#]  Write source coordinates\n";
		};

	is(&get_mysql_backup_parameters({ 'source_data' => 2 }, 'mysql-new'),
		'--source-data=2',
		'a dump client advertising --source-data uses the new option name');
	is(&get_mysql_backup_parameters({ 'source_data' => 2 }, 'mysql-old'),
		'--master-data=2',
		'an older dump client falls back to --master-data');
	is(&get_mysql_backup_parameters({ 'source_data' => 2 }, 'mariadb-dump'),
		'--master-data=2',
		'a MariaDB dump client uses --master-data');
	is(&get_mysql_backup_parameters({ 'source_data' => 2 }, undef),
		'--master-data=2',
		'a missing dump command safely falls back to --master-data');
	is(&get_mysql_backup_parameters({ 'source_data' => 2 }, 'mysql-new'),
		'--source-data=2', 'dump client capability checks are cached');
	is($help_calls, 3, 'each configured dump command is checked only once');
	ok(!defined(&get_mysql_backup_parameters({ }, 'mysql-new')),
		'a disabled global default omits MySQL source coordinates');
	$main::config{'mysql_source_data'} = 1;
	is(&get_mysql_backup_parameters({ }, 'mysql-new'), '--source-data=2',
		'an enabled global default includes MySQL source coordinates');
	is(&get_mysql_backup_parameters(undef, 'mysql-new'), '--source-data=2',
		'a backup without feature options inherits the global default');
	ok(!defined(&get_mysql_backup_parameters({ 'source_data' => 0 },
		'mysql-new')), 'an explicit backup option overrides the default off');
	ok(!defined(&get_mysql_backup_parameters({
		'source_data' => '2; touch /tmp/untrusted',
		}, 'mysql-new')), 'arbitrary MySQL backup parameters are rejected');
	}

{
	no warnings qw(once redefine);
	local %main::mysql_source_data_support_cache;
	local %main::config = (
		'gzip_mysql' => 0,
		'mysql_source_data' => 1,
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
	local *main::backquote_command = sub {
		return "  --source-data[=#]  Write source coordinates\n";
		};
	local *main::foreign_defined = sub { return 0; };
	local *main::write_as_domain_user = sub { };
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::mysql_single_transaction = sub { return 1; };
	local *main::validate_mysql_backup = sub { return undef; };
	local *main::text = sub { return $_[0]; };
	my @backup_call;
	local *main::foreign_call = sub {
		@backup_call = @_;
		return undef;
		};

	my $ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok($ok, 'mock MySQL backup succeeds');
	is($backup_call[1], 'backup_database',
		'Virtualmin calls the Webmin MySQL backup API');
	is($backup_call[-1], '--source-data=2',
		'the global default is passed through to Webmin');
	}

{
	# Verify the option keys used by both backup and restore paths
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
		'the legacy schedule exposes options to the backup path');
	is($sched->{'opts_dir'}, 'include=public_html',
		'the legacy schedule preserves options for the restore path');

	# Verify that older callers can still save the legacy option key
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
		'opts_dir' => 'exclude=tmp',
		'enabled' => 0,
		});
	is($main::config{'backup_opts_dir'}, 'exclude=tmp',
		'the legacy restore key remains accepted when saving');
	}

done_testing();
