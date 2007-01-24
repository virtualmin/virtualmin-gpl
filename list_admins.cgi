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

@admins = &list_extra_admins($d);
if (@admins) {
	print &ui_form_start("delete_admins.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_links_row(\@links);
	@tds = ( "width=5" );
	print &ui_columns_start([
		"", $text{'admins_name'},
		$text{'admins_desc'}
		], \@tds);
	foreach $a (sort { $a->{'name'} cmp $b->{'name'} } @admins) {
		print &ui_checked_columns_row([
			"<a href='edit_admin.cgi?dom=$in{'dom'}&name=".
			&urlize($a->{'name'})."'>".$a->{'name'}."</a>",
			$a->{'desc'}
			], \@tds, "d", $a->{'name'});
		}
	print &ui_columns_end();
	print &ui_links_row(\@links);
	print &ui_form_end([ [ "delete", $text{'admins_delete'} ] ]);
	}
else {
	print "<b>$text{'admins_none'}</b><p>\n";
	print &ui_links_row([ $links[2] ]);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
