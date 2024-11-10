#!/usr/local/bin/perl
# Save DNS options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($text{'spf_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_dns($d) || &error($text{'spf_ecannot'});
&set_all_null_print();
$oldd = { %$d };

&obtain_lock_dns($d);

# Update alias DNS copy mode
if ($d->{'alias'} && defined($in{'aliasdns'})) {
	$d->{'aliasdns'} = $in{'aliasdns'};
	}

if (!$in{'readonly'}) {
	$spf = &get_domain_spf($d);
	if ($in{'enabled'}) {
		# Turn on and update SPF record
		$spf ||= &default_domain_spf($d);
		$defspf = &default_domain_spf($d);
		foreach $t ('a', 'mx', 'ip4', 'ip6', 'include') {
			local @v = split(/\s+/, $in{'extra_'.$t});
			foreach my $v (@v) {
				if ($a eq 'a' || $t eq 'mx' || $t eq 'include'){
					# Must be a valid hostname
					$v =~ /^[a-z0-9\.\-\_]+$/i ||
						&error(&text('spf_e'.$t, $v));
					}
				elsif ($a eq "ip4") {
					# Must be a valid IP or IP/cidr or
					# IP/mask
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
		foreach my $r ('ruf', 'rua') {
			if ($in{'dmarc'.$r.'_def'}) {
				delete($dmarc->{$r});
				}
			else {
				$in{'dmarc'.$r} =~ /^mailto:\S+\@\S+$/ ||
					&error($text{'tmpl_edmarc'.$r});
				$dmarc->{$r} = $in{'dmarc'.$r};
				}
			}
		$err = &save_domain_dmarc($d, $dmarc);
		}
	else {
		# Just turn off DMARC record
		$err = &save_domain_dmarc($d, undef);
		}
	&error($err) if ($err);

	# Update DKIM records
	my $dkim = &get_dkim_config();
	if ($dkim && defined($in{'dkim'})) {
		my $olddkim = &has_dkim_domain($d, $dkim);
		if ($in{'dkim'} eq '1') {
			$d->{'dkim_enabled'} = 1;
			}
		elsif ($in{'dkim'} eq '0') {
			$d->{'dkim_enabled'} = 0;
			}
		else {
			delete($d->{'dkim_enabled'});
			}
		my $newdkim = &has_dkim_domain($d, $dkim);
		if (!$olddkim && $newdkim) {
			&update_dkim_domains($d, 'setup');
			}
		elsif ($olddkim && !$newdkim) {
			&update_dkim_domains($d, 'delete');
			}
		}
	}

if (&can_domain_dnssec($d) && defined($in{'dnssec'})) {
	# Turn DNSSEC on or off
	&pre_records_change($d);
	my $key = &has_domain_dnssec($d);
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
if ($in{'cloud'} =~ /^remote_(\S+)$/) {
	# On remote DNS
	$rhost = $1;
	($rserver) = grep { $_->{'host'} eq $rhost } &list_remote_dns();
	$rserver || &error($text{'spf_eremoteexists'});
	$cloud = undef;
	}
elsif ($in{'cloud'} ne 'local' && $in{'cloud'} ne 'services') {
	# On a cloud provider
	($c) = grep { $_->{'name'} eq $in{'cloud'} } &list_dns_clouds();
	$c || &error($text{'spf_ecloudexists'});
	$d->{'dns_cloud'} eq $c->{'name'} || &can_dns_cloud($c) ||
		&error($text{'spf_ecloudcannot'});
	$cloud = $in{'cloud'};
	}
else {
	# On local or Cloudmin services
	$cloud = $in{'cloud'};
	}
$err = &modify_dns_cloud($d, $cloud, $rserver);
$err && &error(&text('spf_ecloud', $err));

&run_post_actions();

# All done
&webmin_log("spf", "domain", $d->{'dom'});
&domain_redirect($d);

