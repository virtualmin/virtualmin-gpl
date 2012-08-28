#!/usr/local/bin/perl
# save_alias.cgi
# Create, update or delete an alias

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_aliases() || &error($text{'aliases_ecannot'});

&obtain_lock_mail($d);
@aliases = &list_domain_aliases($d);
if (!$in{'new'}) {
	($virt) = grep { $_->{'from'} eq $in{'old'} } @aliases;
	$virt || &error($text{'alias_egone'});
	%oldvirt = %$virt;
	}
&error_setup($text{'alias_err'});

if ($in{'delete'}) {
	# Just delete the virtuser (and the autoreply file)
	if (defined(&get_simple_alias)) {
		$simple = &get_simple_alias($d, $virt);
		&delete_simple_autoreply($d, $simple) if ($simple);
		}
	&delete_virtuser($virt);
	&sync_alias_virtuals($d);
	&release_lock_mail($d);
	&run_post_actions_silently();
	&webmin_log("delete", "alias", $virt->{'from'}, $virt);
	}
else {
	# Verify and store core inputs
	$sfx = $in{'simplemode'};
	if ($in{'new'}) {
		($mleft, $mreason, $mmax) = &count_feature("aliases");
		$mleft == 0 && &error($text{'alias_ealiaslimit'});
		}
	if (!$in{$sfx.'name_def'}) {
		my $nerr = &valid_mailbox_name($in{$sfx.'name'});
		if ($nerr || $in{$sfx.'name'} =~ /\@/) {
			&error($text{'alias_ename'});
			}
		}
	$name = $in{$sfx.'name_def'} ? "" : $in{$sfx.'name'};
	$virt->{'from'} = $name."\@".$d->{'dom'};
	if ($can_alias_comments) {
		$virt->{'cmt'} = $in{$sfx.'cmt'};
		}

	if ($in{'simplemode'} eq 'complex') {
		# Verify and store complex inputs
		@values = &parse_alias($in{$sfx.'name_def'}, $in{$sfx.'name'},
			       %oldvirt ? $oldvirt{'to'} : undef, "alias", $d);
		@values || &error($text{'alias_enone'});
		$virt->{'to'} = \@values;
		}
	else {
		# Verify and store simple inputs
		$simple = &get_simple_alias($d, $virt);
		if ($simple) {
			# Remove existing autoreply file
			&delete_simple_autoreply($d, $simple);
			}
		$simple ||= { };
		&parse_simple_form($simple, \%in, $d, 0, 0, 0,
				   $virt->{'from'});
		&save_simple_alias($d, $virt, $simple);
		if ($simple->{'bounce'} && @{$virt->{'to'}} > 1) {
			# Cannot bounce and forward
			&error(&text('alias_ebounce'));
			}
		}

	# Make sure alias doesn't forward to itself
	foreach my $t (@{$virt->{'to'}}) {
		if ($t eq $virt->{'from'}) {
			&error($text{'alias_eloop'});
			}
		}

	if ($in{'new'}) {
		# Check for a clash
		if (&check_clash($name, $d->{'dom'})) {
			&error($text{'alias_eclash'});
			}

		# Create the virtuser
		&create_virtuser($virt);
		}
	else {
		if ($virt->{'from'} ne $in{'old'}) {
			# Has been renamed .. check for a clash
			if (&check_clash($name, $d->{'dom'})) {
				&error($text{'alias_eclash'});
				}
			}

		# Modify virtuser
		&modify_virtuser(\%oldvirt, $virt);
		}
	&sync_alias_virtuals($d);
	if ($in{'simplemode'} eq 'simple') {
		# Write out the autoreply file, if any
		&write_simple_autoreply($d, $simple);
		}
	&release_lock_mail($d);
	&run_post_actions_silently();
	if ($in{'new'}) {
		&webmin_log("create", "alias", $virt->{'from'}, $virt);
		}
	else {
		&webmin_log("modify", "alias", $virt->{'from'}, $virt);
		}
	}
&redirect("list_aliases.cgi?dom=$in{'dom'}&show=$in{'show'}");


