#!/usr/local/bin/perl
# Display all custom fields for domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newfields_ecannot'});
&ui_print_header(undef, $text{'newfields_title'}, "", "custom_fields");

print "$text{'newfields_descr'}<p>\n";

@fields = &list_custom_fields();
print &ui_form_start("save_newfields.cgi", "post");
print &ui_columns_start([ $text{'newfields_name'},
			  $text{'newfields_desc'},
			  $text{'newfields_type'} ]);
$i = 0;
foreach $f (@fields, { }, { }) {
	print &ui_columns_row([
		&ui_textbox("name_$i", $f->{'name'}, 15),
		&ui_textbox("desc_$i", $f->{'desc'}, 45),
		&ui_select("type_$i", $f->{'type'},
			   [ map { [ $_, $text{'newfields_type'.$_} ] } (0 .. 10) ]).
		&ui_textbox("opts_$i", $f->{'opts'}, 25)
			]);
	$i++;	
	}
close(FIELDS);
print &ui_columns_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

