#!/usr/local/bin/perl
# Show all new features from older versions

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newchangelog_ecannot'});
&ui_print_header(undef, $text{'newchangelog_title'}, "");

@doms = &list_visible_domains();
@doms = &sort_indent_domains(\@doms);
($d) = grep { !$_->{'parent'} } @doms;
$html = &get_new_features_html($d, 1);
$html = $text{'newchangelog_desc'}."<p>\n".$html;
print &ui_table_start(undef, "width=100%", 2);
print &ui_table_row(undef, $html, 2);
print &ui_table_end();

&ui_print_footer("", $text{'index_return'});

