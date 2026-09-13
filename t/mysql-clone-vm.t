#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempfile);
use Cwd qw(abs_path);

my $test_script = abs_path(__FILE__);

# Opt in before loading Webmin or reading service configuration.
plan skip_all => 'Set VIRTUALMIN_MYSQL_CLONE_VM_TEST=1 on a disposable Virtualmin MySQL VM'
	unless ($ENV{'VIRTUALMIN_MYSQL_CLONE_VM_TEST'} || '') eq '1';
plan skip_all => 'Requires root on a disposable Linux VM'
	unless $^O eq 'linux' && $< == 0 && $> == 0;
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
die 'Cannot find the Webmin installation' unless $root;
my $module = "$root/virtual-server";
chdir($module) or die $!;
$0 = "$module/mysql-clone-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
plan skip_all => 'Requires the local MySQL feature'
	unless $virtual_server::config{'mysql'} &&
	virtual_server::get_default_mysql_module() eq 'mysql';
virtual_server::require_mysql();
plan skip_all => 'Requires a database on this VM'
	unless ($mysql::config{'host'} || '') =~ /^(localhost|127\.0\.0\.1|::1)?$/;
foreach my $command (qw(timeout)) {
	die "Required command not found: $command" unless has_command($command);
	}
local $main::error_must_die = 1;
virtual_server::set_all_null_print();
note("Testing installed Virtualmin in $module");

# The restore fault is limited to this child process and the target fixture.
# Corrupt a real dump just before the real MySQL importer reads it.
if (@ARGV && $ARGV[0] eq '--restore-failure') {
	Test::More->builder()->no_ending(1);
	shift(@ARGV);
	my ($source, $target, $user) = @ARGV;
	die 'Invalid restore fixture' unless $source =~ /^mysql-clone-myc[a-z0-9]+\.invalid$/ &&
		$target =~ /^mysql-clone-myc[a-z0-9]+\.invalid$/ && $user =~ /^myc[a-z0-9]+$/;
	my $restore = \&virtual_server::execute_dom_sql_file;
	my $corrupted = 0;
	no warnings 'redefine';
	local *virtual_server::execute_dom_sql_file = sub {
		my ($d, $db, $file) = @_;
		if ($d->{'dom'} eq $target && $db eq $d->{'db'}) {
			open(my $dump, '>>', $file) or die $!;
			print $dump "\nINVALID CLONE FIXTURE SQL;\n" or die $!;
			close($dump) or die $!;
			$corrupted++;
			print "Corrupted primary clone dump\n";
			}
		return $restore->(@_);
		};
	@ARGV = ('--domain', $source, '--newdomain', $target, '--newuser', $user);
	{ package virtual_server; do "$module/clone-domain.pl"; }
	die $@ if $@;
	die 'Restore fault was not exercised' unless $corrupted;
	exit(0);
	}

# Fixture credentials stay on the VM, outside process arguments and TAP.
my ($passfh, $passfile) = tempfile('mysql-clone-pass-XXXXXX',
	DIR => '/tmp', UNLINK => 1);
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
print $passfh unpack('H*', $bytes) or die $!;
close($passfh) or die $!;
my $tag = sprintf('%x%04x', $$, int(rand(65536)));
my @users = map { "myc${_}$tag" } qw(s e d f b r);
my @names = map { "mysql-clone-$_.invalid" } @users;
my (%attempted, %dbusers, %databases);
my $collision;
foreach my $i (0 .. $#names) {
	die "Fixture domain already exists: $names[$i]"
		if virtual_server::get_domain_by('dom', $names[$i]);
	die "Fixture account already exists: $users[$i]" if getpwnam($users[$i]);
	}

# Always clean up after a failed assertion or setup command.
{
	local $SIG{'ALRM'} = sub { die "MySQL clone tests timed out\n"; };
	local $SIG{'INT'} = sub { die "MySQL clone tests interrupted\n"; };
	alarm(900);
	my $completed = eval { run_tests(); 1; };
	my $error = $@;
	alarm(0);
	if (!$completed) {
		fail('MySQL clone integration completed');
		diag($error);
		}
	}
cleanup();
done_testing();

# Test empty and populated clones, then database name, dump and import failures.
sub run_tests
{
$attempted{$names[0]} = 1;
cli('create-domain', '--domain', $names[0], '--user', $users[0],
	'--passfile', $passfile, '--unix', '--dir', '--mysql', '--no-ip6',
	'--limits-from-plan', '--no-email', '--no-slaves', '--no-secondaries');
my $source = domain($names[0]);
foreach my $db (virtual_server::domain_databases($source, [ 'mysql' ])) {
	cli('delete-database', '--domain', $names[0], '--type', 'mysql',
		'--name', $db->{'name'});
	}
$source = domain($names[0]);
ok($source->{'mysql'}, 'source still has MySQL enabled');
is(scalar(virtual_server::domain_databases($source, [ 'mysql' ])), 0,
	'source has no MySQL databases');

$attempted{$names[1]} = 1;
my ($status, $output) = run_command($^X, "$module/clone-domain.pl",
	'--domain', $names[0], '--newdomain', $names[1], '--newuser', $users[1]);
is($status, 0, 'cloning without databases exits successfully') or diag($output);
my $empty = domain($names[1]);
ok($empty->{'mysql'}, 'empty clone retains MySQL support');
is(scalar(virtual_server::domain_databases($empty, [ 'mysql' ])), 0,
	'empty clone has no MySQL databases');

# Populate a real database and give its owner an additional allowed host.
cli('create-database', '--domain', $names[0], '--type', 'mysql',
	'--name', $source->{'db'});
$source = domain($names[0]);
my @dbs = virtual_server::domain_databases($source, [ 'mysql' ]);
die 'Expected one source database' unless @dbs == 1;
seed_database($dbs[0]->{'name'});
my @hosts = virtual_server::unique(virtual_server::get_mysql_allowed_hosts($source), '192.0.2.123');
my $host_error = virtual_server::save_mysql_allowed_hosts($source, \@hosts);
die $host_error if defined($host_error);
$attempted{$names[2]} = 1;
cli('clone-domain', '--domain', $names[0], '--newdomain', $names[2],
	'--newuser', $users[2]);
my $target = domain($names[2]);
my @copied = virtual_server::domain_databases($target, [ 'mysql' ]);
is(scalar(@copied), 1, 'normal clone contains one database');
die 'Missing cloned database' unless @copied == 1;
is(sql($copied[0]->{'name'}, 'SELECT value FROM clone_probe'),
	'mysql-clone-data-ok', 'normal clone preserves table data');

is_deeply([ sort(virtual_server::get_mysql_allowed_hosts($target)) ],
	[ sort(@hosts) ], 'normal clone preserves allowed hosts');

# Reserve only the secondary target database name. Domain creation and the
# primary database copy can succeed before clone_mysql reports the clash.
my $extra = virtual_server::fix_database_name($source->{'prefix'}, 'mysql').'_extra';
cli('create-database', '--domain', $names[0], '--type', 'mysql', '--name', $extra);
seed_database($extra);
my $prefix = virtual_server::compute_prefix($names[3], $users[3], undef, 1);
my $reserved = virtual_server::fix_database_name($prefix, 'mysql').'_extra';
sql('mysql', 'CREATE DATABASE '.identifier($reserved));
$collision = $reserved;
$attempted{$names[3]} = 1;
($status, $output) = run_command($^X, "$module/clone-domain.pl",
	'--domain', $names[0], '--newdomain', $names[3], '--newuser', $users[3]);
is($status, 1 << 8, 'partial database clone exits with failure') or diag($output);
like($output, qr/\Q$reserved\E already exists/, 'failure comes from the database clash');
my $partial = domain($names[3]);
my @partial = virtual_server::domain_databases($partial, [ 'mysql' ]);
is(scalar(@partial), 1, 'partial clone retains the successfully copied database');
die 'Missing partially cloned database' unless @partial == 1;
is(sql($partial[0]->{'name'}, 'SELECT value FROM clone_probe'),
	'mysql-clone-data-ok', 'partial failure does not discard copied data');

# A view whose base table is missing makes the actual dump command fail.
sql($dbs[0]->{'name'}, 'CREATE TABLE clone_view_base (value int)');
sql($dbs[0]->{'name'}, 'CREATE VIEW clone_bad_view AS SELECT value FROM clone_view_base');
sql($dbs[0]->{'name'}, 'DROP TABLE clone_view_base');
$attempted{$names[4]} = 1;
($status, $output) = run_command($^X, "$module/clone-domain.pl",
	'--domain', $names[0], '--newdomain', $names[4], '--newuser', $users[4]);
is($status, 1 << 8, 'dump failure reaches the CLI exit status') or diag($output);
like($output, qr/backup of \Q$dbs[0]->{'name'}\E failed/, 'failure comes from the real dump');
sql($dbs[0]->{'name'}, 'DROP VIEW clone_bad_view');
check_later_database($names[4]);

# Import a deliberately corrupted dump while leaving database services intact.
$attempted{$names[5]} = 1;
($status, $output) = run_command($^X, $test_script, '--restore-failure',
	$names[0], $names[5], $users[5]);
is($status, 1 << 8, 'restore failure reaches the CLI exit status') or diag($output);
like($output, qr/Corrupted primary clone dump/, 'corrupts the intended dump');
like($output, qr/restore into .* failed : .*ERROR 1064/, 'real importer rejects the invalid SQL');
check_later_database($names[5]);
}

# Run commands without stdin or unbounded waits; passwords never enter arguments.
sub run_command
{
my $command = join(' ', map { quote_path($_) }
	('timeout', '--kill-after=10s', '180s', @_));
my $output = backquote_command("$command </dev/null 2>&1");
return ($?, $output);
}

sub cli
{
my ($command, @args) = @_;
my ($status, $output) = run_command($^X, "$module/$command.pl", @args);
die "$command failed (status $status):\n$output" if $status;
}

# Only generated fixture identifiers are interpolated into SQL.
sub identifier
{
my ($name) = @_;
die "Unexpected fixture identifier" unless $name =~ /^[a-z0-9_]+$/;
return '`'.$name.'`';
}

# Use the VM's configured database login without putting credentials in argv.
sub sql
{
my ($db, $query, @params) = @_;
my $rv = virtual_server::execute_dom_sql(undef, $db, $query, @params);
my $data = $rv->{'data'} || [];
return @$data ? $data->[0]->[0] : '';
}

sub seed_database
{
my ($db) = @_;
sql($db, 'CREATE TABLE clone_probe (value text)');
sql($db, "INSERT INTO clone_probe VALUES ('mysql-clone-data-ok')");
}

# A later successful copy must not hide the first database's failure.
sub check_later_database
{
my ($name) = @_;
my $d = domain($name);
my @dbs = virtual_server::domain_databases($d, [ 'mysql' ]);
is(scalar(@dbs), 2, 'both target databases were created');
my ($extra) = grep { $_->{'name'} =~ /_extra$/ } @dbs;
die 'Missing secondary clone database' unless $extra;
is(sql($extra->{'name'}, 'SELECT value FROM clone_probe'),
	'mysql-clone-data-ok', 'later database still copies successfully');
}

# CLI subprocesses change domain records behind Webmin's map caches.
sub refresh_caches
{
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
}

sub domain
{
my ($name) = @_;
refresh_caches();
my $d = virtual_server::get_domain_by('dom', $name) || die "Missing domain $name";
$dbusers{virtual_server::mysql_user($d)} = 1;
$databases{$_->{'name'}} = 1 foreach virtual_server::domain_databases($d, [ 'mysql' ]);
return $d;
}

# Delete through Virtualmin, then verify Unix accounts, database users and DBs.
sub cleanup
{
unlock_all_files();
foreach my $i (reverse(0 .. $#names)) {
	next unless $attempted{$names[$i]};
	refresh_caches();
	if (virtual_server::get_domain_by('dom', $names[$i])) {
		domain($names[$i]);
		my ($status, $output) = run_command($^X, "$module/delete-domain.pl",
			'--domain', $names[$i]);
		is($status, 0, "deletes $names[$i]") or diag($output);
		}
	refresh_caches();
	ok(!virtual_server::get_domain_by('dom', $names[$i]), "$names[$i] is removed");
	ok(!defined(getpwnam($users[$i])), "Unix account $users[$i] is removed");
	}
if ($collision) {
	sql('mysql', 'DROP DATABASE '.identifier($collision));
	$databases{$collision} = 1;
	}
foreach my $spec ([ 'mysql.user', 'User', \%dbusers ],
		 [ 'information_schema.SCHEMATA', 'SCHEMA_NAME', \%databases ]) {
	my ($table, $column, $names) = @$spec;
	foreach my $name (sort keys %$names) {
		identifier($name);
		is(sql('mysql', "SELECT count(*) FROM $table WHERE $column = ?", $name),
			'0', "$name is removed from $table");
		}
	}
}
