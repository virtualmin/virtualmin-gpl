#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempfile);
use Cwd qw(abs_path);

my $test_script = abs_path(__FILE__);
my ($restore_file, $restore_contents);

# Restore the rejected vhost even when clone-domain.pl exits with status 1.
END {
	if ($restore_file) {
		my $status = $?;
		if (open(my $fh, '>', $restore_file)) {
			print $fh $restore_contents or die "Cannot restore $restore_file: $!";
			close($fh) or die "Cannot close $restore_file: $!";
			$? = $status;
			}
		else {
			die "Cannot restore $restore_file: $!";
			}
		}
	}

# Opt in before loading Webmin or touching service configuration.
plan skip_all => 'Set VIRTUALMIN_CLONE_POST_VM_TEST=1 on a disposable Virtualmin Apache VM'
	unless ($ENV{'VIRTUALMIN_CLONE_POST_VM_TEST'} || '') eq '1';
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
$0 = "$module/clone-post-actions-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
plan skip_all => 'Requires Apache' unless $virtual_server::config{'web'};
foreach my $command (qw(curl timeout)) {
	die "Required command not found: $command" unless has_command($command);
	}
virtual_server::require_apache();
local $main::error_must_die = 1;
virtual_server::set_all_null_print();

# Inject faults after the target vhost is cloned, using the real CLI and actions.
if (@ARGV && $ARGV[0] eq '--fault') {
	Test::More->builder()->no_ending(1);
	shift(@ARGV);
	my ($mode, $source, $target, $user) = @ARGV;
	die 'Invalid clone fixture' unless $mode =~ /^(config_error|reload_error|exception)$/ &&
		$source =~ /^post-clone-pact[a-z0-9]+\.invalid$/ &&
		$target =~ /^post-clone-pact[a-z0-9]+\.invalid$/ && $user =~ /^pact[a-z0-9]+$/;
	my $clone = \&virtual_server::clone_web;
	local $virtual_server::config{'check_apache'} = $mode eq 'config_error' ? 1 : 0;
	no warnings 'redefine';
	local *virtual_server::clone_web = sub {
		my $rv = $clone->(@_);
		my ($d) = @_;
		if ($d->{'dom'} eq $target) {
			if ($mode eq 'config_error') {
				my ($virt) = virtual_server::get_apache_virtual($target, $d->{'web_port'});
				die 'Missing fixture vhost' unless $virt;
				$restore_file = $virt->{'file'};
				$restore_contents = read_file_contents($restore_file);
				open(my $bad, '>>', $restore_file) or die $!;
				print $bad "\nInvalidCloneFixtureDirective on\n" or die $!;
				close($bad) or die $!;
				}
			elsif ($mode eq 'reload_error') {
				# Run a failing command through Apache's real backend wrapper.
				$apache::config{'apply_cmd'} = "sh -c 'echo Controlled Apache apply failure; exit 17'";
				}
			else {
				virtual_server::register_post_action(sub { die "Controlled post-action exception\n"; });
				}
			virtual_server::register_post_action(sub { print "Later post-action ran\n"; });
			}
		return $rv;
		};
	@ARGV = ('--domain', $source, '--newdomain', $target, '--newuser', $user);
	{ package virtual_server; do "$module/clone-domain.pl"; }
	die $@ if $@;
	exit(0);
	}
note("Testing installed Virtualmin in $module");

# Fixture credentials and hook files remain on the VM with mode 0600.
my ($passfh, $passfile) = tempfile('clone-post-pass-XXXXXX', DIR => '/tmp', UNLINK => 1);
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
print $passfh unpack('H*', $bytes) or die $!;
close($passfh) or die $!;
my ($hookfh, $hookfile) = tempfile('clone-post-hook-XXXXXX', DIR => '/tmp', UNLINK => 1);
print $hookfh <<'HOOK' or die $!;
exit(0) unless ($ENV{'VIRTUALSERVER_ACTION'} || '') eq 'CLONE_DOMAIN';
my ($mode) = @ARGV;
print "After-clone command ran\n" unless $mode eq 'silent';
exit($mode eq 'success' ? 0 : 23);
HOOK
close($hookfh) or die $!;
my $tag = sprintf('%x%04x', $$, int(rand(65536)));
my @cases = qw(success hook_failure hook_silent config_error reload_error exception);
my @users = map { "pact${_}$tag" } (0 .. @cases);
my @names = map { "post-clone-$_.invalid" } @users;
my %attempted;
foreach my $i (0 .. $#names) {
	die "Fixture domain already exists: $names[$i]"
		if virtual_server::get_domain_by('dom', $names[$i]);
	die "Fixture account already exists: $users[$i]" if getpwnam($users[$i]);
	}
{
	local $SIG{'ALRM'} = sub { die "Clone post-action tests timed out\n"; };
	local $SIG{'INT'} = sub { die "Clone post-action tests interrupted\n"; };
	alarm(900);
	my $completed = eval { run_tests(); 1; };
	my $err = $@;
	alarm(0);
	if (!$completed) {
		fail('Clone post-action integration completed');
		diag($err);
		}
	}
cleanup();
done_testing();

# Check real after-clone commands and service failures without stopping Apache.
sub run_tests
{
$attempted{$names[0]} = 1;
cli('create-domain', '--domain', $names[0], '--user', $users[0],
	'--passfile', $passfile, '--unix', '--dir', '--web', '--no-ip6',
	'--content', 'Post-action clone page', '--limits-from-plan',
	'--no-email', '--no-slaves', '--no-secondaries');
cli('modify-web', '--domain', $names[0], '--mode', 'none');
foreach my $i (1 .. @cases) {
	my $case = $cases[$i-1];
	$attempted{$names[$i]} = 1;
	my ($status, $output);
	{
		my $mode = $case eq 'hook_failure' ? 'failure' :
			$case eq 'hook_silent' ? 'silent' : 'success';
		local $ENV{'VIRTUALMIN_POST_COMMAND'} = join(' ', map { quote_path($_) } ($^X, $hookfile, $mode));
		local $ENV{'VIRTUALMIN_OUTPUT_COMMAND'} = 1;
		if ($case =~ /^(config_error|reload_error|exception)$/) {
			($status, $output) = run_command($^X, $test_script, '--fault',
				$case, $names[0], $names[$i], $users[$i]);
			}
		else {
			($status, $output) = run_command($^X, "$module/clone-domain.pl",
				'--domain', $names[0], '--newdomain', $names[$i], '--newuser', $users[$i]);
			}
		}
	subtest "clone completion: $case" => sub {
		is($status, $case eq 'success' ? 0 : 1 << 8, 'CLI reports the completion result') or diag($output);
		my $d = domain($names[$i]);
		ok($d->{'web'}, 'clone remains saved with its website');
		like($output, qr/After-clone command ran/, 'after-clone command ran') unless $case eq 'hook_silent';
		like($output, qr/Post-creation command failed/, 'reports the failing hook') if $case =~ /^hook_/;
		if ($case =~ /^(config_error|reload_error|exception)$/) {
			like($output, qr/Later post-action ran/, 'continues with later actions');
			my %errors = (config_error => qr/InvalidCloneFixtureDirective/,
				reload_error => qr/Controlled Apache apply failure/,
				exception => qr/Controlled post-action exception/);
			like($output, $errors{$case}, 'reports the intended fault');
			}
		if ($case eq 'success') {
			my ($http, $page) = run_command('curl', '--fail', '--silent', '--show-error',
				'--noproxy', '*', '--max-time', '20', '--resolve',
				"$d->{'dom'}:$d->{'web_port'}:$d->{'ip'}", "http://$d->{'dom'}:$d->{'web_port'}/");
			is($http, 0, 'normal clone serves HTTP') or diag($page);
			like($page, qr/Post-action clone page/, 'serves the copied content');
			}
		};
	apache::flush_config_cache();
	my $err = apache::test_config();
	die "Apache fixture was not restored: $err" if $err;
	}
}

# Every command has a deadline and receives EOF on stdin.
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

# Refresh domain maps after the CLI creates or deletes fixtures.
sub refresh_caches
{
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
apache::flush_config_cache();
}

sub domain
{
my ($name) = @_;
refresh_caches();
return virtual_server::get_domain_by('dom', $name) || die "Missing domain $name";
}

# Remove all fixture domains and verify Apache still has a valid, running config.
sub cleanup
{
unlock_all_files();
foreach my $i (reverse(0 .. $#names)) {
	next unless $attempted{$names[$i]};
	refresh_caches();
	if (virtual_server::get_domain_by('dom', $names[$i])) {
		my ($status, $output) = run_command($^X, "$module/delete-domain.pl", '--domain', $names[$i]);
		is($status, 0, "deletes $names[$i]") or diag($output);
		}
	refresh_caches();
	ok(!virtual_server::get_domain_by('dom', $names[$i]), "$names[$i] is removed");
	ok(!defined(getpwnam($users[$i])), "Unix account $users[$i] is removed");
	}
my $err = apache::test_config();
ok(!$err, 'Apache configuration is valid after cleanup') or diag($err);
my $pid = virtual_server::get_apache_pid();
ok($pid && kill(0, $pid), 'Apache is running after cleanup');
}
