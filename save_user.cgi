#!/usr/local/bin/perl
# save_user.cgi
# Create, update or delete a user

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

if ($in{'recoverybut'}) {
	# Redirect to password recovery form
	&redirect("recovery.cgi?dom=$in{'dom'}&user=$in{'old'}&".
		  "unix=$in{'unix'}");
	return;
	}

if (!$in{'delete'} || $in{'confirm'}) {
	&obtain_lock_unix($d);
	&obtain_lock_mail($d);
	}
@users = &list_domain_users($d);
$tmpl = $d ? &get_template($d->{'template'}) : &get_template(0);
if (!$in{'new'}) {
	# Lookup user details
	($user) = grep { ($_->{'user'} eq $in{'old'} ||
			  &remove_userdom($_->{'user'}, $d) eq $in{'old'}) &&
			 $_->{'unix'} == $in{'unix'} } @users;
	$user || &error("User does not exist!");
	%old = %$user;
	$mailbox = $d && $d->{'user'} eq $user->{'user'} && $user->{'unix'};
	$user->{'olduser'} = $user->{'user'};
	}
else {
	# Construct initial user object
	$user = &create_initial_user($d, undef, $in{'web'});
	}
&error_setup($text{'user_err'});
&require_useradmin();

&build_taken(\%taken, \%utaken);

if ($in{'switch'}) {
	# Auto-login to Usermin
	&can_switch_usermin($d, $user) ||
		&error($text{'user_eswitch'});
	&foreign_require("usermin", "usermin-lib.pl");
	($cookie, $url) = &usermin::switch_to_usermin_user($user->{'user'});
	print "Set-Cookie: $cookie\n";
	&redirect($url);
	return;
	}
elsif ($in{'remailbut'}) {
	# Re-send signup email
	&error_setup($text{'user_err2'});
	@erv = &send_user_email($d, $user, $user->{'email'}, 0);
	if (!$erv[0]) {
		&error($erv[1]);
		}
	&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");
	return;
	}
elsif ($in{'delete'}) {
	# Just deleting a user
	if ($in{'confirm'}) {
		# Get rid of his mail file
		$mailbox && &error($text{'user_edelete'});
		if (!$user->{'nomailfile'}) {
			&delete_mail_file($user);
			}

		# Delete simple autoreply file
		$simple = &get_simple_alias($d, $user);
		&delete_simple_autoreply($d, $simple) if ($simple);

		# Delete the user, his virtusers and aliases
		&delete_user($user, $d);

		if (!$user->{'nocreatehome'} && $user->{'home'}) {
			# Remove home directory
			&delete_user_home($user, $d);
			}

		# Delete in plugins
		foreach $f (&list_mail_plugins()) {
			&plugin_call($f, "mailbox_delete", $user, $d);
			}

		# Delete in other modules
		if ($config{'other_users'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_delete_user", $user);
			}

		$user->{'dom'} = $d->{'dom'};
		delete($user->{'plainpass'}) if ($d->{'hashpass'});
		&set_all_null_print();
		&run_post_actions();
		&release_lock_unix($d);
		&release_lock_mail($d);
		&webmin_log("delete", "user",
			    &remove_userdom($user->{'user'}, $d), $user);
		}
	else {
		# Confirm deletion first
		$ind = $d ? &domain_in($d) : undef;
		&ui_print_header($ind, $text{'user_delete'}, "");

		print "<center>\n";
		print &ui_form_start("save_user.cgi");
		print &ui_hidden("dom", $in{'dom'});
		print &ui_hidden("old", $in{'old'});
		print &ui_hidden("unix", $in{'unix'});
		print &ui_hidden("delete", 1);

		# Count up home directory size
		local ($mailsz) = &mail_file_size($user);
		local ($homesz) = &disk_usage_kb($user->{'home'});
		local $msg = $user->{'nocreatehome'} || !$user->{'home'} ?
				'user_rusurew' :
			     $mailsz && $homesz && !&mail_under_home() ?
				'user_rusure' :'user_rusureh';
		print "<p>",&text($msg, "<tt>$in{'old'}</tt>",
			  	  &nice_size($mailsz),
				  &nice_size($homesz*1024),
				  "<tt>$user->{'home'}</tt>"),"<p>\n";

		# Check for home directory clash
		if (!$user->{'nocreatehome'} && $user->{'home'} &&
		    !$user->{'webowner'}) {
			local @hclash = grep {
				(&same_file($_->{'home'}, $user->{'home'}) ||
				 &is_under_directory($user->{'home'},
						     $_->{'home'})) &&
				$_ ne $user } @users;
			if (@hclash) {
				print "<b>",&text('user_hclash',
				    join(" ", map { "<tt>$_->{'user'}</tt>" }
						  @hclash)),"</b><p>\n";
				}
			}

		print &ui_form_end([ [ "confirm", $text{'user_deleteok'} ] ]);
		print "</center>\n";

		if ($d) {
			&ui_print_footer("list_users.cgi?dom=$in{'dom'}",
				$text{'users_return'});
			}
		else {
			&ui_print_footer("", $text{'index_return'});
			}
		exit;
		}
	}
else {
	# Saving or creating, so verify inputs
	if ($in{'new'} && $d) {
		($mleft, $mreason, $mmax) = &count_feature("mailboxes");
		$mleft == 0 && &error($text{'user_emailboxlimit'});
		}
	if (!$mailbox) {
		if (!$config{'allow_upper'}) {
			$in{'mailuser'} = lc($in{'mailuser'});
			}
		$err = &valid_mailbox_name($in{'mailuser'});
		&error($err) if ($err);
		if ($user->{'person'}) {
			$in{'real'} =~ /^[^:\r\n]*$/ ||
				&error($text{'user_ereal'});
			$user->{'real'} = $in{'real'};
			}
		if (!$in{'new'} && $in{'mailpass_def'}) {
			# Password not being changed
			$user->{'passmode'} = 4;
			}
		else {
			# Either password is being changed, or this is new user
			$user->{'plainpass'} =
				&parse_new_password("mailpass", 1);
			$need_password_check = 1;
			$user->{'pass'} = &encrypt_user_password(
					$user, $user->{'plainpass'});
			$user->{'passmode'} = 3;
			&set_pass_change($user);
			}
		if (!$user->{'alwaysplain'}) {
			# Disable account if requested
			&set_pass_disable($user, $in{'disable'});
			}
		if ($user->{'mailquota'}) {
			# Check and save qmail quota
			if (!$in{'qquota_def'}) {
				$in{'qquota'} =~ /^\d+$/ ||
					&error($text{'user_eqquota'});
				$user->{'qquota'} = $in{'qquota'};
				}
			else {
				$user->{'qquota'} = 0;
				}
			}
		if ($user->{'unix'} && !$user->{'noquota'}) {
			# Check and save quota inputs
			$qedit = &can_mailbox_quota();
			@defmquota = split (/ /, $tmpl->{'defmquota'});
			$pd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
			if (&has_home_quotas() && $qedit) {
				# Use entered quota
				if ( $in{'quota'} eq -1 ) {
					$in{'quota'} = $in{'otherquota'};
					}
				$in{'quota_def'} || $in{'quota'} =~ /^[0-9\.]+$/ ||
					&error($text{'user_equota'});
				$user->{'quota'} = $in{'quota_def'} ? 0 : &quota_parse("quota", "home");
				!$user->{'quota'} || !$pd->{'quota'} ||
				  $user->{'quota'} <= $pd->{'quota'} ||
				  &error(&text('user_eoverquota',
					&nice_size($pd->{'quota'}*
						   &quota_bsize("home"))));
				}
			elsif (&has_home_quotas() && $in{'new'}) {
				# Use default
				$user->{'quota'} = $defmquota[0];
				}
			if (&has_mail_quotas() && $qedit) {
				if ( $in{'mquota'} eq -1 ) {
					$in{'mquota'} = $in{'othermquota'};
					}
				$in{'mquota_def'} || $in{'mquota'} =~ /^[0-9\.]+$/ ||
					&error($text{'user_equota'});
				$user->{'mquota'} = $in{'mquota_def'} ? 0 : &quota_parse("mquota", "mail");
				!$user->{'mquota'} || !$pd->{'mquota'} ||
				  $user->{'mquota'} <= $pd->{'mquota'} ||
				  &error(&text('user_eovermquota',
					&nice_size($pd->{'mquota'}*
						   &quota_bsize("mail"))));
				}
			elsif (&has_mail_quotas() && $in{'new'}) {
				# Use default
				$user->{'mquota'} = $defmquota[0];
				}
			}

		if ($d) {
			# Save list of allowed databases
			local ($db, @dbs);
			foreach $db (split(/\r?\n/, $in{'dbs'})) {
				local ($type, $name) = split(/_/, $db, 2);
				push(@dbs, { 'type' => $type,
					     'name' => $name });
				}
			$user->{'dbs'} = \@dbs;
			}
		}
	else {
		# For a domain owner, the password is never changed here
		$user->{'passmode'} = 4;
		}

	# Save extra email addresses
	%oldextra = ( );
	if (!$in{'new'}) {
		%oldextra = map { $_, 1 } @{$old{'extraemail'}};
		}
	$eu = $mailbox ? $d->{'user'} : $in{'mailuser'};
	@extra = split(/\s+/, $in{'extra'});
	%donextra = ( );
	foreach $e (@extra) {
		$e = lc($e);
		if ($d && $e =~ /^([^\@ \t]+$)$/) {
			$e = "$e\@$d->{'dom'}";
			}
		if ($e !~ /^(\S*)\@(\S+)$/) {
			&error(&text('user_eextra1', $e));
			}
		if ($e eq $eu."\@".$d->{'dom'}) {
			&error(&text('user_eextra5', $e));
			}
		local ($eu, $ed) = ($1, $2);
		local $edom = &get_domain_by("dom", $ed);
		$edom && $edom->{'mail'} || &error(&text('user_eextra2', $ed));
		&can_edit_domain($edom) || $oldextra{$e} ||
			&error(&text('user_eextra3', $ed));
		!$edom->{'alias'} || !$edom->{'aliascopy'} ||
			&error(&text('user_eextra7', $ed));
		$donextra{lc($e)}++ && &error(&text('user_eextra6', $e));
		}
	$user->{'extraemail'} = \@extra;

	# Check if extras would exceed limit
	($mleft, $mreason, $mmax) = &count_feature("aliases");
	if ($mleft >= 0 &&
	    $mleft - @extra + (%old ? @{$old{'extraemail'}} : 0) < 0) {
		&error($text{'alias_ealiaslimit'});
		}

	# Save primary email address
	if ($d && !$user->{'noprimary'}) {
		$user->{'email'} = $in{'mailbox'} ? $eu."\@".$d->{'dom'}
						  : undef;
		}

	# Save recovery address
	if (!$mailbox) {
		$in{'recovery_def'} || $in{'recovery'} =~ /^\S+\@\S+$/ ||
			&error($text{'user_erecovery'});
		$user->{'recovery'} = $in{'recovery_def'} ? ""
							  : $in{'recovery'};
		}

	# Get the email address to send new/updated mailbox, for the mailbox
	# itself. Email may also be sent to the reseller and domain owner
	if ($in{'new'} && &will_send_user_email($d, 1) &&
	    !$in{'newmail_def'}) {
		$in{'newmail'} =~ /^\S+$/ || &error($text{'user_enewmail'});
		$newmailto = $in{'newmail'};
		}
	elsif (!$in{'new'} && &will_send_user_email($d, 0) &&
	       !$in{'remail_def'}) {
		$in{'remail'} =~ /^\S+$/ || &error($text{'user_eremail'});
		$newmailto = $in{'remail'};
		}

	if (!$mailbox && !$user->{'fixedhome'} && !$user->{'brokenhome'}) {
		# Find home
		if (&can_mailbox_home($user) &&
		    $d && $d->{'home'} && !$in{'home_def'}) {
			$in{'home'} =~ /^\S.*\S$/ && $in{'home'} !~ /\.\./ ||
				&error($text{'user_ehome'});
			$in{'home'} =~ /^\// && &error($text{'user_ehome2'});
			if ($user->{'webowner'}) {
				# Custom home directory for web FTP user
				$home = &public_html_dir($d)."/".$in{'home'};
				}
			else {
				# Custom home directory for mailbox user
				$home = "$d->{'home'}/$in{'home'}";
				}
			$user->{'maybecreatehome'} = 1;
			}
		elsif ($d) {
			if ($user->{'webowner'}) {
				# Auto home directory for web FTP user
				$home = &public_html_dir($d);
				}
			else {
				# Auto home directory for mailbox user
				$home = "$d->{'home'}/$config{'homes_dir'}/".
					$in{'mailuser'};
				}
			}
		else {
			# Auto home directory for local user
			$home = &useradmin::auto_home_dir(
				$home_base, $in{'mailuser'},
				$config{'localgroup'});
			}

		# Make sure home exists, for web owner user
		if ($user->{'webowner'} && !-d $home) {
			&error($text{'user_ehomeexists'});
			}
		}

	# Update secondary groups
	%cangroups = map { $_, 1 } (&allowed_secondary_groups($d),
				    @{$user->{'secs'}});
	@secs = split(/\0/, $in{'groups'});
	foreach my $g (@secs) {
		$cangroups{$g} || &error(&text('user_egroup', $g));
		}
	$user->{'secs'} = [ @secs ];

	# Update no-spam flag
	if ($config{'spam'} && $d->{'spam'}) {
		$user->{'nospam'} = $in{'nospam'};
		}

	# Work out full email address, perhaps with real name
	if ($user->{'real'}) {
		$fullemail = '"'.$user->{'real'}.'" <'.$user->{'email'}.'>';
		}
	else {
		$fullemail = $user->{'email'};
		}

	# Create or update the user
	$emailmailbox = 0;
	if ($in{'new'}) {
		# Set new user parameters
		if ($user->{'unix'} && !$user->{'webowner'}) {
			# UID needs to be unique
			$user->{'uid'} = &allocate_uid(\%taken);
			}
		else {
			# UID is same as domain for Qmail users and web owners
			$user->{'uid'} = $d->{'uid'};
			}
		$user->{'gid'} = $d ? $d->{'gid'} :
				      getgrnam($config{'localgroup'});

		# Check for clash within this domain
		($clash) = grep { $_->{'user'} eq $in{'mailuser'} &&
			  	  $_->{'unix'} == $user->{'unix'} } @users;
		$clash && &error($text{'user_eclash2'});

		if ($user->{'unix'}) {
			if (&can_mailbox_ftp()) {
				# Shell can be set based on FTP flag
				&check_available_shell($in{'shell'}, 'mailbox',
						       undef) ||
					&error($text{'user_eshell'});
				$user->{'shell'} = $in{'shell'};
				}
			elsif ($in{'new'}) {
				# If the shell cannot be edited, always use
				# the default.
				$user->{'shell'} =
					&default_available_shell('mailbox');
				}
			}
		if (!$user->{'fixedhome'} && !$user->{'brokenhome'}) {
			$user->{'home'} = $home;
			}

		if (($utaken{$in{'mailuser'}} || ($d && $config{'append'})) &&
		    !$user->{'noappend'}) {
			# Need to append domain name
			if ($d) {
				# Add group name
				$user->{'user'} = &userdom_name($in{'mailuser'},$d);
				}
			else {
				# No domain to add, so give up!
				&error($text{'user_eclash2'});
				}
			}
		else {
			# Username is as entered
			$user->{'user'} = $in{'mailuser'};
			}

		if ($d && $user->{'unix'}) {
			# Check for a Unix clash
			$mclash = &check_clash($in{'mailuser'}, $d->{'dom'});
			if ($utaken{$user->{'user'}} ||
			    $user->{'email'} && $mclash ||
			    !$user->{'email'} && $mclash == 2) {
				&error($text{'user_eclash'});
				}
			}

		# Check if any extras clash
		foreach $e (@extra) {
			$e =~ /^(\S*)\@(\S+)$/;
			if (&check_clash($1, $2)) {
				&error(&text('user_eextra4', $e));
				}
			}

		# Check if the name is too long
		if ($user->{'unix'} &&
		    ($lerr = &too_long($user->{'user'}))) {
			&error($lerr);
			}

		# Check if home directory already exists
		if (-e $home && !$user->{'nocreatehome'} &&
		    !$user->{'maybecreatehome'}) {
			&error(&text('user_emkhome', $home));
			}

		# Set mail file location
		if ($user->{'qmail'}) {
			&userdom_substitutions($user, $d);
			$user->{'mailstore'} =
			    &substitute_virtualmin_template(
				$config{'ldap_mailstore'}, $user);
			}

		if (!$user->{'noalias'}) {
			# Save alias
			if ($in{'simplemode'} eq 'simple') {
				# From simple form
				$simple = &get_simple_alias($d, $user);
				&parse_simple_form($simple, \%in, $d, 1, 1, 1,
						   $user->{'user'});
				$simple->{'from'} = $fullemail;
				&save_simple_alias($d, $user, $simple);
				if (@{$user->{'to'}} == 1 &&
				    $simple->{'tome'}) {
					# If forwarding is just to the user's
					# mailbox, then that is like no
					# forwarding at all
					$user->{'to'} = undef;
					}
				}
			else {
				# From complex form
				@values = &parse_alias(undef, $user->{'user'},
						       undef, "user", $d);
				$user->{'to'} = @values ? \@values : undef;
				}

			# Check for alias loop
			&check_email_to_loop();
			}

		# Now we have the username, check the password
		if ($need_password_check) {
			$perr = &check_password_restrictions($user, 0, $d);
			&error($perr) if ($perr);
			}

		# Validate plugins
		foreach $f (&list_mail_plugins()) {
			$err = &plugin_call($f, "mailbox_validate", $user, \%old, \%in, $in{'new'}, $d);
			&error($err) if ($err);
			}

		# Validate user
		$err = &validate_user($d, $user);
		&error($err) if ($err);

		if ($home && !$user->{'nocreatehome'} &&
		    (!$user->{'maybecreatehome'} || !-d $home)) {
			# Create his homedir, unless either this is a user
			# who has none, or it already exists
			&create_user_home($user, $d);
			}

		# Create the user and virtusers and alias
		&create_user($user, $d);

		# Send an email upon creation
		if ($user->{'email'} || $newmailto) {
			$emailmailbox = 1;
			}
		}
	else {
		# Check if any extras clash
		%oldextra = map { $_, 1 } @{$old{'extraemail'}};
		foreach $e (@extra) {
			$e =~ /^(\S*)\@(\S+)$/;
			if (!$oldextra{$e} && &check_clash($1, $2)) {
				&error(&text('user_eextra4', $e));
				}
			}

		# For any user except the domain owner, update his home and shel
		if (!$mailbox) {
			# Check if new homedir already exists, if changed
			if (-e $home &&
			    &simplify_path($user->{'home'}) ne
			     &simplify_path($home) &&
			    &resolve_links($user->{'home'}) ne
			     &resolve_links($home) &&
			    $user->{'home'} ne $home &&
			    !$user->{'nocreatehome'}) {
				&error(&text('user_emkhome', $home));
				}

			# Update user parameters (handle rename and .group)
			if ($in{'mailuser'} ne $in{'oldpop3'}) {
				# Check for a clash in this domain
				($clash) = grep { $_->{'user'} eq $in{'mailuser'} &&
				  $_->{'unix'} == $user->{'unix'} } @users;
				$clash && &error($text{'user_eclash2'});

				# Has been renamed .. check for a username clash
				if ($d && ($utaken{$in{'mailuser'}} ||
					   $config{'append'}) &&
				    !$user->{'noappend'}) {
					# New name has to include group
					$style = &guess_append_style(
							$user->{'user'}, $d);
					$user->{'user'} = &userdom_name(
						$in{'mailuser'}, $d, $style);
					}
				else {
					# Can rename without the dot
					$user->{'user'} = $in{'mailuser'};
					}

				# Check if the name is too long
				if ($lerr = &too_long($user->{'user'})) {
					&error($lerr);
					}

				# Check for a virtuser clash too
				if ($d && &check_clash($in{'mailuser'},
						       $d->{'dom'})) {
					&error($text{'user_eclash'});
					}
				}
			}

		if (!$user->{'noalias'}) {
			# Save aliases
			if ($in{'simplemode'} eq 'simple') {
				# From simple form
				$simple = &get_simple_alias($d, \%old);
				&parse_simple_form($simple, \%in, $d, 1, 1, 1,
						   $user->{'user'});
				$simple->{'from'} = $fullemail;
				&save_simple_alias($d, $user, $simple);
				if (@{$user->{'to'}} == 1 &&
				    $simple->{'tome'}) {
					# If forwarding is just to the user's
					# mailbox, then that is like no
					# forwarding at all
					$user->{'to'} = undef;
					}
				}
			else {
				# From complex form
				@values = &parse_alias(undef, $user->{'user'},
						$old{'to'}, "user", $d);
				$user->{'to'} = @values ? \@values : undef;
				}

			# Check for alias loop
			&check_email_to_loop();
			}

		# Validate plugins
		foreach $f (&list_mail_plugins()) {
			$err = &plugin_call($f, "mailbox_validate", $user, \%old, \%in, $in{'new'}, $d);
			&error($err) if ($err);
			}

		# Now we have the username, check the password
		if ($need_password_check) {
			$perr = &check_password_restrictions($user, 0, $d);
			&error($perr) if ($perr);
			}

		# Validate user
		$err = &validate_user($d, $user, \%old);
		&error($err) if ($err);

		if (!$mailbox) {
			# Rename homedir
			if ($user->{'home'} ne $home &&
			    (-d $user->{'home'} || $user->{'nocreatehome'}) &&
			    !$user->{'fixedhome'} && !$user->{'brokenhome'}) {
				if (!$user->{'nocreatehome'}) {
					&rename_file($user->{'home'}, $home);
					}
				$user->{'home'} = $home;
				}

			# Update shell
			if (defined($in{'shell'})) {
				&check_available_shell($in{'shell'}, 'mailbox',
						       $user->{'shell'}) ||
					&error($text{'user_eshell'});
				$user->{'shell'} = $in{'shell'};
				}

			# Set mail file location
			if ($user->{'qmail'}) {
				local $store = &substitute_virtualmin_template(
					$config{'ldap_mailstore'}, $user);
				$user->{'mailstore'} = $store;
				}

			if (!$user->{'nomailfile'}) {
				# Rename his mail file (if needed)
				&rename_mail_file($user, \%old);
				}
			}

		# Update the user and any virtusers and aliases
		&modify_user($user, \%old, $d);

		# Send an email upon changes
		if ($newmailto) {
			$emailmailbox = 1;
			}
		}

	# Create an empty mail file, if needed
	if ($user->{'email'} && ($in{'new'} || !$old{'email'} ||
				 $user->{'user'} ne $old{'user'})) {
		&create_mail_file($user, $d);
		}

	# Run plugin save functions
	foreach $f (&list_mail_plugins()) {
		$dp = &plugin_call($f, "mailbox_save", $user, \%old,
				   \%in, $in{'new'}, $d);
		if ($dp eq '1') {
			# For use by email template
			$user->{$f} = 1;
			}
		else {
			$user->{$f} = 0;
			}
		}

	# Send email about update or creation, unless autoreplying
	if (!$simple || !$simple->{'auto'}) {
		@erv = &send_user_email($d, $user,
					$emailmailbox ? $newmailto : "none",
					$in{'new'} ? 0 : 1);
		}

	# Call other module functions
	if ($config{'other_users'}) {
		if ($in{'new'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_create_user", $user);
			}
		else {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_modify_user", $user, \%old);
			}
		}

	if ($simple) {
		# Write out the simple alias autoreply file
		&write_simple_autoreply($d, $simple);
		}

	&set_all_null_print();
	&run_post_actions();
	$user->{'dom'} = $d->{'dom'};
	delete($user->{'plainpass'}) if ($d->{'hashpass'});
	&release_lock_unix($d);
	&release_lock_mail($d);
	&webmin_log($in{'new'} ? "create" : "modify", "user",
		    &remove_userdom($user->{'user'}, $d), $user);
	}
&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");

# Call error if the user's forwarding address is his own address
sub check_email_to_loop
{
foreach my $t (@{$user->{'to'}}) {
	if ($t eq $user->{'email'}) {
		&error($text{'user_eloop'});
		}
	}
}

