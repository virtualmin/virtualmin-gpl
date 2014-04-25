#!/usr/local/bin/perl
# Show greylisting enable / disable flag and whitelists

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ui_print_header(undef, $text{'postgrey_title'}, "", "postgrey");
&ReadParse();

# Check if can use
$err = &check_postgrey();
if ($err) {
	print &text('postgrey_failed', $err),"<p>\n";
	if (&can_install_postgrey()) {
		print &ui_form_start("install_postgrey.cgi");
		print &text('postgrey_installdesc'),"<p>\n";
		print &ui_form_end([ [ undef, $text{'postgrey_install'} ] ]);
		}
	&ui_print_footer("", $text{'index_return'});
	return;
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
	$formno = 1;
	print &ui_hr();
	@tabs = map { [ $_, $text{'postgrey_tab'.$_},
			'postgrey.cgi?type='.&urlize($_) ] }
		    @postgrey_data_types;
	print &ui_tabs_start(\@tabs, 'type', $in{'type'} || $tabs[0]->[0], 1);

	foreach $t (@postgrey_data_types) {
		print &ui_tabs_start_tab('type', $t);
		$data = &list_postgrey_data($t);
		if ($data) {
			# Show in editable table
			@table = ( );
			foreach $d (@$data) {
				push(@table, [
				    { 'type' => 'checkbox', 'name' => 'd',
				      'value' => $d->{'index'} },
				    "<a href='edit_postgrey.cgi?type=$t&".
				    "index=$d->{'index'}'>".
				    &html_escape($d->{'value'})."</a>",
				    $d->{'re'} ? $text{'yes'} : $text{'no'},
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
				  $text{'postgrey_re'}, 
				  $text{'postgrey_cmts'} ],
				100,
				\@table,
				undef,
				0,
				undef,
				$text{'postgrey_none'.$t},
				$formno++,
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

