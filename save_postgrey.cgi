#!/usr/local/bin/perl
# Create, edit or delete one greylisting whitelist entry

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ReadParse();
&licence_status();
&error_setup($text{'editgrey_err'});
&obtain_lock_postgrey();

if (!$in{'new'}) {
	$data = &list_postgrey_data($in{'type'});
	my $old = $data->[$in{'index'}];
	$old || &error($text{'editgrey_gone'});
	$d = { %$old };
	$d->{'cmts'} = [ @{$old->{'cmts'} || []} ];
	}
else {
	$d = { };
	}

if ($in{'delete'}) {
	# Delete one entry
	&delete_postgrey_data($in{'type'}, $d);
	}
else {
	# Validate inputs
	$in{'value'} =~ /^\S+$/ || &error($text{'editgrey_evalue'.$in{'type'}});
	if (&get_postgrey_type() eq 'milter' &&
	    $in{'type'} eq 'clients' &&
	    &postgrey_milter_is_ip_cidr($in{'value'})) {
		$in{'re'} = 0;
		}
	if (&get_postgrey_type() eq 'milter' &&
	    $in{'type'} eq 'recipients' &&
	    !$in{'re'} &&
	    $in{'value'} !~ /^[^@\s]+@[^@\s]+$/) {
		&error($text{'editgrey_ercptmilter'});
		}
	$d->{'value'} = $in{'value'};
	$d->{'re'} = $in{'re'};
	if ($in{'re'}) {
		my $re = $in{'value'};
		eval { 'foo' =~ /$re/; };
		if ($@) {
			&error(&text('editgrey_eregexp', "$@"));
			}
		}
	@cmts = grep { /\S/ } split(/\r?\n/, $in{'cmts'});
	$d->{'cmts'} = \@cmts;
	if (&find_duplicate_postgrey_data($in{'type'}, $d,
			$in{'new'} ? undef : $d->{'index'})) {
		&error(&text('editgrey_eduplicate',
			     "<tt>".&html_escape($d->{'value'})."</tt>"));
		}

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

