#!/usr/local/bin/perl
# Save SPF options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'spf_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_spf($d) || &error($text{'spf_ecannot'});
&set_all_null_print();
$oldd = { %$d };

&obtain_lock_dns($d);
$spf = &get_domain_spf($d);
if ($in{'enabled'}) {
	# Turn on and update SPF record
	$spf ||= &default_domain_spf($d);
	$defspf = &default_domain_spf($d);
	foreach $t ('a', 'mx', 'ip4', 'ip6', 'include') {
		local @v = split(/\s+/, $in{'extra_'.$t});
		foreach my $v (@v) {
			if ($a eq 'a' || $t eq 'mx' || $t eq 'include') {
				# Must be a valid hostname
				$v =~ /^[a-z0-9\.\-\_]+$/i ||
					&error(&text('spf_e'.$t, $v));
				}
			elsif ($a eq "ip4") {
				# Must be a valid IP or IP/cidr or IP/mask
				&check_ipaddress($v) ||
				  ($v =~ /^([0-9\.]+)\/(\d+)$/ &&
				   $2 > 0 && $2 <= 32 &&
				   &check_ipaddress("$1")) ||
				  ($v =~ /^([0-9\.]+)\/([0-9\.]+)$/ &&
				   &check_ipaddress("$1") &&
				   &check_ipaddress("$2")) ||
					&error(&text('spf_e'.$t, $v));
				}
			elsif ($a eq "ip6") {
				# Must be a valid IPv6 or IPv6/cidr
				&check_ip6address($v) ||
				  ($v =~ /^([0-9\:]+)\/(\d+)$/ &&
				   $2 > 0 && $2 <= 128 &&
				   &check_ip6address("$1")) ||
					&error(&text('spf_e'.$t, $v));
				}
			}
		$spf->{$t.':'} = \@v;
		}
	$spf->{'all'} = $in{'all'};
	&save_domain_spf($d, $spf);
	}
else {
	# Just turn off SPF record
	&save_domain_spf($d, undef);
	}

# TLSA records
if (defined($in{'tlsa'})) {
	my @trecs = &get_domain_tlsa_records($d);
	my $changed;
	if ($in{'tlsa'} && !@trecs) {
		# Need to add records
		&pre_records_change($d);
		&sync_domain_tlsa_records($d, 1);
		$changed++;
		}
	elsif (!$in{'tlsa'} && @trecs) {
		# Need to remove records
		&pre_records_change($d);
		&sync_domain_tlsa_records($d, 2);
		$changed++;
		}
	if ($changed) {
		($recs, $file) = &get_domain_dns_records_and_file($d);
		&post_records_change($d, $recs, $file);
		&reload_bind_records($d);
		}
	}

$dmarc = &get_domain_dmarc($d);
$err = undef;
if ($in{'denabled'}) {
	# Turn on and update DMARC record
	$dmarc ||= &default_domain_dmarc($d);
	$defdmarc = &default_domain_dmarc($d);
	$dmarc->{'p'} = $in{'dp'};
	$in{'dpct'} =~ /^\d+$/ && $in{'dpct'} >= 0 &&
	  $in{'dpct'} <= 100 || &error($text{'tmpl_edmarcpct'});
	$dmarc->{'pct'} = $in{'dpct'};
	$err = &save_domain_dmarc($d, $dmarc);
	}
else {
	# Just turn off DMARC record
	$err = &save_domain_dmarc($d, undef);
	}
&error($err) if ($err);

if (defined(&bind8::supports_dnssec) && &bind8::supports_dnssec() &&
    &can_domain_dnssec($d) && defined($in{'dnssec'})) {
	# Turn DNSSEC on or off
	&pre_records_change($d);
	my $key = &bind8::get_dnssec_key(&get_bind_zone($d->{'dom'}));
	my $err;
	my $changed = 0;
	if ($key && !$in{'dnssec'}) {
		$err = &disable_domain_dnssec($d);
		$changed++;
		}
	elsif (!$key && $in{'dnssec'}) {
		$err = &enable_domain_dnssec($d);
		$changed++;
		}
	&error($err) if ($err);
	if ($changed) {
		($recs, $file) = &get_domain_dns_records_and_file($d);
		&post_records_change($d, $recs, $file);
		&reload_bind_records($d);
		}
	}

&modify_dns($d, $oldd);
&release_lock_dns($d);
&save_domain($d);

# Update DNS cloud if changed
$err = &modify_dns_cloud($d, $in{'cloud'});
$err && &error(&text('spf_ecloud', $err));

&run_post_actions();

# All done
&webmin_log("spf", "domain", $d->{'dom'});
&domain_redirect($d);

