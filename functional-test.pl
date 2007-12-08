#!/usr/local/bin/perl
# Runs all Virtualmin tests

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/functional-test.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "functional-test.pl must be run as root";
	}

# Parse command-line args
# XXX
# XXX test types to run
# XXX test domain for users/aliases/etc
# XXX need to rollback domain creation on failure?

# Build list of test types
$domains_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'feature-features' ],
		      [ 'limits-from-template' ] ],
        },

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'args' => [ ],
	  'grep' => "^\Q$test_domain\E",
	];

# XX
