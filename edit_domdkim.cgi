#!/usr/local/bin/perl
# Show per-domain DKIM key

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_mail() || &error($text{'edit_ecannot'});
$dkim = &get_dkim_config();
$dkim && $dkim->{'enabled'} ||  &error($text{'domdkim_enabled'});
&require_mail();

&ui_print_header(&domain_in($d), $text{'domdkim_title'}, "", "domdkim");

print &ui_form_start("save_domdkim.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'domdkim_header'}, undef, 2);

$keyfile = &get_domain_dkim_key($d);
$key = $keyfile ? &read_file_contents($keyfile) : undef;
$privkeyglob = &get_dkim_privkey($dkim);
print &ui_table_row($text{'domdkim_key'},
	&ui_radio("key_def", $key ? 0 : 1,
		  [ [ 1, $text{'domdkim_key1'}, 'onclick="dkimstate(1,1,0,0)"' ],
		    [ 2, $text{'domdkim_key2'}, 'onclick="dkimstate(2,1,1,1)"' ],
		    [ 0, $text{'domdkim_key0'}, 'onclick="dkimstate(0,0,0,0)"' ] ])."<br>\n".
	&ui_textarea("key", $key || $privkeyglob, 20, 80, undef, undef, !$key && "readonly=true"));

$pubkey = &get_dkim_pubkey($dkim, $d);
print &ui_table_row($text{'dkim_pubkeypem'},
	&ui_textarea("pubkey", $pubkey, 8, 60, "hard",
		     undef, "readonly=true"));

$dnskey = &get_dkim_dns_pubkey($dkim, $d);
$records = $dkim->{'selector'}."._domainkey IN TXT ".
	   &split_long_txt_record("\"v=DKIM1; k=rsa; t=s; p=$dnskey\"");
print &ui_table_row($text{'domdkim_records'},
	&ui_textarea("records", $records, 4, 80, "off",
		     undef, "readonly=true"));

print "<script>";
print 'function dkimstate(e,t,s,r){var d=document.querySelector(\'[name="key"]\'),o=document.querySelector(\'[name="pubkey"]\'),a=document.querySelector(\'[name="records"]\');s=s?"line-through":"none",[d,o,a].forEach(function(e){e.style.setProperty("text-decoration",s),"none"===s?e.classList.remove("disabled"):e.classList.add("disabled")}),0===e?(d.removeAttribute("readonly"),d.classList.remove("disabled")):2===e?(d.setAttribute("readonly",!0),d.classList.add("disabled")):1===e&&(d.setAttribute("readonly",!0),d.classList.remove("disabled"))}';
print "</script>";

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


