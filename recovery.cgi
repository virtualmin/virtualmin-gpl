#!/usr/local/bin/perl
# Send a user his current or a random password, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
&foreign_require("mailboxes");

# Get the user
@users = &list_domain_users($d);
($user) = grep { ($_->{'user'} eq $in{'user'} ||
		  &remove_userdom($_->{'user'}, $d) eq $in{'user'}) &&
		 $_->{'unix'} == $in{'unix'} } @users;
$user || &error("User does not exist!");

&ui_print_header(&domain_in($d), $text{'recovery_title'}, "");

if ($in{'confirm'}) {
	# Generate a new password
	if (!$user->{'plainpass'}) {
		local $olduser = { %$user };
		$user->{'passmode'} = 3;
		$user->{'plainpass'} = &random_password();
		$user->{'pass'} = &encrypt_user_password(
					$user, $user->{'plainpass'});
		&modify_user($user, $olduser, $d);

		# Call plugin save functions
		foreach my $f (&list_mail_plugins()) {
			&plugin_call($f, "mailbox_modify",
				     $user, $olduser, $d);
			}
		$msgt = "recovery_body2";
		}
	else {
		$msgt = "recovery_body1";
		}

	# Send the email
	my $email = &remove_userdom($user->{'user'}, $d)."\@".
		    &show_domain_name($d);
	my $msg = &text($msgt, $user->{'plainpass'},
			$user->{'user'}, $email)."\n";
	$msg = join("\n", &mailboxes::wrap_lines($msg, 75));
	my $subject = &text('recovery_subject', $email);

	&$first_print(&text('recovery_sending',
			"<tt>".&html_escape($user->{'recovery'})."</tt>"));
	($ok, $err) = &send_template_email($msg, $user->{'recovery'}, { },
					   $subject, undef, undef, $d);
	if ($ok) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('recovery_failed', $err));
		}
	}
else {
	# Show a confirmation form
	print &ui_confirmation_form(
		"recovery.cgi",
		&text($user->{'plainpass'} ? 'recovery_msg1' : 'recovery_msg2',
		      "<tt>".&html_escape($user->{'user'})."</tt>",
		      "<tt>".&html_escape($user->{'recovery'})."</tt>"),
		[ [ "user", $in{'user'} ],
		  [ "unix", $in{'unix'} ],
		  [ "dom", $in{'dom'} ] ],
		[ [ "confirm", $text{'recovery_send'} ] ],
		);
	}

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});
