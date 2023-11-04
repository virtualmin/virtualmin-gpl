#!/usr/local/bin/perl
# Set the TTL on all records in a domain

require './virtual-server-lib.pl';
&error_setup($text{'transfer_err2'});
&ReadParse();
my $d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_records($d) || &error($text{'records_ecannot'});
$in{'newttl'} =~ /^\d+$/ || &error($text{'transfer_enewttl'});

# Update default TTL
&obtain_lock_dns($d);
&pre_records_change($d);
my ($recs, $file) = &get_domain_dns_records_and_file($d);
my ($oldttl) = grep { $_->{'defttl'} } @$recs;
if ($oldttl) {
	$oldttl->{'defttl'} = $in{'newttl'};
	&modify_dns_record($recs, $file, $oldttl);
	}
else {
	my $newttl = { 'defttl' => $in{'newttl'} };
	&create_dns_record($recs, $file, $newttl);
	}

# Update records
foreach my $r (@$recs) {
	if ($r->{'ttl'} && $r->{'type'} ne 'SOA' && !&is_dnssec_record($r)) {
		$r->{'ttl'} = $in{'newttl'};
		&modify_dns_record($recs, $file, $r);
		}
	}

&post_records_change($d, $recs, $file);
&reload_bind_records($d);

$d->{'ttl_change_time'} = time();
$d->{'ttl_change_from'} = $in{'oldttl'};
&save_domain($d);
&release_lock_dns($d);
&webmin_log("fixttl", "domain", $d->{'dom'});
&redirect("transfer_form.cgi?dom=$in{'dom'}");
