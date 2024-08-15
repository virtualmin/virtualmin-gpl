#!/usr/local/bin/perl
# Show a list of known remote MySQL servers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmysqls_ecannot'});
&ui_print_header(undef, $text{'newmysqls_title'}, "", "newmysqls");

# Show a table of current servers
@alldoms = &list_domains();
print &ui_form_start("delete_newmysqls.cgi");
print &ui_columns_start(
	[ "", $text{'newmysqls_host'}, $text{'newmysqls_ver'},
	  $text{'newmysqls_doms'}, $text{'newmysqls_def'},
	  $text{'newmysqls_creator'}, $text{'newmysqls_actions'} ]);
foreach my $mm (&list_remote_mysql_modules(),
		&list_remote_postgres_modules()) {
	if ($mm->{'dbtype'} eq 'mysql') {
		@doms = grep { $_->{'mysql'} && 
			       ($_->{'mysql_module'} || 'mysql') eq
			       $mm->{'minfo'}->{'dir'} } @alldoms;
		}
	else {
		@doms = grep { $_->{'postgres'} &&
			       ($_->{'postgres_module'} || 'postgresql') eq
			       $mm->{'minfo'}->{'dir'} } @alldoms;
		}
	$doms = !@doms ? $text{'newmysqls_none'} :
		@doms > 5 ? &text('newmysqls_dcount', scalar(@doms)) :
		  join(", ", map { &show_domain_name($_) } @doms);
	if ($mm->{'dbtype'} eq 'mysql') {
		($ver, $variant, $err) = &get_dom_remote_mysql_version(
						$mm->{'minfo'}->{'dir'});
		}
	else {
		($ver, $variant, $err) = &get_dom_remote_postgres_version(
						$mm->{'minfo'}->{'dir'});
		}
	$vstr = $err || &text('newmysqls_ver'.$variant, $ver);
	print &ui_checked_columns_row([
		$mm->{'desc'},
		$vstr,
		$doms,
		$mm->{'config'}->{'virtualmin_default'} ?
			$text{'yes'} : $text{'no'},
		$mm->{'config'}->{'virtualmin_provision'} ?
			$text{'newmysqls_cm'} : $text{'newmysqls_man'},
		&ui_link("/$mm->{'minfo'}->{'dir'}", $text{'newmysqls_open'}),
		], \@tds, "d", $mm->{'minfo'}->{'dir'}, 0, 
		   $mm->{'config'}->{'virtualmin_provision'} ? 1 : 0);
	}
print &ui_columns_end();
print &ui_form_end([ [ undef, $text{'newmysqls_delete'} ],
		     [ 'default', $text{'newmysqls_makedef'} ] ]);

# Show a form to add a new one
print &ui_hr();
print &ui_form_start("create_newmysql.cgi", "post");
print &ui_table_start($text{'newmysqls_header'}, undef, 2);

# Database type
my @types;
push(@types, [ 'mysql', $text{'databases_mysql'} ]) if ($config{'mysql'});
push(@types, [ 'postgres', $text{'databases_postgres'} ]) if ($config{'postgres'});
print &ui_table_row($text{'newmysqls_formtype'},
	&ui_select("type", $types[0]->[0], \@types));

# Remote server, or local socket
print &ui_table_row($text{'newmysqls_formhost'},
	&ui_radio_table("mode", 0,
		[ [ 0, $text{'newmysqls_remote'},
		    &ui_textbox("host", undef, 40) ],
		  [ 1, $text{'newmysqls_sock'},
		    &ui_textbox("sock", undef, 40) ],
		  [ 2, $text{'newmysqls_nohost'} ] ]));

# TCP port number
print &ui_table_row($text{'newmysqls_port'},
	&ui_opt_textbox("port", undef, 6, $text{'newmysqls_portdef'}));

# SSL mode
print &ui_table_row($text{'newmysqls_ssl'},
	&ui_yesno_radio("ssl", 1));

# Username and password
print &ui_table_row($text{'newmysqls_user'},
	&ui_textbox("myuser", undef, 40));
print &ui_table_row($text{'newmysqls_pass'},
	&ui_textbox("mypass", undef, 40));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'create'} ] ]);

&ui_print_footer("", $text{'index_return'});

