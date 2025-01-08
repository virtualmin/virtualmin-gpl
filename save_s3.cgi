#!/usr/local/bin/perl
# Create, update or delete an S3 acccount

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($in{'delete'} ? $text{'s3_err2'} : $text{'s3_err'});
&can_cloud_providers() || &error($text{'s3s_ecannot'});

# Get the account
my @users;
my $s3;
my $olds3;
if ($in{'new'}) {
	$s3 = { };
	}
else {
	($s3) = grep { $_->{'id'} eq $in{'id'} } &list_s3_accounts();
	$s3 || &error($text{'s3_egone'});
	@users = grep { &backup_uses_s3_account($_, $s3) }
		      &list_scheduled_backups();
	$olds3 = { %$s3 };
	}

if ($in{'delete'}) {
	# Delete unless in use
	@users && &error(&text('s3_eusers', scalar(@users)));
	&delete_s3_account($s3);
	&webmin_log("delete", "s3", $s3->{'access'});
	}
else {
	# Validate inputs
	$s3->{'desc'} = $in{'desc'};
	$in{'access'} =~ /^\S+$/ || &error($text{'backup_eakey'});
	$s3->{'access'} = $in{'access'};
	$in{'secret'} =~ /^\S+$/ || &error($text{'backup_eskey'});
	$s3->{'secret'} = $in{'secret'};
	if ($in{'endpoint_def'}) {
		delete($s3->{'endpoint'});
		$s3->{'location'} = $in{'location'};
		}
	else {
		$in{'endpoint'} =~ s/^(http|https):\/\///;
		my ($host, $port) = split(/:/, $in{'endpoint'});
		&to_ipaddress($host) ||
			&error($text{'cloud_es3_endpoint'});
		!$port || $port =~ /^\d+$/ ||
			&error($text{'cloud_es3_endport'});
		$s3->{'endpoint'} = $in{'endpoint'};
		$s3->{'location'} = $in{'location2'};
		}
	$s3->{'id'} ||= &domain_id();
	if ($s3->{'location'}) {
		@locs = &s3_list_locations($s3);
		!@locs || &indexof($s3->{'location'}, @locs) >= 0 ||
			&error($text{'s3_elocation'});
		}

	# Validate that it works
	my $buckets = &s3_list_buckets($s3);
	if (!ref($buckets)) {
		&delete_s3_account($s3) if ($in{'new'});
		&error(&text('s3_echeck', $buckets));
		}

	# Save the account
	&save_s3_account($s3);

	if (!$in{'new'}) {
		# Update existing backups if the keys changed
		foreach my $sched (@users) {
			my @newdests;
			foreach my $dest (&get_scheduled_backup_dests($sched)) {
				my @p = &parse_backup_url($dest);
				if ($p[0] == 3 && ($p[1] eq $olds3->{'access'} ||
						   $p[2] eq $olds3->{'secret'})) {
					$p[1] = $s3->{'access'};
					$p[2] = $s3->{'secret'} if ($p[2]);
					push(@newdests, &join_backup_url(@p));
					}
				else {
					push(@newdests, $dest);
					}
				}
			$sched->{'dest'} = $newdests[0];
			for(my $i=1; $i<@newdests; $i++) {
				$sched->{'dest'.$i} = $newdests[$i];
				}
			&save_scheduled_backup($sched);
			}
		}

	&webmin_log($in{'new'} ? "create" : "update", "s3", $s3->{'access'});
	}

&redirect("list_s3s.cgi");
