#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path getcwd);
use File::Temp qw(tempdir);
use FindBin;

my ($webmin) = grep { defined($_) && -r "$_/WebminCore.pm" }
	$ENV{'WEBMIN_ROOT'}, "$FindBin::Bin/../..", "$FindBin::Bin/../../webmin";
plan skip_all => 'Set WEBMIN_ROOT to the Webmin source tree' if (!$webmin);
{
	local @INC = ($webmin, @INC);
	require WebminCore;
	WebminCore->import('open_beneath');
}

require "$FindBin::Bin/../feature-dir.pl";
require "$FindBin::Bin/../security-lib.pl";
require "$FindBin::Bin/../virtual-server-lib-funcs.pl";

my $base = abs_path(tempdir(CLEANUP => 1));
my $domains = "$base/domains";
mkdir($domains) or die $!;
my $child = { parent => '123', home => "$domains/child" };
mkdir($child->{home}) or die $!;
my $parent = { home => $base };
my (@calls, @messages);
my $cwd = getcwd();

# Record the directory where removal or ownership changes would run.
no warnings qw(once redefine);
local $main::first_print = sub { };
local $main::second_print = sub { push(@messages, @_) };
local *main::require_useradmin = sub { };
local *main::safe_delete_dir = sub { 1 };
local *main::is_readonly_mode = sub { 0 };
local *main::get_domain = sub { $parent };
local *main::backquote_logged = sub {
	push(@calls, [ getcwd(), @_ ]);
	$? = 0;
	return '';
	};
local *main::system_logged = sub { push(@calls, [ getcwd(), @_ ]); return 0 };
local *main::set_php_wrappers_writable = sub { push(@calls, [ getcwd(), 'wrappers' ]) };
local *main::html_escape = sub { $_[0] };
local *main::text = sub { join(' ', @_) };
local *main::error = sub { die "$_[0]\n" };
local *main::same_file = sub { $_[0] eq $_[1] };
local $main::text{'setup_done'} = 'done';

ok(main::delete_dir($child), 'sub-server deletion succeeds');
is_deeply([ map { $_->[0] } @calls ], [ $domains ],
	'removal runs from inside the verified parent directory');
is($calls[0]->[1], "rm -rf -- './child' 2>&1", 'removal uses only the final name');
is(getcwd(), $cwd, 'original working directory restored');
{
	local $child->{home} = "$base/./domains/child";
	ok(main::delete_dir($child), 'a relative component naming the same directory is valid');
}

# Mail restore changes ownership from inside the mailbox it verified.
@calls = ();
my $user = { home => $child->{home}, uid => 1234, gid => 1235 };
main::set_mailbox_home_owner($child, $user);
is_deeply(\@calls, [ [ $child->{home}, 'chown', '-hRP', '1234:1235', '.' ] ],
	'restored ownership is limited to the open mailbox');
{
	local *main::system_logged = sub { return 256 };
	is(eval { main::set_mailbox_home_owner($child, $user) }, 0,
	   'an ownership failure lets the caller continue');
	is($messages[-1], "user_ehomeowner $user->{home}",
	   'the restore output identifies the affected mailbox');
}
{
	local $user->{home} = "$domains/missing";
	@calls = ();
	is(eval { main::set_mailbox_home_owner($child, $user) }, 0,
	   'a home that cannot be opened is skipped');
	is_deeply(\@calls, [], 'a skipped home reaches no ownership command');
	is($messages[-1], "user_ehomeowner $user->{home}", 'the skipped home is reported');
}
{
	local *main::delete_btrfs_user_home = sub { undef };
	local *main::system_logged = sub { return 256 };
	like(eval { main::delete_user_home($user, $parent) }, qr/user_edeletehome/,
	     'returns a warning so the caller can finish deleting the account');
}
{
	local *main::delete_btrfs_user_home = sub { 'Btrfs removal failed' };
	is(eval { main::delete_user_home($user, $parent) }, 'Btrfs removal failed',
	   'returns a subvolume error to the caller');
}
{
	local $user->{home} = "$base/direct";
	mkdir($user->{home}) or die $!;
	local *main::delete_btrfs_user_home = sub { undef };
	@calls = ();
	is(main::delete_user_home($user, $parent), undef,
	   'a direct child home can be removed');
	is_deeply(\@calls, [ [ $base, 'rm', '-rf', '--', 'direct' ] ],
	          'a direct child is removed from the domain home');
}
@calls = ();
symlink('domains', "$base/shortcut") or die $!;
$child->{home} = "$base/shortcut/child";
ok(!main::delete_dir($child), 'a directory link in the path is refused');
is_deeply(\@calls, [], 'refused path reaches no filesystem command');
is($messages[-1], "delete_ehomepath $child->{home}",
	'refusal identifies the home left in place');

my $external = abs_path(tempdir(CLEANUP => 1));
$child->{home} = $external;
ok(!main::delete_dir($child), "a sub-server home outside the owner's home is kept");
is_deeply(\@calls, [], 'no removal command runs for the external home');

done_testing();
