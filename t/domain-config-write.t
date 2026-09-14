#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);

{
	no warnings 'once';
	$main::module_root_directory = "$FindBin::Bin/..";
}
do "$FindBin::Bin/../virtual-server-lib-funcs.pl"
	or die "Failed to load virtual-server-lib-funcs.pl: $@ $!";

subtest 'selected domain keys preserve newer settings' => sub {
	no warnings qw(once redefine numeric);
	my %domain = (
		'id' => '123',
		'dom' => 'example.test',
		'letsencrypt_last' => 10,
		);
	my %latest = (
		%domain,
		'owner_setting' => 'new',
		'removed' => 1,
		);
	$domain{'pending'} = 'caller change';
	my ($saved, @events);
	local $main::domains_dir = '/tmp/virtualmin-domains-test';
	local *main::lock_file = sub { push(@events, 'lock'); return 1; };
	local *main::test_lock = sub { return 0; };
	local *main::get_domain = sub {
		is_deeply([ @_ ], [ '123', undef, 1 ],
			'domain is force re-read after locking');
		push(@events, 'read');
		return \%latest;
		};
	local *main::save_domain = sub {
		push(@events, 'save');
		$saved = { %{$_[0]} };
		return 1;
		};
	local *main::unlock_file = sub { push(@events, 'unlock'); };

	my $result = &main::save_domain_keys(\%domain,
		{ 'letsencrypt_last' => 20 }, [ 'removed' ]);
	is_deeply($saved, {
		'id' => '123',
		'dom' => 'example.test',
		'letsencrypt_last' => 20,
		'owner_setting' => 'new',
		}, 'only requested changes are merged into the latest domain');
	is_deeply(\@events, [ qw(lock read save unlock) ],
		'domain is read and saved while locked');
	is($domain{'letsencrypt_last'}, 20,
		'requested value is reflected in the caller domain');
	ok(!exists($domain{'removed'}),
		'requested deletion is reflected in the caller domain');
	is($domain{'pending'}, 'caller change',
		'unrelated unsaved caller value is retained');
	ok(!exists($saved->{'pending'}),
		'unrequested caller value is not written');
	is($result, undef, 'keyed domain update has a void return value');
	};

subtest 'unchanged domain update avoids a write' => sub {
	no warnings qw(once redefine);
	my %domain = (
		'id' => '123',
		'dom' => 'example.test',
		'setting' => 'current',
		'pending' => 'caller change',
		);
	my %latest = (
		'id' => '123',
		'dom' => 'example.test',
		'setting' => 'current',
		'concurrent' => 'preserved',
		);
	my $saves = 0;
	local $main::domains_dir = '/tmp/virtualmin-domains-test';
	local %main::get_domain_cache = ( '123' => \%domain );
	local *main::lock_file = sub { return 1; };
	local *main::get_domain = sub {
		$main::get_domain_cache{'123'} = \%latest;
		return \%latest;
		};
	local *main::save_domain = sub { $saves++; };
	local *main::unlock_file = sub { };

	my $result = &main::save_domain_keys(
		\%domain, { 'setting' => 'current' });
	is($saves, 0, 'domain is not saved when the requested value is current');
	is($domain{'pending'}, 'caller change',
		'unrelated unsaved caller changes are retained');
	ok(!exists($domain{'concurrent'}),
		'unrelated file values are not mixed into the caller');
	is($main::get_domain_cache{'123'}, \%domain,
		'forced read does not replace the caller cache object');
	is($result, undef, 'unchanged domain update has a void return value');
	};

subtest 'domain diff saves only intended changes' => sub {
	no warnings qw(once redefine);
	my %original = (
		'id' => '123',
		'dom' => 'example.test',
		'changed' => 'old',
		'removed' => 1,
		);
	my %domain = (
		'id' => '123',
		'dom' => 'example.test',
		'changed' => 'new',
		'added' => 1,
		);
	my ($values, $deletes);
	local *main::save_domain_keys = sub {
		(undef, $values, $deletes) = @_;
		return;
		};

	my $result = &main::save_domain_diff(\%domain, \%original);
	is_deeply($values, { 'changed' => 'new', 'added' => 1 },
		'diff contains only changed and added keys');
	is_deeply($deletes, [ 'removed' ],
		'diff contains the deleted key');
	is($result, undef, 'domain diff has a void return value');
	};

subtest 'save_domain retains a caller-owned lock' => sub {
	no warnings qw(once redefine);
	my %domain = (
		'id' => '123',
		'dom' => 'example.test',
		'created' => 1,
		);
	my ($writes, $unlocks) = (0, 0);
	local $main::domains_dir = '/tmp/virtualmin-domains-test';
	local %main::get_domain_by_maps = ( );
	local @main::list_domains_cache = ( );
	local %main::get_domain_cache = ( );
	local *main::make_dir = sub { };
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$; };
	local *main::read_file = sub { return 0; };
	local *main::write_file = sub { $writes++; };
	local *main::unlock_file = sub { $unlocks++; };
	local *main::set_ownership_permissions = sub { };

	ok(&main::save_domain(\%domain, 1),
		'domain save succeeds under caller lock');
	is($writes, 1, 'domain is written once');
	is($unlocks, 0, 'caller-owned lock is not released');
	};

subtest 'save_domain stops without a lock' => sub {
	no warnings qw(once redefine);
	my %domain = (
		'id' => '123',
		'dom' => 'example.test',
		'created' => 1,
		);
	my $writes = 0;
	local $main::domains_dir = '/tmp/virtualmin-domains-test';
	local *main::make_dir = sub { };
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$ + 1; };
	local *main::write_file = sub { $writes++; };

	ok(!&main::save_domain(\%domain, 1),
		'save fails when lock is unavailable');
	is($writes, 0, 'domain is not written without a lock');
	};

# A vanished domain must not be recreated from an old in-memory copy.
subtest 'keyed update skips deleted domains and failed locks' => sub {
	no warnings qw(once redefine);
	my %domain = ( 'id' => '123', 'dom' => 'example.test', 'setting' => 'old' );
	my ($reads, $saves, $unlocks) = (0, 0, 0);
	local *main::lock_file = sub { return 1; };
	local *main::get_domain = sub { $reads++; return undef; };
	local *main::save_domain = sub { $saves++; };
	local *main::unlock_file = sub { $unlocks++; };
	&main::save_domain_keys(\%domain, { 'setting' => 'new' });
	is($saves, 0, 'deleted domain is not saved');
	is($domain{'setting'}, 'old', 'missing domain leaves the caller unchanged');
	is($unlocks, 1, 'lock is released when the domain is missing');
	{
		local *main::lock_file = sub { return 0; };
		local *main::test_lock = sub { return $$ + 1; };
		&main::save_domain_keys(\%domain, { 'setting' => 'new' });
	}
	is($reads, 1, 'failed lock prevents a read');
	is($saves, 0, 'failed lock prevents a save');
	is($unlocks, 1, 'another process lock is not released');
	};

# Exercise the collection caller with a newer saved record and a stale cache.
subtest 'last-login collection preserves newer domain fields' => sub {
	no warnings qw(once redefine);
	my %domain = ( 'id' => '123', 'dom' => 'example.test' );
	my %disk = ( %domain, 'description' => 'updated', 'last_login_timestamp' => 5 );
	my $saves = 0;
	local *main::list_domains = sub { return \%domain; };
	local *main::list_domain_users = sub { return { 'user' => 'fixture' }; };
	local *main::get_last_login_time = sub { return { 'imap' => 10, 'smtp' => 20 }; };
	local *main::lock_file = sub { return 1; };
	local *main::unlock_file = sub { };
	local *main::get_domain = sub { return { %disk }; };
	local *main::save_domain = sub { %disk = %{$_[0]}; $saves++; return 1; };
	&main::update_domains_last_login_times();
	is($disk{'last_login_timestamp'}, 20, 'latest login is saved');
	is($disk{'description'}, 'updated', 'concurrent domain change survives');
	&main::update_domains_last_login_times();
	is($saves, 1, 'unchanged login does not rewrite the domain');
	};

# Both IP-update entry points must diff against their actual original object.
foreach my $entry ('dynamic IP', 'bulk IP CGI') {
	subtest "$entry preserves unrelated concurrent changes" => sub {
		no warnings qw(once redefine uninitialized);
		my %domain = ( 'id' => '123', 'dom' => 'example.test',
			'ip' => '192.0.2.1', 'description' => 'old' );
		my %disk = ( %domain, 'description' => 'new' );
		local %main::oldd = ( 'unrelated_global' => 1 );
		local @main::features = ( );
		local @main::doms = ( \%domain );
		local %main::in = ( 'mode' => 0, 'old' => '192.0.2.1', 'new' => '192.0.2.2' );
		local $main::first_print = sub { };
		local $main::second_print = sub { };
		local $main::indent_print = sub { };
		local $main::outdent_print = sub { };
		local *main::list_domains = sub { return \%domain; };
		local *main::list_feature_plugins = sub { return (); };
		local *main::text = sub { return $_[0]; };
		local *main::set_domain_envs = sub { };
		local *main::reset_domain_envs = sub { };
		local *main::making_changes = sub { return undef; };
		local *main::made_changes = sub { return undef; };
		local *main::lock_file = sub { return 1; };
		local *main::unlock_file = sub { };
		local *main::get_domain = sub { return { %disk }; };
		local *main::save_domain = sub { %disk = %{$_[0]}; return 1; };
		if ($entry eq 'dynamic IP') {
			is(&main::update_all_domain_ip_addresses('192.0.2.2', '192.0.2.1'),
				1, 'one domain is updated');
			}
		else {
			# Run the bulk loop only; the page's input and service setup are separate.
			my $code = source_block('save_newips.cgi',
				'# Do each domain, and all active features in it',
				'# Tell the user if nothing happened');
			my ($output, $err);
			{
				local *STDOUT;
				open(STDOUT, '>', \$output) or die $!;
				eval 'package main; no strict; '.$code;
				$err = $@;
			}
			is($err, '', 'bulk IP loop completes');
			}
		is($disk{'ip'}, '192.0.2.2', 'requested IP is saved');
		is($disk{'description'}, 'new', 'newer unrelated setting survives');
		};
	}

# Certificate uploads continue changing the domain after the initial save.
subtest 'certificate upload saves its final metadata' => sub {
	no warnings qw(once redefine);
	local $main::d = { 'id' => '123', 'dom' => 'example.test',
		'ssl_pass' => 'fixture-passphrase', 'ssl_combined' => '/fixture/combined' };
	local %main::original_domain = ( 'id' => '123', 'dom' => 'example.test' );
	my %disk = ( %main::original_domain, 'description' => 'newer value' );
	local *main::disable_letsencrypt_renewal = sub { };
	local *main::lock_file = sub { return 1; };
	local *main::unlock_file = sub { };
	local *main::get_domain = sub { return { %disk }; };
	local *main::save_domain = sub { %disk = %{$_[0]}; return 1; };
	my $code = source_block('newkey.cgi',
		"# Turn off any let's encrypt renewal", '# Run the after command');
	eval 'package main; no strict; '.$code;
	is($@, '', 'certificate metadata save completes');
	ok($disk{'ssl_pass'} eq $main::d->{'ssl_pass'}, 'passphrase is persisted');
	is($disk{'ssl_combined'}, '/fixture/combined', 'combined certificate path is persisted');
	is($disk{'description'}, 'newer value', 'unrelated setting remains current');
	};

# Archiving an old snapshot must not write it back to the live domain.
subtest 'backup metadata stays in the archive' => sub {
	no warnings qw(once redefine);
	my $tmp = tempdir(CLEANUP => 1);
	my %domain = ( 'id' => '123', 'dom' => 'example.test',
		'file' => "$tmp/live", 'dir' => 1, 'lastread_time' => 10,
		'backup_encpass' => 'obsolete', 'backup_mail_folders' => 'obsolete',
		'backup_web_default' => 1, 'template' => 0 );
	my %disk = ( %domain, 'dir' => 0, 'disabled' => 1, 'owner' => 'newer' );
	my %before = %disk;
	my ($archive, $mode);
	my $unlocks = 0;
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	local $main::initial_users_dir = "$tmp/missing";
	local $main::extra_admins_dir = "$tmp/missing";
	local $main::extra_users_dir = "$tmp/missing";
	local $main::script_log_directory = "$tmp/missing";
	local $main::saved_aliases_dir = "$tmp/missing";
	local %main::config;
	local *main::foreign_config = sub { return (); };
	local *main::domain_has_website = sub { return ''; };
	local *main::domain_has_ssl = sub { return ''; };
	local *main::lock_domain = sub { return 0; };
	local *main::unlock_domain = sub { $unlocks++; };
	local *main::save_domain = sub {
		%disk = %{$_[0]};
		delete($disk{'lastread_time'});
		};
	local *main::open_tempfile = sub { };
	local *main::close_tempfile = sub { };
	local *main::set_ownership_permissions = sub { $mode = $_[2]; };
	local *main::write_file = sub {
		is($_[0], "$tmp/archive", 'snapshot is written to the archive path');
		is($mode, 0600, 'archive is private before metadata is written');
		$archive = { %{$_[1]} };
		};
	local *main::copy_source_dest = sub {
		$archive = { %disk } if $_[0] eq $domain{'file'};
		return 1;
		};
	local *main::list_templates = sub { return { 'id' => 0, 'standard' => 1 }; };
	local *main::get_plan = sub { return undef; };
	local *main::get_website_ssl_file = sub { return undef; };
	ok(&main::backup_virtualmin(\%domain, "$tmp/archive"), 'metadata backup succeeds');
	is_deeply(\%disk, \%before, 'newer live settings are untouched');
	is($unlocks, 0, 'backup does not release a caller-owned domain lock');
	is($archive->{'dir'}, 1, 'temporary home-directory flag is archived');
	ok(!exists($archive->{'lastread_time'}), 'process-local read time is not archived');
	is($domain{'lastread_time'}, 10, 'caller snapshot retains its read time');
	foreach my $key (qw(backup_encpass backup_mail_folders backup_web_default)) {
		ok(!exists($archive->{$key}), "archive removes obsolete $key");
		}
	};

# Keep CGI tests bounded to the changed persistence code, without host setup.
sub source_block
{
my ($file, $start, $end) = @_;
open(my $fh, '<', "$FindBin::Bin/../$file") or die "$file: $!";
my $source = do { local $/; <$fh> };
close($fh);
my $from = index($source, $start);
my $to = index($source, $end, $from + length($start));
die "Cannot find test block in $file" if ($from < 0 || $to < 0);
return substr($source, $from, $to - $from);
}

done_testing();
