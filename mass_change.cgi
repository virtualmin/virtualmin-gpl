#!/usr/local/bin/perl
# Actually update multiple users at once

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'mass_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
@mass = split(/\0/, $in{'d'});
@mass || &error($text{'mass_enone'});

&obtain_lock_unix($d);
&obtain_lock_mail($d);
@users = &list_domain_users($d);
@ashells = grep { $_->{'mailbox'} && $_->{'avail'} } &list_available_shells();

# Get the users
foreach $mu (@mass) {
	($unix, $name) = split(/\//, $mu, 2);
	($user) = grep { $_->{'user'} eq $name &&
			 $_->{'unix'} == $unix } @users;
	if ($user) {
		push(@musers, $user);
		}
	}
@musers || &error($text{'mass_enone'});

# Validate inputs
!&has_home_quotas() || $in{'quota_def'} != 0 ||
    $in{'quota'} =~ /^[0-9\.]+$/ || &error($text{'user_equota'});
!&has_mail_quotas() || $in{'mquota_def'} != 0 ||
    $in{'mquota'} =~ /^[0-9\.]+$/ || &error($text{'user_emquota'});
!&has_server_quotas() || $in{'qquota_def'} != 0 ||
    $in{'qquota'} =~ /^[0-9]+$/ || &error($text{'user_eqquota'});

# Update each one
&ui_print_unbuffered_header(&domain_in($d), $text{'mass_title'}, "");

foreach $user (@musers) {
	$changed = 0;
	$old = { %$user };
	&$first_print(&text('mass_user', "<tt>$user->{'user'}</tt>"));
	&$indent_print();
	$pop3 = &remove_userdom($user->{'user'}, $d);

	# Home directory quota
	if (&has_home_quotas() && $in{'quota_def'} != 2) {
		&$first_print($text{'mass_setquota'});
		if ($user->{'domainowner'}) {
			&$second_print($text{'mass_edomainowner'});
			}
		elsif ($user->{'noquota'}) {
			&$second_print($text{'mass_enoquota'});
			}
		elsif (!$user->{'unix'}) {
			&$second_print($text{'mass_eunix'});
			}
		elsif ($in{'quota_def'} == 1) {
			# Quota set to unlimited
			if ($user->{'quota'}) {
				$user->{'quota'} = 0;
				$changed++;
				}
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'quota_def'} == 0) {
			# Quota set to specific value
			$nq = &quota_parse("quota", "home");
			if ($nq != $user->{'quota'}) {
				$user->{'quota'} = $nq;
				$changed++;
				}
			&$second_print(&text('mass_setq',
					&quota_show($user->{'quota'}, "home")));
			}
		}

	# Mail file quota
	if (&has_mail_quotas() && $in{'mquota_def'} != 2) {
		&$first_print($text{'mass_setmquota'});
		if ($user->{'domainowner'}) {
			&$second_print($text{'mass_edomainowner'});
			}
		elsif ($user->{'noquota'}) {
			&$second_print($text{'mass_enoquota'});
			}
		elsif (!$user->{'unix'}) {
			&$second_print($text{'mass_eunix'});
			}
		elsif ($in{'mquota_def'} == 1) {
			if ($user->{'mquota'}) {
				$user->{'mquota'} = 0;
				$changed++;
				}
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'mquota_def'} == 0) {
			$nq = &quota_parse("mquota", "mail");
			if ($nq != $user->{'mquota'}) {
				$user->{'mquota'} = $nq;
				$changed++;
				}
			&$second_print(&text('mass_setq',
					&quota_show($user->{'mquota'},"mail")));
			}
		}

	# Mail server quota
	if (&has_server_quotas() && $in{'qquota_def'} != 2) {
		&$first_print($text{'mass_setqquota'});
		if (!$user->{'mailquota'}) {
			&$second_print($text{'mass_emailquota'});
			}
		elsif ($in{'qquota_def'} == 1) {
			if ($user->{'qquota'}) {
				$user->{'qquota'} = 0;
				$changed++;
				}
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'qquota_def'} == 0) {
			if ($user->{'qquota'} != $in{'qquota'}) {
				$user->{'qquota'} = $in{'qquota'};
				$changed++;
				}
			&$second_print(&text('mass_setq', $user->{'qquota'}));
			}
		}

	# Primary email address
	if ($in{'email'}) {
		&$first_print($text{'mass_setprimary'});
		if ($user->{'noprimary'}) {
			&$second_print($text{'mass_eprimary'});
			}
		elsif ($in{'email'} == 1) {
			if ($user->{'email'} ne $pop3."\@".$d->{'dom'}) {
				$user->{'email'} = $pop3."\@".$d->{'dom'};
				$changed++;
				}
			&$second_print(&text('mass_primarye',$user->{'email'}));
			}
		elsif ($in{'email'} == 2) {
			if ($user->{'email'}) {
				$user->{'email'} = undef;
				$changed++;
				}
			&$second_print($text{'mass_primaryd'});
			}
		}

	# FTP login
	if (!$in{'shell_def'} && &can_mailbox_ftp()) {
		&$first_print($text{'mass_setshell'});
		($shell) = grep { $_->{'shell'} eq $in{'shell'} }
				@ashells;
		if (!$user->{'unix'}) {
			&$second_print($text{'mass_eunix'});
			}
		elsif ($shell) {
			if ($user->{'shell'} ne $in{'shell'}) {
				$user->{'shell'} = $in{'shell'};
				$changed++;
				}
			&$second_print(&text('mass_shelldone',
					     $shell->{'desc'}));
			}
		else {
			&$second_print(&text('mass_shellbad'));
			}
		}

	if ($in{'disable'}) {
		&$first_print($text{'mass_setdisable'});
		if ($user->{'alwaysplain'}) {
			&$second_print($text{'mass_eplain'});
			}
		elsif ($in{'disable'} == 1) {
			# Enabling
			if ($user->{'pass'} =~ /^\!/) {
				&set_pass_disable($user, 0);
				$changed++;
				}
			&$second_print($text{'mass_disable1'});
			}
		elsif ($in{'disable'} == 2) {
			# Disabling
			if ($user->{'pass'} !~ /^\!/) {
				&set_pass_disable($user, 1);
				$changed++;
				}
			&$second_print($text{'mass_disable2'});
			}
		}

	# Save the user
	&modify_user($user, $old, $d);

	# Email user if requested
	if ($in{'updateemail'} && $changed && $user->{'email'}) {
		&send_user_email($d, $user, $user->{'email'}, 1);
		}

	&$outdent_print();
	&$second_print($text{'setup_done'});
	}
&release_lock_unix($d);
&release_lock_mail($d);
&run_post_actions();
&webmin_log("modify", "users", scalar(@musers),
	    { 'dom' => $d->{'dom'} });

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return2'});

