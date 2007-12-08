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
$ENV{'PATH'} = "$module_root_directory:$ENV{'PATH'}";

# Make sure wget doesn't use a cache
$ENV{'http_proxy'} = undef;
$ENV{'ftp_proxy'} = undef;

$test_domain = "example.com";	# Never really exists
$test_subdomain = "example.net";
$test_user = "testy";
$test_alias = "testing";
$timeout = 60;			# Longest time a test should take
$wget_command = "wget -O - --cache=off --proxy=off ";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$test_domain = shift(@ARGV);
		}
	elsif ($a eq "--sub-domain") {
		$test_subdomain = shift(@ARGV);
		}
	elsif ($a eq "--test") {
		push(@tests, shift(@ARGV));
		}
	elsif ($a eq "--no-cleanup") {
		$no_cleanup = 1;
		}
	else {
		&usage();
		}
	}

$prefix = &compute_prefix($test_domain);
$test_full_user = &userdom_name($test_user, { 'dom' => $test_domain,
					      'prefix' => $prefix });
($test_domain_user) = &unixuser_name($test_domain);

# XXX test domain for users/aliases/etc
# XXX don't run remote actions

# Build list of test types
$domains_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'postgres' ], [ 'spam' ], [ 'virus' ],
		      [ 'limits-from-template' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      [ 'no-email' ] ],
        },

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Disable a feature
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webalizer' ] ],
	},

	# Re-enable a feature
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webalizer' ] ],
	},

	# Change some attributes
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'desc' => 'New description' ],
		      [ 'pass' => 'newpass' ],
		      [ 'quota' => 555*1024 ],
		      [ 'bw' => 666*1024 ] ],
	},

	# Check attribute changes
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'Password: newpass',
		      'Description: New description',
		      'Server quota: 555',
		      'Bandwidth limit: 666', ],
	},

	# Disable the whole domain
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Make sure website is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Test home page',
	},

	# Re-enable the domain
	{ 'command' => 'enable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Check website again
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Validate all features
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'postgres' ], [ 'spam' ], [ 'virus' ],
		      [ 'no-email' ] ],
	},

	# Make sure it worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'Description: Test sub-domain',
		      'Parent domain: '.$test_domain ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	];

# Mailbox tests
$mailbox_tests = [
	# Create a domain for testing
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mail' ], [ 'mysql' ],
		      [ 'limits-from-template' ],
		      [ 'no-email' ] ],
        },

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Make sure the mailbox exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Check Unix account
	{ 'command' => 'su -s /bin/sh '.$test_full_user.' -c "id -a"',
	  'grep' => 'uid=',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	},

	# Modify the user
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'pass' => 'newpass' ],
		      [ 'real' => 'New name' ],
		      [ 'add-mysql' => $test_domain_user ],
		      [ 'add-email' => 'extra@'.$test_domain ] ],
	},

	# Validate the modifications
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Password: newpass',
		      'Real name: New name',
		      'Databases:.*'.$test_domain_user,
		      'Extra addresses:.*extra@'.$test_domain, ],
	},

	# Delete the user
	{ 'command' => 'delete-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user' => $test_user ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Alias tests
$alias_tests = [
	# Create a domain for the aliases
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mail' ], [ 'dns' ],
		      [ 'limits-from-template' ],
		      [ 'no-email' ] ],
        },

	# Add a test alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Make sure it was created
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_domain,
		      '^ *nobody@webmin.com',
		      '^ *nobody@virtualmin.com' ],
	},

	# Make sure the mail server sees it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_alias.'@'.$test_domain ] ],
	},

	# Delete the alias
	{ 'command' => 'delete-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from' => $test_alias ] ],
	},

	# Make sure the server no longer sees it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_alias.'@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Create a simple autoreply alias
	{ 'command' => 'create-simple-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'autoreply', 'Test autoreply' ] ],
	},

	# Make sure it was created
	{ 'command' => 'list-simple-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Autoreply message: Test autoreply' ],
	},

	# Cleanup the aliases and domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Reseller tests
# XXX

# Script tests
# XXX

$alltests = { 'domains' => $domains_tests,
	      'mailbox' => $mailbox_tests,
	      'alias' => $alias_tests,
	      'reseller' => $reseller_tests,
	      'script' => $script_tests,
	    };

# Run selected tests
$total_failed = 0;
if (!@tests) {
	@tests = keys %$alltests;
	}
foreach $tt (@tests) {
	print "Running $tt tests ..\n";
	@tts = @{$alltests->{$tt}};
	$allok = 1;
	$count = 0;
	$failed = 0;
	$total = 0;
	foreach $t (@tts) {
		$total++;
		$ok = &run_test($t);
		if (!$ok) {
			$allok = 0;
			$failed++;
			last;
			}
		$count++;
		}
	if (!$allok && $count && !$no_cleanup) {
		# Run cleanup
		($cleaner) = grep { $_->{'cleanup'} } @tts;
		if ($cleaner && $cleaner ne $t) {
			$total++;
			&run_test($cleaner);
			}
		}
	$skip = @tts - $total;
	print ".. $count OK, $failed FAILED, $skip SKIPPED\n\n";
	$total_failed += $failed;
	}

if ($total_failed) {
	print "!!!!!!!!!!!!! $total_failed TESTS FAILED !!!!!!!!!!!!!!\n";
	}
exit($total_failed);

sub run_test
{
local ($t) = @_;
local $cmd = "$t->{'command'}";
foreach my $a (@{$t->{'args'}}) {
	if (defined($a->[1])) {
		if ($a->[1] =~ /\s/) {
			$cmd .= " --".$a->[0]." '".$a->[1]."'";
			}
		else {
			$cmd .= " --".$a->[0]." ".$a->[1];
			}
		}
	else {
		$cmd .= " --".$a->[0];
		}
	}
print "    Running $cmd ..\n";
sleep($t->{'sleep'});
local $out = &backquote_with_timeout("$cmd 2>&1 </dev/null", $timeout);
if ($? && !$t->{'fail'} || !$? && $t->{'fail'}) {
	print $out;
	print "    .. failed : $?\n";
	return 0;
	}
if ($t->{'grep'}) {
	# One line must match all regexps
	local @greps = ref($t->{'grep'}) ? @{$t->{'grep'}} : ( $t->{'grep'} );
	foreach my $grep (@greps) {
		local $match = 0;
		foreach my $l (split(/\r?\n/, $out)) {
			if ($l =~ /$grep/) {
				$match = 1;
				}
			}
		if (!$match) {
			print $out;
			print "    .. no match on $grep\n";
			return 0;
			}
		}
	}
if ($t->{'antigrep'}) {
	# No line must match all regexps
	local @greps = ref($t->{'antigrep'}) ? @{$t->{'antigrep'}}
					     : ( $t->{'antigrep'} );
	foreach my $grep (@greps) {
		local $match = 0;
		foreach my $l (split(/\r?\n/, $out)) {
			if ($l =~ /$grep/) {
				$match = 1;
				}
			}
		if ($match) {
			print $out;
			print "    .. unexpected match on $grep\n";
			return 0;
			}
		}
	}
print "    .. success\n";
return 1;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Runs some or all Virtualmin functional tests.\n";
print "\n";
print "usage: functional-tests.pl [--domain test.domain]\n";
print "                           [--test type]*\n";
exit(1);
}


