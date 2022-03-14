#!/usr/local/bin/perl
# Attempt to install AWS CLI package

require './virtual-server-lib.pl';
&can_cloud_providers() || &error($text{'clouds_ecannot'});
&foreign_require("software");

&ui_print_unbuffered_header(undef, $text{'cloud_s3_awscli_title'}, "");

print &text('cloud_s3_awscli_installing'),"<br>\n";
&$indent_print();
my @inst = &software::update_system_install('awscli');
my $ok = scalar(@inst);
&$outdent_print();
print $ok ? $text{'dkim_installed'}
	  : $text{'dkim_installfailed'},"<p>\n";

&ui_print_footer("edit_cloud.cgi?name=s3", $text{'cloud_s3_awscli_return'});
