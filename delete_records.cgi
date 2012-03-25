#!/usr/local/bin/perl
# Delete some records from a zone

require './virtual-server-lib.pl';
&ReadParse();
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
	($recs, $file) = &get_domain_dns_records_and_file($d);
	$file || &error($recs);
	foreach $r (reverse(@$recs)) {
		if (&indexof($r->{'id'}, @d) >= 0) {
			&can_delete_record($d, $r) ||
				&error(&text('records_edelete', $r->{'name'}));
			if ($r->{'defttl'}) {
				# Delete the TTL, renumber others down so that
				# bumping the SOA modifies the correct line
				&bind8::delete_defttl($file, $r);
				foreach my $e (@$recs) {
					$e->{'line'}--
					  if ($e->{'line'} > $r->{'line'});
					$e->{'eline'}--
					  if (defined($e->{'eline'}) &&
					      $e->{'eline'} > $r->{'line'});
					}
				}
			else {
				# Delete the record
				&bind8::delete_record($file, $r);
				}
			}
		}
	$err = &post_records_change($d, $recs, $file);
	&release_lock_dns($d);
	&reload_bind_records($d);
	&run_post_actions_silently();
	&webmin_log("delete", "records", $d->{'dom'},
		    { 'count' => scalar(@d) });
	&error(&text('records_epost', $err)) if ($err);
	&redirect("list_records.cgi?dom=$in{'dom'}");
	}
elsif ($in{'manual'}) {
	# Redirect to manual DNS form
	&redirect("manual_records.cgi?dom=$in{'dom'}&type=$in{'type'}");
	}
else {
	# Redirect to add form for selected type
	&redirect("edit_record.cgi?dom=$in{'dom'}&type=$in{'type'}");
	}

