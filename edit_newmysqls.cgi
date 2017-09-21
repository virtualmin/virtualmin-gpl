#!/usr/local/bin/perl
# Show a list of known remote MySQL servers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmysqls_ecannot'});
&ui_print_header(undef, $text{'newmysqls_title'}, "", "newmysqls");

# Show a table of current servers
@alldoms = grep { $_->{'mysql'} } &list_domains();
print &ui_form_start("delete_newmysqls.cgi");
print &ui_columns_start([ "", $text{'newmysqls_host'}, $text{'newmysqls_doms'},
			  $text{'newmysqls_def'}, $text{'newmysqls_creator'},
			  $text{'newmysqls_actions'} ]);
foreach my $mm (&list_remote_mysql_modules()) {
	@doms = grep { ($_->{'mysql_module'} || 'mysql') eq
		       $mm->{'minfo'}->{'dir'} } @alldoms;
	$doms = !@doms ? $text{'newmysqls_none'} :
		@doms > 5 ? &text('newmysqls_dcount', scalar(@doms)) :
		  join(", ", map { &show_domain_name($_) } @doms);
	print &ui_checked_columns_row([
		$mm->{'config'}->{'host'} ||
		  $mm->{'config'}->{'sock'} ||
		  "<i>$text{'newmysqls_local'}</i>",
		$doms,
		$mm->{'config'}->{'virtualmin_default'} ?
			$text{'yes'} : $text{'no'},
		$mm->{'config'}->{'virtualmin_provision'} ?
			$text{'newmysqls_cm'} : $text{'newmysqls_man'},
		&ui_link("/$mm->{'minfo'}->{'dir'}", $text{'newmysqls_open'}),
		], \@tds, "d", $mm->{'minfo'}->{'dir'});
	}
print &ui_columns_end();
print &ui_form_end([ [ undef, $text{'newmysqls_delete'} ],
		     [ 'default', $text{'newmysqls_makedef'} ] ]);

# Show a form to add a new one
print &ui_hr();
print &ui_form_start("create_newmysql.cgi", "post");
print &ui_table_start($text{'newmysqls_header'}, undef, 2);

# Remote server, or local socket
print &ui_table_row($text{'newmysqls_host'},
	&ui_radio_table("mode", 0,
		[ [ 0, $text{'newmysqls_remote'},
		    &ui_textbox("host", undef, 40) ],
		  [ 1, $text{'newmysqls_sock'},
		    &ui_textbox("sock", undef, 40) ],
		  [ 2, $text{'newmysqls_nohost'} ] ]));

# TCP port number
print &ui_table_row($text{'newmysqls_port'},
	&ui_opt_textbox("port", undef, 6, $text{'newmysqls_portdef'}));

# Username and password
print &ui_table_row($text{'newmysqls_user'},
	&ui_textbox("myuser", undef, 40));
print &ui_table_row($text{'newmysqls_pass'},
	&ui_textbox("mypass", undef, 40));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'create'} ] ]);

&ui_print_footer("", $text{'index_return'});

