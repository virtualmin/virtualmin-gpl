#!/usr/local/bin/perl
# Stop the Rails server process behind some script

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});

# Get the script being removed
@got = &list_domain_scripts($d);
($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
$script = &get_script($sinfo->{'name'});
$sinfo && $script || &error($text{'stopscript_egone'});

# Do it and tell the user
&ui_print_header(&domain_in($d), $text{'stopscript_title'}, "");

print &text('stopscript_doing', "<i>$script->{'desc'}</i>"),"<br>";
&{$script->{'stop_server_func'}}($d, $sinfo->{'opts'});
print &text('stopscript_done'),"<p>\n";
&webmin_log("stop", "script", $sinfo->{'name'},
	    { 'ver' => $sinfo->{'version'},
	      'desc' => $sinfo->{'desc'},
	      'dom' => $d->{'dom'} });

&ui_print_footer("edit_script.cgi?dom=$in{'dom'}&script=$in{'script'}",
		  $text{'scripts_ereturn'},
		 "list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));
