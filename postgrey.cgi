#!/usr/local/bin/perl
# Show greylisting enable / disable flag and whitelists

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ui_print_header(undef, $text{'postgrey_title'}, "", "postgrey");
&ReadParse();

# Check if can use
$err = &check_postgrey();
if ($err) {
	&ui_print_endpage(&text('postgrey_failed', $err));
	}

# Show button to enable / disable
print $text{'postgrey_desc'},"<p>\n";
$ok = &is_postgrey_enabled();
print &ui_buttons_start();
if ($ok) {
	print &ui_buttons_row("disable_postgrey.cgi",
			      $text{'postgrey_disable'},
			      $text{'postgrey_disabledesc'});
	}
else {
	print &ui_buttons_row("enable_postgrey.cgi",
			      $text{'postgrey_enable'},
			      $text{'postgrey_enabledesc'});
	}
print &ui_buttons_end();

if ($ok) {
	# Show whitelists of emails and clients
	print &ui_hr();
	@types = ( 'clients', 'recipients' );
	@tabs = map { [ $_, $text{'postgrey_tab'.$_},
			'postgrey.cgi?type='.&urlize($_) ] } @types;
	print &ui_tabs_start(\@tabs, 'type', $in{'type'} || $types[0], 1);

	foreach $t (@types) {
		print &ui_tabs_start_tab('type', $t);
		$data = &list_postgrey_data($t);
		if ($data) {
			# Show in editable table
			@table = ( );
			foreach $d (@$data) {
				push(@table, [
				    { 'type' => 'checkbox', 'name' => 'd',
				      'value' => $_->{'index'} },
				    "<a href='edit_postgrey.cgi?type=$t&".
				    "index=$d->{'index'}'>".
				    &html_escape($d->{'value'})."</a>",
				    &html_escape(join(" ", @{$d->{'cmts'}})),
				    ]);
				}
			print &ui_form_columns_table(
				"delete_postgrey.cgi",
				[ [ undef, $text{'postgrey_delete'} ] ],
				1,
				[ [ "edit_postgrey.cgi?type=$t&new=1",
				    $text{'postgrey_add'.$t} ] ],
				[ [ 'type', $t ] ],
				[ '', $text{'postgrey_head'.$t},
				  $text{'postgrey_cmts'} ],
				100,
				\@table,
				undef,
				0,
				undef,
				$text{'postgrey_none'.$t},
				);
			}
		else {
			# Could not get file
			print "<b>$text{'postgrey_nofile'}</b><p>\n";
			}
		print &ui_tabs_end_tab('type', $t);
		}

	print &ui_tabs_end(1);
	}

&ui_print_footer("", $text{'index_return'});

