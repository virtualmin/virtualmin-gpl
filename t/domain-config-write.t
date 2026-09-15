#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr);

{
	no warnings 'once';
	$main::module_root_directory = "$FindBin::Bin/..";
}
do "$FindBin::Bin/../virtual-server-lib-funcs.pl"
	or die "Failed to load virtual-server-lib-funcs.pl: $@ $!";
my $get_domain = \&main::get_domain;

# Model separate cached and saved records with Webmin's non-nesting lock API.
sub fixture
{
my ($code) = @_;
no warnings qw(once redefine uninitialized);
my %stale = ( id => '123', dom => 'example.test', ip => '192.0.2.1',
              virt => 0, owner => 'old' );
my %disk = ( %stale, owner => 'new' );
my ($held, $writes, $reads, $missing) = (0, 0, 0, 0);
local $main::domains_dir = '/tmp/virtualmin-domains-test';
local %main::domain_lock_scope;
local %main::get_domain_cache = ( '123' => \%stale );
local *main::lock_file = sub { return 0 if $held; $held = 1; return 1; };
local *main::test_lock = sub { return $held ? $$ : 0; };
local *main::unlock_file = sub { $held = 0; };
local *main::error = sub { die $_[0]; };
local *main::get_domain = sub {
	if ($_[2]) {
		ok($held, 'reread happens under the lock');
		$reads++;
		}
	return $get_domain->(@_);
	};
# Exercise the real cache behavior without reading or changing host files.
local *main::read_file = sub {
	return 0 if $missing;
	%{$_[1]} = %disk;
	return 1;
	};
local *main::complete_domain = sub { };
local *main::save_domain = sub {
	ok($held, 'save happens under the lock');
	%disk = %{$_[0]};
	$main::get_domain_cache{$_[0]->{id}} = $_[0];
	$writes++;
	return 1;
	};
local *main::list_domains = sub { return \%stale; };
local *main::list_feature_plugins = sub { return (); };
local @main::features = ( 'web' );
local %main::config = ( web => 1 );
local *main::text = sub { return $_[0]; };
local *main::set_domain_envs = sub { };
local *main::reset_domain_envs = sub { };
local *main::making_changes = sub { return undef; };
local *main::made_changes = sub { return undef; };
local $main::first_print = sub { };
local $main::second_print = sub { };
local $main::indent_print = sub { };
local $main::outdent_print = sub { };
$code->(\%stale, \%disk, \$held, \$writes, \$missing);
}

subtest 'operation locks survive nested helpers and failures' => sub {
	fixture(sub {
		my ($stale, $disk, $held) = @_;
		my $rv = main::with_locked_domain($stale, sub {
			my ($d) = @_;
			is($d->{owner}, 'new', 'callback sees the current domain');
			main::lock_domain($d);
			main::unlock_domain($d);
			ok($$held, 'nested feature unlock cannot release the operation lock');
			eval { main::with_locked_domain($d, sub { fail('nested update ran'); }); };
			like($@, qr/already being updated/, 'nested operation is rejected');
			ok($$held, 'rejected nested operation retains outer lock');
			return 42;
			});
		is($rv, 42, 'callback result is returned');
		ok(!$$held, 'operation releases its lock');
		eval { main::with_locked_domain($stale, sub { die "fixture failure\n"; }); };
		like($@, qr/fixture failure/, 'failure is propagated');
		ok(!$$held, 'failed operation releases its lock');
		main::lock_domain($stale);
		main::with_locked_domain($stale, sub { });
		ok($$held, 'pre-existing caller lock is retained');
		main::unlock_domain($stale);
		});
	};

subtest 'private cache protects snapshots and pending changes' => sub {
	fixture(sub {
		my ($stale, $disk, $held, $writes) = @_;
		$stale->{owner} = 'unsaved caller change';
		my %before = %$stale;
		my $other_reference = $stale;
		main::with_locked_domain($stale, sub {
			my ($d) = @_;
			is($d->{owner}, 'new', 'operation starts with the disk record');
			is(refaddr(main::get_domain($d->{id})), refaddr($d),
				'lookups inside the operation use its private record');
			$d->{owner} = 'pending outer change';
			eval { main::with_locked_domain($d, sub { fail('nested update ran'); }); };
			like($@, qr/already being updated/, 'nested update is rejected');
			is($d->{owner}, 'pending outer change', 'rejected update preserves pending values');
			main::save_domain($d);
			});
		is_deeply($other_reference, \%before, 'all references to the caller snapshot are unchanged');
		is(main::get_domain('123')->{owner}, 'pending outer change',
			'next lookup sees the saved record instead of the restored stale cache');
		is($$writes, 1, 'only the outer update is saved');

		# An exception must not leave unsaved changes in the cache.
		eval { main::with_locked_domain($stale, sub {
			$_[0]->{owner} = 'abandoned change';
			die "fixture failure\n";
			}); };
		like($@, qr/fixture failure/, 'callback failure is propagated');
		is(main::get_domain('123')->{owner}, 'pending outer change',
			'failed callback does not leave an unsaved value in the cache');
		ok(!$$held, 'failed callback releases its lock');
		});
	};

subtest 'missing domains and failed locks prevent operations' => sub {
	fixture(sub {
		my ($stale, $disk, $held, $writes, $missing) = @_;
		$$missing = 1;
		main::with_locked_domain($stale, sub { fail('deleted domain callback ran'); });
		ok(!$$held, 'deleted domain releases its lock');
		no warnings 'redefine';
		local *main::lock_file = sub { return 0; };
		local *main::test_lock = sub { return $$ + 1; };
		eval { main::with_locked_domain($stale, sub { fail('unlocked callback ran'); }); };
		like($@, qr/could not be locked/, 'lock failure stops the operation');
		is($$writes, 0, 'neither failure writes a domain');
		local *main::test_lock = sub { return undef; };
		my @warnings;
		local $SIG{__WARN__} = sub { push(@warnings, @_); };
		{
			local $^W = 1;
			eval { main::with_locked_domain($stale, sub { fail('unlocked callback ran'); }); };
		}
		like($@, qr/could not be locked/, 'missing lock owner is reported');
		is_deeply(\@warnings, [], 'undefined lock owner does not cause a warning');
		});
	};

# Skip domains that now use a dedicated or different shared IP.
for my $entry ('dynamic IP') {
	for my $conflict ('unchanged', 'dedicated IP', 'different shared IP', 'deleted') {
		subtest "$entry rereads before applying changes: $conflict" => sub {
			fixture(sub {
				my ($stale, $disk, $held, $writes, $missing) = @_;
				no warnings qw(once redefine uninitialized);
				$disk->{web} = 1;
				if ($conflict eq 'dedicated IP') {
					$disk->{ip} = '192.0.2.3';
					$disk->{virt} = 1;
					}
				elsif ($conflict eq 'different shared IP') {
					$disk->{ip} = '192.0.2.4';
					}
				$$missing = 1 if $conflict eq 'deleted';
				my $calls = 0;
				local *main::try_function = sub {
					my (undef, undef, $d, $oldd) = @_;
					$calls++;
					is($oldd->{owner}, 'new', 'services receive the record read before the IP change');
					main::lock_domain($d);
					main::unlock_domain($d);
					ok($$held, 'lock survives a service helper');
					return 1;
					};
				main::update_all_domain_ip_addresses('192.0.2.2', '192.0.2.1');
				my $changed = $conflict eq 'unchanged' ? 1 : 0;
				is($calls, $changed, 'service changes require current eligibility');
				is($$writes, $changed, 'only eligible domains are saved');
				is($disk->{ip}, $changed ? '192.0.2.2' : $conflict eq 'dedicated IP' ?
					'192.0.2.3' : $conflict eq 'different shared IP' ? '192.0.2.4' :
					'192.0.2.1', 'current IP is preserved or deliberately updated');
				is($disk->{owner}, 'new', 'other current settings survive');
				ok(!$$held, 'lock is released');
				});
			};
		}
	}

# A pre-change command can alter eligibility while the domain is unlocked.
subtest 'pre-command changes are rechecked before services run' => sub {
	fixture(sub {
		my ($stale, $disk, $held, $writes) = @_;
		no warnings qw(once redefine);
		local *main::making_changes = sub {
			ok(!$$held, 'pre-command runs without the domain lock');
			$disk->{virt} = 1;
			return undef;
			};
		main::update_all_domain_ip_addresses('192.0.2.2', '192.0.2.1');
		is($$writes, 0, 'newly dedicated domain is not saved after the command');
		is($disk->{ip}, '192.0.2.1', 'IP remains unchanged');
		});
	fixture(sub {
		my ($stale, $disk, $held, $writes) = @_;
		no warnings qw(once redefine);
		$disk->{disabled_auto} = time() - 60;
		local *main::get_disable_features = sub { return ('web'); };
		local *main::make_date = sub { return 'fixture date'; };
		local *main::making_changes = sub {
			ok(!$$held, 'scheduled pre-command runs without the domain lock');
			delete($disk->{disabled_auto});
			return undef;
			};
		main::disable_virtual_server($stale, 'schedule');
		is($$writes, 0, 'schedule canceled by a command prevents service updates');
		});
	};

subtest 'login collector rechecks current domain settings' => sub {
	fixture(sub {
		my ($stale, $disk, $held, $writes) = @_;
		no warnings qw(once redefine);
		local *main::list_domain_users = sub { return { user => 'fixture' }; };
		local *main::get_last_login_time = sub { return { imap => 10, smtp => 20 }; };
		$disk->{disabled} = 'web';
		main::update_domains_last_login_times();
		is($disk->{last_login_timestamp}, 20, 'latest login is saved');
		is($disk->{disabled}, 'web', 'disabled state survives');
		main::update_domains_last_login_times();
		is($$writes, 1, 'unchanged login avoids a write');
		$disk->{last_login_timestamp} = 30;
		main::update_domains_last_login_times();
		is($disk->{last_login_timestamp}, 30, 'older collected logins cannot replace newer ones');
		$disk->{no_last_login} = 1;
		delete($disk->{last_login_timestamp});
		main::update_domains_last_login_times();
		ok(!exists($disk->{last_login_timestamp}), 'newly disabled collection is honored');
		});
	};

# Exercise the WHOIS CGI with local lookup results and current domain records.
for my $state ('ignore', 'refresh', 'access revoked', 'deleted', 'lookup failure') {
	subtest "WHOIS update: $state" => sub {
		fixture(sub {
			my ($stale, $disk, $held, $writes, $missing) = @_;
			no warnings qw(once redefine);
			$disk->{disabled} = 'web';
			$disk->{whois_ignore} = 1 if $state eq 'refresh';
			$disk->{owner} = 'denied' if $state eq 'access revoked';
			$$missing = 1 if $state eq 'deleted';
			local %main::in = (doms => 'example.test', ignore => $state eq 'ignore');
			local %INC = (%INC, './virtual-server-lib.pl' => 'WHOIS fixture');
			local *main::ReadParse = sub { };
			local *main::get_domain_by = sub { return $stale; };
			local *main::can_edit_domain = sub { return $_[0]->{owner} ne 'denied'; };
			my ($lookups, $redirects) = (0, 0);
			local *main::get_whois_expiry = sub {
				$lookups++;
				ok($$held, 'WHOIS lookup holds the domain lock');
				is($_[0]->{owner}, 'new', 'WHOIS lookup receives current settings');
				die "fixture WHOIS failure\n" if $state eq 'lookup failure';
				return (1900000000, undef);
				};
			local *main::get_referer_relative = sub { return 'fixture.cgi'; };
			local *main::redirect = sub { $redirects++; };
			eval {
				do "$FindBin::Bin/../recollect_whois.cgi";
				die $@ if $@;
				};
			if ($state eq 'lookup failure') {
				like($@, qr/fixture WHOIS failure/, 'lookup failure reaches the caller');
				}
			else {
				is($@, '', 'WHOIS request completes');
				}
			my $saved = $state eq 'ignore' || $state eq 'refresh';
			is($$writes, $saved ? 1 : 0, 'only an allowed, completed update is saved');
			is($lookups, $state eq 'refresh' || $state eq 'lookup failure' ? 1 : 0,
				'deleted or unauthorized domains never reach the lookup');
			is($disk->{disabled}, 'web', 'newer disabled status survives');
			if ($state eq 'ignore') {
				ok($disk->{whois_ignore}, 'expiry checks are disabled');
				}
			elsif ($state eq 'refresh') {
				is($disk->{whois_expiry}, 1900000000, 'new expiry is saved');
				ok(!exists($disk->{whois_ignore}), 'refresh resumes expiry checks');
				ok($disk->{whois_next} > $disk->{whois_last}, 'next check is scheduled');
				}
			is($redirects, $state eq 'lookup failure' ? 0 : 1, 'completed requests redirect');
			ok(!$$held, 'domain lock is released, including after failure');
			});
		};
	}

# Skip canceled or postponed schedules and domains already disabled or protected.
for my $state ('canceled', 'deferred', 'protected', 'disabled') {
	subtest "scheduled disable rechecks $state domain" => sub {
		fixture(sub {
			my ($stale, $disk, $held, $writes) = @_;
			$stale->{disabled_auto} = time() - 60;
			$disk->{disabled_auto} = time() - 60;
			delete($disk->{disabled_auto}) if $state eq 'canceled';
			$disk->{disabled_auto} = time() + 3600 if $state eq 'deferred';
			$disk->{$state} = 1 if $state eq 'protected' || $state eq 'disabled';
			main::disable_virtual_server($stale, 'schedule');
			is($$writes, 0, 'stale schedule does not change the domain');
			ok(!$$held, 'skipped schedule releases the lock');
			});
		};
	}

# After an operation, the caller and cache must share the updated object.
for my $operation ('disable', 'enable', 'IP update') {
	subtest "$operation keeps caller and cache synchronized" => sub {
		fixture(sub {
			my ($stale, $disk, $held) = @_;
			no warnings qw(once redefine);
			$disk->{web} = 1;
			$disk->{disabled} = 'web' if $operation eq 'enable';
			local *main::get_disable_features = sub { return ('web'); };
			local *main::get_enable_features = sub { return ('web'); };
			local *main::update_extra_webmin = sub { };
			local *main::try_function = sub {
				my $d = $_[2];
				is(refaddr(main::get_domain($d->{id})), refaddr($d),
					'feature lookups use the active record');
				return (1, 1);
				};
			if ($operation eq 'disable') {
				is(main::disable_virtual_server($stale, 'manual'), undef, 'disable succeeds');
				}
			elsif ($operation eq 'enable') {
				is(main::enable_virtual_server($stale), undef, 'enable succeeds');
				}
			else {
				is(main::update_all_domain_ip_addresses('192.0.2.2', '192.0.2.1'), 1,
					'IP update succeeds');
				}
			is(refaddr(main::get_domain('123')), refaddr($stale),
				'caller and subsequent lookups share one object');
			$stale->{owner} = 'later caller edit';
			is(main::get_domain('123')->{owner}, 'later caller edit',
				'later edits do not diverge between caller and cache');
			});
		};
	}

# Test transfer failures with simulated backups, services and transport.
# If disabling the source fails, the destination must not be restored.
for my $state ('protected', 'newly protected', 'hook failure', 'allowed') {
	for my $showoutput (0, 1) {
		subtest "transfer disable: $state, output=$showoutput" => sub {
			fixture(sub {
				my ($stale, $disk, $held, $writes) = @_;
				no warnings qw(once redefine);
				$disk->{web} = 1;
				$disk->{protected} = 1 if $state eq 'protected';
				my ($restores, $cleanups, $depth, $services) = (0, 0, 0, 0);
				my @messages;
				local @main::backup_features = ('virtualmin');
				local *main::get_domain_by = sub { return (); };
				local *main::list_backup_plugins = sub { return (); };
				local *main::prune_all_features_for_backup = sub { return @_; };
				local *main::backup_domains = sub { return (1, 1, []); };
				local *main::indexof = sub {
					my ($value, @list) = @_;
					for my $i (0 .. $#list) { return $i if $list[$i] eq $value; }
					return -1;
					};
				local *main::execute_command_via_ssh = sub {
					my $cmd = $_[3];
					return (1, '') if $cmd =~ /^grep /;
					return (1, "example.test.tar.gz\n") if $cmd =~ /^ls /;
					if ($cmd =~ /^rm /) { $cleanups++; return (1, ''); }
					die "Unexpected fixture transport command: $cmd";
					};
				local *main::execute_virtualmin_api_command = sub {
					$restores++ unless $_[4] =~ / --test$/;
					return (0, '', '');
					};
				local *main::show_domain_name = sub { return $_[0]->{dom}; };
				local *main::get_disable_features = sub { return ('web'); };
				local *main::update_extra_webmin = sub { };
				local *main::try_function = sub { $services++; return (1, 1); };
				local *main::making_changes = sub {
					$disk->{protected} = 1 if $state eq 'newly protected';
					return $state eq 'hook failure' ? 'fixture hook refused' : undef;
					};
				local *main::html_escape = sub { return $_[0]; };
				local *main::text = sub { return join(' ', @_); };
				local $main::first_print = sub { };
				local $main::second_print = sub { push(@messages, $_[0] || ''); };
				local *main::push_all_print = sub { $depth++; };
				local *main::pop_all_print = sub { $depth--; };
				local *main::set_all_null_print = sub { };
				local *main::set_all_capture_print = sub { };
				my $expected = $state eq 'allowed' ? 1 : 0;
				is(main::transfer_virtual_server($stale, 'destination.invalid', 'fixture',
					undef, 'ssh', 1, 0, 0, $showoutput), $expected, 'transfer returns its real status');
				is($restores, $expected, 'destination is restored only after source disabling succeeds');
				is($services, $expected, 'refused disables do not change services');
				is($$writes, $expected, 'refused disables do not write the domain');
				is($cleanups, 1, 'remote backup fixture is cleaned up');
				is($depth, 0, 'output handlers are restored');
				if (!$expected) {
					like(join("\n", @messages), qr/transfer_edisable.*(?:protected|fixture hook refused)/,
						'transfer reports why disabling failed');
					}
				});
			};
		}
	}

# Restore recreates a record already marked disabled, but still needs to disable
# its newly created services. Ordinary requests must not repeat that operation.
subtest 'restore can reapply disabled state to recreated services' => sub {
	fixture(sub {
		my ($stale, $disk, $held, $writes) = @_;
		no warnings qw(once redefine);
		$disk->{disabled} = 'web';
		$disk->{web} = 1;
		my $calls = 0;
		local *main::get_disable_features = sub { return ('web'); };
		local *main::update_extra_webmin = sub { };
		local *main::try_function = sub {
			$calls++;
			ok($$held, 'restored service is disabled under the domain lock');
			return (1, 1);
			};
		main::disable_virtual_server($stale, 'manual');
		is($calls, 0, 'ordinary repeated disabling is skipped');
		main::disable_virtual_server($stale, 'manual', undef, undef, 1);
		is($calls, 1, 'restore explicitly reapplies the service state');
		ok(!$$held, 'restore operation releases its lock');
		});
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

done_testing();
