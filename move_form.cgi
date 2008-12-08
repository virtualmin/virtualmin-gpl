#!/usr/local/bin/perl
# Display server re-parent form

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_move_domain($d) || &error($text{'move_ecannot'});
&ui_print_header(&domain_in($d), $text{'move_title'}, "", "move");

if (!$d->{'parent'}) {
	print "$text{'move_desc'}<p>\n";
	}
else {
	print "$text{'move_desc2'}<p>\n";
	}
print &ui_form_start("move.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'move_header'}, "width=100%", 2);

# Domain being moved
print &ui_table_row($text{'move_dom'},
	"<tt>".&show_domain_name($d)."</tt>");

# New parent
@pdoms = sort { lc($a->{'dom'}) cmp lc($b->{'dom'}) }
		grep { !$_->{'parent'} && &can_config_domain($_) }
	      &list_domains();
if ($d->{'parent'}) {
	@pdoms = grep { $_->{'id'} ne $d->{'parent'} } @pdoms;
	}
else {
	@pdoms = grep { $_->{'id'} ne $d->{'id'} } @pdoms;
	}
print &ui_table_row($text{'move_target'},
		    &ui_select("parent", undef,
			[ $d->{'parent'} ? ( [ 0, $text{'move_up'} ] ) : ( ),
			  map { [ $_->{'id'}, $_->{'dom'} ] } @pdoms ]));

# Options for making a new parent domain
if ($d->{'parent'}) {
	print &ui_table_row($text{'move_newuser'},
		&ui_textbox("newuser", $d->{'user'}, 20));

	print &ui_table_row($text{'move_newpass'},
		&ui_password("newpass", $d->{'pass'}, 20));
	}

print &ui_table_end();
print &ui_form_end([ [ "move", $text{'move_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
