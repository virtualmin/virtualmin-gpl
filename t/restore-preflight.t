#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

# Keep Unix account lookups independent of the workstation running the tests.
our (%users, %groups, %uids, %gids);
BEGIN {
	*CORE::GLOBAL::getpwnam = sub { return $users{$_[0]}; };
	*CORE::GLOBAL::getgrnam = sub { return $groups{$_[0]}; };
	*CORE::GLOBAL::getpwuid = sub { return $uids{$_[0]}; };
	*CORE::GLOBAL::getgrgid = sub { return $gids{$_[0]}; };
}

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
no warnings 'once';
$main::module_root_directory = $root;
$main::module_name = 'virtual-server';
foreach my $name ('virtual-server-lib-funcs.pl',
		 'feature-unix.pl', 'feature-dns.pl',
		 'feature-mysql.pl', 'feature-postgres.pl') {
	my $file = File::Spec->catfile($root, $name);
	my $loaded = do $file;
	die $@ if ($@);
	die "Failed to load $file: $!" if (!defined($loaded));
	}

{
	no warnings 'redefine';
	local @main::features = qw(unix dns mysql postgres);
	local %main::config = ( 'dns' => 1, 'mysql' => 1, 'postgres' => 1 );
	my (%existing, %resellers);
	my %templates = ( 0 => { 'dns_cloud' => 'cloudflare',
				'dns_cloud_import' => 1 } );
	my ($remote_unix, $local_zone, $cloud_calls) = (0, 0, 0);
	local *main::get_domain = sub { return $existing{$_[0]}; };
	local *main::get_domain_by = sub {
		my ($field, $value) = @_;
		return undef if (!defined($value));
		my ($d) = grep { $_->{$field} eq $value } values %existing;
		return $d;
		};
	local *main::list_domains = sub { return values %existing; };
	local *main::get_reseller = sub { return $resellers{$_[0]}; };
	local *main::get_template = sub { return $templates{$_[0]}; };
	local *main::remote_unix = sub { return $remote_unix; };
	local *main::list_feature_plugins = sub { return (); };
	local *main::list_provision_features = sub { return ('dns'); };
	local *main::list_dns_clouds = sub {
		return ({ 'name' => 'cloudflare', 'desc' => 'Cloudflare DNS' });
		};
	local *main::dnscloud_cloudflare_get_state = sub { return { 'ok' => 1 }; };
	local *main::dnscloud_cloudflare_check_domain = sub { $cloud_calls++; return 1; };
	local *main::get_bind_zone = sub { return $local_zone ? {} : undef; };
	local *bind8::find_value = sub { return 'master'; };
	local *main::mysql_user = sub { return $_[0]->{'user'}; };
	local *main::postgres_user = sub { return $_[0]->{'user'}; };
	local *main::show_domain_name = sub { return $_[0]->{'dom'}; };
	local *main::text = sub { return join(': ', map { defined($_) ? $_ : '' } @_); };
	local *main::indexof = sub {
		my ($value, @values) = @_;
		foreach my $i (0 .. $#values) {
			return $i if ($values[$i] eq $value);
			}
		return -1;
		};

	my $domain = {
		'dom' => 'restore.example.invalid', 'id' => 42, 'missing' => 1,
		'user' => 'restorefixture', 'group' => 'restorefixture',
		'uid' => 1000, 'gid' => 1000, 'unix' => 1, 'dns' => 1,
		'template' => 0, 'dns_cloud' => 'cloudflare', 'dns_cloud_import' => 0,
		};
	my %original = %$domain;
	my $errors = sub {
		my ($d, $opts) = @_;
		return [ &check_restore_errors({}, [ $d ], $opts) ];
		};
	my $blocked = sub {
		my ($d, $opts, $pattern, $label) = @_;
		my $errs = $errors->($d, $opts);
		is(scalar(@$errs), 1, "$label: one error");
		ok($errs->[0]->{'critical'}, "$label: fatal before transfer deletion");
		like($errs->[0]->{'desc'} || '', $pattern, "$label: correct conflict");
		is($errs->[0]->{'dom'}, $d, "$label: identifies original domain");
		};

	# Numeric IDs may change; account names must still be checked.
	$uids{1000} = 'occupied';
	$gids{1000} = 'occupied';
	is_deeply($errors->($domain, { 'reuid' => 1 }), [],
		'reallocation accepts occupied UID and GID');
	$blocked->($domain, { 'reuid' => 0 }, qr/setup_eunixclash3/,
		'keeping an occupied UID');
	delete($uids{1000});
	$blocked->($domain, { 'reuid' => 0 }, qr/setup_eunixclash4/,
		'keeping an occupied GID');
	delete($gids{1000});
	$users{'restorefixture'} = 1;
	$blocked->($domain, { 'reuid' => 1 }, qr/setup_eunixclash1/,
		'occupied username despite reallocation');
	%users = ();
	$groups{'restorefixture'} = 1;
	$blocked->($domain, { 'reuid' => 1 }, qr/setup_eunixclash2/,
		'occupied group name despite reallocation');
	%groups = ();
	is_deeply($domain, \%original, 'preflight preserves backup metadata');

	# DNS checks must use the destination provider and takeover setting.
	is_deeply($errors->($domain, {}), [], 'destination permits taking over existing zone');
	is($cloud_calls, 0, 'takeover needs no cloud zone lookup');
	$templates{0}->{'dns_cloud_import'} = 0;
	$blocked->($domain, {}, qr/setup_dnscloudclash/, 'destination refuses zone takeover');
	$blocked->({ %$domain, 'dns_cloud_import' => 1 }, {}, qr/setup_dnscloudclash/,
		'source takeover setting cannot override destination');
	$blocked->({ %$domain, 'dns_cloud' => 'local' }, {}, qr/setup_dnscloudclash/,
		'destination cloud provider replaces source provider');
	is_deeply($errors->($domain, { 'repl' => 1 }), [],
		'replication permits an existing cloud zone');
	$templates{0}->{'dns_cloud'} = 'local';
	is_deeply($errors->($domain, {}), [], 'destination local DNS replaces source cloud DNS');
	$local_zone = 1;
	$blocked->($domain, {}, qr/setup_edns:/, 'existing destination local DNS zone');
	$local_zone = 0;
	$templates{0}->{'dns_cloud'} = 'cloudflare';
	$templates{0}->{'dns_cloud_import'} = 1;
	is_deeply($errors->({ %$domain, 'template' => 999 }, {}), [],
		'template that must be restored defers DNS validation');
	is_deeply($errors->({ %$domain, 'alias' => 17 }, {}), [],
		'alias target that must be restored defers DNS validation');
	{
		local $main::config{'dns'} = 0;
		$templates{0}->{'dns_cloud_import'} = 0;
		is_deeply($errors->($domain, {}), [], 'globally disabled DNS is not recreated');
		$templates{0}->{'dns_cloud_import'} = 1;
	}

	# Issue #1224: sub-server database ownership conflicts must abort the
	# preflight even when numeric IDs and cloud zones can be reused.
	$existing{99} = { 'id' => 99, 'dom' => 'owner.example.invalid',
		'mysql' => 1, 'postgres' => 1, 'user' => 'databaseowner',
		'db_mysql' => 'blog', 'db_postgres' => 'blog' };
	my $parent = { 'id' => 17, 'dom' => 'parent.example.invalid' };
	$existing{17} = $parent;
	foreach my $feature ('mysql', 'postgres') {
		my $child = { %$domain, 'parent' => 17, 'db' => 'blog', $feature => 1,
			'backup_parent_dom' => $parent->{'dom'} };
		$blocked->($child, { 'reuid' => 1 }, qr/setup_e${feature}dbdom/,
			"$feature ownership conflict with parent on destination");
		delete($existing{17});
		my @errs = &check_restore_errors({}, [ $parent, $child ], { 'reuid' => 1 });
		is(scalar(@errs), 1, "$feature conflict found when parent is also in backup");
		like($errs[0]->{'desc'}, qr/setup_e${feature}dbdom/,
			"$feature conflict identifies database owner");
		$existing{17} = $parent;
		$blocked->({ %$child, 'template' => 999 }, {}, qr/setup_e${feature}dbdom/,
			"$feature conflict still checked when DNS must be deferred");
		is_deeply($errors->({ %$child, 'db' => 'unused' }, {}), [],
			"$feature accepts non-conflicting database");
	}

	# Import-only recovery does not create resources. Shared Unix accounts
	# retain the existing restore exception through wasmissing.
	$users{'restorefixture'} = 1;
	is_deeply($errors->($domain, { 'fix' => 1 }), [],
		'fix mode imports metadata without creation clashes');
	$remote_unix = 1;
	is_deeply($errors->($domain, {}), [], 'restored remote Unix account can already exist');
	$remote_unix = 0;
	%users = ();
	is_deeply($errors->({ %$domain, 'missing' => 0 }, {}), [],
		'existing domains do not need creation checks');
	is_deeply([ &check_restore_errors({}) ], [], 'backups without domains are supported');

	# Parent and reseller validation keep their existing severity.
	delete($existing{17});
	my $child = { %$domain, 'parent' => 17,
		'backup_parent_dom' => 'parent.example.invalid' };
	$blocked->($child, {}, qr/restore_eparent/, 'missing parent');
	is_deeply([ &check_restore_errors({}, [ $child, $parent ], {}) ], [],
		'parent in backup satisfies dependency');
	my $resold = { %$domain, 'reseller' => 'restore-reseller' };
	my $errs = $errors->($resold, {});
	is(scalar(@$errs), 1, 'missing reseller is reported');
	ok(!$errs->[0]->{'critical'}, 'missing reseller remains a warning');
	like($errs->[0]->{'desc'}, qr/restore_ereseller/, 'reseller warning describes dependency');
	is_deeply([ &check_restore_errors(
		{ 'virtualmin' => [ 'resellers' ] }, [ $resold ], {}) ], [],
		'resellers included in backup satisfy dependency');
	$resellers{'restore-reseller'} = {};
	is_deeply($errors->($resold, {}), [], 'existing reseller satisfies dependency');
	is_deeply($domain, \%original, 'all checks leave original metadata unchanged');
}

done_testing();
