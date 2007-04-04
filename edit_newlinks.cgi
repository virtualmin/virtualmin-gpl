#!/usr/local/bin/perl
# Display all custom links for domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newlinks_ecannot'});
&ui_print_header(undef, $text{'newlinks_title'}, "", "custom_links");

print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print "$text{'newlinks_descr'}<p>\n";
&print_subs_table("DOM", "IP", "USER", "EMAILTO");
print &ui_hidden_end(),"<p>\n";

@links = &list_custom_links();
print &ui_form_start("save_newlinks.cgi", "post");
print &ui_columns_start([ $text{'newlinks_desc'},
			  $text{'newlinks_url'},
			  $text{'newlinks_open'},
			  $text{'newlinks_who'}, ]);
$i = 0;
foreach $l (@links, { }, { }) {
	print &ui_columns_row([
		&ui_textbox("desc_$i", $l->{'desc'}, 20),
		&ui_textbox("url_$i", $l->{'url'}, 60),
		&ui_radio("open_$i", int($l->{'open'}),
			  [ [ 0, $text{'newlinks_same'} ],
			    [ 1, $text{'newlinks_new'} ] ]),
		join(" ", map { &ui_checkbox("who_$i", $_,
				$text{'newlinks_'.$_}, $l->{'who'}->{$_}) }
			      ('master', 'domain', 'reseller'))
			]);
	$i++;	
	}
print &ui_columns_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

