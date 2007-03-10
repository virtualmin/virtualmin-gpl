#!/usr/local/bin/perl
# Show a form for importing a backup from some other control panel

require './virtual-server-lib.pl';
&require_migration();
&can_migrate_servers() || &error($text{'migrate_ecannot'});

&ui_print_header(undef, $text{'migrate_title'}, "");

print "$text{'migrate_desc'}<p>\n";

print &ui_form_start("migrate.cgi", "form-data");
print &ui_table_start($text{'migrate_header'}, "width=100%", 4);

print &ui_table_row($text{'migrate_file'},
	&ui_radio("mode", 0,
		[ [ 0, &text('migrate_file0', &ui_upload("upload"))."<br>" ],
		  [ 1, &text('migrate_file1', &ui_textbox("file", undef, 30)).
		         &file_chooser_button("file") ] ]), 3);

print &ui_table_row($text{'migrate_type'},
		    &ui_select("type", undef,
			[ map { [ $_, $text{'migrate_'.$_} ] }
			      @migration_types ]), 3);

print &ui_table_row($text{'migrate_dom'},
		   &ui_textbox("dom", undef, 40), 3);

print &ui_table_row($text{'migrate_user'},
		   &ui_textbox("user", undef, 20));

print &ui_table_row($text{'migrate_pass'},
		   &ui_textbox("pass", undef, 20));

print &ui_table_row($text{'migrate_webmin'},
		    &ui_yesno_radio("webmin", 1));

foreach $t (&list_templates()) {
	next if ($t->{'deleted'});
	next if (!$t->{'for_parent'});	# XXX
	push(@tmpls, $t);
	}
print &ui_table_row($text{'migrate_template'},
		    &ui_select("template", 0, 
			[ map { [ $_->{'id'}, $_->{'name'} ] } @tmpls ]));

# IP to assign
print &ui_table_row($text{'migrate_ip'}, &virtual_ip_input(\@tmpls), 3);

# Parent user
@doms = sort { $a->{'user'} cmp $b->{'user'} }
	     grep { $_->{'unix'} } &list_domains();
if (@doms) {
	print &ui_table_row($text{'migrate_parent'},
			    &ui_radio("parent_def", 1,
				      [ [ 1, $text{'migrate_parent1'} ],
					[ 0, $text{'migrate_parent0'} ] ])."\n".
			    &ui_select("parent", undef,
				       [ map { [ $_->{'user'} ] } @doms ]), 3);
	}
else {
	print &ui_hidden("parent_def", 1);
	}

# Domain prefix
print &ui_table_row($text{'migrate_prefix'},
		   &ui_opt_textbox("prefix", undef, 20, $text{'migrate_auto'}));

print &ui_table_end();
print &ui_form_end([ [ "migrate", $text{'migrate_show'} ] ]);

&ui_print_footer("", $text{'index_return'});

