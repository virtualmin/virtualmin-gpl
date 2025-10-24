#!/usr/local/bin/perl
# Show details of an S3 bucket

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_buckets() || &error($text{'buckets_ecannot'});

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
	$buckets = &s3_list_buckets($account->[0], $account->[1]);
	ref($buckets) || &error(&text('bucket_elist', $buckets));
	($bucket) = grep { $_->{'Name'} eq $in{'name'} } @$buckets;
	$bucket || &error($text{'bucket_egone'});
	$info = &s3_get_bucket($account->[0], $account->[1], $in{'name'});
	ref($info) || &error(&text('bucket_einfo', $info));
	}

print &ui_form_start("save_bucket.cgi", "post");
if ($in{'new'}) {
	print &ui_hidden("new", 1);
	}
else {
	print &ui_hidden("account", $in{'account'});
	print &ui_hidden("name", $in{'name'});
	}

print &ui_table_start($text{'bucket_header'}, "width=100%", 4);
if ($in{'new'}) {
	# Can select account, enter a bucket name and choose a location
	print &ui_table_row($text{'bucket_account'},
		&ui_select("account", undef,
		   [ map { [ $_->[0], $_->[3]->{'desc'} ] } @accounts ]));

	print &ui_table_row($text{'bucket_name'},
		&ui_textbox("name", undef, 40));

	print &ui_table_row($text{'bucket_location'},
		&ui_select("location", $config{'s3_location'},
		   [ [ "", $text{'default'} ],
		     &s3_list_locations($account->[0], $account->[1]) ]));
	}
else {
	# Account, bucket and location are fixed
	if ($account->[3]) {
		print &ui_table_row($text{'bucket_account2'},
			$account->[3]->{'desc'} || $account->[3]->{'access'});
		}
	else {
		print &ui_table_row($text{'bucket_account'},
			"<tt>$in{'account'}</tt>");
		}

	print &ui_table_row($text{'bucket_name'},
		"<tt>$in{'name'}</tt>");

	print &ui_table_row($text{'bucket_location'},
		$info->{'location'} ? "<tt>$info->{'location'}</tt>"
				    : $text{'default'});

	print &ui_table_row($text{'bucket_owner'},
	    "<tt>".($info->{'acl'}->{'Owner'}->{'DisplayName'} ||
		    $info->{'acl'}->{'Owner'}->{'ID'})."</tt>", 3);

	# Show file count and size
	$files = &s3_list_files($account->[0], $account->[1], $in{'name'});
	if (ref($files)) {
		$size = 0;
		foreach my $f (@$files) {
			$size += $f->{'Size'};
			}
		print &ui_table_row($text{'bucket_size'},
			@$files ? &text('bucket_sizestr', &nice_size($size),
							  scalar(@$files))
				: $text{'bucket_empty'});
		}
	}

# Bucket permissions
$ptable = &ui_columns_start([ $text{'bucket_type'},
			      $text{'bucket_grantee'},
			      $text{'bucket_perm'} ]);
$grant = $in{'new'} ? [ ] : $info->{'acl'}->{'Grants'};
$i = 0;
foreach my $g (@$grant, { }) {
	$grantee = $g->{'Grantee'}->{'DisplayName'} ||
		   $g->{'Grantee'}->{'ID'} ||
		   $g->{'Grantee'}->{'URI'};
	$grantee =~ s/^\Q$s3_groups_uri\E//;
	$ptable .= &ui_columns_row([
		&ui_select("type_$i",
			   $g->{'Grantee'}->{'Type'},
			   [ [ "", "&nbsp;" ],
			     [ "CanonicalUser", $text{'bucket_user'} ],
			     [ "Group", $text{'bucket_group'} ] ]),
		&ui_textbox("grantee_$i", $grantee, 30),
		&ui_select("perm_$i", $g->{'Permission'} || "READ",
			   [ "FULL_CONTROL", "READ", "WRITE", "READ_ACP",
			     "WRITE_ACP" ]),
		]);
	$i++;
	}
$ptable .= &ui_columns_end();
print &ui_table_row($text{'bucket_grant'}, $ptable, 3);

# Lifecycle policies
$ltable = &ui_columns_start([ $text{'bucket_lprefix'},
			      $text{'bucket_lstatus'},
			      $text{'bucket_lglacier'},
			      $text{'bucket_ldelete'} ]);
$lifecycle = !$in{'new'} && $info->{'lifecycle'} ?
		$info->{'lifecycle'}->{'Rules'} : [ ];
$i = 0;
foreach my $l (@$lifecycle, { }) {
	$prefix = $l->{'Filter'} ? $l->{'Filter'}->{'Prefix'} : undef;
	$mode = !(keys %$l) ? 2 : $prefix ? 0 : 1;
	my $trans = $l->{'Transitions'} && @{$l->{'Transitions'}} ?
			$l->{'Transitions'}->[0] : undef;
	$ltable .= &ui_columns_row([
		&ui_radio("lprefix_def_$i", $mode,
			  [ [ 2, $text{'bucket_lnone'}."<br>" ],
			    [ 1, $text{'bucket_lall'}."<br>" ],
			    [ 0, $text{'bucket_lstart'}." ".
				 &ui_textbox("lprefix_$i", $prefix, 10) ] ]),
		&ui_checkbox("lstatus_$i", 1, "",
			     $l->{'Status'} eq 'Enabled'),
		&ui_select("class_$i", $trans->{'StorageClass'},
			[ "GLACIER", "STANDARD_IA", "ONEZONE_IA",
			  "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"]).
		"<br>\n".
		&days_date_field("lglacier_$i", $trans),
		&days_date_field("ldelete_$i", $l->{'Expiration'}),
		]);
	$i++;
	}
$ltable .= &ui_columns_end();
print &ui_table_row($text{'bucket_lifecycle'}, $ltable, 3);

# Logging settings
print &ui_table_row($text{'bucket_logging'},
	&ui_radio_table("logging_def", $info->{'logging'} ? 0 : 1,
		[ [ 1, $text{'bucket_logging_def'} ],
		  [ 0, &text('bucket_logging_target',
			&ui_textbox("ltarget",
			  $info->{'logging'}->{'TargetBucket'}, 20),
			&ui_textbox("lprefix",
			  $info->{'logging'}->{'TargetPrefix'}, 10)) ],
		]), 3);

print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("list_buckets.cgi", $text{'buckets_return'});

# days_date_field(name, object)
# Returns HTML for selecting a day or date policy
sub days_date_field
{
local ($name, $obj) = @_;
local $mode = $obj->{'Days'} ? 1 : $obj->{'Date'} ? 2 : 0;
local ($y, $m, $d) = $obj->{'Date'} =~ /^(\d+)\-(\d+)\-(\d+)/ ?
			($1, $2, $3) : ( );
return &ui_radio($name, $mode,
	[ [ 0, $text{'bucket_lnever'}."<br>" ],
	  [ 1, &text('bucket_ldays',
	          &ui_textbox($name."_days", $obj->{'Days'}, 5))."<br>" ],
	  [ 2, &text('bucket_ldate',
		  &ui_date_input($d, $m, $y, $name."_day", $name."_month",
				 $name."_year")) ] ]);
}
