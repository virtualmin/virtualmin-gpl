#!/usr/local/bin/perl
# Attempt to install email ratelimiting package

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'ratelimit_ecannot'});

&ui_print_header(undef, $text{'ratelimit_title4'}, "");

print &text('ratelimit_installing'),"<br>\n";
&$indent_print();
$ok = &install_ratelimit_package();
&$outdent_print();
print $ok ? $text{'ratelimit_installed'}
	  : $text{'ratelimit_installfailed'},"<p>\n";

&ui_print_footer("ratelimit.cgi", $text{'ratelimit_return'});
