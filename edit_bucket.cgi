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

print &ui_table_start($text{'bucket_header'}, "width=100%", 2);
if ($in{'new'}) {
	# Can select account, enter a bucket name and choose a location
	print &ui_table_row($text{'bucket_account'},
		&ui_select("account", undef, [ map { $_->[0] } @accounts ]));

	print &ui_table_row($text{'bucket_name'},
		&ui_textbox("name", undef, 40));

	print &ui_table_row($text{'bucket_location'},
		&ui_select("location", $config{'s3_location'},
			   [ [ "", $text{'default'} ],
			     &s3_list_locations(@$account) ]));
	}
else {
	# Account, bucket and location are fixed
	print &ui_table_row($text{'bucket_account'},
		"<tt>$in{'account'}</tt>");

	print &ui_table_row($text{'bucket_name'},
		"<tt>$in{'name'}</tt>");

	print &ui_table_row($text{'bucket_location'},
		$info->{'location'} ? "<tt>$info->{'location'}</tt>"
				    : $text{'default'});

	print &ui_table_row($text{'bucket_owner'},
	    "<tt>$info->{'acl'}->{'Owner'}->[0]->{'DisplayName'}->[0]</tt>");

	# Show file count and size
	$files = &s3_list_files(@$account, $in{'name'});
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
$grant = $in{'new'} ? [ ] :
	    $info->{'acl'}->{'AccessControlList'}->[0]->{'Grant'};
$i = 0;
foreach my $g (@$grant, { }) {
	$grantee = $g->{'Grantee'}->[0]->{'DisplayName'}->[0] ||
		   $g->{'Grantee'}->[0]->{'URI'}->[0];
	$grantee =~ s/^\Q$s3_groups_uri\E//;
	$ptable .= &ui_columns_row([
		&ui_select("type_$i",
			   $g->{'Grantee'}->[0]->{'xsi:type'},
			   [ [ "", "&nbsp;" ],
			     [ "CanonicalUser", $text{'bucket_user'} ],
			     [ "Group", $text{'bucket_group'} ] ]),
		&ui_textbox("grantee_$i", $grantee, 30),
		&ui_select("perm_$i", $g->{'Permission'}->[0] || "READ",
			   [ "FULL_CONTROL", "READ", "WRITE", "READ_ACP",
			     "WRITE_ACP" ]),
		]);
	$i++;
	}
$ptable .= &ui_columns_end();
print &ui_table_row($text{'bucket_grant'}, $ptable);

# Lifecycle policies
$ltable = &ui_columns_start([ $text{'bucket_lprefix'},
			      $text{'bucket_lstatus'},
			      $text{'bucket_lglacier'},
			      $text{'bucket_ldelete'} ]);
$lifecycle = !$in{'new'} && $info->{'lifecycle'} ?
		$info->{'lifecycle'}->{'Rule'} : [ ];
$i = 0;
foreach my $l (@$lifecycle, { }) {
	$prefix = $l->{'Prefix'} ? $l->{'Prefix'}->[0] : undef;
	$prefix = undef if (ref($prefix));
	$mode = !(keys %$l) ? 2 : $prefix ? 0 : 1;
	$ltable .= &ui_columns_row([
		&ui_radio("lprefix_def_$i", $mode,
			  [ [ 2, $text{'bucket_lnone'}."<br>" ],
			    [ 1, $text{'bucket_lall'}."<br>" ],
			    [ 0, $text{'bucket_lstart'}." ".
				 &ui_textbox("lprefix_$i", $prefix, 10) ] ]),
		&ui_checkbox("lstatus_$i", 1, "",
			     $l->{'Status'}->[0] eq 'Enabled'),
		&days_date_field("lglacier_$i", $l->{'Transition'}->[0]),
		&days_date_field("ldelete_$i", $l->{'Expiration'}->[0]),
		]);
	$i++;
	}
$ltable .= &ui_columns_end();
print &ui_table_row($text{'bucket_lifecycle'}, $ltable);

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
local ($y, $m, $d) = $obj->{'Date'}->[0] =~ /^(\d+)\-(\d+)\-(\d+)/ ?
			($1, $2, $3) : ( );
return &ui_radio($name, $mode,
	[ [ 0, $text{'bucket_lnever'}."<br>" ],
	  [ 1, &text('bucket_ldays',
	          &ui_textbox($name."_days", $obj->{'Days'}->[0], 5))."<br>" ],
	  [ 2, &text('bucket_ldate',
		  &ui_date_input($d, $m, $y, $name."_day", $name."_month",
				 $name."_year")) ] ]);
}
