#!/usr/local/bin/perl
# Show all MySQL and PostgreSQL databases owned by this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
$tmpl = &get_template($d->{'template'});

# Fix up manually deleted databases
if (&can_import_servers()) {
	@all = &all_databases($d);
	&resync_all_databases($d, \@all);
	}
@dbs = &domain_databases($d);

$msg = &text('databases_indom', scalar(@dbs),
	     "<tt>".&show_domain_name($d)."</tt>");
&ui_print_header($msg, $text{'databases_title'}, "", "databases");

# Work out if allowed hosts can be edited
$can_allowed_hosts = 0;
foreach $f (@database_features) {
	$afunc = "get_".$f."_allowed_hosts";
	$can_allowed_hosts = 1 if ($d->{$f} && defined(&$afunc));
	}
$can_allowed_hosts = $can_allowed_hosts && !$d->{'parent'} &&
		     &can_allowed_db_hosts();

# Work out features we can change passwords for
@pass_features = ( );
@user_features = ( );
if (!$d->{'parent'}) {
	foreach my $f (@database_features) {
		$spfunc = "set_${f}_pass";
		$sufunc = "set_${f}_user";
		if ($d->{$f} && $config{$f}) {
			if (defined(&$spfunc)) {
				push(@pass_features, $f);
				}
			if (defined(&$sufunc)) {
				push(@user_features, $f);
				}
			}
		}
	}

# Show message about DB host
if ($d->{'mysql'} && &master_admin()) {
	my $myhost = &get_database_host_mysql($d);
	if ($myhost && $myhost ne 'localhost') {
		print "<b>",&text('databases_hosted',
				  "<tt>$myhost</tt>"),"</b><p>\n";
		}
	}

# Start tabs for various options, if appropriate
@tabs = ( [ "list", $text{'databases_tablist'} ] );
if (!$d->{'parent'}) {
	if ($virtualmin_pro) {
		push(@tabs, [ "usernames", $text{'databases_tabusernames'} ]);
		}
	}
if (@pass_features) {
	push(@tabs, [ "passwords", $text{'databases_tabpasswords'} ]);
	}
if (&can_import_servers()) {
	push(@tabs, [ "import", $text{'databases_tabimport'} ]);
	}
if ($can_allowed_hosts) {
	push(@tabs, [ "hosts", $text{'databases_tabhosts'} ]);
	}
if ($d->{'mysql'} && &can_edit_templates() && !$d->{'parent'}) {
	push(@tabs, [ "remote", $text{'databases_tabremote'} ]);
	}
foreach $t (@tabs) {
	$t->[2] = "list_databases.cgi?dom=$in{'dom'}&databasemode=$t->[0]";
	}
if (@tabs > 1) {
	print &ui_tabs_start(\@tabs, "databasemode",
			     $in{'databasemode'} || "list", 1);
	}

# Create add links
($dleft, $dreason, $dmax, $dhide) = &count_feature("dbs");
if ($dleft != 0) {
	push(@links, ["edit_database.cgi?dom=$in{'dom'}&new=1",
		     $text{'databases_add'}]);
	}

# Build and show DB list
print &ui_tabs_start_tab("databasemode", "list") if (@tabs > 1);
print "$text{'databases_desc1'}<p>\n";
foreach $db (sort { $a->{'name'} cmp $b->{'name'} } @dbs) {
	local $action;
	if ($db->{'link'}) {
		$action = "<a href='$db->{'link'}'>".
			  "$text{'databases_man'}</a>";
		}
	local $dis = $db->{'name'} eq $d->{'db'} && !&can_edit_database_name();
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $db->{'type'}.'_'.$db->{'name'},
		  'disabled' => $dis },
		"<a href='edit_database.cgi?dom=$in{'dom'}&name=$db->{'name'}&type=$db->{'type'}'>$db->{'name'}</a>",
		$db->{'desc'},
		$action
		]);
	}

# Generate the table
print &ui_form_columns_table(
	"delete_databases.cgi",
	[ [ "delete", $text{'databases_delete'} ] ],
	1,
	\@links,
	[ [ "dom", $in{'dom'} ] ],
	[ "", $text{'databases_db'},
	$text{'databases_type'},
	$text{'databases_action'}],
	100,
	\@table,
	undef, 0, undef,
	$text{'databases_none'});

# Show how many more can be added
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

	foreach $f (@user_features) {
		$sfunc = "set_${f}_user";
		$ufunc = "${f}_user";
		$un = &$ufunc($d);
		print &ui_table_row($text{'feature_'.$f},
		    &ui_radio_table($f."_def", 1,
			[ [ 1, &text('databases_leave', "<tt>$un</tt>") ],
			  [ 0, $text{'databases_newuser'},
			    &ui_textbox($f, undef, 20) ] ]));
		}

	print &ui_table_end();
	print &ui_form_end([ [ "save", $text{'save'} ] ]);
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

# Show form to change database passwords
if (!$d->{'parent'}) {
	print &ui_tabs_start_tab("databasemode", "passwords") if (@tabs > 1);
	if ($d->{'hashpass'}) {
		print "$text{'databases_desc3h'}<p>\n";
		}
	else {
		print "$text{'databases_desc3'}<p>\n";
		}
	print &ui_form_start("save_dbpass.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_table_start($text{'databases_pheader'}, undef, 2);

	foreach $f (@pass_features) {
		$sfunc = "set_${f}_pass";
		$ufunc = "${f}_pass";
		$efunc = "${f}_enc_pass";
		$pw = &$ufunc($d, 1);
		$encpw = defined(&$efunc) ? &$efunc($d) : undef;
		@opts = ( );
		if (!$tmpl->{$f.'_nopass'} && $d->{'pass'}) {
			push(@opts, [ 1, $text{'databases_samepass'} ]);
			}
		if ($encpw) {
			push(@opts, [ 2, $text{'databases_enc'} ]);
			}
		push(@opts, [ 0, $text{'databases_newpass'},
			      &ui_password($f,
                                 $pw eq $d->{'pass'} &&
				 !$tmpl->{$f.'_nopass'} ? "" : $pw, 20)." ".
			      ($pw ? &show_password_popup($d, undef, $f) : "")
			    ]);
		if (@opts > 1) {
			print &ui_table_row($text{'feature_'.$f},
				&ui_radio_table($f."_def",
				   $encpw ? 2 : $pw eq $d->{'pass'} ? 1 : 0,
				   \@opts));
			}
		else {
			print &ui_table_row($text{'feature_'.$f},
				$opts[0]->[2].
				&ui_hidden($f."_def", $opts[0]->[0]));
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
		        !$_->{'special'} &&
			$d->{$_->{'type'}} } @all;
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

# Show allowed remote hosts list
if ($can_allowed_hosts) {
	print &ui_tabs_start_tab("databasemode", "hosts") if (@tabs > 1);
	print "$text{'databases_desc5'}<p>\n";
	foreach $f (@database_features) {
		# One for each DB type (really only MySQL for now)
		next if (!$d->{$f});
		$afunc = "get_".$f."_allowed_hosts";
		next if (!defined(&$afunc));
		@hosts = &$afunc($d);
		print &ui_form_start("save_dbhosts.cgi", "post");
		print &ui_hidden("type", $f);
		print &ui_hidden("dom", $in{'dom'});
		print &ui_table_start(
		  &text('databases_ahosts', $text{'databases_'.$f}), undef, 2);
		print &ui_table_row(undef,
			&ui_textarea("hosts", join("\n", @hosts), 5, 40).
			"<br>".$text{'databases_hosts_'.$f}.
			"<br>".$text{'databases_hosts_fmt'}, 2);
		print &ui_table_end();
		print &ui_form_end([ [ undef, $text{'save'} ] ]);
		}
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

# Show MySQL host system
if ($d->{'mysql'} && &can_edit_templates() && !$d->{'parent'}) {
	print &ui_tabs_start_tab("databasemode", "remote") if (@tabs > 1);
        print "$text{'databases_desc6'}<p>\n";
	my @mymods = &list_remote_mysql_modules();
	if (@mymods < 2) {
		# Cannot change
		print &text('databases_desc6a', 'edit_newmysqls.cgi'),"<p>\n";
		}
	else {
		print &ui_form_start("save_mysqlremote.cgi", "post");
		print &ui_hidden("dom", $in{'dom'});
		print &ui_table_start(undef, undef, 2);

		# Current host system
		my ($mymod) = grep { ($d->{'mysql_module'} || 'mysql') eq
				     $_->{'minfo'}->{'dir'} } @mymods;
		print &ui_table_row($text{'databases_remoteold'},
			$mymod->{'desc'});

		# New host system
		print &ui_table_row($text{'databases_remotenew'},
			&ui_select("mymod", $mymod->{'minfo'}->{'dir'},
				[ map { [ $_->{'minfo'}->{'dir'},
					  $_->{'desc'} ] } @mymods ]));

		print &ui_table_end();
		print &ui_form_end([ [ undef, $text{'databases_remoteok'} ] ]);
		print "<b>$text{'databases_warn'}</b> <p>\n";
		}
	print &ui_tabs_end_tab() if (@tabs > 1);
	}

print &ui_tabs_end(1) if (@tabs > 1);

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

