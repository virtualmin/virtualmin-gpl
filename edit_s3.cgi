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

print &ui_form_start("save_s3.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("id", $in{'id'});
print &ui_table_start($text{'s3_header'}, undef, 2);

# Access key
# XXX

# Secret key
# XXX

# Endpoint URL
# XXX

if (!$in{'new'}) {
	# Current users
	# XXX
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
