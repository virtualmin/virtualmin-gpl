#!/usr/local/bin/perl
# Break the SSL linkage for a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
$d->{'ssl_same'} || &error($text{'cert_esame'});

# Break it
$same = &get_domain($d->{'ssl_same'});
$same || &error($text{'cert_esame'});
&break_ssl_linkage($d, $same);
&save_domain($d);
&run_post_actions_silently();
&webmin_log("breakcert", "domain", $d->{'dom'}, $d);

&redirect("cert_form.cgi?dom=$d->{'id'}");
