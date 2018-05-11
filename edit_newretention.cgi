#!/usr/local/bin/perl
# Show a form for setting up global mailbox cleanup rules

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'retention_ecannot'});
&ui_print_header(undef, $text{'newretention_title'}, "", "retention");

print $text{'retention_desc'},"<p>\n";
print &ui_form_start("save_newretention.cgi", "post");
print &ui_table_start($text{'retention_header'}, undef, 2);

# Automatic cleanup policy
print &ui_table_row($text{'retention_policy'},
	&ui_radio_table("policy", $config{'retention_policy'} || 0,
		[ [ 0, $text{'retention_disabled'} ],
		  [ 1, &text('retention_days',
			&ui_textbox("days", $config{'retention_days'}, 5)) ],
		  [ 2, &text('retention_size',
			&ui_bytesbox("size", $config{'retention_size'}, 5)) ]
		]));

# Apply to domains
@alldoms = &list_domains();
print &ui_table_row($text{'retention_doms'},
	&ui_radio("mode", $config{'retention_mode'} || 0,
		  [ [ 0, $text{'retention_domsall'}."<br>" ],
		    [ 1, $text{'retention_domonly'}."<br>" ],
		    [ 2, $text{'retention_domexcept'}."<br>" ] ]).
	&servers_input("doms", [ split(/\s+/, $config{'retention_doms'}) ],
		       \@alldoms));

# Apply to folders
print &ui_table_row($text{'retention_folders'},
	&ui_radio("folders", $config{'retention_folders'} || 0,
		  [ [ 0, $text{'retention_folders0'} ],
		    [ 1, $text{'retention_folders1'} ] ]));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
