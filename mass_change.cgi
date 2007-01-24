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

&lock_user_db();
@users = &list_domain_users($d);

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
$in{'quota_def'} < 2 || $in{'quota'} =~ /^[0-9\.]+$/ ||
	&error($text{'user_equota'});
$in{'mquota_def'} < 2 || $in{'mquota'} =~ /^[0-9\.]+$/ ||
	&error($text{'user_emquota'});
$in{'qquota_def'} < 2 || $in{'qquota'} =~ /^[0-9]+$/ ||
	&error($text{'user_eqquota'});

# Update each one
&ui_print_unbuffered_header(&domain_in($d), $text{'mass_title'}, "");

foreach $user (@musers) {
	$old = { %$user };
	&$first_print(&text('mass_user', "<tt>$user->{'user'}</tt>"));
	&$indent_print();
	$pop3 = &remove_userdom($user->{'user'}, $d);

	# Home directory quota
	if ($in{'quota_def'}) {
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
			$user->{'quota'} = 0;
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'quota_def'} == 2) {
			$user->{'quota'} = &quota_parse("quota", "home");
			&$second_print(&text('mass_setq',
					&quota_show($user->{'quota'}, "home")));
			}
		}

	# Mail file quota
	if ($in{'mquota_def'}) {
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
			$user->{'mquota'} = 0;
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'mquota_def'} == 2) {
			$user->{'mquota'} = &quota_parse("mquota", "mail");
			&$second_print(&text('mass_setq',
					&quota_show($user->{'mquota'},"mail")));
			}
		}

	# Mail server quota
	if ($in{'qquota_def'}) {
		&$first_print($text{'mass_setqquota'});
		if (!$user->{'mailquota'}) {
			&$second_print($text{'mass_emailquota'});
			}
		elsif ($in{'qquota_def'} == 1) {
			$user->{'qquota'} = 0;
			&$second_print($text{'mass_setu'});
			}
		elsif ($in{'qquota_def'} == 2) {
			$user->{'qquota'} = $in{'qquota'};
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
			$user->{'email'} = $pop3."\@".$d->{'dom'};
			&$second_print(&text('mass_primarye',$user->{'email'}));
			}
		elsif ($in{'email'} == 2) {
			$user->{'email'} = undef;
			&$second_print($text{'mass_primaryd'});
			}
		}

	# FTP login
	if ($in{'ftp'} && &can_mailbox_ftp()) {
		&$first_print($text{'mass_setftp'});
		if (!$user->{'unix'}) {
			&$second_print($text{'mass_eunix'});
			}
		elsif ($in{'ftp'} == 1) {
			$user->{'shell'} = $config{'ftp_shell'};
			&$first_print($text{'mass_ftp1'});
			}
		elsif ($in{'ftp'} == 2) {
			$user->{'shell'} = $config{'shell'};
			&$first_print($text{'mass_ftp2'});
			}
		elsif ($in{'ftp'} == 3) {
			$user->{'shell'} = $config{'jail_shell'};
			&$first_print($text{'mass_ftp3'});
			}
		}

	if ($in{'disable'}) {
		&$first_print($text{'mass_setdisable'});
		if ($user->{'alwaysplain'}) {
			&$second_print($text{'mass_eplain'});
			}
		elsif ($in{'disable'} == 1) {
			&set_pass_disable($user, 0);
			&$first_print($text{'mass_disable1'});
			}
		elsif ($in{'disable'} == 2) {
			&set_pass_disable($user, 1);
			&$first_print($text{'mass_disable2'});
			}
		}

	# Save the user
	&modify_user($user, $old, $d);

	&$outdent_print();
	&$second_print($text{'setup_done'});
	}
&unlock_user_db();

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return2'});

