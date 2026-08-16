#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $lib = File::Spec->catfile($root, 'btrfs-lib.pl');
my $loaded = do $lib;
die $@ if ($@);
die "Failed to load $lib: $!" if (!defined($loaded));

# The production library gets these helpers from Virtualmin and Webmin.
{
	no warnings qw(redefine once);
	*main::require_useradmin = sub { };
	*main::is_under_directory = sub {
		my ($dir, $file) = @_;
		return 1 if ($dir eq "/" || $dir eq $file);
		$dir =~ s/\/*$/\//;
		return index($file, $dir) == 0;
		};
}

# Load the real English messages so unit tests also catch missing language keys.
my $lang = File::Spec->catfile($root, 'lang', 'en');
open(my $langfh, '<', $lang) or die "Failed to read $lang: $!";
while(my $line = <$langfh>) {
	chomp($line);
	my ($key, $value) = split(/=/, $line, 2);
	$main::text{$key} = $value if (defined($value));
	}
close($langfh);
{
	no warnings qw(redefine once);
	*main::text = sub {
		my ($key, @args) = @_;
		my $message = $main::text{$key};
		return undef if (!defined($message));
		$message =~ s/\$(\d+)/defined($args[$1-1]) ? $args[$1-1] : ''/ge;
		return $message;
		};
}

# Full qgroup accounting is the normal baseline for lifecycle unit tests.
{
	no warnings qw(redefine once);
	*quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'mode' => 'qgroup', 'inconsistent' => 0 };
		};
}

is(&btrfs_quota_blocks_to_bytes(1024), 1048576,
	'Virtualmin blocks are converted to Btrfs bytes');
is(&btrfs_quota_bytes_to_blocks(1025), 2,
	'partial Btrfs usage blocks are rounded up');
ok(!defined(&btrfs_quota_blocks_to_bytes(0)),
	'zero quota removes the qgroup limit');

# Runtime operations must explain incompatible simple quotas before mutation.
{
	no warnings qw(redefine once);
	local $main::webmin_script_type = 'cmd';
	local $ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => '/quota-test',
		);
	local $main::home_base = '/quota-test';
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'mode' => 'squota', 'inconsistent' => 1 };
		};
	my ($subvolume_checks, $rescans) = (0, 0);
	local *quota::btrfs_subvolume_id = sub { $subvolume_checks++; return 256; };
	local *quota::rescan_btrfs_quotas = sub { $rescans++; return undef; };
	my ($err, $created) = &ensure_btrfs_subvolume(
		'/quota-test/example', {
			'id' => 1700000000123456,
			'home' => '/quota-test/example',
			});
	is($err,
		'cannot apply domain quotas while /quota-test uses Btrfs simple '.
		'quota mode; ensure full qgroup accounting is selected in the Disk '.
		'Quotas module, then disable and re-enable Btrfs quotas, run the '.
		'configuration check, and try again',
		'simple quota mode returns a plain actionable runtime error');
	ok(!$created, 'simple quota mode does not create a subvolume');
	is($subvolume_checks, 0,
		'simple quota mode is rejected before inspecting the layout');
	is($rescans, 0, 'simple quota mode is rejected before an invalid rescan');
}

# Authorized browser sessions should receive a direct configuration link.
{
	no warnings qw(redefine once);
	local $main::webmin_script_type = 'web';
	local *main::foreign_available = sub { return $_[0] eq 'quota'; };
	local *main::get_module_acl = sub { return ( 'noconfig' => 0 ); };
	local *main::get_webprefix = sub { return '/webmin'; };
	local *main::html_escape = sub { return $_[0]; };
	local *main::ui_tag = sub {
		return '<'.$_[0].'>'.$_[1].'</'.$_[0].">\n";
		};
	local *main::ui_link = sub {
		return '<a href="'.$_[0].'">'.$_[1].'</a>';
		};
	my $err = &btrfs_simple_quota_error('/home');
	like($err, qr{while <tt>/home</tt> uses},
		'UI error formats the filesystem path as literal text');
	like($err,
		qr{in the <a href="/webmin/config\.cgi\?module=quota">Disk Quotas module</a>},
		'UI error links to accessible Disk Quotas module configuration');
}

# The error must remain plain text when module configuration is forbidden.
{
	no warnings qw(redefine once);
	local $main::webmin_script_type = 'web';
	local *main::foreign_available = sub { return 1; };
	local *main::get_module_acl = sub { return ( 'noconfig' => 1 ); };
	local *main::html_escape = sub { return $_[0]; };
	local *main::ui_tag = sub {
		return '<'.$_[0].'>'.$_[1].'</'.$_[0].">\n";
		};
	my $err = &btrfs_simple_quota_error('/home');
	unlike($err, qr/<a\b/, 'UI error omits an inaccessible configuration link');
}

# Virtualmin should use Webmin's mount mapping when indexing qgroups by path.
{
	no warnings qw(redefine once);
	local %main::config = ( 'home_quotas' => '/home' );
	local $main::home_base = '/home';
	local $main::btrfs_qgroups_cache;
	local $main::btrfs_qgroups_by_id_cache;
	local $main::btrfs_qgroups_by_path_cache;
	local *quota::list_btrfs_qgroups = sub {
		return [ { 'id' => '0/256', 'path' => '@home/example' } ];
		};
	my (@mount_args, @path_args);
	local *quota::btrfs_mountinfo = sub {
		@mount_args = @_;
		return ('/home', '/@home');
		};
	local *quota::btrfs_qgroup_absolute_path = sub {
		@path_args = @_;
		return '/home/example';
		};
	my $qgroups = &list_btrfs_qgroups(0, undef);
	is_deeply(\@mount_args, [ '/home' ],
		'quota module resolves the Btrfs mount layout');
	is_deeply(\@path_args, [ '/home', '/@home', '@home/example' ],
		'quota module converts the filesystem-relative qgroup path');
	is($main::btrfs_qgroups_by_path_cache->{'/home/example'}, $qgroups->[0],
		'resolved qgroup path is indexed for Virtualmin');
}

my $object = { };
&apply_btrfs_quota($object, {
	'referenced' => 1048577,
	'max_referenced' => 2097152,
	});
is($object->{'uquota'}, 1025, 'referenced bytes become used blocks');
is($object->{'hardquota'}, 2048, 'referenced limit becomes hard blocks');
is($object->{'softquota'}, 2048,
	'Btrfs limit remains visible for soft-quota templates');

my $tmp = tempdir(CLEANUP => 1);
my $domainhome = "$tmp/domain-root";
my $newhome = "$tmp/example";
my @command;
# New mailbox homes should inherit their parent qgroup atomically.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::ensure_btrfs_parent_qgroup = sub {
		return undef;
		};
	local *quota::btrfs_subvolume_id = sub {
		return $_[0] eq $domainhome ? 256 : undef;
		};
	local *quota::run_btrfs_command = sub {
		my ($logged, @args) = @_;
		@command = @args;
		return ('', undef);
		};
	local *quota::rescan_btrfs_quotas = sub { return undef; };
	my ($err, $created) = &ensure_btrfs_subvolume(
		$newhome, {
			'id' => 1700000000123456,
			'home' => $domainhome,
			});
	is($err, undef, 'new Btrfs mailbox home can be prepared');
	ok($created, 'new Btrfs mailbox home reports subvolume creation');
}
is_deeply(\@command,
	[ 'subvolume', 'create', '-i', '1/256', $newhome ],
	'mailbox subvolume is atomically attached to its domain parent qgroup');

# Sub-server users should resolve to the top-level quota owner.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1 );
	my $top = {
		'id' => 1700000000123456,
		'home' => $domainhome,
		};
	my $sub = {
		'id' => 1700000000123457,
		'parent' => $top->{'id'},
		'home' => "$domainhome/domains/sub.example",
		};
	local *main::get_domain = sub { return $top; };
	my @prepared;
	local *main::ensure_btrfs_subvolume = sub {
		@prepared = @_;
		return (undef, 1);
		};
	my $user = {
		'user' => 'submailbox',
		'home' => "$domainhome/homes/submailbox",
		};
	my ($err, $created) = &ensure_btrfs_user_home($user, $sub);
	is($err, undef, 'sub-server mailbox home can be prepared');
	ok($created, 'sub-server mailbox uses Btrfs subvolume creation');
	is_deeply(\@prepared, [ $user->{'home'}, $top ],
		'sub-server mailbox is attached to the top-level domain qgroup');
}
# Parent IDs must fit Btrfs's 48-bit qgroup object-ID field.
{
	no warnings qw(redefine once);
	local *quota::btrfs_subvolume_id = sub { return 987654; };
	is(&btrfs_quota_parent_id({
		'id' => 1700000000123456,
		'home' => $domainhome,
		}), '1/987654',
		'parent qgroup uses the 48-bit subvolume ID, not Virtualmin domain ID');
}
# Domain roots need their subvolume ID before the aggregate can be created.
{
	no warnings qw(redefine once);
	my $newdomain = "$tmp/new-domain";
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::ensure_btrfs_parent_qgroup = sub {
		return undef;
		};
	local *main::get_btrfs_qgroup_by_path = sub {
		return { 'id' => '0/401', 'parents' => [ ] };
		};
	my $created_on_disk = 0;
	local *quota::btrfs_subvolume_id = sub {
		return $created_on_disk ? 401 : undef;
		};
	my (@domain_command, @assigned, @rescanned);
	local *quota::run_btrfs_command = sub {
		my ($logged, @args) = @_;
		@domain_command = @args;
		$created_on_disk = 1;
		return ('', undef);
		};
	local *quota::assign_btrfs_qgroup = sub {
		@assigned = @_;
		return undef;
		};
	local *quota::rescan_btrfs_quotas = sub {
		@rescanned = @_;
		return undef;
		};
	my ($err, $created) = &ensure_btrfs_subvolume(
		$newdomain, {
			'id' => 1700000000654321,
			'home' => $newdomain,
			});
	is($err, undef, 'new domain home can be prepared');
	ok($created, 'new domain home reports subvolume creation');
	is_deeply(\@domain_command,
		[ 'subvolume', 'create', $newdomain ],
		'domain subvolume is created before its ID-derived parent qgroup');
	is_deeply(\@assigned, [ $tmp, '0/401', '1/401' ],
		'domain root is assigned to its collision-free parent qgroup');
	is_deeply(\@rescanned, [ $tmp, 1 ],
		'domain root assignment waits for consistent accounting');
}
# Existing subvolumes should be relinked without being recreated.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::ensure_btrfs_parent_qgroup = sub {
		return undef;
		};
	local *main::get_btrfs_qgroup_by_path = sub {
		return { 'id' => '0/300', 'parents' => [ ] };
		};
	local *quota::btrfs_subvolume_id = sub {
		return $_[0] eq $domainhome ? 256 : 300;
		};
	my (@assigned, @rescanned);
	local *quota::assign_btrfs_qgroup = sub {
		@assigned = @_;
		return undef;
		};
	local *quota::rescan_btrfs_quotas = sub {
		@rescanned = @_;
		return undef;
		};
	my ($err, $created) = &ensure_btrfs_subvolume(
		"$tmp/existing-subvolume", {
			'id' => 1700000000234,
			'home' => $domainhome,
			});
	is($err, undef, 'an existing subvolume can join a domain qgroup');
	ok(!$created, 'an existing subvolume is not recreated');
	is_deeply(\@assigned,
		[ $tmp, '0/300', '1/256' ],
		'existing subvolume is assigned to the domain parent');
	is_deeply(\@rescanned, [ $tmp, 1 ],
		'qgroup assignment waits for accounting to become consistent');
}
# A coincidentally matching external qgroup must never be adopted.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::btrfs_subvolume_id = sub { return 256; };
	local *main::list_btrfs_qgroups = sub {
		$main::btrfs_qgroups_by_id_cache = {
			'1/256' => {
				'id' => '1/256',
				'children' => [ '0/999' ],
				},
			'0/999' => {
				'id' => '0/999',
				'virtualmin_path' => '/srv/unrelated',
				},
			};
		return [ values(%{$main::btrfs_qgroups_by_id_cache}) ];
		};
	my $err = &ensure_btrfs_parent_qgroup({
		'id' => 1700000000234,
		'home' => $domainhome,
		});
	like($err, qr/already used outside/,
		'an unrelated pre-existing parent qgroup is never adopted');
}

my $legacy = "$tmp/legacy";
mkdir($legacy) or die "mkdir($legacy): $!";
open(my $fh, '>', "$legacy/file") or die "create legacy file: $!";
print {$fh} "data\n";
close($fh);
# Populated ordinary directories must be left for explicit migration.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::ensure_btrfs_parent_qgroup = sub {
		return undef;
		};
	local *quota::btrfs_subvolume_id = sub {
		return $_[0] eq $domainhome ? 256 : undef;
		};
	my ($err, $created) = &ensure_btrfs_subvolume(
		$legacy, {
			'id' => 1700000000456,
			'home' => $domainhome,
			});
	is($err, "existing home $legacy is not a Btrfs subvolume",
		'legacy-home error begins lowercase after the failure prefix');
	ok(!$created, 'legacy directory is left untouched');
	{
	local $main::webmin_script_type = 'web';
	local *main::html_escape = sub { return $_[0]; };
	local *main::ui_tag = sub {
		return '<'.$_[0].'>'.$_[1].'</'.$_[0].">\n";
		};
	my ($web_err) = &ensure_btrfs_subvolume(
		$legacy, {
			'id' => 1700000000456,
			'home' => $domainhome,
			});
	is($web_err, "existing home <tt>$legacy</tt> is not a Btrfs subvolume",
		'legacy-home path is formatted as literal text in the UI');
	}
}
ok(-f "$legacy/file", 'legacy home contents are preserved');

# Domains created before Btrfs quotas keep working: their mailboxes stay
# ordinary directories without limits instead of failing user creation.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1, 'home_quotas' => $tmp );
	my $legacy_domain_home = "$tmp/legacy-domain";
	my $legacy_mailbox = "$legacy_domain_home/homes/mailbox";
	mkdir($legacy_domain_home) or die "mkdir($legacy_domain_home): $!";
	mkdir("$legacy_domain_home/homes") or
		die "mkdir($legacy_domain_home/homes): $!";
	my $domain = { 'id' => 1700000000460, 'home' => $legacy_domain_home };
	my $user = { 'user' => 'mailbox', 'home' => $legacy_mailbox };
	local *main::btrfs_quota_domain = sub { return $_[0]; };
	local *quota::btrfs_subvolume_id = sub { return undef; };
	my $prepared = 0;
	local *main::ensure_btrfs_subvolume = sub {
		$prepared++;
		return ('must not be called', 0);
		};
	my $limited = 0;
	local *main::set_btrfs_qgroup_limit = sub {
		$limited++;
		return undef;
		};
	my ($err, $created) = &ensure_btrfs_user_home($user, $domain);
	is($err, undef, 'mailbox creation succeeds in a pre-quota domain');
	ok(!$created, 'pre-quota domain mailbox stays an ordinary directory');
	mkdir($legacy_mailbox) or die "mkdir($legacy_mailbox): $!";
	is(&set_btrfs_home_quota($legacy_mailbox, 4096, $domain), undef,
		'mailbox quota is skipped in a pre-quota domain');
	open(my $mfh, '>', "$legacy_mailbox/mail") or die $!;
	print {$mfh} "mail\n";
	close($mfh);
	is(&convert_btrfs_restored_user_home($user, $domain), undef,
		'restore leaves pre-quota domain mailboxes unconverted');
	ok(-f "$legacy_mailbox/mail", 'pre-quota mailbox data is untouched');
	is($prepared, 0, 'pre-quota domain never attempts subvolume creation');
	is($limited, 0, 'pre-quota domain never applies a qgroup limit');
}

# Full restores explicitly convert populated mailbox directories while keeping
# normal creation's refusal above intact.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1 );
	my $restore_root = "$tmp/restore-domain";
	my $restore_home = "$restore_root/homes/restored-user";
	mkdir($restore_root) or die "mkdir($restore_root): $!";
	mkdir("$restore_root/homes") or die "mkdir($restore_root/homes): $!";
	mkdir($restore_home) or die "mkdir($restore_home): $!";
	open(my $rfh, '>', "$restore_home/mail-data") or
		die "create restored mailbox data: $!";
	print {$rfh} "restored\n";
	close($rfh);
	open(my $dfh, '>', "$restore_home/.mail-settings") or
		die "create restored dotfile: $!";
	print {$dfh} "settings\n";
	close($dfh);
	my $domain = { 'id' => 1700000000457, 'home' => $restore_root };
	my $user = { 'home' => $restore_home };
	my $is_subvolume = 0;
	local *main::btrfs_quota_domain = sub { return $domain; };
	local *quota::btrfs_subvolume_id = sub {
		return 456 if ($_[0] eq $restore_root);
		return $is_subvolume ? 457 : undef;
		};
	local *main::ensure_btrfs_user_home = sub {
		mkdir($restore_home) or die "mkdir restored subvolume: $!";
		$is_subvolume = 1;
		return (undef, 1);
		};
	my $copy_command;
	local *main::system_logged = sub {
		$copy_command = $_[0];
		my ($holding) = glob($restore_home.
			'.virtualmin-btrfs-restore-*');
		foreach my $name ('mail-data', '.mail-settings') {
			open(my $src, '<', "$holding/$name") or die $!;
			open(my $dst, '>', "$restore_home/$name") or die $!;
			while(read($src, my $buffer, 8192)) {
				print {$dst} $buffer;
				}
			close($src);
			close($dst);
			}
		return 0;
		};
	local *main::unlink_file = sub {
		my ($holding) = @_;
		unlink("$holding/mail-data", "$holding/.mail-settings");
		return (rmdir($holding), $!);
		};
	my $err = &convert_btrfs_restored_user_home($user, $domain);
	is($err, undef, 'restore converts a populated mailbox into a subvolume');
	ok($is_subvolume, 'restore creates the mailbox subvolume explicitly');
	like($copy_command, qr/\bcp -a --reflink=always --/,
		'restore uses a mandatory same-filesystem Btrfs reflink');
	ok(-f "$restore_home/mail-data", 'restored mailbox content is preserved');
	ok(-f "$restore_home/.mail-settings", 'restored dotfiles are preserved');
	my @holding = glob($restore_home.'.virtualmin-btrfs-restore-*');
	is(scalar(@holding), 0, 'successful conversion removes its staging copy');
}

# A subvolume creation failure must atomically restore the original directory.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1 );
	my $restore_root = "$tmp/failed-restore-domain";
	my $restore_home = "$restore_root/homes/restored-user";
	mkdir($restore_root) or die "mkdir($restore_root): $!";
	mkdir("$restore_root/homes") or die "mkdir($restore_root/homes): $!";
	mkdir($restore_home) or die "mkdir($restore_home): $!";
	open(my $fh, '>', "$restore_home/original-data") or die $!;
	print {$fh} "untouched\n";
	close($fh);
	my $domain = { 'id' => 1700000000458, 'home' => $restore_root };
	my $user = { 'home' => $restore_home };
	local *main::btrfs_quota_domain = sub { return $domain; };
	local *quota::btrfs_subvolume_id = sub {
		return $_[0] eq $restore_root ? 458 : undef;
		};
	local *main::ensure_btrfs_user_home = sub {
		return ('simulated subvolume creation failure', 0);
		};
	my $err = &convert_btrfs_restored_user_home($user, $domain);
	like($err, qr/simulated subvolume creation failure/,
		'conversion reports subvolume creation failure');
	ok(-f "$restore_home/original-data",
		'failed conversion restores the original mailbox directory');
	my @holding = glob($restore_home.'.virtualmin-btrfs-restore-*');
	is(scalar(@holding), 0, 'failed conversion leaves no staging directory');
}

# A reflink failure must delete the empty target and recover the parked source.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1 );
	my $restore_root = "$tmp/failed-copy-domain";
	my $restore_home = "$restore_root/homes/restored-user";
	mkdir($restore_root) or die "mkdir($restore_root): $!";
	mkdir("$restore_root/homes") or die "mkdir($restore_root/homes): $!";
	mkdir($restore_home) or die "mkdir($restore_home): $!";
	open(my $fh, '>', "$restore_home/original-data") or die $!;
	print {$fh} "untouched\n";
	close($fh);
	my $domain = { 'id' => 1700000000459, 'home' => $restore_root };
	my $user = { 'home' => $restore_home };
	my $is_subvolume = 0;
	local *main::btrfs_quota_domain = sub { return $domain; };
	local *quota::btrfs_subvolume_id = sub {
		return 458 if ($_[0] eq $restore_root);
		return $is_subvolume ? 459 : undef;
		};
	local *main::ensure_btrfs_user_home = sub {
		mkdir($restore_home) or die "mkdir restored subvolume: $!";
		$is_subvolume = 1;
		return (undef, 1);
		};
	local *main::system_logged = sub { return 1; };
	local *main::delete_btrfs_user_home = sub {
		$is_subvolume = 0;
		return rmdir($restore_home) ? undef : "delete failed: $!";
		};
	my $err = &convert_btrfs_restored_user_home($user, $domain);
	like($err, qr/failed to copy restored mailbox data/,
		'conversion reports a failed reflink');
	ok(-f "$restore_home/original-data",
		'failed reflink restores the untouched mailbox directory');
	my @holding = glob($restore_home.'.virtualmin-btrfs-restore-*');
	is(scalar(@holding), 0, 'failed reflink leaves no staging directory');
}

# Re-enabling quotas should rebuild direct and sub-server mailbox limits.
{
	no warnings qw(redefine once);
	my $mailbox = "$tmp/relinked-mailbox";
	my $child_mailbox = "$tmp/relinked-child-mailbox";
	mkdir($mailbox) or die "mkdir($mailbox): $!";
	mkdir($child_mailbox) or die "mkdir($child_mailbox): $!";
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::ensure_btrfs_domain_home = sub {
		return (undef, 0);
		};
	my $domain = {
		'id' => 1700000000555,
		'home' => $domainhome,
		};
	my $child = {
		'id' => 1700000000556,
		'parent' => $domain->{'id'},
		'home' => "$domainhome/domains/child",
		};
	my $grandchild = {
		'id' => 1700000000557,
		'parent' => $child->{'id'},
		'home' => "$domainhome/domains/child/domains/grandchild",
		};
	my $parent_user = {
		'user' => 'mailbox',
		'home' => $mailbox,
		'quota_cache' => 4096,
		};
	my $child_user = {
		'user' => 'child-mailbox',
		'home' => $child_mailbox,
		'quota_cache' => 8192,
		};
	my $grandchild_mailbox = "$tmp/relinked-grandchild-mailbox";
	mkdir($grandchild_mailbox) or die "mkdir($grandchild_mailbox): $!";
	my $grandchild_user = {
		'user' => 'grandchild-mailbox',
		'home' => $grandchild_mailbox,
		'quota_cache' => 12288,
		};
	local *main::get_domain_by = sub {
		return ($child) if ($_[1] eq $domain->{'id'});
		return ($grandchild) if ($_[1] eq $child->{'id'});
		return ( );
		};
	local *main::list_domain_users = sub {
		return $_[0]->{'id'} eq $domain->{'id'} ?
			($parent_user) :
		       $_[0]->{'id'} eq $child->{'id'} ?
			($child_user) : ($grandchild_user);
		};
	my (@relinked, @limits);
	local *main::ensure_btrfs_user_home = sub {
		push(@relinked, [ @_ ]);
		return (undef, 0);
		};
	local *main::btrfs_quota_parent_id = sub { return '1/256'; };
	local *main::set_btrfs_qgroup_limit = sub {
		push(@limits, [ @_ ]);
		return undef;
		};
	my $err = &set_btrfs_server_quotas(
		$domain, 1024, 2048);
	is($err, undef, 'server quota repairs the complete mailbox hierarchy');
	is_deeply(\@relinked, [
		[ $parent_user, $domain ],
		[ $child_user, $child ],
		[ $grandchild_user, $grandchild ],
		], 'all descendant mailbox qgroups are relinked');
	is_deeply(\@limits, [
		[ $mailbox, undef, 4096 ],
		[ $child_mailbox, undef, 8192 ],
		[ $grandchild_mailbox, undef, 12288 ],
		[ $domainhome, undef, 1024 ],
		[ $tmp, '1/256', 2048 ],
		], 'cached mailbox, owner, and aggregate limits are restored');
}

# Backups and restores toggle server quotas, so a pre-quota domain home must
# be skipped instead of failing those operations.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	my $legacy_domain_home = "$tmp/legacy-server-domain";
	mkdir($legacy_domain_home) or die "mkdir($legacy_domain_home): $!";
	local *quota::btrfs_subvolume_id = sub { return undef; };
	my ($prepared, $limited) = (0, 0);
	local *main::ensure_btrfs_domain_home = sub {
		$prepared++;
		return ('must not be called', 0);
		};
	local *main::set_btrfs_qgroup_limit = sub {
		$limited++;
		return undef;
		};
	my $err = &set_btrfs_server_quotas(
		{ 'id' => 1700000000558, 'home' => $legacy_domain_home }, 0, 0);
	is($err, undef, 'server quota toggling tolerates a pre-quota domain');
	is($prepared, 0, 'pre-quota domain home is not converted by quota toggling');
	is($limited, 0, 'pre-quota domain receives no qgroup limits');
}

# Mailbox creation applies its quota before the Unix passwd entry is present.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	my $home = "$tmp/pre-passwd-mailbox";
	mkdir($home) or die "mkdir($home): $!";
	my @calls;
	local *main::btrfs_quota_domain = sub { return $_[0]; };
	local *main::ensure_btrfs_subvolume = sub {
		push(@calls, [ 'ensure', @_ ]);
		return (undef, 0);
		};
	local *quota::btrfs_subvolume_id = sub { return 321; };
	local *main::set_btrfs_qgroup_limit = sub {
		push(@calls, [ 'limit', @_ ]);
		return undef;
		};
	my $domain = { 'home' => "$tmp/domain" };
	my $err = &set_btrfs_home_quota(
		$home, 8192, $domain);
	is($err, undef,
		'mailbox quota can be applied before its passwd entry exists');
is_deeply(\@calls, [
		[ 'ensure', $home, $domain ],
		[ 'limit', $home, undef, 8192 ],
		], 'pre-passwd mailbox path is prepared and limited directly');
}

# Quota listings must not execute one Btrfs lookup for every unrelated system
# account whose home happens to exist outside the configured home tree.
{
	no warnings qw(redefine once);
	local %main::config = ( 'home_quotas' => $tmp );
	local $main::home_base = $tmp;
	my $home = "$tmp/quota-list-mailbox";
	mkdir($home) or die "mkdir($home): $!";
	local *main::list_btrfs_qgroups = sub {
		$main::btrfs_qgroups_by_path_cache = { };
		$main::btrfs_qgroups_by_id_cache = { };
		return [ ];
		};
	my @lookups;
	local *main::get_btrfs_qgroup_by_path = sub {
		push(@lookups, $_[0]);
		return undef;
		};
	my @users = (
		{ 'home' => $home },
		{ 'home' => '/' },
		);
	is(&populate_btrfs_user_quotas(\@users), undef,
		'Btrfs user quotas can be populated without unrelated lookups');
	is_deeply(\@lookups, [ $home ],
		'fallback lookup stays within the configured home tree');
}

# Clearing quota during deletion must tolerate legacy or aborted-restore homes.
{
	no warnings qw(redefine once);
	local %main::config = ( 'btrfs_quotas' => 1 );
	my $home = "$tmp/ordinary-mailbox-to-delete";
	mkdir($home) or die "mkdir($home): $!";
	my $domain = { 'home' => "$tmp/domain" };
	local *main::btrfs_quota_domain = sub { return $_[0]; };
	local *quota::btrfs_subvolume_id = sub { return undef; };
	my $prepared = 0;
	local *main::ensure_btrfs_subvolume = sub {
		$prepared++;
		return ('must not be called', 0);
		};
	my $err = &set_btrfs_home_quota($home, 0, $domain, 1);
	is($err, undef, 'quota clearing accepts an ordinary mailbox directory');
	is($prepared, 0, 'quota clearing does not convert a home being deleted');
}

# Subvolume deletion should repair accounting marked inconsistent by Btrfs.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::run_btrfs_command = sub { return ('', undef); };
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 1 };
		};
	my @rescanned;
	local *quota::rescan_btrfs_quotas = sub {
		@rescanned = @_;
		return undef;
		};
	my $err = &delete_btrfs_subvolume(
		"$tmp/deleted-subvolume");
	is($err, undef, 'subvolume deletion repairs inconsistent accounting');
	is_deeply(\@rescanned, [ $tmp, 1 ],
		'subvolume deletion waits for the required qgroup rescan');
}
# Mailbox teardown should detach its qgroup before deleting the subvolume.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *main::require_useradmin = sub { };
	local *quota::btrfs_subvolume_id = sub { return 300; };
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 0 };
		};
	local *main::btrfs_quota_parent_id = sub { return '1/256'; };
	local *main::get_btrfs_qgroup_by_path = sub {
		return { 'id' => '0/300', 'parents' => [ '1/256' ] };
		};
	my (@unassigned, @deleted);
	local *quota::unassign_btrfs_qgroup = sub {
		@unassigned = @_;
		return undef;
		};
	local *main::delete_btrfs_subvolume = sub {
		@deleted = @_;
		return undef;
		};
	my $mailbox = "$domainhome/homes/delete-me";
	my $err = &delete_btrfs_user_home(
		{ 'home' => $mailbox },
		{ 'id' => 1700000000123456, 'home' => $domainhome });
	is($err, undef, 'mailbox subvolume can be deleted cleanly');
	is_deeply(\@unassigned, [ $tmp, '0/300', '1/256' ],
		'mailbox qgroup is detached before subvolume deletion');
	is_deeply(\@deleted, [ $mailbox, 300 ],
		'mailbox subvolume is deleted after its relationship is removed');
}
# External quota backends do not load Webmin's quota module. Ordinary mailbox
# deletion must remain a no-op here instead of calling an undefined Btrfs API.
{
	no warnings qw(redefine once);
	local %main::config = ( 'quota_commands' => 1 );
	local *main::require_useradmin = sub { };
	local *main::btrfs_quota_domain = sub { return $_[0]; };
	local *quota::btrfs_subvolume_id;
	my $err = &delete_btrfs_user_home(
		{ 'home' => "$domainhome/homes/external-quota-user" },
		{ 'home' => $domainhome });
	is($err, undef,
		'external quota backends skip unavailable Btrfs mailbox cleanup');
}
# Subvolume teardown must clean stale qgroups left by older kernels.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::run_btrfs_command = sub { return ('', undef); };
	local *quota::list_btrfs_qgroups = sub {
		return [ { 'id' => '0/300' } ];
		};
	my @deleted;
	local *quota::delete_btrfs_qgroup = sub {
		@deleted = @_;
		return undef;
		};
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 0 };
		};
	my $err = &delete_btrfs_subvolume(
		"$tmp/deleted-subvolume-with-qgroup", 300);
	is($err, undef, 'subvolume and its stale qgroup can be deleted cleanly');
	is_deeply(\@deleted, [ $tmp, '0/300' ],
		'level-0 qgroup is removed explicitly after subvolume deletion');
}
# A kernel that already removed the qgroup must not turn deletion into an error.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::run_btrfs_command = sub { return ('', undef); };
	local *quota::list_btrfs_qgroups = sub { return [ ]; };
	my $delete_calls = 0;
	local *quota::delete_btrfs_qgroup = sub {
		$delete_calls++;
		return 'must not be called';
		};
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 0 };
		};
	my $err = &delete_btrfs_subvolume(
		"$tmp/deleted-subvolume-without-qgroup", 301);
	is($err, undef,
		'already-removed level-0 qgroup is accepted during teardown');
	is($delete_calls, 0,
		'already-removed level-0 qgroup is not destroyed a second time');
}
# Domain teardown must stop if qgroup relationships cannot be inspected.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::btrfs_subvolume_id = sub { return 256; };
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 0 };
		};
	local *quota::rescan_btrfs_quotas = sub { return undef; };
	local *main::btrfs_quota_parent_id = sub {
		die 'domain teardown should derive its parent from the known ID';
		};
	local *main::list_btrfs_qgroups = sub {
		my ($sync, $errref) = @_;
		$$errref = 'qgroup read failed';
		return undef;
		};
	my $err = &delete_btrfs_domain_home({
		'id' => 1700000000789,
		'home' => "$tmp/delete-failure",
		});
	is($err, 'qgroup read failed',
		'domain deletion stops when qgroup relationships cannot be read');
}
# Domain teardown must not orphan mailbox subvolumes that still exist.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 1,
		'home_quotas' => $tmp,
		);
	local $main::home_base = $tmp;
	local *quota::btrfs_subvolume_id = sub { return 256; };
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 1, 'inconsistent' => 0 };
		};
	local *quota::rescan_btrfs_quotas = sub { return undef; };
	local *main::list_btrfs_qgroups = sub {
		$main::btrfs_qgroups_by_id_cache = {
			'1/256' => {
				'id' => '1/256',
				'children' => [ '0/256', '0/257' ],
				},
			};
		return [ values(%{$main::btrfs_qgroups_by_id_cache}) ];
		};
	my $err = &delete_btrfs_domain_home({
		'id' => 1700000000999,
		'home' => "$tmp/delete-nested",
		});
	like($err, qr/nested home subvolumes remain/,
		'domain deletion refuses to orphan a nested mailbox subvolume');
}
# Subvolume deletion must still work after Virtualmin quota editing is disabled.
{
	no warnings qw(redefine once);
	local %main::config = (
		'btrfs_quotas' => 0,
		);
	local $main::home_base = $tmp;
	local *quota::btrfs_subvolume_id = sub { return 256; };
	local *quota::btrfs_quota_status = sub {
		return { 'enabled' => 0 };
		};
	my @deleted;
	local *main::delete_btrfs_subvolume = sub {
		@deleted = @_;
		return undef;
		};
	my $home = "$tmp/quotas-disabled";
	my $err = &delete_btrfs_domain_home({
		'id' => 1700000000111,
		'home' => $home,
		});
	is($err, undef,
		'Btrfs domain home is deleted when Virtualmin quotas are disabled');
	is_deeply(\@deleted, [ $home ],
		'disabled qgroups do not leave a Btrfs subvolume behind');
}

done_testing();
