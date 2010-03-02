#!/usr/local/bin/perl
# Start the Rails server process behind some script

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});

# Get the script being started
@got = &list_domain_scripts($d);
($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
$script = &get_script($sinfo->{'name'});
$sinfo && $script || &error($text{'stopscript_egone'});

# Do it and tell the user
&ui_print_header(&domain_in($d), $text{'startscript_title'}, "");

print &text('startscript_doing', "<i>$script->{'desc'}</i>"),"<br>";
$err = &{$script->{'start_server_func'}}($d, $sinfo->{'opts'});
if ($err) {
	print &text('startscript_failed', $err),"<p>\n";
	}
else {
	print $text{'setup_done'},"<p>\n";
	&webmin_log("start", "script", $sinfo->{'name'},
		    { 'ver' => $sinfo->{'version'},
		      'desc' => $sinfo->{'desc'},
		      'dom' => $d->{'dom'} });
	}

&ui_print_footer("edit_script.cgi?dom=$in{'dom'}&script=$in{'script'}",
		  $text{'scripts_ereturn'},
		 "list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));
