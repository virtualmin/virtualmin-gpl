#!/usr/local/bin/perl
# Display details of one custom link

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newlinks_ecannot'});

# Page header
if ($in{'new'}) {
	&ui_print_header(undef, $text{'elink_title1'}, "", "edit_link");
	$link = { 'who' => { 'master' => 1, 'reseller' => 1, 'domain' => 1 } };
	}
else {
	&ui_print_header(undef, $text{'elink_title2'}, "", "edit_link");
	@links = &list_custom_links();
	$link = $links[$in{'idx'}];
	}
@tmpls = &list_templates();
@cats = &list_custom_link_categories();

print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print "$text{'newlinks_descr'}<p>\n";
&print_subs_table("DOM", "IP", "USER", "EMAILTO");
print &ui_hidden_end(),"<p>\n";

# Start of link details section
print &ui_form_start("save_link.cgi", "post");
print &ui_hidden("idx", $in{'idx'});
print &ui_hidden("new", $in{'new'});
print &ui_hidden_table_start($text{'elink_header1'}, "width=100%", 2,
			     "main", 1, [ "width=30%" ]);

# Description
print &ui_table_row($text{'elink_desc'},
	&ui_textbox("desc", $link->{'desc'}, 40));

# URL template
print &ui_table_row($text{'elink_url'},
	&ui_textbox("url", $link->{'url'}, 60));

# Open mode
print &ui_table_row($text{'elink_open'},
	&ui_radio("open", int($link->{'open'}),
		  [ [ 0, $text{'newlinks_same'} ],
		    [ 1, $text{'newlinks_new'} ] ]));

# Category on menu
print &ui_table_row($text{'elink_cat'},
	&ui_select("cat", $link->{'cat'},
		   [ [ undef, $text{'newlinks_nocat'} ],
		     map { [ $_->{'id'}, $_->{'desc'} ] } @cats ]));

print &ui_hidden_table_end();

# Start of visibility section
print &ui_hidden_table_start($text{'elink_header2'}, "width=100%", 2,
			     "vis", 0, [ "width=30%" ]);

# User types
print &ui_table_row($text{'elink_who'},
	join("<br>\n", map { &ui_checkbox("who", $_,
                                $text{'newlinks_'.$_}, $link->{'who'}->{$_}) }
                           ('master', 'domain', 'reseller')));

# Templates
print &ui_table_row($text{'elink_tmpl'},
	&ui_select("tmpl", $link->{'tmpl'},
                     [ [ "", "&lt;$text{'newlinks_any'}&gt;" ],
                       map { [ $_->{'id'}, $_->{'name'} ] } @tmpls ]));

# Domains with feature
print &ui_table_row($text{'elink_feature'},
	&ui_select("feature", $link->{'feature'},
		   [ [ "", "&lt;$text{'newlinks_any'}&gt;" ],
		     (map { [ $_, $text{'feature_'.$_} ] } @features),
		     (map { [ $_, &plugin_call($_, "feature_name") ] } @plugins)
		   ]));
	

print &ui_hidden_table_end();
print &ui_form_end(
	$in{'new'} ? [ [ undef, $text{'create'} ] ]
		   : [ [ undef, $text{'save'} ], [ 'delete', $text{'delete'} ] ]
	);

&ui_print_footer("edit_newlinks.cgi", $text{'newlinks_return'});

