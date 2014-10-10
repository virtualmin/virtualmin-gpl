#!/usr/local/bin/perl
# Edit settings for one provider

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'clouds_ecannot'});

&ui_print_header(undef, $text{'cloud_title'}, "");

@provs = &list_cloud_providers();
($prov) = grep { $_->{'name'} eq $in{'name'} } @provs;
$prov || &error($text{'cloud_egone'});

print &ui_form_start("save_cloud.cgi", "post");
print &ui_hidden("name", $in{'name'});
print &ui_table_start($text{'cloud_header'}, undef, 2);

# Cloud provider name
print &ui_table_row($text{'cloud_provider'},
		    $prov->{'desc'});

# Provider options
$ifunc = "cloud_".$prov->{'name'}."_show_inputs";
print &$ifunc($prov);

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("list_clouds.cgi", $text{'clouds_return'});
