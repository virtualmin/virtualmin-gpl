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
	WebminCore->import(qw(open_beneath is_under_directory));
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

# Exercise the actual file listing, with ownership and mode changes recorded.
{
	local $main::config{'homes_dir'} = 'homes';
	my (@users, @perms);
	local *POSIX::lchown = sub { push(@calls, [ getcwd(), @_ ]); return 1 };
	local *main::list_domain_users = sub { @users };
	local *main::get_domain_by = sub { () };
	local *main::virtual_server_directories = sub { [ 'homes', '755', 'homes' ] };
	local *main::open_execute_command = sub {
		open(main::FIND, '-|', '/bin/sh', '-c', $_[1]) or die $!;
		};
	local *main::set_php_wrappers_writable = sub { };
	local *main::set_ownership_permissions = sub {
		push(@perms, [ getcwd(), @_ ]) if (defined($_[2]));
		};
	my $domain = { home => $base, uid => 1234, gid => 1235 };
	my $homes = "$base/homes";
	mkdir($homes) or die $!;
	my $mailbox = "$homes/mailuser";
	mkdir($mailbox) or die $!;
	push(@users, { unix => 1, home => $mailbox, uid => 1236, gid => 1235 });
	my $file = "invoice\n2025";
	foreach my $dir ($base, $mailbox) {
		open(my $fh, '>', "$dir/$file") or die $!;
		close($fh) or die $!;
		}
	symlink($file, "$mailbox/mail-link") or die $!;
	my $custom = "$base/ftp[1]";
	mkdir($custom) or die $!;
	push(@users, { unix => 1, home => $custom, uid => 1237, gid => 1235 });
	open(my $marker, '>', "$base/.nodelete") or die $!;
	close($marker) or die $!;
	@calls = ();
	my @changes = main::set_home_ownership($domain);
	is_deeply([ sort map { $_->[0] } grep { $_->[0] =~ /\Q$file\E\z/ } @changes ],
		  [ sort ("$base/$file", "$mailbox/$file") ],
		  'owner and mailbox reports each keep a multiline filename intact');
	is_deeply([ grep { $_->[-1] eq $file } @calls ],
		  [ [ $base, 1234, 1235, $file ], [ $mailbox, 1236, 1235, $file ] ],
		  'each multiline name is repaired inside its own directory');
	ok(!grep({ $_->[-1] eq 'mail-link' } @calls), 'repair leaves mailbox links alone');
	is_deeply([ grep { $_->[0] eq $custom || $_->[-1] eq 'ftp[1]' ||
			   $_->[-1] eq '.nodelete' } @calls ], [],
		  'repair leaves custom user homes and .nodelete alone');
	is_deeply(\@perms, [ [ $homes, $domain->{uid}, $domain->{gid}, 0755, '.' ] ],
		  'restore sets the owner and mode inside the verified homes directory');
	rename($homes, "$base/saved-homes") && symlink('domains', $homes) or die $!;
	@perms = ();
	main::set_home_ownership($domain);
	is_deeply(\@perms, [], 'restore skips the shared directory when it is a link');

	local *main::virtual_server_directories = sub { [ 'cgi-bin', '750', 'cgi' ] };
	my $cgi = "$base/cgi-bin";
	mkdir($cgi) or die $!;
	main::set_home_ownership($domain);
	is_deeply(\@perms, [ [ $cgi, undef, undef, 0750, '.' ] ],
		  'repair sets the configured mode inside the CGI directory');
	rmdir($cgi) && symlink('domains', $cgi) or die $!;
	@perms = ();
	main::set_home_ownership($domain);
	is_deeply(\@perms, [], 'repair skips the CGI directory when it is a link');

	@messages = ();
	main::set_home_ownership({ %$domain, parent => '123', home => $external });
	is_deeply(\@messages, [ "fixperms_ehome $external" ],
		  'repair reports a sub-server home outside its parent');
}

done_testing();
