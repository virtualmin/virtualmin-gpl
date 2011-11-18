#!/usr/local/bin/perl
# Delete several website redirects

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
&error_setup($text{'redirects_derr'});

# Find them and delete them
@d = split(/\0/, $in{'d'});
@d || &error($text{'redirects_denone'});
&obtain_lock_web($d);
@redirects = &list_redirects($d);
foreach $path (@d) {
	($r) = grep { $_->{'path'} eq $path } @redirects;
	if ($r) {
		$err = &delete_redirect($d, $r);
		&error($err) if ($err);
		}
	}

# Log and return
&release_lock_web($d);
&set_all_null_print();
&run_post_actions();
&webmin_log("delete", "redirects", scalar(@d), { 'dom' => $d->{'dom'} });

&redirect("list_redirects.cgi?dom=$in{'dom'}");

