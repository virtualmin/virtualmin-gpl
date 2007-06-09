#!/usr/local/bin/perl
# Show all MySQL and PostgreSQL databases owned by this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});

&ui_print_header(&domain_in($d), $text{'databases_title'}, "", "databases");

# Fix up manually deleted databases
if (&can_import_servers()) {
	@all = &all_databases($d);
	&resync_all_databases($d, \@all);
	}

# Start tabs for various options, if appropriate
@tabs = ( [ "list", $text{'databases_tablist'} ] );
if (!$d->{'parent'} && $virtualmin_pro) {
	push(@tabs, [ "usernames", $text{'databases_tabusernames'} ]);
	push(@tabs, [ "passwords", $text{'databases_tabpasswords'} ]);
	}
if (&can_import_servers()) {
	push(@tabs, [ "import", $text{'databases_tabimport'} ]);
	}
foreach $t (@tabs) {
	$t->[2] = "list_databases.cgi?dom=$in{'dom'}&databasemode=$t->[0]";
	}
if (@tabs > 1) {
	print &ui_tabs_start(\@tabs, "databasemode",
			     $in{'databasemode'} || "list", 1);
	}

# Create select / add links
($dleft, $dreason, $dmax, $dhide) = &count_feature("dbs");
@links = ( &select_all_link("d"),
	   &select_invert_link("d") );
if ($dleft != 0) {
	push(@links, "<a href='edit_database.cgi?dom=$in{'dom'}&new=1'>".
		     $text{'databases_add'}."</a>");
	}

# Build and show DB list
print &ui_tabs_start_tab("databasemode", "list") if (@tabs > 1);
print "$text{'databases_desc1'}<p>\n";
@dbs = &domain_databases($d);
if (@dbs) {
	print &ui_form_start("delete_databases.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_links_row(\@links);
	print &ui_columns_start([ "", $text{'databases_db'},
				  $text{'databases_type'},
				  $text{'databases_action'} ], undef, 0,
				[ "width=5" ]);
	foreach $db (sort { $a->{'name'} cmp $b->{'name'} } @dbs) {
		local $action;
		if ($db->{'link'}) {
			$action = "<a href='$db->{'link'}'>".
				  "$text{'databases_man'}</a>";
			}
		print &ui_checked_columns_row([
			"<a href='edit_database.cgi?dom=$in{'dom'}&name=$db->{'name'}&type=$db->{'type'}'>$db->{'name'}</a>",
			$db->{'desc'},
			$action ],
			[ "width=5" ],
			"d", $db->{'type'}."_".$db->{'name'});
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'databases_none'}</b><p>\n";
	shift(@links); shift(@links);
	}
print &ui_links_row(\@links);
if (@dbs) {
	print &ui_form_end([ [ "delete", $text{'databases_delete'} ] ]);
	}
if ($dleft != 0 && $dleft != -1 && !$dhide) {
	print "<b>",&text('databases_canadd'.$dreason, $dleft),"</b><p>\n";
	}
elsif ($dleft == 0) {
	print &text('databases_noadd'.$dreason, $dmax),"<br>\n";
	}
print &ui_tabs_end_tab() if (@tabs > 1);

# Show form to change database usernames
if (!$d->{'parent'} && $virtualmin_pro) {
	print &ui_tabs_start_tab("databasemode", "usernames") if (@tabs > 1);
	print "$text{'databases_desc2'}<p>\n";
	print &ui_form_start("save_dbname.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_table_start($text{'databases_uheader'}, undef, 2);

	foreach $f (@database_features) {
		$sfunc = "set_${f}_user";
		$ufunc = "${f}_user";
		if (defined($sfunc) && $config{$f} && $d->{$f}) {
			$un = &$ufunc($d);
			print &ui_table_row($text{'feature_'.$f},
			    &ui_opt_textbox($f, undef, 20,
				&text('databases_leave', "<tt>$un</tt>")));
			}
		}

	print &ui_table_end();
	print &ui_form_end([ [ "save", $text{'save'} ] ]);
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

# Show form to change database passwords
if (!$d->{'parent'} && $virtualmin_pro) {
	print &ui_tabs_start_tab("databasemode", "passwords") if (@tabs > 1);
	print "$text{'databases_desc3'}<p>\n";
	print &ui_form_start("save_dbpass.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_table_start($text{'databases_pheader'}, undef, 2);

	foreach $f (@database_features) {
		$sfunc = "set_${f}_pass";
		$ufunc = "${f}_pass";
		$efunc = "${f}_enc_pass";
		if (defined($sfunc) && $config{$f} && $d->{$f}) {
			$pw = &$ufunc($d, 1);
			$encpw = defined(&$efunc) ? &$efunc($d) : undef;
			print &ui_table_row($text{'feature_'.$f},
			    &ui_radio($f."_def",
				$encpw ? 2 : $pw eq $d->{'pass'} ? 1 : 0,
				[ [ 1, $text{'databases_samepass'}."<br>" ],
				  $encpw ?
				    ( [ 2, $text{'databases_enc'}."<br>" ] ) :
				    ( ),
				  [ 0, $text{'databases_newpass'}." ".
				       &ui_textbox($f,
					 $pw eq $d->{'pass'} ? "" : $pw, 20) ]
				]));
			}
		}

	print &ui_table_end();
	print &ui_form_end([ [ "save", $text{'save'} ] ]);
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

# Show database import form, if there are any not owned by any user
if (&can_import_servers()) {
	foreach $dd (&list_domains()) {
		foreach $db (&domain_databases($dd)) {
			$inuse{$db->{'type'},$db->{'name'}}++;
			}
		}
	@avail = grep { !$inuse{$_->{'type'},$_->{'name'}} &&
		        !$_->{'special'} } @all;
	@avail = sort { $a->{'name'} cmp $b->{'name'} } @avail;
	print &ui_tabs_start_tab("databasemode", "import") if (@tabs > 1);
	print "$text{'databases_desc4'}<p>\n";
	if (@avail) {
		print &ui_form_start("import_database.cgi", "post");
		print &ui_hidden("dom", $in{'dom'}),"\n";
		print &ui_table_start($text{'databases_iheader'}, undef, 2);

		print &ui_table_row($text{'databases_ilist'},
			&ui_select("import", [ ],
			    [ map { [ "$_->{'type'} $_->{'name'}",
				      "$_->{'name'} ($_->{'desc'})"
				    ] } @avail ], 5, 1));

		print &ui_table_end();
		print &ui_form_end([ [ "ok", $text{'databases_import'} ] ]);
		}
	else {
		print "$text{'databases_noimport'}<p>\n";
		}
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

print &ui_tabs_end(1) if (@tabs > 1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

