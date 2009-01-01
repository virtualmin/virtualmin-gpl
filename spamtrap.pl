#!/usr/local/bin/perl
# Blacklist email in spamtrap files, and whitelist mail in hamtraps, for all
# domains with spam emailed.

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
&foreign_require("mailboxes", "mailboxes-lib.pl");

if ($ARGV[0] eq "-debug" || $ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# XXX
