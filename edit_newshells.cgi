#!/usr/local/bin/perl
# Show a form for entering custom shells

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newshells_ecannot'});
&ui_print_header(undef, $text{'newshells_title'}, "", "newshells");

print $text{'newshells_descr'},"<p>\n";

# Find available shells
@shells = &list_available_shells();
$i = 0;
@fields = ( );
foreach $s (@shells) {
	push(@fields, "shell_$i", "desc_$i", "owner_$i", "mailbox_$i",
		      "reseller_$i", "default_$i", "avail_$i");
	$i++;
	}
print &ui_form_start("save_newshells.cgi", "post");

# Use defaults?
print "<b>$text{'newshells_defs'}</b>\n";
$defs = -r $custom_shells_file ? 0 : 1;
$js1 = &js_disable_inputs(\@fields, [ ], "onClick");
$js0 = &js_disable_inputs([ ], \@fields, "onClick");
print &ui_radio("defs", $defs,
		[ [ 1, $text{'newshells_defs1'}, $js1 ],
		  [ 0, $text{'newshells_defs0'}, $js0 ] ]),"<p>\n";

# Build custom shells table rows
$i = 0;
foreach $s (@shells, { }) {
	push(@table, [
		{ 'type' => 'checkbox', 'name' => "avail_$i",
		  'value' => 1, 'checked' => $s->{'avail'},
		  'disabled' => $defs },
		&ui_textbox("shell_$i", $s->{'shell'}, 25, $defs),
		&ui_textbox("desc_$i", $s->{'desc'}, 40, $defs),
		&ui_checkbox("owner_$i", 1, " ", $s->{'owner'}, undef, $defs),
		&ui_checkbox("mailbox_$i", 1, " ", $s->{'mailbox'},
			     undef, $defs),
		&ui_checkbox("reseller_$i", 1, " ", $s->{'reseller'},
			     undef, $defs),
		&ui_checkbox("default_$i", 1, " ", $s->{'default'},
			     undef, $defs),
		&ui_select("id_$i", $s->{'id'},
			   [ [ 'nologin', $text{'limits_shell_nologin'} ],
			     [ 'ftp', $text{'limits_shell_ftp'} ],
			     [ 'ssh', $text{'limits_shell_ssh'} ] ]),
		]);
	$i++;
	}

# Render the table
print &ui_columns_table(
	[ $text{'newshells_avail'}, $text{'newshells_shell'},
	  $text{'newshells_desc'}, $text{'newshells_owner'},
	  $text{'newshells_mailbox'}, $text{'newshells_reseller'},
	  $text{'newshells_default'}, $text{'newshells_id'}, ],
	100,
	\@table,
	undef,
	1);

print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

