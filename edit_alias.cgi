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

@tds = ( "width=30%" );
print &ui_form_start("save_alias.cgi", "post");
print &ui_hidden("new", $in{'new'}),"\n";
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_hidden("old", $in{'alias'}),"\n";

# Work out if simple mode is supported
if ($virtualmin_pro && ($in{'new'} || &get_simple_alias($d, $virt))) {
	$can_simple = 1;
	}

# Show tabs
if ($can_simple) {
	@tabs = ( [ "simple", $text{'alias_simplemode'} ],
		  [ "complex", $text{'alias_complexmode'} ] );
	print &ui_table_start($text{'alias_header'}, "width=100%", 2);
	print &ui_table_row(
		undef, &ui_tabs_start(\@tabs, "simplemode", "simple"), 2);
	}
else {
	print &ui_hidden("simplemode", "complex"),"\n";
	print &ui_table_start($text{'alias_header'}, "width=100%", 2);
	}

# Alias description
if ($can_alias_comments) {
	print &ui_table_row(&hlink($text{'alias_cmt'}, "aliascmt"),
			    &ui_textbox("cmt", $virt->{'cmt'}, 50),
			    undef, \@tds);
	}

# Alias name, or catchall
$name = $virt->{'from'};
$name =~ s/\@\S+$//;
print &ui_table_row(&hlink($text{'alias_name'}, "aliasname"),
	    &ui_radio("name_def", $name eq "" && !$in{'new'} ? 1 : 0,
		       [ [ 1, $text{'alias_catchall'} ],
			 [ 0, $text{'alias_mailbox'} ] ])."\n".
	    &ui_textbox("name", $name, 20),
	    undef, \@tds);

print &ui_table_hr();

# Simple alias destination
if ($can_simple) {
	print &ui_tabs_start_tabletab("simplemode", "simple");
	$simple = $in{'new'} ? { } : &get_simple_alias($d, $virt);
	&show_simple_form($simple, 0, 0, 0, \@tds);
	print &ui_tabs_end_tabletab();
	}

# Complex alias destinations
if ($can_simple) {
	print &ui_tabs_start_tabletab("simplemode", "complex");
	}
&alias_form($virt->{'to'}, &hlink("<b>$text{'alias_dests'}</b>", "aliasdest"),
	    $d, "alias", $in{'alias'}, \@tds);
if ($can_simple) {
	print &ui_tabs_end_tabletab();
	}
print &ui_table_end();

if ($in{'new'}) {
	print &ui_form_end([ [ "create", $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ "save", $text{'save'} ],
			     [ "delete", $text{'delete'} ] ]);
	}

if ($single_domain_mode) {
	&ui_print_footer("list_aliases.cgi?dom=$in{'dom'}",
		$text{'aliases_return'},
		"", $text{'index_return2'});
	}
else {
	&ui_print_footer("list_aliases.cgi?dom=$in{'dom'}",
		$text{'aliases_return'},
		&domain_footer_link($d),
		"", $text{'index_return'});
	}


