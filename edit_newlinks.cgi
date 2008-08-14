#!/usr/local/bin/perl
# Display all custom links for domains, and link categories

require './virtual-server-lib.pl';
&ReadParse();
&can_edit_templates() || &error($text{'newlinks_ecannot'});
&ui_print_header(undef, $text{'newlinks_title'}, "", "custom_links");
@tmpls = &list_templates();
@ctmpls = grep { !$_->{'standard'} } @tmpls;

# Make the table data
@links = &list_custom_links();
@cats = &list_custom_link_categories();
print &ui_form_start("save_newlinks.cgi", "post");
$i = 0;
@table = ( );
foreach $l (@links) {
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
	push(@table, [
		"<a href='edit_link.cgi?idx=$i'>".
		  $l->{'desc'}."</a>",
		$l->{'url'},
		$l->{'open'} ? $text{'newlinks_same'} : $text{'newlinks_new'},
		join(", ", map { $text{'newlinks_'.$_} }
			      grep { $l->{'who'}->{$_} }
				   ('master', 'domain', 'reseller') ),
		@links > 1 ? ( $updown ) : ( ),
		]);
	$i++;	
	}

# Generate the table
print &ui_form_columns_table(
	undef,
	undef,
	0,
	[ [ "edit_link.cgi?new=1", $text{'newlinks_add'} ] ],
	undef,
	[ $text{'newlinks_desc'}, $text{'newlinks_url'},
	  $text{'newlinks_open'}, $text{'newlinks_who'},
	  @links > 1 ? ( $text{'newlinks_move'} ) : ( ), ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'newlinks_none'},
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
local ($desc, $max) = @_;
$max ||= 12;
if (length($desc) > $max) {
	return substr($desc, 0, $max-2)."...";
	}
return $desc;
}

