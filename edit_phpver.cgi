#!/usr/local/bin/perl
# Save per-directory PHP versions for a server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpver($d) || &error($text{'phpver_ecannot'});

# Make sure an Apache virtualhost exists, or else all the rest is pointless
($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
$virt || &error(&text('phpmode_evirt', $d->{'dom'}, $d->{'web_port'}));

&ui_print_header(&domain_in($d), $text{'phpver_title'}, "", "phpver");

$mode = &get_domain_php_mode($d);
if ($mode eq "mod_php") {
	print &text('phpver_emodphp'),"<p>\n";
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	return;
	}
@avail = &list_available_php_versions($d);
if (@avail <= 1) {
	print &text('phpver_eavail2', $avail[0]->[0]),"<p>\n";
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	return;
	}

@hiddens = ( [ "dom", $in{'dom'} ] );

# Build versions list
@vlist = ( );
foreach my $v (@avail) {
	if ($v->[1]) {
		my $fullver = &get_php_version($v->[1], $d);
		push(@vlist, [ $v->[0], $fullver ]);
		}
	else {
		push(@vlist, $v->[0]);
		}
	}

# Build data for existing directories
@dirs = &list_domain_php_directories($d);
$pub = &public_html_dir($d);
$i = 0;
@table = ( );
$anydelete = 0;
foreach $dir (@dirs) {
	$ispub = $dir->{'dir'} eq $pub;
	$sel = &ui_select("ver_$i", $dir->{'version'}, \@vlist);
	push(@hiddens, [ "dir_$i", $dir->{'dir'} ]);
	if ($ispub) {
		# Can only change version for public html
		push(@table, [
			{ 'type' => 'checkbox', 'name' => 'd',
			  'value' => $dir->{'dir'}, 'disabled' => 1 },
			"<i>$text{'phpver_pub'}</i>",
			$sel
			]);
		}
	elsif (substr($dir->{'dir'}, 0, length($pub)) eq $pub) {
		# Show directory relative to public_html
		push(@table, [
			{ 'type' => 'checkbox', 'name' => 'd',
			  'value' => $dir->{'dir'} },
			"<tt>".substr($dir->{'dir'}, length($pub)+1)."</tt>",
			$sel
			]);
		$anydelete++;
		}
	else {
		# Show full path
		push(@table, [
			{ 'type' => 'checkbox', 'name' => 'd',
			  'value' => $dir->{'dir'} },
			"<tt>$dir->{'dir'}</tt>",
			$sel
			]);
		$anydelete++;
		}
	$i++;
	}

# Add row for new dir
push(@table, [ { 'type' => 'checkbox', 'name' => 'd',
		 'value' => 1, 'disabled' => 1 },
	       &ui_textbox("newdir", undef, 30),
	       &ui_select("newver", $dir->{'version'}, \@vlist),
	     ]);

# Generate the table
print &ui_form_columns_table(
	"save_phpver.cgi",
	[ @dirs > 1 ? ( [ "delete", $text{'phpver_delete'} ], undef ) : ( ),
	  [ "save", $text{'phpver_save'} ] ],
	$anydelete,
	undef,
	\@hiddens,
	[ "", $text{'phpver_dir'}, $text{'phpver_ver'} ],
	undef,
	\@table,
	undef,
	1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


