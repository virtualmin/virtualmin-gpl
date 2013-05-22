#!/usr/local/bin/perl
# Show details of an S3 bucket

require './virtual-server-lib.pl';
&ReadParse();
can_backup_buckets() || &error($text{'buckets_ecannot'});

@accounts = &list_all_s3_accounts();
if ($in{'new'}) {
	&ui_print_header(undef, $text{'bucket_title1'}, "");
	$bucket = { };
	$info = { };
	}
else {
	&ui_print_header(undef, $text{'bucket_title2'}, "");

	# Get the account and bucket
	($account) = grep { $_->[0] eq $in{'account'} } @accounts;
	$account || &error($text{'bucket_eagone'});
	$buckets = &s3_list_buckets(@$account);
	ref($buckets) || &error(&text('bucket_elist', $buckets));
	($bucket) = grep { $_->{'Name'} eq $in{'name'} } @$buckets;
	$bucket || &error($text{'bucket_egone'});
	$info = &s3_get_bucket(@$account, $in{'name'});
	}

print &ui_form_start("save_bucket.cgi", "post");
if ($in{'new'}) {
	print &ui_hidden("new", 1);
	}
else {
	print &ui_hidden("account", $in{'account'});
	print &ui_hidden("name", $in{'name'});
	}

print &ui_table_start($text{'bucket_header'}, undef, 2);
if ($in{'new'}) {
	# Can select account, enter a bucket name and choose a location
	print &ui_table_row($text{'bucket_account'},
		&ui_select("account", undef, [ map { $_->[0] } @accounts ]));

	print &ui_table_row($text{'bucket_name'},
		&ui_textbox("name", undef, 40));

	print &ui_table_row($text{'bucket_location'},
		&ui_select("location", "us-west-1",
			   [ &s3_list_locations(@$account) ]));
	}
else {
	# Account, bucket and location are fixed
	print &ui_table_row($text{'bucket_account'},
		"<tt>$in{'account'}</tt>");

	print &ui_table_row($text{'bucket_name'},
		"<tt>$in{'name'}</tt>");

	print &ui_table_row($text{'bucket_location'},
		"<tt>$info->{'location'}</tt>");

	print &ui_table_row($text{'bucket_owner'},
		"<tt>$info->{'acl'}->{'Owner'}->{'DisplayName'}</tt>");
	}

# Bucket permissions
$ptable = &ui_columns_start([ $text{'bucket_type'},
			      $text{'bucket_grantee'},
			      $text{'bucket_perm'} ]);
$grant = $in{'new'} ? [ ] : $info->{'acl'}->{'AccessControlList'}->{'Grant'};
$i = 0;
foreach my $g (@$grant, { }) {
	$ptable .= &ui_columns_row([
		&ui_select("type_$i",
			   $g->{'Grantee'}->{'xsi:type'},
			   [ [ "", "&nbsp;" ],
			     [ "CanonicalUser", $text{'bucket_user'} ],
			     [ "Group", $text{'bucket_group'} ] ]),
		&ui_textbox("grantee_$i", $g->{'Grantee'}->{'DisplayName'}, 30),
		&ui_select("perm_$i", $g->{'Permission'} || "READ",
			   [ "FULL_CONTROL", "READ", "WRITE", "READ_ACP",
			     "WRITE_ACP" ]),
		]);
	$i++;
	}
$ptable .= &ui_columns_end();
print &ui_table_row($text{'bucket_grant'}, $ptable);

# Expiry policy
# XXX

print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("list_buckets.cgi", $text{'buckets_return'});

