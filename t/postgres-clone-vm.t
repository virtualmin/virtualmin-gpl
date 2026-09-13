#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempfile);

# Opt in before loading Webmin or reading service configuration.
plan skip_all => 'Set VIRTUALMIN_POSTGRES_CLONE_VM_TEST=1 on a disposable Virtualmin PostgreSQL VM'
	unless ($ENV{'VIRTUALMIN_POSTGRES_CLONE_VM_TEST'} || '') eq '1';
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
$0 = "$module/postgres-clone-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
plan skip_all => 'Requires the local PostgreSQL feature'
	unless $virtual_server::config{'postgres'} &&
	virtual_server::get_default_postgres_module() eq 'postgresql';
foreach my $command (qw(psql runuser timeout)) {
	die "Required command not found: $command" unless has_command($command);
	}
local $main::error_must_die = 1;
virtual_server::set_all_null_print();
note("Testing installed Virtualmin in $module");

# Fixture credentials stay on the VM, outside process arguments and TAP.
my ($passfh, $passfile) = tempfile('postgres-clone-pass-XXXXXX',
	DIR => '/tmp', UNLINK => 1);
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
print $passfh unpack('H*', $bytes) or die $!;
close($passfh) or die $!;
my $tag = sprintf('%x%04x', $$, int(rand(65536)));
my @users = map { "pgc${_}$tag" } qw(s e d f);
my @names = map { "postgres-clone-$_.invalid" } @users;
my (%attempted, %roles, %databases);
my $collision;
foreach my $i (0 .. $#names) {
	die "Fixture domain already exists: $names[$i]"
		if virtual_server::get_domain_by('dom', $names[$i]);
	die "Fixture account already exists: $users[$i]" if getpwnam($users[$i]);
	}

# Always clean up after a failed assertion or setup command.
{
	local $SIG{'ALRM'} = sub { die "PostgreSQL clone tests timed out\n"; };
	local $SIG{'INT'} = sub { die "PostgreSQL clone tests interrupted\n"; };
	alarm(900);
	my $completed = eval { run_tests(); 1; };
	my $error = $@;
	alarm(0);
	if (!$completed) {
		fail('PostgreSQL clone integration completed');
		diag($error);
		}
	}
cleanup();
done_testing();

# Test an empty database list, copied table data, and a real database name clash.
sub run_tests
{
$attempted{$names[0]} = 1;
cli('create-domain', '--domain', $names[0], '--user', $users[0],
	'--passfile', $passfile, '--unix', '--dir', '--postgres', '--no-ip6',
	'--limits-from-plan', '--no-email', '--no-slaves', '--no-secondaries');
my $source = domain($names[0]);
foreach my $db (virtual_server::domain_databases($source, [ 'postgres' ])) {
	cli('delete-database', '--domain', $names[0], '--type', 'postgres',
		'--name', $db->{'name'});
	}
$source = domain($names[0]);
ok($source->{'postgres'}, 'source still has PostgreSQL enabled');
is(scalar(virtual_server::domain_databases($source, [ 'postgres' ])), 0,
	'source has no PostgreSQL databases');

$attempted{$names[1]} = 1;
my ($status, $output) = run_command($^X, "$module/clone-domain.pl",
	'--domain', $names[0], '--newdomain', $names[1], '--newuser', $users[1]);
is($status, 0, 'cloning without databases exits successfully') or diag($output);
my $empty = domain($names[1]);
ok($empty->{'postgres'}, 'empty clone retains PostgreSQL support');
is(scalar(virtual_server::domain_databases($empty, [ 'postgres' ])), 0,
	'empty clone has no PostgreSQL databases');

# Insert as the domain's PostgreSQL role, so its dump can read the table.
cli('create-database', '--domain', $names[0], '--type', 'postgres',
	'--name', $source->{'db'});
$source = domain($names[0]);
my @dbs = virtual_server::domain_databases($source, [ 'postgres' ]);
die 'Expected one source database' unless @dbs == 1;
sql($dbs[0]->{'name'}, 'SET ROLE '.identifier(virtual_server::postgres_user($source)).
	"; CREATE TABLE clone_probe (value text); INSERT INTO clone_probe VALUES ('postgres-clone-data-ok')");
$attempted{$names[2]} = 1;
cli('clone-domain', '--domain', $names[0], '--newdomain', $names[2],
	'--newuser', $users[2]);
my $target = domain($names[2]);
my @copied = virtual_server::domain_databases($target, [ 'postgres' ]);
is(scalar(@copied), 1, 'normal clone contains one database');
die 'Missing cloned database' unless @copied == 1;
is(sql($copied[0]->{'name'}, 'SELECT value FROM clone_probe'),
	'postgres-clone-data-ok', 'normal clone preserves table data');

# Reserve only the secondary target database name. Domain creation and the
# primary database copy can succeed before clone_postgres reports the clash.
my $extra = virtual_server::fix_database_name($source->{'prefix'}, 'postgres').'_extra';
cli('create-database', '--domain', $names[0], '--type', 'postgres', '--name', $extra);
my $prefix = virtual_server::compute_prefix($names[3], $users[3], undef, 1);
my $reserved = virtual_server::fix_database_name($prefix, 'postgres').'_extra';
sql('postgres', 'CREATE DATABASE '.identifier($reserved));
$collision = $reserved;
$attempted{$names[3]} = 1;
($status, $output) = run_command($^X, "$module/clone-domain.pl",
	'--domain', $names[0], '--newdomain', $names[3], '--newuser', $users[3]);
is($status, 1 << 8, 'partial database clone exits with failure') or diag($output);
like($output, qr/\Q$reserved\E already exists/, 'failure comes from the database clash');
my $partial = domain($names[3]);
my @partial = virtual_server::domain_databases($partial, [ 'postgres' ]);
is(scalar(@partial), 1, 'partial clone retains the successfully copied database');
die 'Missing partially cloned database' unless @partial == 1;
is(sql($partial[0]->{'name'}, 'SELECT value FROM clone_probe'),
	'postgres-clone-data-ok', 'partial failure does not discard copied data');
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
return '"'.$name.'"';
}

sub sql
{
my ($db, $query) = @_;
my ($status, $output) = run_command('runuser', '-u', 'postgres', '--',
	'psql', '-XAt', '--dbname', $db, '--set', 'ON_ERROR_STOP=1', '--command', $query);
die "Fixture SQL failed (status $status):\n$output" if $status;
$output =~ s/\s+$//;
return $output;
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
$roles{virtual_server::postgres_user($d)} = 1;
$databases{$_->{'name'}} = 1 foreach virtual_server::domain_databases($d, [ 'postgres' ]);
return $d;
}

# Delete through Virtualmin, then verify Unix accounts, database roles and DBs.
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
	sql('postgres', 'DROP DATABASE '.identifier($collision));
	$databases{$collision} = 1;
	}
foreach my $spec ([ 'pg_roles', 'rolname', \%roles ],
		 [ 'pg_database', 'datname', \%databases ]) {
	my ($table, $column, $names) = @$spec;
	foreach my $name (sort keys %$names) {
		identifier($name);
		is(sql('postgres', "SELECT count(*) FROM $table WHERE $column = '$name'"),
			'0', "$name is removed from $table");
		}
	}
}
