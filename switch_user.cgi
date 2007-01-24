#!/usr/local/bin/perl
# Switch the login to a domain's admin

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_switch_user($d) || &error($text{'switch_ecannot'});

&require_acl();
&get_miniserv_config(\%miniserv);
&acl::open_session_db(\%miniserv);
($olduser, $oldtime) = split(/\s+/, $acl::sessiondb{$main::session_id});
$olduser || &error($acl::text{'switch_eold'});
$acl::sessiondb{$main::session_id} = "$d->{'user'} $oldtime $ENV{'REMOTE_ADDR'}";
dbmclose(%acl::sessiondb);
&reload_miniserv();
&webmin_log("switch", "domain", $d->{'dom'}, $d);
&redirect("/");

