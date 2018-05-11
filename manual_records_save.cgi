#!/usr/local/bin/perl
# Save manually edited records

require './virtual-server-lib.pl';
&require_bind();
&ReadParse();
&error_setup($text{'mrecords_err'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_manual_dns() || &error($text{'mrecords_ecannot'});
$in{'data'} =~ s/\r//g;
$in{'data'} =~ /\S/ || &error($text{'mrecords_enone'});

# Get the zone and records
&obtain_lock_dns($d);
&pre_records_change($d);
($recs, $file) = &get_domain_dns_records_and_file($d);
$file || &error($recs);
$chroot_relative_file = $file;
$file = &bind8::make_chroot($file);
$olderr = &validate_dns($d, $recs);

# Update the file with entered records
$temp = &transname();
&copy_source_dest($file, $temp);
&open_tempfile(FILE, ">$file");
&print_tempfile(FILE, $in{'data'});
&close_tempfile(FILE);

# Re-read the file and re-validate
$recs = [ &bind8::read_zone_file($chroot_relative_file, $d->{'dom'}) ];
&set_record_ids($recs);
$err = &validate_dns($d, $recs);
if ($in{'validate'} && $err && !$olderr) {
	# Undo over-write
	&copy_source_dest($temp, $file);
	&error(&text('mrecords_evalidate', $err));
	}

# Save records
&post_records_change($d, $recs, $file);
&release_lock_dns($d);
&reload_bind_records($d);
&run_post_actions_silently();
&webmin_log("manual", "records", $d->{'dom'},
	    { 'count' => scalar(@$recs) });
&redirect("list_records.cgi?dom=$in{'dom'}");

