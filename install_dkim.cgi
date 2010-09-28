#!/usr/local/bin/perl
# Attempt to install DKIM filter package

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'dkim_ecannot'});

&ui_print_header(undef, $text{'dkim_title4'}, "");

print &text('dkim_installing'),"<br>\n";
&$indent_print();
$ok = &install_dkim_package();
&$outdent_print();
print $ok ? $text{'dkim_installed'}
	  : $text{'dkim_installfailed'},"<p>\n";

&ui_print_footer("dkim.cgi", $text{'dkim_return'});
