#!/usr/local/bin/perl
# Collect various pieces of general system information, for display by themes
# on their status pages. Run every 5 mins from Cron.

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

$info = &collect_system_info();
if ($info) {
	&save_collected_info($info);
	}

