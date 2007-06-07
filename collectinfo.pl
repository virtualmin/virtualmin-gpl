#!/usr/local/bin/perl
# Collect various pieces of general system information, for display by themes
# on their status pages. Run every 5 mins from Cron.

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

# Make sure we are not already running
if (&test_lock($collected_info_file)) {
	print "Already running\n";
	exit(0);
	}
&lock_file($collected_info_file);

$info = &collect_system_info();
if ($info) {
	&save_collected_info($info);
	}
&unlock_file($collected_info_file);
