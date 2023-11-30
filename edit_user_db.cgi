#!/usr/local/bin/perl
# edit_user_db.cgi
# Display a form for adding a database user.

require './virtual-server-lib.pl';
&ReadParse();
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'users_ecannot'});
	}
else {
	&can_edit_local() || &error($text{'users_ecannot2'});
	}
&can_edit_users() || &error($text{'users_ecannot'});
$din = $d ? &domain_in($d) : undef;
$tmpl = $d ? &get_template($d->{'template'}) : &get_template(0);

&ui_print_header($din, $text{'user_createdb'}, "");
$user = &create_initial_user($d);

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user_db.cgi", "post");
print &ui_hidden("new", 1);
print &ui_hidden("dom", $in{'dom'});

# my @users = &list_domain_users($d, 1, 1, 1, 0);
# var_dump(\@users);

print &ui_table_start($d ? $text{'user_header_db'} : $text{'user_lheader'},
                      "width=100%", 2);

# Edit db user
print &ui_table_row(&hlink($text{'user_user2'}, "username"),
	&ui_textbox("dbuser", undef, 13, 0, undef,
		&vui_ui_input_noauto_attrs()).
	($d ? "\@".&show_domain_name($d) : ""),
	2, \@tds);

# Edit password
my $pwfield = &new_password_input("dbpass");
print &ui_table_row(&hlink($text{'user_pass'}, "password"),
			$pwfield,
			2, \@tds);

# List databases
my @dbs;
@dbs = grep { $_->{'users'} } &domain_databases($d) if ($d);

# Show allowed databases
if (@dbs) {
        my $hrr = "<hr data-row-separator>";
        print &ui_table_row(undef, $hrr, 2);
	print &ui_table_row(undef, $hrr, 2) if (!$user->{'mysql_user'} && $shell_row);
	@userdbs = map { [ $_->{'type'}."_".$_->{'name'},
			   $_->{'name'}." ($_->{'desc'})" ] } @{$user->{'dbs'}};
	@alldbs = map { [ $_->{'type'}."_".$_->{'name'},
			  $_->{'name'}." ($_->{'desc'})" ] } @dbs;
	print &ui_table_row(&hlink($text{'user_dbs'},"userdbs"),
	  &ui_multi_select("dbs", \@userdbs, \@alldbs, 5, 1, 0,
			   $text{'user_dbsall'}, $text{'user_dbssel'}),
	  2, \@tds);
	}

print &ui_table_end();

# Form create/delete buttons
if ($in{'new'}) {
	print &ui_form_end(
	   [ [ "create", $text{'create'} ] ]);
	}
else {
	print &ui_form_end(
	   [ [ "save", $text{'save'} ],
	     [ "delete", $text{'delete'} ]  ]);
	}

# Link back to user list and/or main menu
if ($d) {
	if ($single_domain_mode) {
		&ui_print_footer(
			"list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			"", $text{'index_return2'});
		}
	else {
		&ui_print_footer(
			"list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			&domain_footer_link($d),
			"", $text{'index_return'});
		}
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

