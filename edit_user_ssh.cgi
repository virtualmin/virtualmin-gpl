#!/usr/local/bin/perl
# edit_user_ssh.cgi
# Display a form for adding a SSH user.

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

&ui_print_header($din, $text{'user_createssh'}, "");
$user = &create_initial_user($d);

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user.cgi", "post");
print &ui_hidden("new", 1);
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("recovery_def", 1);

print &ui_hidden_table_start($d ? $text{'user_header_ssh'} : $text{'user_lheader'},
		             "width=100%", 2, "table1", 1);

# Edit mail username
my $universal_type = $config{'nopostfix_extra_user'} != 2 ? "_universal" : "";
print &ui_table_row(&hlink($text{'user_user2'}, "username2$universal_type"),
	&ui_textbox("mailuser", undef, 13, 0, undef,
		&vui_ui_input_noauto_attrs()).
	($d ? "\@".&show_domain_name($d) : ""),
	2, \@tds);

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

if (&can_mailbox_ftp() && $user->{'unix'}) {
	# Show SSH shell select if more than one available
	my @ssh_shells =
		grep { $_->{'id'} eq 'ssh' && $_->{'avail'} }
			&list_available_shells($d);
	my $ssh_shell = $ssh_shells[0]->{'shell'};
	if (scalar(@ssh_shells) == 1) {
		print &ui_hidden("shell", $ssh_shell);
		}
	else {
		print &ui_table_row(&hlink($text{'user_ushell'}, "ushell"),
			&available_shells_menu("shell", $ssh_shell || $user->{'shell'}, "mailbox",
					0, $user->{'webowner'}),
			2, \@tds);
		}
	}

# Show secondary groups
my @sgroups = &allowed_secondary_groups($d);
if (@sgroups && $user->{'unix'}) {
	print &ui_table_row(&hlink($text{'user_groups'},"usergroups"),
			    &ui_select("groups", $user->{'secs'},
				[ map { [ $_ ] } @sgroups ], 5, 1, 1),
			    2, \@tds);
	}

print &ui_hidden_table_end();

# Quota and home directory related fields
my $showquota = $user->{'unix'} && !$user->{'noquota'};
my $showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
	    !$user->{'fixedhome'};

if ($showquota || $showhome) {
	# Start quota and home table
	print &ui_hidden_table_start($text{'user_header2'}, "width=100%", 2,
				     "table2", 1);
	}

if ($showquota) {
	# Show quotas field(s)
	if (&has_home_quotas()) {
		print &ui_table_row(
			&hlink($qsame ? $text{'user_umquota'}
				      : $text{'user_uquota'}, "diskquota"),
			&quota_field("quota", $user->{'quota'},
			     $user->{'uquota'}, $user->{'ufquota'},
			     "home", $user),
			2, \@tds);
		}
	if (&has_mail_quotas()) {
		print &ui_table_row(&hlink($text{'user_mquota'}, "diskmquota"),
				    &quota_field("mquota", $user->{'mquota'},
					 $user->{'umquota'},$user->{'umfquota'},
					 "mail", $user),
				    2, \@tds);
		}
	}

if ($showhome) {
	# Show home directory editing field
	local $reshome = &resolve_links($user->{'home'});
	local $helppage = "userhome";
	if ($user->{'brokenhome'}) {
		# Home directory is in odd location, and so cannot be edited
		$homefield = "<tt>$user->{'home'}</tt>";
		print &ui_hidden("brokenhome", 1),"\n";
		}
	else {
		# Home is under server root, and so can be edited
		$homefield = &ui_radio("home_def", 1 ? 1 : 0,
				[ [ 1, $text{'user_home1'} ],
				  [ 0, &text('user_homeunder') ] ])." ".
			     &ui_textbox("home", 1 ? "" :
			substr($user->{'home'}, length($d->{'home'})+1), 20);
		}
	print &ui_table_row(&hlink($text{'user_home'}, $helppage),
			    $homefield,
			    2, \@tds);
	}

if ($showquota || $showhome) {
	print &ui_hidden_table_end("table2");
	}

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

