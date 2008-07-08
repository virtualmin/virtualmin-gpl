#!/usr/local/bin/perl
# Show SPF settings for this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'spf_title'}, "", "spf");

print &ui_form_start("save_spf.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'spf_header'}, undef, 2);

# SPF enabled
$spf = &get_domain_spf($d);
$defspf = &default_domain_spf($d);
print &ui_table_row(&hlink($text{'spf_enabled'}, 'spf_enabled'),
		    &ui_yesno_radio("enabled", $spf ? 1 : 0));

# Extra a, mx and ip4
$edspf = $spf || $defspf;
foreach $t ('a', 'mx', 'ip4', 'include') {
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

print &ui_table_hr();

# IP address for DNS
print &ui_table_row(&hlink($text{'spf_dnsip'}, 'dns_ip'),
		    &ui_opt_textbox("dns_ip", $d->{'dns_ip'}, 20,
				    &text('spf_default', $d->{'ip'})));

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


