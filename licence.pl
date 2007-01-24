#!/usr/local/bin/perl
# Check the system's licence, and set a flag that will be later displayed
# in Virtualmin

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

&read_file($licence_status, \%licence);
&update_licence_from_site(\%licence);
&write_file($licence_status, \%licence);
