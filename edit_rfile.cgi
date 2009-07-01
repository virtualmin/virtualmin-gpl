#!/usr/local/bin/perl
# edit_rfile.cgi
# Display the contents of an autoreply file

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'rfile_ecannot'});

&ui_print_header(undef, $text{'rfile_title'}, "");

if (-e $in{'file'}) {
	&open_tempfile_as_domain_user($d, FILE, $in{'file'}) ||
		&error(&text('rfile_eread', $in{'file'}, $d->{'user'}, $!));
	while(<FILE>) {
		if (/^Reply-Tracking:\s*(.*)/) {
			$replies = $1;
			}
		elsif (/^Reply-Period:\s*(.*)/) {
			$period = $1;
			}
		else {
			push(@lines, $_);
			}
		}
	&close_tempfile_as_domain_user($d, FILE);
	}

print &text('rfile_desc', "<tt>$in{'file'}</tt>"),"<p>\n";
print "$text{'rfile_desc2'}<p>\n";

$what = $in{'alias'} ? 'alias' : 'user';
print "<form action=save_rfile.cgi method=post enctype=multipart/form-data>\n";
print "<input type=hidden name=file value=\"$in{'file'}\">\n";
print "<input type=hidden name=dom value=\"$in{'dom'}\">\n";
print "<input type=hidden name=$what value=\"",$in{$what},"\">\n";
print "<input type=hidden name=unix value=\"1\">\n";
print "<textarea name=text rows=20 cols=80>",
	join("", @lines),"</textarea><p>\n";

print $text{'rfile_replies'},"\n";
printf "<input type=radio name=replies_def value=1 %s> %s\n",
	$replies eq '' ? "checked" : "", $text{'rfile_none'};
printf "<input type=radio name=replies_def value=0 %s> %s\n",
	$replies eq '' ? "" :"checked", $text{'rfile_file'};
printf "<input name=replies size=30 value='%s'> %s<br>\n",
	$replies, &file_chooser_button("replies");
print "&nbsp;" x 3;
print $text{'rfile_period'},"\n";
printf "<input type=radio name=period_def value=1 %s> %s\n",
	$period eq '' ? "checked" : "", $text{'rfile_default'};
printf "<input type=radio name=period_def value=0 %s>\n",
	$period eq '' ? "" :"checked";
printf "<input name=period size=5 value='%s'> %s<p>\n",
	$period, $text{'rfile_secs'};

print "<input type=submit value=\"$text{'save'}\"> ",
      "<input type=reset value=\"$text{'rfile_undo'}\">\n";
print "</form>\n";

&ui_print_footer("edit_$what.cgi?dom=$in{'dom'}&$what=$in{$what}",
	$text{$what.'_return'});
