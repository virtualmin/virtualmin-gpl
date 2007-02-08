#!/usr/local/bin/perl
# Delete serveral users in a domain, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'users_derr'});

$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
@del = split(/\0/, $in{'d'});
@del || &error($text{'users_ednone'});

&lock_user_db();
@users = &list_domain_users($d);

# Get the users
foreach $du (@del) {
	($unix, $name) = split(/\//, $du, 2);
	($user) = grep { $_->{'user'} eq $name &&
			 $_->{'unix'} == $unix } @users;
	if ($user) {
		push(@dusers, $user);
		&error($text{'users_edunix'}) if ($user->{'domainowner'});
		}
	}

if ($in{'confirm'}) {
	# Do it!
	foreach $user (@dusers) {
		# Delete mail file
		if (!$user->{'nomailfile'}) {
			&delete_mail_file($user);
			}

		# Delete the user, his virtusers and aliases
		&delete_user($user, $d);

		# Remove home directory
		if (!$user->{'nocreatehome'} && $user->{'home'}) {
			&delete_user_home($user, $d);
			}

		# Delete in plugins
		foreach $f (@mail_plugins) {
			&plugin_call($f, "mailbox_delete", $user, $d);
			}

		# Delete in other modules
		if ($config{'other_users'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_delete_user", $user);
			}
		}
	&run_post_actions();
	&webmin_log("delete", "users", scalar(@dusers),
		    { 'dom' => $d->{'dom'} });
	&redirect("list_users.cgi?dom=$in{'dom'}");
	}
else {
	# Ask first
	&ui_print_header(&domain_in($d), $text{'users_dtitle'}, "");
	print &ui_form_start("delete_users.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	foreach $du (@del) {
		print &ui_hidden("d", $du),"\n";
		}
	foreach $user (@dusers) {
		if (!$user->{'nomailfile'} && !&mail_under_home()) {
			local ($mailsz) = &mail_file_size($user);
			$total += $mailsz;
			}
		if (!$user->{'nocreatehome'} && $user->{'home'}) {
			local $homesz = &disk_usage_kb($user->{'home'});
			$total += $homesz*1024;
			}
		}
	print "<center>\n";
	print &text($total ? 'users_drusure' : 'users_drusure2',
			scalar(@dusers), &nice_size($total)),"<p>\n";
	print &ui_form_end([ [ "confirm", $text{'users_dconfirm'} ] ]);
	print "</center>\n";
	&ui_print_footer("list_users.cgi?dom=$in{'dom'}",
			 $text{'users_return'});
	}
&unlock_user_db();

