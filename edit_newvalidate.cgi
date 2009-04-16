#!/usr/local/bin/perl
# Show a form for validating multiple servers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newvalidate_ecannot'});
&ui_print_header(undef, $text{'newvalidate_title'}, "", "newvalidate");

print "$text{'newvalidate_desc'}<p>\n";
print &ui_form_start("validate.cgi", "post");
print &ui_table_start($text{'newvalidate_header'}, undef, 2);

# Servers to check
@doms = &list_domains();
print &ui_table_row(&hlink($text{'newvalidate_servers'}, "newvalidate_servers"),
		    &ui_radio("servers_def", 1,
			[ [ 1, $text{'newips_all'} ],
			  [ 0, $text{'newips_sel'} ] ])."<br>\n".
		    &servers_input("servers", [ ], \@doms));

# Features to check
foreach $f (@validate_features) {
	push(@fopts, [ $f, $text{'feature_'.$f} ]);
	}
foreach $f (&list_feature_plugins()) {
	if (&plugin_defined($f, "feature_validate")) {
		push(@fopts, [ $f, &plugin_call($f, "feature_name") ]);
		}
	}
print &ui_table_row(&hlink($text{'newvalidate_feats'}, "newvalidate_feats"),
		    &ui_radio("features_def", 1,
			[ [ 1, $text{'newvalidate_all'} ],
			  [ 0, $text{'newvalidate_sel'} ] ])."<br>\n".
		    &ui_select("features", undef,
			       \@fopts, 10, 1));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newvalidate_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
