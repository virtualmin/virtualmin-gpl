#!/usr/local/bin/perl
# Display aliases and redirects in some domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
&ui_print_header(&domain_in($d), $text{'redirects_title'}, "", "redirects");

# Build table data
@redirects = map { &remove_wellknown_redirect($_) } &list_redirects($d);
foreach $r (@redirects) {
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $r->{'id'} },
		"<a href='edit_redirect.cgi?dom=$in{'dom'}&".
		  "id=$r->{'id'}'>$r->{'path'}</a>",
		$r->{'alias'} ? $text{'redirects_alias'}
			      : $text{'redirects_redirect'},
		$r->{'dest'},
		]);
	}

# Generate the table
print &ui_form_columns_table(
	"delete_redirects.cgi",
	[ [ undef, $text{'redirects_delete'} ] ],
	1,
	[ [ "edit_redirect.cgi?new=1&dom=$in{'dom'}",
	    $text{'redirects_add'} ] ],
	[ [ "dom", $in{'dom'} ] ],
	[ "", $text{'redirects_path'},
          $text{'redirects_type'},
          $text{'redirects_dest'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'redirects_none'},
	);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
