#!/usr/local/bin/perl
# Force a re-scan of mail logs, in case the user didn't search for anything
# recently.

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
if (&procmail_log_status() == 2) {
	# Only do if caching has been used
	&parse_procmail_log(undef, undef, undef, undef, "12345");
	}
