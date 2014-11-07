#!/usr/local/bin/perl
# Save custom shells

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newshells_err'});
&can_edit_templates() || &error($text{'newshells_ecannot'});

if ($in{'defs'}) {
	# Reverting to defaults
	&save_available_shells(undef);
	}
else {
	# Validate and save shells. Must be at least one for mailboxes and
	# admins, and one default for each
	for($i=0; defined($in{"shell_$i"}); $i++) {
		next if (!$in{"shell_$i"});
		-r $in{"shell_$i"} || &error(&text('newshells_eshell', $i+1));
		$in{"desc_$i"} =~ /\S/ || &error(&text('newshells_edesc',$i+1));
		local %shell = ( 'shell' => $in{"shell_$i"},
				 'desc' => $in{"desc_$i"},
				 'owner' => $in{"owner_$i"},
				 'mailbox' => $in{"mailbox_$i"},
				 'reseller' => $in{"reseller_$i"},
				 'default' => $in{"default_$i"},
				 'id' => $in{"id_$i"},
				 'avail' => $in{"avail_$i"} );
		$shell{'owner'} || $shell{'mailbox'} || $shell{'reseller'} ||
			&error(&text('newshells_eowner', $i+1));
		push(@shells, \%shell);
		}
	@oshells = grep { $_->{'owner'} && $_->{'avail'} } @shells;
	@oshells || &error($text{'newshells_eowners'});
	@mshells = grep { $_->{'mailbox'} && $_->{'avail'} } @shells;
	@mshells || &error($text{'newshells_emailboxes'});
	@rshells = grep { $_->{'reseller'} && $_->{'avail'} } @shells;
	@rshells || &error($text{'newshells_eresellers'});
	@doshells = grep { $_->{'default'} } @oshells;
	@doshells == 1 || &error($text{'newshells_eownerdef'});
	@dmshells = grep { $_->{'default'} } @mshells;
	@dmshells == 1 || &error($text{'newshells_emailboxdef'});

	# Save them
	&save_available_shells(\@shells);
	}

&run_post_actions_silently();
&webmin_log("shells", undef, $in{'defs'});
&redirect("");

