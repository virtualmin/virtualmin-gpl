#!/usr/bin/perl
# Check delay configuration against temporary files without touching services.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;

# Load the production greylisting code and milter parser.
do "$FindBin::Bin/../postgrey-lib.pl" or die "$@ $!";
do "$FindBin::Bin/../ratelimit-lib.pl" or die "$@ $!";

my $dir = tempdir(CLEANUP => 1);
my $file = "$dir/options";
my ($backend, %cache);
no warnings qw(redefine once);
# get_postgrey_type(): Select the backend being tested.
*get_postgrey_type = sub { return $backend; };
# get_postgrey_options_file(): Route Postgrey writes to the fixture.
*get_postgrey_options_file = sub { return $file; };
# get_ratelimit_config_file(): Route milter writes to the same fixture.
*get_ratelimit_config_file = sub { return $file; };
# foreign_require(module): Avoid loading host service modules.
*foreign_require = sub { };
# lock_file(path), unlock_file(path): Avoid real locks in these unit tests.
*lock_file = sub { };
*unlock_file = sub { };
# error(message): Make configuration failures catchable by the tests.
*error = sub { die "configuration error\n"; };
# indexof(value, values...): Find a fixture value, or return -1 when absent.
*indexof = sub {
	my ($wanted, @list) = @_;
	for(my $i=0; $i<@list; $i++) {
		# Match parsed directives for the shared writer.
		return $i if ($wanted && $wanted eq $list[$i]);
		}
	return -1;
	};

# read_file_lines(path) supplies Webmin's cached line interface for fixtures.
sub read_file_lines
{
my ($path) = @_;
if (!$cache{$path}) {
	# Load once so later reads see any pending edits to this fixture.
	open(my $fh, '<', $path) or die $!;
	my @lines = <$fh>;
	chomp(@lines);
	$cache{$path} = \@lines;
	}
return $cache{$path};
}

# flush_file_lines(path) writes only the temporary test configuration.
sub flush_file_lines
{
my ($path) = @_;
open(my $fh, '>', $path) or die $!;
print $fh join("\n", @{$cache{$path}}), "\n";
close($fh) or die $!;
}

# read_env_file(path, &values, [comments], [&lines])
# Reads fixture assignments and optional line numbers. The comments flag is
# accepted but unused. These fixtures only need active assignments.
sub read_env_file
{
my ($path, $values, $comments, $lines) = @_;
my $lref = read_file_lines($path);
for(my $i=0; $i<@$lref; $i++) {
	# Read fixture assignments and strip comments after quoted values.
	next if ($lref->[$i] !~ /^\s*(?:export\s+)?(\w+)\s*=\s*(.*)$/);
	my ($name, $value) = ($1, $2);
	$value =~ s/^(["'])(.*)\1\s*(?:#.*)?$/$2/;
	$values->{$name} = $value;
	# Supply line positions when the caller plans to replace a variable.
	$lines->{$name} = $i if ($lines);
	}
}

# fixture(contents) replaces the temporary configuration and resets the cache.
sub fixture
{
my ($contents) = @_;
%cache = ();
open(my $fh, '>', $file) or die $!;
print $fh $contents;
close($fh) or die $!;
}

# contents() reads the saved configuration independently of the line cache.
sub contents
{
open(my $fh, '<', $file) or die $!;
local $/;
return <$fh>;
}

# Postgrey package settings callback(): Check defaults and manual overrides.
subtest 'Postgrey package settings' => sub {
	# Default to five minutes while preserving other package options.
	$backend = 'postgrey';
	local %main::config;
	fixture("# Keep this comment\nPOSTGREY_OPTS=\"--inet=10023\"\n".
		"POSTGREY_TEXT='Please try again'\n");
	save_postgrey_delay();
	like(contents(), qr/--inet=10023 --delay=300/,
		'missing module setting defaults to five minutes');
	like(contents(), qr/POSTGREY_TEXT='Please try again'/,
		'unrelated startup options are untouched');

	# POSTGREY_OPTS must override the separate delay used by RPM packages.
	fixture("POSTGREY_DELAY=\"--delay=60\"\n".
		"POSTGREY_OPTS='--max-age=35 --delay 120' # custom\n");
	$main::config{'postgrey_delay'} = 300;
	save_postgrey_delay();
	like(contents(), qr/POSTGREY_DELAY="--delay=60"/,
		'package variable is preserved');
	like(contents(), qr/POSTGREY_OPTS='--max-age=35 --delay=300' # custom/,
		'override replaces the old delay and preserves quoting and comment');

	# Create an options variable when only the package's delay is present.
	fixture("POSTGREY_DELAY=\"--delay=60\"\n");
	$main::config{'postgrey_delay'} = 45;
	save_postgrey_delay();
	like(contents(), qr/POSTGREY_OPTS="--delay=45"/,
		'manual module override is written when options are missing');
	# Reapplying an override must not duplicate the delay argument.
	my $before = contents();
	save_postgrey_delay();
	is(contents(), $before, 'applying the same delay makes no further changes');
	};

# Milter defaults and custom rules callback(): Limit changes to the default ACL.
subtest 'milter defaults and custom rules' => sub {
	# Saving a delay must keep the default rule's whitelist action.
	$backend = 'milter';
	local %main::config;
	fixture("racl whitelist default\n");
	save_postgrey_delay();
	is(contents(), "racl whitelist default delay 300s\n",
		'saving the default does not enable greylisting');
	# Enabling greylisting must retain the saved delay.
	enable_postgrey_milter_greylisting();
	is(contents(), "racl greylist default delay 300s\n",
		'enabled greylisting uses five minutes');

	# Override the global delay on the default ACL only.
	fixture("greylist 10m\nracl greylist default delay 30m\n");
	save_postgrey_delay();
	like(contents(), qr/racl greylist default delay 300s/,
		'module default replaces an existing default ACL delay');
	like(contents(), qr/^greylist 10m\n/, 'global setting is retained');

	# Preserve custom rules, continued lines and quoted reply text.
	fixture("racl greylist addr 192.0.2.0/24 delay 1h\n".
		"acl \"fallback\" greylist default \\\n".
		" delay 15m autowhite 30d msg \"delay 5m\" # keep this\n");
	$main::config{'postgrey_delay'} = 60;
	save_postgrey_delay();
	# Verify the override changes only the default rule's numeric delay.
	like(contents(), qr/default\s+\\\n\s+delay 60s/,
		'manual override preserves the multiline rule');
	like(contents(), qr/addr 192\.0\.2\.0\/24 delay 1h/,
		'specific rule is unchanged');
	like(contents(), qr/autowhite 30d msg "delay 5m" # keep this/,
		'other options, message and inline comment survive');
	# Disabling greylisting must retain the last saved delay.
	disable_postgrey_milter_greylisting();
	like(contents(), qr/whitelist default\s+\\\n\s+delay 60s/,
		'disabling retains the configured delay');

	# A missing default rule must be created without activating greylisting.
	fixture("# No default ACL\n");
	save_postgrey_delay();
	like(contents(), qr/racl whitelist default delay 60s/,
		'a missing default ACL is created');
	};

# Enable callback(): Check save/start ordering and service failure handling.
subtest 'enabling applies the delay before starting either backend' => sub {
	local %main::config;
	# first_print(message), second_print(message): Suppress progress output.
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	my ($running, $service_ok, @actions) = (0, 1);
	# find_byname(name): Return the test's simulated running state.
	local *find_byname = sub { return $running; };
	# get_postgrey_port(): Keep listener selection outside this test.
	local *get_postgrey_port = sub { return 10023; };
	# init::action_status(name): Model an existing service enabled at boot.
	local *init::action_status = sub { return 2; };
	# init::start_action(name): Check the default before simulating startup.
	local *init::start_action = sub {
		push(@actions, 'start');
		like(contents(), qr/--delay=300/, 'default saved before startup');
		return ($service_ok, 'test failure');
		};
	# init::restart_action(name): Check the override before a fake restart.
	local *init::restart_action = sub {
		push(@actions, 'restart');
		like(contents(), qr/--delay=60/, 'override saved before restart');
		return ($service_ok, 'test failure');
		};
	# require_mail(): Record when enable reaches Postfix setup.
	local *require_mail = sub { push(@actions, 'postfix'); };
	# postfix::get_real_value(name): Supply a matching policy endpoint.
	local *postfix::get_real_value = sub {
		return 'check_policy_service inet:127.0.0.1:10023';
		};
	# text(key, [values...]): Return the key without loading translations.
	local *text = sub { return $_[0]; };
	# html_escape(value): Pass the fixed test error text through unchanged.
	local *html_escape = sub { return $_[0]; };
	# Starting a stopped service must happen after the default is saved.
	$backend = 'postgrey';
	fixture("POSTGREY_OPTS=\"--inet=10023\"\n");
	ok(enable_postgrey(), 'stopped Postgrey is enabled');
	is_deeply(\@actions, [ 'start', 'postfix' ], 'service starts before Postfix setup');
	# A running service must restart to pick up the manual override.
	$running = 1;
	$main::config{'postgrey_delay'} = 60;
	@actions = ();
	ok(enable_postgrey(), 'running Postgrey is enabled with a new delay');
	is_deeply(\@actions, [ 'restart', 'postfix' ], 'running service is restarted');
	# A restart failure must prevent the later Postfix setup step.
	$service_ok = 0;
	@actions = ();
	ok(!enable_postgrey(), 'restart failure is reported');
	is_deeply(\@actions, [ 'restart' ], 'failed service is not added to Postfix');

	$backend = 'milter';
	fixture("racl whitelist default\n");
	# enable_postgrey_milter(): Check the delay, then activate the fixture.
	local *enable_postgrey_milter = sub {
		like(contents(), qr/whitelist default delay 60s/,
			'milter override is saved before enabling the backend');
		enable_postgrey_milter_greylisting();
		return 1;
		};
	ok(enable_postgrey(), 'milter backend is enabled');
	like(contents(), qr/greylist default delay 60s/, 'enabled ACL keeps the override');
	};

# Invalid settings callback(): Reject bad delays before either backend changes.
subtest 'invalid module settings cannot change configuration' => sub {
	local %main::config;
	foreach my $type ('postgrey', 'milter') {
		$backend = $type;
		fixture("# Must remain unchanged\n");
		my $before = contents();
		# Cover bad numbers, units, newlines, shell text and overflow.
		foreach my $value ('', 0, -1, '1.5', '5m', "60\n",
				   '60;false', 2147483648) {
			$main::config{'postgrey_delay'} = $value;
			my $ok = eval { enable_postgrey(); 1 };
			ok(!$ok, "$type rejects invalid input");
			is(contents(), $before, 'configuration is unchanged');
			}
		}
	};

# Quoted comments callback(): Distinguish syntax from literal message content.
subtest 'quoted inline comments' => sub {
	# Quotes in a trailing comment must not absorb the delay argument.
	$backend = 'postgrey';
	local %main::config;
	fixture('POSTGREY_OPTS="--inet=10023" # "Custom options"'."\n");
	save_postgrey_delay();
	is(contents(), 'POSTGREY_OPTS="--inet=10023 --delay=300" # "Custom options"'."\n",
		'delay stays inside the option value and before the comment');
	# A quoted hash must remain part of the milter reply text.
	$backend = 'milter';
	fixture('racl whitelist default msg "Try again # later"'."\n");
	save_postgrey_delay();
	like(contents(), qr/msg "Try again # later" delay 300s/,
		'literal hash in the reply text survives');
	# Continue past that message to replace a delay on the following line.
	fixture('racl whitelist default msg "Try again # later" \\'."\n".
		' delay 30m # Keep the reply text'."\n");
	save_postgrey_delay();
	like(contents(), qr/msg "Try again # later" \\\n delay 300s # Keep the reply text/,
		'existing delay on a continued line is replaced');
	};

# Unclosed quotes callback(): Check that parsing fails without partial edits.
subtest 'unclosed quotes abort enabling without changing configuration' => sub {
	$backend = 'milter';
	local %main::config;
	my ($locked, $enabled);
	# lock_file(path), unlock_file(path): Track lock cleanup.
	local *lock_file = sub { $locked = 1; };
	local *unlock_file = sub { $locked = 0; };
	# enable_postgrey_milter(): Record an unexpected enable attempt.
	local *enable_postgrey_milter = sub { $enabled++; };
	# text(key, [values...]): Keep the error key, line and path visible.
	local *text = sub { return join(' ', @_); };
	# html_escape(value): Keep the fixture path readable in the test error.
	local *html_escape = sub { return $_[0]; };
	# error(message): Raise the full error text for location checks.
	local *error = sub { die $_[0]."\n"; };
	foreach my $prefix ('', "racl whitelist default delay 30m \\\n") {
		# A later parse failure must also discard earlier line edits.
		my $rule = $prefix || 'racl whitelist default ';
		fixture($rule.'msg "Try again'."\n");
		my $before = contents();
		my $line = $prefix ? 2 : 1;
		my $ok = eval { enable_postgrey(); 1 };
		# Check the error location, unchanged data and cleanup.
		ok(!$ok, 'enabling fails for an unclosed quote');
		like($@, qr/postgrey_eparse $line /,
			'error identifies the line that could not be parsed');
		is(contents(), $before, 'file is unchanged');
		is(join("\n", @{read_file_lines($file)})."\n", $before,
			'cached configuration is unchanged');
		ok(!$locked, 'configuration lock is released');
		ok(!$enabled, 'backend is not enabled');
		}
	};

done_testing();
