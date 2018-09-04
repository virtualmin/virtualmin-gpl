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
	&bind8::modify_defttl($file, $oldttl, $in{'newttl'});
	}
else {
	&bind8::create_defttl($file, $in{'newttl'});
	foreach my $e (@$recs) {
		$e->{'line'}++;
		$e->{'eline'}++ if (defined($e->{'eline'}));
		}
	}

# Update records
foreach my $r (@$recs) {
	if ($r->{'ttl'} && $r->{'type'} ne 'SOA') {
		$r->{'ttl'} = $in{'newttl'};
		&bind8::modify_record($file, $r, $r->{'name'},
		    $r->{'ttl'}, $r->{'class'}, $r->{'type'},
		    &join_record_values($r), $r->{'comment'});
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
