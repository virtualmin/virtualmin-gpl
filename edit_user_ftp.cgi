#!/usr/local/bin/perl
# edit_user_ftp.cgi
# Display a form for adding a FTP user.

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

&ui_print_header($din, $text{'user_createweb'}, "", "users_explain_user_ftp");
$user = &create_initial_user($d, undef, 1);

# FTP user in a sub-server .. check if FTP restrictions are active
if ($user->{'webowner'} && $d->{'parent'} && $config{'ftp'}) {
	my @chroots = &list_ftp_chroots();
	my ($home) = grep { $_->{'dir'} eq '~' } @chroots;
	if (!$home) {
		print "<b>$text{'user_chrootwarn'}</b><p>\n";
		}
	}

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user.cgi", "post");
print &ui_hidden("new", 1);
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("quota_def", 1);
print &ui_hidden("mquota_def", 1);
print &ui_hidden("recovery_def", 1);
print &ui_hidden("web", 1);
print &ui_hidden("shell", '/bin/false');

print &ui_table_start($d ? $text{'user_header_ftp'} : $text{'user_lheader'},
		             "width=100%", 2);

# Edit mail username
my $universal_type = $config{'nopostfix_extra_user'} != 2 ? "_universal" : "";
print &ui_table_row(&hlink($text{'user_user2'}, "username4$universal_type"),
	&ui_textbox("mailuser", undef, 13, 0, undef,
		&vui_ui_input_noauto_attrs()).
	($d ? "\@".&show_domain_name($d) : ""), 2, \@tds);

# Password cannot be edited for domain owners (because it is the domain pass)
$pwfield = "";
$pwfield = &new_password_input("mailpass");
if (!$user->{'alwaysplain'}) {
	# Option to disable
	$pwfield .= "<br>" if ($pwfield !~ /\/table>/);
	$pwfield .=
		&ui_checkbox("disable", 1, $text{'user_disabled'},
				$user->{'pass'} =~ /^\!/ ? 1 : 0);
	}
print &ui_table_row(&hlink($text{'user_pass'}, "password"),
			$pwfield,
			2, \@tds);

# Real name - only for true Unix users or LDAP persons
if ($user->{'person'}) {
	print &ui_table_row(&hlink($text{'user_real'}, "realname"),
			   &ui_textbox("real", $user->{'real'}, 40, 0, undef,
			     &vui_ui_input_noauto_attrs()),
		2, \@tds);
	}

# Show secondary groups
my @sgroups = &allowed_secondary_groups($d);
if (@sgroups && $user->{'unix'}) {
	print &ui_table_row(&hlink($text{'user_groups'},"usergroups"),
			    &ui_select("groups", $user->{'secs'},
				[ map { [ $_ ] } @sgroups ], 5, 1, 1),
			    2, \@tds);
	}

# Show home directory editing field
my $showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
	    !$user->{'fixedhome'};
if ($showhome) {
	if ($user->{'brokenhome'}) {
		# Home directory is in odd location, and so cannot be edited
		$homefield = "<tt>$user->{'home'}</tt>";
		print &ui_hidden("brokenhome", 1),"\n";
		}
	elsif ($user->{'webowner'}) {
		# Home can be public_html or a sub-dir
		local $phd = &public_html_dir($d);
		$homefield = &ui_radio("home_def", 1 ? 1 : 0,
				       [ [ 1, $text{'user_home2'} ],
					 [ 0, $text{'user_homeunder2'} ] ])." ".
			     &ui_textbox("home", 1 ? "" :
				substr($user->{'home'}, length($phd)+1), 20);
		}
	print &ui_table_row(&hlink($text{'user_home'}, 'userhomeftp'),
			    $homefield,
			    2, \@tds);
	}

print &ui_table_end();

# Form create/delete buttons
print &ui_form_end(
	[ [ "create", $text{'create'} ] ]);

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

