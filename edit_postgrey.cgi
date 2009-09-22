#!/usr/local/bin/perl
# Allow editing of one greylisting whitelist entry

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ReadParse();

if ($in{'new'}) {
	&ui_print_header(undef, $text{'creategrey_title'.$in{'type'}}, "");
	$d = { };
	}
else {
	&ui_print_header(undef, $text{'editgrey_title'.$in{'type'}}, "");
	$data = &list_postgrey_data($in{'type'});
	$d = $data->[$in{'index'}];
	$d || &error($text{'editgrey_gone'});
	}

# Start of form block
print &ui_form_start("save_postgrey.cgi", "post");
print &ui_hidden("type", $in{'type'});
print &ui_hidden("new", $in{'new'});
print &ui_hidden("index", $in{'index'});
print &ui_table_start($text{'editgrey_header'.$in{'type'}}, undef, 2);

# Value field
print &ui_table_row($text{'editgrey_value'.$in{'type'}},
	&ui_textbox("value", $d->{'value'}, 60)."<br>\n".
	&ui_checkbox("re", 1, $text{'editgrey_re'}, $d->{'re'}));

# Comment lines
print &ui_table_row($text{'editgrey_cmts'},
	&ui_textarea("cmts", join("\n", @{$d->{'cmts'}}), 3, 75));

# End of form block
print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("postgrey.cgi?type=".&urlize($in{'type'}),
		 $text{'postgrey_return'});
