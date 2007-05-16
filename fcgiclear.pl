#!/usr/local/bin/perl
# Delete any orphan php*-cgi processes

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
&cleanup_php_cgi_processes();

