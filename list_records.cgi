#!/usr/local/bin/perl
# Show DNS records in some zone

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_records($d) || &error($text{'records_ecannot'});
($recs, $file) = &get_domain_dns_records_and_file($d);
$file || &error($recs);

&ui_print_header(&domain_in($d), $text{'records_title'}, "", "records");

# Warn if DNS records are not valid
$err = &validate_dns($d, $recs, 1);
if ($err) {
	print ui_alert_box(&text('records_evalid', $err), 'warn');
	}

# Exclude sub-domains and parent domains
$recs = &filter_domain_dns_records($d, $recs);

# Check if we need a comment column
foreach $r (@$recs) {
	$anycomment++ if ($r->{'comment'});
	}

print &ui_form_start("delete_records.cgi");
@links = ( &select_all_link("d"), &select_invert_link("d") );
print &ui_hidden("dom", $in{'dom'});
@tds = ( "width=5" );
print &ui_links_row(\@links);
print &ui_columns_start([ "", $text{'records_name'},
			      $text{'records_type'},
			      $text{'records_value'},
			      $anycomment ? ( $text{'records_comment'} ) : ( ),
		        ], 100, 0, \@tds);

%tmap = map { $_->{'type'}, $_ } &list_dns_record_types($d);
RECORD: foreach $r (@$recs) {
	if ($r->{'defttl'}) {
		# Default TTL .. skip if in sub-domain
		next if ($d->{'dns_submode'});
		$name = '$ttl';
		$values = $r->{'defttl'};
		$tdesc = $text{'records_typedefttl'};
		$etype = 1;
		$gotttl++;
		}
	elsif ($r->{'generate'}) {
		# Record generator .. cannot edit yet
		$name = '$generate';
		$values = join(" ", @{$r->{'generate'}});
		$tdesc = $text{'records_typegenerate'};
		$etype = 0;
		}
	else {
		# Regular DNS record
		next if ($r->{'type'} eq 'DNSKEY' ||	# auto-generated DNSSEC
			 $r->{'type'} eq 'NSEC' ||
			 $r->{'type'} eq 'NSEC3' ||
			 $r->{'type'} eq 'RRSIG');

		$name = $r->{'name'};
		$name =~ s/\.$//;
		$name =~ s/\.\Q$d->{'dom'}\E//;
		$values = join(" ", @{$r->{'values'}});
		if (length($values) > 80) {
			$values = substr($values, 0, 75)." ...";
			}
		$t = $tmap{$r->{'type'}};
		$etype = $t;
		$tdesc = $t ? $t->{'type'}." - ".$t->{'desc'} : $r->{'type'};
		}
	print &ui_checked_columns_row([
		$etype && &can_edit_record($r, $d) ?
		    "<a href='edit_record.cgi?dom=$in{'dom'}&id=".
		      &urlize($r->{'id'})."'>$name</a>" :
		    $name,
		$tdesc,
		&html_escape($values),
		$anycomment ? ( &html_escape($r->{'comment'}) ) : ( ),
		], \@tds, "d", $r->{'id'}, 0, !&can_delete_record($r, $d));
	}

print &ui_columns_end();
print &ui_links_row(\@links);
@types = map { [ $_->{'type'}, $_->{'type'}." - ".$_->{'desc'} ] }
	     grep { $_->{'create'} } &list_dns_record_types($d);
if (!$gotttl) {
	push(@types, [ '$ttl', '$ttl - '.$text{'records_typedefttl'} ]);
	}
print &ui_form_end([ [ 'delete', $text{'records_delete'} ],
		     undef,
		     [ 'new', $text{'records_add'},
		       &ui_select("type", "A", \@types) ],
		     undef,
		     &can_manual_dns() ?
			( [ 'manual', $text{'records_manual'} ] ) : ( ), ]);

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
