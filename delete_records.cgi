#!/usr/local/bin/perl
# Delete some records from a zone

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($text{'records_derr'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_records($d) || &error($text{'records_ecannot'});
&require_bind();

if ($in{'delete'}) {
	# Deleting selected records
	@d = split(/\0/, $in{'d'});
	@d || &error($text{'records_enone'});
	&obtain_lock_dns($d);
	&pre_records_change($d);
	($recs, $file) = &get_domain_dns_records_and_file($d);
	$file || &error($recs);
	foreach $r (reverse(@$recs)) {
		if (&indexof($r->{'id'}, @d) >= 0) {
			&can_delete_record($d, $r) ||
				&error(&text('records_edelete', $r->{'name'}));
			&delete_dns_record($recs, $file, $r);
			}
		}
	$err = &post_records_change($d, $recs, $file);
	&release_lock_dns($d);
	&reload_bind_records($d);
	&run_post_actions_silently();
	&webmin_log("delete", "records", $d->{'dom'},
		    { 'count' => scalar(@d) });
	&error(&text('records_epost', $err)) if ($err);
	&redirect("list_records.cgi?dom=$in{'dom'}&show=$in{'show'}");
	}
elsif ($in{'manual'}) {
	# Redirect to manual DNS form
	&redirect("manual_records.cgi?dom=$in{'dom'}&type=$in{'type'}&show=$in{'show'}");
	}
elsif ($in{'reset'}) {
	# Redirect to reset form
	&redirect("reset_features.cgi?server=$in{'dom'}&features=dns");
	}
else {
	# Redirect to add form for selected type
	&redirect("edit_record.cgi?dom=$in{'dom'}&type=$in{'type'}&show=$in{'show'}");
	}

