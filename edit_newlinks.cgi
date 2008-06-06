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

# Make the table data
@links = &list_custom_links();
@cats = &list_custom_link_categories();
print &ui_form_start("save_newlinks.cgi", "post");
$i = 0;
@table = ( );
$spacer = "<img src=images/gap.gif>";
foreach $l (@links, { }, { }) {
	$updown = "";
	if (%$l) {
		# Create move up / down links
		$updown = &ui_up_down_arrows(
			"move_newlinks.cgi?idx=$i&up=1",
			"move_newlinks.cgi?idx=$i&down=1",
			$l ne $links[0],
			$l ne $links[@links-1],
			);
		}
	$catsel = &ui_select("cat_$i", $l->{'cat'},
	    [ [ "", $text{'newlinks_nocat'} ],
	      map { [ $_->{'id'}, &shorten_category($_->{'desc'}) ] } @cats ]);
	push(@table, [
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
		]);
	$i++;	
	}

# Generate the table
print ui_form_columns_table(
	"save_newlinks.cgi",
	[ [ "save", $text{'save'} ] ],
	0,
	undef,
	undef,
	[ $text{'newlinks_desc'}, $text{'newlinks_url'},
	  $text{'newlinks_open'}, $text{'newlinks_who'},
	  @cats ? ( $text{'newlinks_cat'} ) : ( ),
	  @links > 1 ? ( $text{'newlinks_move'} ) : ( ), ],
	100,
	\@table,
	1,
	);

print &ui_hr();

# Show link category form
print "$text{'newlinks_catdesc'}<p>\n";
$i = 0;
@table = ( );
@hiddens = ( );
foreach $c (@cats, { }, { }) {
	push(@table, [ &ui_textbox("desc_$i", $c->{'desc'}, 50,
			 	   0, undef, "style='width:100%'") ]);
	push(@hiddens, [ "id_$i", $c->{'id'} ]);
	$i++;
	}
print &ui_form_columns_table(
	"save_linkcats.cgi",
	[ [ undef, $text{'save'} ] ],
	0,
	undef,
	\@hiddens,
	[ $text{'newlinks_catname'} ],
	undef,
	\@table,
	undef,
	1);

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

