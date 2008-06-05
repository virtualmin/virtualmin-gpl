#!/usr/local/bin/perl
# Show all extra admins for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_admins($d) || &error($text{'admins_ecannot'});

&ui_print_header(&domain_in($d), $text{'admins_title'}, "");

@links = ( &select_all_link("d"),
	   &select_invert_link("d"),
	   "<a href='edit_admin.cgi?dom=$in{'dom'}&new=1'>$text{'admins_add'}</a>" );

# Make table data
@admins = &list_extra_admins($d);
foreach $a (sort { $a->{'name'} cmp $b->{'name'} } @admins) {
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $a->{'name'} },
		"<a href='edit_admin.cgi?dom=$in{'dom'}&name=".
		&urlize($a->{'name'})."'>".$a->{'name'}."</a>",
		$a->{'desc'}
		]);
	}

# Render the table
print &ui_form_columns_table(
	"delete_admins.cgi",
	[ [ "delete", $text{'admins_delete'} ] ],
	1,
	[ [ "edit_admin.cgi?dom=$in{'dom'}&new=1", $text{'admins_add'} ] ],
	[ [ "dom", $in{'dom'} ] ],
	[ "", $text{'admins_name'}, $text{'admins_desc'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'admins_none'},
	);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
