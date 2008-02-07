#!/usr/local/bin/perl
# Run the Virtualmin config check

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/check-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "check-scripts.pl must be run as root";
	}

&set_all_text_print();
$cerr = &html_tags_to_text(&check_virtual_server_config());
if ($cerr) {
	print "ERROR: $cerr\n";
	exit(1);
	}
else {
	print "OK\n";
	exit(0);
	}


