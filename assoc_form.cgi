#!/usr/local/bin/perl
# Show a form to associate or disassociate features

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_associate_domain($d) || &error($text{'assoc_ecannot'});

&ui_print_header(&domain_in($d), $text{'assoc_title'}, "");

print $text{'assoc_desc'},"<p>\n";

print &ui_form_start("assoc.cgi", "post");
print &ui_table_start($text{'assoc_header'}, undef, 2);

# Features to enable or disable
my @grid;
foreach my $f (&list_possible_domain_features($d)) {
	push(@grid, &ui_checkbox($f, 1, $text{'edit_'.$f}, $d->{$f}));
	}
print &ui_table_row($text{'assoc_features'},
	&ui_grid_table(\@grid, 2));

# Validate afterwards?
print &ui_table_row($text{'assoc_validate'},
	&ui_yesno_radio("validate", 0));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
