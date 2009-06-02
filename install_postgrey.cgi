#!/usr/local/bin/perl
# Attempt to install Postgrey package

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});

&ui_print_header(undef, $text{'postgrey_title4'}, "");

print &text('postgrey_installing'),"<br>\n";
&$indent_print();
$ok = &install_postgrey_package();
&$outdent_print();
print $ok ? $text{'postgrey_installed'}
	  : $text{'postgrey_installfailed'},"<p>\n";

&ui_print_footer("postgrey.cgi", $text{'postgrey_return'});
