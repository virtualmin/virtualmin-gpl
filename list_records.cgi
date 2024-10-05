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
$readonly = &copy_alias_records($d);

$msg = &domain_in($d);
if ($d->{'provision_dns'}) {
	$msg = &text('records_provmsg', $msg);
	}
elsif ($cloud = &get_domain_dns_cloud($d)) {
	$msg = &text('records_cloudmsg', $msg, $cloud->{'desc'});
	}
&ui_print_header($msg, $text{'records_title'}, "", "records");

if ($readonly && ($alias = &get_domain($d->{'alias'}))) {
	print &ui_alert_box(&text('records_aliasof', &show_domain_name($alias)),
			    'warn');
	}

# Warn if DNS records are not valid
$err = &validate_dns($d, $recs, 1);
if ($err) {
	print ui_alert_box(&text('records_evalid', $err), 'warn');
	}

# Exclude sub-domains and parent domains
if (!$in{'show'} || $d->{'dns_submode'}) {
	$recs = &filter_domain_dns_records($d, $recs);
	}
if (!$in{'show'}) {
	$recs = &filter_generated_dns_records($d, $recs);
	}

# Check if we need a comment column
if (&supports_dns_comments($d)) {
	foreach $r (@$recs) {
		$anycomment++ if ($r->{'comment'});
		}
	}

@tds = ( "width=5" );
if (!$readonly) {
	print &ui_form_start("delete_records.cgi");
	@links = ( &select_all_link("d"), &select_invert_link("d") );
	if (!$d->{'dns_submode'}) {
		if ($in{'show'}) {
			push(@links, &ui_link(
				"list_records.cgi?dom=$in{'dom'}&show=0",
				$text{'records_show0'}));
			}
		else {
			push(@links, &ui_link(
				"list_records.cgi?dom=$in{'dom'}&show=1",
				$text{'records_show1'}));
			}
		}
	print &ui_hidden("dom", $in{'dom'});
	print &ui_links_row(\@links);
	}
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
		next if (&is_dnssec_record($r));	# auto-generated DNSSEC
		$name = $r->{'name'};
		$name =~ s/\.$//;
		$values = join(" ", @{$r->{'values'}});
		if (length($values) > 80) {
			$values = substr($values, 0, 75)." ...";
			}
		$t = $tmap{$r->{'type'}};
		$etype = $t;
		$tdesc = $t ? $t->{'type'}." - ".$t->{'desc'} : $r->{'type'};
		}
	my $pmsg = "";
	if ($r->{'type'} =~ /^(A|AAAA|CNAME)$/ && $cloud && $cloud->{'proxy'}) {
		if ($r->{'proxied'}) {
			$pmsg = "<span data-type='proxied' ".
		           	"data-text='$text{'records_typeprox'}'> ".
		                "($text{'records_typeprox'})</span>";
			}
		else {
			$pmsg = "<span data-type='not-proxied' ".
		                "data-text='$text{'records_typenoprox'}'>".
				"</span>";
			}
		}
	print &ui_checked_columns_row([
		$etype && &can_edit_record($r, $d) && !$readonly ?
		    "<a href='edit_record.cgi?dom=$in{'dom'}&id=".
		      &urlize($r->{'id'})."&show=$in{'show'}'>$name</a>" :
		    $name,
		$tdesc,
		&html_escape($values).$pmsg,
		$anycomment ? ( &html_escape($r->{'comment'}) ) : ( ),
		],
		\@tds, "d", $r->{'id'}, 0,
		$readonly || !&can_delete_record($r, $d));
	}

print &ui_columns_end();
if (!$readonly) {
	print &ui_links_row(\@links);
	@types = map { [ $_->{'type'}, $_->{'type'}." - ".$_->{'desc'} ] }
		     grep { $_->{'create'} } &list_dns_record_types($d);
	if (!$gotttl && &supports_dns_defttl($d)) {
		push(@types, [ '$ttl', '$ttl - '.$text{'records_typedefttl'} ]);
		}
	print &ui_hidden("show", $in{'show'});
	print &ui_form_end([ [ 'delete', $text{'records_delete'} ],
			     undef,
			     [ 'new', $text{'records_add'},
			       &ui_select("type", "A", \@types) ],
			     undef,
			     &can_edit_templates() ?
				( [ 'reset', $text{'records_reset'} ] ) : ( ),
			     &can_manual_dns() ?
				( [ 'manual', $text{'records_manual'} ] ) : ( ), ]);
	}

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
