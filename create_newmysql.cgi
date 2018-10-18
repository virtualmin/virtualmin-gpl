#!/usr/local/bin/perl
# Add a new MySQL clone module

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmysqls_ecannot'});
&error_setup($text{'newmysqls_err'});
&ReadParse();

# Validate inputs
if ($in{'mode'} == 0) {
	&to_ipaddress($in{'host'}) || &error($text{'newmysqls_ehost'});
	&check_ipaddress($in{'host'}) && &error($text{'newmysqls_eip'});
	$host = $in{'host'};
	}
elsif ($in{'mode'} == 1) {
	$in{'sock'} =~ /^\/\S+$/ || &error($text{'newmysqls_esock'});
	$sock = $in{'sock'};
	}
if (!$in{'port_def'}) {
	$in{'port'} =~ /^\d+$/ || &error($text{'newmysqls_eport'});
	$port = $in{'port'};
	}
$in{'myuser'} =~ /^\S+$/ || &error($text{'newmysqls_euser'});
$user = $in{'myuser'};
$pass = $in{'mypass'};

# Add the clone module
$mm = { 'minfo' => { },
	'config' => { 'host' => $host,
		      'port' => $port,
		      'sock' => $sock,
		      'login' => $user,
		      'pass' => $pass },
      };
&create_remote_mysql_module($mm);

# Check that the MySQL connection works, and delete if not
$mod = $mm->{'minfo'}->{'dir'};
&foreign_require($mod, "mysql-lib.pl");
($ok, $err) = &foreign_call($mod, "is_mysql_running");
if ($ok != 1) {
	&delete_remote_mysql_module($mm);
	&error(&text('newmysqls_econn', $err));
	}

&webmin_log("create", "newmysql", $host || $sock, $mm->{'config'});
&redirect("edit_newmysqls.cgi");

