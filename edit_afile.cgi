#!/usr/local/bin/perl
# edit_afile.cgi
# Display the contents of an address file

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'afile_ecannot'});

&ui_print_header(undef, $text{'afile_title'}, "");

&switch_to_domain_user($d);
if (-e $in{'file'}) {
	open(FILE, $in{'file'}) ||
		&error(&text('afile_eread', $in{'file'}, $d->{'user'}, $!));
	@lines = <FILE>;
	close(FILE);
	}

print "<b>",&text('afile_desc', "<tt>$in{'file'}</tt>"),"</b><p>\n";

$what = $in{'alias'} ? 'alias' : 'user';
print "<form action=save_afile.cgi method=post enctype=multipart/form-data>\n";
print "<input type=hidden name=file value=\"$in{'file'}\">\n";
print "<input type=hidden name=$what value=\"",$in{$what},"\">\n";
print "<input type=hidden name=dom value=\"$in{'dom'}\">\n";
print "<textarea name=text rows=20 cols=80>",
	join("", @lines),"</textarea><p>\n";
print "<input type=submit value=\"$text{'save'}\"> ",
      "<input type=reset value=\"$text{'afile_undo'}\">\n";
print "</form>\n";

&ui_print_footer("edit_$what.cgi?dom=$in{'dom'}&$what=$in{$what}",
	$text{$what.'_return'});

