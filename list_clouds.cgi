#!/usr/local/bin/perl
# Show a list of cloud storage providers

require './virtual-server-lib.pl';
&ReadParse();
can_cloud_providers() || &error($text{'clouds_ecannot'});

&ui_print_header(undef, $text{'clouds_title'}, "", "clouds");

@provs = &list_cloud_providers();
print &ui_columns_start([ $text{'clouds_name'},
			  $text{'clouds_state'},
			  $text{'clouds_users'} ]);
foreach my $p (@provs) {
	print &ui_columns_row([ &ui_link("edit_cloud.cgi?name=$p->{'name'}",
					 $p->{'desc'}),
				&$sfunc($p),
				$users ]);
	}
print &ui_columns_end();

&ui_print_footer("", $text{'index_return'});
