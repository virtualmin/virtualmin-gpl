#!/usr/local/bin/perl
# Enable postgrey

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
$err = &check_postgrey();
&error($err) if ($err);
&ui_print_header(undef, $text{'postgrey_title2'}, "");

&enable_postgrey();

&ui_print_footer("postgrey.cgi", $text{'postgrey_return'});

