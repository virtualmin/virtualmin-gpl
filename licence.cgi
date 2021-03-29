#!/usr/local/bin/perl
# Force a re-check of the licence

require './virtual-server-lib.pl';
&can_recheck_licence() || &error($text{'licence_ecannot'});
&ui_print_unbuffered_header(undef, $text{'licence_title'}, "");

print "$text{'licence_doing'}<br>\n";
&read_file($licence_status, \%licence);
&update_licence_from_site(\%licence);
&write_file($licence_status, \%licence);
($status, $expiry, $err, $doms, $servers) = &check_licence_expired();
if ($status == 0) {
	my $suc_text = &text($expiry ? 'licence_ok3' : 'licence_ok2',
	    $doms > 0 ? $doms : $text{'licence_unlimited'},
	    $servers > 0 ? $servers : $text{'licence_unlimited'},
	    $expiry);
	$suc_text =~ s/<i>(.*?)<\/i>./<b>@{[&ui_text_color("$1.", 'primary')]}<\/b>/;
	print $suc_text,"<p>\n";
	if ($licence{'warn'}) {
		# Most recent check failed
		print "<b>",&text('licence_warn',
			              &ui_text_color($licence{'warn'}, 'warn')),
		      "</b><p>\n";
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
		print "<b>";
		if ($days) {
			print &ui_text_color(&text('licence_soon', $days), 'warn');
			}
		else {
			print &ui_text_color(&text('licence_soon2', $hours), 'warn');
			}
		print "</b><p>\n";
		}
	elsif (!$expirytime) {
		print "<b>",&text('licence_goterr2',
			&ui_text_color($expiry, 'danger')),"</b><p>\n";
		}
	}
else {
	print "<b>",&text('licence_goterr',
		&ui_text_color($err, 'danger')),"</b><p>\n";
	}

&ui_print_footer("", $text{'index_return'});

