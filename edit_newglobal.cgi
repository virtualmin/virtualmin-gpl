#!/usr/local/bin/perl
# Show a list of global template variables

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newglobal_ecannot'});
&ui_print_header(undef, $text{'newglobal_title'}, "", "newglobal");

print $text{'newglobal_desc'},"<p>\n";

# Build table of global variables
@vars = &get_global_template_variables();
$i = 0;
@table = ( );
foreach $v (@vars, { 'enabled' => 1 }) {
	push(@table, [
		{ 'type' => 'checkbox', 'name' => "enabled_$i",
		  'value' => 1,
		  'checked' => $v->{'enabled'} },
		&ui_textbox("name_$i", $v->{'name'}, 30, 0, undef,
			    "style=width:100%"),
		&ui_textbox("value_$i", $v->{'value'}, 50, 0, undef,
			    "style=width:100%"),
		]);
	$i++;
	}

# Output the table and form
print &ui_form_columns_table(
	"save_newglobal.cgi",
	[ [ undef, $text{'save'} ] ],
	0,
	undef,
	undef,
	[ $text{'newglobal_enabled'}, $text{'newglobal_name'},
	  $text{'newglobal_value'} ],
	100,
	\@table,
	undef,
	1,
	);

&ui_print_footer("", $text{'index_return'});
