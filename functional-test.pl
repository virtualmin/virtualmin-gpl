#!/usr/local/bin/perl
# Runs all Virtualmin tests

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/functional-test.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "functional-test.pl must be run as root";
	}
$ENV{'PATH'} = "$module_root_directory:$module_root_directory/pro:$ENV{'PATH'}";
&require_mysql();
&require_postgres();
&require_mail();
&foreign_require("dovecot");
$mysql::mysql_login ||= 'root';

# Make sure wget doesn't use a cache
$ENV{'http_proxy'} = undef;
$ENV{'ftp_proxy'} = undef;

$test_domain = "example.com";	# Never really exists
$test_ssl_subdomain = "ssl.".$test_domain;
$test_ssl2_subdomain = "ssl2.".$test_domain;
$test_dns_subdomain = "dns.".$test_domain;
$test_rename_domain = "examplerename.com";
$test_target_domain = "exampletarget.com";
$test_clone_domain = "exampleclone.com";
$test_subdomain = "example.net";
$test_parallel_domain1 = "example1.net";
$test_parallel_domain2 = "example2.net";
$test_cloud_domain = "cloudexample.com";
$test_cloud_subdomain = "dns.cloudexample.com";
$test_ip_address = &get_default_ip();
$test_user = "testy";
$test_alias = "testing";
$test_alias_two = "yetanothertesting";
$test_reseller = "testsel";
$test_reseller_two = "anothersel";
$test_plan = "Test plan";
$test_admin = "testadmin";
$timeout = 240;			# Longest time a test should take
$nowdate = strftime("%Y-%m-%d", localtime(time()));
$yesterdaydate = strftime("%Y-%m-%d", localtime(time()-24*60*60));
$wget_command = "wget -O - --cache=off --proxy=off --no-check-certificate ";
$curl_command = "curl --fail ";
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
$test_zip_backup_file = "/tmp/$test_domain.zip";
$test_tar_backup_file = "/tmp/$test_domain.tar";
$test_bzip2_backup_file = "/tmp/$test_domain.tar.bz2";
$test_differential_backup_file = "/tmp/$test_domain.differential.tar.gz";
$test_differential_backup_file2 = "/tmp/$test_domain.differential2.tar.gz";
$test_backup_dir = "/tmp/functional-test-backups";
$test_backup_dir2 = "/tmp/functional-test-backups2";
$test_email_dir = "/usr/local/webadmin/virtualmin/testmail";
$spam_email_file = "$test_email_dir/spam.txt";
$virus_email_file = "$test_email_dir/virus.txt";
$ok_email_file = "$test_email_dir/ok.txt";
$supports_fcgid = &indexof("fcgid", &supported_php_modes()) >= 0;
$supports_fpm = &indexof("fpm", &supported_php_modes()) >= 0;
$supports_cgi = &indexof("cgi", &supported_php_modes()) >= 0;
@php_versions = sort { &compare_versions($a->[0], $b->[0]) }
		  grep { &indexof("fcgid", @{$_->[2]}) >= 0 }
		     &list_available_php_versions();
$max_php_version = $php_versions[@php_versions-1]->[0];
$scriptdb = 'mysql';
$test_ssh_private_key = "/tmp/functional-test.key";
$test_ssh_public_key = "/tmp/functional-test.key.pub";

@create_args = ( [ 'limits-from-plan' ],
		 [ 'no-email' ],
		 [ 'no-slaves' ],
	  	 [ 'no-secondaries' ],
		 [ 'default-cert-owner' ], );

@other_webmin_pages = ( 'cert_form', 'edit_spf', 'edit_domain',
			'edit_domdkim', 'edit_limits', 'edit_mail',
			'edit_phpmode', 'edit_spam', 'edit_spf',
			'edit_website', 'list_users', 'list_aliases',
			'list_databases', 'list_scripts', 'rename_form',
			'move_form', 'transfer_form', 'clone_form',
			'newip_form', 'pro/edit_res', 'list_admins',
			'list_balancers', 'list_redirects',
			'list_records', 'view_records', 'usage',
			'reemail', 'pro/maillog', 'disable_domain',
			'assoc_form', 'pro/edit_html' );

$max_output = 2048;

# Parse command-line args
$web = 'web';
$ssl = 'ssl';
&load_plugin_libraries();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$test_domain = shift(@ARGV);
		}
	elsif ($a eq "--sub-domain") {
		$test_subdomain = shift(@ARGV);
		}
	elsif ($a eq "--test") {
		push(@tests, split(/\s+/, shift(@ARGV)));
		}
	elsif ($a eq "--skip-test") {
		push(@skips, shift(@ARGV));
		}
	elsif ($a eq "--no-cleanup") {
		$no_cleanup = 1;
		}
	elsif ($a eq "--skip-cleanup") {
		$no_cleanup = 2;
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
	elsif ($a eq "--web-feature") {
		$web = shift(@ARGV);
		&indexof($web, @plugins) >= 0 || &usage("$web is not a plugin");
		&plugin_call($web, "feature_provides_web") ||
			&usage("$web is not a website plugin");
		}
	elsif ($a eq "--ssl-feature") {
		$ssl = shift(@ARGV);
		&indexof($ssl, @plugins) >= 0 || &usage("$ssl is not a plugin");
		}
	elsif ($a eq "--list-tests") {
		$list_tests = 1;
		}
	elsif ($a eq "--script") {
		push(@testscripts, split(/\s+/, shift(@ARGV)));
		}
	elsif ($a eq "--script-db") {
		$scriptdb = shift(@ARGV);
		}
	elsif ($a eq "--version") {
		push(@testversions, split(/\s+/, shift(@ARGV)));
		}
	elsif ($a eq "--template") {
		$tmplname = shift(@ARGV);
		$tmplname || &usage("--template must be followed by a ".
				    "template name or ID");
		}
	elsif ($a eq "--max-output") {
		$max_output = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$webmin_wget_command = "wget -q -O - --cache=off --proxy=off --http-user=$webmin_user --http-passwd=$webmin_pass --user-agent=Webmin ";
$admin_webmin_wget_command = "wget -q -O - --cache=off --proxy=off --http-user=$test_admin --http-passwd=smeg --user-agent=Webmin ";
if ($tmplname) {
	push(@create_args, [ 'template', $tmplname ]);
	}

&get_miniserv_config(\%miniserv);
$webmin_proto = "http";
if ($miniserv{'ssl'}) {
	eval "use Net::SSLeay";
	$webmin_proto = "https" if (!$@);
	}
$webmin_port = $miniserv{'port'};
$webmin_url = "$webmin_proto://localhost:$webmin_port";
if ($webmin_proto eq "https") {
	$webmin_wget_command .= "--no-check-certificate ";
	$admin_webmin_wget_command .= "--no-check-certificate ";
	}
$normal_agent_wget_command = $webmin_wget_command;
$normal_agent_wget_command =~ s/--user-agent=\S+//;

if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	$usermin_port = $uminiserv{'port'};
	$usermin_proto = "http";
	if ($uminiserv{'ssl'}) {
		eval "use Net::SSLeay";
		$usermin_proto = "https" if (!$@);
		}
	}

($test_domain_user) = &unixuser_name($test_domain);
($test_rename_domain_user) = &unixuser_name($test_rename_domain);
($test_clone_domain_user) = &unixuser_name($test_clone_domain);
($test_ssl_subdomain_user) = &unixuser_name($test_ssl_subdomain);
$prefix = &compute_prefix($test_domain, $test_domain_user, undef, 1);
$rename_prefix = &compute_prefix($test_rename_domain, $test_rename_domain_user,
				 undef, 1);
$clone_prefix = &compute_prefix($test_clone_domain, $test_clone_domain_user,
				 undef, 1);
$ssl_prefix = &compute_prefix($test_ssl_subdomain, $test_ssl_subdomain_user,
			      undef, 1);

%test_domain = ( 'dom' => $test_domain,
		 'prefix' => $prefix,
		 'user' => $test_domain_user,
		 'group' => $test_domain_user,
		 'template' => &get_init_template() );
$test_full_user = &userdom_name($test_user, \%test_domain);
$test_user_extra = $test_user."_extra";
$test_full_user_extra = &userdom_name($test_user_extra, \%test_domain);
$test_full_atuser = &userdom_name($test_user, \%test_domain, 6);
$test_full_user_mysql = &mysql_username($test_full_user);
$test_full_user_mysql_extra = &mysql_username($test_full_user_extra);
$test_user_mysql_extra = &mysql_username($test_user_extra);
$test_full_user_postgres = &postgres_username($test_full_user);
($test_target_domain_user) = &unixuser_name($test_target_domain);
$test_target_domain_db = 'targetdb';
$test_domain_home = $test_domain{'home'} =
	&server_home_directory(\%test_domain);
$test_domain_html = $test_domain_home.'/public_html';
$test_full_user_home = $test_domain_home.'/homes/'.$test_user;
$test_domain_db = &database_name(\%test_domain);
$test_domain_key = &default_certificate_file(\%test_domain, "key");
$test_domain_cert = &default_certificate_file(\%test_domain, "cert");

%test_rename_domain = ( 'dom' => $test_rename_domain,
		        'prefix' => $rename_prefix,
       		        'user' => $test_rename_domain_user,
		        'group' => $test_rename_domain_user,
		        'template' => &get_init_template() );
$test_rename_full_user = &userdom_name($test_user, \%test_drename_omain);

%test_clone_domain = ( 'dom' => $test_clone_domain,
		       'prefix' => $clone_prefix,
       		       'user' => $test_clone_domain_user,
		       'group' => $test_clone_domain_user,
		       'template' => &get_init_template() );
$test_clone_domain_home = $test_clone_domain{'home'} =
	&server_home_directory(\%test_clone_domain);
$test_clone_domain_db = &database_name(\%test_clone_domain);
$test_full_clone_user = &userdom_name($test_user, \%test_clone_domain);
$test_full_clone_user_mysql = &mysql_username($test_full_clone_user);

%test_ssl_subdomain = ( 'dom' => $test_ssl_subdomain,
		        'prefix' => $ssl_prefix,
       		        'user' => $test_ssl_subdomain_user,
		        'group' => $test_ssl_subdomain_user,
		        'template' => &get_init_template() );
$test_ssl_subdomain_home = $test_ssl_subdomain{'home'} =
	&server_home_directory(\%test_ssl_subdomain);

# Create PostgreSQL password file for root logins
$pg_pass_file = "/tmp/pgpass.txt";
open(PGPASS, ">$pg_pass_file");
print PGPASS "*:*:*:${postgresql::postgres_login}:${postgresql::postgres_pass}\n";
close(PGPASS);
$ENV{'PGPASSFILE'} = $pg_pass_file;
chmod(0600, $pg_pass_file);

# Get the theme for the Webmin user
if ($webmin_user) {
	&foreign_require("acl");
	($uinfo) = grep { $_->{'name'} eq $webmin_user } &acl::list_users();
	$webmin_user_theme = $uinfo ? $uinfo->{'theme'} : undef;
	}
$webmin_user_theme ||= $current_theme;

# Check that global configs are setup for the test
$config{'auto_redirect'} && die "auto_redirect must be set to 0";
$config{'spam_client'} eq 'spamassassin' ||
	die "Spam client must be spamassassin";

# Work out which DNS server is being used
if ($tmplname) {
	($tmpl) = grep { $_->{'name'} eq $tmplname } &list_templates();
	$tmpl || die "No template named $tmplname exists";
	}
else {
	$tmpl = &get_template(0);
	}
if ($tmpl->{'dns_cloud'} =~ /^remote_(\S+)$/) {
	$dnsserver = $1;
	}
else {
	$dnsserver = "127.0.0.1";
	}

$_config_tests = [
	# Just validate global config
	{ 'command' => 'check-config.pl' },

	# Is lookup-domain running?
	{ 'command' => 'ps auxwww | grep -v grep | grep lookup-domain-daemon' },
	
	# Bandwidth monitoring enabled?
	{ 'command' => 'grep bw_active=1 '.$module_config_directory.'/config' },

	# Has some backup keys
	defined(&list_backup_keys) ?
		( { 'command' => 'list-backup-keys.pl',
		    'args' => [ [ 'multiline' ] ],
		    'grep' => 'Description' } ) :
		( ),

	# Is Webmin running?
	{ 'command' => $normal_agent_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/",
	},
	];

$domains_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( [ 'virtualmin-awstats' ] ) : ( ),
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to admin mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ] ],
	},

	# Check IMAP and POP3 for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Check PostgreSQL login
	$config{'postgres'} ?
		&postgresql_login_commands($test_domain_user, 'smeg',
					   $test_domain_db, $test_domain_home)
		: ( ),

	# Check AWstats login
	&indexof('virtualmin-awstats', @plugins) >= 0 ? (
		{ 'command' => $wget_command.'http://'.$test_domain_user.':smeg@'.$test_domain.'/cgi-bin/awstats.pl',
		  'grep' => 'AWStats',
		},
		) : ( ),

	# Check PHP execution
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Enable PHP error log
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'php-log', 'logs/php_error_log' ] ],
	},

	# Write to PHP error log
	{ 'command' => 'echo "<?php error_log(\"foo\"); ?>" >~'.
		       $test_domain_user.'/public_html/log.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/log.php',
	},

	# Check PHP error log
	{ 'command' => 'cat '.$test_domain_home.'/logs/php_error_log',
	  'grep' => 'foo',
	},

	# Check log rotation for the PHP error log
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'feature' => 'logrotate' ] ],
	},

	# Turn off PHP error log
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-php-log' ] ],
	},

	# Write a PHP error, which won't get logged
	{ 'command' => 'echo "<?php error_log(\"bar\"); ?>" >~'.
		       $test_domain_user.'/public_html/log.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/log.php',
	},

	# Check PHP error log
	{ 'command' => 'cat '.$test_domain_home.'/logs/php_error_log',
	  'antigrep' => 'bar',
	},

	# Re-enable PHP error log
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'php-log', 'logs/php_error_log' ] ],
	},

	# Check log rotation for the PHP error log again
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'feature' => 'logrotate' ] ],
	},

	$supports_cgi ? (
		# Switch PHP mode to CGI
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'cgi' ] ],
		},

		# Validate PHP mode
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: cgi' ],
		},

		# Validate PHP mode cache
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'simple-multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: cgi' ],
		},

		# Check PHP running via CGI
		{ 'command' => 'echo "<?php system(\'id -a\'); '.
			       'echo php_sapi_name(),"\\n"; ?>" >~'.
			       $test_domain_user.'/public_html/test.php',
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => [ 'uid=[0-9]+\\('.$test_domain_user.'\\)',
			      'cgi-fcgi' ],
		},
		) : ( ),

	$supports_fcgid ? (
		# Switch PHP mode to fCGId
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fcgid' ] ],
		},

		# Validate PHP mode
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: fcgid' ],
		},

		# Validate PHP mode cache
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'simple-multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: fcgid' ],
		},

		# Check PHP running via fCGId
		{ 'command' => 'echo "<?php system(\'id -a\'); '.
			       'echo php_sapi_name(),"\\n"; ?>" >~'.
			       $test_domain_user.'/public_html/test.php',
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => [ 'uid=[0-9]+\\('.$test_domain_user.'\\)',
			      'cgi-fcgi' ],
		},
		) : ( ),

	$supports_fpm ? (
		# Switch PHP mode to FPM
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fpm' ] ],
		},

		# Validate PHP mode
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: fpm' ],
		},

		# Validate PHP mode cache
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'simple-multiline' ],
			      [ 'domain', $test_domain ] ],
		  'grep' => [ 'PHP execution mode: fpm' ],
		},

		# Check PHP running via FPM
		{ 'command' => 'echo "<?php system(\'id -a\'); '.
			       'echo php_sapi_name(),"\\n"; ?>" >~'.
			       $test_domain_user.'/public_html/test.php',
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => [ 'uid=[0-9]+\\('.$test_domain_user.'\\)',
			      'fpm-fcgi' ],
		},

		# Switch to an FPM socket file
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'php-fpm-socket' ] ],
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => [ 'uid=[0-9]+\\('.$test_domain_user.'\\)',
			      'fpm-fcgi' ],
		  'sleep' => 1,
		},

		# Switch back to an FPM port
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'php-fpm-port' ] ],
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => [ 'uid=[0-9]+\\('.$test_domain_user.'\\)',
			      'fpm-fcgi' ],
		  'sleep' => 1,
		},
		) : ( ),

	# Switch PHP mode to None
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'none' ] ],
	},

	# Validate PHP mode
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'PHP execution mode: none' ],
	},

	# Validate PHP mode cache
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'simple-multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'PHP execution mode: none' ],
	},

	# Check PHP scripts don't run
	{ 'command' => 'echo "<?php print 22222+22222; ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'antigrep' => '44444',
	  'grep' => '22222\+22222',
	},

	# Switch PHP mode to one that works
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'default-mode' ] ],
	},

	# Check that script runs now
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => '44444',
	  'antigrep' => '22222\+22222',
	  'sleep' => 1,
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

	# Check new FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':newpass@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check new IMAP and POP3 for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'newpass' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'newpass' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check new Webmin password
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password newpass '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check new MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -pnewpass '.$test_domain_db.' -e "select version()"',
	},

	# Check new AWstats password
	&indexof('virtualmin-awstats', @plugins) >= 0 ? (
		{ 'command' => $wget_command.'http://'.$test_domain_user.':newpass@'.$test_domain.'/cgi-bin/awstats.pl',
		  'grep' => 'AWStats',
		},
		) : ( ),

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],
	},

	# Make sure it worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'Description: Test sub-domain',
		      'Parent domain: '.$test_domain ],
	},

	# Add some DNS records
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing A 1.2.3.4' ] ],
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record-with-ttl', 'ttltest A 3600 5.6.7.8' ] ],
	},

	# Verify that it worked
	{ 'command' => 'host -t A testing.'.$test_domain,
	  'grep' => '1.2.3.4',
	},
	{ 'command' => 'host -t A ttltest.'.$test_domain,
	  'grep' => '5.6.7.8',
	},

	# Modify one of the records
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'update-record', 'testing A', 'testing A 5.5.5.5' ] ],
	},

	# Verify that it worked
	{ 'command' => 'host -t A testing.'.$test_domain,
	  'grep' => '5.5.5.5',
	},

	# Delete the records
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-record', 'testing A' ] ],
	  'sleep' => 1,
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-record', 'ttltest A 5.6.7.8' ] ],
	  'sleep' => 1,
	},

	# Make sure they are gone
	{ 'command' => 'host -t A testing.'.$test_domain,
	  'fail' => 1,
	},
	{ 'command' => 'host -t A ttltest.'.$test_domain,
	  'fail' => 1,
	},

	# Disable SPF, then re-enable
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-spf' ] ],
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'spf' ] ],
	},

	# Verify the record
	{ 'command' => 'dig TXT '.$test_domain.' ; dig SPF '.$test_domain,
	  'grep' => 'v=spf1',
	  'sleep' => 5,
	},

	# Disable SPF again
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-spf' ] ],
	},

	# Verify the record is gone
	{ 'command' => 'dig TXT '.$test_domain.' ; dig SPF '.$test_domain,
	  'antigrep' => 'v=spf1',
	  'sleep' => 5,
	},

	# Disable DMARC, then re-enable
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-dmarc' ] ],
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dmarc' ] ],
	},

	# Verify the record
	{ 'command' => 'dig TXT _dmarc.'.$test_domain,
	  'grep' => 'DMARC',
	  'sleep' => 5,
	},

	# Disable DMARC again
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-dmarc' ] ],
	},

	# Verify the record is gone
	{ 'command' => 'dig TXT _dmarc.'.$test_domain,
	  'antigrep' => 'DMARC',
	  'sleep' => 5,
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$jail_tests = [
	# Create a jailed domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
		      [ 'enable-jail' ],
		      @create_args, ],
	},

	# Make sure it is chroot'd
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => "Jail directory:",
	},

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'shell', '/bin/sh' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Check that the domain owner Unix user is chroot'd
	{ 'command' => 'su '.$test_domain_user." -c 'ls $home_base' | wc -l",
	  'grep' => '^1$',
	},

	# Check that the mailbox Unix user is chroot'd
	{ 'command' => 'su '.$test_full_user." -c 'ls $home_base' | wc -l",
	  'grep' => '^1$',
	},

	# Check the mailbox user's shell
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Shell: /bin/sh' ],
	},

	# Check shells in /etc/passwd
	{ 'command' => 'grep ^'.$test_full_user.': /etc/passwd',
	  'antigrep' => '/bin/sh',
	},

	$supports_fpm ? (
		# Switch PHP mode to FPM
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fpm' ] ],
		},

		# Make sure that PHP scripts are also chrooted
		{ 'command' => 'echo "<?php system(\'ls '.$home_base.' | wc -l\'); ?>" >~'.
			       $test_domain_user.'/public_html/test.php',
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => '^1$',
		},
		) : ( ),

	# Change the mailbox user's shell
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'shell' => '/bin/bash' ] ],
	},

	# Check that the mailbox Unix user is chroot'd still
	{ 'command' => 'su '.$test_full_user." -c 'ls $home_base' | wc -l",
	  'grep' => '^1$',
	},

	# Check the mailbox user's shell is the new one
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Shell: /bin/bash' ],
	},

	# Check shells in /etc/passwd again
	{ 'command' => 'grep ^'.$test_full_user.': /etc/passwd',
	  'antigrep' => [ '/bin/bash', '/bin/sh' ],
	},

	# Turn off the chroot
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'disable-jail' ] ],
	},

	# Make sure it is not chroot'd
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => "Jail directory:",
	},

	# Check that the Unix user is not chroot'd
	{ 'command' => 'su '.$test_domain_user." -c 'ls $home_base' | wc -l",
	  'antigrep' => '^1$',
	},

	# Check that the mailbox Unix user is not chroot'd
	{ 'command' => 'su '.$test_full_user." -c 'ls $home_base' | wc -l",
	  'antigrep' => '^1$',
	},

	# Check the user's shell was preserved
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Shell: /bin/bash' ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];
if (&check_jailkit_support()) {
	$jail_tests = [ { 'command' => 'echo Jailkit support is not available on this system' } ];
	}

$disable_tests = [
	# Create a domain that we will disable
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
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

	# Disable the whole domain
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Check that it was disabled
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Disabled: Manually',
	},

	# Test that DNS lookup fails
	{ 'command' => 'host -t A '.$test_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test that DNS lookup works for the disabled domain
	{ 'command' => 'host -t A '.$test_domain.'.disabled',
	  'grep' => &get_default_ip(),
	},

	# Make sure website is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Test home page',
	  'quiet' => 1,
	},

	# Check FTP login fails
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'grep' => 'Login incorrect',
	  'fail' => 1,
	},

	# Check IMAP and POP3 for admin mailbox fails
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'fail' => 1,
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'fail' => 1,
	},

	# Check Webmin login fails
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	  'fail' => 1,
	},

	# Make sure MySQL login is no longer working
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	  'fail' => 1,
	},

	$config{'postgres'} ?
		# Make sure PostgreSQL login doesn't work
		&postgresql_login_commands($test_domain_user, 'smeg',
                                           $test_domain_db, $test_domain_home,
					   1)
		: ( ),

	# Check FTP login as the mailbox fails
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/',
	  'grep' => 'Login incorrect',
	  'fail' => 1,
	},

	# Check IMAP and POP3 for mailbox fails
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'fail' => 1,
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'fail' => 1,
	},

	# Re-enable the domain
	{ 'command' => 'enable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Check website again
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Validate all features
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Schedule a disable for a few seconds into the future
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'schedule' => 0.0001 ] ],
	},

	# Check that it shows up in list-domains
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Disable scheduled on',
	},

	# Wait a bit for the disable time
	{ 'command' => 'sleep 8',
	},

	# Run a schedule collection, which should trigger the disable
	{ 'command' => $module_config_directory."/collectinfo.pl",
	  'antigrep' => 'Already running',
	  'tries' => 5,
	},

	# Check that it was disabled
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Disabled: Manually configured schedule',
	},

	# Make sure website is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Test home page',
	  'quiet' => 1,
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

	# Check attributes
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Password: smeg',
		      'Email address: '.$test_user.'@'.$test_domain,
		      'Home byte quota: '.(100*1024*1024) ],
	  'antigrep' => [ 'Home quota expected:' ],
	},

	# Check Unix account
	{ 'command' => $gconfig{'os_type'} =~ /-linux/ ? 
			'su -s /bin/sh '.$test_full_user.' -c "id -a"' :
			'id -a '.$test_full_user,
	  'grep' => 'uid=',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	},

	# Check IMAP and POP3 for mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Modify the user
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'pass' => 'newpass' ],
		      [ 'real' => 'New name' ],
		      [ 'quota' => 200*1024 ],
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
		      'Home byte quota: '.(200*1024*1024),
		      'Databases:.*'.$test_domain_user,
		      'Extra addresses:.*extra@'.$test_domain, ],
	  'antigrep' => [ 'Home quota expected:' ],
	},

	# Check user's MySQL login
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -pnewpass '.$test_domain_db.' -e "select version()"',
	},

	# Break the quota by editing directly
	{ 'command' => 'setquota '.$test_full_user.' 555555 555555 0 0 '.
		       $config{'home_quotas'},
	},

	# Make sure the cached quota is still known
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Home byte quota expected: '.(200*1024*1024) ],
	},

	# Fix the broken quota
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'apply-all-quotas' ] ],
	},

	# Check the fix
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Home byte quota: '.(200*1024*1024) ],
	  'antigrep' => [ 'Home byte quota expected:' ],
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

# SSH user tests
$sshuser_tests = [
	# Create a domain for testing
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Generate a keypair for SSH
	{ 'command' => 'rm -f '.$test_ssh_private_key.' '.$test_ssh_public_key,
	},
	{ 'command' => 'ssh-keygen -f '.$test_ssh_private_key.' </dev/null',
	},

	# Add a user with an SSH key
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'shell', '/bin/sh' ],
		      [ 'ssh-pubkey', $test_ssh_public_key ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Make sure we can SSH as that user
	{ 'command' => 'ssh -i '.$test_ssh_private_key.' '.$test_full_user.'@localhost echo OK',
	  'grep' => 'OK',
	},

	# Remove the user
	{ 'command' => 'delete-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user' => $test_user ] ],
	},

	# Re-create without an SSH key
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'shell', '/bin/sh' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# SSH should now fail
	{ 'command' => 'ssh -i '.$test_ssh_private_key.' '.$test_full_user.'@localhost echo OK',
	  'antigrep' => 'OK',
	  'fail' => 1,
	},

	# Add an SSH key to the user
	{ 'command' => 'modify-user.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'user', $test_user ],
		      [ 'ssh-pubkey', $test_ssh_public_key ],
		    ],
	},

	# SSH should now work again
	{ 'command' => 'ssh -i '.$test_ssh_private_key.' '.$test_full_user.'@localhost echo OK',
	  'grep' => 'OK',
	},

	# Cleanup the key
	{ 'command' => 'rm -f '.$test_ssh_private_key.' '.$test_ssh_public_key,
	  'cleanup' => 1,
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
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
		      'To: nobody@webmin.com',
		      'To: nobody@virtualmin.com' ],
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

	# Turn off mail
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'mail' ] ],
	},

	# Turn mail back on again
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'mail' ] ],
	},

	# Make sure aliases still exist
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_alias_two.'@'.$test_domain,
	},
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

$atalias_tests = &convert_to_atmail($alias_tests);

# Reseller tests
$reseller_tests = [
	# Create a reseller
	{ 'command' => 'create-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test reseller' ],
		      [ 'email', $test_reseller.'@'.$test_domain ],
		      [ 'unix' ] ],
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
		       '--user '.$test_reseller.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_reseller.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Make changes
	{ 'command' => 'modify-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'desc', 'New description' ],
		      [ 'email', 'newmail@'.$test_domain ],
		      [ 'max-doms', 66 ],
		      [ 'allow', $web ],
		      [ 'pass', 'smeg2' ],
		      [ 'logo', 'http://'.$test_domain.'/logo.gif' ],
		      [ 'link', 'http://'.$test_domain ] ],
	},

	# Check new reseller details
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'multiline' ] ],
	  'grep' => [ 'Description: New description',
		      'Email: newmail@'.$test_domain,
		      'Maximum domains: 66',
		      'Allowed features:.*'.$web,
		      'Logo URL: http://'.$test_domain.'/logo.gif',
		      'Logo link: http://'.$test_domain,
		    ],
	},

	# Check Webmin login again
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_reseller.' '.
		       '--password smeg2 '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check FTP login again
	{ 'command' => $wget_command.
		       'ftp://'.$test_reseller.':smeg2@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Turn off Unix login
	{ 'command' => 'modify-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'no-unix' ] ],
	},

	# Check FTP login again, which should now fail
	{ 'command' => $wget_command.
		       'ftp://'.$test_reseller.':smeg2@localhost/',
	  'grep' => 'Login incorrect',
	  'ignorefail' => 1,
	},

	# Turn on Unix login
	{ 'command' => 'modify-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'unix' ] ],
	},

	# Check FTP login again, which should now work
	{ 'command' => $wget_command.
		       'ftp://'.$test_reseller.':smeg2@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Create a domain owned by the reseller
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      [ 'reseller', $test_reseller ],
		      @create_args, ],
        },

	# Make sure the domain is owned by the reseller
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Reseller: '.$test_reseller ],
	},
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Owned servers: '.$test_domain ],
	},

	# Change to no reseller
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'reseller', 'NONE' ] ],
	},

	# Verify that it worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'Reseller: '.$test_reseller ],
	},
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'Owned servers: '.$test_domain ],
	},

	# Switch to the reseller again
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'reseller', $test_reseller ] ],
	},

	# Verify ownership
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Reseller: '.$test_reseller ],
	},
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Owned servers: '.$test_domain ],
	},

	# Create a second reseller
	{ 'command' => 'create-reseller.pl',
	  'args' => [ [ 'name', $test_reseller_two ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test reseller two' ],
		      [ 'email', $test_reseller_two.'@'.$test_domain ],
		      [ 'unix' ] ],
	},

	# Add him to the domain
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-reseller', $test_reseller_two ] ],
	},

	# Verify ownership by both
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Reseller: '.$test_reseller.' '.$test_reseller_two ],
	},
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'name', $test_reseller_two ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Owned servers: '.$test_domain ],
	},

	# Take away ownership
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'delete-reseller', $test_reseller_two ] ],
	},

	# Verify ownership again
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'Reseller:.*'.$test_reseller_two ],
	},

	# Backup the domain
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete the reseller
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ] ],
	},

	# Delete the domain in preparation for a restore
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Check that a restore fails
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	  'fail' => 1,
	},

	# Check that a restore with warnings skipped works
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'skip-warnings' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Delete the reseller and domain
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ] ],
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller_two ] ],
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	];

# Script tests
$script_tests = [
	# Create a domain for the scripts
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'mysql' ], [ 'dns' ],
		      @create_args, ],
        },

	# Install SugarCRM
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'sugarcrm' ],
		      [ 'path', '/' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'opt', 'demo 1' ],
		      [ 'opt', 'nowizard 1' ],
		      [ 'version', 'latest' ] ],
	  'timeout' => 300,
	  'antigrep' => 'partially complete',
	},

	# Check that it was registered
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'name-only' ] ],
	  'grep' => 'sugarcrm',
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/',
	  'grep' => 'SugarCRM|modules/Users/login.css',
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'sugarcrm' ] ],
	},

	# Check that it's gone
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'name-only' ] ],
	  'antigrep' => 'sugarcrm',
	},

	# Upgrade PHP version on the domain if possible
	{ 'command' => 'set-php-directory.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'dir', '.' ],
		      [ 'version', $max_php_version ] ],
	  'ignorefail' => 1,
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
	  'antigrep' => 'partially complete',
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/wordpress/',
	  'grep' => 'WordPress',
	},

	# Check script list
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: wordpress',
		      'Directory: /home/'.$test_domain_user.
			'/public_html/wordpress',
		      'Database: '.$test_domain_db.' ',
		      'URL: http(s?)://'.$test_domain.'/wordpress',
		    ],
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ] ],
	},

	# Install with it's own DB
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'path', '/wordpress' ],
		      [ 'db', 'mysql '.$test_domain_db.'_wp' ],
		      [ 'newdb' ],
		      [ 'version', 'latest' ] ],
	  'antigrep' => 'partially complete',
	},

	# Check that it works with it's own DB
	{ 'command' => $wget_command.'http://'.$test_domain.'/wordpress/',
	  'grep' => 'WordPress',
	},

	# Check script list
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: wordpress',
		      'Directory: /home/'.$test_domain_user.
			'/public_html/wordpress',
		      'Database: '.$test_domain_db.'_wp ',
		      'URL: http(s?)://'.$test_domain.'/wordpress',
		    ],
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ] ],
	},

	# Make sure the DB is gone
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => '^'.$test_domain_db.'_wp',
	},

	# Install Wordpress
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'path', '/wordpress' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'version', 'latest' ] ],
	  'antigrep' => 'partially complete',
	},

	# Re-register it
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'deregister' ], ],
	},

	# Check that it's gone
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'name-only' ] ],
	  'antigrep' => 'wordpress',
	},

	# Re-detect it
	{ 'command' => 'detect-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'wordpress:', 'Newly detected' ],
	},

	# Check that it's back
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: wordpress',
		      'Database: '.$test_domain_db.' ',
		    ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# GPL Script tests
$gplscript_tests = [
	# Create a domain for the scripts
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'mysql' ], [ 'dns' ],
		      @create_args, ],
        },

	# List all scripts
	{ 'command' => 'list-available-scripts.pl',
	  'grep' => 'RoundCube',
	},

	# Install Roundcube
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ],
		      [ 'path', '/roundcube' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'atleast-version', '1.3.17' ] ],
	  'antigrep' => 'partially complete',
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/roundcube/',
	  'grep' => 'Welcome to Roundcube Webmail',
	},

	# Check script list
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: roundcube',
		      'Directory: /home/'.$test_domain_user.
			'/public_html/roundcube',
		      'Database: '.$test_domain_db.' ',
		      'URL: http(s?)://'.$test_domain.'/roundcube',
		    ],
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ] ],
	},

	# Install with it's own DB
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ],
		      [ 'path', '/roundcube' ],
		      [ 'db', 'mysql '.$test_domain_db.'_roundcube' ],
		      [ 'newdb' ],
		      [ 'atleast-version', '1.3.17' ] ],
	  'antigrep' => 'partially complete',
	},

	# Check that it works with it's own DB
	{ 'command' => $wget_command.'http://'.$test_domain.'/roundcube/',
	  'grep' => 'Welcome to Roundcube Webmail',
	},

	# Check script list
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: roundcube',
		      'Directory: /home/'.$test_domain_user.
			'/public_html/roundcube',
		      'Database: '.$test_domain_db.'_roundcube ',
		      'URL: http(s?)://'.$test_domain.'/roundcube',
		    ],
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ] ],
	},

	# Make sure the DB is gone
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => '^'.$test_domain_db.'_roundcube',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

if ($supports_fpm) {
	$fpmscript_tests = [ @$script_tests ];
	splice(@$fpmscript_tests, 1, 0,
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fpm' ] ],
		});
	}
else {
	$fpmscript_tests = [];
	}

# Test that testable scripts install OK and don't 500
$allscript_tests = [
	# Create a domain for the scripts
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'mysql' ], [ 'dns' ],
		      [ 'postgres' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Use fcgid PHP mode so we can switch versions
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'fcgid' ] ],
	},
	];

# Test each script that we can
foreach my $sname (&list_scripts(1)) {
	next if (@testscripts && &indexof($sname, @testscripts) < 0);
	my $script = &get_script($sname);
	next if (!$script);
	my $tfunc = $script->{'testable_func'};
	next if (!$tfunc || !defined(&$tfunc));
	my $tpfunc = $script->{'testpath_func'};
	my $tipfunc = $script->{'testinstallpath_func'};
	my $tafunc = $script->{'testargs_func'};

	foreach my $ver (@{$script->{'install_versions'}}) {
		next if (@testversions && &indexof($ver, @testversions) < 0);
		my $testable = &$tfunc($ver);
		next if (!$testable);
		my $ipath = defined(&$tipfunc) ? &$tipfunc($ver) : "/";
		my $path = defined(&$tpfunc) ? &$tpfunc($ver) :
			   $ipath ? $ipath : "/";
		my @args = defined(&$tafunc) ? &$tafunc($ver) : ();
		push(@$allscript_tests,
			# Install it
			{ 'command' => 'install-script.pl',
			  'args' => [ [ 'domain', $test_domain ],
				      [ 'type', $script->{'name'} ],
				      [ 'path', $ipath ],
				      [ 'db', $scriptdb.' '.$test_domain_db ],
				      [ 'version', $ver ],
				      @args,
				    ],
			  'continuefail' => 1,
			  'antigrep' => 'partially complete',
			});

		if ($testable == 1) {
			push(@$allscript_tests,
				# Test that it works
				{ 'command' => $curl_command.
					       'http://'.$test_domain.$path,
				  'antigrep' => 'Test home page',
				  'quiet' => 1,
				  'continuefail' => 1,
				});
			}

		push(@$allscript_tests,
			# Un-install it
			{ 'command' => 'delete-script.pl',
			  'args' => [ [ 'domain', $test_domain ],
				      [ 'type', $script->{'name'} ] ],
			  'continuefail' => 1,
			});
		}
	}

# Cleanup the domain
push(@$allscript_tests,
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	);

# Database tests
$database_tests = [
	# Create a domain for the databases
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      @create_args, ],
        },

	# Add a extra MySQL database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Check that we can login to MySQL
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	# Check MySQL extra login creation
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user_mysql_extra ],
		      [ 'pass', 'smeg' ],
		      [ 'mysql', $test_domain_db ],
		      [ 'db-only' ] ],
	},

	# Check MySQL extra login
	{ 'command' => 'mysql -u '.$test_full_user_mysql_extra.' -psmeg '.$test_domain_db.' -e "select version()"',
	},
	
	# Make sure the MySQL database appears
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_domain_user.'_extra',
	},

	# Check for allowed DB hosts
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Allowed mysql hosts:.*1\\.2\\.3\\.4',
	},

	# Create a mailbox user with access to the DBs
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mysql', $test_domain_db ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Verify that mailbox user exists and has DB access
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Databases: '.$test_domain_db.' \(mysql\)' ],
	  'antigrep' => [ $test_domain_db.'_extra \(mysql\)' ],
	},

	# Drop the extra MySQL database
	{ 'command' => 'delete-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Check for allowed DB hosts after the drop
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Allowed mysql hosts:.*1\\.2\\.3\\.4',
	},

	$config{'postgres'} ?
	(
		# Create a PostgreSQL database
		{ 'command' => 'create-database.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'type', 'postgres' ],
			      [ 'name', $test_domain_user.'_extra2' ] ],
		},

		# Make sure the PostgreSQL database appears
		{ 'command' => 'list-databases.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'multiline' ] ],
		  'grep' => '^'.$test_domain_user.'_extra2',
		},

		# Check that we can login
		&postgresql_login_commands($test_domain_user, 'smeg',
					   $test_domain_user.'_extra2',
					   $test_domain_home),

		# Drop the PostgreSQL database
		{ 'command' => 'delete-database.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'type', 'postgres' ],
			      [ 'name', $test_domain_user.'_extra2' ] ],
		},
	) : ( ),

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
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ],
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
	  'grep' => [ '/google/', 'http://www.google.com/' ],
	},

	# Modify the proxy URL
	{ 'command' => 'modify-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ],
		      [ 'url', 'http://www.bing.com/' ] ],
	},

	# Test that it works with the new URL
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => '<title>Bing',
	},

	# Check the proxy list for the new URL
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => [ '/google/', 'http://www.bing.com/' ],
	},

	# Delete the proxy
	{ 'command' => 'delete-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ] ],
	},

	# Check that it's gone from the proxy list
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'antigrep' => '/google/',
	},

	# Create a proxy to multiple URLs
	{ 'command' => 'create-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ],
		      [ 'url', 'http://www.google.com/' ],
		      [ 'url', 'http://www.google.com.au/' ] ],
	},

	# Test that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => '<title>Google',
	},

	# Check the proxy list
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => [ '/google/', 'http://www.google.com/',
		      'http://www.google.com.au/' ],
	},

	# Delete the proxy
	{ 'command' => 'delete-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ] ],
	},

	# Check that it's gone from the proxy list
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'antigrep' => '/google/',
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
	  'timeout' => 360,
	  'always_cleanup' => 1,
	},

	# Make sure ensim migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_ensim_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: apservice',
		      'Features: unix dir dns mail web webalizer',
		      'Server quota:\s+30\s+Mi?B' ],
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
		      'migrated\s+1\s+aliases',
		    ],
	  'migrate' => 'cpanel',
	  'timeout' => 360,
	  'always_cleanup' => 1,
	},

	# Make sure cPanel migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_cpanel_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: adam',
		      'Features: unix dir dns mail web webalizer logrotate mysql',
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
	  'timeout' => 360,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: rtsadmin',
		      'Features: unix dir dns mail web webalizer logrotate mysql spam virus',
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
	  'timeout' => 360,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_windows_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: sbcher',
		      'Features: unix dir dns mail web logrotate spam',
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
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server under the parent
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'content' => 'Test sub-server home page' ],
		      @create_args, ],
	},

	# Create a domain to be the target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'spod' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'db', $test_target_domain_db ],
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

	# Add an FTP user to the domain being moved
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', 'ftp_'.$test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test FTP user' ],
		      [ 'web' ] ],
	},

	# Install a script into the domain being moved
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ],
		      [ 'path', '/roundcube' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'atleast-version', '1.3.17' ] ],
	  'antigrep' => 'partially complete',
	},

	# Move under the target
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'parent', $test_target_domain ] ],
	},

	# Check parentage
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Parent domain: '.$test_target_domain,
		      'Username: '.$test_target_domain_user ],
	},
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Parent domain: '.$test_target_domain,
		      'Username: '.$test_target_domain_user ],
	},

	# Make sure the old Unix user is gone
	{ 'command' => 'grep ^'.$test_domain_user.': /etc/passwd',
	  'fail' => 1,
	},

	# Make sure the website still works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Make sure the sub-server website still works
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test sub-server home page',
	},

	# Check MySQL login under new owner to the moved DB
	{ 'command' => 'mysql -u '.$test_target_domain_user.' -pspod '.$test_domain_db.' -e "select version()"',
	},

	# Make sure MySQL is gone under old owner to the moved DB
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	  'fail' => 1,
	},

	# Make sure MySQL still works for the new owner's own DB
	{ 'command' => 'mysql -u '.$test_target_domain_user.' -pspod '.$test_target_domain_db.' -e "select version()"',
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

	# Make sure the FTP user still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => 'ftp_'.$test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ "^ftp_".$test_user, "Website manager" ],
	},

	# Make sure the script install was updated
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: roundcube',
		      'Directory: /home/'.$test_target_domain_user.
			'/domains/'.$test_domain.'/public_html/roundcube',
		      'Database: '.$test_domain_db.' ',
		      'URL: http(s?)://'.$test_domain.'/roundcube',
		    ],
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
	  'quiet' => 1,
	},

	# Make sure MySQL is back
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Make sure MySQL still works for the old owner's own DB
	{ 'command' => 'mysql -u '.$test_target_domain_user.' -pspod '.$test_target_domain_db.' -e "select version()"',
	},

	# Make sure the parent domain and user are correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => 'Username: '.$test_domain_user,
	  'antigrep' => 'Parent domain:',
	},

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Make sure the FTP user still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => 'ftp_'.$test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ "^ftp_".$test_user, "Website manager" ],
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

# Move alias domain tests
$movealias_tests = [
	# Create a parent domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'logrotate' ],
		      [ 'content' => 'Test old home page' ],
		      @create_args, ],
        },

	# Create an alias of it
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'alias', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test alias-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create a domain to be the target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'spod' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'content' => 'Test new home page' ],
		      @create_args, ],
        },

	# Test HTTP get to the alias
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test old home page',
	},

	# Move to the new target
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_target_domain ] ],
	},

	# Test HTTP get to the alias again
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test new home page',
	},

	# Cleanup the original parent domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Cleanup the new target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1 },
	];

# Alias domain tests
$aliasdom_tests = [
	# Create a domain to be the alias target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test alias target page' ],
		      @create_args, ],
        },

	# Add a DNS record to the target
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'add-record', 'testing A 1.2.3.4' ] ],
	},

	# Enable webmail DNS record
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_target_domain ],
		      [ 'webmail' ] ],
	},

	# Create the alias domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'alias', $test_target_domain ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Test DNS lookups
	{ 'command' => 'host -t A '.$test_domain,
	  'grep' => &get_default_ip(),
	},
	{ 'command' => 'host -t A testing.'.$test_domain,
	  'grep' => '1.2.3.4',
	},
	{ 'command' => 'host -t A webmail.'.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test alias target page',
	},

	# Test HTTP get to webmail alias
	{ 'command' => $wget_command.'http://webmail.'.$test_domain,
	  'grep' => 'Usermin',
	},

	# Turn off webmail redirect for the alias
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-webmail' ] ],
	},

	# Test HTTP get to webmail alias, which will now fail
	{ 'command' => $wget_command.'http://webmail.'.$test_domain,
	  'fail' => 1,
	},

	# But HTTP get to the main domain webmail alias will still work
	{ 'command' => $wget_command.'http://webmail.'.$test_target_domain,
	  'grep' => 'Usermin',
	},

	# Turn back on webmail redirect for the alias
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webmail' ] ],
	},

	# Test HTTP get to webmail alias again
	{ 'command' => $wget_command.'http://webmail.'.$test_domain,
	  'grep' => 'Usermin',
	},

	# Give alias domain it's own DNS records
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'alias-dns' ] ],
	},

	# Add a DNS record to the alias domain
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing2 A 1.2.3.4' ] ],
	},

	# Make sure it works, and so does the record copied from the target
	{ 'command' => 'host -t A testing2.'.$test_domain,
	  'grep' => '1.2.3.4',
	},
	{ 'command' => 'host -t A testing.'.$test_domain,
	  'grep' => '1.2.3.4',
	},

	# Add a DNS record to the target domain
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'add-record', 'testing3 A 1.2.3.4' ] ],
	},

	# Make sure it's not in the alias
	{ 'command' => 'host -t A testing3.'.$test_domain,
	  'antigrep' => '1.2.3.4',
	  'fail' => 1,
	},

	# Switch alias domain back to copying DNS records
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-alias-dns' ] ],
	},

	# Make sure the record is now in the alias
	{ 'command' => 'host -t A testing3.'.$test_domain,
	  'grep' => '1.2.3.4',
	},

	# Enable aliascopy mode
	{ 'command' => 'modify-mail.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'alias-copy' ] ],
	},

	# Create a mailbox in the target
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Test SMTP to him in the alias domain
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	},

	# Test SMTP to a missing user
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', 'bogus@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Try disabling a feature in the main domain used by the alias
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'web' ], [ 'logrotate' ] ],
	  'fail' => 1,
	},

	# Convert to sub-server
	{ 'command' => 'unalias-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Validate to make sure it worked
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Create a web page, and make sure it can be fetched
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'content' => 'Test un-aliased page' ] ],
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test un-aliased page',
	},

	# Make sure mail to the user no longer works
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Delete the alias domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Re-create the alias domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'alias', $test_target_domain ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1 },
	];

# Backup tests
@post_restore_tests = (
	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_domain,
	  'grep' => &get_default_ip(),
	},
	{ 'command' => 'host -t A www.'.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Test HTTP get of alias domains
	{ 'command' => $wget_command.'http://'.$test_parallel_domain1,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},
	{ 'command' => $wget_command.'http://'.$test_parallel_domain2,
	  'grep' => 'Test home page',
	  'quiet' => 1,
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
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	$config{'postgres'} ?
		# Check PostgreSQL login
		&postgresql_login_commands($test_domain_user, 'smeg',
					   $test_domain_db,
					   $test_domain_home)
		: ( ),

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Make sure the mailbox has the same settings
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Password: smeg',
		      'Email address: '.$test_user.'@'.$test_domain,
		      'Home quota: 777' ],
	  'antigrep' => [ 'Home quota expected:' ],
	},

	# Test DNS lookup of sub-domain
	{ 'command' => 'host -t A '.$test_subdomain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get of sub-domain
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Check that extra database exists
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => $test_domain_db.'_extra',
	},

	# Check for allowed DB host
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Allowed mysql hosts:.*1\\.2\\.3\\.4',
	},
	);

$scheduled_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Create a scheduled backup for just this domain to a file
	{ 'command' => 'create-scheduled-backup.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ],
		      [ 'schedule', '* * * * *' ] ],
	},

	# Wait a minute for it to run
	{ 'command' => 'sleep 90'
	},

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_file },
	{ 'command' => 'ls -l '.$test_backup_file.'.info' },
	{ 'command' => 'ls -l '.$test_backup_file.'.dom' },

	# Make sure it was logged
	{ 'command' => 'list-backup-logs.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'start', -1 ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Domains: '.$test_domain,
		      'Final status: OK',
		      'Destination: '.$test_backup_file,
		      'Run from: sched',
		      'Differential: No' ],
	},

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

	# Run post-restore tests
	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_domain,
	  'grep' => &get_default_ip(),
	},
	{ 'command' => 'host -t A www.'.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
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
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	$config{'postgres'} ?
		# Check PostgreSQL login
		&postgresql_login_commands($test_domain_user, 'smeg',
					   $test_domain_db,
					   $test_domain_home)
		: ( ),

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Make sure the mailbox has the same settings
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Password: smeg',
		      'Email address: '.$test_user.'@'.$test_domain,
		      'Home quota: 777' ],
	  'antigrep' => [ 'Home quota expected:' ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Delete the scheduled backup
	{ 'command' => 'delete-scheduled-backup.pl',
	  'args' => [ [ 'dest', $test_backup_file ] ],
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	];

$backup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Enable PHP error logging to a non-standard file
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'php-log', 'logs/custom-php.log' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'logrotate' ], [ 'dns' ],
		      [ 'mail' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, with a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain with dir' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, without a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain without dir' ],
		      [ $web ], [ 'dns' ],
		      @create_args, ],
	},

	# Test that everything works initially
	@post_restore_tests,

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_file },
	{ 'command' => 'ls -l '.$test_backup_file.'.info' },
	{ 'command' => 'ls -l '.$test_backup_file.'.dom' },

	# Make sure it was logged
	{ 'command' => 'list-backup-logs.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'start', -1 ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Domains: '.$test_domain.' '.$test_subdomain.' '.
		        $test_parallel_domain1.' '.$test_parallel_domain2,
		      'Final status: OK',
		      'Destination: '.$test_backup_file,
		      'Run from: api',
		      'Differential: No' ],
	},

	# Backup to a temp dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.info' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.dom' },

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Create a file that should get removed by the restore
	{ 'command' => 'su -s /bin/sh '.$test_domain_user.
		       ' -c "touch ~/public_html/kill.txt"',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'option', 'dir delete 1' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Make sure the file that didn't exist before the backup was removed
	{ 'command' => 'ls ~'.$test_domain_user.'/public_html/kill.txt',
	  'fail' => 1,
	},

	# Test that everything still works
	@post_restore_tests,

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Re-create from backup
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Try restoring only the sub-server, which will fail
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	  'fail' => 1,
	},

	# Re-create from backup dir
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Run various tests yet again
	@post_restore_tests,

	# Also check the PHP error log
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'PHP error log:.*logs/custom-php.log' ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$enc_backup_tests = &convert_to_encrypted($backup_tests);

$mysqlbackup_tests = [
	# Create a domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Create a mailbox user with access to the DBs
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mysql', $test_domain_db ],
		      [ 'mysql', $test_domain_db.'_extra' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Restore just MySQL from the temp file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'feature', 'mysql' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Check that the user still has access
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Disconnect the databases
	{ 'command' => 'disconnect-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db ] ],
	},
	{ 'command' => 'disconnect-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Create some tables
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.' -e "create table foo (id int(4))"',
	},
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.'_extra -e "create table bar (id int(4))"',
	},

	# Create a MySQL user who would clash on restore
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' mysql -e "create user \''.$test_full_user_mysql.'\'@localhost identified by \'blah\';"',
	},
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' mysql -e "grant all on '.$test_domain_db.'.* to \''.$test_full_user_mysql.'\'@localhost;"',
	},

	# Verify that the manually created user works
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -pblah '.$test_domain_db.' -e "desc foo"',
	 'grep' => 'int\(4\)',
        },

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Attempt a restore, which should fail
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	  'ignorefail' => 1,
	  'grep' => 'Restore failed',
	},

	# Try the restore again with warnings disabled
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ],
		      [ 'skip-warnings' ] ],
	},

	# Verify database association
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_domain_db.'_extra$',
		      '^'.$test_domain_db.'$' ],
	},

	# Verify that DB contents still exist
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.' -e "desc foo"',
	  'grep' => 'int\(4\)',
	},
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.'_extra -e "desc bar"',
	  'grep' => 'int\(4\)',
	},

	# Verify that mailbox user exists and has DB access
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Databases: '.$test_domain_db.' \(mysql\), '.
				    $test_domain_db.'_extra \(mysql\)' ],
	},

	# Verify that mailbox user can access DBs
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -psmeg '.$test_domain_db.' -e "desc foo"',
	 'grep' => 'int\(4\)',
        },
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -psmeg '.$test_domain_db.'_extra -e "desc bar"',
	 'grep' => 'int\(4\)',
        },

	# Disconnect the main database
	{ 'command' => 'disconnect-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db ] ],
	},

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Re-create, which should fail
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	  'fail' => 1,
        },

	# Re-create with warnings skipped, which should pass
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      [ 'skip-warnings' ],
		      @create_args, ],
        },

	# Verify database association
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_domain_db.'$' ],
	},

	# Verify that DB contents still exist
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.' -e "desc foo"',
	  'grep' => 'int\(4\)',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Clean up DBs
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' mysql -e "drop database if exists '.$test_domain_db.';"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' mysql -e "drop database if exists '.$test_domain_db.'_extra;"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' mysql -e "drop user \''.$test_full_user_mysql.'\'@localhost;"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	},
	];

$enc_mysqlbackup_tests = &convert_to_encrypted($mysqlbackup_tests);

$postgresbackup_tests = [
	# Make sure the PostgreSQL root login works
	{ 'command' => 'psql -U '.$postgresql::postgres_login.
		       ' -c "select version()"',
	  'user' => $postgresql::postgres_sameunix ?
			$postgresql::postgres_login : undef,
	},

	# Create a domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'postgres' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Create some tables
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db, $test_domain_home, 0, "create table foo (id int4)"),
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db.'_extra', $test_domain_home, 0, "create table bar (id int4)"),

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete the tables
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db, $test_domain_home, 0, "drop table foo"),
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db.'_extra', $test_domain_home, 0, "drop table bar"),

	# Restore just PostgreSQL from the temp file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'feature', 'postgres' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Check that the domain owner still has access
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db, $test_domain_home, 0, "select version()"),

	# Verify that DB contents exist again
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db, $test_domain_home, 0, "select count(*) from foo"),
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db.'_extra', $test_domain_home, 0, "select count(*) from bar"),

	# Disconnect the databases
	{ 'command' => 'disconnect-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_db ] ],
	},
	{ 'command' => 'disconnect-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Attempt a restore, which should fail (due to the DB clash)
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	  'fail' => 1,
	  'grep' => 'Restore failed',
	},

	# Try the restore again with warnings disabled, which should
	# re-associate the databases
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ],
		      [ 'skip-warnings' ] ],
	},

	# Verify database association
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_domain_db.'_extra$',
		      '^'.$test_domain_db.'$' ],
	},

	# Verify that DB contents still exist
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db, $test_domain_home, 0, "select count(*) from foo"),
	&postgresql_login_commands($test_domain_user, 'smeg', $test_domain_db.'_extra', $test_domain_home, 0, "select count(*) from bar"),

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Cleanup leftover DBs and user
	{ 'command' => 'psql -U '.$postgresql::postgres_login.
		       ' -c "drop database '.$test_domain_db.'"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	  'user' => $postgresql::postgres_sameunix ?
			$postgresql::postgres_login : undef,
	},
	{ 'command' => 'psql -U '.$postgresql::postgres_login.
		       ' -c "drop database '.$test_domain_db.'_extra"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	  'user' => $postgresql::postgres_sameunix ?
			$postgresql::postgres_login : undef,
	},
	{ 'command' => 'psql -U '.$postgresql::postgres_login.
		       ' -c "drop user '.$test_domain_user.'"',
	  'cleanup' => 1,
	  'ignorefail' => 1,
	  'user' => $postgresql::postgres_sameunix ?
			$postgresql::postgres_login : undef,
	},
	];

$enc_postgresbackup_tests = &convert_to_encrypted($postgresbackup_tests);

$multibackup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, with a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain with dir' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, without a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain without dir' ],
		      [ $web ], [ 'dns' ],
		      @create_args, ],
	},

	# Back them both up to a directory
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Make sure backup and all meta files exist
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.info' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.dom' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_subdomain.'.tar.gz' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_subdomain.'.tar.gz.info' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_subdomain.'.tar.gz.dom' },

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

	# Restore with domain creation
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Clean out the backup dir
	{ 'command' => 'rm -rf '.$test_backup_dir },

	# Back all domains with domain owner permissions
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'as-owner' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Make sure the backup files are owned by the domain owner
	{ 'command' => 'ls -l '.$test_backup_dir.' | awk \'{ print $3 }\'',
	  'grep' => $test_domain_user,
	  'antigrep' => 'root',
	},

	# Delete the domains, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore with domain creation
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Restore DB with domain owner permissions
	{ 'command' => 'chmod -R 755 '.$test_backup_dir,
	},
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'feature', 'mysql' ],
		      [ 'feature', 'postgres' ],
		      [ 'as-owner' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	];

$enc_multibackup_tests = &convert_to_encrypted($multibackup_tests);

$remote_backup_dir = "/home/$test_target_domain_user";
$ssh_backup_prefix = "ssh://$test_target_domain_user:smeg\@localhost".
		     $remote_backup_dir;
$ftp_backup_prefix = "ftp://$test_target_domain_user:smeg\@localhost".
		     $remote_backup_dir;
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
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup via SSH
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$ssh_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Delete the backups file
	{ 'command' => "rm -rf /home/$test_target_domain_user/$test_domain.tar.gz" },

	# Backup via FTP
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$ftp_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup via SSH in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore via SSH in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
	},

	# Delete the backups dir
	{ 'command' => "rm -rf /home/$test_target_domain_user/backups" },

	# Backup via FTP in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ftp_backup_prefix/backups" ] ],
	},

	# Restore via FTP in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/backups" ] ],
	},

	# Delete the backups dir
	{ 'command' => "rm -rf /home/$test_target_domain_user/backups" },

	# Backup via SSH one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore via SSH, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
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

$enc_remotebackup_tests = &convert_to_encrypted($remotebackup_tests);

$webmin_backup_dir = "/tmp/webminbackup-test";
$webmin_backup_prefix = "webmin://$webmin_user:$webmin_pass\@localhost$webmin_backup_dir";

$webminbackup_tests = [
	# Create a domain for the backup target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Create backup dir
	{ 'command' => 'mkdir -p '.$webmin_backup_dir },

	# Backup via Webmin
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$webmin_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$webmin_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore via Webmin
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$webmin_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain via Webmin
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$webmin_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup via Webmin in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$webmin_backup_prefix/backups" ] ],
	},

	# Restore via Webmin in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$webmin_backup_prefix/backups" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Cleanup backup dir
	{ 'command' => 'rm -rf '.$webmin_backup_dir,
	  'cleanup' => 1,
	},
	];
if (!$webmin_user || !$webmin_pass) {
	$webminbackup_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}

$enc_webminbackup_tests = &convert_to_encrypted($webminbackup_tests);

if ($s3_account = &get_default_s3_account()) {
	$s3_backup_prefix = "s3://$s3_account->{'access'}:$s3_account->{'secret'}\@virtualmin-test-backup-bucket";
	}
$s3backup_tests = [
	# Create target bucket
	{ 'command' => 'create-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-test-backup-bucket' ] ],
	},

	# Create target bucket in another region
	{ 'command' => 'create-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-test-backup-bucket-eu-west-1' ],
		      [ 'location', 'eu-west-1' ] ],
	},

	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to S3
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$s3_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$s3_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from S3
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$s3_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from S3
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$s3_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to S3 in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $s3_backup_prefix ] ],
	},

	# Restore from S3 in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $s3_backup_prefix ] ],
	},

	# Backup from S3 one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $s3_backup_prefix ] ],
	},

	# Restore from S3, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $s3_backup_prefix ] ],
	},

	# Backup to S3 subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $s3_backup_prefix."/subdir" ] ],
	},

	# Restore from S3 subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $s3_backup_prefix."/subdir" ] ],
	},

	# Backup to S3 subdirectory using a date-based filename
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'strftime' ],
		      [ 'dest', $s3_backup_prefix."/subdir-%d-%M-%Y" ] ],
	},

	# Purge backups from S3
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'dest', $s3_backup_prefix."/subdir-%d-%M-%Y" ],
		      [ 'strftime' ],
		      [ 'purge', '0.00001' ] ],
	  'grep' => 'Deleting file',
	  'sleep' => 5,
	},

	# Backup to S3 in the other bucket
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$s3_backup_prefix-eu-west-1/$test_domain.tar.gz" ] ],
	},

	# Restore from S3 in the other bucket
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $s3_backup_prefix."-eu-west-1" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Delete the S3 buckets
	{ 'command' => 'delete-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-test-backup-bucket' ],
		      [ 'recursive' ] ],
	  'cleanup' => 1,
	},
	{ 'command' => 'delete-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-test-backup-bucket-eu-west-1' ],
		      [ 'recursive' ] ],
	  'cleanup' => 1,
	},
	];

$enc_s3backup_tests = &convert_to_encrypted($s3backup_tests);

$http_s3backup_tests = &convert_to_http_api($s3backup_tests);

$rs_backup_prefix = "rs://$config{'rs_user'}:$config{'rs_key'}\@virtualmin-test-backup-container";
$rsbackup_tests = [
	# Create target container
	{ 'command' => 'create-rs-container.pl',
	  'args' => [ [ 'container', 'virtualmin-test-backup-container' ] ],
	},

	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to Rackspace
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$rs_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$rs_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from Rackspace
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$rs_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from Rackspace
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$rs_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Rackspace in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $rs_backup_prefix ] ],
	},

	# Restore from Rackspace in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $rs_backup_prefix ] ],
	},

	# Backup from Rackspace one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $rs_backup_prefix ] ],
	},

	# Restore from Rackspace, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $rs_backup_prefix ] ],
	},

	# Backup to Rackspace subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $rs_backup_prefix."/subdir" ] ],
	},

	# Restore from Rackspace subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $rs_backup_prefix."/subdir" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Delete the Rackspace container
	{ 'command' => 'delete-rs-container.pl',
	  'args' => [ [ 'container', 'virtualmin-test-backup-container' ],
		      [ 'recursive' ] ],
	  'cleanup' => 1,
	},
	];

$enc_rsbackup_tests = &convert_to_encrypted($rsbackup_tests);

$gcs_backup_prefix = "gcs://virtualmin-test-backup-bucket";
$gcsbackup_tests = [
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to GCS
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$gcs_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$gcs_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from GCS
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$gcs_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from GCS
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$gcs_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to GCS in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $gcs_backup_prefix ] ],
	},

	# Restore from GCS in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $gcs_backup_prefix ] ],
	},

	# Backup from GCS one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $gcs_backup_prefix ] ],
	},

	# Restore from GCS, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $gcs_backup_prefix ] ],
	},

	# Backup to GCS subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $gcs_backup_prefix."/subdir" ] ],
	},

	# Restore from GCS subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $gcs_backup_prefix."/subdir" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_gcsbackup_tests = &convert_to_encrypted($gcsbackup_tests);

$dropbox_backup_prefix = "dropbox://virtualmin-test-backup-bucket";
$dropboxbackup_tests = [
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to Dropbox
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$dropbox_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$dropbox_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Dropbox again, to test that over-writing works
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$dropbox_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$dropbox_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from Dropbox
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$dropbox_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from Dropbox
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$dropbox_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Dropbox in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $dropbox_backup_prefix ] ],
	},

	# Backup to Dropbox in home format again, to test overwriting
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $dropbox_backup_prefix ] ],
	},

	# Restore from Dropbox in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $dropbox_backup_prefix ] ],
	},

	# Backup from Dropbox one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $dropbox_backup_prefix ] ],
	},

	# Restore from Dropbox, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $dropbox_backup_prefix ] ],
	},

	# Backup to Dropbox subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $dropbox_backup_prefix."/subdir" ] ],
	},

	# Restore from Dropbox subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $dropbox_backup_prefix."/subdir" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_dropboxbackup_tests = &convert_to_encrypted($dropboxbackup_tests);

$azure_backup_prefix = "azure://virtualmin-test-backup-bucket";
$azurebackup_tests = [
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to Azure
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$azure_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$azure_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Azure again, to test that over-writing works
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$azure_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$azure_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from Azure
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$azure_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from Azure
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$azure_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Azure in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $azure_backup_prefix ] ],
	},

	# Backup to Azure in home format again, to test overwriting
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $azure_backup_prefix ] ],
	},

	# Restore from Azure in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $azure_backup_prefix ] ],
	},

	# Backup from Azure one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $azure_backup_prefix ] ],
	},

	# Restore from Azure, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $azure_backup_prefix ] ],
	},

	# Backup to Azure subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $azure_backup_prefix."/subdir" ] ],
	},

	# Restore from Azure subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $azure_backup_prefix."/subdir" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_azurebackup_tests = &convert_to_encrypted($azurebackup_tests);

$drive_backup_prefix = "drive://virtualmin-test-backup-folder";
$drivebackup_tests = [
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to Google Drive
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$drive_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$drive_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Google Drive again, to test that over-writing works
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$drive_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$drive_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from Google Drive
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$drive_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from Google Drive
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$drive_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Google Drive in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $drive_backup_prefix ] ],
	},

	# Backup to Google Drive in home format again, to test overwriting
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $drive_backup_prefix ] ],
	},

	# Restore from Google Drive in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $drive_backup_prefix ] ],
	},

	# Backup from Google Drive one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $drive_backup_prefix ] ],
	},

	# Restore from Google Drive, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $drive_backup_prefix ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_drivebackup_tests = &convert_to_encrypted($drivebackup_tests);

$bb_backup_prefix = "bb://virtualmin-test-backup-bucket";
$bbbackup_tests = [
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Backup to Dropbox
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$bb_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$bb_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Backblaze again, to test that over-writing works
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$bb_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$bb_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore from Backblaze
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$bb_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain from Backblaze
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$bb_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup to Backblaze in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $bb_backup_prefix ] ],
	},

	# Backup to Backblaze in home format again, to test overwriting
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $bb_backup_prefix ] ],
	},

	# Restore from Backblaze in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $bb_backup_prefix ] ],
	},

	# Backup from Backblaze one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', $bb_backup_prefix ] ],
	},

	# Restore from Backblaze, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $bb_backup_prefix ] ],
	},

	# Backup to Backblaze subdirectory in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $bb_backup_prefix."/subdir" ] ],
	},

	# Restore from Backblaze subdirectory in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $bb_backup_prefix."/subdir" ] ],
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_bbbackup_tests = &convert_to_encrypted($bbbackup_tests);

$splitbackup_tests = [
	# Create a domain for the backup target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, with a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain with dir' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, without a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain without dir' ],
		      [ $web ], [ 'dns' ],
		      @create_args, ],
	},

	# Back them both up to two directories
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_parallel_domain1 ],
		      [ 'domain', $test_parallel_domain2 ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ],
		      [ 'dest', $test_backup_dir2 ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place from the first location
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Test that everything will works
	@post_restore_tests,

	# Delete web page again
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place from the second location
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir2 ] ],
	},

	# Test that everything will works again
	@post_restore_tests,

	# Backup to two remote locations
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $ssh_backup_prefix ],
		      [ 'dest', $ftp_backup_prefix ] ],
	  'timeout' => 300,
	},

	# Restore via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Backup to a single file on two remote locations
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', $ssh_backup_prefix."/onefile.tar.gz" ],
		      [ 'dest', $ftp_backup_prefix."/onefile.tar.gz" ] ],
	  'timeout' => 300,
	},

	# Restore via SSH from a single file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/onefile.tar.gz" ] ],
	},

	# Restore via FTP from a single file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/onefile.tar.gz" ] ],
	},

	# Backup to a local file and remote file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_dir.'/onefile.tar.gz' ],
		      [ 'dest', $ftp_backup_prefix."/onefile.tar.gz" ] ],
	},

	# Restore from the local file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir.'/onefile.tar.gz' ] ],
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$enc_splitbackup_tests = &convert_to_encrypted($splitbackup_tests);

$differential_tests = [
	# Create a test domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      [ 'mode', 'fcgid' ],
		      @create_args, ],
        },

	# Install Roundcube to use up some disk
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'roundcube' ],
		      [ 'path', '/roundcube' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'atleast-version', '1.3.17' ] ],
	  'antigrep' => 'partially complete',
	},

	# Test that roundcube works before the backup
	{ 'command' => $wget_command.'http://'.$test_domain.'/roundcube/',
	  'grep' => 'Welcome to Roundcube Webmail',
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Apply a content style change
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'content' => 'New website content' ] ],
	},

	# Create an differential backup
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'differential' ],
		      [ 'dest', $test_differential_backup_file ] ],
	},

	# Make sure the differential is smaller than the full
	{ 'command' =>
		"full=`du -k $test_backup_file | cut -f 1` ; ".
		"incr=`du -k $test_differential_backup_file | cut -f 1` ; ".
		"test \$incr -lt \$full"
	},

	# Create another differential backup
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'differential' ],
		      [ 'dest', $test_differential_backup_file2 ] ],
	},

	# Make sure the second differential is smaller than the full
	{ 'command' =>
		"full=`du -k $test_backup_file | cut -f 1` ; ".
		"incr=`du -k $test_differential_backup_file2 | cut -f 1` ; ".
		"test \$incr -lt \$full"
	},

	# Make sure the two differentials are the same
	{ 'command' =>
		"incr=`du -k $test_differential_backup_file | cut -f 1` ; ".
		"incr2=`du -k $test_differential_backup_file2 | cut -f 1` ; ".
		"test \$incr -eq \$incr2"
	},

	# Delete the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore the full backup
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Restore the differential
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_differential_backup_file ] ],
	},

	# Verify that the latest files were restored
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'New website content',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/roundcube/',
	  'grep' => 'Welcome to Roundcube Webmail',
	},

	# Finally delete to clean up
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$enc_differential_tests = &convert_to_encrypted($differential_tests);

$purge_tests = [
	# Create a test domain to backup
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a domain for the backup target via SSH
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Backup to a date-based directory that is a lie
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'dest', $test_backup_dir.'/1973-12-12' ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(124531200, 124531200, \"$test_backup_dir/1973-12-12\")'"
	},

	# Do another strftime-format backup with purging, to remove the old dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'strftime' ],
		      [ 'purge', 30 ],
		      [ 'dest', $test_backup_dir.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting directory',
	},

	# Make sure the right dir got deleted
	{ 'command' => 'ls -ld '.$test_backup_dir.'/1973-12-12',
	  'fail' => 1 },
	{ 'command' => 'ls -ld '.$test_backup_dir.'/'.$nowdate },

	# Backup via SSH to a date-based directory that is a lie
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/1973-12-12" ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(124531200, 124531200, \"$remote_backup_dir/1973-12-12\")'"
	},

	# Do another SSH strftime-format backup with purging
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'strftime' ],
		      [ 'purge', 30 ],
		      [ 'dest', $ssh_backup_prefix.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting file',
	},

	# Backup via FTP to a date-based directory that is a lie, but only
	# one day ago to exercise the different date format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/$yesterdaydate" ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(time()-24*60*60, time()-24*60*60, \"$remote_backup_dir/$yesterdaydate\")'"
	},

	# Do another FTP strftime-format backup with purging
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'strftime' ],
		      [ 'purge', '0.5' ],
		      [ 'dest', $ftp_backup_prefix.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting FTP file',
	},

	# Finally delete to clean up
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},
	];

$mail_tests = [
	# Create a domain to get spam
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ], [ $web ],
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

	# If spamd is running, make it restart so that it picks up the new user
	{ 'command' => $gconfig{'os_type'} eq 'solaris' ?
			'pkill -HUP spamd' : 'killall -HUP spamd',
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

        # Send some reasonable mail to him
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
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

	# Use IMAP and POP3 to count mail - should be two or more
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
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
			       '`virtualmin list-domains.pl --domain '.$test_domain.
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

        # Enable a website
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'web' ] ],
	},

	# Enable mail autoconfig URL
	{ 'command' => 'modify-mail.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'autoconfig' ] ],
	},

	# Test the URL
	{ 'command' => $wget_command.'http://autoconfig.'.$test_domain.
		       '/mail/config-v1.1.xml?emailaddress=foo@'.$test_domain,
	  'grep' => 'clientConfig',
	  'sleep' => 5,
	},

	# Disable mail autoconfig URL
	{ 'command' => 'modify-mail.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-autoconfig' ] ],
	},

	# Test the URL is gone
	{ 'command' => $wget_command.'http://autoconfig.'.$test_domain.
		       '/mail/config-v1.1.xml?emailaddress=foo@'.$test_domain,
	  'antigrep' => 'clientConfig',
	  'ignorefail' => 1,
	  'sleep' => 5,
	},

	# Test that the DNS record is gone too
	{ 'command' => 'host -t A autoconfig.'.$test_domain.' '.$dnsserver,
	  'fail' => 1,
	},

	# Test sender BCC feature
	$supports_bcc >= 1 ? (
		# Enable outgoing BCC
		{ 'command' => 'modify-mail.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'sender-bcc', 'bob@bob.com' ] ],
		},

		# Test if set in config
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'domain', $test_domain ],
                              [ 'multiline' ] ],
		  'grep' => 'BCC email to: bob@bob.com',
		},

		# Disable outgoing BCC
		{ 'command' => 'modify-mail.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'no-sender-bcc' ] ],
		},

		# Test if set gone from config
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'domain', $test_domain ],
                              [ 'multiline' ] ],
		  'antigrep' => 'BCC email to:',
		},

		) : ( ),

	# Test recipient feature
	$supports_bcc >= 2 ? (
		# Enable incoming BCC
		{ 'command' => 'modify-mail.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'recipient-bcc', 'bob@bob.com' ] ],
		},

		# Test if set in config
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'domain', $test_domain ],
                              [ 'multiline' ] ],
		  'grep' => 'BCC incoming email to: bob@bob.com',
		  'antigrep' => 'BCC email to:',
		},

		# Disable incoming BCC
		{ 'command' => 'modify-mail.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'no-recipient-bcc' ] ],
		},

		# Test if set gone from config
		{ 'command' => 'list-domains.pl',
		  'args' => [ [ 'domain', $test_domain ],
                              [ 'multiline' ] ],
		  'antigrep' => 'BCC incoming email to:',
		},

		) : ( ),

	&get_dkim_type() && ($dkim = &get_dkim_config()) &&
	    $dkim && $dkim->{'enabled'} ? (
		# Check for the DKIM DNS record
		{ 'command' => 'get-dns.pl',
		  'args' => [ [ 'multiline' ],
			      [ 'domain', $test_domain ],
			      [ 'regexp' => '_domainkey' ] ],
		  'grep' => [ 'v=DKIM1' ],
		},

		# Check that it can actually be looked up
		{ 'command' => 'dig TXT default._domainkey.'.$test_domain.' ; dig SPF default._domainkey.'.$test_domain,
		  'grep' => 'v=DKIM1',
		},
		) : ( ),

	# Enable webmail DNS record and redirect
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webmail' ] ],
	},

	# Test wget to it
	{ 'command' => $wget_command.'http://webmail.'.$test_domain.'/',
	  'grep' => 'Usermin',
	},

	# Disable webmail DNS record and redirect
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-webmail' ] ],
	},

	# Test wget to it, which should fail now
	{ 'command' => $wget_command.'http://webmail.'.$test_domain.'/',
	  'fail' => 1,
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },
	];

$atmail_tests = &convert_to_atmail($mail_tests);

$aliasmail_tests = [
	# Create a domain to be the alias target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'spod' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],
        },

	# Create an alias domain to get mail
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'alias-with-mail', $test_target_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'dns' ], [ 'mail' ],
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

	# If spamd is running, make it restart so that it picks up the new user
	{ 'command' => $gconfig{'os_type'} eq 'solaris' ?
			'pkill -HUP spamd' : 'killall -HUP spamd',
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

        # Send some reasonable mail to him
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
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

	# Use IMAP and POP3 to count mail - should be two or more
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
        },
	];

$exclude_tests = [
	# Create a domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-directory and file to exclude
	{ 'command' => 'su -s /bin/sh '.$test_domain_user.' -c "mkdir ~/xxx"',
	},
	{ 'command' => 'su -s /bin/sh '.$test_domain_user.' -c "touch ~/xxx/yyy.txt"',
	},

	# Create a sub-directory and file to keep
	{ 'command' => 'su -s /bin/sh '.$test_domain_user.' -c "mkdir ~/aaa"',
	},
	{ 'command' => 'su -s /bin/sh '.$test_domain_user.' -c "touch ~/aaa/yyy.txt"',
	},

	# Add an extra MySQL database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Set exclude path
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-exclude', 'zzz' ],
		      [ 'add-exclude', 'xxx' ],
		      [ 'add-exclude', 'vvv' ] ],
	},

	# Set exclude DB
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-db-exclude', $test_domain_user.'_extra' ] ],
	},

	# Check exclude list
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Backup exclusion: xxx',
		      'Backup exclusion: vvv',
		      'Backup exclusion: zzz',
		      'Backup DB exclusion: '.$test_domain_user.'_extra' ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore to re-create
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Make sure the dir is gone
	{ 'command' => 'ls -ld '.$test_domain_home.'/xxx',
	  'fail' => 1,
	},

	# Make sure the other dir still exists
	{ 'command' => 'ls -ld '.$test_domain_home.'/aaa',
	},

	# Make sure the removed DB is gone
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => '^'.$test_domain_user.'_extra',
	},

	# Remove path exclude
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-exclude', 'zzz' ] ],
	},

	# Remove DB exclude
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-db-exclude', $test_domain_user.'_extra' ] ],
	},

	# Re-check exclude list
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Backup exclusion: xxx',
		      'Backup exclusion: vvv' ],
	  'antigrep' => [ 'Backup exclusion: zzz',
			  'Backup DB exclusion: '.$test_domain_user.'_extra' ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$prepost_tests = [
	# Create a domain just to see if scripts run
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ],
		      [ 'logrotate' ],
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
        },

	# Check the pre and post deletion scripts for the deletion
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE '.$test_domain,
		      'AFTER '.$test_domain ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	$virtualmin_pro ? 
		(
		# Create a reseller for the new domain
		{ 'command' => 'create-reseller.pl',
		  'args' => [ [ 'name', $test_reseller ],
			      [ 'pass', 'smeg' ],
			      [ 'desc', 'Test reseller' ],
			      [ 'email', $test_reseller.'@'.$test_domain ] ],
		},
		) : ( ),

	# Re-create the domain, capturing all variables
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      $virtualmin_pro ? ( [ 'reseller', $test_reseller ] )
				      : ( ),
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ],
		      [ 'logrotate' ],
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( [ 'virtualmin-awstats' ] ) : ( ),
		      [ 'post-command' => 'env >/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure all important variables were set
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'VIRTUALSERVER_ACTION=CREATE_DOMAIN',
		      'VIRTUALSERVER_DOM='.$test_domain,
		      'VIRTUALSERVER_USER='.$test_domain_user,
		      'VIRTUALSERVER_OWNER=Test domain',
		      'VIRTUALSERVER_UID=\d+',
		      'VIRTUALSERVER_GID=\d+',
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( 'VIRTUALSERVER_VIRTUALMIN_AWSTATS=1' ) : ( ),
		      $virtualmin_pro ? (
			      'RESELLER_NAME='.$test_reseller,
			      'RESELLER_DESC=Test reseller',
			      'RESELLER_EMAIL='.$test_reseller.'@'.$test_domain,
			      ) : ( ),
		    ]
	},

	# Set a custom field
	{ 'command' => 'modify-custom.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'allow-missing' ],
		      [ 'set', 'myfield foo' ] ],
	},

	# Create a sub-server, capturing all variables
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'post-command' => 'env >/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure parent variables work
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'VIRTUALSERVER_ACTION=CREATE_DOMAIN',
		      'VIRTUALSERVER_DOM='.$test_subdomain,
		      'VIRTUALSERVER_OWNER=Test sub-domain',
		      'PARENT_VIRTUALSERVER_USER='.$test_domain_user,
		      'PARENT_VIRTUALSERVER_DOM='.$test_domain,
		      'PARENT_VIRTUALSERVER_OWNER=Test domain',
		      'PARENT_VIRTUALSERVER_FIELD_MYFIELD=foo',
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( 'PARENT_VIRTUALSERVER_VIRTUALMIN_AWSTATS=1' ) : ( ),
		      $virtualmin_pro ? (
			      'RESELLER_NAME='.$test_reseller,
			      'RESELLER_DESC=Test reseller',
			      'RESELLER_EMAIL='.$test_reseller.'@'.$test_domain,
			      ) : ( ),
		    ]
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },

	$virtualmin_pro ? (
		# Cleanup the reseller
		{ 'command' => 'delete-reseller.pl',
		  'args' => [ [ 'name', $test_reseller ] ],
		  'cleanup' => 1 },
		) : ( ),
	];

$webmin_tests = [
	# Make sure the main Virtualmin page can be displayed
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/",
	  'grep' => [ 'Virtualmin Virtual Servers',
		      $virtualmin_pro ? ( 'Delete Selected' ) : ( ) ],
	},

	# Check left and right frames (if using the framed theme)
	$webmin_user_theme eq "virtual-server-theme" ? (
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/",
	  'grep' => [ '<frameset', '</frameset>', 'left.cgi', 'right.cgi' ],
	},
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/left.cgi",
	  'grep' => [ '<body', '</body>', '<select' ],
	},
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/right.cgi",
	  'grep' => [ '<body', '</body>', 'System hostname',
		      $virtualmin_pro ? ( 'Virtualmin License' ) : ( ) ],
	},
	) : ( ),

	# Create a test domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/domain_setup.cgi?dom=$test_domain&vpass=smeg&template=0&plan=0&dns_ip_def=1&vuser_def=1&email_def=1&mgroup_def=1&group_def=1&prefix_def=1&db_def=1&quota=100&quota_units=1048576&uquota=120&uquota_units=1048576&bwlimit_def=0&bwlimit=100&bwlimit_units=MB&mailboxlimit_def=1&aliaslimit_def=0&aliaslimit=34&dbslimit_def=0&dbslimit=10&domslimit_def=0&domslimit=3&nodbname=0&field_purpose=&field_amicool=&unix=1&dir=1&logrotate=1&mail=1&dns=1&$web=1&webalizer=1&mysql=1&webmin=1&proxy_def=1&fwdto_def=1&virt=0&ip=&content_def=1'",
	  'grep' => [ 'Adding new virtual website|Creating Nginx virtual host',
		      'Saving server details' ],
	},

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Get the domain ID
	{ 'command' => 'list-domains.pl --id-only --domain '.$test_domain,
	  'save' => 'DOMAIN_ID',
	},

	# Check Webmin login as domain owner
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	},

	# List users in the domain
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/list_users.cgi?dom=\$DOMAIN_ID",
	  'grep' => [ '<body', '</body>', 'Edit Users',
		      '<b>'.$test_domain_user.'</b>' ],
	},

	# Add a user to the domain
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_user.cgi?dom=\$DOMAIN_ID\\&new=1\\&mailuser=bob\\&real=Bob+Smeg\\&mailpass=smeg\\&quota_def=1\\&mquota_def=1\\&home_def=1\\&mailbox=1\\&tome=1\\&newmail_def=1\\&shell=/dev/null\\&recovery_def=1",
	  'antigrep' => 'Failed to save user',
	},

	# Verify the new user exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "bob",
	},

	# Open the page to edit the user
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/edit_user.cgi?dom=\$DOMAIN_ID\\&user=bob\\&unix=1",
	  'grep' => [ '<body', '</body>', 'Edit User', 'Save', 'Delete' ],
	},

	# Modify the user to enable forwarding
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_user.cgi?dom=\$DOMAIN_ID\\&old=bob\\&unix=1\\&mailuser=bob\\&oldpop3=bob\\&real=Bob+Smeg\\&mailpass_def=1\\&quota_def=1\\&mquota_def=1\\&home_def=1\\&mailbox=1\\&forward=1\\&forwardto=nobody\@virtualmin.com\\&shell=/dev/null\\&remail_def=1\\&simplemode=simple\\&recovery_def=1",
	  'antigrep' => 'Failed to save user',
	},

	# Check that forwarding is set
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'simple-aliases' ] ],
	  'grep' => 'Forward: nobody@virtualmin.com',
	},

	# Delete the user
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_user.cgi?dom=\$DOMAIN_ID\\&old=bob\\&unix=1\\&delete=1\\&confirm=1",
	  'antigrep' => 'Failed to save user',
	},

	# List mail aliases in the domain
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/list_aliases.cgi?dom=\$DOMAIN_ID",
	  'grep' => [ '<body', '</body>', 'Mail Aliases',
		      'Delete Selected Aliases' ],
	},

	# Create a new alias
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_alias.cgi?dom=\$DOMAIN_ID\\&new=1\\&simplename=sales\\&simplemode=simple\\&forward=1\\&forwardto=nobody\@virtualmin.com",
	  'antigrep' => 'Failed to save alias',
	},

	# Verify that the new alias exists
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^sales@'.$test_domain,
		      'To: nobody@virtualmin.com' ],
	},

	# Open the page to edit the alias
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/edit_alias.cgi?dom=\$DOMAIN_ID\\&from=sales\@${test_domain}",
	  'grep' => [ '<body', '</body>', 'Edit Mail Alias', 'Save', 'Delete' ],
	},

	# Re-save the alias
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_alias.cgi?dom=\$DOMAIN_ID\\&old=sales\@${test_domain}\\&simplename=sales\\&simplemode=simple\\&forward=1\\&forwardto=nobody\@webmin.com",
	  'antigrep' => 'Failed to save alias',
	},

	# Verify that the change happened
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^sales@'.$test_domain,
		      'To: nobody@webmin.com' ],
	},

	# Delete the alias
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_alias.cgi?dom=\$DOMAIN_ID\\&old=sales\@${test_domain}\\&delete=1",
	  'antigrep' => 'Failed to save alias',
	},

	# List databases in the domain
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/list_databases.cgi?dom=\$DOMAIN_ID",
	  'grep' => [ '<body', '</body>', 'Edit Databases',
		      'Delete Selected' ],
	},

	# Create a new database
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_database.cgi?dom=\$DOMAIN_ID\\&new=1\\&name=${test_domain_db}_junk\\&type=mysql",
	  'antigrep' => 'Failed to create database',
	},

	# Verify that it was created
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_domain_db.'_junk',
	},

	# Check MySQL login to the database
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_junk -e "select version()"',
	},

	# Edit that same database
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/edit_database.cgi?dom=\$DOMAIN_ID\\&type=mysql\\&name=${test_domain_db}_junk",
	  'grep' => [ '<body', '</body>', 'Delete This Database',
		      'Manage Database' ],
	},

	# Delete the database
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/save_database.cgi?dom=\$DOMAIN_ID\\&delete=1\\&confirm=1\\&name=${test_domain_db}_junk\\&type=mysql",
	},

	# Verify that it is gone
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => '^'.$test_domain_db.'_junk',
	},

	# Verify that list of scripts works
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/list_scripts.cgi?dom=\$DOMAIN_ID",
	  'grep' => [ '<body', '</body>', 'Manage Web Apps',
		      'phpMyAdmin', 'Installed Web Apps','Available Web Apps' ],
	},

	# Install a script via the web UI
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/script_install.cgi?dom=\$DOMAIN_ID\\&script=roundcube\\&version=1.3.17\\&dir_def=0\\&dir=roundcube\\&passmode=\\&db=mysql_${test_domain_db}",
	  'grep' => [ '<body', '</body>', 'Install Web App', 
		      'Now installing RoundCube' ],
	  'antigrep' => [ 'Failed to install' ],
	},

	# Make sure it worked
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: roundcube',
		      'Database: '.$test_domain_db.' ',
		      'URL: http(s?)://'.$test_domain.'/roundcube',
		    ],
	},

	# Verify that list of scripts contains roundcube
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/list_scripts.cgi?dom=\$DOMAIN_ID",
	  'grep' => [ '/roundcube' ],
	},

	# Get the script ID
	{ 'command' => 'list-scripts.pl --id-only --domain '.$test_domain,
	  'save' => 'SCRIPT_ID',
	},

	# Un-install the script
	{ 'command' => $webmin_wget_command.
                       "${webmin_proto}://localhost:${webmin_port}/virtual-server/unscript_install.cgi?dom=\$DOMAIN_ID\\&confirm=1\\&script=\$SCRIPT_ID",
	  'grep' => [ '<body', '</body>', 'RoundCube directory and tables deleted' ],
	  'antigrep' => [ 'Failed to uninstall script' ],
	},

	# Test other per-domain pages
	(map {
		my $page = $_.".cgi";
		{ 'command' => $webmin_wget_command.
			       "${webmin_proto}://localhost:${webmin_port}/virtual-server/${page}?dom=\$DOMAIN_ID",
		  'antigrep' => [ '>Failed to' ],
		}
		} @other_webmin_pages),

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/virtual-server/delete_domain.cgi\\?dom=\$DOMAIN_ID\\&confirm=1",
	  'grep' => [ 'Deleting virtual website|Removing Nginx virtual host',
		      'Deleting server details' ],
	  'cleanup' => 1,
	},
	];
if (!$webmin_user || !$webmin_pass) {
	$webmin_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}

$remote_tests = [
	# Test domain creation via remote API
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=create-domain&domain=$test_domain&pass=smeg&dir=&unix=&$web=&dns=&mail=&webalizer=&mysql=&logrotate=&webmin=&".join("&", map { $_->[0]."=" } @create_args)."'",
	  'grep' => 'Exit status: 0',
	},

	# Make sure it was created
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains'",
	  'grep' => [ "^$test_domain", 'Exit status: 0' ],
	},

	# Check Webmin login as domain owner
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	},

	# Get the domain in JSON format
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains&domain=$test_domain&multiline=&json=1'",
	  'grep' => [ "\"name\" : \"$test_domain\"" ],
	},

	# Get the domain in XML format
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains&domain=$test_domain&multiline=&xml=1'",
	  'grep' => [ "name=\"$test_domain\"" ],
	},

	# Get the domain in Perl format
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains&domain=$test_domain&multiline=&perl=1'",
	  'grep' => [ "'name' => '$test_domain'" ],
	},

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=delete-domain&domain=$test_domain'",
	  'grep' => [ 'Exit status: 0' ],
	  'cleanup' => 1,
	},
	];
if (!$webmin_user || !$webmin_pass) {
	$remote_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}

$ssl_tests = [
	# Create a domain with SSL and a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ $ssl ],
		      [ 'logrotate' ],
		      [ 'allocate-ip' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Create a sub-domain with SSL on the same IP
	{ 'command' => 'create-domain.pl',
          'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'desc', 'Test SSL subdomain' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent-ip' ],
		      [ 'content' => 'Test SSL subdomain home page' ],
		      @create_args, ],
	},

	# Create a second sub-domain with SSL on the same IP, but with no
	# linked cert, but with redirect to SSL
	{ 'command' => 'create-domain.pl',
          'args' => [ [ 'domain', $test_ssl2_subdomain ],
		      [ 'desc', 'Test SSL 2 subdomain' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent-ip' ],
		      [ 'break-ssl-cert' ],
		      [ 'ssl-redirect' ],
		      [ 'content' => 'Test SSL subdomain home page' ],
		      @create_args, ],
	},

	# Create an alias domain for the second sub-domain
	{ 'command' => 'create-domain.pl',
          'args' => [ [ 'domain', $test_target_domain ],
		      [ 'alias', $test_ssl2_subdomain ],
		      [ 'desc', 'Test SSL 2 alias' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      [ 'parent-ip' ],
		      @create_args, ],
	},

	# Make sure TLSA records are enabled
	{ 'command' => 'modify-dns.pl',
          'args' => [ [ 'domain', $test_domain ],
		      [ 'enable-tlsa' ] ],
	},

	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_domain,
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

	# Test HTTP get to subdomain, which should not redirect
	{ 'command' => $wget_command.'http://'.$test_ssl_subdomain,
	  'grep' => 'Test SSL subdomain home page',
	  'antigrep' => 'https://'.$test_ssl_subdomain,
	},

	# Test HTTP get to second subdomain, which should redirect
	{ 'command' => $wget_command.'http://'.$test_ssl2_subdomain,
	  'grep' => ['Test SSL subdomain home page',
		     'https://'.$test_ssl2_subdomain],
	},

	# Test HTTP get to alias, which should redirect to itself
	{ 'command' => $wget_command.'http://'.$test_target_domain,
	  'grep' => ['Test SSL subdomain home page',
		     'https://'.$test_target_domain],
	},

	# Check for SSL linkage
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'SSL shared with: '.$test_domain ],
	  'antigrep' => [ 'SSL key file: '.$test_domain_home.
		          '/domains/'.$test_ssl_subdomain.'/',
		          'SSL cert file: '.$test_domain_home.
                          '/domains/'.$test_ssl_subdomain.'/' ],
	},

	# Check for SSL expiry, and save it
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'SSL cert expiry:' ],
	},
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'ssl-expiry-only' ] ],
	  'save' => 'SSL_EXPIRY',
	},

	# Test HTTPS get to subdomain
	{ 'command' => $wget_command.'https://'.$test_ssl_subdomain,
	  'grep' => 'Test SSL subdomain home page',
	},

	# Test SSL cert to subdomain (should be the same)
	{ 'command' => 'openssl s_client -host '.$test_ssl_subdomain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},
	
	# Check for no SSL linkage on the second domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl2_subdomain ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'SSL shared with: '.$test_domain ],
	  'grep' => [ 'SSL key file: '.$test_domain_home.
		      '/domains/'.$test_ssl2_subdomain.'/',
		      'SSL cert file: '.$test_domain_home.
                      '/domains/'.$test_ssl2_subdomain.'/' ],
	},

	# Check for TLSA records
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'TLSA' ],
		      [ 'multiline' ] ],
	  'grep' => [ '^_443._tcp.www.'.$test_domain,
		      '^_443._tcp.'.$test_domain,
		      $webmin_proto eq 'https' ?
			( '^_'.$webmin_port.'._tcp.'.$test_domain ) : ( ),
		      $usermin_proto eq 'https' ?
			( '^_'.$usermin_port.'._tcp.'.$test_domain ) : ( ),
		    ],
	},

	# Re-link SSL on the second domain
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_ssl2_subdomain ],
		      [ 'link-ssl-cert' ] ],
	},

	# Check for SSL linkage on the second domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl2_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'SSL shared with: '.$test_domain ],
	  'antigrep' => [ 'SSL key file: '.$test_domain_home.
		          '/domains/'.$test_ssl2_subdomain.'/',
		          'SSL cert file: '.$test_domain_home.
                          '/domains/'.$test_ssl2_subdomain.'/' ],
	},
	
	# Test HTTPS get to the second subdomain
	{ 'command' => $wget_command.'https://'.$test_ssl2_subdomain,
	  'grep' => 'Test SSL subdomain home page',
	},

	# Test SSL cert to the second subdomain (should be the same)
	{ 'command' => 'openssl s_client -host '.$test_ssl2_subdomain.
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

	$supports_cgi ? (
		# Switch PHP mode to CGI
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'cgi' ] ],
		},

		# Check PHP running via CGI via HTTPS
		{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
			       $test_domain_user.'/public_html/test.php',
		},
		{ 'command' => $wget_command.
			       'https://'.$test_domain.'/test.php',
		  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
		},
		) : ( ),

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

	# Test SSL cert info
	{ 'command' => 'get-ssl.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'cn: '.$test_domain, 'o: Virtualmin',
		      'alt: test_subdomain' ],
	},

	# Test if expiry was updated
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'ssl-expiry-only' ] ],
	  'antigrep' => '$SSL_EXPIRY',
	},

	# Test new SSL cert via HTTP
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Virtualmin', 'CN='.$test_domain ],
	},

	# Make sure SSL linkage is broken
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'multiline' ] ],
	  'antigrep' => 'SSL shared with:',
	  'grep' => [ 'SSL key file: '.$test_domain_home.
		      '/domains/'.$test_ssl_subdomain.'/',
		      'SSL cert file: '.$test_domain_home.
                      '/domains/'.$test_ssl_subdomain.'/' ],
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
		      'BEGIN (RSA )?PRIVATE KEY', 'END (RSA )?PRIVATE KEY',
		      'BEGIN CERTIFICATE REQUEST', 'END CERTIFICATE REQUEST' ],
	},

	# Test re-installation of the cert and key
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'cert', $test_domain_cert ],
		      [ 'key', $test_domain_key ] ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

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

	# Test DNS lookup after the restore
	{ 'command' => 'host -t A '.$test_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test HTTPS get after the restore
	{ 'command' => $wget_command.'https://'.$test_domain,
	  'grep' => 'Test SSL home page',
	},

	# Get a shared IP address
	{ 'command' => 'list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Re-create the main domain with a shared IP
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ $ssl ],
		      [ 'logrotate' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Re-create the sub-domain with a different owner
	{ 'command' => 'create-domain.pl',
          'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'desc', 'Test SSL subdomain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL subdomain home page' ],
		      @create_args, ],
	},

	# Check that there is no SSL linkage
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'multiline' ] ],
	  'antigrep' => 'SSL shared with:',
	},

	# Test SSL cert to main domain
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Test SSL cert to subdomain
	{ 'command' => 'openssl s_client -host '.$test_ssl_subdomain.
		       ' -servername '.$test_ssl_subdomain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL subdomain', 'CN=(\\*\\.)?'.$test_ssl_subdomain ],
	},

	# Delete the subdomain and re-create with forced linkage
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ] ],
	},
	{ 'command' => 'create-domain.pl',
          'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'desc', 'Test SSL subdomain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'always-link-ssl-cert' ],
		      [ 'content' => 'Test SSL subdomain home page' ],
		      @create_args, ],
	},

	# Check that there is an SSL linkage now
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => 'SSL shared with: '.$test_domain,
	},

	# Test SSL cert to subdomain with linkage
	{ 'command' => 'openssl s_client -host '.$test_ssl_subdomain.
		       ' -servername '.$test_ssl_subdomain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Break the linkage, which should copy in the cert
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'break-ssl-cert' ] ],
	},

	# Check that there is no longer an SSL linkage
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ],
		      [ 'multiline' ] ],
	  'antigrep' => 'SSL shared with: '.$test_domain,
	  'grep' => [ 'SSL key file: '.$test_ssl_subdomain_home.'/',
		      'SSL cert file: '.$test_ssl_subdomain_home.'/', ],
	},

	# Test SSL cert to subdomain with copied cert
	{ 'command' => 'openssl s_client -host '.$test_ssl_subdomain.
		       ' -servername '.$test_ssl_subdomain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Move the cert and key files to a custom location
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'ssl-cert', $test_domain_home.'/ssl.cert' ],
		      [ 'ssl-key', $test_domain_home.'/ssl.key' ] ],
	},

	# Make sure it worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'SSL cert file: '.$test_domain_home.'/ssl.cert',
		      'SSL key file: '.$test_domain_home.'/ssl.key' ],
	},

	# Also check that HTTPS still works
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# And re-run validation
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ] ],
	},

	# Move back to default paths
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'default-ssl-paths' ] ],
	},

	# Make sure it worked too
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'SSL cert file: '.$test_domain_home.'/ssl.cert',
		          'SSL key file: '.$test_domain_home.'/ssl.key' ],
	},

	# Check for TLSA records again after all these changes
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'TLSA' ],
		      [ 'multiline' ] ],
	  'grep' => [ '^_443._tcp.www.'.$test_domain,
		      '^_443._tcp.'.$test_domain,
		      $webmin_proto eq 'https' ?
			( '^_'.$webmin_port.'._tcp.'.$test_domain ) : ( ),
		      $usermin_proto eq 'https' ?
			( '^_'.$usermin_port.'._tcp.'.$test_domain ) : ( ),
		    ],
	},

	# Turn off TLSA
	{ 'command' => 'modify-dns.pl',
          'args' => [ [ 'domain', $test_domain ],
		      [ 'disable-tlsa' ] ],
	},

	# Make sure TLSA records are gone
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'TLSA' ],
		      [ 'multiline' ] ],
	  'antigrep' => [ 'TLSA' ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_ssl_subdomain ] ],
	  'ignorefail' => 1,
	  'cleanup' => 1 },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$sslserv_tests = [
	# Create a domain with SSL and a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ $ssl ], [ 'logrotate' ], [ 'webmin' ],
		      [ 'allocate-ip' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Create an alias as well
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'alias', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test alias-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Install a dummy CA cert
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'ca', $module_root_directory.'/lets-encrypt-*.pem.txt' ] ],
	},

	# Get the IP address
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'ip-only' ],
		      [ 'domain', $test_domain ] ],
	  'save' => 'PRIVATE_IP',
	},

	# Force enable private SSL cert for Webmin, Usermin, etc
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Check that they show up in list-domains
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'SSL cert used by: dovecot \\($PRIVATE_IP\\)',
		      'SSL cert used by: postfix \\($PRIVATE_IP\\)',
		      'SSL cert used by: webmin \\('.$test_domain.'\\)',
		      'SSL cert used by: usermin \\('.$test_domain.'\\)',
		    ],
	},

	# Check that cert is in the Dovecot config for the IP
	{ 'command' => 'cat '.&dovecot::get_config_file(),
	  'grep' => [ 'local $PRIVATE_IP', ],
	},

	# Validate that Webmin cert works
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://'.$test_domain.':'.
		       $webmin_port.'/',
	},
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$webmin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Usermin cert works
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$usermin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Dovecot cert works
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', 'mail.'.$test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Postfix cert works
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ],
		      [ 'server', 'mail.'.$test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Re-generate the cert with a different org
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'self' ],
		      [ 'o', 'Test 2 SSL domain' ] ],
	},

	# Validate that new Dovecot cert works
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test 2 SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that new Postfix cert works
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'grep' => [ 'O=Test 2 SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Re-generate the cert with original org
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'self' ],
		      [ 'o', 'Test SSL domain' ] ],
	},

	# Turn off private IP for the domain
	{ 'command' => 'modify-domain.pl',
          'args' => [ [ 'domain', $test_domain ],
		      [ 'default-ip' ] ],
	},

	# Check that they show up in list-domains, but by domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'SSL cert used by: dovecot \\('.$test_domain.'\\)',
		      'SSL cert used by: webmin \\('.$test_domain.'\\)',
		      'SSL cert used by: usermin \\('.$test_domain.'\\)',
		    ],
	  'antigrep' => [ 'SSL cert used by: postfix' ],
	},

	# Check that cert is in the Dovecot config, but by hostname
	{ 'command' => 'cat '.&dovecot::get_config_file(),
	  'grep' => [ 'local_name '.$test_domain,
		      'local_name \\*\\.'.$test_domain,
		    ],
	},

	# Check that cert is not in the Dovecot config for the IP anymore
	{ 'command' => 'cat '.&dovecot::get_config_file(),
	  'antigrep' => [ 'local $PRIVATE_IP', ],
	},

	# Validate that Webmin cert still works with SNI
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://'.$test_domain.':'.
		       $webmin_port.'/',
	},
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port '.$webmin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Usermin cert still works with SNI
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port '.$usermin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Dovecot cert still works with SNI
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', $test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Dovecot cert still works with SNI on the alias
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', $test_subdomain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_subdomain.
		       ' -servername '.$test_subdomain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Re-check that Postfix still works, but without the per-IP cert
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ],
		      [ 'server', $test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -servername mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'antigrep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},
	
	# Re-generate the cert with a different org
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'self' ],
		      [ 'o', 'Test 2 SSL domain' ] ],
	},

	# Validate that new Dovecot cert still works with SNI
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -servername '.$test_domain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test 2 SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Re-check that new Postfix still works
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -servername mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'antigrep' => [ 'O=Test 2 SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Turn off per-service certs
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Check that cert is no longer in the Dovecot config
	{ 'command' => 'cat '.&dovecot::get_config_file(),
	  'antigrep' => [ 'local_name '.$test_domain,
		          'local_name \\*\\.'.$test_domain,
		        ],
	},

	# Re-check that per-domain cert is no longer being used
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$webmin_port.' </dev/null',
	  'antigrep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	  'sleep' => 1,
	},
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$usermin_port.' </dev/null',
	  'antigrep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 993 </dev/null',
	  'antigrep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'antigrep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Turn per-service certs back on again, so we can test deletion
	{ 'command' => 'modify-domain.pl',
          'args' => [ [ 'domain', $test_domain ],
		      [ 'allocate-ip' ] ],
	},
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$nossl_tests = [
	# Create a domain without SSL, but with a private IP and a cert
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ], [ 'webmin' ], [ 'mail' ],
		      [ 'allocate-ip' ],
		      [ 'generate-ssl-cert' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Test SSL cert info
	{ 'command' => 'get-ssl.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'cn: \*.'.$test_domain ],
	},
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'SSL cert file:', 'SSL key file:' ],
	},

	# Remove from other services before removing the cert
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Try removing the cert
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-cert' ] ],
	},

	# Test that it's gone
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'antigrep' => [ 'SSL cert file:', 'SSL key file:' ],
	},

	# Bring it back
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'o' => 'Test SSL domain' ],
		      [ 'self' ] ],
	},

	# Force enable private SSL cert for Webmin, Usermin, etc
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Validate that Webmin cert works
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://'.$test_domain.':'.
		       $webmin_port.'/',
	},
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$webmin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Usermin cert works
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port '.$usermin_port.' </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Dovecot cert works
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', 'mail.'.$test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 993 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Validate that Postfix cert works
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ],
		      [ 'server', 'mail.'.$test_domain ],
		      [ 'ssl' ] ],
	},
	{ 'command' => 'openssl s_client -host mail.'.$test_domain.
		       ' -port 465 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
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

	# Test SSL cert info
	{ 'command' => 'get-ssl.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'cn: '.$test_domain, 'o: Virtualmin' ],
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
		      'BEGIN (RSA )?PRIVATE KEY', 'END (RSA )?PRIVATE KEY',
		      'BEGIN CERTIFICATE REQUEST', 'END CERTIFICATE REQUEST' ],
	},

	# Test re-installation of the cert and key
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'cert', $test_domain_cert ],
		      [ 'key', $test_domain_key ] ],
	},

	# Enable SSL, which should use the generated cert
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ $ssl ] ],
	},

	# Try removing the cert, which will fail
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-cert' ] ],
	  'fail' => 1,
	},

	# Test generated SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'C=US', 'ST=California', 'L=Santa Clara',
		      'O=Virtualmin', 'OU=Testing', 'CN='.$test_domain ],
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
	{ 'command' => 'list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host -t A '.$test_domain,
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
	{ 'command' => 'host -t A '.$test_domain,
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
	{ 'command' => 'list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain with SSL on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ $ssl ],
		      [ 'logrotate' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host -t A '.$test_domain,
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
		      [ 'dir' ], [ $web ], [ 'dns' ], [ $ssl ],
	 	      [ 'logrotate' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL shared sub-domain home page' ],
		      @create_args, ],
        },

	# Test DNS and website for the sub-domain
	{ 'command' => 'host -t A '.'sslsub.'.$test_domain,
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

	# Try to create a domain on the same IP with a conflicting name, which should
	# be allowed by SNI
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'desc', 'Test SSL shared clash' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ $ssl ],
		      [ 'logrotate' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL shared clash' ],
		      [ 'skip-warnings' ],
		      @create_args, ],
        },

	# Test a wget which should return the new site thanks to SNI
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test SSL shared clash',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL shared home page',
	},

	# Remove the test subdomain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ] ],
	},


	# Create a domain without SSL on the same IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', "sslsub2.".$test_domain ],
		      [ 'desc', 'Test SSL shared clash' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'logrotate' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL shared sub-domain 2' ],
		      @create_args, ],
        },

	# Enable SSL on that domain, which should work
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain', "sslsub2.".$test_domain ],
		      [ $ssl ] ],
	},

	# Try to create a domain on the same IP with a conflicting name,
	# but without SSL yet
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'desc', 'Test SSL shared clash' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'logrotate' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'content' => 'Test SSL shared clash' ],
		      @create_args, ],
        },

	# Enable SSL on that conflicting domain, which should by allowed by SNI
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'skip-warnings' ],
		      [ $ssl ] ],
	},

	# Test a wget which should return the new site thanks to SNI
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test SSL shared clash',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL shared home page',
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
if (&domain_has_website() ne 'web') {
	# Assume only Apache supports
	$wildcard_tests = [
		{ 'command' => 'echo Skipping SSL wildcard tests for non-Apache webserver' },
		];
	}

# Tests for concurrent domain creation
$parallel_tests = [
	# Create a domain not in parallel
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test serial domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'content' => 'Test serial home page' ],
		      @create_args, ],
        },

	# Create two domains in background processes
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'desc', 'Test parallel domain 1' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ $web ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'content' => 'Test parallel 1 home page' ],
		      @create_args, ],
	  'background' => 1,
        },
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'desc', 'Test parallel domain 2' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ $web ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ], [ 'logrotate' ],
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

	# Remove the domains
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
		      [ 'features', 'dns mail web' ],
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
		      'Allowed features: dns mail web',
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
		      [ 'features', 'dns mail web' ],
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
	  'grep' => [ 'Plan: '.$test_plan,
		      'Server block quota: 7777',
		      'User block quota: 8888',
		      'Maximum sub-servers: 7',
		      'Bandwidth limit: 74.17',
		      'Allowed features: dns mail web',
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
		      [ 'features', 'dns mail web webalizer' ],
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
		      'Allowed features: dns mail web webalizer',
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

$plugin_tests = [
	# Create a domain on the plan
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Test Mailman plugin enable
	&indexof('virtualmin-mailman', @plugins) >= 0 ? (
		# Turn on mailman feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-mailman' ] ]
		},

		# Test mailman URL
		{ 'command' => $wget_command.'http://'.$test_domain.'/mailman/listinfo',
		  'grep' => 'Mailing Lists',
		},

		# Turn off mailman feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-mailman' ] ]
		},
		) :
		( { 'command' => 'echo Mailman plugin not enabled' }
		),

	# Test AWstats plugin
	&indexof('virtualmin-awstats', @plugins) >= 0 ? (
		# Turn on awstats feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-awstats' ] ]
		},

		# Test AWstats web UI
		{ 'command' => $wget_command.'http://'.$test_domain_user.':smeg@'.$test_domain.'/cgi-bin/awstats.pl',
		  'grep' => 'AWStats',
		},

		# Check for Cron job
		{ 'command' => 'crontab -l',
		  'grep' => 'awstats.pl '.$test_domain
		},

		# Turn off AWstats feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-awstats' ] ]
		},
		) :
		( { 'command' => 'echo AWstats plugin not enabled' }
		),

	# Test SVN plugin
	&indexof('virtualmin-svn', @plugins) >= 0 ? (
		# Turn on SVN feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-svn' ] ]
		},

		# Test SVN URL
		{ 'command' => $wget_command.'-S http://'.$test_domain.'/svn',
		  'ignorefail' => 1,
		  'grep' => 'Authorization Required|Forbidden',
		},

		# Check for SVN config files
		{ 'command' => 'cat ~'.$test_domain_user.'/etc/svn-access.conf',
		},
		{ 'command' => 'cat ~'.$test_domain_user.'/etc/svn.*.passwd',
		},

		# Turn off SVN feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-svn' ] ]
		},
		) :
		( { 'command' => 'echo SVN plugin not enabled' }
		),

	# Test DAV plugin
	&indexof('virtualmin-dav', @plugins) >= 0 ? (
		# Turn on SVN feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-dav' ] ]
		},

		# Test DAV URL
		{ 'command' => $wget_command.'-S http://'.$test_domain_user.':smeg@'.$test_domain.'/dav/',
		},

		# Turn off SVN feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-dav' ] ]
		},
		) :
		( { 'command' => 'echo DAV plugin not enabled' }
		),

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Website API tests
$web_tests = [
	# Create a domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test web page' ],
		      @create_args, ],
	},

	# Enable matchall
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'matchall' ] ],
	},

	# Test foo.domain wget
	{ 'command' => $wget_command.'http://foo.'.$test_domain,
	  'grep' => 'Test web page',
	  'sleep' => 5,		# Wait for BIND update
	},

	# Disable matchall
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-matchall' ] ],
	},

	# Test foo.domain wget, which should fail now
	{ 'command' => $wget_command.'http://foo.'.$test_domain,
	  'fail' => 1,
	  'sleep' => 5,		# Wait for BIND update
	},

	# Disable web feature
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ $web ],
		      [ 'logrotate' ] ],
	},

	# Test wget, which should fail
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Test web page',
	  'ignorefail' => 1,
	},

	# Re-enable web feature
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ $web ],
		      [ 'logrotate' ] ],
	},

	# Test wget, which should work again
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	&supports_ssi() ? (
		# Enable use of server-side includes
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'includes', '.shtml' ] ],
		},

		# Create a test file and get it
		{ 'command' => 'echo "<!--#echo var="REQUEST_METHOD" -->" >~'.$test_domain_user.'/public_html/test.shtml',
		},
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.shtml',
		  'grep' => 'GET',
		},

		# Disable use of server-side includes
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'no-includes' ] ],
		},

		# Get the file again, and make sure includes are disabled
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.shtml',
		  'antigrep' => 'GET',
		},
	) : ( ),

	# Enable proxying
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'proxy', 'http://www.google.com/' ] ],
	},

	# Test wget for proxy
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Google',
	},

	# Disable proxying
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-proxy' ] ],
	},

	# Test wget to make sure proxy is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Google',
	},

	# Enable frame forwarding
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'framefwd', 'http://www.google.com/' ] ],
	},

	# Test wget for frame
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => [ 'http://www.google.com/', 'frame' ],
	},

	# Disable frame forwarding
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-framefwd' ] ],
	},

	# Test wget to make sure frame is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Make this the default website
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'default-website' ] ],
	},

	# Test request to IP
	{ 'command' => $wget_command.'http://'.$test_ip_address,
	  'grep' => 'Test web page',
	},

	# Create sub-directory
	{ 'command' => 'mkdir /home/'.$test_domain_user.'/public_html/subby' },
	{ 'command' => 'echo foo >>/home/'.$test_domain_user.'/public_html/subby/index.html' },
	{ 'command' => 'chown -R '.$test_domain_user.' /home/'.$test_domain_user.'/public_html/subby' },

	# Change HTML directory to sub-directory
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'document-dir', 'public_html/subby' ] ],
	},

	# Test wget for sub-directory
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'foo',
	},

	# Change HTML directory back
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'document-dir', 'public_html' ] ],
	},

	# Test wget to make sure sub-directory is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Change listen port to 8888
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'port', 8888 ] ],
	},

	# Test wget on new port
	{ 'command' => $wget_command.'http://'.$test_domain.':8888',
	  'grep' => 'Test web page',
	},

	# Test wget to make sure port 80 now fails
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'ignorefail' => 1,
	  'antigrep' => 'Test web page',
	},

	# Change listen port back to 80
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'port', 80 ] ],
	},

	# Test wget to make sure port 80 works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Change access and error logs to a new location
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'access-log' => '/var/log/'.$test_domain.'_access_log' ],
		      [ 'error-log' => '/var/log/'.$test_domain.'_error_log' ] ],
	},

	# Verify the move
	{ 'command' => 'ls -l /var/log/'.$test_domain.'_access_log' },
	{ 'command' => 'ls -l /var/log/'.$test_domain.'_error_log' },

	# Make another request
	{ 'command' => $wget_command.'http://'.$test_domain.'/smeg',
	  'ignorefail' => 1,
	},

	# Verify that it was logged
	{ 'command' => 'grep smeg /var/log/'.$test_domain.'_access_log' },

	# Create a test CGI script
	{ 'command' => '(echo "#!/bin/sh" ; echo "echo Content-type: text/plain" ; echo echo ; echo uptime ; echo env) >~'.$test_domain_user.'/cgi-bin/test.cgi',
	},
	{ 'command' => 'chown '.$test_domain_user.': ~'.$test_domain_user.'/cgi-bin/test.cgi',
	},
	{ 'command' => 'chmod 755 ~'.$test_domain_user.'/cgi-bin/test.cgi',
	},

	# Run the test CGI script
	{ 'command' => $wget_command.'http://'.$test_domain.'/cgi-bin/test.cgi',
	  'grep' => 'load average',
	},

	# Test with CGI scripts off
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'disable-cgi' ] ],
	},

	{ 'command' => $wget_command.
		       'http://'.$test_domain.'/cgi-bin/test.cgi',
	  'fail' => 1,
	},

	# Test in fcgiwrap mode
	&supports_fcgiwrap() ? (
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'enable-fcgiwrap' ] ],
		},

		{ 'command' => $wget_command.
			       'http://'.$test_domain.'/cgi-bin/test.cgi',
		  'grep' => 'load average',
		},
	) : ( ),

	# Test in suexec mode
	&supports_fcgiwrap() ? (
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'enable-suexec' ] ],
		},

		{ 'command' => $wget_command.
			       'http://'.$test_domain.'/cgi-bin/test.cgi',
		  'grep' => 'load average',
		},
	) : ( ),

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$ip6_tests = [
	# Create a domain with an IPv6 address
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test IPv6 domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ],
		      [ 'allocate-ip6' ],
		      [ 'content' => 'Test IPv6 home page' ],
		      @create_args, ],
	},

	# Create an alias for it
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test alias domain' ],
		      [ 'alias', $test_domain ],
		      [ 'dir' ], [ $web ], [ 'dns' ],
		      @create_args, ],
	},

	# Delay needed for v6 address to become routable
	{ 'command' => 'sleep 10' },

	# Test DNS lookup for v6 entry
	{ 'command' => 'host -t AAAA '.$test_domain,
	  'grep' => 'IPv6 address',
	},
	{ 'command' => 'host -t AAAA '.$test_target_domain,
	  'grep' => 'IPv6 address',
	},

	# Test HTTP get to v6 address
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},
	{ 'command' => $wget_command.' --inet6 http://'.$test_target_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Test removal of v6 address
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-ip6' ] ],
	},

	# Make sure DNS entries are gone
	{ 'command' => 'host -t AAAA '.$test_domain,
	  'antigrep' => 'IPv6 address',
	},

	# Make sure HTTP get to v6 address no longer works
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'fail' => 1,
	},
	{ 'command' => $wget_command.' --inet6 http://'.$test_target_domain,
	  'fail' => 1,
	},

	# But v4 address should still work
	{ 'command' => $wget_command.' --inet4 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Re-allocate an address
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'allocate-ip6' ] ],
	},

	# Delay needed for v6 address to become routable
	{ 'command' => 'sleep 10' },

	# Re-check HTTP get
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Create a sub-domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'desc', 'Test IPv6 sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'logrotate' ],
		      [ 'default-ip6' ],
		      [ 'content' => 'Test IPv6 sub-domain home page' ],
		      @create_args, ],
	},

	# Test DNS lookup for v6 entry
	{ 'command' => 'host -t AAAA '.$test_subdomain,
	  'grep' => [ 'IPv6 address', &get_default_ip6() ],
	},

	# Test HTTP get to v6 address
	{ 'command' => $wget_command.' --inet6 http://'.$test_subdomain,
	  'grep' => 'Test IPv6 sub-domain home page',
	},

	# Validate the domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_subdomain ],
		      [ 'all-features' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];
if (!&supports_ip6()) {
	$ip6_tests = [ { 'command' => 'echo IPv6 is not supported' } ];
	}

# Tests for renaming a virtual server via the web UI
$webrename_tests = [
	# Create a domain that will get renamed
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test rename domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      [ 'logrotate' ],
		      $virtualmin_pro ? ( [ 'status' ] ) : ( ),
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( [ 'virtualmin-awstats' ] ) : ( ),
		      [ 'content' => 'Test rename page' ],
		      @create_args, ],
	},

	# Create a mailbox
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create an alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Get the domain ID
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'id-only' ] ],
	  'save' => 'DOMID',
	},

	# Validate the domain before
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Call the rename CGI
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/virtual-server/rename.cgi\\?dom=\$DOMID\\&new=$test_rename_domain\\&user_mode=1\\&home_mode=1\\&prefix_mode=1",
	   'grep' => 'Saving server details',
	},

	# Validate the domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'all-features' ] ],
	},

	# Make sure DNS works
	{ 'command' => 'host -t A '.$test_rename_domain,
	  'grep' => &get_default_ip(),
	},

	# Make sure website works
	{ 'command' => $wget_command.'http://'.$test_rename_domain,
	  'grep' => 'Test rename page',
	},

	# Make sure MySQL login works
	{ 'command' => 'mysql -u '.$test_rename_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Validate renamed mailbox
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Unix username: '.$test_rename_full_user ],
	},
	
	# Validate renamed alias
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_rename_domain ],
	},

	# Check that log file was renamed
	-d "/var/log/virtualmin" ? (
	{ 'command' => 'ls /var/log/virtualmin/'.$test_rename_domain.'_access_log' },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_rename_domain.'_error_log' },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_domain.'_access_log',
	  'fail' => 1 },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_domain.'_error_log',
	  'fail' => 1 },
	) : ( ),

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_rename_domain ] ],
	  'ignorefail' => 1,
	  'cleanup' => 1
        },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'ignorefail' => 1,
	  'cleanup' => 1
        },
	];
if (!$webmin_user || !$webmin_pass) {
	$webrename_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}

# Tests for renaming a virtual server via the API
$rename_tests = [
	# Create a domain that will get renamed
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test rename domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ $ssl ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      [ 'logrotate' ], [ 'allocate-ip' ],
		      $virtualmin_pro ? ( [ 'status' ] ) : ( ),
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( [ 'virtualmin-awstats' ] ) : ( ),
		      [ 'content' => 'Test rename page' ],
		      @create_args, ],
	},

	# Install a dummy CA cert
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'ca', $module_root_directory.'/lets-encrypt-*.pem.txt' ] ],
	},

	# Get the IP address
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'ip-only' ],
		      [ 'domain', $test_domain ] ],
	  'save' => 'PRIVATE_IP',
	},

	# Force enable private SSL cert for Webmin, Usermin, etc
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-domain' ],
		      [ 'service', 'webmin' ],
		      [ 'service', 'usermin' ],
		      [ 'service', 'dovecot' ],
		      [ 'service', 'postfix' ] ],
	},

	# Create a mailbox
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create an alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ $ssl ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ],
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],
	},

	# Validate the domains before
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_subdomain ],
		      [ 'all-features' ] ],
	},

	# Rename the domain
	{ 'command' => 'rename-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'new-domain' => $test_rename_domain ],
		      [ 'auto-user' ],
		      [ 'auto-home' ],
		      [ 'auto-prefix' ] ],
	},

	# Validate the domains after
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'domain' => $test_subdomain ],
		      [ 'all-features' ] ],
	},

	# Make sure DNS works
	{ 'command' => 'host -t A '.$test_rename_domain,
	  'grep' => '$PRIVATE_IP',
	},
	{ 'command' => 'host -t A www.'.$test_rename_domain,
	  'grep' => '$PRIVATE_IP',
	},

	# Make sure website works
	{ 'command' => $wget_command.'http://'.$test_rename_domain,
	  'grep' => 'Test rename page',
	},

	# Make sure MySQL login works
	{ 'command' => 'mysql -u '.$test_rename_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Validate renamed mailbox
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Unix username: '.$test_rename_full_user ],
	},
	
	# Validate renamed alias
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_rename_domain ],
	},

	# Check that log file was renamed
	-d "/var/log/virtualmin" ? (
	{ 'command' => 'ls /var/log/virtualmin/'.$test_rename_domain.'_access_log' },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_rename_domain.'_error_log' },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_domain.'_access_log',
	  'fail' => 1 },
	{ 'command' => 'ls /var/log/virtualmin/'.$test_domain.'_error_log',
	  'fail' => 1 },
	) : ( ),

	# Check that service certs still show up
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_rename_domain ] ],
	  'grep' => [ 'SSL cert used by: dovecot \\($PRIVATE_IP\\)',
		      'SSL cert used by: postfix \\($PRIVATE_IP\\)',
		      'SSL cert used by: webmin \\('.$test_rename_domain.'\\)',
		      'SSL cert used by: usermin \\('.$test_rename_domain.'\\)',
		    ],
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_rename_domain ] ],
	  'ignorefail' => 1,
	  'cleanup' => 1
        },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'ignorefail' => 1,
	  'cleanup' => 1
        },
	];
if (!$webmin_user || !$webmin_pass) {
	$webrename_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}



# Tests for web, mail and FTP bandwidth accounting.
# Uses a different domain to prevent re-reading of old mail logs.
$test_bw_domain = 'bw'.time().$test_domain;
$test_bw_domain_user = 'bw'.time().$test_domain_user;
$bw_tests = [
	# Create a domain for bandwidth logging
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'user', $test_bw_domain_user ],
		      [ 'prefix', $prefix ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test bandwidth page' ],
		      @create_args, ],
	},

	# Run bw.pl once to skip to the end of logs
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Create a 1M file in the domain's directory
	{ 'command' => 'dd if=/dev/zero of=/home/'.$test_bw_domain_user.'/public_html/huge bs=1024 count=1024 && chown '.$test_bw_domain_user.': /home/'.$test_bw_domain_user.'/public_html/huge',
	},

	# Fetch the file 5 times with wget
	{ 'command' => join(" ; ", map { $wget_command.'http://'.$test_bw_domain.'/huge >/dev/null' } (0..4)),
	},

	# Fetch 1 time with FTP
	{ 'command' => $wget_command.
		       'ftp://'.$test_bw_domain_user.':smeg@localhost/public_html/huge >/dev/null',
	},

	# Create a 1M test file
	{ 'command' => '(cat '.$ok_email_file.' ; head -c250000 /dev/zero | od -c -v) >/tmp/random.txt',
	},

	# Send email to the domain's user
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_bw_domain_user.'@'.$test_bw_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Check IMAP for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check POP3 for admin mailbox
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Run bw.pl on this domain
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Check separate web, FTP and mail usage
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'grep' => [ 'web:5[0-9]{6}',
		      'ftp:1[0-9]{6}',
		      'mail:1[0-9]{6}', ],
	},

	# Get usage from list-domains
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Bandwidth usage: 7(\\.[0-9]+)?\s+Mi?B',
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_bw_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'logrotate' ],
		      @create_args, ],
	},

	# Create a 1M file in the sub-domain's directory
	{ 'command' => 'dd if=/dev/zero of=/home/'.$test_bw_domain_user.'/domains/'.$test_subdomain.'/public_html/huge bs=1024 count=1024 && chown '.$test_bw_domain_user.': /home/'.$test_bw_domain_user.'/domains/'.$test_subdomain.'/public_html/huge',
	},

	# Fetch the file 5 times with wget
	{ 'command' => join(" ; ", map { $wget_command.'http://'.$test_subdomain.'/huge >/dev/null' } (0..4)),
	},

	# Run bw.pl on the parent domain
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	  'sleep' => 5,
	},

	# Check web usage in sub-domain
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'web:5[0-9]{6}' ],
	},

	# Get usage from list-domains again
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Bandwidth usage: 12(\\.[0-9]+)?\s+Mi?B',
	},

	# Check separate usage in parent domain
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'include-subservers' ] ],
	  'grep' => [ 'web:10[0-9]{6}',
		      'ftp:1[0-9]{6}',
		      'mail:1[0-9]{6}', ],
	},

	# Create a mailbox with FTP access
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Send a 1M email to it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_bw_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Check IMAP for mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check POP3 for mailbox
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Create a 1M file in the user's directory
	{ 'command' => 'dd if=/dev/zero of=/home/'.$test_bw_domain_user.'/homes/'.$test_user.'/huge bs=1024 count=1024 && chown '.$test_full_user.': /home/'.$test_bw_domain_user.'/homes/'.$test_user.'/huge',
	},

	# Fetch 1 time with FTP
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/huge >/dev/null',
	},

	# Re-run bw.pl to pick up that email
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	  'sleep' => 5,
	},

	# Check that the email was counted
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'grep' => [ 'mail:2[0-9]{6}',
		      'ftp:2[0-9]{6}' ],
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'cleanup' => 1
        },
	];

$datestr = &make_date(time(), 1);
$lastlogin_tests = [
	# Create domain for logins
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'user', $test_bw_domain_user ],
		      [ 'prefix', $prefix ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test bandwidth page' ],
		      @create_args, ],
	},

	# Create a 1M test file
	{ 'command' => '(cat '.$ok_email_file.' ; head -c250000 /dev/zero | od -c -v) >/tmp/random.txt',
	},

	# Send email with SMTP authentication
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_bw_domain_user.'@'.$test_bw_domain ],
		      [ 'user', $test_bw_domain_user ],
                      [ 'pass', 'smeg' ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Check IMAP for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check POP3 for admin mailbox
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Send email to the domain user
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_bw_domain_user.'@'.$test_bw_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Do a status collection run
	{ 'command' => $module_config_directory."/collectinfo.pl",
	  'antigrep' => 'Already running',
	  'sleep' => 5,
	  'tries' => 5,
	},

	# Check for various recent logins
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_bw_domain ],
		      [ 'include-owner' ],
		      [ 'multiline' ] ],
	  'grep' => 'Last logins: imap '.$datestr.' \d+:\d+, '.
		    'pop3 '.$datestr.' \d+:\d+, '.
		    'smtp '.$datestr.' \d+:\d+',
	},

	# Check that the most recent login for the domain was collected
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain' => $test_bw_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Last login: '.$datestr.' \d+:\d+',
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'cleanup' => 1
        },
	];

$blocks_per_mb = int(1024*1024 / &quota_bsize("home"));
$quota_tests = [
	# Create a domain with a 10M quota
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test quota domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'quota', 10*$blocks_per_mb ],
		      [ 'uquota', 10*$blocks_per_mb ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test quota page' ],
		      (grep { $_->[0] ne 'limits-from-plan' } @create_args), ],
	},

	# Make sure 20M file creation fails
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=20480'",
	  'fail' => 1,
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Give quota system a few seconds to detect the deletion
	{ 'command' => 'sleep 10' },

	# Make sure 5M file creation works
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=5120'",
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Up quota to 30M
	{ 'command' => 'modify-domain.pl',
 	  'args' => [ [ 'domain', $test_domain ],
		      [ 'quota', 30*$blocks_per_mb ],
		      [ 'uquota', 30*$blocks_per_mb ],
		    ],
	},

	# Make sure 20M file creation now works
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=20480'",
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Create a mailbox with 5M quota
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 5*$blocks_per_mb ],
		      [ 'mail-quota', 5*$blocks_per_mb ] ],
	},

	# Make sure 20M file creation fails
	{ 'command' => &command_as_user($test_full_user, 0, "dd if=/dev/zero of=/home/$test_domain_user/homes/$test_user/junk bs=1024 count=20480"),
	  'fail' => 1,
	},
	{ 'command' => "rm -f /home/$test_domain_user/homes/$test_user/junk" },

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	  'ignorefail' => 1,
	},

	# Create a large test email
	{ 'command' => '(cat '.$ok_email_file.' ; head -c2000000 /dev/zero | od -c -v) >/tmp/random.txt',
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send email to the new mailbox, which won't get delivered
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'nobody@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Wait for delivery to fail due to lack of quota
	{ 'command' => 'while [ "`tail -10 /var/log/mail*log | grep -i '.
		       'can.t.create`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	},

	# Remove the user
	{ 'command' => 'delete-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ] ],
	},

	# Enable some more features for backing up
	{ 'command' => 'enable-feature.pl',
          'args' => [ [ 'domain', $test_domain ],
		      [ $web ], [ 'dns' ], [ 'mail' ],
                      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
                      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
                      [ 'spam' ], [ 'virus' ], [ 'webmin' ] ],
	},

	# Fill up quota for the domain again
	{ 'command' => &command_as_user($test_full_user, 0, "dd if=/dev/zero of=/home/$test_domain_user/homes/$test_user/junk bs=1024 count=20480"),
	  'fail' => 1,
	},

	# Test a backup to a single file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Backup to a temp dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Backup to a temp dir (old format)
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'separate' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Backup to a file under the home dir, as the user - which will fail
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'asowner' ],
		      [ 'dest', $test_domain_home.'/backup.tar.gz' ] ],
	  'fail' => 1,
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

# Test deletion of domains when entries in virtual file overlap
$overlap_tests = [
	# Create first domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain one' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create user A in first domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', 'a'.$test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user A' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create alias A in first domain
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', 'a'.$test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Create second domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'desc', 'Test domain two' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create user A in second domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', 'a'.$test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user A' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create alias A in second domain
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'from', 'a'.$test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Create user B in first domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', 'b'.$test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user B' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create alias B in first domain
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', 'b'.$test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Create user B in second domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', 'b'.$test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user B' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create alias B in second domain
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'from', 'b'.$test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Delete first domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Validate second domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_subdomain ],
		      [ 'all-features' ] ],
	},

	# Make sure user A in second domain still has email
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', 'a'.$test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Email address: a'.$test_user.'@'.$test_subdomain ],
	},

	# Make sure alias A in second domain still exists
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^a'.$test_alias.'@'.$test_subdomain ],
	},

	# Make sure user B in second domain still has email
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', 'b'.$test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Email address: b'.$test_user.'@'.$test_subdomain ],
	},

	# Make sure alias B in second domain still exists
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^b'.$test_alias.'@'.$test_subdomain ],
	},

	# Delete second domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ] ],
	  'cleanup' => 1,
	},
	];

$redirect_tests = [
	# Create a domain for the redirects
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test redirect domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ $ssl ],
		      [ 'dns' ], [ 'mail' ], [ 'logrotate' ],
		      [ 'content' => 'Non-redirected web page' ],
		      @create_args, ],
	},

	# Create a redirect for /google
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google' ],
		      [ 'redirect', 'http://www.google.com' ] ],
	},

	# Make sure the redirect appears
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/google', 'Destination: http://www.google.com',
		      'Type: Redirect', 'Match sub-paths: No' ],
	},

	# Test wget to redirect to google
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => 'Feeling Lucky',
	},

	# Test wget to a sub-url, which should also work as Redirect includes
	# sub-paths automatically
	{ 'command' => $wget_command.'http://'.$test_domain.
		       '/google/imghp',
	  'grep' => 'Google Images',
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/google' ] ],
	},

	# Make sure the redirect is gone
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => [ '^/google' ],
	},

	# Test wget, which should fail
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'fail' => 1,
	},

	# Create a redirect for /google again, but with sub-path matching
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google' ],
		      [ 'redirect', 'http://www.google.com' ],
		      [ 'regexp' ] ],
	},

	# Make sure the redirect appears correctly
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/google', 'Destination: http://www.google.com',
		      'Type: Redirect', 'Match sub-paths: Yes' ],
	},

	# Test wget to redirect to google
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => 'Feeling Lucky',
	},

	# Test wget to a sub-url, should go to the same place
	{ 'command' => $wget_command.'http://'.$test_domain.
		       '/google/imghp',
	  'antigrep' => 'Google Images',
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/google' ] ],
	},

	# Create the directory and a file in it
	{ 'command' => 'mkdir -p '.$test_domain_home.'/public_html/blah' },
	{ 'command' => 'echo foo >'.$test_domain_home.'/public_html/blah/bar.txt' },

	# Create a directory alias for /tmp
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/somedir' ],
		      [ 'alias', $test_domain_home.'/public_html/blah' ] ],
	},

	# Make sure the alias appears
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/somedir',
		      'Destination: '.$test_domain_home.'/public_html/blah',
		      'Type: Alias', 'Match sub-paths: No' ],
	},

	# Validate that the file can be fetched
	{ 'command' => $wget_command.'http://'.$test_domain.'/somedir/bar.txt',
	  'grep' => 'foo',
	},

	# Delete the alias
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/somedir' ] ],
	},

	# Validate that the file can no longer be fetched
	{ 'command' => $wget_command.'http://'.$test_domain.'/somedir/bar.txt',
	  'fail' => 1,
	},

	# Create a redirect from www.domain to just the domain
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ],
		      [ 'redirect', 'http://'.$test_domain ] ],
	},

	# Make sure the redirect appears
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/$', 'Destination: http://'.$test_domain,
		      'Limit to hostname: www.'.$test_domain,
		      'Regexp hostname: No',
		      'Type: Redirect', 'Match sub-paths: No' ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'grep' => 'http://'.$test_domain,
	},

	# Check that it works for SSL
	{ 'command' => $wget_command.'https://www.'.$test_domain,
	  'grep' => 'http://'.$test_domain,
	},

	# Check that there is no redirect for another domain
	{ 'command' => $wget_command.'http://mail.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ] ],
	},

	# Check that it no longer works
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Create a redirect using a regexp
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/' ],
		      [ 'host-regexp', '"(ftp|www).'.$test_domain.'"' ],
		      [ 'redirect', 'http://'.$test_domain ] ],
	},

	# Make sure the redirect appears
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/$', 'Destination: http://'.$test_domain,
		      'Limit to hostname: \(ftp\|www\).'.$test_domain,
		      'Regexp hostname: Yes',
		      'Type: Redirect', 'Match sub-paths: No' ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'grep' => 'http://'.$test_domain,
	},

	# Check that there is no redirect for another domain
	{ 'command' => $wget_command.'http://mail.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/' ],
		      [ 'host', '"(ftp|www).'.$test_domain.'"' ] ],
	},

	# Create an HTTP-only redirect
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ],
		      [ 'http' ],
		      [ 'redirect', 'http://'.$test_domain ] ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'grep' => 'http://'.$test_domain,
	},

	# Check that it doesn't work for SSL
	{ 'command' => $wget_command.'https://www.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ] ],
	},

	# Check that it no longer works
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Create an HTTPS-only redirect
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ],
		      [ 'https' ],
		      [ 'redirect', 'http://'.$test_domain ] ],
	},

	# Check that it works
	{ 'command' => $wget_command.'https://www.'.$test_domain,
	  'grep' => 'http://'.$test_domain,
	},

	# Check that it doesn't work for SSL
	{ 'command' => $wget_command.'http://www.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Delete the redirect
	{ 'command' => 'delete-redirect.pl',
          'args' => [ [ 'domain', $test_domain ],
                      [ 'path', '/' ],
		      [ 'host', 'www.'.$test_domain ] ],
	},

	# Check that it no longer works
	{ 'command' => $wget_command.'https://www.'.$test_domain,
	  'antigrep' => 'http://'.$test_domain,
	},

	# Create a redirect that excludes well-known
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/' ],
		      [ 'redirect', 'http://www.google.com' ],
		      [ 'fix-wellknown' ] ],
	},

	# Test wget to redirect to google
	{ 'command' => $wget_command.'http://'.$test_domain.'/',
	  'grep' => 'Feeling Lucky',
	},

	# Test wget doesn't redirect .well-known
	{ 'command' => $wget_command.'http://'.$test_domain.'/.well-known/',
	  'antigrep' => 'Feeling Lucky',
	  'fail' => 1,
	},

	# Make sure the redirect appears
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', '' ],
		      [ 'multiline' ],
		      [ 'fix-wellknown' ] ],
	  'grep' => [ '^/$', ],
	},
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', '' ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.quotemeta('^/(?!.well-known)').'$', ],
	},

	# Enable webmail and admin redirects
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webmail' ] ],
	},

	# Make sure they shows up
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', 'webmail.'.$test_domain ],
		      [ 'fix-wellknown' ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/$',
		      'Limit to hostname: webmail.'.$test_domain,
		      'Destination: '.$usermin_proto.'://'.$test_domain.':'.$usermin_port ],
	},
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', 'admin.'.$test_domain ],
		      [ 'fix-wellknown' ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/$',
		      'Limit to hostname: admin.'.$test_domain,
		      'Destination: '.$webmin_proto.'://'.$test_domain.':'.$webmin_port ],
	},

	# Test HTTP and HTTPS get to webmail alias
	{ 'command' => $wget_command.'http://webmail.'.$test_domain,
	  'grep' => 'Usermin',
	},
	{ 'command' => $wget_command.'https://webmail.'.$test_domain,
	  'grep' => 'Usermin',
	},

	# Test HTTP and HTTPS get to admin alias
	{ 'command' => $wget_command.'http://admin.'.$test_domain,
	  'grep' => 'Webmin',
	},
	{ 'command' => $wget_command.'https://admin.'.$test_domain,
	  'grep' => 'Webmin',
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$admin_tests = [
	# Create a domain for the admins
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test admins domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'webmin' ], [ 'mail' ], [ 'logrotate' ],
		      [ 'content' => 'Test web page' ],
		      @create_args, ],
	},

	# Create an extra admin
	{ 'command' => 'create-admin.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'name', $test_admin ],
		      [ 'desc', 'Test extra admin' ],
		      [ 'email', 'admin@'.$test_domain ],
		      [ 'pass', 'smeg' ],
		      [ 'edit', 'users' ],
		      [ 'edit', 'aliases' ],
		      [ 'edit', 'dbs' ],
		      [ 'allowed-domain', $test_domain ] ],
	},

	# Make sure he was created
	{ 'command' => 'list-admins.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_admin,
		      'Description: Test extra admin',
		      'Password: smeg',
		      'Email: admin@'.$test_domain,
		      'Create servers: No',
		      'Rename servers: No',
		      'Allowed virtual servers: '.$test_domain,
		      'Edit capabilities: users aliases dbs', ],
	},

	# Check his login to Virtualmin
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/",
	  'grep' => [ 'Virtualmin Virtual Servers|Virtual Email', $test_domain ],
	},

	# Check he can list aliases
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/list_aliases.cgi\\?dom=".
		       "`virtualmin list-domains.pl --domain $test_domain --id-only`",
	  'grep' => [ $test_domain, 'Mail Aliases' ],
	},

	# Check he can list users
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/list_users.cgi\\?dom=".
		       "`virtualmin list-domains.pl --domain $test_domain --id-only`",
	  'grep' => [ $test_domain, 'Edit Users' ],
	},

	# Take away access to aliases and users
	{ 'command' => 'modify-admin.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'name', $test_admin ],
		      [ 'cannot-edit', 'aliases' ],
		      [ 'cannot-edit', 'users' ] ],
	},

	# Check he can no longer list aliases
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/list_aliases.cgi\\?dom=".
		       "`virtualmin list-domains.pl --domain $test_domain --id-only`",
	  'antigrep' => 'Mail Aliases',
	  'grep' => 'You are not allowed to edit aliases in this domain',
	},

	# Check he can no longer list users
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/list_users.cgi\\?dom=".
		       "`virtualmin list-domains.pl --domain $test_domain --id-only`",
	  'antigrep' => 'Edit Users',
	  'grep' => 'You are not allowed to edit users in this domain',
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'logrotate' ],
		      @create_args, ],
	},

	# Grant the admin access to it
	{ 'command' => 'modify-admin.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'name', $test_admin ],
		      [ 'add-domain', $test_subdomain ] ],
	},

	# Make sure he can see it too
	{ 'command' => $admin_webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/",
	  'grep' => [ 'Virtualmin Virtual Servers', $test_domain,
		      $test_subdomain ],
	},

	# Delete the admin
	{ 'command' => 'delete-admin.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'name', $test_admin ] ],
	},

	# Make sure he is gone
	{ 'command' => 'list-admins.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'antigrep' => '^'.$test_admin,
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$configbackup_tests = [
	# Create a test plan
	{ 'command' => 'create-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 7777 ],
		      [ 'admin-quota', 8888 ],
		      [ 'max-doms', 7 ],
		      [ 'max-bw', 77777777 ],
		      [ 'features', 'dns mail web' ],
		      [ 'capabilities', 'users aliases scripts' ],
		      [ 'nodbname' ] ],
	},

	# Backup all config settings locally
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'all-virtualmin' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete the plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	},

	# Restore plan from local file
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'virtualmin', 'templates' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Make sure it worked
	{ 'command' => 'list-plans.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 7777',
		      'Administrator block quota: 8888',
		      'Maximum doms: 7',
		      'Maximum bw: 77777777',
		      'Allowed features: dns mail web',
		      'Edit capabilities: users aliases scripts',
		      'Can choose database names: No' ],
	},

	# Backup all config settings to a local dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'all-virtualmin' ],
		      [ 'separate' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Restore plan from local dir
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'virtualmin', 'templates' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Create a domain for the backup target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Backup all config settings via SSH
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'all-virtualmin' ],
		      [ 'dest', "$ssh_backup_prefix/virtualmin.tar.gz" ] ],
	},

	# Restore plans via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'virtualmin', 'templates' ],
		      [ 'source', "$ssh_backup_prefix/virtualmin.tar.gz" ] ],
	},

	# Delete the backups file
	{ 'command' => "rm -rf /home/$test_target_domain_user/virtualmin.tar.gz" },

	# Backup all config settings via SSH to a dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'all-virtualmin' ],
		      [ 'separate' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore plans via SSH from a dir
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'virtualmin', 'templates' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},

	# Delete the plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	  'cleanup' => 1 },
	];

$enc_configbackup_tests = &convert_to_encrypted($configbackup_tests);

$clone_tests = [
	# Create a parent domain to be cloned
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'logrotate' ], [ 'webmin' ], [ 'spam' ],
		      [ 'virus' ], [ $ssl ],
		      [ 'allocate-ip' ], [ 'allocate-ip6' ],
		      [ 'content' => 'Test source page' ],
		      @create_args, ],
        },

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add some aliases
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},
	{ 'command' => 'create-simple-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias.'2' ],
		      [ 'autoreply', 'Test autoreply' ] ],
	},

	# Add a mailbox
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'spod' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'extra', 'bob@'.$test_domain ],
		      [ 'extra', 'fred@'.$test_domain ],
		      [ 'mysql', $test_domain_db ],
		      [ 'mysql', $test_domain_db.'_extra' ],
		      [ 'mail-quota', 100*1024 ] ],
	},
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'add-forward', 'jack@'.$test_domain ],
		      [ 'add-forward', 'jill@'.$test_domain ],
		      [ 'autoreply', 'User autoreply' ] ],
	},

	$supports_cgi ? (
		# Switch PHP mode to CGI
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'cgi' ] ],
		},
		) : ( ),

	# Install phpMyAdmin
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'phpmyadmin' ],
		      [ 'path', '/phpmyadmin' ],
		      [ 'atleast-version', '4.9.7' ] ],
	  'antigrep' => 'partially complete',
	},

	# Create a dummy .htaccess file with a path
	{ 'command' => 'echo AuthUserFile '.$test_domain_home.'/users.txt >'.
		       $test_domain_home.'/.htaccess',
	},
	{ 'command' => 'chown '.$test_domain_user.': '.
		       $test_domain_home.'/.htaccess',
	},

	# Add a DNS record
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing A 1.2.3.4' ] ],
	},

	# Validate before cloning
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Clone it
	{ 'command' => 'clone-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'newdomain', $test_clone_domain ],
		      [ 'newuser', $test_clone_domain_user ],
		      [ 'newpass', 'foo' ] ],
	},

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_clone_domain",
	},

	# Check the new .htaccess file has been fixed
	{ 'command' => 'cat ~'.$test_clone_domain_user.'/.htaccess',
	  'antigrep' => [ $test_domain_home.'/' ],
	},

	# Validate new ownership
	{ 'command' => 'find ~'.$test_clone_domain_user.
		       ' -type f -user '.$test_domain_user,
	  'antigrep' => [ $test_domain_user ],
	},

	# Force change web content
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'content' => 'Test clone page' ] ],
	},

	# Validate everything
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_clone_domain ],
		      [ 'all-features' ] ],
	},

	# Check mail aliases
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_clone_domain,
		      'To: nobody@virtualmin.com' ],
	},
	{ 'command' => 'list-simple-aliases.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Autoreply message: Test autoreply' ],
	},

	# Check mailboxes
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_clone_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ],
		      [ 'simple-aliases' ] ],
	  'grep' => [ 'Password: spod',
		      'Home quota: 100',
		      'Databases: '.$test_clone_domain_db.' \\(mysql\\), '.
				    $test_clone_domain_db.'_extra \\(mysql\\)',
		      'Email address: '.$test_user.'@'.$test_clone_domain,
		      'Extra addresses: bob@'.$test_clone_domain.
		      		     ' fred@'.$test_clone_domain,
		      'Forward: jack@'.$test_clone_domain,
		      'Forward: jill@'.$test_clone_domain,
		      'Autoreply message: User autoreply',
	            ],
	},

	# Check script list
	{ 'command' => 'list-scripts.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Type: phpmyadmin',
		      'Directory: /home/'.$test_clone_domain_user.
			'/public_html/phpmyadmin',
		      'URL: http(s?)://'.$test_clone_domain.'/phpmyadmin',
		    ],
	},

	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_clone_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTPS get
	{ 'command' => $wget_command.'https://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTP get to v6 address
	{ 'command' => $wget_command.' --inet6 http://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTP get of old page
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test source page',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_clone_domain_user.':foo@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to admin mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_clone_domain_user.'@'.$test_clone_domain ]],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_clone_domain_user.' '.
		       '--password foo '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_clone_domain_user.' -pfoo '.$test_clone_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_clone_domain_user.' -pfoo '.$test_clone_domain_db.'_extra -e "select version()"',
	},

	# Check MySQL login to old DB as old user
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	# Check MySQL login by mailbox user
	{ 'command' => 'mysql -u '.$test_full_clone_user_mysql.' -pspod '.$test_clone_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_full_clone_user_mysql.' -pspod '.$test_clone_domain_db.'_extra -e "select version()"',
	},

	# Check PHP running via CGI
	{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
		       $test_clone_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_clone_domain.'/test.php',
	  'grep' => 'uid=[0-9]+\\('.$test_clone_domain_user.'\\)',
	},

	# Check for basic DNS records
	{ 'command' => 'host -t A www.'.$test_clone_domain,
	},
	{ 'command' => 'host -t A mail.'.$test_clone_domain,
	},

	# Check the extra DNS record
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_clone_domain ] ],
	  'grep' => [ 'testing' ],
	},
	{ 'command' => 'host -t A testing.'.$test_clone_domain,
	  'grep' => '1.2.3.4',
	},

	# Cleanup the domain being cloned
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Cleanup the clone
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_clone_domain ] ],
	  'cleanup' => 1 },
	];

$clonesub_tests = [
	# Create a parent domain to hold the clone
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server to clone
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'db', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      [ 'spam' ], [ 'virus' ], [ $ssl ],
		      [ 'allocate-ip' ], [ 'allocate-ip6' ],
                      [ 'content' => 'Test source page' ],
		      @create_args, ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'type', 'mysql' ],
		      [ 'name', 'example2_extra' ] ],
	},

	# Check MySQL login to DBs before cloning
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg example2 -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg example2_extra -e "select version()"',
	},

	# Add some aliases
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},
	{ 'command' => 'create-simple-alias.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'from', $test_alias.'2' ],
		      [ 'autoreply', 'Test autoreply' ] ],
	},

	# Add a mailbox
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'spod' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'extra', 'bob@'.$test_subdomain ],
		      [ 'extra', 'fred@'.$test_subdomain ],
		      [ 'mysql', 'example2' ],
		      [ 'mysql', 'example2_extra' ],
		      [ 'mail-quota', 100*1024 ] ],
	},
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', $test_user ],
		      [ 'add-forward', 'jack@'.$test_subdomain ],
		      [ 'add-forward', 'jill@'.$test_subdomain ],
		      [ 'autoreply', 'User autoreply' ] ],
	},

	$supports_cgi ? (
		# Switch PHP mode to CGI
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_subdomain ],
			      [ 'mode', 'cgi' ] ],
		},
		) : ( ),

	# Clone it
	{ 'command' => 'clone-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'newdomain', $test_clone_domain ] ],
	},

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_clone_domain",
	},

	# Force change web content
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'content' => 'Test clone page' ] ],
	},

	# Validate everything
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_subdomain ],
		      [ 'domain' => $test_clone_domain ],
		      [ 'all-features' ] ],
	},

	# Check mail aliases
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_clone_domain,
		      'To: nobody@virtualmin.com' ],
	},
	{ 'command' => 'list-simple-aliases.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Autoreply message: Test autoreply' ],
	},

	# Check mailboxes
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_clone_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ],
		      [ 'simple-aliases' ] ],
	  'grep' => [ 'Password: spod',
		      'Home quota: 100',
		      'Databases: exampleclone \\(mysql\\), '.
				 'exampleclone_extra \\(mysql\\)',
		      'Email address: '.$test_user.'@'.$test_clone_domain,
		      'Extra addresses: bob@'.$test_clone_domain.
		      		     ' fred@'.$test_clone_domain,
		      'Forward: jack@'.$test_clone_domain,
		      'Forward: jill@'.$test_clone_domain,
		      'Autoreply message: User autoreply',
	            ],
	},

	# Test DNS lookup
	{ 'command' => 'host -t A '.$test_clone_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTPS get
	{ 'command' => $wget_command.'https://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTP get to v6 address
	{ 'command' => $wget_command.' --inet6 http://'.$test_clone_domain,
	  'grep' => 'Test clone page',
	},

	# Test HTTP get of old page
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test source page',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg exampleclone -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg exampleclone_extra -e "select version()"',
	},

	# Check MySQL login to old DB
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg example2 -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg example2_extra -e "select version()"',
	},

	# Check MySQL login by mailbox user
	{ 'command' => 'mysql -u '.$test_full_clone_user_mysql.' -pspod exampleclone -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_full_clone_user_mysql.' -pspod exampleclone_extra -e "select version()"',
	},

	# Cleanup all the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$hashpass_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'hashpass' ],
		      [ 'mysql-pass', 'spod' ],
		      [ 'postgres-pass', 'spam' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Check for hashed password
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Hashed password:', 'Password for mysql:',
		      'Password storage: Hashed' ],
	  'antigrep' => [ 'Password:' ],
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to admin mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ] ],
	},

	# Check IMAP and POP3 for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password smeg '.
		       $webmin_proto.'://localhost:'.
		       $webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -pspod '.$test_domain_db.' -e "select version()"',
	},

	$config{'postgres'} ?
		&postgresql_login_commands($test_domain_user, 'spam',
                                           $test_domain_db, $test_domain_home)
		: ( ),

	# Change password
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'pass' => 'newpass' ] ],
	},

	# Check new Webmin password
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       '--user '.$test_domain_user.' '.
		       '--password newpass '.
		       $webmin_proto.'://localhost:'.$webmin_port.'/',
	},

	# Check FTP login with new password
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':newpass@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check IMAP and POP3 for admin mailbox with new password
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'newpass' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check MySQL login again (password should be un-changed)
	{ 'command' => 'mysql -u '.$test_domain_user.' -pspod '.$test_domain_db.' -e "select version()"',
	},

	# Check PostgreSQL login again (password should be un-changed)
	$config{'postgres'} ?
		&postgresql_login_commands($test_domain_user, 'spam',
					   $test_domain_db, $test_domain_home)
		: ( ),

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ],
		      [ 'mysql', $test_domain_user ] ],
	},

	# Make sure the mailbox exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'antigrep' => 'Password:',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check IMAP and POP3 for mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check MySQL login for the mailbox
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Change password
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'pass' => 'newpass' ] ],
	},

	# Check FTP login with new password
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':newpass@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check IMAP and POP3 for mailbox with new password
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'newpass' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check MySQL login for the mailbox with new password
	{ 'command' => 'mysql -u '.$test_full_user_mysql.' -pnewpass '.$test_domain_db.' -e "select version()"',
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'mail' ],
		      @create_args, ],
	},

	# Check for hashed password
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Hashed password:',
		      'Password storage: Hashed' ],
	  'antigrep' => [ 'Password:' ],
	},

	# Create a mailbox in it
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Make sure the mailbox exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_subdomain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'antigrep' => 'Password:',
	},

	# Create another domain with a random MySQL pass
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_clone_domain ],
		      [ 'desc', 'Test domain two' ],
		      [ 'pass', 'smeg' ],
		      [ 'hashpass' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Get the MySQL password
	{ 'command' => 'list-domains.pl --multiline '.
		       '--domain '.$test_clone_domain.
		       ' | grep "Password for mysql" | awk \'{ print $4 }\'',
	  'save' => 'MYSQL_PASS',
	  'antigrep' => 'smeg',
	},

	# Check MySQL login with random pass
	{ 'command' => 'mysql -u '.$test_clone_domain_user.' -p$MYSQL_PASS '.$test_clone_domain_db.' -e "select version()"',
	},

	$config{'postgres'} ? (
		# Get the PostgreSQL password
		{ 'command' => 'list-domains.pl --multiline '.
			       '--domain '.$test_clone_domain.
			       ' | grep "Password for postgres" | awk \'{ print $4 }\'',
		  'save' => 'POSTGRES_PASS',
		  'antigrep' => 'smeg',
		},

		# Test login
		&postgresql_login_commands($test_clone_domain_user,
					   '$POSTGRES_PASS',
					    $test_clone_domain_db,
					    $test_clone_domain_home),
		) : ( ),

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
	},
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_clone_domain ] ],
	  'cleanup' => 1
	},
	];

$ipbackup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server to be included, with a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'logrotate' ], [ 'dns' ],
		      [ 'mail' ], [ $ssl ],
		      [ 'allocate-ip' ],
		      [ 'content' => 'Test sub-home page' ],
		      @create_args, ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore from backup, with IP re-allocation
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'original-ip' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Make sure the main domain is on the shared IP
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'IP address: '.&get_default_ip(),
	},

	# Check that the main domain IP resolves OK
	{ 'command' => 'host -t A '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Check main domain website
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Make sure the sub-server is on a private IP
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'multiline' ] ],
	  'antigrep' => 'IP address: '.&get_default_ip(),
	  'grep' => 'IP address:.*On',
	},

	# Check that the sub-server IP resolves OK
	{ 'command' => 'host -t A '.$test_subdomain,
	  'antigrep' => &get_default_ip(),
	},

	# Check sub-server website
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test sub-home page',
	},
	{ 'command' => $wget_command.'https://'.$test_subdomain,
	  'grep' => 'Test sub-home page',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$s3_tests = [
	# Create a random file
	{ 'command' => 'dd if=/dev/random of=/tmp/s3.dat count=10 bs=1024',
	},

	# Create a bucket
	{ 'command' => 'create-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ] ],
	},

	# List buckets
	{ 'command' => 'list-s3-buckets.pl',
	  'grep' => 'virtualmin-s3-test-bucket',
	},

	# Upload the file
	{ 'command' => 'upload-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'source', '/tmp/s3.dat' ] ],
	},

	# List files
	{ 'command' => 'list-s3-files.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ] ],
	  'grep' => 's3.dat',
	},

	# Download the file
	{ 'command' => 'download-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'file', 's3.dat' ],
		      [ 'dest', '/tmp/s3.dat.2' ] ],
	},

	# Make sure they are the same
	{ 'command' => 'diff /tmp/s3.dat /tmp/s3.dat.2 >/dev/null' },

	# Delete the file on S3
	{ 'command' => 'delete-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'file', 's3.dat' ] ],
	},

	# List files, to make sure it is gone
	{ 'command' => 'list-s3-files.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ] ],
	  'antigrep' => 's3.dat',
	},

	# Try a download, which should fail
	{ 'command' => 'download-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'file', 's3.dat' ],
		      [ 'dest', '/tmp/s3.dat.2' ] ],
	  'fail' => 1,
	},

	# Re-upload multipart
	{ 'command' => 'upload-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'source', '/tmp/s3.dat' ],
		      [ 'multipart' ] ],
	},

	# Download the file again
	{ 'command' => 'download-s3-file.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'file', 's3.dat' ],
		      [ 'dest', '/tmp/s3.dat.2' ] ],
	},

	# Make sure they are the same again
	{ 'command' => 'diff /tmp/s3.dat /tmp/s3.dat.2 >/dev/null' },

	# Delete the bucket
	{ 'command' => 'delete-s3-bucket.pl',
	  'args' => [ [ 'bucket', 'virtualmin-s3-test-bucket' ],
		      [ 'recursive' ] ],
	  'cleanup' => 1,
	},
	];
if (!$s3_account) {
	$s3_tests = [ { 'command' => 'echo No default S3 access or secret key defined on this system' } ];
	}
else {
	$s3_eu_tests = &convert_to_location($s3_tests, "eu-west-1");
	$s3_http_tests = &convert_to_http_api($s3_tests);
	$s3_eu_http_tests = &convert_to_http_api($s3_eu_tests);
	}

$rs_tests = [
	# Create a random file
	{ 'command' => 'dd if=/dev/urandom of=/tmp/rs.dat count=2048 bs=1024',
	},

	# Create a container
	{ 'command' => 'create-rs-container.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ] ],
	},

	# List containers
	{ 'command' => 'list-rs-containers.pl',
	  'grep' => 'virtualmin-rs-test-container',
	},

	# Upload the file
	{ 'command' => 'upload-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'source', '/tmp/rs.dat' ] ],
	},

	# List files
	{ 'command' => 'list-rs-files.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ] ],
	  'grep' => 'rs.dat',
	},

	# Download the file
	{ 'command' => 'download-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'file', 'rs.dat' ],
		      [ 'dest', '/tmp/rs.dat.2' ] ],
	},

	# Make sure they are the same
	{ 'command' => 'diff /tmp/rs.dat /tmp/rs.dat.2 >/dev/null' },

	# Delete the file on Rackspace
	{ 'command' => 'delete-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'file', 'rs.dat' ] ],
	},

	# List files to ensure it is gone
	{ 'command' => 'list-rs-files.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'name-only' ] ],
	  'antigrep' => 'rs.dat',
	},

	# Upload the file in multipart mode
	{ 'command' => 'upload-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'source', '/tmp/rs.dat' ],
		      [ 'multipart' ],
		      [ 'chunk-size', 1048576 ] ],
	},

	# List files to make sure the part exists
	{ 'command' => 'list-rs-files.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'name-only' ] ],
	  'grep' => [ 'rs.dat.0000', 'rs.dat$' ],
	},

	# Download the file again
	{ 'command' => 'download-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'file', 'rs.dat' ],
		      [ 'dest', '/tmp/rs.dat.2' ] ],
	},

	# Make sure they are the same
	{ 'command' => 'diff /tmp/rs.dat /tmp/rs.dat.2 >/dev/null' },

	# Delete the file on Rackspace
	{ 'command' => 'delete-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'file', 'rs.dat' ] ],
	},

	# List files to ensure it is gone, and all parts
	{ 'command' => 'list-rs-files.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'name-only' ] ],
	  'antigrep' => [ 'rs.dat$', 'rs.dat.0000' ],
	},

	# Try a download, which should fail
	{ 'command' => 'download-rs-file.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'file', 'rs.dat' ],
		      [ 'dest', '/tmp/rs.dat.2' ] ],
	  'fail' => 1,
	},

	# Delete the container
	{ 'command' => 'delete-rs-container.pl',
	  'args' => [ [ 'container', 'virtualmin-rs-test-container' ],
		      [ 'recursive' ] ],
	  'cleanup' => 1,
	},
	];
if (!$config{'rs_user'} || !$config{'rs_key'}) {
	$rs_tests = [ { 'command' => 'echo No default Rackspace access or secret key defined on this system' } ];
	}

$dns_tests = [
	# Create a domain with DNS
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-domain that should share the DNS zone
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'desc', 'Test subdomain' ],
		      [ 'dir' ], [ 'dns' ],
		      [ 'content' => 'Test home page' ],
		      [ 'parent' => $test_domain ],
		      @create_args, ],
        },

	# Create an alias that should get a copy of records
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'alias', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test alias-domain' ],
		      [ 'dir' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Validate DNS sub-domain was created
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate standard records
	{ 'command' => 'host -t A '.$test_domain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A www.'.$test_domain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A mail.'.$test_domain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A '.$test_dns_subdomain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A www.'.$test_dns_subdomain.' '.$dnsserver,
	},

	# Validate alias domain records
	{ 'command' => 'host -t A '.$test_subdomain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A www.'.$test_subdomain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A mail.'.$test_subdomain.' '.$dnsserver,
	},

	# Check for MX and NS records
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => [ $test_domain.'\\.\\s+MX\\s+',
		      'mail\\s+A\\s+',
		      $test_domain.'\\.\\s+NS\\s+',
		    ],
	},

	# Turn off email and make sure mail-related records are gone
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_subdomain ],
		      [ 'mail' ] ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'antigrep' => [ $test_domain.'\\.\\s+MX\\s+',
		          'mail\\s+A\\s+',
		        ],
	},

	# Add a record to both domains
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing1 A 1.2.3.4' ] ],
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'add-record', 'testing2 A 1.2.3.4' ] ],
	},

	# Validate that they were created
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},
	{ 'command' => 'host -t A testing1.'.$test_domain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A testing1.'.$test_subdomain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A testing2.'.$test_dns_subdomain.' '.$dnsserver,
	},

	# Backup and restore the DNS feature for all domains
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_dns_subdomain ],
		      [ 'feature', 'dns' ],
		      [ 'dest', $test_backup_file ] ],
	},
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'domain', $test_dns_subdomain ],
		      [ 'feature', 'dns' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Split the sub-domain into it's own zone
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'disable-subdomain' ] ],
	},

	# Validate the split
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'antigrep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Move the sub-domain back into the parent zone
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'enable-subdomain' ] ],
	},

	# Validate the move
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Rename the parent domain so that the sub-domain no longer matches
	{ 'command' => 'rename-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'new-domain', $test_rename_domain ] ],
	},

	# Check that the sub-domain is now separate
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'antigrep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_rename_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'user', $test_domain_user ] ],
	  'cleanup' => 1 },
	];

$dnssub_tests = [
	# Create a domain with DNS
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-domain with it's own owner that should share the DNS zone
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'desc', 'Test subdomain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ],
		      [ 'content' => 'Test home page' ],
		      [ 'any-dns-subdomain' ],
		      @create_args, ],
        },

	# Validate DNS sub-domain was created
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Add a record to both domains
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing1 A 1.2.3.4' ] ],
	},
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'add-record', 'testing2 A 1.2.3.4' ] ],
	},

	# Validate that they were created
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},
	{ 'command' => 'host -t A testing1.'.$test_domain.' '.$dnsserver,
	},
	{ 'command' => 'host -t A testing2.'.$test_dns_subdomain.' '.$dnsserver,
	},

	# Split the sub-domain into it's own zone
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'disable-subdomain' ] ],
	},

	# Validate the split
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'antigrep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Move the sub-domain back into the parent zone
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'enable-subdomain' ] ],
	},

	# Validate the move
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'Parent DNS virtual server: '.$test_domain ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_dns_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ] ],
	  'cleanup' => 1 },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$dnssec_tests = [
	# Create a domain with DNS
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-domain with its one zone file
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'desc', 'Test subdomain' ],
		      [ 'dir' ], [ 'dns' ],
		      [ 'content' => 'Test home page' ],
		      [ 'parent' => $test_domain ],
		      [ 'separate-dns-subdomain' ],
		      @create_args, ],
        },

	# Enable DNSSEC for both
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_dns_subdomain ],
		      [ 'enable-dnssec' ] ],
	},

	# Validate everything
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain', $test_dns_subdomain ],
		      [ 'all-features' ] ],
	},

	# Check for DNSSEC records
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dnssec-records' ] ],
	  'grep' => [ 'NSEC', 'DS' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'dnssec-records' ] ],
	  'grep' => [ 'NSEC' ],
	},

	# Check that a DNS lookup shows it is enabled
	{ 'command' => 'dig '.$test_domain.' +dnssec',
	  'grep' => $test_domain.'\.\s+\d+\s+IN\s+RRSIG',
	},

	# Disable DNSSEC for both
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_dns_subdomain ],
		      [ 'disable-dnssec' ] ],
	},

	# Check DNSSEC records are gone
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dnssec-records' ] ],
	  'antigrep' => [ 'NSEC', 'DS' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'domain', $test_dns_subdomain ],
		      [ 'dnssec-records' ] ],
	  'antigrep' => [ 'NSEC' ],
	},

	# Check that a DNS lookup shows it is disabled
	{ 'command' => 'dig '.$test_domain.' +dnssec',
	  'antigrep' => $test_domain.'\.\s+\d+\s+IN\s+RRSIG',
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'user', $test_domain_user ] ],
	  'cleanup' => 1 },
	];

$googledns_tests = [
	# Create a domain using Google DNS
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'cloud-dns' => 'google' ],
		      [ 'content' => 'Test home page' ],
		      [ 'user' => $test_domain_user ],
		      @create_args, ],
        },

	# Validate all features
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_cloud_domain ],
		      [ 'all-features' ] ],
	},

	# Validate that it has regular records
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'www', 'mail' ],
	},

	# Add a DNS record
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'add-record', 'testing1 A 1.2.3.4' ] ],
	},

	# Validate that it was created
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'testing1' ],
	},

	# Create a sub-domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_subdomain ],
		      [ 'parent', $test_cloud_domain ],
		      [ 'desc', 'Test subdomain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
        },

	# Validate that it's a DNS sub-domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_subdomain ] ],
	  'grep' => [ 'Parent DNS virtual server: '.$test_cloud_domain ],
	},

	# Validate that it has regular records
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_subdomain ] ],
	  'grep' => [ 'www', 'mail' ],
	},

	# Add a sub-domain record
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_cloud_subdomain ],
		      [ 'add-record', 'testing2 A 1.2.3.4' ] ],
	},

	# Validate that it was created
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Backup and restore both domains
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'domain', $test_cloud_subdomain ],
		      [ 'feature', 'dns' ],
		      [ 'dest', $test_backup_file ] ],
	},
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'domain', $test_cloud_subdomain ],
		      [ 'feature', 'dns' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Re-check that expected records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_subdomain ] ],
	  'grep' => [ 'testing2' ],
	},

	# Delete the sub-domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_subdomain ] ],
	},

	# Validate that the record is gone from the parent
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'antigrep' => [ 'testing2' ],
	},

	# Disable and re-enable the DNS feature
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ] ],
	},
	{ 'command' => 'enable-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ] ],
	},

	# Validate that the record stil exists
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'testing1' ],
	},

	# Move to local hosting
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'cloud-dns' => 'local' ] ],
	},

	# Validate that the record still exists
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'testing1' ],
	},

	# Move back to the cloud
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'cloud-dns' => 'google' ] ],
	},

	# Validate that the record still exists
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_cloud_domain ] ],
	  'grep' => [ 'testing1' ],
	},

	# Rename the domain
	{ 'command' => 'rename-domain.pl',
	  'args' => [ [ 'domain', $test_cloud_domain ],
		      [ 'new-domain', $test_rename_domain ] ],
	},

	# Validate that records still exist
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_rename_domain ] ],
	  'grep' => [ 'testing1' ],
	},

	# Validate all features after the rename
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'all-features' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'user', $test_domain_user ] ],
	  'cleanup' => 1 },
	];

$route53_tests = &convert_to_dnscloud($googledns_tests, "route53");

$htpasswd_tests = [
	# Create a domain with a website
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test web page' ],
		      @create_args, ],
	},

	# Test wget without protection
	{ 'command' => $wget_command.' http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Setup protected directory
	{ 'command' => 'virtualmin create-protected-directory',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Protection test' ],
		      [ 'path', $test_domain_html ] ],
	  'grep' => 'Added protection for '.$test_domain_html,
	},

	# Check the directory was created
	{ 'command' => 'virtualmin list-protected-directories',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dir-only' ] ],
	  'grep' => $test_domain_html,
	},

	# Test wget with protection, which should now fail
	{ 'command' => $wget_command.' http://'.$test_domain,
	  'fail' => 1,
	},

	# Add a user
	{ 'command' => 'virtualmin create-protected-user',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', $test_domain_html ],
		      [ 'user', 'testy' ],
		      [ 'pass', 'smeg' ] ],
	},

	# Check the user was created
	{ 'command' => 'virtualmin list-protected-users',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', $test_domain_html ],
		      [ 'name-only' ] ],
	  'grep' => 'testy',
	},

	# Test wget as the new user
	{ 'command' => $wget_command.' http://testy:smeg@'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Delete the user
	{ 'command' => 'virtualmin delete-protected-user',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', $test_domain_html ],
		      [ 'user', 'testy' ] ],
	},

	# Test wget as the user, which should fail now
	{ 'command' => $wget_command.' http://testy:smeg@'.$test_domain,
	  'fail' => 1,
	},

	# Delete the directory protection
	{ 'command' => 'virtualmin delete-protected-directory',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', $test_domain_html ] ],
	},

	# Test wget works again
	{ 'command' => $wget_command.' http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$htpasswd_tests_extra = [
	# Create a domain with a website
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ],
		      [ 'logrotate' ],
		      [ 'content' => 'Test web page' ],
		      @create_args, ],
	},

	# Test wget without protection
	{ 'command' => $wget_command.' http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Setup protected directory
	{ 'command' => 'virtualmin create-protected-directory',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Protection test' ],
		      [ 'path', $test_domain_html ] ],
	  'grep' => 'Added protection for '.$test_domain_html,
	},

	# Check the directory was created
	{ 'command' => 'virtualmin list-protected-directories',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dir-only' ] ],
	  'grep' => $test_domain_html,
	},

	# Test wget with protection, which should now fail
	{ 'command' => $wget_command.' http://'.$test_domain,
	  'fail' => 1,
	},

	# Create webserver extra user
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user_extra ],
		      [ 'pass', 'smeg' ],
		      [ 'webserver-dir', $test_domain_html ],
		      [ 'webserver-only' ] ],
	},

	# Check the user was created
	{ 'command' => 'virtualmin list-protected-users',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', $test_domain_html ],
		      [ 'name-only' ] ],
	  'grep' => $test_user_extra,
	},

	# Test wget as the new user
	{ 'command' => $wget_command.' http://'.&urlize($test_full_user_extra).':smeg@'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Delete extra user
	{ 'command' => 'virtualmin delete-user',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user_extra ] ],
	},

	# Test wget as the user, which should fail now
	{ 'command' => $wget_command.' http://'.&urlize($test_full_user_extra).':smeg@'.$test_domain,
	  'fail' => 1,
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$reset_tests = [
	# Create a domain with all the features
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ $ssl ], [ 'dns' ],
		      [ 'mail' ], [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Switch PHP mode to fCGId
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'fcgid' ] ],
	},

	# Create a redirect for /google
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google' ],
		      [ 'redirect', 'http://www.google.com' ] ],
	},

	# Create a redirect for SSL only
	{ 'command' => 'create-redirect.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/ssl' ],
		      [ 'redirect', 'http://www.example.com' ],
		      [ 'https' ], ],
	},

	# Change PHP version on one directory
	{ 'command' => 'set-php-directory.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'dir', 'foo' ],
		      [ 'version', $max_php_version ] ],
	},

	# Add a bogus Apache directive
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-directive', 'Smeg spod' ] ],
	},

	# Reset the website feature
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'web' ] ],
	},

	# Validate to ensure that the config is now OK
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'feature', 'web' ],
		      [ 'feature', 'ssl' ], ],
	},

	# Check that the first redirect still exists
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^/google',
		      'Destination: http://www.google.com',
		      'Type: Redirect',
		      'Match sub-paths: No',
		      'Protocols: http https$', ],
	},

	# Check that the second SSL-only redirect still exists
	{ 'command' => 'list-redirects.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ],
		      [ 'path', '/ssl' ] ],
	  'grep' => [ '^/ssl',
		      'Destination: http://www.example.com',
		      'Type: Redirect',
		      'Match sub-paths: No',
		      'Protocols: https$', ],
	},

	# Check that the PHP mode is correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'PHP execution mode: fcgid' ],
	},

	# Check for the custom PHP version
	{ 'command' => 'list-php-directories.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '/foo$',
		      'PHP version: '.$max_php_version ],
	},

	# Check PHP execution
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Add a DNS record that will be lost
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-record', 'testing A 1.2.3.4' ] ],
	},

	# Remove a DNS record that will be re-created
	{ 'command' => 'modify-dns.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'remove-record', 'www A' ] ],
	},

	# Try a DNS reset that should fail
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'dns' ] ],
	  'fail' => 1,
	},

	# Try again, this time skipping warnings
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'skip-warnings' ],
		      [ 'dns' ] ],
	  'grep' => 'testing \\(A\\)',
	},

	# Check that the record is gone, and that a regular record is back
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'antigrep' => [ 'testing1' ],
	},
	{ 'command' => 'get-dns.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'www' ],
	},

	# Attempt a MySQL reset, which should be OK since there are no tables
	# or extra DBs yet
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'mysql' ] ],
	},

	# Create one table
	{ 'command' => 'mysql -u '.$mysql::mysql_login.' -p'.$mysql::mysql_pass.' '.$test_domain_db.' -e "create table foo (id int(4))"',
	},

	# MySQL reset should now fail
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'mysql' ] ],
	  'fail' => 1,
	},

	# Attempt a Postgres reset, which should be OK since there are no tables
	# or extra DBs yet
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'postgres' ] ],
	},

	# Add a new Postgres DB to block the reset
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'postgres' ],
		      [ 'name', $test_domain_user.'_extra2' ] ],
	},

	# Postgres reset should now fail
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'postgres' ] ],
	  'fail' => 1,
	},

	# Break the Unix user's password
	{ 'command' => 'echo pog | passwd --stdin '.$test_domain_user,
	},

	# Check FTP login fails
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'grep' => 'Login incorrect',
	  'ignorefail' => 1,
	},

	# Reset the Unix user
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'unix' ] ],
	},

	# Check FTP login works now
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Validate all features one final time
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Switch PHP mode to FPM
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'fpm' ] ],
	},

	# Reset the website feature again
	{ 'command' => 'reset-feature.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'web' ] ],
	},

	# Validate to ensure that the config is now OK
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'feature', 'web' ],
		      [ 'feature', 'ssl' ], ],
	},

	# Check that the PHP mode is correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'PHP execution mode: fpm' ],
	},

	# Check PHP execution again
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$compression_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Backup to a temp file in ZIP format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_zip_backup_file ],
		      [ 'compression', 'zip' ] ],
	},

	# Check that it's actually a ZIP
	{ 'command' => 'file '.$test_zip_backup_file,
	  'grep' => ['Zip archive data'],
	},

	# Backup to a temp file in tar.gz format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ],
		      [ 'compression', 'gzip' ] ],
	},

	# Check that it's actually a tar.gz
	{ 'command' => 'file '.$test_backup_file,
	  'grep' => ['gzip compressed data'],
	},

	# Backup to a temp file in tar format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_tar_backup_file ],
		      [ 'compression', 'tar' ] ],
	},

	# Check that it's actually a tar
	{ 'command' => 'file '.$test_tar_backup_file,
	  'grep' => ['tar archive'],
	},

	# Backup to a temp file in tar.bz2 format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_bzip2_backup_file ],
		      [ 'compression', 'bzip2' ] ],
	},

	# Check that it's actually a tar.bz2
	{ 'command' => 'file '.$test_bzip2_backup_file,
	  'grep' => ['bzip2 compressed data'],
	},

	# Backup to a ZIP file, but without specifying a compression format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_zip_backup_file ] ],
	},

	# Check that it's actually a ZIP
	{ 'command' => 'file '.$test_zip_backup_file,
	  'grep' => ['Zip archive data'],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore from the ZIP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_zip_backup_file ] ],
	},

	# Test HTTP get on restored file
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Backup to a directory in ZIP format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ],
		      [ 'compression', 'zip' ] ],
	},

	# Check that it's actually a ZIP
	{ 'command' => 'file '.$test_backup_dir.'/'.$test_domain.'.zip',
	  'grep' => ['Zip archive data'],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore from the ZIP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Test HTTP get on restored file
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	  'quiet' => 1,
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$parallel_backup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Cleanup backup destinations
	{ 'command' => 'rm -rf '.$test_backup_dir },
	{ 'command' => 'rm -rf '.$test_backup_dir2 },

	# Backup to a temp dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'dest', $test_backup_dir ] ],
	  'background' => 1,
	},

	# Backup to another temp dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'dest', $test_backup_dir2 ] ],
	  'background' => 2,
	},

	# Wait for background processes to complete
	{ 'wait' => [ 1, 2 ] },

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.info' },
	{ 'command' => 'ls -l '.$test_backup_dir.'/'.$test_domain.'.tar.gz.dom' },

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_dir2.'/'.$test_domain.'.tar.gz' },
	{ 'command' => 'ls -l '.$test_backup_dir2.'/'.$test_domain.'.tar.gz.info' },
	{ 'command' => 'ls -l '.$test_backup_dir2.'/'.$test_domain.'.tar.gz.dom' },

	# Make sure both were logged
	{ 'command' => 'list-backup-logs.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'start', -1 ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Domains: '.$test_domain,
		      'Final status: OK',
		      'Destination: '.$test_backup_dir,
		      'Destination: '.$test_backup_dir2 ],
	},

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore from backup 1
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore from backup 2
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir2 ] ],
	},

	# Cleanup backup destination
	{ 'command' => 'rm -f '.$test_backup_file },
	{ 'command' => 'rm -f '.$test_backup_file.'.info' },
	{ 'command' => 'rm -f '.$test_backup_file.'.dom' },

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	  'background' => 1,
	},

	# Backup to the same temp file, which should fail
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	  'background' => 2,
	  'sleep' => 1,
	},

	# Wait for background processes to complete
	{ 'wait' => [ 2 ],
	  'fail' => 1 },
	{ 'wait' => [ 1 ] },

	# Make sure the file and meta-files exist
	{ 'command' => 'ls -l '.$test_backup_file },
	{ 'command' => 'ls -l '.$test_backup_file.'.info' },
	{ 'command' => 'ls -l '.$test_backup_file.'.dom' },

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$transfer_tests = [
	# Create a parent domain to be transferred
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ], [ 'logrotate' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ $web ], [ 'logrotate' ], [ 'dns' ],
		      [ 'mail' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, with a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain with dir' ],
		      [ 'dir' ], [ $web ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Create an alias domain to be included, without a dir
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'alias', $test_domain ],
		      [ 'desc', 'Test alias domain without dir' ],
		      [ $web ], [ 'dns' ],
		      @create_args, ],
	},

	# Test that everything works initially
	@post_restore_tests,

	# Transfer locally
	{ 'command' => 'transfer-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', '127.0.0.1' ],
		      [ 'webmin' ],
		      [ 'pass', $webmin_pass ],
		      [ 'overwrite' ] ],
	},

	# Test that everything still works
	@post_restore_tests,

	# Transfer locally
	{ 'command' => 'transfer-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'host', '127.0.0.1' ],
		      [ 'webmin' ],
		      [ 'pass', $webmin_pass ],
		      [ 'overwrite' ],
		      [ 'delete' ] ],
	},

	# Test that everything still works
	@post_restore_tests,

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];
if (!$webmin_pass) {
	$transfer_tests = [ { 'command' => 'echo Missing user or password ; false' } ];
	}

$ftp_tests = [
	# Create a domain with SSL, FTP and a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test FTP domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ $web ], [ 'dns' ], [ $ssl ],
		      [ 'logrotate' ], [ 'ftp' ],
		      [ 'allocate-ip' ],
		      [ 'content' => 'Test FTP home page' ],
		      @create_args, ],
        },

	# Copy the domain's SSL cert to proftpd
	{ 'command' => 'install-service-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'add-domain' ],
		      [ 'service', 'proftpd' ] ],
	},

	# Check that anonymous FTP to it works
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain.'/',
	  'antigrep' => 'Login incorrect',
	},

	# Put a file in the anonymous FTP directory
	{ 'command' => 'echo "bar" >~'.
		       $test_domain_user.'/ftp/foo.txt',
	},

	# Try to fetch it
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain.'/foo.txt',
	  'grep' => 'bar',
	},

	# Test that encrypted FTP works and serves the right cert
	{ 'command' => $curl_command.' --ftp-ssl --insecure -v '.
		       'ftp://'.$test_domain.'/foo.txt',
	  'grep' => [ 'bar', 'O=Test FTP domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Disable the domain
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'feature' => 'ftp' ] ],
	},

	# FTP should fail now
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain.'/',
	  'grep' => 'Login incorrect',
	  'fail' => 1,
	},

	# Re-enable the domain
	{ 'command' => 'enable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# FTP should work again
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain.'/',
	  'antigrep' => 'Login incorrect',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$xml_tests = [
	# Create a domain to run API commands on
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ $web ], [ 'mail' ],
		      [ 'mysql' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain to list
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database to list
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add a test alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# List the domain in XML mode
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'xml' ] ],
	  'grep' => [ '<data name="'.$test_domain.'">',
		      '<username>'.$test_domain_user.'</username>',
		      '<features>unix dir dns mail '.$web.' logrotate mysql</features>',
		    ],
	},

	# List the domain in JSON mode
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'json' ] ],
	  'grep' => [ '"name" : "'.$test_domain.'"',
		      '"username"\\s+:\\s+\\[\\s+"'.$test_domain_user.'"\\s+\]',
		      '"features"\\s+:\\s+\\[\\s+"unix dir dns mail '.$web.' logrotate mysql"\\s+\]',
		    ],
	  'grepall' => 1,
	},

	# List the users in XML mode
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'xml' ] ],
	  'grep' => [ '<data name="'.$test_full_user.'">',
		      '<domain>'.$test_domain.'</domain>',
		      '<real_name>Test user</real_name>',
		      '<user>'.$test_user.'</user>',
		      '<home_byte_quota>'.(777*1024*&quota_bsize("home")).
			'</home_byte_quota>',
		    ],
	},

	# List the users in JSON mode
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'json' ] ],
	  'grep' => [ '"name" : "'.$test_full_user.'"',
		      '"domain"\\s+:\\s+\\[\\s+"'.$test_domain.'"\\s+\]',
		      '"real_name"\\s+:\\s+\\[\\s+"Test user"\\s+\]',
		      '"user"\\s+:\\s+\\[\\s+"'.$test_user.'"\\s+\]',
		      '"home_byte_quota"\\s+:\\s+\\[\\s+"'.(777*1024*&quota_bsize("home")).'"\\s+\]',
		    ],
	  'grepall' => 1,
	},

	# List the aliases in XML mode
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'xml' ] ],
	  'grep' => [ '<data name="'.$test_alias.'@'.$test_domain.'">',
		      '<to>nobody@webmin.com</to>',
		      '<to>nobody@virtualmin.com</to>',
		    ],
	},

	# List the aliases in JSON
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'json' ] ],
	  'grep' => [ '"name"\\s+:\\s+"'.$test_alias.'@'.$test_domain.'"',
		      '"to"\\s+:\\s+\\[\\s+"nobody@webmin.com",\\s+"nobody@virtualmin.com"\\s+\\]',
		    ],
	  'grepall' => 1,
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$alltests = { '_config' => $_config_tests,
	      'domains' => $domains_tests,
	      'hashpass' => $hashpass_tests,
	      'disable' => $disable_tests,
	      'web' => $web_tests,
	      'mailbox' => $mailbox_tests,
	      'sshuser' => $sshuser_tests,
	      'alias' => $alias_tests,
	      'atalias' => $atalias_tests,
	      'aliasdom' => $aliasdom_tests,
	      'reseller' => $reseller_tests,
	      'script' => $script_tests,
	      'gplscript' => $gplscript_tests,
	      'fpmscript' => $fpmscript_tests,
	      'database' => $database_tests,
	      'proxy' => $proxy_tests,
	      'migrate' => $migrate_tests,
	      'move' => $move_tests,
	      'movealias' => $movealias_tests,
	      'backup' => $backup_tests,
	      'enc_backup' => $enc_backup_tests,
	      'mysqlbackup' => $mysqlbackup_tests,
	      'enc_mysqlbackup' => $enc_mysqlbackup_tests,
	      'postgresbackup' => $postgresbackup_tests,
	      'enc_postgresbackup' => $enc_postgresbackup_tests,
	      'multibackup' => $multibackup_tests,
	      'enc_multibackup' => $enc_multibackup_tests,
	      'splitbackup' => $splitbackup_tests,
	      'enc_splitbackup' => $enc_splitbackup_tests,
	      'remotebackup' => $remotebackup_tests,
	      'enc_remotebackup' => $enc_remotebackup_tests,
	      's3backup' => $s3backup_tests,
	      'enc_s3backup' => $enc_s3backup_tests,
	      'http_s3backup' => $http_s3backup_tests,
	      'gcsbackup' => $gcsbackup_tests,
	      'enc_gcsbackup' => $enc_gcsbackup_tests,
	      'dropboxbackup' => $dropboxbackup_tests,
	      'enc_dropboxbackup' => $enc_dropboxbackup_tests,
	      'azurebackup' => $azurebackup_tests,
	      'enc_azurebackup' => $enc_azurebackup_tests,
	      'drivebackup' => $drivebackup_tests,
	      'enc_drivebackup' => $enc_drivebackup_tests,
	      'bbbackup' => $bbbackup_tests,
	      'enc_bbbackup' => $enc_bbbackup_tests,
	      'rsbackup' => $rsbackup_tests,
	      'enc_rsbackup' => $enc_rsbackup_tests,
	      'configbackup' => $configbackup_tests,
	      'enc_configbackup' => $enc_configbackup_tests,
	      'webminbackup' => $webminbackup_tests,
	      'enc_webminbackup' => $enc_webminbackup_tests,
	      'ipbackup' => $ipbackup_tests,
	      'purge' => $purge_tests,
	      'differential' => $differential_tests,
	      'enc_differential' => $enc_differential_tests,
              'mail' => $mail_tests,
              'atmail' => $atmail_tests,
              'aliasmail' => $aliasmail_tests,
	      'prepost' => $prepost_tests,
	      'webmin' => $webmin_tests,
	      'remote' => $remote_tests,
	      'ssl' => $ssl_tests,
	      'nossl' => $nossl_tests,
	      'sslserv' => $sslserv_tests,
	      'shared' => $shared_tests,
	      'wildcard' => $wildcard_tests,
	      'parallel' => $parallel_tests,
	      'plans' => $plans_tests,
	      'plugin' => $plugin_tests,
	      'ip6' => $ip6_tests,
	      'webrename' => $webrename_tests,
	      'rename' => $rename_tests,
	      'bw' => $bw_tests,
	      'lastlogin' => $lastlogin_tests,
	      'quota' => $quota_tests,
	      'overlap' => $overlap_tests,
	      'redirect' => $redirect_tests,
	      'admin' => $admin_tests,
	      'clone' => $clone_tests,
	      'clonesub' => $clonesub_tests,
	      's3' => $s3_tests,
	      's3_eu' => $s3_eu_tests,
	      's3_http' => $s3_http_tests,
	      's3_eu_http' => $s3_eu_http_tests,
	      'exclude' => $exclude_tests,
	      'rs' => $rs_tests,
	      'jail' => $jail_tests,
	      'dns' => $dns_tests,
	      'dnssec' => $dnssec_tests,
	      'dnssub' => $dnssub_tests,
	      'googledns' => $googledns_tests,
	      'route53' => $route53_tests,
	      'htpasswd' => $htpasswd_tests,
	      'htpasswd_extra' => $htpasswd_tests_extra,
	      'reset' => $reset_tests,
	      'compression' => $compression_tests,
	      'allscript' => $allscript_tests,
	      'parallel_backup' => $parallel_backup_tests,
	      'transfer' => $transfer_tests,
	      'ftp' => $ftp_tests,
	      'scheduled' => $scheduled_tests,
	      'xml' => $xml_tests,
	    };
if (!$virtualmin_pro) {
	# Some tests don't work on GPL
	delete($alltests->{'admin'});
	delete($alltests->{'reseller'});
	delete($alltests->{'proxy'});
	delete($alltests->{'script'});
	}

# Find tests to run
if (!@tests) {
	@tests = sort { $a cmp $b } (keys %$alltests);
	}
else {
	for($i=0; $i<@tests; $i++) {
		@match = grep { /^$tests[$i]$/ } (keys %$alltests);
		@match || die "No test named or matching $tests[$i]";
		splice(@tests, $i, 1, @match);
		}
	@tests = sort { $a cmp $b } @tests;
	}
@tests = grep { &indexof($_, @skips) < 0 } @tests;

# Just show tests that would be run
if ($list_tests) {
	foreach my $t (@tests) {
		print $t,"\n";
		}
	exit(0);
	}

# Run selected tests
$total_failed = 0;
@failed_tests = ( );
@press = grep { $_->{'status'} } &get_startstop_links();
TESTS: foreach $tt (@tests) {
	next if ($done_test{$tt}++);

	# Cleanup backups first
	&unlink_file($test_backup_file);
	&unlink_file($test_differential_backup_file);
	&unlink_file($test_backup_dir);
	system("mkdir -p $test_backup_dir");
	&unlink_file($test_backup_dir2);
	system("mkdir -p $test_backup_dir2");

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
		next if ($no_cleanup == 2 && $t->{'cleanup'});
		$lastt = $t;
		$total++;
		$ok = &run_test($t);
		if (!$ok) {
			$allok = 0;
			$failed++;
			if (!$t->{'continuefail'}) {
				last;
				}
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
	if ($failed) {
		push(@failed_tests, $tt);
		}

	# Fail hard if the test broke any servers
	foreach my $ss (&get_startstop_links()) {
		my ($oldss) = grep { $ss->{'feature'} eq $_->{'feature'} &&
				     $ss->{'id'} eq $_->{'id'} } @press;
		if (!$ss->{'status'} && $oldss) {
			print "ABORT: $ss->{'name'} no longer running!\n";
			if (!$failed) {
				push(@failed_tests, $tt);
				}
			last TESTS;
			}
		}
	}

if ($total_failed) {
	print "!!!!!!!!!!!!! $total_failed TESTS FAILED !!!!!!!!!!!!!!\n";
	print "!!!!!!!!!!!!! FAILURES : ",join(" ", @failed_tests,),"\n";
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
		if ($t->{'ignorefail'}) {
			print "    .. PID $pid status ignored\n";
			}
		elsif ($?) {
			if ($t->{'fail'}) {
				print "    .. PID $pid successfully failed\n";
				}
			else {
				print "    .. PID $pid failed : $?\n";
				$ok = 0;
				}
			}
		else {
			if ($t->{'fail'}) {
				print "    .. PID $pid failed to fail\n";
				$ok = 0;
				}
			else {
				print "    .. PID $pid done\n";
				}
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
local $cmd = $t->{'command'};
foreach my $a (@{$t->{'args'}}) {
	my ($flag, @vals) = @$a;
	$cmd .= " --".$flag;
	foreach my $v (@vals) {
		if ($v =~ /\s/ || $v eq '') {
			$cmd .= " '".$v."'";
			}
		else {
			$cmd .= " ".$v;
			}
		}
	}
foreach my $e (keys %{$t->{'envs'}}) {
	$cmd = $e."=".quotemeta($t->{'envs'}->{$e})." ".$cmd;
	}
if ($cmd =~ /^wget/) {
	# Wget needs to write to current dir sometimes
	$cmd = "cd / ; $cmd";
	}
if ($t->{'user'}) {
	$cmd = &command_as_user($t->{'user'}, 0, $cmd);
	}
print "    Running $cmd ..\n";
sleep($t->{'sleep'});
if ($gconfig{'os_type'} !~ /-linux$/ && &has_command("bash")) {
	# Force use of bash
	$cmd = "bash -c ".quotemeta($cmd);
	}
local $to = $t->{'timeout'} || $timeout;
local ($out, $timed_out) = &backquote_with_timeout(
				"($cmd) 2>&1 </dev/null", $to);
local @lout = split(/\r?\n/, $out);
local $shortout = $out;
if (length($shortout) > $max_output) {
	$shortout = substr($shortout, 0, $max_output);
	$shortout .= "\n" if ($shortout !~ /\n$/);
	$shortout .= "(Plus ".(length($out) - $max_output)." more bytes...)\n";
	}
if (!$t->{'ignorefail'}) {
	if ($? && !$t->{'fail'} || !$? && $t->{'fail'}) {
		print $shortout if ($output || !$t->{'quiet'});
		if ($t->{'fail'}) {
			print "    .. failed to fail\n";
			}
                elsif ($timed_out) {
                        print "    .. timeout after $to seconds\n";
                        }
		else {
			print "    .. failed : $?\n";
			}
		return 0;
		}
	}
if ($t->{'grep'}) {
	# One line must match all regexps
	local @greps = ref($t->{'grep'}) ? @{$t->{'grep'}} : ( $t->{'grep'} );
	foreach my $grep (@greps) {
		$grep = &substitute_template($grep, \%saved_vars);
		local $match = 0;
		if ($t->{'grepall'}) {
			$match = ($out =~ /$grep/);
			}
		else {
			foreach my $l (split(/\r?\n/, $out)) {
				if ($l =~ /$grep/) {
					$match = 1;
					}
				}
			}
		if (!$match) {
			print $shortout if ($output || !$t->{'quiet'});
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
			print $shortout if ($output || !$t->{'quiet'});
			print "    .. unexpected match on $grep\n";
			return 0;
			}
		}
	}
print $shortout if ($output);
if ($t->{'save'}) {
	# Save output to variable
	$out =~ s/^\s*//;
	$out =~ s/\s*$//;
	$ENV{$t->{'save'}} = $out;
	$saved_vars{$t->{'save'}} = $out;
	print "    .. saved $t->{'save'} value $out\n";
	}
print $t->{'fail'} ?             "    .. successfully failed\n" :
      $t->{'ignorefail'} && $? ? "    .. failed but ignored\n" :
		                 "    .. success\n";
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
print "                           [--no-cleanup | --skip-cleanup]\n";
print "                           [--output]\n";
print "                           [--max-output bytes]\n";
print "                           [--migrate $mig]\n";
print "                           [--user webmin-login --pass password]\n";
print "                           [--script name]*\n";
exit(1);
}

# postgresql_login_commands(user, pass, db, home, failmode, [sql])
# Returns test commands to test a login to PostgreSQL
sub postgresql_login_commands
{
my ($user, $pass, $db, $home, $failmode, $sql) = @_;
return (
	# Create a .pgpass file for the user
	{ 'command' => 'echo "*:*:*:'.$user.':'.$pass.'" > '.
		       $home.'/.pgpass',
	},
	{ 'command' => 'chown '.$user.' '.$home.'/.pgpass',
	},
	{ 'command' => 'chmod 600 '.$home.'/.pgpass',
	},

	# Check PostgreSQL login
	{ 'command' => 'su - '.$user.' -c '.
		quotemeta('psql -U '.$user.' -h localhost '.
			  '-c "'.($sql || 'select 666').'" '.$db),
	  $sql ? ( ) : $failmode ? ( 'antigrep' => 666 ) : ( 'grep' => 666 ),
	  'ignorefail' => $failmode,
	},
	);
}

# convert_to_encrypted(&tests)
# Returns a list of tests with backup and restore commands modified to use
# a key
sub convert_to_encrypted
{
local ($tests) = @_;
if (!defined(&list_backup_keys)) {
	return [ ];
	}
local ($key) = &list_backup_keys();
local $rv = [ ];
foreach my $t (@$tests) {
	my $nt = { %$t };
	if ($nt->{'command'} eq 'backup-domain.pl' ||
	    $nt->{'command'} eq 'restore-domain.pl') {
		$nt->{'args'} = [ @{$nt->{'args'}},
				  [ 'key' => $key->{'id'} ] ];
		}
	push(@$rv, $nt);
	}
return $rv;
}

# convert_to_dnscloud(&tests, cloud)
sub convert_to_dnscloud
{
local ($tests, $cloud) = @_;
local $rv = [ ];
foreach my $t (@$tests) {
        my $nt = { %$t };
	my @a;
	foreach my $a (@{$nt->{'args'}}) {
		if ($a->[0] eq 'cloud-dns' && $a->[1] ne 'local') {
			push(@a, [ $a->[0], $cloud ]);
			}
		else {
			push(@a, $a);
			}
		}
	$nt->{'args'} = \@a;
	push(@$rv, $nt);
	}
return $rv;
}

# convert_to_location(&tests, location)
# Returns a list of tests with bucket creation commands modified to use the
# EU S3 location
sub convert_to_location
{
local ($tests, $location) = @_;
local $rv = [ ];
foreach my $t (@$tests) {
	my $nt = { %$t };
	my @na;
	foreach my $a (@{$t->{'args'}}) {
		push(@na, [ @$a ]);
		}
	$nt->{'args'} = \@na;
	if ($nt->{'command'} eq 'create-s3-bucket.pl') {
		push(@{$nt->{'args'}}, [ 'location' => $location ]);
		}
	foreach my $a (@{$nt->{'args'}}) {
		if ($a->[0] eq 'bucket') {
			$a->[1] .= "-".lc($location);
			}
		}
	push(@$rv, $nt);
	}
return $rv;
}

# convert_to_http_api(&tests)
# Convert S3 tests to run with an environment var set to use HTTP calls
sub convert_to_http_api
{
my ($tests) = @_;
my $rv = [ ];
foreach my $t (@$tests) {
        my $nt = { %$t };
	$nt->{'envs'}->{'NO_AWS_CMD'} = 1;
	push(@$rv, $nt);
	}
return $rv;
}

# convert_to_atmail(&tests)
# Change any domain creation calls to use @-format usernames
sub convert_to_atmail
{
my ($tests) = @_;
my $rv = [ ];
foreach my $t (@$tests) {
	my $nt = { %$t };
	my @nargs;
	if ($nt->{'command'} eq 'create-domain.pl') {
		push(@nargs, [ 'append-style' => 'username@domain' ]);
		}
	foreach my $a (@{$nt->{'args'}}) {
		my $na = [ @$a ];
		if ($na->[1] eq $test_full_user) {
			$na->[1] = $test_full_atuser;
			}
		push(@nargs, $na);
		}
	$nt->{'command'} =~ s/\~\Q$test_full_user\E/~$test_full_atuser/g;
	$nt->{'args'} = \@nargs;
	push(@$rv, $nt);
	}
return $rv;
}
