#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

# Count slept seconds instead of really sleeping in startup wait loops
BEGIN {
	*CORE::GLOBAL::sleep = sub { $main::slept += $_[0] };
	}

do "$FindBin::Bin/../wizard-lib.pl"
	or die "Failed to load wizard-lib.pl: $@ $!";

# Run the database wizard parser with database and service calls stubbed out
sub run_db_wizard
{
my (%opts) = @_;
my @postgres_calls;
my $result;
my $running = $opts{'running'};
$main::slept = 0;

{
	no warnings qw(redefine once);
	local %main::config;
	local %main::text;
	local $postgresql::hba_conf_file = $opts{'hba_conf_file'};
	local *main::foreign_require = sub { };
	local *main::require_mysql = sub { };
	local *mysql::stop_mysql = sub { };
	local *main::require_postgres = sub { };
	local *main::foreign_installed = sub {
		push(@postgres_calls, 'configured') if ($_[1]);
		return $_[1] ? ($opts{'configured'} // 2) : 1;
		};
	local *main::save_module_config = sub { };
	local *main::text = sub {
		my ($key, @args) = @_;
		return join(":", $key, @args);
		};
	local *init::action_status = sub {
		return $opts{'no_service_action'} ? 0 : 1;
		};
	local *init::status_action = sub {
		push(@postgres_calls, 'service');
		return defined($opts{'service_status'}) ?
			$opts{'service_status'} : $running == 1 ? 1 : 0;
		};
	local *init::enable_at_boot = sub { };
	local *init::disable_at_boot = sub { };
	local *postgresql::is_postgresql_local = sub {
		return $opts{'local'};
		};
	local *postgresql::setup_postgresql = sub {
		push(@postgres_calls, 'setup');
		$running = 1 if ($opts{'setup_starts'});
		return $opts{'setup_error'};
		};
	local *postgresql::is_postgresql_running = sub {
		push(@postgres_calls, 'running');
		my $checks = grep { $_ eq 'running' } @postgres_calls;
		$running = 1 if ($opts{'ready_after'} &&
				 $checks >= $opts{'ready_after'});
		return $running;
		};
	local *postgresql::start_postgresql = sub {
		push(@postgres_calls, 'start');
		return $opts{'start_error'} if ($opts{'start_error'});
		$running = 1 if (!$opts{'start_slow'});
		return undef;
		};
	local *postgresql::stop_postgresql = sub { };

	$result = &main::wizard_parse_db({ 'postgres' => 1 });
	}

return ($result, \@postgres_calls);
}

subtest 'an uninitialized local server is set up before it is started' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => 0,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls,
		[ 'running', 'service', 'setup', 'service', 'start',
		  'running' ],
		'stopped service is initialized before startup');
	};

subtest 'an initialized server is only started' => sub {
	my ($result, $calls) = run_db_wizard(
		'hba_conf_file' => '/var/lib/pgsql/data/pg_hba.conf',
		'local' => 1,
		'running' => 0,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls, [ 'running', 'start', 'running', 'configured' ],
		'existing PostgreSQL configuration is not initialized again');
	};

subtest 'a remote server is never initialized locally' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 0,
		'running' => 0,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls, [ 'running', 'start', 'running', 'configured' ],
		'remote PostgreSQL setup is skipped');
	};

subtest 'initialization errors stop before startup' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => 0,
		'setup_error' => 'setup failed',
		);
	is($result, 'wizard_epostgressetup:setup failed',
		'initialization error is returned');
	is_deeply($calls, [ 'running', 'service', 'setup' ],
		'startup is not attempted');
	};

subtest 'startup errors after initialization are returned' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => 0,
		'start_error' => 'start failed',
		);
	is($result, 'wizard_epostgresstart:start failed',
		'startup error is returned');
	is_deeply($calls,
		[ 'running', 'service', 'setup', 'service', 'start' ],
		'configured-module check is not attempted');
	};

subtest 'new cluster connection errors are returned' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => -1,
		'configured' => 1,
		);
	is($result, 'wizard_epostgresconf:../postgresql/',
		'connection error is returned');
	is_deeply($calls, [ 'running', 'configured' ],
		'initialization and startup are not attempted');
	};

subtest 'setup may start the server itself' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => 0,
		'setup_starts' => 1,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls, [ 'running', 'service', 'setup', 'service' ],
		'already-running PostgreSQL is not started again');
	};

subtest 'new cluster validation ignores stale module configuration' => sub {
	my ($result, $calls) = run_db_wizard(
		'configured' => 1,
		'local' => 1,
		'running' => 0,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls,
		[ 'running', 'service', 'setup', 'service', 'start',
		  'running' ],
		'stale module configuration is not used for a new cluster');
	};

subtest 'a running server without discovered configuration is not initialized' => sub {
	my ($result, $calls) = run_db_wizard(
		'configured' => 1,
		'local' => 1,
		'running' => 1,
		);
	is($result, 'wizard_epostgresconf:../postgresql/',
		'module configuration error is returned');
	is_deeply($calls, [ 'running', 'configured' ],
		'running PostgreSQL is not initialized or started');
	};

subtest 'an active service that cannot be reached is not initialized' => sub {
	my ($result, $calls) = run_db_wizard(
		'configured' => 1,
		'local' => 1,
		'running' => 0,
		'service_status' => 1,
		);
	is($result, 'wizard_epostgresconf:../postgresql/',
		'module configuration error is returned');
	is_deeply($calls, [ 'running', 'service', 'configured' ],
		'active PostgreSQL service is not initialized or started');
	};

subtest 'a missing service action falls back to module setup' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'no_service_action' => 1,
		'running' => 0,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls, [ 'running', 'setup', 'start', 'running' ],
		'module setup runs when no service action exists');
	};

subtest 'startup waits for the server to become reachable' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'ready_after' => 4,
		'running' => 0,
		'start_slow' => 1,
		);
	is($result, undef, 'wizard step succeeds');
	is_deeply($calls,
		[ 'running', 'service', 'setup', 'service', 'start',
		  'running', 'running', 'running' ],
		'startup is polled until the server accepts connections');
	is($main::slept, 2, 'wizard waits between connection checks');
	};

subtest 'an unknown service state blocks setup and startup' => sub {
	my ($result, $calls) = run_db_wizard(
		'local' => 1,
		'running' => 0,
		'service_status' => -1,
		);
	is($result, 'wizard_epostgresconf:../postgresql/',
		'module configuration error is returned');
	is_deeply($calls, [ 'running', 'service' ],
		'PostgreSQL is not initialized or started');
	};

subtest 'spam filtering is asked before virus scanning' => sub {
	local %main::config = ( 'spam' => 1, 'virus' => 1 );
	local $main::mail_system = 0;
	my @steps = &main::get_wizard_steps();
	my %index = map { $steps[$_] => $_ } (0 .. $#steps);
	ok(defined($index{'spam'}), 'spam step is included');
	ok(defined($index{'virus'}), 'virus step is included');
	ok($index{'spam'} < $index{'virus'},
		'spam step is shown before the virus step');
	};

subtest 'virus scanning step requires spam filtering' => sub {
	local %main::config = ( 'spam' => 0, 'virus' => 1 );
	local $main::mail_system = 0;
	my @steps = &main::get_wizard_steps();
	is(scalar(grep { $_ eq 'virus' } @steps), 0,
		'virus step is skipped without spam filtering');
	};

subtest 'wizard navigation follows configuration changes' => sub {
	local %main::config = ( 'spam' => 1, 'virus' => 1 );
	local $main::mail_system = 0;
	my @old = &main::get_wizard_steps();
	my $next = &main::get_wizard_next_step('spam', \@old);
	is($old[$next], 'virus', 'next step follows the current one');
	$main::config{'virus'} = 0;
	my @new = &main::get_wizard_steps();
	$next = &main::get_wizard_next_step('virus', \@old);
	is($new[$next], 'db', 'removed step advances to the next surviving one');
	is(&main::get_wizard_next_step('done', \@new), undef,
		'wizard finishes after the last step');
	};

subtest 'enabling virus scanning preserves optional default state' => sub {
	no warnings qw(redefine once);
	local %main::config = ( 'spam' => 1, 'virus' => 2 );
	local *main::check_clamd_status = sub { return 0; };
	local *main::push_all_print = sub { };
	local *main::set_all_null_print = sub { };
	local *main::pop_all_print = sub { };
	local *main::disable_clamd = sub { };
	local *main::save_global_virus_scanner = sub { };
	local *main::save_module_config = sub { };
	my $result = &main::wizard_parse_virus({ 'clamd' => 2 });
	is($result, undef, 'wizard step succeeds');
	is($main::config{'virus'}, 2, 'enabled-but-not-default state is kept');
	};

subtest 'virus scanning cannot be enabled without spam filtering' => sub {
	local %main::config = ( 'spam' => 0, 'virus' => 1 );
	local %main::text = ( 'check_evirusspam' => 'evirusspam' );
	my $result = &main::wizard_parse_virus({ 'clamd' => 1 });
	is($result, 'evirusspam', 'enabling clamd is rejected');
	$result = &main::wizard_parse_virus({ 'clamd' => 2 });
	is($result, 'evirusspam', 'enabling clamscan is rejected');
	};

done_testing();
