#!/usr/local/bin/perl
# Show a list of S3 buckets

require './virtual-server-lib.pl';
&ReadParse();
can_backup_buckets() || &error($text{'buckets_ecannot'});

&ui_print_header(undef, $text{'buckets_title'}, "", "buckets");

# Find all S3 accounts
@accounts = &list_all_s3_accounts();
if (!@accounts) {
	&ui_print_endpage($text{'buckets_eaccounts'});
	}

# Find all buckets
@buckets = ( );
@errs = ( );
foreach my $a (@accounts) {
	my $buckets = &s3_list_buckets(@$a);
	if (ref($buckets)) {
		foreach my $b (@$buckets) {
			$b->{'s3_account'} = $a;
			push(@buckets, $b);
			}
		}
	else {
		push(@errs, $buckets);
		}
	}

# Show them, if any
@links = ( "<a href='edit_bucket.cgi?new=1'>$text{'buckets_add'}</a>" );
if (@buckets) {
	print &ui_links_row(\@links);
	print &ui_columns_start([ $text{'buckets_name'},
				  $text{'buckets_account'},
				  $text{'buckets_created'} ]);
	foreach my $b (sort { $a->{'Name'} cmp $b->{'Name'} } @buckets) {
		print &ui_columns_row([
			"<a href='edit_bucket.cgi?name=".&urlize($b->{'Name'}).
			  "&account=".&urlize($b->{'s3_account'}->[0]).
			  "'>".&html_escape($b->{'Name'})."</a>",
			$b->{'s3_account'}->[0],
			&make_date(&s3_parse_date($b->{'CreationDate'})),
			]);
		}
	print &ui_columns_end();
	}
elsif (@errs) {
	print "<b>",&text('buckets_errs', join(", ", @errs)),"</b><p>\n";
	}
else {
	print "<b>$text{'buckets_none'}</b><p>\n";
	}
print &ui_links_row(\@links);

&ui_print_footer("", $text{'index_return'});

