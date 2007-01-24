#!/usr/local/bin/perl
# edit_vfile.cgi
# Display the contents of an autoresponder file and alias settings

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'vfile_ecannot'});

&ui_print_header(undef, $text{'vfile_title'}, "");
$what = $in{'alias'} ? 'alias' : 'user';

# Find the alias and its settings
if ($what eq "alias") {
	@aliases = &list_domain_aliases($d);
	($virt) = grep { $_->{'from'} eq $in{$what} } @aliases;
	@av = &alias_type($virt->{'to'}->[$in{'idx'}]);
	}
else {
	@users = &list_domain_users($d);
	($user) = grep { $_->{'user'} eq $in{$what} } @users;
	@av = &alias_type($user->{'to'}->[$in{'idx'}]);
	}

# Read the autoreply file
if (-e $in{'file'}) {
	open(FILE, $in{'file'}) ||
		&error(&text('rfile_eread', $in{'file'}, $d->{'user'}, $!));
	while(<FILE>) {
		push(@lines, $_);
		}
	close(FILE);
	}

print &text('vfile_desc', "<tt>$in{'file'}</tt>"),"<p>\n";
print "$text{'vfile_desc2'}<p>\n";

print "<form action=save_vfile.cgi method=post enctype=multipart/form-data>\n";
print "<input type=hidden name=file value=\"$in{'file'}\">\n";
print "<input type=hidden name=dom value=\"$in{'dom'}\">\n";
print "<input type=hidden name=$what value=\"",$in{$what},"\">\n";
print "<input type=hidden name=idx value=\"$in{'idx'}\">\n";

print "<table>\n";
print "<tr> <td colspan=2><textarea name=text rows=10 cols=80>",
	join("", @lines),"</textarea></td> </tr>\n";

# Show timeouts
print "<tr> <td><b>$text{'vfile_time'}</b></td>\n";
print "<td>",&ui_textbox("time", $av[2], 8)," ",$text{'vfile_secs'},
      "</td> </tr>\n";

print "<tr> <td><b>$text{'vfile_num'}</b></td>\n";
print "<td>",&ui_textbox("num", $av[3], 8),"</td> </tr>\n";

# Show directory
print "<tr> <td><b>$text{'vfile_dir'}</b></td>\n";
print "<td>",&ui_opt_textbox("dir",
			     $av[4] eq $in{'file'}.".log" ? undef : $av[4], 30,
			     $text{'vfile_auto'}),"</td> </tr>\n";

# Show flag options
print "<tr> <td><b>$text{'vfile_flag'}</b></td>\n";
print "<td>",&ui_radio("flag", $av[5],
	[ [ "", $text{'default'} ],
	  [ 1, $text{'yes'} ],
	  [ 0, $text{'no'} ] ]),"</td> </tr>\n";

# Show sender address
$other = $av[6] eq "" || $av[6] eq "+" || $av[6] eq "\$" ? 0 : 1;
print "<tr> <td><b>$text{'vfile_from'}</b></td>\n";
print "<td>",&ui_radio("from", $other ? "other" : $av[6],
	[ [ "", $text{'default'} ],
	  [ "+", $text{'vfile_blank'} ],
	  [ "\$", $text{'vfile_to'} ],
	  [ "other", $text{'vfile_other'} ] ]),"\n",
	&ui_textbox("other", $other ? $av[6] : undef, 20),"</td> </tr>\n";

print "</table>\n";
print "<input type=submit value=\"$text{'save'}\"> ",
      "<input type=reset value=\"$text{'rfile_undo'}\">\n";
print "</form>\n";

&ui_print_footer("edit_$what.cgi?dom=$in{'dom'}&$what=$in{$what}",
	$text{$what.'_return'});
