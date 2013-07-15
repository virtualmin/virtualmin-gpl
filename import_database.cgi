#!/usr/local/bin/perl
# Add some databases to this server's control

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_databases() && &can_import_servers() ||
	&error($text{'edit_ecannot'});
&set_all_null_print();

# Check databases to import for sanity
@import = split(/\0/, $in{'import'});
foreach $tn (@import) {
	($type, $db) = split(/\s+/, $tn, 2);
	if ($type eq "mysql" &&
	    ($db eq "mysql" || $db eq "information_schema")) {
		&error(&text('databases_eimysql', $db));
		}
	elsif ($type eq "postgres" && $db =~ /^template\d+$/) {
		&error(&text('databases_eipostgres', $db));
		}
	}

foreach $tn (@import) {
	($type, $db) = split(/\s+/, $tn, 2);
	@dbs = split(/\s+/, $d->{'db_'.$type});
	push(@dbs, $db);
	$d->{'db_'.$type} = join(" ", @dbs);

	# Call the grant function to actually allow access
	$gfunc = "grant_".$type."_database";
	if (defined(&$gfunc)) {
		&$gfunc($d, $db);
		}
	&webmin_log("import", "database", $db,
		    { 'type' => $type, 'dom' => $d->{'dom'} });
	}
&save_domain($d);
&refresh_webmin_user($d);
&run_post_actions_silently();
&redirect("list_databases.cgi?dom=$in{'dom'}");

