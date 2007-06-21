#!/usr/local/bin/perl
# Show a form for creating multiple aliases from a text file.
# This is in the format :
#	mailbox:dest1:dest2:...

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&ui_print_header(&domain_in($d), $text{'amass_title'}, "", "amass");

print $text{'amass_help'};
print "<br><tt>$text{'amass_format'}</tt><p>";
print &text('amass_help2', "edit_alias.cgi?new=1&dom=$in{'dom'}"),"<p>\n";

print &ui_form_start("mass_acreate.cgi", "form-data");
print &ui_table_start($text{'amass_header'}, "width=100%", 2);
print &ui_hidden("dom", $in{'dom'}),"\n";

# Source file / data
if (&master_admin()) {
	push(@sopts, [ 1, &text('cmass_local',
			   &ui_textbox("local", undef, 40))."<br>" ]);
	}
push(@sopts, [ 0, &text('cmass_upload', &ui_upload("upload", 40))."<br>" ]);
push(@sopts, [ 2, &text('cmass_text', &ui_textarea("text", "", 5, 60))."<br>"]);
print &ui_table_row($text{'cmass_file'},
		    &ui_radio("file_def", 0, \@sopts));

print &ui_table_end();
print &ui_form_end([ [ "create", $text{'create'} ] ]);

&ui_print_footer("list_aliases.cgi?dom=$in{'dom'}", $text{'aliases_return'},
		 "", $text{'index_return'});
