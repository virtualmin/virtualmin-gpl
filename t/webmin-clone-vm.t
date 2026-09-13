#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempfile);
use Cwd qw(abs_path);
use JSON::PP qw(encode_json decode_json);

my $test_script = abs_path(__FILE__);

# Opt in before loading Webmin or changing user preferences.
plan skip_all => 'Set VIRTUALMIN_WEBMIN_CLONE_VM_TEST=1 on a disposable Virtualmin VM'
	unless ($ENV{'VIRTUALMIN_WEBMIN_CLONE_VM_TEST'} || '') eq '1';
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
$0 = "$module/webmin-clone-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
plan skip_all => 'Requires local Webmin user management'
	unless $virtual_server::config{'webmin'} && !virtual_server::remote_webmin();
die 'Requires timeout' unless has_command('timeout');
virtual_server::require_acl();
local $main::error_must_die = 1;
virtual_server::set_all_null_print();

# Read and write fixture preferences in fresh processes to avoid cached settings.
if (@ARGV && $ARGV[0] eq '--preferences') {
	Test::More->builder()->no_ending(1);
	my (undef, $name, $mode) = @ARGV;
	die 'Invalid fixture user' unless $name =~ /^wcl[0-2][a-f0-9]+$/;
	my ($user) = acl::list_users([ $name ]);
	if ($mode) {
		die 'Missing fixture Webmin user' unless $user;
		if ($mode eq 'explicit') {
			die 'Requires Authentic Theme' unless -f "$root/authentic-theme/theme.info";
			$user->{'lang'} = 'fr';
			# Ensure the source theme differs from the new account's default.
			$user->{'theme'} = $virtual_server::config{'webmin_theme'} eq 'authentic-theme'
				? '' : 'authentic-theme';
			}
		elsif ($mode eq 'inherited') {
			delete(@$user{qw(lang theme)});
			}
		else {
			die 'Invalid preference mode';
			}
		virtual_server::obtain_lock_webmin();
		acl::modify_user($name, $user);
		virtual_server::release_lock_webmin();
		}
	# Do not include password hashes or other authentication data in test output.
	print encode_json($user ? { map { $_ => $user->{$_} } qw(name lang theme email) } : undef);
	exit(0);
	}
note("Testing installed Virtualmin in $module");

# Generate the fixture password on the VM and keep it out of command arguments.
my ($passfh, $passfile) = tempfile('webmin-clone-pass-XXXXXX', DIR => '/tmp', UNLINK => 1);
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
print $passfh unpack('H*', $bytes) or die $!;
close($passfh) or die $!;
my $tag = sprintf('%x%04x', $$, int(rand(65536)));
my @users = map { "wcl${_}$tag" } (0 .. 2);
my @names = map { "webmin-clone-$_.invalid" } @users;
my %attempted;
foreach my $i (0 .. $#names) {
	die "Fixture domain already exists: $names[$i]" if domain($names[$i]);
	die "Fixture Unix account already exists: $users[$i]" if getpwnam($users[$i]);
	die "Fixture Webmin account already exists: $users[$i]" if preferences($users[$i]);
	}

# Return through cleanup on assertion, setup or timeout failures.
{
	local $SIG{'ALRM'} = sub { die "Webmin clone tests timed out\n"; };
	local $SIG{'INT'} = sub { die "Webmin clone tests interrupted\n"; };
	alarm(600);
	my $completed = eval { run_tests(); 1; };
	my $err = $@;
	alarm(0);
	if (!$completed) {
		fail('Webmin clone integration completed');
		diag($err);
		}
	}
cleanup();
done_testing();

# Clone through the CLI and inspect both users' saved preferences afterward.
sub run_tests
{
$attempted{$names[0]} = 1;
cli('create-domain', '--domain', $names[0], '--user', $users[0],
	'--passfile', $passfile, '--unix', '--dir', '--webmin', '--no-ip6',
	'--limits-from-plan', '--no-email', '--no-slaves', '--no-secondaries');
foreach my $i (1 .. 2) {
	my $mode = $i == 1 ? 'explicit' : 'inherited';
	preferences($users[0], $mode);
	my $before = preferences($users[0]);
	die 'Missing source Webmin user' unless $before;
	$attempted{$names[$i]} = 1;
	my ($status, $output) = run_command($^X, "$module/clone-domain.pl",
		'--domain', $names[0], '--newdomain', $names[$i], '--newuser', $users[$i]);
	subtest "clone $mode Webmin preferences" => sub {
		is($status, 0, 'clone-domain exits successfully') or diag($output);
		is_deeply(preferences($users[0]), $before, 'source user preferences are unchanged');
		my $d = domain($names[$i]);
		ok($d && $d->{'webmin'}, 'clone has Webmin access enabled');
		my $target = preferences($users[$i]);
		ok($target, 'clone has its own Webmin user');
		die 'Missing clone domain or user' unless $d && $target;
		is($target->{'lang'}, $before->{'lang'}, 'clone inherits source language');
		is($target->{'theme'}, $before->{'theme'}, 'clone inherits source theme');
		is($target->{'name'}, $users[$i], 'clone keeps its own username');
		is($target->{'email'}, $d->{'emailto'}, 'clone keeps its own email address');
		};
	}
}

# Bound every child command and supply EOF on stdin.
sub run_command
{
my $command = join(' ', map { quote_path($_) } ('timeout', '--kill-after=10s', '180s', @_));
my $output = backquote_command("$command </dev/null 2>&1");
return ($?, $output);
}

sub cli
{
my ($command, @args) = @_;
my ($status, $output) = run_command($^X, "$module/$command.pl", @args);
die "$command failed (status $status):\n$output" if $status;
}

sub preferences
{
my ($name, $mode) = @_;
my ($status, $output) = run_command($^X, $test_script, '--preferences', $name,
	defined($mode) ? ($mode) : ());
die "Preference helper failed (status $status):\n$output" if $status;
return decode_json($output);
}

# Refresh domain maps after CLI subprocesses change them.
sub domain
{
my ($name) = @_;
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
return virtual_server::get_domain_by('dom', $name);
}

# Delete the fixtures and verify that both Unix and Webmin accounts are gone.
sub cleanup
{
unlock_all_files();
foreach my $i (reverse(0 .. $#names)) {
	next unless $attempted{$names[$i]};
	if (domain($names[$i])) {
		my ($status, $output) = run_command($^X, "$module/delete-domain.pl", '--domain', $names[$i]);
		is($status, 0, "deletes $names[$i]") or diag($output);
		}
	ok(!domain($names[$i]), "$names[$i] is removed");
	ok(!defined(getpwnam($users[$i])), "Unix account $users[$i] is removed");
	ok(!preferences($users[$i]), "Webmin account $users[$i] is removed");
	}
}
