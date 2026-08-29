#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

{
	no warnings 'once';
	$main::module_root_directory = "$FindBin::Bin/..";
}
do "$FindBin::Bin/../virtual-server-lib-funcs.pl"
	or die "Failed to load virtual-server-lib-funcs.pl: $@ $!";

# Run an atomic config update against an independently changed on-disk config
sub run_config_update
{
my ($local, $disk, $update) = @_;
my (@events, @saved);
my $result;

{
	no warnings qw(once redefine);
	local %main::config = %$local;
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	local *main::lock_file = sub {
		push(@events, 'lock');
		return 1;
		};
	local *main::read_file = sub {
		push(@events, 'read');
		%{$_[1]} = %$disk;
		return 1;
		};
	local *main::save_module_config = sub {
		push(@events, 'save');
		push(@saved, { %{$_[0]} });
		};
	local *main::unlock_file = sub { push(@events, 'unlock'); };
	$result = $update->();
	%$local = %main::config;
	}

return ($result, \@events, \@saved);
}

subtest 'selected-key update preserves newer settings' => sub {
	my $local = {
		'wizard_run' => 0,
		'spam' => 1,
		'last_renewal' => 10,
		};
	my $disk = {
		'wizard_run' => 1,
		'spam' => 0,
		'last_renewal' => 10,
		};
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_keys(
			{ 'last_renewal' => 20 }) });

	is_deeply($events, [ qw(lock read save unlock) ],
		'config is read and saved while locked');
	is_deeply($saved->[0], {
		'wizard_run' => 1,
		'spam' => 0,
		'last_renewal' => 20,
		}, 'only the requested key is merged into the latest config');
	is($local->{'last_renewal'}, 20,
		'updated key is reflected in the process-local config');
	is($local->{'wizard_run'}, 0,
		'unrelated process-local values are not silently changed');
	is_deeply($result, $saved->[0], 'latest merged config is returned');
	};

subtest 'unchanged update avoids an unnecessary write' => sub {
	my $local = { 'last_renewal' => 20 };
	my $disk = { 'last_renewal' => 20, 'wizard_run' => 1 };
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_keys(
			{ 'last_renewal' => 20 }) });

	is_deeply($events, [ qw(lock read unlock) ],
		'no write is made when the selected value is current');
	is(scalar(@$saved), 0, 'module config was not saved');
	is_deeply($result, $disk, 'latest config is still returned');
	};

subtest 'snapshot update merges only changes made by a long process' => sub {
	my $original = {
		'wizard_run' => 0,
		'spam' => 1,
		'checked' => 'old',
		'removed' => 1,
		};
	my $local = {
		'wizard_run' => 0,
		'spam' => 1,
		'checked' => 'new',
		'added' => 1,
		};
	my $disk = {
		'wizard_run' => 1,
		'spam' => 0,
		'checked' => 'old',
		'removed' => 1,
		'concurrent' => 1,
		};
	my ($result, $events, $saved) = run_config_update(
		$local, $disk,
		sub { &main::save_module_config_diff($original) });

	is_deeply($saved->[0], {
		'wizard_run' => 1,
		'spam' => 0,
		'checked' => 'new',
		'added' => 1,
		'concurrent' => 1,
		}, 'newer values survive while intended additions, changes and deletions apply');
	is_deeply($events, [ qw(lock read save unlock) ],
		'snapshot changes use the same locked merge');
	is_deeply($result, $saved->[0], 'merged snapshot config is returned');
	};

subtest 'an existing process lock is retained' => sub {
	no warnings qw(once redefine);
	local %main::config = ( 'checked' => 'old' );
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	my $saved;
	my $unlocks = 0;
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$; };
	local *main::read_file = sub {
		%{$_[1]} = ( 'checked' => 'old', 'concurrent' => 1 );
		return 1;
		};
	local *main::save_module_config = sub { $saved = { %{$_[0]} }; };
	local *main::unlock_file = sub { $unlocks++ };

	my $result = &main::save_module_config_keys({ 'checked' => 'new' });
	is_deeply($saved, { 'checked' => 'new', 'concurrent' => 1 },
		'update succeeds while the caller owns the lock');
	is($unlocks, 0, 'helper does not release its caller lock');
	is_deeply($result, $saved, 'merged config is returned');
	};

subtest 'update stops when the lock was not acquired' => sub {
	no warnings qw(once redefine);
	local %main::config = ( 'checked' => 'old' );
	local $main::module_config_file = '/tmp/virtualmin-config-test';
	my $read = 0;
	local *main::lock_file = sub { return 0; };
	local *main::test_lock = sub { return $$ + 1; };
	local *main::read_file = sub { $read++; return 1; };

	my $result = &main::save_module_config_keys({ 'checked' => 'new' });
	ok(!defined($result), 'failed lock returns no config');
	is($read, 0, 'config is not accessed without a lock');
	is($main::config{'checked'}, 'old', 'process-local config is unchanged');
	};

done_testing();
