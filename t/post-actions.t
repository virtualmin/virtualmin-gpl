#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

# Restart tests replace process and service operations, including the delay.
BEGIN { *CORE::GLOBAL::sleep = sub { 0 }; }
foreach my $spec (
	[ 'virtual-server-lib-funcs.pl', qw(register_post_action run_post_actions) ],
	[ 'feature-web.pl', 'restart_apache' ]) {
	my ($file, @names) = @$spec;
	open(my $fh, '<', "$FindBin::Bin/../$file") or die $!;
	my $source = do { local $/; <$fh> };
	foreach my $name (@names) {
		my ($function) = $source =~ /(^sub \Q$name\E\n\{.*?^\})/ms;
		die "Missing $name" unless $function;
		eval "no strict; no warnings; $function";
		die $@ if $@;
		}
	}
sub text { join(' ', @_) }

# An action failure must not stop later actions or become success afterward.
foreach my $result (qw(success zero exception)) {
	subtest "post-action returns $result" => sub {
		local @main::post_actions;
		my (@ran, @messages);
		local $main::second_print = sub { push(@messages, @_); };
		local *main::restart_apache = sub {
			push(@ran, 'apache');
			die "Controlled post exception\n" if $result eq 'exception';
			return $result eq 'zero' ? 0 : 1;
			};
		my $later = sub { push(@ran, 'later'); };
		register_post_action(\&restart_apache);
		register_post_action($later);
		is(run_post_actions(), $result eq 'success' ? 1 : 0, 'reports the action result');
		is_deeply(\@ran, [ 'apache', 'later' ], 'runs the remaining actions');
		is_deeply(\@main::post_actions, [], 'consumes completed actions');
		like(join(' ', @messages), qr/Controlled post exception/, 'preserves the error')
			if $result eq 'exception';
		is(run_post_actions(), 1, 'an empty queue succeeds');
		};
	}

# Untyped callbacks have no status contract and must still run in void context.
subtest 'legacy callback compatibility' => sub {
	local @main::post_actions;
	my @contexts;
	foreach my $value (0, '', undef) {
		register_post_action(sub {
			push(@contexts, defined(wantarray) ? 'value' : 'void');
			return $value;
			});
		}
	is(run_post_actions(), 1, 'zero counts and empty values are not failures');
	is_deeply(\@contexts, [ ('void') x 3 ], 'retains the calling context');
	my @messages;
	local $main::second_print = sub { push(@messages, @_); };
	register_post_action(sub { die "Legacy callback failed\n"; });
	is(run_post_actions(), 0, 'exceptions from arbitrary callbacks still fail');
	like(join(' ', @messages), qr/Legacy callback failed/, 'prints their errors');
	};

# Filtering must retain skipped work, and repeated actions still run only once.
subtest 'filtering and deduplication' => sub {
	local @main::post_actions;
	my ($apache, $fpm) = (0, 0);
	local *main::restart_apache = sub { $apache++; return 1; };
	local *main::restart_php_fpm_server = sub { $fpm++; return 0; };
	register_post_action(\&restart_apache);
	register_post_action(\&restart_apache);
	register_post_action(\&restart_php_fpm_server, { init => 'fixture-fpm' });
	is(run_post_actions(\&restart_apache), 1, 'only selected actions affect status');
	is($apache, 1, 'runs a duplicated reload once');
	is($fpm, 0, 'does not run the skipped action');
	is(scalar(@main::post_actions), 1, 'keeps the skipped action queued');
	is(run_post_actions(), 0, 'reports the queued service failure when run');
	is($fpm, 1, 'runs the queued action once');
	};

subtest 'restart replaces reload' => sub {
	local @main::post_actions;
	my @modes;
	local *main::restart_apache = sub { push(@modes, $_[0]); return 1; };
	register_post_action(\&restart_apache, 0);
	register_post_action(\&restart_apache, 1);
	is(run_post_actions(), 1, 'restart succeeds');
	is_deeply(\@modes, [ 1 ], 'suppresses the redundant reload');
	};

# Run the actual Apache wrapper with only its backend and file locks replaced.
foreach my $case (qw(success config_error stopped reload_error reload_empty
		     reload_exception stop_error start_error restart_success)) {
	subtest "Apache $case" => sub {
		local %main::config = (check_apache => $case eq 'config_error');
		local %apache::httpd_modules = (core => 2.0);
		local $main::module_config_directory = '/fixture';
		my (%locks, @messages, @calls);
		local $main::first_print = sub { };
		local $main::second_print = sub { push(@messages, @_); };
		local *main::require_apache = sub { };
		local *main::lock_file = sub { $locks{$_[0]} = 1; };
		local *main::unlock_file = sub { delete($locks{$_[0]}); };
		local *main::get_apache_pid = sub { $case eq 'stopped' ? undef : $$ };
		local *apache::test_config = sub { 'Controlled config failure' };
		local *apache::restart_apache = sub {
			push(@calls, 'reload');
			die "Controlled reload exception\n" if $case eq 'reload_exception';
			return '' if $case eq 'reload_empty';
			return $case eq 'reload_error' ? 'Controlled reload failure' : undef;
			};
		local *apache::stop_apache = sub {
			push(@calls, 'stop');
			return $case eq 'stop_error' ? 'Controlled stop failure' : undef;
			};
		local *apache::start_apache = sub {
			push(@calls, 'start');
			return $case eq 'start_error' ? 'Controlled start failure' : undef;
			};
		my $full = $case =~ /^(stop_error|start_error|restart_success)$/;
		my $rv = eval { restart_apache($full ? 1 : 0) };
		my $err = $@;
		if ($case eq 'reload_exception') {
			like($err, qr/Controlled reload exception/, 'propagates the exception');
			}
		else {
			is($err, '', 'does not throw for a returned error');
			is($rv, $case =~ /^(success|restart_success)$/ ? 1 : 0,
				'reports the backend outcome');
			}
		is_deeply(\%locks, {}, 'releases the restart lock on every path');
		is_deeply(\@calls, [ 'stop' ], 'does not start after a failed stop')
			if $case eq 'stop_error';
		is_deeply(\@calls, [], 'does not reload a rejected configuration')
			if $case eq 'config_error';
		};
	}
done_testing();
