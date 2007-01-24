#!/usr/local/bin/perl
# all_webmin.cgi
# Update all Webmin users

require './virtual-server-lib.pl';
&master_admin() || &error($text{'allwebmin_ecannot'});

&ui_print_unbuffered_header(undef, $text{'allwebmin_title'}, "");

&modify_all_webmin();
if (defined(&modify_all_resellers)) {
	&modify_all_resellers();
	}
&run_post_actions();

&ui_print_footer("", $text{'index_return'});
