#!/usr/local/bin/perl
# cert_form.cgi
# Show a form for requesting a CSR, or installing a cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin", "webmin-lib.pl");
&ui_print_header(&domain_in($d), $text{'cert_title'}, "");
@cert_attributes = ('cn', 'o', 'issuer_cn', 'issuer_o', 'notafter', 'type');

# Show tabs
$prog = "cert_form.cgi?d=$in{'dom'}&mode=";
@tabs = ( [ "current", $text{'cert_tabcurrent'}, $prog."current" ],
	  [ "csr", $text{'cert_tabcsr'}, $prog."csr" ],
	  [ "new", $text{'cert_tabnew'}, $prog."new" ],
	  [ "chain", $text{'cert_tabchain'}, $prog."new" ],
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "current", 1);

# Details of current cert
print &ui_tabs_start_tab("mode", "current");
print "$text{'cert_desc2'}<p>\n";
print &ui_table_start($text{'cert_header2'}, undef, 4);
$info = &cert_info($d);
foreach $i (@cert_attributes) {
	if ($info->{$i}) {
		print &ui_table_row($text{'cert_'.$i}, $info->{$i});
		}
	}
@dlinks = (
	"<a href='download_cert.cgi/cert.pem?dom=$in{'dom'}'>".
	"$text{'cert_pem'}</a>",
	"<a href='download_cert.cgi/cert.p12?dom=$in{'dom'}'>".
	"$text{'cert_pkcs12'}</a>",
	);
print &ui_table_row($text{'cert_download'}, &ui_links_row(\@dlinks));
print &ui_table_end();
print &ui_tabs_end_tab();

# CSR generation form
print &ui_tabs_start_tab("mode", "csr");
print "$text{'cert_desc1'}<br>\n";
print "$text{'cert_desc4'}<p>\n";

# Show warning if there is a CSR outstanding
if ($d->{'ssl_csr'} && -r $d->{'ssl_csr'}) {
	print "<b>",&text('cert_csrwarn', "<tt>$d->{'ssl_csr'}</tt>",
			  "<tt>$d->{'ssl_newkey'}</tt>"),"</b><p>\n";
	}

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
		    &ui_opt_textbox("size", $config{'key_size'}, 6,
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

# CA certificate form
$chain = &get_chained_certificate_file($d);
print &ui_tabs_start_tab("mode", "chain");
print "$text{'cert_desc5'}<p>\n";

print &ui_form_start("newchain.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header4'}, undef, 2);

# Where cert is stored
# XXX if changed by regular user, force to home dir
print &ui_table_row($text{'cert_chain'},
	&ui_radio("mode", $chain ? 1 : 0,
	  [ [ 0, $text{'cert_chain0'}."<br>" ],
	    &can_chained_cert_path() ?
		  ( [ 1, &text('cert_chain1',
			       &ui_textbox("file", $chain, 50)." ".
			       &file_chooser_button("file"))."<br>" ] ) :
	    $chain ? ( [ 1, &text('cert_chain1', "<tt>$chain</tt>")."<br>" ] ) :
		     ( ),
	    [ 2, &text('cert_chain2',
		       &ui_upload("upload", 50)) ] ]));

# Current details
if ($chain) {
	$info = &cert_file_info($chain);
	foreach $i (@cert_attributes) {
		if ($info->{$i}) {
			print &ui_table_row($text{'cert_c'.$i} ||
					    $text{'cert_'.$i}, $info->{$i});
			}
		}
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_chainok'} ] ]);
print &ui_tabs_end_tab();

print &ui_tabs_end(1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

