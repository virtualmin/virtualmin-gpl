#!/usr/local/bin/perl
# Save frame-forwarding HTML

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() || &error($text{'edit_ecannot'});

$ff = &framefwd_file($d);
$in{'text'} =~ s/\r//g;
$in{'text'} =~ s/\n*$/\n/;
&lock_file($ff);
&open_tempfile_as_domain_user($d, FILE, ">$ff", 1) ||
	&error(&text('expframe_ewrite', $ff, $d->{'user'}, $!));
&print_tempfile(FILE, $in{'text'});
&close_tempfile_as_domain_user($d, FILE);
&unlock_file($ff);

&run_post_actions_silently();
&webmin_log("frame", "domain", $d->{'dom'}, $d);
&domain_redirect($d);
