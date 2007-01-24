#!/usr/local/bin/perl
# Run Webalizer reports for all virtual servers

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/run-all-webalizer.pl";
require './virtual-server-lib.pl';
$< == 0 || die "run-all-webalizer.pl must be run as root";

&require_webalizer();
&foreign_require("cron", "cron-lib.pl");

&cron::create_wrapper($webalizer::cron_cmd,
		      "webalizer", "webalizer.pl");
foreach $d (&list_domains()) {
	next if (!$d->{'webalizer'});
	$alog = &get_apache_log($d->{'dom'}, $d->{'web_port'});
	next if (!$alog);
	print "Running Webalizer for $d->{'dom'} ($alog)\n";
	system("$webalizer::cron_cmd ".quotemeta($alog));
	}

