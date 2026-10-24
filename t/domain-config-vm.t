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
die 'Install the candidate domain locking helper first'
	unless defined(&virtual_server::get_lock_domain);
die 'Requires timeout' unless has_command('timeout');
local $main::error_must_die = 1;
local $virtual_server::gconfig{'error_stack'} = 1;
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

# Clean up the fixture when setup or tests fail.
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

# An operation starts from the current record even when given an old object.
my $stale = virtual_server::get_domain($id, undef, 1);
cli('modify-domain', '--domain', $name, '--desc', 'Newer owner description');
update_fixture($stale, { 'test_domain_key' => 'parent' });
is(disk()->{'owner'}, 'Newer owner description', 'locked update preserves a newer description');
is(disk()->{'test_domain_key'}, 'parent', 'locked update saves its requested field');

# Saving must keep the lock already held by the caller.
virtual_server::lock_domain($id);
update_fixture($stale, { 'test_outer_lock' => 1 });
is(test_lock("$virtual_server::domains_dir/$id"), $$, 'locked update retains the caller lock');
my $fresh = virtual_server::get_domain($id, undef, 1);
virtual_server::save_domain($fresh);
is(test_lock("$virtual_server::domains_dir/$id"), $$, 'full save retains the caller lock');
virtual_server::unlock_domain($id);
ok(!test_lock("$virtual_server::domains_dir/$id"), 'caller releases the domain lock');

# Fork before locking so the child does not inherit a held lock.
# Both processes then update different keys using Webmin's locks.
my $child = fork();
die "fork: $!" unless defined($child);
if (!$child) {
	my $ok = eval {
		for my $value (1 .. 6) {
			update_fixture($stale, { 'test_child_key' => $value });
			}
		1;
		};
	POSIX::_exit($ok ? 0 : 1);
	}
for my $value (1 .. 6) {
	update_fixture($stale, { 'test_parent_key' => $value });
	}
waitpid($child, 0);
is($?, 0, 'concurrent writer completes');
is(disk()->{'test_child_key'}, 6, 'child updates survive');
is(disk()->{'test_parent_key'}, 6, 'parent updates survive');

# Recheck IP settings under the lock and keep it through service changes.
ip_update_races();

# Feed known login timestamps to the collector for this fixture only.
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

# A backup snapshot may predate both the CLI change and login collection.
my $backup_file = "$tmp/stale-domain-backup";
my %before_backup = %{disk()};
ok(virtual_server::backup_virtualmin({ %$stale }, $backup_file),
	'stale domain snapshot can be archived');
my $after_backup = disk();
ok(!grep({ !exists($after_backup->{$_}) ||
	$after_backup->{$_} ne $before_backup{$_} } keys %before_backup),
	'backup leaves every current live field unchanged');
is(scalar(keys %$after_backup), scalar(keys %before_backup),
	'backup does not add metadata to the live domain');
my %archived;
read_file($backup_file, \%archived) or die 'Cannot read archived snapshot';
is($archived{'dir'}, $stale->{'dir'}, 'archive retains the snapshot home flag');
ok(exists($archived{'backup_web_type'}), 'archive includes restore metadata');
is((stat($backup_file))[2] & 0777, 0600, 'archived domain metadata is private');

my $mtime = (stat("$virtual_server::domains_dir/$id"))[9];
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	sleep(1);
	virtual_server::update_domains_last_login_times();
}
is((stat("$virtual_server::domains_dir/$id"))[9], $mtime, 'unchanged login avoids another write');

# Login collection must not restore stale disabled fields after the domain is enabled.
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

# Recheck the current disable schedule under the domain lock.
$d = virtual_server::get_domain($id, undef, 1);
update_fixture($d, { 'disabled_auto' => time() - 10 });
$stale = { %{$d} };
$stale->{'disabled_auto'} = time() - 10;
cli('disable-domain', '--domain', $name, '--schedule', 'none');
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	virtual_server::disable_scheduled_virtual_servers();
}
ok(!disk()->{'disabled'}, 'CLI cancellation survives the stale schedule collector');
ok(!exists(disk()->{'disabled_auto'}), 'collector does not restore a canceled schedule');

# A real pre-command can cancel the schedule without deadlocking, and the
# collector must check again after that command returns.
update_fixture($id, { 'disabled_auto' => time() - 10 });
{
	no warnings 'redefine';
	my $scheduled = virtual_server::get_domain($id, undef, 1);
	local *virtual_server::list_domains = sub { return $scheduled; };
	local $ENV{'VIRTUALMIN_PRE_COMMAND'} = join(' ', map { quote_path($_) }
		('timeout', '30', $^X, "$module/disable-domain.pl", '--domain', $name,
		 '--schedule', 'none'));
	virtual_server::disable_scheduled_virtual_servers();
}
ok(!disk()->{'disabled'} && !exists(disk()->{'disabled_auto'}),
	'pre-command cancels scheduling before any service is disabled');

$d = virtual_server::get_domain($id, undef, 1);
update_fixture($d, { 'disabled_auto' => time() - 10 });
$stale = virtual_server::get_domain($id, undef, 1);
update_fixture({ %$stale }, { 'protected' => 1 });
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	virtual_server::disable_scheduled_virtual_servers();
}
ok(!disk()->{'disabled'}, 'newly protected domain is not disabled from a stale schedule');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'skipped schedule releases the lock');
$d = virtual_server::get_domain($id, undef, 1);
update_fixture($d, { }, [ 'protected' ]);
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $d; };
	local $ENV{'VIRTUALMIN_POST_COMMAND'} = join(' ', map { quote_path($_) }
		('env', '-u', 'VIRTUALMIN_POST_COMMAND', 'timeout', '30', $^X,
		 "$module/modify-domain.pl", '--domain', $name,
		 '--desc', 'After-command owner description'));
	virtual_server::disable_scheduled_virtual_servers();
}
virtual_server::run_post_actions();
ok(disk()->{'disabled'}, 'eligible scheduled domain is disabled');
is(disk()->{'disabled_reason'}, 'schedule', 'scheduled reason is saved');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'completed schedule releases the lock');
is(disk()->{'owner'}, 'After-command owner description', 'after-command can update the domain after it is unlocked');
cli('modify-domain', '--domain', $name, '--desc', 'Newer owner description');
cli('enable-domain', '--domain', $name);

# Exercise existing CLI writers and the nested SSL saves used by real features.
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

# Exercise both archive layouts and the temporary home needed by aliases.
backup_roundtrips();

# A background update must not recreate a domain deleted after the initial read.
$stale = virtual_server::get_domain($id, undef, 1);
cli('delete-domain', '--domain', $name);
update_fixture($stale, { 'last_login_timestamp' => time() });
ok(!-e "$virtual_server::domains_dir/$id", 'locked update does not recreate a deleted domain');
ok(!test_lock("$virtual_server::domains_dir/$id"), 'deleted-domain update releases its lock');
}

# Set test values on the current record under its lock, then copy those values
# to the caller's snapshot. Other fields in that snapshot stay unchanged.
sub update_fixture
{
my ($domain, $values, $deletes) = @_;
my $domain_id = ref($domain) ? $domain->{'id'} : $domain;
my $locked;
local $main::get_domain_cache{$domain_id};
# The fixture deliberately supplies snapshots, even when testing a caller lock.
# Reread under that existing lock; otherwise get_lock_domain takes it first.
my $d = (test_lock("$virtual_server::domains_dir/$domain_id") || 0) == $$ ?
	virtual_server::get_domain($domain_id, undef, 1) :
	virtual_server::get_lock_domain({ id => $domain_id }, \$locked);
eval {
	local $main::error_must_die = 1;
	if ($d) {
		$d->{$_} = $values->{$_} for keys %$values;
		delete($d->{$_}) for @{$deletes || []};
		virtual_server::save_domain($d);
		}
	};
my $err = $@;
virtual_server::unlock_domain($domain_id) if $locked;
die $err if $err;
if (ref($domain)) {
	$domain->{$_} = $values->{$_} for keys %$values;
	delete($domain->{$_}) for @{$deletes || []};
	}
}

# Use real DNS changes and real feature callbacks, limited to this fixture.
sub ip_update_races
{
my $saved = { %{disk()} };
my $old_dns = '192.0.2.10';
my $new_dns = '192.0.2.11';
cli('modify-domain', '--domain', $name, '--dns-ip', $old_dns);
my $stale = virtual_server::get_domain($id, undef, 1);
cli('modify-domain', '--domain', $name, '--dns-ip', '192.0.2.12');
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	is(virtual_server::update_all_domain_ip_addresses($new_dns, $old_dns), 0,
		'IP updater skips a domain moved by another CLI process');
}
is(disk()->{'dns_ip'}, '192.0.2.12', 'CLI IP change survives stale collector state');

# Mark the domain's IP as dedicated to test that it is skipped,
# without changing any VM interface addresses.
cli('modify-domain', '--domain', $name, '--dns-ip', $old_dns);
$stale = { %{virtual_server::get_domain($id, undef, 1)} };
update_fixture({ %$stale }, { virt => 1 });
{
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	is(virtual_server::update_all_domain_ip_addresses($new_dns, $old_dns), 0,
		'newly dedicated domain is excluded after the locked reread');
}
is(disk()->{'dns_ip'}, $old_dns, 'dedicated domain keeps its DNS IP');
update_fixture({ %$stale }, { virt => $saved->{'virt'} });

# Fork before locking. The child signals just before attempting the same lock,
# and cannot complete while any real service callback is in progress.
pipe(my $start_read, my $start_write) or die $!;
pipe(my $ready_read, my $ready_write) or die $!;
my $child = fork();
die "fork: $!" unless defined($child);
if (!$child) {
	close($start_write);
	close($ready_read);
	my $ok = eval {
		my $byte;
		sysread($start_read, $byte, 1) == 1 or die 'No start signal';
		syswrite($ready_write, '1') == 1 or die 'Cannot signal writer';
		update_fixture($id, { test_during_ip_update => 1 });
		1;
		};
	POSIX::_exit($ok ? 0 : 1);
	}
close($start_read);
close($ready_write);
my $started = 0;
my $try = \&virtual_server::try_function;
my $plugin = \&virtual_server::plugin_call;
my $check = sub {
	my ($d) = @_;
	return unless $d && ref($d) eq 'HASH' && $d->{'id'} eq $id;
	is(test_lock("$virtual_server::domains_dir/$id"), $$,
		'domain lock survives real service callback');
	if (!$started++) {
		syswrite($start_write, '1') == 1 or die 'Cannot start competing writer';
		my $byte;
		sysread($ready_read, $byte, 1) == 1 or die 'No writer signal';
		select(undef, undef, undef, 0.3);
		is(waitpid($child, POSIX::WNOHANG()), 0, 'competing writer waits during IP changes');
		}
	};
my $ok = eval {
	no warnings 'redefine';
	local *virtual_server::list_domains = sub { return $stale; };
	local *virtual_server::try_function = sub {
		my @rv = $try->(@_);
		$check->($_[2]) if $_[1] =~ /^modify_/;
		return wantarray ? @rv : $rv[0];
		};
	local *virtual_server::plugin_call = sub {
		my $want = wantarray;
		my (@rv, $rv);
		if ($want) { @rv = $plugin->(@_); }
		else { $rv = $plugin->(@_); }
		$check->($_[2]) if $_[1] eq 'feature_modify';
		return $want ? @rv : $rv;
		};
	is(virtual_server::update_all_domain_ip_addresses($new_dns, $old_dns), 1,
		'eligible IP update completes through real features');
	1;
	};
my $err = $@;
close($start_write);
close($ready_read);
waitpid($child, 0);
is($?, 0, 'competing writer completes after IP update');
die $err unless $ok;
ok($started, 'real service callbacks were exercised');
is(disk()->{'dns_ip'}, $new_dns, 'background IP change is saved');
ok(disk()->{'test_during_ip_update'}, 'later competing edit survives');
virtual_server::run_post_actions();
if ($saved->{'dns_ip'}) {
	cli('modify-domain', '--domain', $name, '--dns-ip', $saved->{'dns_ip'});
	}
else {
	cli('modify-domain', '--domain', $name, '--no-dns-ip');
	}
cli('validate-domains', '--domain', $name, '--all-features');
pass('features validate after concurrent IP update');
# Subsequent tests imitate new requests after the restoring CLI process exits.
# Discard parsed file data without flushing it back over that process's changes.
unflush_file_lines($_) for keys %main::file_cache;
bind8::clear_config_cache();
virtual_server::clear_domain_dns_records_and_file({ id => $id });
virtual_server::flush_virtualmin_caches();
}

# Restore real files and settings, then cover an alias that has no home to archive.
sub backup_roundtrips
{
my $d = domain();
my $payload = "$d->{'home'}/domain-config-backup-fixture";
my $shell = (getpwnam($user))[8];
foreach my $homeformat (0, 1) {
	my $destination = "$tmp/backup-$homeformat";
	my @format = $homeformat ? ('--newformat') : ();
	$destination .= '.tar.gz' unless $homeformat;
	mkdir($destination, 0700) or die $! if $homeformat;
	write_file_contents($payload, "original backup payload\n");
	# Exclude CGI/FCGIwrap restoration from the Nginx domain recreation test.
	cli('modify-web', '--domain', $name, '--disable-cgi')
		if $homeformat && !$virtual_server::config{'web'};
	cli('disable-domain', '--domain', $name) if $homeformat;
	cli('backup-domain', '--domain', $name, '--all-features',
		'--dest', $destination, @format, '--compression', 'gzip');
	my $archive = $homeformat ? "$destination/$name.tar.gz" : $destination;
	ok(-s $archive, "backup format $homeformat produces an archive");
	write_file_contents($payload, "changed after backup\n");
	cli('delete-domain', '--domain', $name) if $homeformat;
	cli('restore-domain', '--domain', $name, '--all-features', '--source', $archive);
	if ($homeformat) {
		$id = domain()->{'id'};
		ok(disk()->{'disabled'}, 'recreated backup remains disabled');
		isnt((getpwnam($user))[8], $shell, 'recreated disabled account has login blocked');
		cli('enable-domain', '--domain', $name);
		is((getpwnam($user))[8], $shell, 'enabling the recreated backup restores login');
		}
	is(read_file_contents($payload), "original backup payload\n",
		"backup format $homeformat restores home contents");
	is(disk()->{'owner'}, 'Newer owner description',
		"backup format $homeformat restores domain metadata");
	cli('validate-domains', '--domain', $name, '--all-features');
	pass("backup format $homeformat restores valid features");
	}

# Home-format backups must archive dir=1 while cleaning up the temporary home.
my $alias_name = "alias-$name";
cli('create-domain', '--domain', $alias_name, '--alias', $name,
	'--dns', '--no-ip6', '--no-email', '--no-slaves', '--no-secondaries',
	'--letsencrypt-never');
my $alias = domain($alias_name)
	or die 'Alias fixture was not created';
ok(!$alias->{'dir'} && !-d $alias->{'home'}, 'alias starts without a home directory');
my $destination = "$tmp/alias-backup";
mkdir($destination, 0700) or die $!;
cli('backup-domain', '--domain', $alias_name, '--all-features',
	'--dest', $destination, '--newformat', '--compression', 'gzip');
my $archive = "$destination/$alias_name.tar.gz";
ok(-s $archive, 'alias backup produces a home-format archive');
$alias = virtual_server::get_domain($alias->{'id'}, undef, 1);
ok(!$alias->{'dir'} && !-d $alias->{'home'}, 'alias backup removes its temporary home');

# An existing home is intentionally enabled and must survive backup cleanup.
mkdir($alias->{'home'}, 0755) or die $!;
set_ownership_permissions($alias->{'uid'}, $alias->{'gid'}, 0755, $alias->{'home'});
my $existing_destination = "$tmp/alias-existing-home";
mkdir($existing_destination, 0700) or die $!;
cli('backup-domain', '--domain', $alias_name, '--all-features',
	'--dest', $existing_destination, '--newformat', '--compression', 'gzip');
$alias = virtual_server::get_domain($alias->{'id'}, undef, 1);
ok($alias->{'dir'} && -d $alias->{'home'}, 'backup preserves and enables an existing home');
cli('delete-domain', '--domain', $alias_name);
cli('restore-domain', '--domain', $alias_name, '--all-features', '--source', $archive);
$alias = domain($alias_name)
	or die 'Alias fixture was not restored';
is($alias->{'parent'}, $id, 'restored alias retains its parent');
ok($alias->{'dir'} && -d $alias->{'home'}, 'restore uses the archived temporary home flag');
cli('validate-domains', '--domain', $alias_name, '--all-features');
pass('restored alias features validate');
cli('delete-domain', '--domain', $alias_name);
}

# Limit CLI execution time. Passwords are passed through a file.
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
my ($lookup_name) = @_;
$lookup_name ||= $name;
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
return virtual_server::get_domain_by('dom', $lookup_name);
}

# Remove the domain and its service, Unix, and Webmin state even after failures.
sub cleanup
{
unlock_all_files();
return unless $attempted;
if (my $d = domain()) {
	update_fixture($d, { }, [ 'protected' ]);
	my ($status, $output) = run_command("$module/delete-domain.pl", '--domain', $name);
	is($status, 0, 'fixture cleanup succeeds') or diag($output);
	}
ok(!domain(), 'fixture domain is removed');
ok(!getpwnam($user), 'fixture Unix account is removed');
}
