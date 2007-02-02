#!/usr/local/bin/perl
# Save per-directory PHP versions for a server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpver($d) || &error($text{'phpver_ecannot'});
@avail = &list_available_php_versions($d);
@avail > 1 || &error($text{'phpver_eavail'});

&ui_print_header(&domain_in($d), $text{'phpver_title'}, "", "phpver");

print &ui_form_start("save_phpver.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";

# Start of table
@tds = ( "width=5" );
@dirs = &list_domain_php_directories($d);
if (@dirs > 1) {
	@links = ( &select_all_link("d"), &select_invert_link("d") );
	}
print &ui_links_row(\@links);
print &ui_columns_start([ "",
			  $text{'phpver_dir'},
			  $text{'phpver_ver'} ], undef, 0, \@tds);

# Show existing directories
$pub = &public_html_dir($d);
$i = 0;
foreach $dir (@dirs) {
	$ispub = $dir->{'dir'} eq $pub;
	$sel = &ui_select("ver_$i", $dir->{'version'},
			  [ map { [ $_->[0] ] } @avail ]);
	print &ui_hidden("dir_$i", $dir->{'dir'}),"\n";
	if ($ispub) {
		# Can only change version for public html
		print &ui_columns_row([ &ui_checkbox("d", 1, "", 0, undef, 1),
					"<i>$text{'phpver_pub'}</i>",
					$sel ], \@tds);
		}
	elsif (substr($dir->{'dir'}, 0, length($pub)) eq $pub) {
		# Show directory relative to public_html
		print &ui_checked_columns_row([
			"<tt>".substr($dir->{'dir'}, length($pub)+1)."</tt>",
			$sel ], \@tds, "d", $dir->{'dir'});
		}
	else {
		# Show full path
		print &ui_checked_columns_row([
			"<tt>$dir->{'dir'}</tt>",
			$sel ], \@tds, "d", $dir->{'dir'});
		}
	$i++;
	}

# Show row for new dir
print &ui_columns_row([ &ui_checkbox("d", 1, "", 0, undef, 1),
			&ui_textbox("newdir", undef, 30),
			&ui_select("newver", $dir->{'version'},
				  [ map { [ $_->[0] ] } @avail ])
		      ], \@tds);
print &ui_columns_end();
print &ui_links_row(\@links);

print &ui_table_end();
print &ui_form_end([ @dirs > 1 ? ( [ "delete", $text{'phpver_delete'} ] ) : ( ),
		     [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


