#!/usr/local/bin/perl
# Force a re-check of the licence

require './virtual-server-lib.pl';
&can_recheck_licence() || &error($text{'licence_ecannot'});
&ui_print_header(undef, $text{'licence_title'}, "");

print "$text{'licence_doing'}<br>\n";
&read_file($licence_status, \%licence);
&update_licence_from_site(\%licence);
&write_file($licence_status, \%licence);
($status, $expiry, $err, $doms, $servers) = &check_licence_expired();
if ($status == 0) {
	print &text('licence_ok2',
	    $doms > 0 ? $doms : $text{'licence_unlimited'},
	    $servers > 0 ? $servers : $text{'licence_unlimited'}),"<p>\n";
	if ($licence{'warn'}) {
		# Most recent check failed
		print &text('licence_warn',
			"<font color=#ff8800>$licence{'warn'}</font>"),"<p>\n";
		}
	}
else {
	print &text('licence_goterr',
		"<font color=#ff0000>$err</font>"),"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});

