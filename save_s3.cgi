#!/usr/local/bin/perl
# Create, update or delete an S3 acccount

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($in{'delete'} ? $text{'s3_err2'} : $text{'s3_err'});
&can_cloud_providers() || &error($text{'s3s_ecannot'});

# Get the account
my @users;
my $s3;
if ($in{'new'}) {
	$s3 = { };
	}
else {
	($s3) = grep { $_->{'id'} eq $in{'id'} } &list_s3_accounts();
	$s3 || &error($text{'s3_egone'});
	@users = grep { &backup_uses_s3_account($_, $s3) }
		      &list_scheduled_backups();
	}

if ($in{'delete'}) {
	# Delete unless in use
	@users && &error(&text('s3_eusers', scalar(@users)));
	&delete_s3_account($s3);
	&webmin_log("delete", "s3", $s3->{'access'});
	}
else {
	# Validate inputs
	$in{'access'} =~ /^\S+$/ || &error($text{'backup_eakey'});
	$s3->{'access'} = $in{'access'};
	$in{'secret'} =~ /^\S+$/ || &error($text{'backup_eskey'});
	$s3->{'secret'} = $in{'secret'};
	if ($in{'endpoint_def'}) {
		delete($s3->{'endpoint'});
		}
	else {
		$in{'endpoint'} =~ s/^(http|https):\/\///;
		my ($host, $port) = split(/:/, $in{'endpoint'});
		&to_ipaddress($host) ||
			&error($text{'cloud_es3_endpoint'});
		!$port || $port =~ /^\d+$/ ||
			&error($text{'cloud_es3_endport'});
		$s3->{'endpoint'} = $in{'endpoint'};
		}

	# Validate that it works
	$get_s3_account_cache{$s3->{'access'}} = $s3;
	my $buckets = &s3_list_buckets($s3->{'access'}, $s3->{'secret'});
	&error(&text('s3_echeck', $buckets)) if (!ref($buckets));

	# Save the account
	&save_s3_account($s3);

	# Update existing backups
	foreach my $s (@users) {
		# XXX
		}

	&webmin_log($in{'new'} ? "create" : "update", "s3", $s3->{'access'});
	}

&redirect("list_s3s.cgi");
