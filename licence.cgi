#!/usr/local/bin/perl
# Force a re-check of the licence

require './virtual-server-lib.pl';
&can_recheck_licence() || &error($text{'licence_ecannot'});
&read_env_file($virtualmin_license_file, \%serial);
my $serial = $serial{'SerialNumber'};
$serial =~ /^gpl$/i && &error($text{'upgrade_eserial'});
&ui_print_unbuffered_header(undef, $text{'licence_title'}, "", undef, undef, 1);

print "$text{'licence_doing'}<br>\n";
&read_file($licence_status, \%licence);
&update_licence_from_site(\%licence);
&write_file($licence_status, \%licence);
($status, $expiry, $err, $doms, $servers) = &check_licence_expired();
if (defined($status) && $status == 0) {
	my $suc_text = &text($expiry ? 'licence_ok3' : 'licence_ok2',
	    $doms > 0 ? $doms : $text{'licence_unlimited'},
	    $servers > 0 ? $servers : $text{'licence_unlimited'}, $expiry);
	print $suc_text,"<p>\n";
	if ($licence{'warn'}) {
		# Most recent check failed send to stderr
		&error_stderr(&text('licence_warn', $licence{'warn'}, $serial));
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
		if ($days) {
			print &text('licence_soon', $days);
			}
		else {
			print &text('licence_soon2', $hours);
			}
		print "<p>\n";
		}
	elsif (!$expirytime) {
		print &text('licence_goterr2', $expiry),"<p>\n";
		}
	}
else {
	$err = lcfirst($err);
	$err =~ s/\s*\.$//;
	print &text('licence_goterr', lcfirst($err)),"<p>\n";
	}

&ui_print_footer("pro/licence.cgi", lc($text{'licence_manager'}));

