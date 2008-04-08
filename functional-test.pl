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
$test_target_domain = "exampletarget.com";
$test_subdomain = "example.net";
$test_user = "testy";
$test_alias = "testing";
$test_reseller = "testsel";
$timeout = 60;			# Longest time a test should take
$wget_command = "wget -O - --cache=off --proxy=off ";
$migration_dir = "/usr/local/webadmin/virtualmin/migration";
$migration_ensim_domain = "apservice.org";
$migration_ensim = "$migration_dir/$migration_ensim_domain.ensim.tar.gz";
$migration_cpanel_domain = "hyccchina.com";
$migration_cpanel = "$migration_dir/$migration_cpanel_domain.cpanel.tar.gz";
$migration_plesk_domain = "requesttosend.com";
$migration_plesk = "$migration_dir/$migration_plesk_domain.plesk.txt";
$migration_plesk_windows_domain = "sbcher.com";
$migration_plesk_windows = "$migration_dir/$migration_plesk_windows_domain.plesk_windows.psa";
$test_backup_file = "/tmp/$test_domain.tar.gz";

@create_args = ( [ 'limits-from-template' ],
		 [ 'no-email' ],
		 [ 'no-slaves' ],
	  	 [ 'no-secondaries' ] );

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
	elsif ($a eq "--skip-test") {
		push(@skips, shift(@ARGV));
		}
	elsif ($a eq "--no-cleanup") {
		$no_cleanup = 1;
		}
	elsif ($a eq "--output") {
		$output = 1;
		}
	elsif ($a eq "--migrate") {
		$migrate = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

$prefix = &compute_prefix($test_domain);
$test_full_user = &userdom_name($test_user, { 'dom' => $test_domain,
					      'prefix' => $prefix });
($test_domain_user) = &unixuser_name($test_domain);
($test_target_domain_user) = &unixuser_name($test_target_domain);

# Build list of test types
$domains_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'postgres' ], [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
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

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       'http://'.$test_domain_user.':smeg@localhost:10000/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_user.' -e "select version()"',
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

	# Check new Webmin password
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       'http://'.$test_domain_user.':newpass@localhost:10000/',
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
		      @create_args, ],
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
		      @create_args, ],
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

	# Check user's MySQL login
	{ 'command' => 'mysql -u '.$test_full_user.' -pnewpass '.$test_domain_user.' -e "select version()"',
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
		      @create_args, ],
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
$reseller_tests = [
	# Create a reseller
	{ 'command' => 'create-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test reseller' ],
		      [ 'email', $test_reseller.'@'.$test_domain ] ],
	},

	# Verify that he exists
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'multiline' ] ],
	  'grep' => [ '^'.$test_reseller,
		      'Description: Test reseller',
		      'Email: '.$test_reseller.'@'.$test_domain,
		    ],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       'http://'.$test_reseller.':smeg@localhost:10000/',
	},

	# Make changes
	{ 'command' => 'modify-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'desc', 'New description' ],
		      [ 'email', 'newmail@'.$test_domain ],
		      [ 'max-doms', 66 ],
		      [ 'allow', 'web' ],
		      [ 'logo', 'http://'.$test_domain.'/logo.gif' ],
		      [ 'link', 'http://'.$test_domain ] ],
	},

	# Check new reseller details
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'multiline' ] ],
	  'grep' => [ 'Description: New description',
		      'Email: newmail@'.$test_domain,
		      'Maximum domains: 66',
		      'Allowed features:.*web',
		      'Logo URL: http://'.$test_domain.'/logo.gif',
		      'Logo link: http://'.$test_domain,
		    ],
	},

	# Delete the reseller
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ] ],
	  'cleanup' => 1 },
	];

# Script tests
$script_tests = [
	# Create a domain for the scripts
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'mysql' ], [ 'dns' ],
		      @create_args, ],
        },

	# List all scripts
	{ 'command' => 'list-available-scripts.pl',
	  'grep' => 'WordPress',
	},

	# Install Wordpress
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'path', '/wordpress' ],
		      [ 'db', 'mysql '.$test_domain_user ],
		      [ 'version', 'latest' ] ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/wordpress/',
	  'grep' => 'WordPress installation',
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Database tests
$database_tests = [
	# Create a domain for the databases
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ], [ 'postgres' ],
		      @create_args, ],
        },

	# Add a MySQL database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Check that we can login to MySQL
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_user.'_extra -e "select version()"',
	},

	# Create a PostgreSQL database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_user.'_extra2' ] ],
	},

	# Make sure both databases appear in the list
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_domain_user.'_extra',
		      '^'.$test_domain_user.'_extra2' ],
	},

	# Drop the MySQL database
	{ 'command' => 'delete-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Drop the PostgreSQL database
	{ 'command' => 'delete-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_user.'_extra2' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Proxy tests
$proxy_tests = [
	# Create the domain for proxies
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ],
		      @create_args, ],
        },

	# Create a proxy to Google
	{ 'command' => 'create-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ],
		      [ 'url', 'http://www.google.com/' ] ],
	},

	# Test that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => '<title>Google',
	},

	# Check the proxy list
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => '/google/',
	},

	# Delete the proxy
	{ 'command' => 'delete-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Migration tests
$migrate_tests = [
	# Migrate an ensim backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'ensim' ],
		      [ 'source', $migration_ensim ],
		      [ 'domain', $migration_ensim_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_ensim_domain,
		      'migrated\s+5\s+aliases' ],
	  'migrate' => 'ensim',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure ensim migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_ensim_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: apservice',
		      'Features: unix dir mail dns web webalizer',
		      'Server quota:\s+30\s+MB' ],
	  'migrate' => 'ensim',
	},

	# Cleanup the ensim domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_ensim_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'ensim',
	},

	# Migrate a cPanel backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'cpanel' ],
		      [ 'source', $migration_cpanel ],
		      [ 'domain', $migration_cpanel_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_cpanel_domain,
		      'migrated\s+4\s+mail\s+users',
		      'created\s+1\s+list',
		      'created\s+1\s+database',
		    ],
	  'migrate' => 'cpanel',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure cPanel migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_cpanel_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: adam',
		      'Features: unix dir mail dns web webalizer mysql',
		    ],
	  'migrate' => 'cpanel',
	},

	# Cleanup the cpanel domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_cpanel_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'cpanel',
	},

	# Migrate a Plesk for Linux backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'plesk' ],
		      [ 'source', $migration_plesk ],
		      [ 'domain', $migration_plesk_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_plesk_domain,
		      'migrated\s+3\s+users',
		      'migrated\s+1\s+alias',
		      'migrated\s+1\s+databases,\s+and\s+created\s+1\s+user',
		    ],
	  'migrate' => 'plesk',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: rtsadmin',
		      'Features: unix dir mail dns web webalizer logrotate mysql spam virus',
		    ],
	  'migrate' => 'plesk',
	},

	# Cleanup the plesk domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_plesk_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'plesk',
	},

	# Migrate a Plesk for Windows backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'plesk' ],
		      [ 'source', $migration_plesk_windows ],
		      [ 'domain', $migration_plesk_windows_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.
			$migration_plesk_windows_domain,
		      'migrated\s+2\s+users',
		      'migrated\s+1\s+alias',
		    ],
	  'migrate' => 'plesk_windows',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_windows_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: sbcher',
		      'Features: unix dir mail dns web logrotate spam',
		    ],
	  'migrate' => 'plesk_windows',
	},

	# Cleanup the plesk domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_plesk_windows_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'plesk_windows',
	},

	];
if (!-d $migration_dir) {
	$migrate_tests = [ { 'command' => 'echo Migration files under '.$migration_dir.' were not found in this system' } ];
	}

# Move domain tests
$move_tests = [
	# Create a parent domain to be moved
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a domain to be the target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Add a user to the domain being moved
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Move under the target
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'parent', $test_target_domain ] ],
	},

	# Make sure the old Unix user is gone
	{ 'command' => 'grep ^'.$test_domain_user.': /etc/passwd',
	  'fail' => 1,
	},

	# Make sure the website still works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Make sure the parent domain and user are correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'Parent domain: '.$test_target_domain,
		      'Username: '.$test_target_domain_user ],
	},

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Move back to top-level
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'newuser', $test_domain_user ],
		      [ 'newpass', 'smeg' ] ],
	},

	# Make sure the Unix user is back
	{ 'command' => 'grep ^'.$test_domain_user.': /etc/passwd',
	},

	# Make sure the website still works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Make sure the parent domain and user are correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => 'Username: '.$test_domain_user,
	  'antigrep' => 'Parent domain:',
	},

	# Cleanup the domain being moved
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1 },
	];

# Backup tests
@post_restore_tests = (
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

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       'http://'.$test_domain_user.':smeg@localhost:10000/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_user.' -e "select version()"',
	},

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},
	);
$backup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Test that everything will works
	@post_restore_tests,

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Re-create from backup
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$mail_tests = [
	# Create a domain to get spam
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],

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

        # Send some mail to him
	{ 'command' => 'echo Hello World | mail -s "Test mail" '.
		       $test_user.'\@'.$test_domain,
	},

	# Give the mail server 30 seconds to deliver
	{ 'command' => 'sleep 30',
	},

	# Check procmail log for delivery
	# XXX

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
        },

$alltests = { 'domains' => $domains_tests,
	      'mailbox' => $mailbox_tests,
	      'alias' => $alias_tests,
	      'reseller' => $reseller_tests,
	      'script' => $script_tests,
	      'database' => $database_tests,
	      'proxy' => $proxy_tests,
	      'migrate' => $migrate_tests,
	      'move' => $move_tests,
	      'backup' => $backup_tests,
              'mail' => $mail_tests,
	    };

# Run selected tests
$total_failed = 0;
if (!@tests) {
	@tests = keys %$alltests;
	}
@tests = grep { &indexof($_, @skips) < 0 } @tests;
foreach $tt (@tests) {
	print "Running $tt tests ..\n";
	@tts = @{$alltests->{$tt}};
	$allok = 1;
	$count = 0;
	$failed = 0;
	$total = 0;
	local $i = 0;
	foreach $t (@tts) {
		$t->{'index'} = $i++;
		}
	if ($migrate) {
		# Limit migration tests to one type
		@tts = grep { !$_->{'migrate'} ||
			      $_->{'migrate'} eq $migrate } @tts;
		}
	$lastt = undef;
	foreach $t (@tts) {
		$lastt = $t;
		$total++;
		$ok = &run_test($t);
		if (!$ok) {
			$allok = 0;
			$failed++;
			last;
			}
		$count++;
		}
	if (!$allok && ($count || $lastt->{'always_cleanup'}) && !$no_cleanup) {
		# Run cleanup
		($cleaner) = grep { $_->{'cleanup'} &&
				    $_->{'index'} >= $lastt->{'index'} } @tts;
		if ($cleaner && $cleaner ne $lastt) {
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
local $out = &backquote_with_timeout("$cmd 2>&1 </dev/null",
				     $t->{'timeout'} || $timeout);
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
print $out if ($output);
print "    .. success\n";
return 1;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
local $mig = join("|", @migration_types);
print "Runs some or all Virtualmin functional tests.\n";
print "\n";
print "usage: functional-tests.pl [--domain test.domain]\n";
print "                           [--test type]*\n";
print "                           [--skip-test type]*\n";
print "                           [--no-cleanup]\n";
print "                           [--output]\n";
print "                           [--migrate $mig]\n";
exit(1);
}


