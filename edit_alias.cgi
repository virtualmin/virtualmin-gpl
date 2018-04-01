#!/usr/local/bin/perl
# edit_alias.cgi
# Display a form for editing or adding a mail alias

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_aliases() || &error($text{'aliases_ecannot'});
&require_mail();
if ($in{'new'}) {
	&ui_print_header(&domain_in($d), $text{'alias_create'}, "");
	}
else {
	&ui_print_header(&domain_in($d), $text{'alias_edit'}, "");
	@aliases = &list_domain_aliases($d);
	($virt) = grep { $_->{'from'} eq $in{'alias'} } @aliases;
	}

# Create form start and end
$fstart = &ui_form_start("save_alias.cgi", "post").
	  &ui_hidden("new", $in{'new'}).
	  &ui_hidden("dom", $in{'dom'}).
	  &ui_hidden("show", $in{'show'}).
	  &ui_hidden("old", $in{'alias'});
if ($in{'new'}) {
	$fend = &ui_form_end([ [ "create", $text{'create'} ] ]);
	}
else {
	$fend = &ui_form_end([ [ "save", $text{'save'} ],
			       [ "delete", $text{'delete'} ] ]);
	}

# Work out if simple mode is supported
if ($in{'new'} || &get_simple_alias($d, $virt)) {
	$can_simple = 1;
	}

# Show tabs, perhaps only one if simple mode isn't supported
$prog = "edit_alias.cgi?dom=$in{'dom'}&show=$in{'show'}&".
	($in{'new'} ? "new=1" : "alias=$in{'alias'}");
if ($can_simple) {
	@tabs = ( [ "simple", $text{'alias_simplemode'},
		    "$prog&simplemode=simple" ] );
	}
push(@tabs, [ "complex", $text{'alias_complexmode'},
	      "$prog&simplemode=complex" ] );
print &ui_tabs_start(\@tabs, "simplemode",
		     $in{'simplemode'} || $tabs[0]->[0], 1);

if ($can_simple) {
	# Simple mode form and destinations
	print &ui_tabs_start_tab("simplemode", "simple");
	print $fstart;
	print &ui_hidden("simplemode", "simple");
	&alias_form_start("simple");
	$simple = $in{'new'} ? { } : &get_simple_alias($d, $virt);
	&show_simple_form($simple, 0, 0, 0, 0, \@tds);
	print &ui_table_end();
	print $fend;
	print &ui_tabs_end_tab();
	}

# Complex alias destinations
print &ui_tabs_start_tab("simplemode", "complex");
print $fstart;
print &ui_hidden("simplemode", "complex");
&alias_form_start("complex");
&alias_form($virt->{'to'}, &hlink("<b>$text{'alias_dests'}</b>", "aliasdest"),
	    $d, "alias", $in{'alias'}, \@tds);
print &ui_table_end();
print $fend;
print &ui_tabs_end_tab();

# End of tabs and the form
print &ui_tabs_end(1);

# End of the page, with backlinks
if ($single_domain_mode) {
       &ui_print_footer("list_aliases.cgi?dom=$in{'dom'}&show=$in{'show'}",
               $text{'aliases_return'},
               "", $text{'index_return2'});
       }
else {
       &ui_print_footer("list_aliases.cgi?dom=$in{'dom'}&show=$in{'show'}",
               $text{'aliases_return'},
               &domain_footer_link($d),
               "", $text{'index_return'});
       }

# alias_form_start(suffix)
# Print start of the alias form, either for simple or complex mode
sub alias_form_start
{
local ($sfx) = @_;
my @tds = ( "width=30%" );
print &ui_table_start($text{'alias_header'}, "width=100%", 2);

# Alias description
if ($can_alias_comments) {
	print &ui_table_row(&hlink($text{'alias_cmt'}, "aliascmt"),
			    &ui_textbox($sfx."cmt", $virt->{'cmt'}, 50),
			    undef, \@tds);
	}

# Alias name, or catchall
my $name = $virt->{'from'};
$name =~ s/\@\S+$//;
if (&can_edit_catchall() || ($name eq "" && !$in{'new'})) {
	# Allow catchall option
	print &ui_table_row(&hlink($text{'alias_name'}, "aliasname"),
		    &ui_radio($sfx."name_def",
			      $name eq "" && !$in{'new'} ? 1 : 0,
			       [ [ 1, $text{'alias_catchall'} ],
				 [ 0, $text{'alias_mailbox'} ] ])."\n".
		    &ui_textbox($sfx."name", $name, 20)."\@".
		     &show_domain_name($d),
		    undef, \@tds);
	}
else {
	# Specific alias name only
	print &ui_table_row(&hlink($text{'alias_name'}, "aliasname2"),
		    &ui_textbox($sfx."name", $name, 20)."\@".$d->{'dom'},
		    undef, \@tds);
	}

print &ui_table_hr();
}


