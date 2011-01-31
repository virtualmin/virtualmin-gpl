#!/usr/local/bin/perl
# Show a form for creating or editing a DNS record

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

if ($in{'new'}) {
	# Adding a new record
	}
else {
	# Editing existing one
	($recs, $file) = &get_domain_dns_records_and_file($d);
	$file || &error($recs);
	}



