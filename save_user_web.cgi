#!/usr/local/bin/perl
# save_user_db.cgi
# Create, update or delete webserver
# user without creating a Unix user

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'user_err'});
my ($d, $user);
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'users_ecannot'});
	}
else {
	&can_edit_local() || &error($text{'users_ecannot2'});
	}
&can_edit_users() || &error($text{'users_ecannot'});
$virtualmin_pro || &error($text{'users_ecannot4web'});

# User to edit or delete
my $user_full = lc("$in{'webuser'}"."@".$d->{'dom'});
if (!$in{'new'}) {
        my $olduser_name = $in{'olduser'};
        $user = &get_extra_web_user($d, $olduser_name);
        $user || &error(&text('user_edoesntexist', &html_escape($olduser_name)));
        my %olduser = %{$user};
        # If renaming user, check if new name is not already used
        if ($olduser_name ne $user_full) {
                my $user_check = &check_extra_user_clash($d, $user_full, 'web');
                !$user_check || &error($user_check);
                }

        if ($in{'delete'}) {
                # Delete webserver user using plugin
                $olduser{'user'} = $olduser_name;
		&delete_webserver_user(\%olduser, $d);
	        }
        else {
                # Update user
                $user->{'user'} = $user_full;
                # Pass password
                if (!$in{'webpass_def'}) {
                        $user->{'pass'} = $in{'webpass'};
                        $user->{'pass'} || &error($text{'user_epasswebnotset'});
                        }

                &modify_webserver_user($user, \%olduser, $d, \%in);
                }
        }
else {
	# Create initial user
        $user->{'user'} = lc("$in{'webuser'}"."@".$d->{'dom'});
        $user->{'extra'} = 1;
        $user->{'type'} = 'web';
        my $userclash = &check_extra_user_clash($d, $user->{'user'}, 'web');
        !$userclash || &error($userclash);
        
        # Set initial password
        $user->{'pass'} = $in{'webpass'};
        $user->{'pass'} || &error($text{'user_epasswebnotset'});

        &modify_webserver_user($user, undef, $d, \%in);
	}

# Log
&webmin_log($in{'new'} ? "create" : "modify", "user",
                &remove_userdom($user->{'user'}, $d), $user);
# Redirect
&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");
