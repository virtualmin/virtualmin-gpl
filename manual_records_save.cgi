#!/usr/local/bin/perl
# Save manually edited records

require './virtual-server-lib.pl';
&require_bind();
&ReadParse();
&error_setup($text{'mrecords_err'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&copy_alias_records($d) && &error($text{'records_ecannot2'});
&can_manual_dns() || &error($text{'mrecords_ecannot'});
$in{'data'} =~ s/\r//g;
$in{'data'} =~ /\S/ || &error($text{'mrecords_enone'});

# Get the zone and records
&obtain_lock_dns($d);
&pre_records_change($d);
($oldrecs, $file) = &get_domain_dns_records_and_file($d);
$file || &error($oldrecs);
if ($in{'validate'}) {
	$olderr = &validate_dns($d, $oldrecs);
	}

# Parse the newly entered records
$recs = [ &text_to_dns_records($in{'data'}, $d->{'dom'}) ];
&set_record_ids($recs);

if ($d->{'provision_dns'} || $d->{'dns_cloud'}) {
	# Merge in any proxy bits set on old records
	foreach my $r (@$oldrecs) {
		my $pr = { %$r };
		delete($pr->{'proxied'});
		$proxy{&dns_record_key($pr)} = $r->{'proxied'};
		}
	foreach my $r (@$recs) {
		$r->{'proxied'} = $proxy{&dns_record_key($r)};
		}
	}
else {
	# Just over-write the records file
	$rootfile = &bind8::make_chroot($file);
	$temp = &transname();
	&copy_source_dest($rootfile, $temp);
	&open_tempfile(RECS, ">$rootfile");
	&print_tempfile(RECS, $in{'data'});
	&close_tempfile(RECS);

	# Check format one more time, so that named-checkconf can see the new
	# zone file
	if ($in{'validate'}) {
		$errs = &validate_dns_records($d, 1);
		if (ref($errs) && @$errs) {
			&copy_source_dest($temp, $rootfile);
			&error(&text('mrecords_evalidate',
				join("<br>", map { &html_escape($_) } @$errs)));
			}
		}
	}

# Save records
&post_records_change($d, $recs, $file);
&release_lock_dns($d);
&reload_bind_records($d);
&run_post_actions_silently();
&webmin_log("manual", "records", $d->{'dom'},
	    { 'count' => scalar(@$recs) });
&redirect("list_records.cgi?dom=$in{'dom'}&show=$in{'show'}");

