#!/usr/local/bin/perl
# Add some databases to this server's control

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_databases() && &can_import_servers() ||
	&error($text{'edit_ecannot'});

foreach $tn (split(/\0/, $in{'import'})) {
	($type, $db) = split(/\s+/, $tn, 2);
	@dbs = split(/\s+/, $d->{'db_'.$type});
	push(@dbs, $db);
	$d->{'db_'.$type} = join(" ", @dbs);
	&webmin_log("import", "database", $db,
		    { 'type' => $type, 'dom' => $d->{'dom'} });
	}
&save_domain($d);
&redirect("list_databases.cgi?dom=$in{'dom'}");

