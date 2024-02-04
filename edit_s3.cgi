#!/usr/local/bin/perl
# Show a form to edit or create an S3 account

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'s3s_ecannot'});

if ($in{'new'}) {
	&ui_print_header(undef, $text{'s3_title1'}, "");
	$s3 = { };
	}
else {
	&ui_print_header(undef, $text{'s3_title2'}, "");
	($s3) = grep { $_->{'id'} eq $in{'id'} } &list_s3_accounts();
	$s3 || &error($text{'s3_egone'});
	}

print $text{'s3_desc'},"<p>\n";

print &ui_form_start("save_s3.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("id", $in{'id'});
print &ui_table_start($text{'s3_header'}, undef, 2);

# Access key
print &ui_table_row($text{'s3_access'},
	&ui_textbox("access", $s3->{'access'}, 60));

# Secret key
print &ui_table_row($text{'s3_secret'},
	&ui_textbox("secret", $s3->{'secret'}, 60));

# Endpoint URL
print &ui_table_row($text{'s3_endpoint'},
	&ui_opt_textbox("endpoint", $s3->{'endpoint'}, 40,
			$text{'s3_endpoint_def'}, $text{'s3_endpoint_hp'}));

if (!$in{'new'}) {
	# Current users
	@users = grep { &backup_uses_s3_account($_, $s3) }
		      &list_scheduled_backups();
	$utable = "";
	if (@users) {
		$utable .= &ui_columns_start([
			$text{'sched_dest'}, $text{'sched_doms'},
			]);
		foreach my $s (@users) {
			@dests = &get_scheduled_backup_dests($s);
			@nices = map { &nice_backup_url($_, 1) } @dests;
			$utable .= &ui_columns_row([
				join("<br>\n", @nices),
				&nice_backup_doms($s),
				]);
			}
		$utable .= &ui_columns_end();
		}
	else {
		$utable = $text{'s3_nousers'};
		}
	print &ui_table_row($text{'s3_usedby'}, $utable);
	}

print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("list_s3s.cgi", $text{'s3s_return'});
