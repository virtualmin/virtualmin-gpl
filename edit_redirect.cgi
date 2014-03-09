#!/usr/local/bin/perl
# Show a form for editing or adding a website redirect

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
if (!$in{'new'}) {
	($r) = grep { $_->{'path'} eq $in{'path'} } &list_redirects($d);
	$r || &error($text{'redirect_egone'});
	}
else {
	$r = { 'http' => 1, 'https' => 1 };
	}

&ui_print_header(&domain_in($d), $in{'new'} ? $text{'redirect_create'}
					    : $text{'redirect_edit'}, "");

print &ui_form_start("save_redirect.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("old", $in{'path'});
print &ui_table_start($text{'redirect_header'}, undef, 2);

# URL path
print &ui_table_row(&hlink($text{'redirect_path'}, 'redirect_path'),
	&ui_textbox("path", $r->{'path'}, 40));

# Destination
print &ui_table_row(&hlink($text{'redirect_dest'}, 'redirect_dest'),
	&ui_radio_table("mode", $r->{'alias'} ? 1 : 0,
		[ [ 0, $text{'redirect_url'},
		    &ui_textbox("url", $r->{'alias'} ? '' : $r->{'dest'}, 40) ],
		  [ 1, $text{'redirect_dir'},
		    &ui_textbox("dir", $r->{'alias'} ? $r->{'dest'} : '', 40) ],
		]));

# Include sub-paths
print &ui_table_row(&hlink($text{'redirect_regexp'}, 'redirect_regexp'),
	&ui_yesno_radio("regexp", $r->{'regexp'}));

# Protocols to include
if ($d->{'ssl'}) {
	print &ui_table_row(&hlink($text{'redirect_proto'}, 'redirect_proto'),
		&ui_checkbox("http", 1, $text{'redirect_http'}, $r->{'http'}).
		" ".
		&ui_checkbox("https", 1, $text{'redirect_https'}, $r->{'https'})
		);
	}
else {
	print &ui_hidden("http", 1);
	}

print &ui_table_end();
print &ui_form_end(
    $in{'new'} ? [ [ undef, $text{'create'} ] ]
    	       : [ [ undef, $text{'save'} ], [ "delete", $text{'delete'} ] ]);

&ui_print_footer("list_redirects.cgi?dom=$in{'dom'}", $text{'redirects_return'},
		 &domain_footer_link($d), "", $text{'index_return'});
