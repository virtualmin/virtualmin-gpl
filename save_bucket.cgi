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
	if ($in{'confirm'}) {
		# Just do it
		$err = &s3_delete_bucket(@$account, $in{'name'}, 0);
		&error($err) if ($err);
		&webmin_log("delete", "bucket", $in{'name'});
		&redirect("list_buckets.cgi");
		}
	else {
		# Ask first
		&ui_print_header(undef, $text{'bucket_title3'}, "");

		# Get size of all files
		$files = &s3_list_files(@$account, $in{'name'});
		ref($files) || &error($files);
		$size = 0;
		foreach my $f (@$files) {
			$size += $f->{'Size'};
			}

		# Show confirm form
		$ttname = "<tt>".&html_escape($in{'name'})."</tt>";
		print &ui_confirmation_form(
			"save_bucket.cgi",
			@$files ? &text('bucket_drusure', $ttname,
					scalar(@$files), &nice_size($size))
				: &text('bucket_drusure2', $ttname),
			[ [ "account", $in{'account'} ],
			  [ "name", $in{'name'} ],
			  [ "delete", 1 ] ],
			[ [ "confirm", $text{'bucket_dok'} ] ],
			);

		&ui_print_footer("list_buckets.cgi", $text{'buckets_return'});
		}
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

	&webmin_log($in{'new'} ? "create" : "modify", "bucket", $in{'name'});
	&redirect("list_buckets.cgi");
	}

