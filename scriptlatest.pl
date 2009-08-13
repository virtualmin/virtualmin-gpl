#!/usr/local/bin/perl
# Download updates to script installers that we don't have yet

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

if ($ARGV[0] eq "-debug" || $ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# XXX not done yet
