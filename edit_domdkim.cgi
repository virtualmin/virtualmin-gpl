#!/usr/local/bin/perl
# Show per-domain DKIM key

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_mail() || &error($text{'edit_ecannot'});
&require_mail();

&ui_print_header(&domain_in($d), $text{'domdkim_title'}, "", "domdkim");

print &ui_form_start("save_domdkim.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'domdkim_header'}, undef, 2);

$key = &get_domain_dkim_key($d);
print &ui_table_row($text{'domdkim_key'},
	&ui_radio("key_def", $key ? 0 : 1,
		  [ [ 1, $text{'domdkim_key1'} ],
		    [ 0, $text{'domdkim_key0'} ] ])."<br>\n".
	&ui_textarea("key", $key, 10, 60));

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


