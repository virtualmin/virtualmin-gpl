#!/usr/local/bin/perl
# Show a form for manually editing DNS records

require './virtual-server-lib.pl';
&require_bind();
&ReadParse();
&error_setup($text{'mrecords_err'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_manual_dns() || &error($text{'mrecords_ecannot'});

# Get the zone and records
($recs, $file) = &get_domain_dns_records_and_file($d);
$file || &error($recs);
$file = &bind8::make_chroot($file);
$data = &read_file_contents($file);

&ui_print_header(&domain_in($d), $text{'mrecords_title'}, "");

# Show editing form
print $text{'mrecords_desc'},"<p>\n";
print &ui_form_start("manual_records_save.cgi", "post");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start(undef, "width=100%", 2);
print &ui_table_row(undef, &ui_textarea("data", $data, 30, 80, "off",
					0, "style='width:100%'"), 2);
print &ui_table_row(undef,
	&ui_checkbox("validate", 1, $text{'mrecords_validate'}, 1));
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("list_records.cgi?dom=$in{'dom'}", $text{'records_return'},
	         &domain_footer_link($d),
		 "", $text{'index_return'});

