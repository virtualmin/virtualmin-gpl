#!/usr/local/bin/perl
# Show DNS records in some zone

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
($recs, $file) = &get_domain_dns_records_and_file($d);
$file || &error($recs);

# Find sub-domains to exclude records in
foreach $sd (&list_domains()) {
	if ($sd->{'dns_submode'} && $sd->{'id'} ne $d->{'id'} &&
	    $sd->{'dom'} =~ /\.\Q$d->{'dom'}\E$/) {
		push(@subdoms, $sd->{'dom'});
		}
	}

&ui_print_header(&domain_in($d), $text{'records_title'}, "", "records");

# Warn if DNS records are not valid
$err = &validate_dns($d);
if ($err) {
	print "<font color=red><b>",&text('records_evalid', $err),
	      "</b></font><p>\n";
	}

print &ui_form_start("delete_records.cgi");
@links = ( &select_all_link("d"), &select_invert_link("d") );
print &ui_hidden("dom", $in{'dom'});
@tds = ( "width=5" );
print &ui_links_row(\@links);
print &ui_columns_start([ "", $text{'records_name'}, $text{'records_type'},
			      $text{'records_value'} ], 100, 0, \@tds);

%tmap = map { $_->{'type'}, $_ } &list_dns_record_types($d);
RECORD: foreach $r (@$recs) {
	next if (!$r->{'name'});		# $ttl or other
	next if ($r->{'type'} eq 'DNSKEY' ||	# auto-generated DNSSEC
		 $r->{'type'} eq 'NSEC' ||
		 $r->{'type'} eq 'NSEC3');
	foreach $sname (@subdoms) {
		next RECORD if ($r->{'name'} eq $sname."." ||
				$r->{'name'} =~ /\.\Q$sname\E\.$/);
		}
	$name = $r->{'name'};
	$name =~ s/\.$//;
	$name =~ s/\.\Q$d->{'dom'}\E//;
	$values = join(" ", @{$r->{'values'}});
	if (length($values) > 80) {
		$values = substr($values, 0, 75)." ...";
		}
	$id = join("/", $r->{'name'}, $r->{'type'}, @{$r->{'values'}});
	$t = $tmap{$r->{'type'}};
	print &ui_checked_columns_row([
		$t && &can_edit_record($r, $d) ?
		    "<a href='edit_record.cgi?id=".&urlize($id)."'>$name</a>" :
		    $name,
		$t ? $t->{'type'}." - ".$t->{'desc'} : $r->{'type'},
		$values,
		], \@tds, "d", $id, 0, !&can_delete_record($r, $d));
	}

print &ui_columns_end();
print &ui_links_row(\@links);
@types = map { [ $_->{'type'}, $_->{'type'}." - ".$_->{'desc'} ] }
	     &list_dns_record_types($d);
print &ui_form_end([ [ 'delete', $text{'records_delete'} ],
		     [ 'new', $text{'records_add'},
		       &ui_select("type", "A", \@types) ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
