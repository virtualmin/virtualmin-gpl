#!/usr/local/bin/perl
# Show SPF settings for this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_spf($d) || &error($text{'spf_ecannot'});

&ui_print_header(&domain_in($d), $text{'spf_title'}, "", "spf");

print &ui_form_start("save_spf.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
@tds = ( "width=30%" );
print &ui_table_start($text{'spf_header'}, "width=100%", 2, \@tds);

# SPF enabled
$spf = &get_domain_spf($d);
$defspf = &default_domain_spf($d);
print &ui_table_row(&hlink($text{'spf_enabled'}, 'spf_enabled'),
		    &ui_yesno_radio("enabled", $spf ? 1 : 0));

# Extra a, mx and ip4
$edspf = $spf || $defspf;
foreach $t ('a', 'mx', 'ip4', 'ip6', 'include') {
	print &ui_table_row(&hlink($text{'spf_'.$t}, 'spf_'.$t),
		&ui_textarea('extra_'.$t,
			     join("\n", @{$edspf->{$t.':'}}), 3, 40));
	}

# All mode
print &ui_table_row(&hlink($text{'spf_all'}, 'spf_all'),
		    &ui_select("all", $edspf->{'all'},
			       [ [ '', "&lt;$text{'default'}&gt;" ],
				 [ 3, $text{'spf_all3'} ],
			         [ 2, $text{'spf_all2'} ],
			         [ 1, $text{'spf_all1'} ],
			         [ 0, $text{'spf_all0'} ] ]));

# DMARC enabled
$dmarc = &get_domain_dmarc($d);
$defdmarc = &default_domain_dmarc($d);
print &ui_table_row(&hlink($text{'spf_denabled'}, 'spf_denabled'),
		    &ui_yesno_radio("denabled", $dmarc ? 1 : 0));

# DMARC policy
$eddmarc = $dmarc || $defdmarc;
print &ui_table_row(&hlink($text{'spf_dp'}, 'spf_dp'),
	&ui_select("dp", $eddmarc->{'p'},
		  [ [ "none", $text{'tmpl_dmarcnone'} ],
		    [ "quarantine", $text{'tmpl_dmarcquar'} ],
		    [ "reject", $text{'tmpl_dmarcreject'} ] ]));

# DMARC percent
print &ui_table_row(&hlink($text{'spf_dpct'}, 'spf_dpct'),
	&ui_textbox("dpct", $eddmarc->{'pct'} || 100, 5)."%");

# DNSSEC enabled
&require_bind();
if (defined(&bind8::supports_dnssec) && &bind8::supports_dnssec() &&
    &can_domain_dnssec($d)) {
	$key = &bind8::get_dnssec_key(&get_bind_zone($d->{'dom'}));
	print &ui_table_row(&hlink($text{'spf_dnssec'}, 'spf_dnssec'),
			    &ui_yesno_radio("dnssec", $key ? 1 : 0));
	}

print &ui_table_end();

# DNSSEC key details
if ($key) {
	print &ui_hidden_table_start($text{'spf_header2'}, "width=100%",
				     2, "dnssec", 0, \@tds);
	print &ui_table_row($text{'spf_public'},
		&ui_textarea("keyline", $key->{'publictext'}, 4, 80,
			     "off", 0, "readonly"));
	print &ui_table_row($text{'spf_private'},
		&ui_textarea("private", $key->{'privatetext'}, 14, 80,
			     "off", 0, "readonly"));
	$dsrecs = &get_domain_dnssec_ds_records($d);
	if (ref($dsrecs)) {
		$dsrecstext = &dns_records_to_text(@$dsrecs);
		$dsrecsbox = &ui_textarea("dsrecs", $dsrecstext, 2, 80,
					  "off", 0, "readonly");
		}
	else {
		$dsrecsbox = &text('spf_edsrecs', $dsrecs);
		}
	print &ui_table_row($text{'spf_dsrecs'},
		$dsrecsbox);
	print &ui_hidden_table_end();
	}

print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


