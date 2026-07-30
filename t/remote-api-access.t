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

{
	no warnings qw(once redefine);
	local @main::plugins = ();
	local *main::master_admin = sub { 0 };
	ok(&can_remote_as_user('list-databases'),
		'database listing is allowed for non-master API users');
	ok(&can_remote_as_user('list-proxies.pl'),
		'allowed command names are normalized');
	ok(&can_remote_as_user('list-redirects'),
		'redirect listing is allowed for non-master API users');
	ok(&can_remote_as_user('modify-user'),
		'user modification is allowed for non-master API users');
	ok(!&can_remote_as_user('list-users'),
		'unaudited core commands remain denied');
	is(&get_user_remote_api_command('list-databases'),
		'can_edit_databases', 'database capability is registered');
	is(&get_user_remote_api_command('list-proxies'),
		'can_edit_forward', 'proxy capability is registered');
	is(&get_user_remote_api_command('list-redirects'),
		'can_edit_redirect', 'redirect capability is registered');
	is(&get_user_remote_api_command('modify-user'),
		'can_edit_users', 'user modification capability is registered');
	}

{
	no warnings qw(once redefine);
	local *main::master_admin = sub { 0 };
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
		{ 'allowed' => 1 }, 'list-users.pl'),
		'unaudited command is denied at the domain boundary');

	local *main::can_edit_users = sub { 0 };
	ok(!&remote_api_can_domain(
		{ 'allowed' => 1 }, 'modify-user.pl'),
		'owned domain is denied without user management capability');

	my ($status, $out) = &run_domain_guard(
		{ 'allowed' => 1 }, 'example.test', 'list-databases.pl');
	ok($status, 'missing capability exits with a failure');
	is($out,
		"You are not allowed to run this command for virtual server example.test\n",
		'missing capability returns a clear permission error');

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
	like($guard[2], qr/remote-api-access\.t$/,
		'calling command is passed to the authorization guard');
	}

foreach my $command (
	qw(list-databases.pl list-proxies.pl list-redirects.pl modify-user.pl)
	) {
	my $path = File::Spec->catfile($root, $command);
	open(my $fh, '<', $path) || die "Cannot read $path: $!";
	local $/ = undef;
	my $source = <$fh>;
	close($fh);
	like($source, qr/get_remote_api_domain\s*\("dom",\s*\$domain\)/,
		"$command uses the shared domain boundary");
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
