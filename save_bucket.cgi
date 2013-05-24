#!/usr/local/bin/perl
# Create, update or delete an S3 bucket

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_buckets() || &error($text{'buckets_ecannot'});

# Get the account
@accounts = &list_all_s3_accounts();
($account) = grep { $_->[0] eq $in{'account'} } @accounts;
$account || &error($text{'bucket_eagone'});

# Get the bucket(s)
$buckets = &s3_list_buckets(@$account);
ref($buckets) || &error(&text('bucket_elist', $buckets));
if (!$in{'new'}) {
	($bucket) = grep { $_->{'Name'} eq $in{'name'} } @$buckets;
	$bucket || &error($text{'bucket_egone'});
	$info = &s3_get_bucket(@$account, $in{'name'});
	}

if ($in{'delete'}) {
	# Just delete it
	&error_setup($text{'bucket_derr'});
	# XXX
	}
else {
	# Validate permissions
	&error_setup($text{'bucket_err'});
	# XXX

	# Validate expiry policy
	# XXX

	if ($in{'new'}) {
		# Validate inputs
		$in{'name'} =~ /^[a-z0-9\-\_\-]+$/i ||
			&error($text{'bucket_ename'});
		($clash) = grep { $_->{'Name'} eq $in{'name'} } @$buckets;
		$clash && &error($text{'bucket_eeclash'});

		# Create the bucket
		$err = &init_s3_bucket(@$account, $in{'name'}, 1,
				       $in{'location'});
		&error($err) if ($err);
		}

	# Apply permisisons

	# Apply expiry policy
	}

&redirect("list_buckets.cgi");
