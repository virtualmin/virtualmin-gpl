#!/usr/local/bin/perl
# Delete several greylisting whitelist entries

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ReadParse();
&error_setup($text{'delgrey_err'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'delgrey_enone'});

# Delete them, in reverse index order
&obtain_lock_postgrey();
$data = &list_postgrey_data($in{'type'});
foreach $i (sort { $b <=> $a } @d) {
	$d = $data->[$i];
	$d || &error($text{'editgrey_gone'});
	&delete_postgrey_data($in{'type'}, $d);
	}
&release_lock_postgrey();
&apply_postgrey_data();

&webmin_log('deletes', 'postgrey', scalar(@d), { 'type' => $in{'type'} });

&redirect("postgrey.cgi?type=$in{'type'}");

