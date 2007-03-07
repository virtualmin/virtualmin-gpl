#!/usr/local/bin/perl
# cert_form.cgi
# Show a form for requesting a CSR, or installing a cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin", "webmin-lib.pl");
&ui_print_header(&domain_in($d), $text{'cert_title'}, "");

# Show tabs
$prog = "cert_form.cgi?d=$in{'dom'}&mode=";
@tabs = ( [ "current", $text{'cert_tabcurrent'}, $prog."current" ],
	  [ "csr", $text{'cert_tabcsr'}, $prog."csr" ],
	  [ "new", $text{'cert_tabnew'}, $prog."new" ],
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "current", 1);

# Details of current cert
print &ui_tabs_start_tab("mode", "current");
print "$text{'cert_desc2'}<p>\n";
print &ui_table_start($text{'cert_header2'}, undef, 4);
$info = &cert_info($d);
foreach $i ('cn', 'o', 'issuer_cn', 'issuer_o', 'notafter', 'type') {
	if ($info->{$i}) {
		print &ui_table_row($text{'cert_'.$i}, $info->{$i});
		}
	}
print &ui_table_end();
print &ui_tabs_end_tab();

# CSR generation form
print &ui_tabs_start_tab("mode", "csr");
print "$text{'cert_desc1'}<br>\n";
print "$text{'cert_desc4'}<p>\n";

print &ui_form_start("csr.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header1'}, undef, 2);

print &ui_table_row($webmin::text{'ssl_cn'},
		    &ui_textbox("commonName", "www.$d->{'dom'}", 30));

print &ui_table_row($webmin::text{'ca_email'},
		    &ui_textbox("emailAddress", $d->{'emailto'}, 30));

print &ui_table_row($webmin::text{'ca_ou'},
		    &ui_textbox("organizationalUnitName", undef, 30));

print &ui_table_row($webmin::text{'ca_o'},
		    &ui_textbox("organizationName", $d->{'owner'}, 30));

print &ui_table_row($webmin::text{'ca_city'} || $text{'cert_city'},
		    &ui_textbox("cityName", undef, 30));

print &ui_table_row($webmin::text{'ca_sp'},
		    &ui_textbox("stateOrProvinceName", undef, 15));

print &ui_table_row($webmin::text{'ca_c'},
		    &ui_textbox("countryName", undef, 2));

print &ui_table_row($webmin::text{'ssl_size'},
		    &ui_opt_textbox("size", undef, 6,
				    "$text{'default'} ($webmin::default_key_size)").
			" ".$text{'ssl_bits'});

print &ui_table_row($webmin::text{'ssl_days'},
		    &ui_textbox("days", 1825, 8));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_csrok'} ],
		     [ "self", $text{'cert_self'} ] ]);
print &ui_tabs_end_tab();

# New key and cert form
print &ui_tabs_start_tab("mode", "new");
print "$text{'cert_desc3'}<p>\n";

print &ui_form_start("newkey.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header3'}, undef, 2);

print &ui_table_row($text{'cert_cert'},
		    &ui_textarea("cert", undef, 8, 70)."<br>\n".
		    "<b>$text{'cert_upload'}</b>\n".
		    &ui_upload("certupload"));

if (-r $d->{'ssl_newkey'}) {
	$newkey = &read_file_contents($d->{'ssl_newkey'});
	}
print &ui_table_row($text{'cert_newkey'},
		    &ui_textarea("newkey", $newkey, 8, 70)."<br>\n".
		    "<b>$text{'cert_upload'}</b>\n".
		    &ui_upload("newkeyupload"));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

print &ui_tabs_end();

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

