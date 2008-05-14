#!/usr/local/bin/perl
# Display all custom links for domains

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newlinks_ecannot'});
&ui_print_header(undef, $text{'newlinks_title'}, "", "custom_links");

print &ui_hidden_start($text{'newuser_docs'}, "docs", 0);
print "$text{'newlinks_descr'}<p>\n";
&print_subs_table("DOM", "IP", "USER", "EMAILTO");
print &ui_hidden_end(),"<p>\n";

@links = &list_custom_links();
@cats = &list_custom_link_categories();
@tds = ( undef, undef, undef, undef, "width=32" );
print &ui_form_start("save_newlinks.cgi", "post");
print &ui_columns_start([ $text{'newlinks_desc'},
			  $text{'newlinks_url'},
			  $text{'newlinks_open'},
			  $text{'newlinks_who'},
			  @cats ? ( $text{'newlinks_cat'} ) : ( ),
			  @links > 1 ? ( $text{'newlinks_move'} ) : ( ), ],
			100, 0, \@tds);
$i = 0;
$spacer = "<img src=images/gap.gif>";
foreach $l (@links, { }, { }) {
	$updown = "";
	if (%$l) {
		# Create move up / down links
		if ($l eq $links[@links-1]) {
			$updown .= $spacer;
			}
		else {
			$updown .= "<a href='move_newlinks.cgi?idx=$i&down=1'>".
				   "<img src=images/movedown.gif border=0></a>";
			}
		if ($l eq $links[0]) {
			$updown .= $spacer;
			}
		else {
			$updown .= "<a href='move_newlinks.cgi?idx=$i&up=1'>".
				   "<img src=images/moveup.gif border=0></a>";
			}
		}
	$catsel = &ui_select("cat_$i", $l->{'cat'},
	    [ [ "", $text{'newlinks_nocat'} ],
	      map { [ $_->{'id'}, &shorten_category($_->{'desc'}) ] } @cats ]);
	print &ui_columns_row([
		&ui_textbox("desc_$i", $l->{'desc'}, 20),
		&ui_textbox("url_$i", $l->{'url'}, 60),
		&ui_radio("open_$i", int($l->{'open'}),
			  [ [ 0, $text{'newlinks_same'} ],
			    [ 1, $text{'newlinks_new'} ] ]),
		join(" ", map { &ui_checkbox("who_$i", $_,
				$text{'newlinks_'.$_}, $l->{'who'}->{$_}) }
			      ('master', 'domain', 'reseller')),
		@cats ? ( $catsel ) : ( ),
		@links > 1 ? ( $updown ) : ( ),
		], \@tds);
	$i++;	
	}
print &ui_columns_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

# Show link category form
print &virtualmin_ui_hr();

print "$text{'newlinks_catdesc'}<p>\n";
print &ui_form_start("save_linkcats.cgi", "post");
print &ui_columns_start([ $text{'newlinks_catname'} ]);
$i = 0;
foreach $c (@cats, { }, { }) {
	print &ui_columns_row([ &ui_textbox("desc_$i", $c->{'desc'}, 50).
				&ui_hidden("id_$i", $c->{'id'}) ]);
	$i++;
	}
print &ui_form_end([ [ undef, $text{'save'} ] ]);

if ($in{'refresh'}) {
	# Update left frame after changing custom links
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}

&ui_print_footer("", $text{'index_return'});

sub shorten_category
{
local ($desc) = @_;
if (length($desc) > 12) {
	return substr($desc, 0, 10)."...";
	}
return $desc;
}

