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
	print &text($expiry ? 'licence_ok3' : 'licence_ok2',
	    $doms > 0 ? $doms : $text{'licence_unlimited'},
	    $servers > 0 ? $servers : $text{'licence_unlimited'},
	    $expiry),"<p>\n";
	if ($licence{'warn'}) {
		# Most recent check failed
		print "<b>",&text('licence_warn',
		   "<font color=#ff8800>$licence{'warn'}</font>"),"</b><p>\n";
		}
	# Check for license close to expiry
	if ($expiry =~ /^(\d+)\-(\d+)\-(\d+)$/) {
		eval {
			$expirytime = timelocal(59, 59, 23, $3, $2-1, $1-1900);
			};
		}
	if ($expirytime && $expirytime - time() < 7*24*60*60) {
		$days = int(($expirytime - time()) / (24*60*60));
		$hours = int(($expirytime - time()) / (60*60));
		print "<font color=#ff8800><b>";
		if ($days) {
			print &text('licence_soon', $days);
			}
		else {
			print &text('licence_soon2', $hours);
			}
		print "</b></font><p>\n";
		}
	elsif (!$expirytime) {
		print "<b>",&text('licence_goterr2',
			"<font color=#ff0000>$expiry</font>"),"</b><p>\n";
		}
	}
else {
	print "<b>",&text('licence_goterr',
		"<font color=#ff0000>$err</font>"),"</b><p>\n";
	}

&ui_print_footer("", $text{'index_return'});

