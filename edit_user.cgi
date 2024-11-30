#!/usr/local/bin/perl
# edit_user.cgi
# Display a form for editing or adding a user. This can be a local user,
# or a domain mailbox user

require './virtual-server-lib.pl';
&ReadParse();

# Check access
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'users_ecannot'});
	}
else {
	&can_edit_local() || &error($text{'users_ecannot2'});
	}
&can_edit_users() || &error($text{'users_ecannot'});

# Get domain and templates details
$din = $d ? &domain_in($d) : undef;
$tmpl = $d ? &get_template($d->{'template'}) : &get_template(0);

# Set user type
$user_type = $in{'type'};

# Set defaults
$form_end = 1;
@tds = ( "width=30%", "width=70%" );

# Create SSH user only form
if ($user_type eq 'ssh') {
	&can_mailbox_ssh() || &error($text{'users_ecannotssh'});
	&ui_print_header($din, $text{'user_createssh'}, "",
			 "users_explain_user_ssh");
	$user = &create_initial_user($d);

	print &ui_form_start("save_user.cgi", "post");
	print &ui_hidden("new", 1);
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("recovery_def", 1);
	print &ui_hidden('newmail_def', 1);

	print &ui_hidden_table_start(
		$d ? $text{'user_header_ssh'} : $text{'user_lheader'},
		"width=100%", 2, "table1", 1);

	# Edit mail username
	print &ui_table_row(
		&hlink($text{'user_user2'}, "username2_universal"),
		&vui_noauto_textbox("mailuser", undef, 13).
		($d ? "\@".&show_domain_name($d) : ""),
		2, \@tds);

	# Password cannot be edited for domain owners (because it is the
	# domain pass)
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

	# SSH public key for Unix user
	if (&proshow()) {
		print &ui_table_row(
			&hlink($text{'form_sshkey'}, "sshkeynogen"),
			&inline_html_pro_tip(
				&ui_radio("sshkey_mode", 0,
					[ [ 0, $text{'form_sshkey0'} ],
					  [ 2, $text{'form_sshkey2'} ] ]),
				'manage-user-ssh-public-key').
			"<br>\n".&ui_textarea("sshkey", undef, 3, 60,
					      undef, !$virtualmin_pro),
					undef, &procell() || \@tds);
		}

	# Real name components
	&show_real_name_fields($user, 1);

	# Show SSH shell select if more than one available
	my @ssh_shells = &list_available_shells_by_type('owner', 'ssh');
	if (scalar(@ssh_shells) == 1) {
		print &ui_hidden("shell", $ssh_shells[0]->{'shell'});
		}
	else {
		print &ui_table_row(
			&hlink($text{'user_ushell'}, "ushell"),
			&available_shells_menu(
				"shell", &get_user_shell($user), "owner"),
			2, \@tds);
		}

	# Show secondary groups
	my @sgroups = &allowed_secondary_groups($d);
	if (@sgroups) {
		print &ui_table_row(&hlink($text{'user_groups'},"usergroups"),
				&ui_select("groups", $user->{'secs'},
					[ map { [ $_ ] } @sgroups ], 5, 1, 1),
				2, \@tds);
		}

	print &ui_hidden_table_end();

	# Quota and home directory related fields
	my $showquota = !$user->{'noquota'};
	my $showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
		!$user->{'fixedhome'};

	if ($showquota || $showhome) {
		# Start quota and home table
		print &ui_hidden_table_start(
			$text{'user_header2'}, "width=100%", 2, "table2", 1);
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
			print &ui_table_row(
				&hlink($text{'user_mquota'}, "diskmquota"),
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
			# Home directory is in odd location, and so cannot
			# be edited
			$homefield = "<tt>$user->{'home'}</tt>";
			print &ui_hidden("brokenhome", 1),"\n";
			}
		else {
			# Home is under server root, and so can be edited
			$homefield = &ui_radio("home_def", 1 ? 1 : 0,
					[ [ 1, $text{'user_home1'} ],
					[ 0, &text('user_homeunder') ] ])." ".
				&ui_textbox("home", "", 20);
			}
		print &ui_table_row(&hlink($text{'user_home'}, $helppage),
				$homefield,
				2, \@tds);
		}

	if ($showquota || $showhome) {
		print &ui_hidden_table_end("table2");
		}

	}
# Create FTP user only form
elsif ($user_type eq 'ftp') {
	&ui_print_header($din, $text{'user_createweb'}, "",
			 "users_explain_user_ftp");
	$user = &create_initial_user($d, undef, 1);

	# FTP user in a sub-server .. check if FTP restrictions are active
	if ($user->{'webowner'} && $d->{'parent'} && $config{'ftp'}) {
		my @chroots = &list_ftp_chroots();
		my ($home) = grep { $_->{'dir'} eq '~' } @chroots;
		if (!$home) {
			print "<b>$text{'user_chrootwarn'}</b><p>\n";
			}
		}
	print &ui_form_start("save_user.cgi", "post");
	print &ui_hidden("new", 1);
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("quota_def", 1);
	print &ui_hidden("mquota_def", 1);
	print &ui_hidden("recovery_def", 1);
	print &ui_hidden('newmail_def', 1);
	print &ui_hidden("web", 1);
	print &ui_hidden("shell", '/bin/false');

	print &ui_table_start(
		$d ? $text{'user_header_ftp'} : $text{'user_lheader'},
		"width=100%", 2);

	# Edit mail username
	print &ui_table_row(
		&hlink($text{'user_user2'}, "username4_universal"),
		&vui_noauto_textbox("mailuser", undef, 13).
		($d ? "\@".&show_domain_name($d) : ""), 2, \@tds);

	# Password cannot be edited for domain owners (because it is the
	# domain pass)
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

	# Real name components
	&show_real_name_fields($user, 1);

	# Show secondary groups
	my @sgroups = &allowed_secondary_groups($d);
	if (@sgroups) {
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
			# Home directory is in odd location, and so cannot
			# be edited
			$homefield = "<tt>$user->{'home'}</tt>";
			print &ui_hidden("brokenhome", 1),"\n";
			}
		elsif ($user->{'webowner'}) {
			# Home can be public_html or a sub-dir
			local $phd = &public_html_dir($d);
			$homefield = &ui_radio("home_def", 1 ? 1 : 0,
					[ [ 1, $text{'user_home2'} ],
					  [ 0, $text{'user_homeunder2'} ] ]).
				     " ".&ui_textbox("home", 1 ? "" :
					substr($user->{'home'}, length($phd)+1), 20);
			}
		print &ui_table_row(&hlink($text{'user_home'}, 'userhomeftp'),
				$homefield,
				2, \@tds);
		}

	print &ui_table_end();
	}
# Create Mail user only form
elsif ($user_type eq 'mail') {
	$d->{'mail'} || &error($text{'users_ecannot3'});

	&ui_print_header($din, $text{'user_createmail'}, "",
			 "users_explain_user_mail");
	$user = &create_initial_user($d);

	print &ui_form_start("save_user.cgi", "post");
	print &ui_hidden("new", 1);
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("home_def", 1);
	print &ui_hidden("shell", '/dev/null');

	# Print quota hidden defaults as
	# it has to be always considered
	my $showquota = !$user->{'noquota'};
	my $showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
		       !$user->{'fixedhome'};
	if ($showquota) {
		if (&has_home_quotas()) {
			my $quota_data = &quota_field(
				"quota", $user->{'quota'}, $user->{'uquota'},
				$user->{'ufquota'}, "home", $user);
			print &vui_hidden($quota_data);
			}
		if (&has_mail_quotas()) {
			my $mquota_data = &quota_field(
				"mquota", $user->{'mquota'}, $user->{'umquota'},
				$user->{'umfquota'}, "mail", $user);
			print &vui_hidden($mquota_data);
			}
		}

	# Show accordions
	print &ui_hidden_table_start(
		$d ? $text{'user_header_mail'} : $text{'user_lheader'},
		"width=100%", 2, "table1", 1);

	# Edit mail username
	print &ui_table_row(
		&hlink($text{'user_user'}, "username_universal"),
		&vui_noauto_textbox("mailuser", undef, 13).
			($d ? "\@".&show_domain_name($d) : ""),
		2, \@tds);

	# Password field
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

	# Password recovery field
	print &ui_table_row(&hlink($text{'user_recovery'}, "recovery"),
		&ui_opt_textbox("recovery", $user->{'recovery'}, 40,
				$text{'user_norecovery'},
				$text{'user_gotrecovery'}));

	# Real name components
	&show_real_name_fields($user, 1);

	print &ui_hidden_table_end();

	# Start third table, for email settings
	$hasprimary = $d && !$user->{'noprimary'} && $d->{'mail'};
	$hasextra = !$user->{'noextra'};
	$hassend = &will_send_user_email($d, 1);
	$hasspam = $config{'spam'} && $hasprimary;
	$hasemail = $hasprimary || $hasextra ||
		    $hassend || $hasspam;

	# Email settings
	if ($hasemail) {
		print &ui_hidden_table_start(
			$text{'user_header3'}, "width=100%", 2, "table2a", 0);
		}

	if ($hasprimary) {
		# Show primary email address field
		print &ui_table_row(&hlink($text{'user_mailbox'}, "mailbox"),
			&ui_yesno_radio("mailbox", 1),
			2, \@tds);
		}

	if ($hasextra) {
		# Show extra email addresses
		@extra = @{$user->{'extraemail'}};
		foreach $e (@extra) {
			if ($e =~ /^(\S*)\@(\S+)$/) {
				local ($eu, $ed) = ($1, $2);
				$ed = &show_domain_name($ed);
				$e = $eu."\@".$ed;
				}
			}
		print &ui_table_row(&hlink($text{'user_extra'}, "extraemail"),
				&ui_textarea("extra", join("\n", @extra), 5, 50),
				2, \@tds);
		}

	if (&will_send_user_email($d, 1)) {
		# Show address for confirmation email (for the mailbox itself)
		print &ui_table_row(&hlink($text{'user_newmail'},"newmail"),
			&ui_opt_textbox("newmail", undef, 40,
				$user->{'email'} ? $text{'user_newmail1'}
						: $text{'user_newmail2'},
				$text{'user_newmail0'}),
			2, \@tds);
		}

	# Show spam check flag
	if ($hasspam) {
		print &ui_table_row(
			&hlink($d->{'virus'} ? $text{'user_nospam'}
					: $text{'user_nospam2'}, "nospam"),
			!$d->{'spam'} ? $text{'user_spamdis'} :
				&ui_radio("nospam", int($user->{'nospam'}),
					[ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]),
			2, \@tds);
		}

	if ($hasemail) {
		# Show forwarding setup for this user, using simple form
		# if possible
		if (($user->{'email'} || $user->{'noprimary'}) &&
		    !$user->{'noalias'}) {
			print &ui_table_hr();

			# Work out if simple mode is supported
			if (!@{$user->{'to'}}) {
				# If no forwarding, just check delivery to me
				# as this is the default.
				$simple = { 'tome' => 1 };
				}
			else {
				$simple = &get_simple_alias($d, $user, 1);
				}
			if ($simple && ($simple->{'local'} || $simple->{'bounce'})) {
				# Local and bounce delivery are not allowed on
				# the simple form, unless we can merge some
				# (@) local users with forward users, which
				# will be handled automatically on save to
				# prevent showing advanced form for no reason
				$simple = undef if (!$simple->{'local-all'} ||
						    $simple->{'bounce'});
				}

			if ($simple) {
				# Show simple form
				print &ui_hidden("simplemode", "simple");
				&show_simple_form(
					$simple, 1, 1, 1, 1, \@tds, "user");
				}
			else {
				# Show complex form
				print &ui_hidden("simplemode", "complex");
				&alias_form($user->{'to'},
				    &hlink($text{'user_aliases'}, "userdest"),
				    $d, "user", $in{'user'}, \@tds);
				}

			}
		# Show user-level mail filters, if he has any
		@filters = ( );
		if (@filters) {
			my $mail_filter_title = $text{'user_header3a'};
			my $mail_filter_body;
			$lastalways = 0;
			@folders = &mailboxes::list_user_folders(
					$user->{'user'});
			@table = ( );
			foreach $filter (@filters) {
				($cdesc, $lastalways) =
					&filter::describe_condition($filter);
				$adesc = &filter::describe_action(
					$filter, \@folders, $user->{'home'});
				push(@table, [ $cdesc, $adesc ]);
				}
			if (!$lastalways) {
				push(@table, [ $filter::text{'index_calways'},
					$filter::text{'index_adefault'} ]);
				}
			$mail_filter_body = &ui_columns_table(
				[ $text{'user_fcondition'},
				  $text{'user_faction'} ],
				100,
				\@table);
			my $mail_filter_details = &ui_details({
				'title' => $mail_filter_title,
				'content' => $mail_filter_body,
				'class' =>'default',
				'html' => 1});
			print &ui_table_row(
				undef, $mail_filter_details, 2,
				undef, ["data-row-wrapper='details'"]);
			}

		print &ui_hidden_table_end("table2a");
		}
	}
# Create database user only form
elsif ($user_type eq 'db') {
	&ui_print_header(
		$din, $text{$in{'new'} ? 'user_createdb' : 'user_edit'}, "",
		$in{'new'} ? 'users_explain_user_db' : undef);

	&list_extra_user_pro_tip('db', "list_users.cgi?dom=$in{'dom'}");
	print &ui_form_start("pro/save_user_db.cgi", "post");
	print &ui_hidden("new", $in{'new'});
	print &ui_hidden("olduser", $in{'user'});
	print &ui_hidden("dom", $in{'dom'});

	my $dbuser;
	my $dbuser_name;
	if (!$in{'new'}) {
		$dbuser = &get_extra_db_user($d, $in{'user'});
		$dbuser || &error(&text('user_edoesntexist',
					&html_escape($in{'user'})));
		$dbuser_name = &remove_userdom(
			$dbuser->{'user'}, $d) || $dbuser->{'user'};
		}

	print &ui_table_start($text{'user_header_db'}, "width=100%", 2);

	# Show current full username
	if (!$in{'new'}) {
		print &ui_table_row(
			&hlink($text{'user_user3'}, "username3"),
			"<tt>$dbuser->{'user'}</tt>", 2, \@tds);
		}

	# Edit db user
	print &ui_table_row(&hlink($text{'user_user2'}, "username_db"),
		&inline_html_pro_tip(
			&vui_noauto_textbox("dbuser", $dbuser_name, 15).
				  ($d ? "\@".&show_domain_name($d) : ""),
			'manage-extra-database-users', 1),
		2, &procell(undef, @tds) || \@tds);

	# Edit password
	my $pwfield = &new_password_input("dbpass");
	if (!$in{'new'}) {
		# For existing user show password field
		$pwfield = &ui_opt_textbox("dbpass", undef, 15,
				$text{'user_passdef'},
				$text{'user_passset'});
		}
	print &ui_table_row(&hlink($text{'user_pass'}, "password"),
				&inline_html_pro_tip($pwfield,
					'manage-extra-database-users', 1),
					2, &procell(undef, @tds) || \@tds);

	# Show allowed databases
	my @dbs = grep { $_->{'users'} } &domain_databases($d) if ($d);
	if (@dbs) {
		my $user;
		$user = &create_initial_user($d) if ($in{'new'});
		print &ui_table_hr();
		my @idbs = $in{'new'} ? @{$user->{'dbs'}} : @{$dbuser->{'dbs'}};
		@userdbs = map { [ $_->{'type'}."_".$_->{'name'},
				$_->{'name'}." ($_->{'desc'})" ] } @idbs;
		@alldbs = map { [ $_->{'type'}."_".$_->{'name'},
				$_->{'name'}." ($_->{'desc'})" ] } @dbs;
		print &ui_table_row(&hlink($text{'user_dbs'},"userdbs"),
			&ui_multi_select("dbs", \@userdbs, \@alldbs, 5, 1, 0,
				$text{'user_dbsall'}, $text{'user_dbssel'}),
					2, &procell(2));
		}

	print &ui_table_end();
	}
# Create web user only form
elsif ($user_type eq 'web') {
	&ui_print_header(
	    $din, $text{$in{'new'} ? 'user_createwebserver' : 'user_edit'}, "",
	    $in{'new'} ? 'users_explain_user_web' : undef);

	&list_extra_user_pro_tip('web', "list_users.cgi?dom=$in{'dom'}");
	print &ui_form_start("pro/save_user_web.cgi", "post");
	print &ui_hidden("new", $in{'new'});
	print &ui_hidden("olduser", $in{'user'});
	print &ui_hidden("dom", $in{'dom'});

	my $webuser = &create_initial_user($d);
	my $webuser_name;
	if (!$in{'new'}) {
		$webuser = &get_extra_web_user($d, $in{'user'});
		$webuser || &error(&text('user_edoesntexist',
					 &html_escape($in{'user'})));
		$webuser_name = &remove_userdom($webuser->{'user'}, $d) ||
				$webuser->{'user'};
		}

	# At first check if we have protected webdirectories in this domain
	my $htpasswd_data;
	foreach my $f (&list_mail_plugins()) {
		if ($f eq "virtualmin-htpasswd") {
			$input = &trim(&plugin_call($f, "mailbox_inputs",
						    $webuser, $in{'new'}, $d));
			$htpasswd_data = $input if ($input);
			last;
			}
		}

	# Print protected directories selector if found
	if ($htpasswd_data) {
		print &ui_table_start(
			$text{'user_header_webserver'}, "width=100%", 2);
	
		# Show current full username
		if (!$in{'new'}) {
			print &ui_table_row(
				&hlink($text{'user_user3'}, "username3"),
				"<tt>$webuser->{'user'}</tt>", 2, \@tds);
			}

		# Edit web user
		print &ui_table_row(&hlink($text{'user_user2'}, "username_web"),
			&inline_html_pro_tip(
				&vui_noauto_textbox("webuser", $webuser_name, 15).
					($d ? "\@".&show_domain_name($d) : ""),
				'manage-extra-webserver-users', 1),
			2, &procell(undef, @tds) || \@tds);

		# Edit password
		my $pwfield = &new_password_input("webpass", 0);
		if (!$in{'new'}) {
			# For existing user show password field
			$pwfield = &ui_opt_textbox("webpass", undef, 15,
					$text{'user_passdef'},
					$text{'user_passset'}, 0);
			}
		print &ui_table_row(
			&hlink($text{'user_pass'}, "password"),
			&inline_html_pro_tip(
				$pwfield, 'manage-extra-webserver-users', 1),
			2, &procell(undef, @tds) || \@tds);
		print &ui_table_hr();
		print $htpasswd_data;
		my $msg = &text('users_addprotecteddir2',
			&get_webprefix().
			"/virtualmin-htpasswd/index.cgi?dom=$d->{'id'}");
		print &ui_table_row("", $msg, 1);
		print &ui_table_end();
		}
	else {
		print &ui_alert_box(
		  &text('users_addprotecteddir',
			&get_webprefix().
			"/virtualmin-htpasswd/index.cgi?dom=$d->{'id'}"),
		  'info');
		}
	$form_end = $htpasswd_data ? 1 : 0;
	}
else {
	# Regular create or edit user form
	if ($in{'new'}) {
		&ui_print_header(
			$din, $text{'user_create'}, "", "users_explain_user");
		$user = &create_initial_user($d);
		}
	else {
		@users = &list_domain_users($d);
		($user) = grep {
			($_->{'user'} eq $in{'user'} ||
			 &remove_userdom($_->{'user'}, $d) eq $in{'user'})
			} @users;
		$mailbox = $d && $d->{'user'} eq $user->{'user'};
		$suffix = $user->{'webowner'} ? 'web' : '';
		&ui_print_header($din, $text{'user_edit'.$suffix}, "");
		}

	$shell_switch = ((&can_mailbox_ftp() && !$mailbox) || &master_admin())&&
			!$user->{'webowner'};
	@sgroups = &allowed_secondary_groups($d);

	# Work out if the other permissions section has anything to display
	if ($d && !$mailbox) {
		@dbs = grep { $_->{'users'} } &domain_databases($d);
		}

	# FTP user in a sub-server .. check if FTP restrictions are active
	if ($user->{'webowner'} && $d->{'parent'} && $config{'ftp'}) {
		my @chroots = &list_ftp_chroots();
		my ($home) = grep { $_->{'dir'} eq '~' } @chroots;
		if (!$home) {
			print "<b>$text{'user_chrootwarn'}</b><p>\n";
			}
		}

	print &ui_form_start("save_user.cgi", "post");
	print &ui_hidden("new", $in{'new'});
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("old", $in{'user'});
	print &ui_hidden("web", $in{'web'});

	print &ui_hidden_table_start(
		$mailbox ? $text{'user_mheader'} :
		$user->{'webowner'} ? $text{'user_header_ftp'} :
		$d ? $text{'user_header'} : $text{'user_lheader'},
		"width=100%", 2, "table1", 1);

	# Show username, editable if this is not the domain owner
	$ulabel = ($d->{'mail'} && !$user->{'webowner'}) ?
		&hlink($text{'user_user'}, "username_universal") :
		&hlink($text{'user_user2'}, "username2_universal");
	if ($in{'new'}) {
		$ulabel = &hlink($text{'user_user3'},
			($user->{'webowner'} ? 'username4' : 'username3').
			"_universal");
		}
	if ($user->{'webowner'}) {
		$ulabel = &hlink($text{'user_user2'}, "username4_universal");
		}

	if ($mailbox) {
		# Domain owner
		my $ouser_email = $user->{'user'};
		if ($d->{'mail'} && $ouser_email !~ /\@/) {
			$ouser_email = $user->{'user'} . "\@" . $d->{'dom'};
			}
		print &ui_table_row(
			&hlink($text{'user_user2'}, "username2_universal"),
			"<tt>$user->{'user'}</tt>", 2, \@tds);
		print &ui_table_row($ulabel, "<tt>$ouser_email</tt>", 2, \@tds)
			if ($d->{'mail'});
		$pop3 = $user->{'user'};
		}
	else {
		# Regular user
		$pop3 = $d && !$user->{'noappend'} ?
			&remove_userdom($user->{'user'}, $d) : $user->{'user'};
	
		# Full username differs
		if ($pop3 ne $user->{'user'}) {
			print &ui_table_row(
				&hlink($text{"user_user3"},
					$user->{'webowner'} ? 'username4' : 'username3'),
				"<tt>$user->{'user'}</tt>");
			}

		# Edit mail username
		print &ui_table_row($ulabel,
			&ui_textbox("mailuser", $pop3, 13, 0, undef,
			&vui_ui_input_noauto_attrs()).
			($d ? "\@".&show_domain_name($d) : ""),
			2, \@tds);
		print &ui_hidden("oldpop3", $pop3),"\n";
		}

	# Password cannot be edited for domain owners (because it is the
	# domain pass)
	if (!$mailbox) {
		$pwfield = "";
		if ($in{'new'}) {
			$pwfield = &new_password_input("mailpass");
			}
		else {
			# For an existing user, offer to change password
			$pwfield = &ui_opt_textbox("mailpass", undef, 13,
				$text{'user_passdef'}."\n".
				(defined($user->{'plainpass'}) ?
				&show_password_popup($d, $user) : ""),
				$text{'user_passset'});
			if ($user->{'change'}) {
				local $tm = timelocal(gmtime($user->{'change'} *
							     60*60*24));
				$pwfield .= "&nbsp;&nbsp;".
				    &text('user_lastch', &make_date($tm, 1));
				}
			}
		if (!$user->{'alwaysplain'}) {
			# Option to disable
			$pwfield .= "<br>" if ($pwfield !~ /\/table>/);
			$pwfield .= &ui_checkbox(
				"disable", 1, $text{'user_disabled'},
				$user->{'pass'} =~ /^\!/ ? 1 : 0);
			}
		print &ui_table_row(&hlink($text{'user_pass'}, "password"),
				$pwfield,
				2, \@tds);

		# SSH public key for Unix user
		if (&proshow()) {
			my $existing_key = &get_domain_user_ssh_pubkey($d, $user);
			my $existing_key_hidden;
			if ($existing_key && !$virtualmin_pro) {
				$existing_key_hidden =
					&ui_hidden("sshkey", $existing_key).
					&ui_hidden("sshkey_mode", 2);
				}
			print &ui_table_row(&hlink($text{'form_sshkey'}, "sshkeynogen"),
				&inline_html_pro_tip(
					&ui_radio("sshkey_mode", $existing_key ? 2 : 0,
						[ [ 0, $text{'form_sshkey0'} ],
						  [ 2, $text{'form_sshkey2'} ] ]),
							'manage-user-ssh-public-key').
				"<br>\n". &ui_textarea("sshkey", $existing_key, 3, 60,
					undef, !$virtualmin_pro, &vui_ui_input_noauto_attrs()).
				$existing_key_hidden,
				undef, &procell() || \@tds);
			}
		# Password recovery field
		if (!$user->{'webowner'}) {
			print &ui_table_row(
				&hlink($text{'user_recovery'}, "recovery"),
				&ui_opt_textbox(
					"recovery", $user->{'recovery'}, 40,
					$text{'user_norecovery'},
					$text{'user_gotrecovery'}));
			}
		}

	# Real name - only for show for mailbox users
	if (!$mailbox || $user->{'real'}) {
		&show_real_name_fields($user, $in{'new'});
		}

	# Show FTP shell field
	if ($shell_switch) {
		my $user_shell;
		if ($in{'new'}) {
			# For the new user fall-back to the no login shell
			my @ftp_shell =
				grep { $_->{'id'} eq 'ftp' && $_->{'avail'} }
					&list_available_shells($d);
			if (@ftp_shell) {
				$user_shell = $ftp_shell[0]->{'shell'};
				}
			}
		else {
			$user_shell = &get_user_shell($user);
			}
		print &ui_table_row(&hlink($text{'user_ushell'}, "ushell"),
			&available_shells_menu("shell", $user_shell,
			  &can_mailbox_ssh() ? ["mailbox", "owner"] : "mailbox",
			  $user->{'webowner'} ? 'ftp' : undef),
			2, \@tds);
		}

	# Show most recent logins
	if (!$in{'new'}) {
		$ll = &get_last_login_time($user->{'user'});
		@grid = ( );
		foreach $k (sort { $a cmp $b } keys %$ll) {
			push(@grid, $text{'user_lastlogin_'.$k},
				&make_date($ll->{$k}));
			}
		print &ui_table_row(
			&hlink($text{'user_lastlogin'}, "lastlogin"),
			@grid ? &ui_grid_table(\@grid, 2, 50)
			: $text{'user_lastlogin_never'});
		}

	# Show secondary groups
	if (@sgroups) {
		print &ui_table_row(&hlink($text{'user_groups'},"usergroups"),
				&ui_select("groups", $user->{'secs'},
					[ map { [ $_ ] } @sgroups ], 5, 1, 1),
				2, \@tds);
		}

	print &ui_hidden_table_end();

	$showquota = !$mailbox && !$user->{'noquota'};
	$showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
		!$mailbox && !$user->{'fixedhome'};

	if ($showquota || $showhome) {
		# Start quota and home table
		my $header2_title = 'user_header2';
		$header2_title = 'user_header2a' if (!$showhome);
		$header2_title = 'user_header2b' if (!$showquota);
		print &ui_hidden_table_start(
			$text{$header2_title}, "width=100%", 2, "table2", 0);
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
			print &ui_table_row(
				&hlink($text{'user_mquota'}, "diskmquota"),
				&quota_field("mquota", $user->{'mquota'},
					     $user->{'umquota'},
					     $user->{'umfquota'}, "mail",$user),
				2, \@tds);
			}
		}

	if ($showhome) {
		# Show home directory editing field
		local $reshome = &resolve_links($user->{'home'});
		local $helppage = "userhome";
		if ($user->{'brokenhome'}) {
			# Home directory is in odd location, and so cannot
			# be edited
			$homefield = "<tt>$user->{'home'}</tt>";
			print &ui_hidden("brokenhome", 1),"\n";
			}
		elsif ($user->{'webowner'}) {
			# Home can be public_html or a sub-dir
			local $phd = &public_html_dir($d);
			local $auto = $in{'new'} ||
				      $reshome eq &resolve_links($phd);
			$homefield = &ui_radio("home_def", $auto ? 1 : 0,
					[ [ 1, $text{'user_home2'} ],
					  [ 0, $text{'user_homeunder2'} ] ]).
				     " ".
				     &ui_textbox("home", $auto ? "" :
					substr($user->{'home'}, length($phd)+1), 20);
			$helppage = "userhomeftp";
			}
		else {
			# Home is under server root, and so can be edited
			local $auto = $in{'new'} ||
			$reshome eq
			&resolve_links("$d->{'home'}/$config{'homes_dir'}/$pop3");
			$homefield = &ui_radio("home_def", $auto ? 1 : 0,
					[ [ 1, $text{'user_home1'} ],
					[ 0, &text('user_homeunder') ] ])." ".
				&ui_textbox("home", $auto ? "" :
				substr($user->{'home'}, length($d->{'home'})+1), 20);
			}
		print &ui_table_row(&hlink($text{'user_home'}, $helppage),
				$homefield,
				2, \@tds);
		}

	if ($showquota || $showhome) {
		print &ui_hidden_table_end("table2");
		}

	# Start third table, for email settings
	$hasprimary = $d && !$user->{'noprimary'} && $d->{'mail'};
	$hasmailfile = !$in{'new'} && ($user->{'email'} ||
		       @{$user->{'extraemail'}}) && !$user->{'nomailfile'};
	$hasextra = !$user->{'noextra'};
	$hassend = &will_send_user_email($d, $in{'new'});
	$hasspam = $config{'spam'} && $hasprimary;
	$hasemail = $hasprimary || $hasmailfile || $hasextra ||
		    $hassend || $hasspam;
	$hasemailaccordion = !$user->{'webowner'} && $d->{'mail'};

	# Email settings
	if ($hasemailaccordion) {
		if ($hasemail && $d->{'mail'}) {
			print &ui_hidden_table_start(
				$text{'user_header3'}, "width=100%", 2, "table2a", 0);
			}

		if ($hasprimary) {
			# Show primary email address field
			print &ui_table_row(
				&hlink($text{'user_mailbox'}, "mailbox"),
				&ui_yesno_radio("mailbox",
					$user->{'email'} || $in{'new'} ? 1 : 0),
				2, \@tds);
			}

		if ($hasmailfile && $config{'show_mailuser'}) {
			# Show the user's mail file
			local ($sz, $umf, $lastmod) = &mail_file_size($user);
			local $link = &read_mail_link($user, $d);
			if ($link) {
				$mffield = "<a href='$link'><tt>$umf</tt></a>\n";
				}
			else {
				$mffield = "<tt>$umf</tt>\n";
				}
			if ($lastmod) {
				$mffield .= "(".&text('user_lastmod',
						&make_date($lastmod)).")";
				}
			if ($user->{'spam_quota'}) {
				$mffield .= "<br><font color=#ff0000>".
				&text($user->{'spam_quota_diff'} ? 'user_spamquota'
								: 'user_soamquota2',
					&nice_size($user->{'spam_quota_diff'})).
				"</font>\n";
				}
			print &ui_table_row(&hlink($text{'user_mail'}, "mailfile"),
					$mffield, 2, \@tds);
			}

		if ($hasextra) {
			# Show extra email addresses
			@extra = @{$user->{'extraemail'}};
			foreach $e (@extra) {
				if ($e =~ /^(\S*)\@(\S+)$/) {
					local ($eu, $ed) = ($1, $2);
					$ed = &show_domain_name($ed);
					$e = $eu."\@".$ed;
					}
				}
			print &ui_table_row(
				&hlink($text{'user_extra'}, "extraemail"),
				&ui_textarea("extra", join("\n", @extra), 5, 50),
				2, \@tds);
			}

		if ($in{'new'} && &will_send_user_email($d, 1)) {
			# Show address for confirmation email (for the mailbox
			# itself)
			print &ui_table_row(
				&hlink($text{'user_newmail'},"newmail"),
				&ui_opt_textbox("newmail", undef, 40,
				    $user->{'email'} ? $text{'user_newmail1'}
						     : $text{'user_newmail2'},
				    $text{'user_newmail0'}),
				2, \@tds);
			}
		elsif (!$in{'new'} && &will_send_user_email($d, 0)) {
			# Show option to re-send info email
			print &ui_table_row(
				&hlink($text{'user_remail'},"remail"),
				&ui_radio("remail_def", 1,
					[ [ 1, $text{'user_remail1'} ],
					[ 0, $text{'user_remail0'} ] ])." ".
				&ui_textbox("remail", $user->{'email'}, 40),
				2, \@tds);
			}

		# Show spam check flag
		if ($hasspam) {
			$awl_link = undef;
			if (!$in{'new'} && &foreign_available("spam")) {
				# Create AWL link
				&foreign_require("spam");
				if (defined(&spam::can_edit_awl) &&
				&spam::supports_auto_whitelist() == 2 &&
				&spam::get_auto_whitelist_file($user->{'user'}) &&
				&spam::can_edit_awl($user->{'user'})) {
					$awl_link = "&nbsp;( <a href='../spam/edit_awl.cgi?".
						"user=".&urlize($user->{'user'}).
						"'>$text{'user_awl'}</a> )";
					}
				}
			print &ui_table_row(
				&hlink($d->{'virus'} ? $text{'user_nospam'} :
					$text{'user_nospam2'}, "nospam"),
				!$d->{'spam'} ? $text{'user_spamdis'} :
					&ui_radio("nospam",
						int($user->{'nospam'}),
						[ [ 0, $text{'yes'} ],
						  [ 1, $text{'no'} ] ]).
					$awl_link,
				2, \@tds);
			}

		if ($hasemail) {
			# Show forwarding setup for this user, using
			# simple form if possible
			if (($user->{'email'} || $user->{'noprimary'}) &&
			    !$user->{'noalias'}) {
				print &ui_table_hr();

				# Work out if simple mode is supported
				if (!@{$user->{'to'}}) {
					# If no forwarding, just check delivery
					# to me as this is the default.
					$simple = { 'tome' => 1 };
					}
				else {
					$simple = &get_simple_alias(
							$d, $user, 1);
					}
				if ($simple && ($simple->{'local'} ||
						$simple->{'bounce'})) {
					# Local and bounce delivery are not allowed on the simple form,
					# unless we can merge some (@) local users with forward users, 
					# which will be handled automatically on save to prevent showing
					# advanced form for no reason
					$simple = undef
						if (!$simple->{'local-all'} || $simple->{'bounce'});
					}

				if ($simple) {
					# Show simple form
					print &ui_hidden("simplemode", "simple");
					&show_simple_form($simple, 1, 1, 1, 1, \@tds, "user");
					}
				else {
					# Show complex form
					print &ui_hidden("simplemode", "complex");
					&alias_form($user->{'to'},
						&hlink($text{'user_aliases'}, "userdest"),
						$d, "user", $in{'user'}, \@tds);
					}

				}
			# Show user-level mail filters, if he has any
			@filters = ( );
			$procmailrc = "$user->{'home'}/.procmailrc" if (!$in{'new'});
			if (!$in{'new'} && $user->{'email'} && -r $procmailrc &&
			&foreign_check("filter")) {
				&foreign_require("filter");
				@filters = &filter::list_filters($procmailrc);
				}
			if (@filters) {
				my $mail_filter_title = $text{'user_header3a'};
				my $mail_filter_body;
				$lastalways = 0;
				@folders = &mailboxes::list_user_folders($user->{'user'});
				@table = ( );
				foreach $filter (@filters) {
					($cdesc, $lastalways) = &filter::describe_condition($filter);
					$adesc = &filter::describe_action($filter, \@folders,
									$user->{'home'});
					push(@table, [ $cdesc, $adesc ]);
					}
				if (!$lastalways) {
					push(@table, [ $filter::text{'index_calways'},
						$filter::text{'index_adefault'} ]);
					}
				$mail_filter_body = &ui_columns_table(
					[ $text{'user_fcondition'}, $text{'user_faction'} ],
					100,
					\@table);
				my $mail_filter_details = &ui_details({
					'title' => $mail_filter_title,
					'content' => $mail_filter_body,
					'class' =>'default',
					'html' => 1});
				print &ui_table_row(undef, $mail_filter_details, 2, undef, ["data-row-wrapper='details'"]);
				}

			print &ui_hidden_table_end("table2a");
			}
		}

	# Cache the list of available mail plugins
	my @list_mail_plugins = &list_mail_plugins();

	# Test available plugins first
	foreach my $f (@list_mail_plugins) {
		if ($f eq "virtualmin-htpasswd") {
			$htpasswdplugin++;
			}
		else {
			$anyotherplugins++
				if (&plugin_defined($f, "mailbox_inputs"));
			}
		}

	# Put user databases select under separate category
	if (@dbs) {
		# Show allowed databases
		print &ui_hidden_table_start(
			$text{'user_header4'}, "width=100%", 2,
			"table4", 0, \@tds);
		@userdbs = map { [ $_->{'type'}."_".$_->{'name'},
				$_->{'name'}." ($_->{'desc'})" ] }
			       @{$user->{'dbs'}};
		@alldbs = map { [ $_->{'type'}."_".$_->{'name'},
				$_->{'name'}." ($_->{'desc'})" ] } @dbs;
		print &ui_table_row(&hlink($text{'user_dbs'},"userdbs"),
		    &ui_multi_select("dbs", \@userdbs, \@alldbs, 5, 1, 0,
			$text{'user_dbsall'}, $text{'user_dbssel'}), 2, \@tds);
		print &ui_hidden_table_end("table4");
		}

	# Put htpasswd into separate category for clarity
	if ($htpasswdplugin) {
		print &ui_hidden_table_start(
			$text{'user_header5'}, "width=100%", 2,
			"table5", 0, \@tds);
		foreach my $f (@list_mail_plugins) {
			if ($f eq "virtualmin-htpasswd") {
				$input = &plugin_call($f, "mailbox_inputs",
						      $user, $in{'new'}, $d);
				print $input;
				my $msg = &text('users_addprotecteddir2',
					&get_webprefix()."/virtualmin-htpasswd/index.cgi?dom=$d->{'id'}");
				print &ui_table_row("", $msg, 1);
				last;
				}
			}
		print &ui_hidden_table_end("table5");
		}

	# Other plugins permissions settings
	# Find and show all plugin features
	foreach my $f (@list_mail_plugins) {
		if ($f ne "virtualmin-htpasswd") {
			my $input = &trim(&plugin_call($f, "mailbox_inputs",
						       $user, $in{'new'}, $d));
			if ($input) {
				$anyotherpluginsdata .= &ui_table_hr()
					if ($list_mail_plugin++);
				$anyotherpluginsdata .= $input;
				}
			}
		}
	if ($anyotherplugins && $anyotherpluginsdata) {
		print &ui_hidden_table_start($text{'user_header6'},
			"width=100%", 2, "table6", 0, \@tds);
		print $anyotherpluginsdata;
		print &ui_hidden_table_end("table6");
		}

	# Work out if switching to Usermin is allowed
	$usermin = 0;
	if (&can_switch_usermin($d, $user) &&
	    &foreign_installed("usermin", 1)) {
		&foreign_require("usermin");
		local %uminiserv;
		&usermin::get_usermin_miniserv_config(\%uminiserv);
		if (&check_pid_file($uminiserv{'pidfile'}) &&
		    defined(&usermin::switch_to_usermin_user) &&
		    $uminiserv{'session'}) {
			$usermin = 1;
			}
		}
	}
# Form create/delete buttons
if ($form_end) {
	my @buts;
	if ($in{'new'}) {
		push(@buts, [ "create", $text{'create'} ]);
		}
	else {
		push(@buts, [ "save", $text{'save'} ]);
		if ($usermin) {
			push(@buts, [ "switch", $text{'user_switch'}, undef,
				undef, "onClick='form.target = \"_blank\"'" ]);
			}
		if ($user->{'domainowner'} && &will_send_domain_email($d)) {
			push(@buts, [ "remailbut", $text{'user_remailbut2'} ]);
			}
		elsif (!$user->{'domainowner'} &&
		       &will_send_user_email($d) && $user->{'email'}) {
			push(@buts, [ "remailbut", $text{'user_remailbut'} ] );
			}
		if ($user->{'recovery'}) {
			push(@buts, [ "recoverybut",$text{'user_sendrecover'} ]);
			}
		if (!$mailbox) {
			push(@buts, [ "delete", $text{'delete'} ]);
			}
		}
	print &ui_form_end(\@buts);
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

sub show_real_name_fields
{
my ($user, $autofill) = @_;

# First name and surname
if (&supports_firstname()) {
	my $onch = "";
	if ($autofill && $ldap_useradmin::config{'given_order'} == 0) {
		# Real name is first+last
		$onch = "onChange='form.real.value = form.firstname.value+\" \"+form.surname.value'";
		}
	elsif ($autofill && $ldap_useradmin::config{'given_order'} == 1) {
		# Real name is last+first
		$onch = "onChange='form.real.value = form.surname.value+\" \"+form.firstname.value'";
		}
	print &ui_table_row(
		&hlink($text{'user_firstname'}, "firstname"),
		&vui_noauto_textbox("firstname", $user->{'firstname'}, 40,
				    0, undef, $onch),
		2, \@tds);

	print &ui_table_row(
		&hlink($text{'user_surname'}, "surname"),
		&vui_noauto_textbox("surname", $user->{'surname'}, 40,
				    0, undef, $onch),
		2, \@tds);
	}

# Real name
print &ui_table_row(
	&hlink($text{'user_real'}, "realname"),
	&vui_noauto_textbox("real", $user->{'real'}, 40),
	2, \@tds);
}
