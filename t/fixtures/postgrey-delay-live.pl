#!/usr/bin/perl
# Load candidate helpers with the installed Webmin libraries on a test VM.
# Arguments: module path, candidate library, action, fixture path and delay.
# Use "-" for installed configuration and an empty delay for the default.

use JSON::PP;

# Require Linux, root and an explicit opt-in before loading Webmin.
my ($module, $candidate, $action, $fixture, $delay) = @ARGV;
$^O eq 'linux' && $> == 0 && $ENV{'VIRTUALMIN_GREYLIST_VM_TEST'} ||
	die "This fixture requires an opted-in Linux test VM\n";

# Load Webmin in its installed module context, then load the candidate helpers.
chdir($module) or die $!;
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
$0 = "$module/postgrey-delay-live.pl";
require './virtual-server-lib.pl';
do $candidate or die "$@ $!";

# Use candidate messages and make Webmin errors fail the test process.
my $language = $candidate;
$language =~ s/postgrey-lib\.pl$/lang\/en/;
&read_file($language, \%text);
$main::error_must_die = 1;

# Use private config files for parser checks and milter protocol tests.
if ($fixture ne '-') {
	no warnings 'redefine';
	if (&get_postgrey_type() eq 'milter') {
		# get_ratelimit_config_file(): Use the milter fixture.
		*get_ratelimit_config_file = sub { return $fixture; };
		}
	else {
		# get_postgrey_options_file(): Use the Postgrey fixture.
		*get_postgrey_options_file = sub { return $fixture; };
		}
	}
if ($action eq 'apply') {
	# Apply the module override without saving Webmin's config file.
	delete $config{'postgrey_delay'};
	$config{'postgrey_delay'} = $delay if (length($delay));
	&save_postgrey_delay();
	# Activate the fixture's default ACL for the milter protocol test.
	&enable_postgrey_milter_greylisting()
		if (&get_postgrey_type() eq 'milter');
	}
elsif ($action ne 'get') {
	# Reject unsupported actions so a typo fails the test.
	die "Unknown action\n";
	}

# Return only the configuration needed by the test driver.
print encode_json({
	backend => &get_postgrey_type(),
	options => &get_postgrey_options_file(),
	args => &get_postgrey_args(),
	}), "\n";
