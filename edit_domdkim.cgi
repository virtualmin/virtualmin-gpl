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
print &ui_table_row($text{'domdkim_key'},
	&ui_radio("key_def", $key ? 0 : 1,
		  [ [ 1, $text{'domdkim_key1'} ],
		    [ 2, $text{'domdkim_key2'} ],
		    [ 0, $text{'domdkim_key0'} ] ])."<br>\n".
	&ui_textarea("key", $key, 20, 80));

if ($keyfile) {
	$pubkey = &get_dkim_pubkey($dkim, $d);
	$records = $dkim->{'selector'}."._domainkey IN TXT ".
		   &split_long_txt_record("\"v=DKIM1; k=rsa; t=s; p=$pubkey\"");
	print &ui_table_row($text{'dkim_records'},
		&ui_textarea("records", $records, 4, 80, "off",
			     undef, "readonly=true"));
	}

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


