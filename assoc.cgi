#!/usr/local/bin/perl
# Associate or dis-associate features

require './virtual-server-lib.pl';
&error_setup($text{'assoc_err'});
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_associate_domain($d) || &error($text{'assoc_ecannot'});

# Update domain object with new features
&obtain_lock_everything($d);
foreach my $f (&list_possible_domain_features($d),
	       &list_possible_domain_plugins($d)) {
	$fname = $text{'feature_'.$f} ||
		 &plugin_call($f, "feature_name") || $f;
	if ($d->{$f} && !$in{$f}) {
		$d->{$f} = 0;
		push(@disabled, $f);
		my $dafunc = "disassociate_".$f;
		if (defined(&$dafunc)) {
			my $err = &$dafunc($d);
			&error(&text('assoc_edassoc', $fname, $err)) if ($err);
			}
		}
	elsif (!$d->{$f} && $in{$f}) {
		$d->{$f} = 1;
		push(@enabled, $f);
		my $afunc = "associate_".$f;
		if (defined(&$afunc)) {
			my $err = &$afunc($d);
			&error(&text('assoc_eassoc', $fname, $err)) if ($err);
			}
		}
	}

if ($in{'validate'}) {
	# Make sure any enabled features actually make sense
	foreach my $f (@enabled) {
		$vfunc = "validate_$f";
		if (defined(&$vfunc)) {
			$err = &$vfunc($d);
			if ($err) {
				&error(&text('assoc_evalidate',
					     $text{'feature_'.$f}, $err));
				}
			}
		}
	}

# Save the domain
&save_domain($d);
&release_lock_everything($d);
&clear_links_cache($d);
&webmin_log("assoc", "domain", $d->{'dom'}, $d);

# Redirect with left-side refresh
&domain_redirect($d, 1);
