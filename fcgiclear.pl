#!/usr/local/bin/perl
# Delete any orphan php*-cgi processes

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';
&cleanup_php_cgi_processes();

