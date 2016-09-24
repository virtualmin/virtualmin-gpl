#!/usr/local/bin/perl
# Create, edit or delete one greylisting whitelist entry

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ReadParse();
&error_setup($text{'editgrey_err'});
&obtain_lock_postgrey();

if (!$in{'new'}) {
	$data = &list_postgrey_data($in{'type'});
	$d = $data->[$in{'index'}];
	$d || &error($text{'editgrey_gone'});
	}

if ($in{'delete'}) {
	# Delete one entry
	&delete_postgrey_data($in{'type'}, $d);
	}
else {
	# Validate inputs
	$in{'value'} =~ /^\S+$/ || &error($text{'editgrey_evalue'.$in{'type'}});
	$d->{'value'} = $in{'value'};
	$d->{'re'} = $in{'re'};
	if ($in{'re'}) {
		eval "'foo' =~ /$in{'value'}/";
		if ($@) {
			&error(&text('editgrey_eregexp', "$@"));
			}
		}
	@cmts = grep { /\S/ } split(/\r?\n/, $in{'cmts'});
	$d->{'cmts'} = \@cmts;

	# Create or update
	if ($in{'new'}) {
		&create_postgrey_data($in{'type'}, $d);
		}
	else {
		&modify_postgrey_data($in{'type'}, $d);
		}
	}

&release_lock_postgrey();
&apply_postgrey_data();
&run_post_actions_silently();
&webmin_log($in{'delete'} ? 'delete' : $in{'new'} ? 'create' : 'modify',
	    'postgrey', $d->{'value'}, { 'type' => $in{'type'} });
&redirect("postgrey.cgi?type=$in{'type'}");

