#!/usr/local/bin/perl
# Show a form for selecting Webmin servers to use as secondary MXs for mail

require './virtual-server-lib.pl';
&foreign_require("servers", "servers-lib.pl");
&can_edit_templates() || &error($text{'newmxs_ecannot'});
&ui_print_header(undef, $text{'newmxs_title'}, "", "newmxs");

@servers = grep { $_->{'user'} } &servers::list_servers();
%mxs = map { $_->{'id'}, $_ } &list_mx_servers();
if (@servers) {
	print &ui_form_start("save_newmxs.cgi", "post");

	# Server selector
	@tds = ( "width=5" );
	$stable = &ui_columns_start([ "",
				      $text{'newmxs_server'},
				      $text{'newmxs_mxname'} ], undef,0, \@tds);
	foreach $s (@servers) {
		$mx = $mxs{$s->{'id'}};
		$stable .= &ui_columns_row(
		  [ &ui_checkbox("servers", $s->{'id'}, undef, $mx),
		    $s->{'desc'} || $s->{'host'},
		    &ui_opt_textbox("mxname_".$s->{'id'},
				    $mx ? $mx->{'mxname'} : undef, 30,
				    $text{'newmxs_same'}) ],
		  \@tds);
		}
	$stable .= &ui_columns_end(),"<br>\n";
	print $stable;

	# Option to add existing mail domains to secondary
	print &ui_checkbox("addexisting", 1, &hlink($text{'newmxs_add'},
						    "newmxs_add")),"<p>\n";

	print &ui_form_end([ [ "save", $text{'save'} ] ]);
	}
else {
	print "<b>$text{'newmxs_none'}</b><p>\n";
	}

&ui_print_footer("", $text{'index_return'});

