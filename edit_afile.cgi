#!/usr/local/bin/perl
# edit_afile.cgi
# Display the contents of an address file

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'afile_ecannot'});

&ui_print_header(undef, $text{'afile_title'}, "");

if (-e $in{'file'}) {
	&open_readfile_as_domain_user($d, FILE, $in{'file'}) ||
		&error(&text('afile_eread', $in{'file'}, $d->{'user'}, $!));
	@lines = <FILE>;
	&close_readfile_as_domain_user($d, FILE);
	}

print "<b>",&text('afile_desc', "<tt>$in{'file'}</tt>"),"</b><p>\n";

$what = $in{'alias'} ? 'alias' : 'user';
print &ui_form_start("save_afile.cgi", "form-data");
print &ui_hidden("file", $in{'file'});
print &ui_hidden($what, $in{$what});
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start(undef, undef, 2);
print &ui_table_row(undef,
	&ui_textarea("text", join("", @lines), 20, 80), 2);
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("edit_$what.cgi?dom=$in{'dom'}&$what=$in{$what}&unix=1",
		 $text{$what.'_return'});

