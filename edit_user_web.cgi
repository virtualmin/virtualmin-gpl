#!/usr/local/bin/perl
# edit_user_web.cgi
# Display a form for adding a webserver user.

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

&ui_print_header($din, $text{$in{'new'} ? 'user_createwebserver' : 'user_edit'}, "");

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user_web.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("olduser", $in{'user'});
print &ui_hidden("dom", $in{'dom'});

my $webuser = &create_initial_user($d);
my $webuser_name;
if (!$in{'new'}) {
        my @webusers = &list_domain_users($d, 1, 0, 1, 1);
        ($webuser) = grep { $_->{'user'} eq $in{'user'} } @webusers;
        $webuser || &error(&text('user_edoesntexist', &html_escape($in{'user'})));
        $webuser_name = &remove_userdom($webuser->{'user'}, $d) || $webuser->{'user'};
        }

# At first check if we have protected webdirectories in this domain
my $htpasswd_data;
foreach my $f (&list_mail_plugins()) {
	if ($f eq "virtualmin-htpasswd") {
                foreach my $f (&list_mail_plugins()) {
                        if ($f eq "virtualmin-htpasswd") {
                                $input = &trim(&plugin_call($f, "mailbox_inputs", $webuser, $in{'new'}, $d));
                                $htpasswd_data = $input if ($input);
                                last;
                                }
		        }
		}
        }

# Print protected directories selector if found
if ($htpasswd_data) {
        print &ui_table_start($text{'user_header_webserver'}, "width=100%", 2);

        # Edit web user
        print &ui_table_row(&hlink($text{'user_user2'}, "username_web"),
                &ui_textbox("webuser", $webuser_name, 15, 0, undef,
                        &vui_ui_input_noauto_attrs()).
                ($d ? "\@".&show_domain_name($d) : ""),
                2, \@tds);

        # Edit password
        my $pwfield = &new_password_input("webpass", 0);
        if (!$in{'new'}) {
                # For existing user show password field
                $pwfield = &ui_opt_textbox("webpass", undef, 15,
                                $text{'user_passdef'},
                                $text{'user_passset'}, 0);
                }
        print &ui_table_row(&hlink($text{'user_pass'}, "password"),
                                $pwfield,
                                2, \@tds);
        print &ui_table_row(undef, "<hr data-row-separator>", 2);
        print $htpasswd_data;
        my $msg = &text('users_addprotecteddir2',
                &get_webprefix()."/virtualmin-htpasswd/index.cgi?dom=$d->{'id'}");
        print &ui_table_row(undef, $msg, 2);
        print &ui_table_end();
        }
else {
        print &text('users_addprotecteddir',
                &get_webprefix()."/virtualmin-htpasswd/index.cgi?dom=$d->{'id'}");
        }

# Form create/delete buttons
if ($htpasswd_data) {
        if ($in{'new'}) {
                print &ui_form_end(
                [ [ "create", $text{'create'} ] ]);
                }
        else {
                print &ui_form_end(
                [ [ "save", $text{'save'} ],
                [ "delete", $text{'delete'} ]  ]);
                }
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

