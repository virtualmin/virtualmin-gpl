#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));

{
package virtual_server;
our (%config, %text, $home_virtualmin_backup, $master, $reseller, @ssh_calls,
     @unlinked, @user_unlinked, @servers, $first_print, $second_print,
     $indent_print, $outdent_print);
$home_virtualmin_backup = 'virtualmin-backup';
%text = ( 'backup_emode' => 'emode', 'backup_edest' => 'edest',
	  'backup_edest2' => 'edest2', 'backup_edest3' => 'edest3' );
$first_print = $second_print = $indent_print = $outdent_print = sub { };
# Fixture permissions and services leave the backup library logic real.
sub master_admin { return $master; }
sub reseller_admin { return $reseller; }
sub get_default_s3_account { return undef; }
sub cloud_google_get_state { return { 'ok' => 1 }; }
sub cloud_bb_get_state { return { 'ok' => 1 }; }
sub cloud_azure_get_state { return { 'ok' => 1 }; }
sub cloud_drive_get_state { return { 'ok' => 1 }; }
sub get_current_dir { return '/'; }
sub check_ip6address { return 0; }
sub text { return join(' ', @_); }
sub html_escape { return $_[0]; }
sub make_date { return $_[0]; }
sub nice_size { return $_[0]; }
sub disk_usage_kb { return 1; }
sub split_path_file { return $_[0] =~ /^(.*)\/([^\/]+)$/ ? ($1, $2) : $_[0]; }
sub unlink_file { push(@unlinked, @_); return 1; }
sub unlink_logged { push(@unlinked, $_[0]); return 1; }
sub unlink_file_as_domain_user {
push(@user_unlinked, [ @_ ]);
return 1;
}
sub run_ssh_command { push(@ssh_calls, [ @_ ]); return undef; }
sub remote_error_setup { }
sub foreign_require { }
sub compression_to_suffix { return 'tar.gz'; }
sub get_domains_by_names {
return map {
	$_ eq 'sub.test' ?
		{ 'dom' => $_, 'user' => 'subowner', 'parent' => 10 } :
		{ 'dom' => $_, 'user' => 'owner' }
	} @_;
}
my $loaded = do "$root/backups-lib.pl";
die $@ if ($@);
die "Failed to load backups-lib.pl: $!" if (!defined($loaded));
}
{
package servers;
sub list_servers { return @virtual_server::servers; }
}

my $dir = tempdir(CLEANUP => 1);
my $home = "$dir/home";
mkdir($home) || die $!;
my $d = { 'home' => $home, 'user' => 'owner' };

# Owner destinations are confined to the domain's own backup directory.
$virtual_server::master = 0;
my ($conf, $err) = virtual_server::confine_backup_dest("x.tar.gz", 2, $d);
is($conf, "$home/virtualmin-backup/x.tar.gz",
	'plain owner destination is confined under the backup directory');
($conf, $err) = virtual_server::confine_backup_dest("../x.tar.gz", 2, $d);
ok(!$conf && $err, 'owner destination cannot leave the backup directory');

# Cloud providers require the matching per-user permission.
my %providers = ( 'gcs://bucket/path' => [ 'google', 7 ],
		  'dropbox://folder/path' => [ 'dropbox', 8 ],
		  'bb://bucket/path' => [ 'bb', 10 ],
		  'azure://container/path' => [ 'azure', 11 ],
		  'drive://folder' => [ 'drive', 12 ] );
foreach my $url (sort keys %providers) {
	my ($key, $mode) = @{$providers{$url}};
	%virtual_server::config = ( );
	my @rv = virtual_server::parse_backup_url($url);
	ok($rv[0] == -1 && $rv[1] =~ /cannot be used/,
		"$key is refused without permission");
	$virtual_server::config{'cloud_'.$key.'_owner'} = 1;
	@rv = virtual_server::parse_backup_url($url);
	is($rv[0], $mode, "$key is accepted with owner permission");
	%virtual_server::config = ( );
	$virtual_server::master = 1;
	@rv = virtual_server::parse_backup_url($url);
	is($rv[0], $mode, "$key is always accepted for the master");
	$virtual_server::master = 0;
	}

# Remote file listing code keeps the directory as data, not code.
my $quoted = "$dir/it's \\ \"odd\" dir";
mkdir($quoted) || die $!;
foreach my $f ("a.info", "b.info", "c.dom") {
	open(my $fh, '>', "$quoted/$f") || die $!;
	close($fh);
	}
my $code = virtual_server::remote_glob_code($quoted, ".info");
my $list = eval $code;
is($@, '', 'generated listing code compiles with quotes and backslashes');
is_deeply([ sort @$list ], [ "$quoted/a.info", "$quoted/b.info" ],
	'generated listing code finds only matching files');
$code = virtual_server::remote_glob_code("$dir/none'; die 'injected", "");
$list = eval $code;
is($@, '', 'quote characters in the directory cannot alter the code');
is_deeply($list, [ ], 'unmatched directory lists nothing');

# Stored Webmin server logins are only used by the master administrator.
@virtual_server::servers = ( { 'host' => 'backup.test', 'port' => 10000,
			       'user' => 'root', 'pass' => 'stored' } );
$virtual_server::master = 0;
my $w = virtual_server::dest_to_webmin("webmin://backup.test:/srv/backups");
ok(!$w->{'user'} && !$w->{'pass'},
	'owners do not inherit stored Webmin server credentials');
$virtual_server::master = 1;
$w = virtual_server::dest_to_webmin("webmin://backup.test:/srv/backups");
is($w->{'user'}, 'root', 'master still uses the stored login');

# The cron entry point runs scheduled backups with the owner's permissions.
foreach my $mode (1, 2, 3) {
	no warnings qw(once redefine);
	local $INC{'./virtual-server-lib.pl'} = 1;
	local @ARGV = ( );
	local $virtual_server::asd;
	local $virtual_server::owner;
	local $virtual_server::remote_user = 'root';
	local $virtual_server::base_remote_user = 'root';
	local $virtual_server::backups_log_dir = $dir;
	local %virtual_server::access = ( );
	local %virtual_server::config = ( );
	my $owner = $mode == 1 ? 'root' : $mode == 2 ? 'owner' : 'reseller';
	local *virtual_server::get_system_hostname = sub { 'fixture.test' };
	local *virtual_server::foreign_check = sub { 0 };
	local *virtual_server::list_scheduled_backups = sub {
		return { id => 1, all => 1, features => '', ownrestore => 0,
			owner => $mode == 1 ? undef : $mode == 2 ? 10 : $owner };
		};
	local *virtual_server::obtain_lock_anything = sub { };
	local *virtual_server::start_running_backup = sub { };
	local *virtual_server::stop_running_backup = sub { };
	local *virtual_server::cleanup_backup_limits = sub { };
	local *virtual_server::webmin_log = sub { };
	local *virtual_server::get_domain = sub { $_[0] eq '10' ? $d : undef };
	local *virtual_server::list_domains = sub {
		return ({ dom => 'a.test', user => 'owner' },
			{ dom => 'b.test', user => 'other' });
		};
	local *virtual_server::can_backup_domain = sub {
		return $mode if (!$_[0]);
		return $mode != 2 || $_[0]->{'user'} eq $owner;
		};
	local *virtual_server::get_module_acl = sub { ( noconfig => 1 ) };
	local *virtual_server::master_admin = sub {
		!$virtual_server::access{'noconfig'};
		};
	local *virtual_server::get_scheduled_backup_dests = sub {
		'ssh://backup.test:/backup.tar.gz';
		};
	local *virtual_server::get_scheduled_backup_purges = sub { ( ) };
	local *virtual_server::backup_domains = sub {
		is(!!$_[10], !!($mode == 2),
			"mode $mode runs as the Unix user only for domain owners");
		is($virtual_server::base_remote_user, $owner,
			"mode $mode runs with the schedule owner's ACL");
		is(virtual_server::master_admin() ? 1 : 0, $mode == 1 ? 1 : 0,
			"mode $mode master access follows the schedule owner");
		return (1, 100, [ ]);
		};
	local *virtual_server::write_file = sub { };
	do "$root/backup.pl";
	die $@ if ($@);
	}

done_testing();
