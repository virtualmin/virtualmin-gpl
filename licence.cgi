#!/usr/local/bin/perl
# Force a re-check of the licence

require './virtual-server-lib.pl';
&can_recheck_licence() || &error($text{'licence_ecannot'});
&ui_print_header(undef, $text{'licence_title'}, "");

print "$text{'licence_doing'}<br>\n";
&read_file($licence_status, \%licence);
&update_licence_from_site(\%licence);
&write_file($licence_status, \%licence);
($status, $expiry, $err) = &check_licence_expired();
if ($status == 0) {
	print "$text{'licence_ok'}<p>\n";
	}
else {
	print &text('licence_goterr', $err),"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});

