#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Handle;
use Errno qw(EACCES EIO);
use Cwd qw(abs_path);
use version;

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
	# Binary row bytes and Unicode schema literals need separate connections.
	no warnings qw(once redefine);
	my $dir = tempdir(CLEANUP => 1);
	my $file = "$dir/binary.sql";
	my $temp = "$file.webmintmp";
	my ($open_error, $close_error, $replace_error, $temp_mode);
	# open_readfile(handle, file) opens fixture input without Webmin startup.
	local *main::open_readfile = sub { return open($_[0], '<', $_[1]); };
	# open_tempfile([handle], file, [no-error], [no-tempfile])
	# Supply a staging path or open it, with controllable open failures.
	local *main::open_tempfile = sub {
		return $temp if (@_ == 1);
		my ($fh, $path) = @_;
		$path =~ s/^>//;
		if ($open_error) {
			# Refuse writing without opening or truncating the original dump.
			$! = EACCES;
			return 0;
			}
		my $ok = open($fh, '>', $path);
		$temp_mode = (stat($path))[2] & 0777 if ($ok);
		return $ok;
		};
	# close_tempfile(handle|file) closes output or commits the validated dump.
	local *main::close_tempfile = sub {
		my ($target) = @_;
		if (ref($target)) {
			# Simulate a close failure after releasing the handle.
			my $ok = close($target);
			if ($close_error) { $! = EIO; return 0; }
			return $ok;
			}
		# Simulate a failed commit that leaves the original untouched.
		if ($replace_error) { $! = EACCES; return 0; }
		my @st = stat($target);
		rename($temp, $target) || return 0;
		return chmod($st[2] & 0777, $target);
		};
	local *main::unlink_file = sub { return unlink($_[0]); };
	my $data = "INSERT INTO t VALUES ('".pack('C*', 0xC5, 0xEB)."');\n";
	my $dump = "/*!40101 SET NAMES binary */;\n".
		"/*!50503 SET character_set_client = utf8mb4 */;\n".
		"/*!50001 CREATE VIEW v AS SELECT 1 AS g */;\n".
		"SET character_set_client = \@saved_cs_client;\n".
		"/*!40101 SET character_set_client = utf8mb4 */;\n".
		"CREATE TABLE t (g VARCHAR(10) CHARACTER SET greek DEFAULT 'test');\n".
		"/*!40101 SET character_set_client = \@saved_cs_client */;\n".$data;
	open(my $fh, '>', $file) || die $!;
	print $fh $dump;
	close($fh);
	chmod(0640, $file) || die $!;
	is(&prepare_mysql_binary_dump($file), undef, 'binary dump schema is prepared');
	open($fh, '<', $file) || die $!;
	my $fixed = do { local $/; <$fh> };
	close($fh);
	like($fixed, qr/SET character_set_connection = utf8mb4.*CREATE TABLE/s,
		'schema statements use the Unicode connection charset');
	like($fixed, qr/SET collation_connection = \@virtualmin_saved_collation.*\Q$data\E/s,
		'row bytes are unchanged and follow restoration of the binary connection');
	is((stat($file))[2] & 0777, 0640, 'dump permissions are preserved');
	is($temp_mode, 0600, 'temporary output is private from creation');
	ok(!-e $temp, 'successful rewrite leaves no temporary file');
	is(scalar(() = $fixed =~ /SET collation_connection = \@virtualmin_saved_collation/g),
		2, 'both the MySQL placeholder view and table restore the connection');
	# API failures must return an error, clean up and preserve the source.
	foreach my $failure (\$open_error, \$close_error, \$replace_error) {
		open($fh, '>', $file) || die $!;
		print $fh $dump;
		close($fh);
		$$failure = 1;
		ok(&prepare_mysql_binary_dump($file), 'a file API failure is returned');
		$$failure = 0;
		open($fh, '<', $file) || die $!;
		is(do { local $/; <$fh> }, $dump, 'API failure preserves the original dump');
		close($fh);
		ok(!-e $temp, 'API failure leaves no temporary output');
		}
	# An incomplete schema block must fail without replacing the original.
	$dump =~ s{/\*!40101 SET character_set_client = \@saved_cs_client \*/;\n}{};
	open($fh, '>', $file) || die $!;
	print $fh $dump;
	close($fh);
	ok(&prepare_mysql_binary_dump($file), 'incomplete charset statements are rejected');
	open($fh, '<', $file) || die $!;
	my $unchanged = do { local $/; <$fh> };
	close($fh);
	is($unchanged, $dump, 'rejected dump remains unchanged');
	ok(!-e $temp, 'rejected dump leaves no partial temporary file');
	# Opening errors are returned, and a colliding file must stay untouched.
	like(&prepare_mysql_binary_dump("$dir/missing.sql"), qr/^Cannot read /,
		'a missing input returns an error');
	open($fh, '>', $temp) || die $!;
	print $fh 'existing file';
	close($fh);
	like(&prepare_mysql_binary_dump($file), qr/^Cannot write /,
		'a temporary path collision returns an error');
	open($fh, '<', $temp) || die $!;
	is(do { local $/; <$fh> }, 'existing file', 'colliding file is preserved');
	close($fh);
}

# compare_versions(version, other-version)
# Compare fixture versions without loading the Webmin runtime.
sub compare_versions
{
return version->parse('v'.$_[0]) <=> version->parse('v'.$_[1]);
}

{
	# Check charset selection, table filters and errors without a DB.
	no warnings qw(once redefine);
	my ($rows, $query_error, $support_error);
	my $supports_mb4 = 1;
	my @queries;
	# execute_dom_sql(&domain, db, sql, [bind-values...])
	# Records queries and returns fixture metadata or a controlled error.
	local *main::execute_dom_sql = sub {
		push(@queries, [ @_ ]);
		if ($_[2] =~ /information_schema.COLUMNS/) {
			# Simulate column metadata or a failure to read it.
			die "$query_error\n" if ($query_error);
			return { 'data' => $rows };
			}
		# Simulate charset support or a failure to query it.
		die "$support_error\n" if ($support_error);
		return { 'data' => $supports_mb4 ? [ [ 'utf8mb4' ] ] : [ ] };
		};
	# text(key, [values...])
	# Returns untranslated error keys and parameters for assertions.
	local *main::text = sub { return join(': ', @_); };
	# Keep a single client charset unchanged, including legacy ones.
	foreach my $cs (qw(ascii latin1 latin2 greek utf8 utf8mb3 utf8mb4 cp932 armscii8)) {
		$rows = [ [ 't', $cs, 'varchar' ] ];
		is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
			[ $cs, undef ], "columns using only $cs keep that dump charset");
		}
	# Supported mixtures and charsets unusable by clients require Unicode.
	foreach my $charsets ([qw(latin1 utf8mb4)], [qw(latin1 latin2 utf8mb3)],
			      [qw(utf8 utf8mb3)], [qw(ucs2)], [qw(utf16 utf16le utf32)]) {
		$rows = [ map { [ 't', $_, 'varchar' ] } @$charsets ];
		is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
			[ 'utf8mb4', undef ], "@{$charsets} use a Unicode client charset");
		}
	# Use a binary connection for mixtures that may lose bytes through Unicode.
	foreach my $charsets ([qw(greek utf8 utf8mb4)], [qw(greek latin1)],
			      [qw(greek utf16)], [qw(greek utf8mb3)],
			      [qw(cp932 utf8mb4)], [qw(armscii8 latin1)],
			      [qw(greek cp932 utf8mb4)], [qw(cp1251 utf8mb4)]) {
		$rows = [ map { [ 't', $_, 'varchar' ] } @$charsets ];
		is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
			[ 'binary', undef ], "@{$charsets} preserve their original bytes");
		}
	# JSON needs Unicode even when the server reports no column charset.
	$rows = [ [ 't', undef, 'json' ], [ 't', 'latin1', 'varchar' ] ];
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
		[ 'utf8mb4', undef ], 'JSON requires Unicode even without charset metadata');
	# Without text columns, use the supported Unicode charset.
	$rows = [ [ 't', undef, 'int' ], [ 't', undef, 'blob' ] ];
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
		[ 'utf8mb4', undef ], 'numeric and binary columns need no native text charset');
	$rows = [ ];
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
		[ 'utf8mb4', undef ], 'empty databases select utf8mb4');

	# Native JSON prevents the binary fallback for legacy charset mixtures.
	foreach my $legacy (qw(greek cp932 armscii8)) {
		$rows = [ [ 'legacy', $legacy, 'varchar' ], [ 'json', undef, 'json' ] ];
		my ($cs, $err) = &get_mysql_backup_charset($dom, 'appdb');
		ok(!defined($cs) && $err, "$legacy with native JSON is rejected");
		like($err, qr/\Q$legacy\E/, 'error identifies the affected charsets');
		}
	# Honor table exclusions and bind database names as SQL values.
	$rows = [ [ 'keep', 'cp932', 'varchar' ], [ 'omit', 'utf8mb4', 'varchar' ] ];
	@queries = ( );
	is_deeply([ &get_mysql_backup_charset($dom, "a'b", [ 'keep' ]) ],
		[ 'cp932', undef ], 'excluded tables do not affect charset selection');
	is($queries[0]->[0], $dom, 'metadata query uses the source domain connection');
	is($queries[0]->[3], "a'b", 'database name is passed as a SQL parameter');
	unlike($queries[0]->[2], qr/a'b/, 'database name is not interpolated into SQL');
	like($queries[0]->[2], qr/TABLE_TYPE <> 'VIEW'/, 'view columns do not affect dumped rows');
	# An empty table list selects all tables in the existing dump API.
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb', [ ]) ],
		[ 'binary', undef ], 'an empty table list includes both charsets');
	# Excluded JSON columns must not prevent a binary dump of remaining tables.
	push(@$rows, [ 'json', undef, 'json' ]);
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb', [ 'keep', 'omit' ]) ],
		[ 'binary', undef ], 'excluded JSON does not prevent binary fallback');

	# Use utf8 when the server lacks utf8mb4 support.
	$supports_mb4 = 0;
	$rows = [ [ 't', 'latin1', 'varchar' ], [ 't', 'utf8', 'varchar' ] ];
	is_deeply([ &get_mysql_backup_charset($dom, 'appdb') ],
		[ 'utf8', undef ], 'older servers use their supported Unicode charset');
	# A query failure must return an error instead of selecting a charset.
	$support_error = 'Cannot read supported charsets';
	my ($cs, $err) = &get_mysql_backup_charset($dom, 'appdb');
	ok(!defined($cs) && $err =~ /Cannot read supported charsets/,
		'capability query errors prevent dumping');
	$query_error = 'Cannot read column charsets';
	($cs, $err) = &get_mysql_backup_charset($dom, 'appdb');
	ok(!defined($cs) && $err =~ /Cannot read column charsets/,
		'metadata query errors prevent dumping');
	}

{
	no warnings qw(once redefine);
	local %main::mysql_binlog_enabled_cache;
	local %main::mysql_source_data_support_cache;
	local %main::mysql_binary_log_status_support_cache;
	local %main::config = ( 'single_tx' => 1 );
	my $binlog = 'ON';
	my $binlog_calls = 0;
	my $help_calls = 0;
	my ($server_version, $variant, $version_error) = ('8.4.0', 'mysql');
	# get_dom_remote_mysql_version(&domain)
	# Supply the connected server's version independently of the client.
	local *main::get_dom_remote_mysql_version = sub {
		return ($server_version, $variant, $version_error);
		};
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::execute_dom_sql = sub {
		$binlog_calls++;
		return { 'data' => [ [ 'log_bin', $binlog ] ] };
		};
	local *main::backquote_command = sub {
		$help_calls++;
		# Real banner formats distinguish the distribution and tool versions.
		return "mysqldump  Ver 8.4.0 for Linux on aarch64\n".
			"  --source-data[=#]  Write source coordinates\n"
			if ($_[0] =~ /^mysql-new /);
		return "mysqldump  Ver 10.13 Distrib 5.7.44, for Linux\n".
			"  --master-data[=#]  Write source coordinates\n"
			if ($_[0] =~ /^mysql-old /);
		return "mysqldump  Ver 10.17 Distrib 10.3.39-MariaDB, for Linux\n".
			"  --master-data[=#]  Write source coordinates\n"
			if ($_[0] =~ /^mariadb-dump /);
		# MySQL 8.0 and 8.1 advertise --source-data but use the old SQL.
		return "mysqldump  Ver 10.13 Distrib $1, for Linux\n".
			"  --source-data[=#]  Write source coordinates\n"
			if ($_[0] =~ /^mysql-(8\.0\.36|8\.1\.0) /);
		return "mysqldump  Ver $1 for Linux on aarch64\n".
			"  --source-data[=#]  Write source coordinates\n"
			if ($_[0] =~ /^mysql-(8\.2\.0|9\.0\.0) /);
		# A wrapper may expose flags without identifying its client version.
		return "  --source-data[=#]  Write source coordinates\n";
		};

	is(&get_mysql_binlog_coords_flag($dom, 'mysql-new'),
		'--source-data=2',
		'binlog enabled with a new dump client uses --source-data');
	$server_version = '8.0.36';
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

	# Reuse cached clients against MySQL 8.4, which rejects the old SQL.
	$server_version = '8.4.0';
	foreach my $client ('mariadb-dump', 'mysql-old', 'mysql-8.0.36',
			   'mysql-8.1.0', 'unknown-client', undef) {
		ok(!defined(&get_mysql_binlog_coords_flag($dom, $client)),
			($client || 'missing client').
			' omits incompatible coordinates on MySQL 8.4');
		}
	# The replacement SQL is supported starting with the MySQL 8.2 client.
	foreach my $client ('mysql-8.2.0', 'mysql-new', 'mysql-9.0.0') {
		is(&get_mysql_binlog_coords_flag($dom, $client),
			'--source-data=2', "$client retains coordinates on MySQL 8.4");
		}
	# Do not cache a server-specific decision under the shared client path.
	($server_version, $variant) = ('10.3.39', 'mariadb');
	is(&get_mysql_binlog_coords_flag($dom, 'mariadb-dump'),
		'--master-data=2', 'MariaDB server retains coordinates with its client');
	($server_version, $variant) = ('8.3.0', 'mysql');
	is(&get_mysql_binlog_coords_flag($dom, 'mariadb-dump'),
		'--master-data=2', 'MySQL before 8.4 retains the legacy statement');
	$server_version = '9.0.0';
	ok(!defined(&get_mysql_binlog_coords_flag($dom, 'mariadb-dump')),
		'later MySQL servers also omit incompatible coordinates');
	# A failed server lookup must not use a fallback local client version.
	($server_version, $variant, $version_error) =
		('10.3.39', 'mariadb', 'Cannot read server version');
	ok(!defined(&get_mysql_binlog_coords_flag($dom, 'mariadb-dump')),
		'unknown server compatibility omits optional coordinates');
	($server_version, $variant, $version_error) = ('8.4.0', 'mysql', undef);
	is($help_calls, 8, 'client probes are reused across different servers');

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
	local %main::mysql_binary_log_status_support_cache;
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
	my $dumpcmd = 'mysql-new';
	local *main::get_domain_mysql_module = sub {
		return { 'config' => {
			'host' => 'localhost',
			'mysqldump' => $dumpcmd,
			} };
		};
	local *main::require_dom_mysql = sub { return 'mysql'; };
	local *main::get_dom_remote_mysql_version = sub { return ('8.4.0', 'mysql'); };
	my $column_rows = [ [ 'posts', 'utf8mb4', 'varchar' ] ];
	# execute_dom_sql(&domain, db, sql, [bind-values...])
	# Supplies column metadata while retaining the binary log fixture.
	local *main::execute_dom_sql = sub {
		# Return column charsets independently of DB defaults.
		return { 'data' => $column_rows }
			if ($_[2] =~ /information_schema.COLUMNS/);
		# Keep binary log coordinates enabled for backup checks.
		return { 'data' => [ [ 'log_bin', 'ON' ] ] };
		};
	local *main::backquote_command = sub {
		# Exercise both clients against the same MySQL 8.4 server.
		return $dumpcmd eq 'mysql-new' ?
			"mysqldump  Ver 8.4.0 for Linux\n  --source-data[=#]\n" :
			"mysqldump  Ver 10.17 Distrib 10.3.39-MariaDB\n  --master-data[=#]\n";
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
	my ($prepared, $prepare_error) = (0, undef);
	local *main::prepare_mysql_binary_dump = sub { $prepared++; return $prepare_error; };
	local *main::text = sub { return $_[0]; };
	my @foreign_calls;
	# foreign_call(module, function, [args...])
	# Records calls and supplies database defaults for restore metadata.
	local *main::foreign_call = sub {
		push(@foreign_calls, [ @_ ]);
		# The database default differs from the Unicode column charset.
		return 'latin1' if ($_[1] eq 'get_character_set');
		# Supply the collation matching the saved database charset.
		return 'latin1_swedish_ci'
			if ($_[1] eq 'get_collation_order');
		# A successful dump returns no error.
		return undef;
		};

	# Dump the Unicode columns in utf8mb4 while retaining the database's
	# latin1 charset and collation in the metadata used for restore.
	my $ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok($ok, 'mock MySQL backup succeeds');
	my ($backup_call) = grep { $_->[1] eq 'backup_database' }
				 @foreign_calls;
	is($backup_call->[1], 'backup_database',
		'Virtualmin calls the Webmin MySQL backup API');
	is($backup_call->[7], 'utf8mb4',
		'dump uses utf8mb4 despite a latin1 database default');
	is($backup_call->[-1], '--source-data=2',
		'coordinates parameter is passed through to Webmin automatically');
	is_deeply([ map { $_->[0] } @defined_calls ], [ 'mysql', 'mysql' ],
		'backup metadata capability checks use the module name');
	is($written_info{'charset_appdb'}, 'latin1',
		'database character set is recorded in backup metadata');
	is($written_info{'collate_appdb'}, 'latin1_swedish_ci',
		'database collation is recorded in backup metadata');

	# An incompatible client still makes a normal single-transaction dump.
	$dumpcmd = 'mariadb-dump';
	@foreign_calls = ( );
	$ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok($ok, 'MariaDB client backup proceeds on MySQL 8.4');
	($backup_call) = grep { $_->[1] eq 'backup_database' } @foreign_calls;
	ok($backup_call && !defined($backup_call->[-1]),
		'backup omits incompatible coordinate flags');
	is($backup_call->[11], 1, 'backup preserves the single-transaction option');
	ok(!grep(/^binlog_/, keys %written_info),
		'backup records no replay identity when coordinates are omitted');

	# Mixed legacy columns must reach Webmin with the binary dump charset.
	$column_rows = [ [ 'legacy', 'cp932', 'varchar' ],
			 [ 'posts', 'utf8mb4', 'varchar' ] ];
	@foreign_calls = ( );
	$ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok($ok, 'mixed legacy charsets can be backed up');
	($backup_call) = grep { $_->[1] eq 'backup_database' } @foreign_calls;
	is($backup_call->[7], 'binary', 'Webmin receives the binary dump charset');
	is($prepared, 1, 'binary backup schema is prepared before validation');
	# A failed rewrite must not produce a successful backup result.
	$prepare_error = 'Cannot write adjusted dump';
	$ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok(!$ok, 'a schema rewrite failure fails the backup');
	$prepare_error = undef;

	# A rejected JSON mixture must not invoke the dump program.
	push(@$column_rows, [ 'documents', undef, 'json' ]);
	@foreign_calls = ( );
	$ok = &backup_mysql(
		{ 'template' => 1, 'db_mysql' => 'appdb', 'user' => 'example' },
		'/tmp/mysql-backup-options-test', { },
		0, 0, undef, { 'dir' => { 'compression' => 0 }, 'skip' => 0 });
	ok(!$ok, 'unsafe charset mixture fails the backup');
	ok(!grep($_->[1] eq 'backup_database', @foreign_calls),
		'unsafe charset mixture never reaches the dump API');
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
