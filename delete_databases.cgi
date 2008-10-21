#!/usr/local/bin/perl
# Delete several databases from a domain, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
&error_setup($text{'ddatabases_err'});

# Get the DBs
@d = split(/\0/, $in{'d'});
@d || &error($text{'ddatabases_enone'});
@dbs = &domain_databases($d);
foreach $tn (@d) {
	($t, $n) = split(/_/, $tn, 2);
	($db) = grep { $_->{'type'} eq $t && $_->{'name'} eq $n } @dbs;
	$db || &error(&text('ddatabases_edb', $t, $n));
	if ($db->{'name'} eq $d->{'db'} && !&can_edit_database_name()) {
		&error(&text('ddatabases_edbdef', $t, $n));
		}
	push(@deldbs, $db);
	}

if ($in{'confirm'}) {
	# Go for it!
	&ui_print_unbuffered_header(&domain_in($d),
				    $text{'ddatabases_title'}, "");
	foreach $db (@deldbs) {
		if (&indexof($db->{'type'}, @database_plugins) >= 0) {
			&plugin_call($db->{'type'}, "database_delete", $d,
				     $db->{'name'});
			}
		else {
			$dfunc = "delete_".$db->{'type'}."_database";
			&$dfunc($d, $db->{'name'});
			}
		}
	&$first_print($text{'setup_save'});
	&save_domain($d);
	&$second_print($text{'setup_done'});

	&refresh_webmin_user($d);
	}
else {
	# Ask first
	&ui_print_header(&domain_in($d), $text{'ddatabases_title'}, "");

	# Work out the total size
	foreach $db (@deldbs) {
		if (&indexof($db->{'type'}, @database_plugins) >= 0) {
			# Get size from plugin
			($size, $tables) = &plugin_call($db->{'type'},
				"database_size", $d, $db->{'name'});
			}
		else {
			# From core DB call
			$szfunc = $db->{'type'}."_size";
			($size, $tables) = &$szfunc($d, $db->{'name'});
			}
		$totalsize += $size;
		$totaltables += $tables;
		}

	print "<center>\n";
	print &ui_form_start("delete_databases.cgi", "post");
	print &ui_hidden("dom", $d->{'id'}),"\n";
	foreach $tn (@d) {
		print &ui_hidden("d", $tn),"\n";
		}
	print &text($totaltables ? 'ddatabases_rusure2' 
				 : 'ddatabases_rusure3', scalar(@d),
		    $totaltables, &nice_size($totalsize)),"<p>\n";
	@dnames = map { $_->{'name'} } @deldbs;
	print &ui_form_end([ [ "confirm", $text{'ddatabases_ok'} ] ]);
	print &text('ddatabases_dbs', 
		join(" ", map { "<tt>$_</tt>" } @dnames)),"<br>\n";
	print "</center>\n";
	}
&ui_print_footer("list_databases.cgi?dom=$d->{'id'}",
		 $text{'databases_return'});


