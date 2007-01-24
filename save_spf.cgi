#!/usr/local/bin/perl
# Save SPF options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'spf_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&set_all_null_print();
$oldd = { %$d };

$spf = &get_domain_spf($d);
if ($in{'enabled'}) {
	$spf ||= &default_domain_spf($d);
	$defspf = &default_domain_spf($d);
	foreach $t ('a', 'mx', 'ip4') {
		local @v = split(/\s+/, $in{'extra_'.$t});
		foreach my $v (@v) {
			if (($t eq "a" || $t eq "mx") &&
			    $v !~ /^[a-z0-9\.\-\_]+$/i ||
			    $t eq "ip4" && !&check_ipaddress($v)) {
				&error(&text('spf_e'.$t, $v));
				}
			}
		$spf->{$t.':'} = \@v;
		}
	$spf->{'all'} = $in{'all'};
	&save_domain_spf($d, $spf);
	}
else {
	# Just turn off
	&save_domain_spf($d, undef);
	}

# Save DNS IP address
if ($in{'dns_ip_def'}) {
	delete($d->{'dns_ip'});
	}
else {
	&check_ipaddress($in{'dns_ip'}) || &error($text{'spf_ednsip'});
	$d->{'dns_ip'} = $in{'dns_ip'};
	}
&modify_dns($d, $oldd);
&save_domain($d);

&run_post_actions();

# All done
&webmin_log("spf", "domain", $d->{'dom'});
&domain_redirect($d);

