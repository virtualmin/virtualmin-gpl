#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempdir);
use POSIX ();

# Load Webmin only after an explicit opt-in on a disposable Linux VM.
plan skip_all => 'Set VIRTUALMIN_DOMAIN_CONFIG_VM_TEST=1 on a disposable Virtualmin VM'
	unless ($ENV{'VIRTUALMIN_DOMAIN_CONFIG_VM_TEST'} || '') eq '1';
plan skip_all => 'Requires root on a disposable Linux VM'
	unless $^O eq 'linux' && $< == 0 && $> == 0;
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
die 'Cannot find Webmin' unless $root;
my $module = "$root/virtual-server";
chdir($module) or die $!;
$0 = "$module/domain-config-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
die 'Install the candidate domain config helpers first'
	unless defined(&virtual_server::save_domain_keys);
die 'Requires timeout' unless has_command('timeout');
local $main::error_must_die = 1;
virtual_server::set_all_null_print();

# Keep fixture credentials and login data on the VM, in a private directory.
my $tmp = tempdir('virtualmin-domain-config-XXXXXX', DIR => '/tmp', CLEANUP => 1);
my $passfile = "$tmp/password";
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
open(my $pass, '>', $passfile) or die $!;
chmod(0600, $passfile) or die $!;
print $pass unpack('H*', $bytes) or die $!;
close($pass) or die $!;
my $user = sprintf('dc%x%04x', $$, int(rand(65536)));
my $name = "domain-config-$user.invalid";
my ($id, $attempted);
die 'Fixture Unix account already exists' if getpwnam($user);
die 'Fixture domain already exists' if domain();

# All setup and test failures return through fixture cleanup.
{
	local $SIG{'ALRM'} = sub { die "Domain config tests timed out\n"; };
	local $SIG{'INT'} = sub { die "Domain config tests interrupted\n"; };
	alarm(900);
	my $ok = eval { run_tests(); 1; };
	my $err = $@;
	alarm(0);
	if (!$ok) {
		fail('domain config integration completed');
		diag($err);
		}
}
cleanup();
done_testing();

# Use real domains, disk reads, Webmin locks, and separate CLI processes.
sub run_tests
{
$attempted = 1;
my @web = $virtual_server::config{'web'} ? ('--web', '--ssl') :
	('--virtualmin-nginx', '--virtualmin-nginx-ssl');
my $web = substr($web[0], 2);
cli('create-domain', '--domain', $name, '--user', $user, '--passfile', $passfile,
	'--unix', '--dir', '--dns', '--mail', '--webmin', @web, '--no-ip6',
	'--limits-from-plan', '--no-email', '--no-slaves', '--no-secondaries',
	'--letsencrypt-never', '--default-cert-owner');
my $d = domain() or die 'Fixture domain was not created';
$id = $d->{'id'};
my $original_shell = (getpwnam($user))[8];
ok($id, 'fixture domain exists');

# A newer unrelated value must survive a diff from an older snapshot.
my $stale = virtual_server::get_domain($id, undef, 1);
my %original = %$stale;
cli('modify-domain', '--domain', $name, '--desc', 'Newer owner description');
$stale->{'test_domain_key'} = 'parent';
virtual_server::save_domain_diff($stale, \%original);
is(disk()->{'owner'}, 'Newer owner description', 'diff preserves a newer description');
is(disk()->{'test_domain_key'}, 'parent', 'diff saves its requested field');

# A nested save must leave the outer critical section locked.
virtual_server::lock_domain($id);
virtual_server::save_domain_keys($stale, { 'test_outer_lock' => 1 });
is(test_lock("$virtual_server::domains_dir/$id"), $$, 'keyed update retains the caller lock');
my $fresh = virtual_server::get_domain($id, undef, 1);
virtual_server::save_domain($fresh);
is(test_lock("$virtual_server::domains_dir/$id"), $$, 'full save retains the caller lock');
virtual_server::unlock_domain($id);
ok(!test_lock("$virtual_server::domains_dir/$id"), 'caller releases the domain lock');

# Two independent processes update different keys through the real lock code.
my $child = fork();
die "fork: $!" unless defined($child);
if (!$child) {
	my $ok = eval {
		for my $value (1 .. 6) {
			virtual_server::save_domain_keys($stale, { 'test_child_key' => $value });
			}
		1;
		};
	POSIX::_exit($ok ? 0 : 1);
	}
for my $value (1 .. 6) {
	virtual_server::save_domain_keys($stale, { 'test_parent_key' => $value });
	}
waitpid($child, 0);
is($?, 0, 'concurrent writer completes');
is(disk()->{'test_child_key'}, 6, 'child updates survive');
is(disk()->{'test_parent_key'}, 6, 'parent updates survive');

# Feed real login records to the collector while limiting its scope to our fixture.
write_file("$tmp/logins", { $user => 'imap=1700000010 smtp=1700000020' });
local $virtual_server::mail_login_file = "$tmp/logins";
$stale = virtual_server::get_domain($id, undef, 1);
cli('disable-domain', '--domain', $name, '--why', 'Domain config test');
my $disabled = disk();
ok($disabled->{'disabled'}, 'CLI saves disabled status');
my @disabled_keys = grep { /^disabled(?:_|$)/ } keys %$disabled;
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	virtual_server::update_domains_last_login_times();
}
my $after = disk();
is($after->{'last_login_timestamp'}, 1700000020, 'collector saves the latest login');
foreach my $key (@disabled_keys) {
	# Some restoration fields contain hashes; compare without logging their values.
	ok(defined($after->{$key}) && $after->{$key} eq $disabled->{$key},
		"collector preserves $key");
	}
my $mtime = (stat("$virtual_server::domains_dir/$id"))[9];
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	sleep(1);
	virtual_server::update_domains_last_login_times();
}
is((stat("$virtual_server::domains_dir/$id"))[9], $mtime, 'unchanged login avoids another write');

# The reverse transition must not restore disabled fields from an old collector.
$stale = virtual_server::get_domain($id, undef, 1);
cli('enable-domain', '--domain', $name);
write_file("$tmp/logins", { $user => 'imap=1700000030' });
delete($main::read_file_cache{"$tmp/logins"});
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	virtual_server::update_domains_last_login_times();
}
ok(!disk()->{'disabled'}, 'collector preserves re-enabled status');
is(disk()->{'last_login_timestamp'}, 1700000030, 'later login is saved');
is((getpwnam($user))[8], $original_shell, 'enable restores the Unix shell');

# The scheduled-disabling loop must recheck eligibility under its domain lock.
$d = virtual_server::get_domain($id, undef, 1);
virtual_server::save_domain_keys($d, { 'disabled_auto' => time() - 10 });
$stale = virtual_server::get_domain($id, undef, 1);
virtual_server::save_domain_keys({ %$stale }, { 'protected' => 1 });
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	virtual_server::disable_scheduled_virtual_servers();
}
ok(!disk()->{'disabled'}, 'newly protected domain is not disabled from a stale schedule');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'skipped schedule releases the lock');
$d = virtual_server::get_domain($id, undef, 1);
virtual_server::save_domain_keys($d, { }, [ 'protected' ]);
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $d; };
	virtual_server::disable_scheduled_virtual_servers();
}
virtual_server::run_post_actions();
ok(disk()->{'disabled'}, 'eligible scheduled domain is disabled');
is(disk()->{'disabled_reason'}, 'schedule', 'scheduled reason is saved');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'completed schedule releases the lock');
cli('enable-domain', '--domain', $name);

# Exercise migrated CLI writers and the nested SSL saves used by real features.
cli('disable-limit', '--domain', $name, "--$web");
ok(!disk()->{"limit_$web"}, 'owner limit is disabled');
cli('enable-limit', '--domain', $name, "--$web");
ok(disk()->{"limit_$web"}, 'owner limit is enabled');
cli('disable-feature', '--domain', $name, '--webmin');
ok(!disk()->{'webmin'}, 'Webmin feature is disabled');
cli('enable-feature', '--domain', $name, '--webmin');
ok(disk()->{'webmin'}, 'Webmin feature is enabled');
cli('generate-cert', '--domain', $name, '--self', '--cn', $name);
$after = disk();
ok(-s $after->{'ssl_cert'} && -s $after->{'ssl_key'}, 'self-signed certificate and key exist');
cli('generate-cert', '--domain', $name, '--csr', '--cn', $name);
$after = disk();
ok(-s $after->{'ssl_csr'} && -s $after->{'ssl_newkey'}, 'CSR and pending key paths are saved');
cli('install-cert', '--domain', $name, '--cert', $after->{'ssl_cert'}, '--key', $after->{'ssl_key'});
is(disk()->{'owner'}, 'Newer owner description', 'CLI writers retain unrelated domain settings');
cli('validate-domains', '--domain', $name, '--all-features');
pass('fixture features validate after disable, enable, and certificate changes');

# A record deleted after reading must not be resurrected by a background writer.
$stale = virtual_server::get_domain($id, undef, 1);
cli('delete-domain', '--domain', $name);
virtual_server::save_domain_keys($stale, { 'last_login_timestamp' => time() });
ok(!-e "$virtual_server::domains_dir/$id", 'keyed update does not recreate a deleted domain');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'deleted-domain update releases its lock');
}

# Bound child commands and keep all credentials out of arguments and diagnostics.
sub run_command
{
my @command = ('timeout', '--kill-after=10s', '180s', $^X, @_);
my $command = join(' ', map { quote_path($_) } @command);
my $output = backquote_command("$command </dev/null 2>&1");
return ($?, $output);
}

sub cli
{
my ($command, @args) = @_;
my ($status, $output) = run_command("$module/$command.pl", @args);
die "$command failed (status $status):\n$output" if $status;
}

# Avoid refreshing the in-memory object when inspecting the newer disk record.
sub disk
{
my %d;
read_file("$virtual_server::domains_dir/$id", \%d) or die 'Cannot read fixture domain';
return \%d;
}

sub domain
{
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
return virtual_server::get_domain_by('dom', $name);
}

# Remove the domain and its service, Unix, and Webmin state even after failures.
sub cleanup
{
unlock_all_files();
return unless $attempted;
if (my $d = domain()) {
	virtual_server::save_domain_keys($d, { }, [ 'protected' ]);
	my ($status, $output) = run_command("$module/delete-domain.pl", '--domain', $name);
	is($status, 0, 'fixture cleanup succeeds') or diag($output);
	}
ok(!domain(), 'fixture domain is removed');
ok(!getpwnam($user), 'fixture Unix account is removed');
}
