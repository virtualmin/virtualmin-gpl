#!/usr/local/bin/perl
# Reset some features on a selected domain

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'reset_err'});
&can_edit_templates() || &error($text{'reset_ecannot'});

# Check and parse inputs
$d = &get_domain($in{'server'});
$d && &can_edit_domain($d) || &error($text{'reset_edom'});
@features = split(/\0/, $in{'features'});
@features || &error($text{'reset_efeatures'});

&ui_print_header(undef, $text{'reset_title'}, "");

&ui_print_footer("", $text{'index_return'},
	 "edit_newvalidate.cgi?mode=reset", $text{'newvalidate_return'});
