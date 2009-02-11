#!/usr/local/bin/perl
# Runs all Virtualmin tests

use POSIX;
package virtual_server;
$no_virtualmin_plugins = 1;	# Save memory
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
$test_parallel_domain1 = "example1.net";
$test_parallel_domain2 = "example2.net";
$test_user = "testy";
$test_alias = "testing";
$test_alias_two = "yetanothertesting";
$test_reseller = "testsel";
$test_plan = "Test plan";
$timeout = 60;			# Longest time a test should take
$wget_command = "wget -O - --cache=off --proxy=off --no-check-certificate  ";
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
$test_backup_dir = "/tmp/functional-test-backups";
$test_email_dir = "/usr/local/webadmin/virtualmin/testmail";
$spam_email_file = "$test_email_dir/spam.txt";
$virus_email_file = "$test_email_dir/virus.txt";
$ok_email_file = "$test_email_dir/ok.txt";
$supports_fcgid = &indexof("fcgid", &supported_php_modes()) >= 0;

@create_args = ( [ 'limits-from-template' ],
		 [ 'no-email' ],
		 [ 'no-slaves' ],
	  	 [ 'no-secondaries' ] );

# Cleanup backup dir
system("rm -rf $test_backup_dir");
system("mkdir -p $test_backup_dir");

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
	elsif ($a eq "--user") {
		$webmin_user = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$webmin_pass = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
$webmin_wget_command = "wget -O - --cache=off --proxy=off --http-user=$webmin_user --http-passwd=$webmin_pass --user-agent=Webmin ";
&get_miniserv_config(\%miniserv);
$webmin_proto = "http";
if ($miniserv{'ssl'}) {
	eval "use Net::SSLeay";
	if (!$@) {
		$webmin_proto = "https";
		}
	}
$webmin_port = $miniserv{'port'};
$webmin_url = "$webmin_proto://localhost:$webmin_port";
if ($webmin_proto eq "https") {
	$webmin_wget_command .= "--no-check-certificate ";
	}

($test_domain_user) = &unixuser_name($test_domain);
$prefix = &compute_prefix($test_domain, $test_domain_user, undef, 1);
%test_domain = ( 'dom' => $test_domain,
		 'prefix' => $prefix,
		 'user' => $test_domain_user,
		 'group' => $test_domain_user,
		 'template' => &get_init_template() );
$test_full_user = &userdom_name($test_user, \%test_domain);
($test_target_domain_user) = &unixuser_name($test_target_domain);
$test_domain{'home'} = &server_home_directory(\%test_domain);
$test_domain_db = &database_name(\%test_domain);
$test_domain_cert = &default_certificate_file(\%test_domain, "cert");
$test_domain_key = &default_certificate_file(\%test_domain, "key");

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
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.':smeg@localhost:'.
		       $webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Check PHP execution
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Switch PHP mode to CGI
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'cgi' ] ],
	},

	# Check PHP running via CGI
	{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
	},

	$supports_fcgid ? (
		# Switch PHP mode to fCGId
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fcgid' ] ],
		},

		# Check PHP running via fCGId
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
		},
		) : ( ),

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
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.
		       ':newpass@localhost:'.$webmin_port.'/',
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
	{ 'command' => 'mysql -u '.$test_full_user.' -pnewpass '.$test_domain_db.' -e "select version()"',
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

	# Create another alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias_two ],
		      [ 'to', 'nobody@webmin.com' ] ],
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

	# Make sure the other alias still exists
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_alias_two.'@'.$test_domain,
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
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_reseller.
		       ':smeg@localhost:'.$webmin_port.'/',
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
		      [ 'db', 'mysql '.$test_domain_db ],
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
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
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
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.
		       ':smeg@localhost:'.$webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Test DNS lookup of sub-domain
	{ 'command' => 'host '.$test_subdomain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get of sub-domain
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test home page',
	},
	);
$backup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ], [ 'webmin' ],
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

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
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
		      [ 'domain', $test_subdomain ],
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

$multibackup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ], [ 'webmin' ],
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

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Back them both up to a directory
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Test that everything will works
	@post_restore_tests,

	# Delete the domains, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	];

$ssh_backup_prefix = "ssh://$test_target_domain_user:smeg\@localhost".
		     "/home/$test_target_domain_user";
$ftp_backup_prefix = "ftp://$test_target_domain_user:smeg\@localhost".
		     "/home/$test_target_domain_user";
$remotebackup_tests = [
	# Create a domain for the backup target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },
	
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Backup via SSH
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Delete the backups file
	{ 'command' => "rm -rf /home/$test_target_domain_user/$test_domain.tar.gz" },

	# Backup via FTP
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Backup via SSH in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore via SSH in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
	},

	# Delete the backups dir
	{ 'command' => "rm -rf /home/$test_target_domain_user/backups" },

	# Backup via FTP in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ftp_backup_prefix/backups" ] ],
	},

	# Restore via FTP in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/backups" ] ],
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
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
	},

	# Setup spam and virus delivery
	{ 'command' => 'modify-spam.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'virus-delete' ],
		      [ 'spam-file', 'spam' ],
		      [ 'spam-no-delete-level' ] ],
	},

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ],
		      [ 'no-creation-mail' ] ],
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

        # Send some reasonable mail to him
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	},

	# Check if the mail arrived
	{ 'command' => 'list-mailbox.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'user', $test_user ] ],
	  'grep' => [ 'Hello World', 'X-Spam-Status:' ],
	},

	-r $virus_email_file ? (
		# Add empty lines to procmail.log
		{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
		},

		# Send a virus message, if we have one
		{ 'command' => 'test-smtp.pl',
		  'args' => [ [ 'from', 'virus@virus.com' ],
			      [ 'to', $test_user.'@'.$test_domain ],
			      [ 'data', $virus_email_file ] ],
		},

		# Check procmail log for virus detection
		{ 'command' => 'while [ "`tail -5 /var/log/procmail.log |grep '.
			       'To:'.$test_user.'@'.$test_domain.
			       ' | grep Mode:Virus`" = "" ]; do '.
			       'sleep 5; done',
		  'timeout' => 60,
		},

		# Make sure it was NOT delivered
		{ 'command' => 'list-mailbox.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'user', $test_user ] ],
		  'antigrep' => 'Virus test',
		},
		) : ( ),

	-r $spam_email_file ? (
		# Add the spammer's address to this domain's blacklist
		{ 'command' => 'echo blacklist_from spam@spam.com >'.
			       $module_config_directory.'/spam/'.
			       '`./list-domains.pl --domain '.$test_domain.
			       ' --id-only`/virtualmin.cf',
		},

		# Add empty lines to procmail.log
		{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
		},

		# Send a spam message, if we have one
		{ 'command' => 'test-smtp.pl',
		  'args' => [ [ 'from', 'spam@spam.com' ],
			      [ 'to', $test_user.'@'.$test_domain ],
			      [ 'data', $spam_email_file ] ],
		},

		# Check procmail log for spam detection
		{ 'command' => 'while [ "`tail -5 /var/log/procmail.log |grep '.
			       'To:'.$test_user.'@'.$test_domain.
			       ' | grep Mode:Spam`" = "" ]; do '.
			       'sleep 5; done',
		  'timeout' => 60,
		},

		# Make sure it went to the spam folder
		{ 'command' => 'grep "Spam test" ~'.$test_full_user.'/spam',
		},
		) : ( ),

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },
	];

$prepost_tests = [
	# Create a domain just to see if scripts run
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_DOM >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_DOM >>/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure pre and post creation scripts run
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE '.$test_domain,
		      'AFTER '.$test_domain ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	# Change the password
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'pass', 'quux' ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_PASS $VIRTUALSERVER_NEWSERVER_PASS >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_PASS $VIRTUALSERVER_OLDSERVER_PASS >>/tmp/prepost-test.out' ],
		    ],
	},

	# Make sure the pre and post change scripts run
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE smeg quux',
		      'AFTER quux smeg' ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_DOM >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_DOM >>/tmp/prepost-test.out' ],
		    ],
	  'cleanup' => 1,
        },

	# Check the pre and post deletion scripts
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE '.$test_domain,
		      'AFTER '.$test_domain ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },
	];

$webmin_tests = [
	# Make sure the main Virtualmin page can be displayed
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/",
	  'grep' => [ 'Virtualmin Virtual Servers', 'Delete Selected' ],
	},

	# Create a test domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/domain_setup.cgi?dom=$test_domain&vpass=smeg&template=0&plan=0&vuser_def=1&email_def=1&mgroup_def=1&group_def=1&prefix_def=1&db_def=1&quota=100&quota_units=1048576&uquota=120&uquota_units=1048576&bwlimit_def=0&bwlimit=100&bwlimit_units=MB&mailboxlimit_def=1&aliaslimit_def=0&aliaslimit=34&dbslimit_def=0&dbslimit=10&domslimit_def=0&domslimit=3&nodbname=0&field_purpose=&field_amicool=&unix=1&dir=1&logrotate=1&mail=1&dns=1&web=1&webalizer=1&mysql=1&webmin=1&proxy_def=1&fwdto_def=1&virt=0&ip=&content_def=1'",
	  'grep' => [ 'Adding new virtual website', 'Saving server details' ],
	},

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/virtual-server/delete_domain.cgi\\?dom=`./list-domains.pl --domain $test_domain --id-only`\\&confirm=1",
	  'grep' => [ 'Deleting virtual website', 'Deleting server details' ],
	  'cleanup' => 1,
	},

	];

$remote_tests = [
	# Test domain creation via remote API
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=create-domain&domain=$test_domain&pass=smeg&dir=&unix=&web=&dns=&mail=&webalizer=&mysql=&logrotate=&".join("&", map { $_->[0]."=" } @create_args)."'",
	  'grep' => 'Exit status: 0',
	},

	# Make sure it was created
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains'",
	  'grep' => [ "^$test_domain", 'Exit status: 0' ],
	},

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=delete-domain&domain=$test_domain'",
	  'grep' => [ 'Exit status: 0' ],
	},
	];

if (!$webmin_user || !$webmin_pass) {
	$webmin_tests = [ { 'command' => 'echo Webmin tests cannot be run unless the --user and --pass parameters are given' } ];
	$remote_tests = [ { 'command' => 'echo Remote API tests cannot be run unless the --user and --pass parameters are given' } ];
	}

$ssl_tests = [
	# Create a domain with SSL and a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'allocate-ip' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL home page',
	},

	# Test HTTPS get
	{ 'command' => $wget_command.'https://'.$test_domain,
	  'grep' => 'Test SSL home page',
	},

	# Test SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Check PHP execution via HTTPS
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'https://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Switch PHP mode to CGI
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'cgi' ] ],
	},

	# Check PHP running via CGI via HTTPS
	{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'https://'.$test_domain.'/test.php',
	  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
	},

	# Test generation of a new self-signed cert
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'self' ],
		      [ 'size', 1024 ],
		      [ 'days', 365 ],
		      [ 'cn', $test_domain ],
		      [ 'c', 'US' ],
		      [ 'st', 'California' ],
		      [ 'l', 'Santa Clara' ],
		      [ 'o', 'Virtualmin' ],
		      [ 'ou', 'Testing' ],
		      [ 'email', 'example@'.$test_domain ],
		      [ 'alt', 'test_subdomain' ] ],
	},

	# Test generated SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'C=US', 'ST=California', 'L=Santa Clara',
		      'O=Virtualmin', 'OU=Testing', 'CN='.$test_domain ],
	},

	# Test generation of a CSR
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'csr' ],
		      [ 'size', 1024 ],
		      [ 'days', 365 ],
		      [ 'cn', $test_domain ],
		      [ 'c', 'US' ],
		      [ 'st', 'California' ],
		      [ 'l', 'Santa Clara' ],
		      [ 'o', 'Virtualmin' ],
		      [ 'ou', 'Testing' ],
		      [ 'email', 'example@'.$test_domain ],
		      [ 'alt', 'test_subdomain' ] ],
	},

	# Testing listing of keys, certs and CSR
	{ 'command' => 'list-certs.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => [ 'BEGIN CERTIFICATE', 'END CERTIFICATE',
		      'BEGIN RSA PRIVATE KEY', 'END RSA PRIVATE KEY',
		      'BEGIN CERTIFICATE REQUEST', 'END CERTIFICATE REQUEST' ],
	},

	# Test re-installation of the cert and key
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'cert', $test_domain_cert ],
		      [ 'key', $test_domain_key ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Shared IP address tests
$shared_tests = [
	# Allocate a shared IP
	{ 'command' => 'create-shared-address.pl',
	  'args' => [ [ 'allocate-ip' ], [ 'activate' ] ],
	},

	# Get the IP
	{ 'command' => './list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host '.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test shared home page',
	},
	
	# Change to the default IP
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'shared-ip', &get_default_ip() ] ],
	},

	# Test DNS and website again
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test shared home page',
	},

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Remove the shared IP
	{ 'command' => 'delete-shared-address.pl',
	  'args' => [ [ 'ip', '$SHARED_IP' ], [ 'deactivate' ] ],
	  'cleanup' => 1,
	},
	];

# Tests with SSL on shared IP
$wildcard_tests = [
	# Allocate a shared IP
	{ 'command' => 'create-shared-address.pl',
	  'args' => [ [ 'allocate-ip' ], [ 'activate' ] ],
	},

	# Get the IP
	{ 'command' => './list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain with SSL on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host '.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL shared home page',
	},

	# Test SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL shared domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Create a sub-domain with SSL on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', "sslsub.".$test_domain ],
		      [ 'desc', 'Test SSL shared sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared sub-domain home page' ],
		      @create_args, ],
        },

	# Test DNS and website for the sub-domain
	{ 'command' => 'host '.'sslsub.'.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://sslsub.'.$test_domain,
	  'grep' => 'Test SSL shared sub-domain home page',
	},

	# Test sub-domain SSL cert
	{ 'command' => 'openssl s_client -host '.'sslsub.'.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL shared domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Try to create a domain on the same IP with a conflicting name,
	# which should fail.
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'desc', 'Test SSL shared clash' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared clash' ],
		      @create_args, ],
	  'fail' => 1,
        },

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Remove the shared IP
	{ 'command' => 'delete-shared-address.pl',
	  'args' => [ [ 'ip', '$SHARED_IP' ], [ 'deactivate' ] ],
	  'cleanup' => 1,
	},
	];

# Tests for concurrent domain creation
$parallel_tests = [
	# Create a domain not in parallel
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test serial domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test serial home page' ],
		      @create_args, ],
        },

	# Create two domains in background processes
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'desc', 'Test parallel domain 1' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test parallel 1 home page' ],
		      @create_args, ],
	  'background' => 1,
        },
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'desc', 'Test parallel domain 2' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test parallel 2 home page' ],
		      @create_args, ],
	  'background' => 2,
        },

	# Wait for background processes to complete
	{ 'wait' => [ 1, 2 ] },

	# Make sure the domains were created
	{ 'command' => 'list-domains.pl',
	  'grep' => [ "^$test_parallel_domain1", "^$test_parallel_domain2" ],
	},

	# Validate all the domains
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_parallel_domain1 ],
		      [ 'domain' => $test_parallel_domain2 ],
		      [ 'all-features' ] ],
	},

	# Delete the two domains in background processes
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ] ],
	  'background' => 3,
	},
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ] ],
	  'background' => 4,
	},

	# Wait for background processes to complete
	{ 'wait' => [ 3, 4 ] },

	# Make sure the domains were deleted
	{ 'command' => 'list-domains.pl',
	  'antigrep' => [ "^$test_parallel_domain1",
			  "^$test_parallel_domain2" ],
	},

	# Validate the parent domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$plans_tests = [
	# Create a test plan
	{ 'command' => 'create-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 7777 ],
		      [ 'admin-quota', 8888 ],
		      [ 'max-doms', 7 ],
		      [ 'max-bw', 77777777 ],
		      [ 'features', 'mail dns web' ],
		      [ 'capabilities', 'users aliases scripts' ],
		      [ 'nodbname' ] ],
	},

	# Make sure it worked
	{ 'command' => 'list-plans.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 7777',
		      'Administrator block quota: 8888',
		      'Maximum doms: 7',
		      'Maximum bw: 77777777',
		      'Allowed features: mail dns web',
		      'Edit capabilities: users aliases scripts',
		      'Can choose database names: No' ],
	},

	# Modify the plan
	{ 'command' => 'modify-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 8888 ],
		      [ 'no-admin-quota' ],
		      [ 'max-doms', 8 ],
		      [ 'auto-features' ],
		      [ 'auto-capabilities' ],
		      [ 'no-nodbname' ] ],
	},

	# Make sure the modification worked
	{ 'command' => 'list-plans.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 8888',
		      'Administrator block quota: Unlimited',
		      'Maximum doms: 8',
		      'Maximum bw: 77777777',
		      'Allowed features: Automatic',
		      'Edit capabilities: Automatic',
		      'Can choose database names: Yes' ],
	},

	# Delete the plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	},

	# Make sure it is gone
	{ 'command' => 'list-plans.pl',
	  'antigrep' => $plan_name,
	},

	# Re-create it
	{ 'command' => 'create-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 7777 ],
		      [ 'admin-quota', 8888 ],
		      [ 'max-doms', 7 ],
		      [ 'max-bw', 77777777 ],
		      [ 'features', 'mail dns web' ],
		      [ 'capabilities', 'users aliases scripts' ],
		      [ 'nodbname' ] ],
	},
	
	# Create a domain on the plan
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      [ 'plan', $test_plan ],
		      @create_args, ],
        },

	# Make sure the plan limits were applied
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 7777',
		      'User block quota: 8888',
		      'Maximum sub-servers: 7',
		      'Bandwidth limit: 74.17',
		      'Allowed features: mail dns web',
		      'Edit capabilities: users aliases scripts',
		      'Can choose database names: No' ],
	},

	# Modify the plan and apply
	{ 'command' => 'modify-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 8888 ],
		      [ 'no-admin-quota' ],
		      [ 'max-doms', 8 ],
		      [ 'max-bw', 88888888 ],
		      [ 'features', 'mail dns web webalizer' ],
		      [ 'no-nodbname' ],
		      [ 'apply' ] ],
	},

	# Verify the new limits on the domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 8888',
		      'User block quota: Unlimited',
		      'Maximum sub-servers: 8',
		      'Bandwidth limit: 84.77',
		      'Allowed features: mail dns web webalizer',
		      'Can choose database names: Yes' ],
	},

	# Remove the domain and plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	  'cleanup' => 1 },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

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
	      'multibackup' => $multibackup_tests,
	      'remotebackup' => $remotebackup_tests,
              'mail' => $mail_tests,
	      'prepost' => $prepost_tests,
	      'webmin' => $webmin_tests,
	      'remote' => $remote_tests,
	      'ssl' => $ssl_tests,
	      'shared' => $shared_tests,
	      'wildcard' => $wildcard_tests,
	      'parallel' => $parallel_tests,
	      'plans' => $plans_tests,
	    };

# Run selected tests
$total_failed = 0;
if (!@tests) {
	@tests = sort { $a cmp $b } (keys %$alltests);
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
		# Run cleanups
		@cleaners = grep { $_->{'cleanup'} &&
				    $_->{'index'} >= $lastt->{'index'} } @tts;
		foreach $cleaner (@cleaners) {
			if ($cleaner ne $lastt) {
				$total++;
				&run_test($cleaner);
				}
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
if ($t->{'wait'}) {
	# Wait for a background process to exit
	local @waits = ref($t->{'wait'}) ? @{$t->{'wait'}} : ( $t->{'wait'} );
	local $ok = 1;
	foreach my $w (@waits) {
		print "    Waiting for background process $w ..\n";
		local $pid = $backgrounds{$w};
		if (!$pid) {
			print "    .. already exited, or never started!\n";
			$ok = 0;
			}
		waitpid($pid, 0);
		if ($?) {
			print "    .. PID $pid failed : $?\n";
			$ok = 0;
			}
		else {
			print "    .. PID $pid done\n";
			}
		delete($backgrounds{$w});
		}
	return $ok;
	}
elsif ($t->{'background'}) {
	# Run a test, but in the background
	print "    Backgrounding test ..\n";
	local $pid = fork();
	if ($pid < 0) {
		print "    .. fork failed : $!\n";
		return 0;
		}
	if (!$pid) {
		local $rv = &run_test_command($t);
		exit($rv ? 0 : 1);
		}
	$backgrounds{$t->{'background'}} = $pid;
	print "    .. backgrounded as $pid\n";
	return 1;
	}
else {
	# Run a regular test command
	return &run_test_command($t);
	}
}

sub run_test_command
{
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
local $out = &backquote_with_timeout("($cmd) 2>&1 </dev/null",
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
		$grep = &substitute_template($grep, \%saved_vars);
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
		$grep = &substitute_template($grep, \%saved_vars);
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
if ($t->{'save'}) {
	# Save output to variable
	$out =~ s/^\s*//;
	$out =~ s/\s*$//;
	$ENV{$t->{'save'}} = $out;
	$saved_vars{$t->{'save'}} = $out;
	}
print $t->{'fail'} ? "    .. successfully failed\n"
		   : "    .. success\n";
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
print "                           [--user webmin-login --pass password]\n";
exit(1);
}


