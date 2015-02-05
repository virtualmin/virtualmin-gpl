#!/usr/local/bin/perl
# Send a user his current or a random password, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});

# Get the user
@users = &list_domain_users($d);
($user) = grep { ($_->{'user'} eq $in{'user'} ||
		  &remove_userdom($_->{'user'}, $d) eq $in{'user'}) &&
		 $_->{'unix'} == $in{'unix'} } @users;
$user || &error("User does not exist!");

&ui_print_header(&domain_in($d), $text{'recovery_title'}, "");

if ($in{'confirm'}) {
	# Send the email
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
