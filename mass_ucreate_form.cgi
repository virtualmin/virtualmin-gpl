#!/usr/local/bin/perl
# Show a form for creating multiple users from a text file.
# This is in the format :
#	user:realname:pass:ftp:email:quota:extras:forwards:dbs

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&ui_print_header(&domain_in($d), $text{'umass_title'}, "", "umass");

print $text{'umass_help'};
print "<br><tt>$text{'umass_format'}</tt><p>";
print $text{'umass_formatftp'},"<br>\n";
print $text{'umass_formatemail'},"<p>\n";
print &text('umass_help2', "edit_user.cgi?new=1&dom=$in{'dom'}"),"<p>\n";

print &ui_form_start("mass_ucreate.cgi", "form-data");
print &ui_table_start($text{'umass_header'}, "width=100%", 2);
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

# Separator character
print &ui_table_row($text{'umass_separator'},
		    &ui_radio("separator", ":",
			      [ [ ":", $text{'umass_separatorcolon'} ],
				[ ",", $text{'umass_separatorcomma'} ],
				[ "tab", $text{'umass_separatortab'} ] ]));

# Password format (encrypted or not)
print &ui_table_row($text{'umass_encpass'},
		    &ui_yesno_radio("encpass", 0));

# Generate random passwords
print &ui_table_row($text{'umass_randpass'},
		    &ui_yesno_radio("randpass", 0));

print &ui_table_end();
print &ui_form_end([ [ "create", $text{'create'} ] ]);

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return'});
