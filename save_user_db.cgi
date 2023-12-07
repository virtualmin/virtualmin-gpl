#!/usr/local/bin/perl
# save_user_db.cgi
# Create, update or delete database
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

# User to edit or delete
my $full_dbuser = lc("$in{'dbuser'}"."@".$d->{'dom'});
if (!$in{'new'}) {
        my @dbusers = &list_domain_users($d, 1, 1, 1, 0);
        my $olduser_name = $in{'olduser'};
        ($user) = grep { $_->{'user'} eq $olduser_name } @dbusers;
        $user || &error(&text('user_edoesntexist', &html_escape($olduser_name)));
        my %olduser = %{$user};
        # If renaming user, check if new name is not already used
        if ($olduser_name ne $full_dbuser) {
                my ($user_check) = grep { $_->{'user'} eq $full_dbuser } @dbusers;
                !$user_check || &error(&text('user_ealreadyexist', &html_escape($full_dbuser)));
                }

        if ($in{'delete'}) {
                # Delete database user
                my ($err, $dts) = &delete_databases_user($d, $olduser_name);
                &error($err) if ($err);
                # Delete user from domain config
                foreach my $dt (@$dts) {
                        &update_domain($d, "${dt}_users", $olduser_name);
                        }
	        }
        else {
                # Update user
                $user->{'user'} = $full_dbuser;
                # Pass password
                if (!$in{'dbpass_def'}) {
                        $user->{'pass'} = $in{'dbpass'};
                        $user->{'pass'} || &error($text{'user_epassdbnotset'});
                        }
                $user->{'plainpass'} = $user->{'pass'};
                
                # Submitted database list changed
                my @dbs;
                foreach my $db (split(/\r?\n/, $in{'dbs'})) {
                        my ($type, $name) = split(/_/, $db, 2);
                        push(@dbs, { 'type' => $type,
                                'name' => $name });
                }
                $user->{'dbs'} = \@dbs;
                &update_domain($d, "$olduser{'type'}_users", $olduser_name);
                &update_domain($d, "$user->{'type'}_users",
                        $user->{'user'},
                        { pass => $user->{'pass'},
                          dbs => $user->{'dbs'} });
                &modify_database_user($user, \%olduser, $d);
                }
        }
else {
	# Create initial user
        $user = &create_initial_user($d);
        $user->{'user'} = $full_dbuser;
        my @dbusers = &list_domain_users($d, 1, 1, 1, 0);
        my ($user_already) = grep { $_->{'user'} eq $user->{'user'} } @dbusers;
        !$user_already || &error(&text('user_ealreadyexist', &html_escape($user->{'user'})));
        
        # Set initial password
        $user->{'pass'} = $in{'dbpass'};
        $user->{'pass'} || &error($text{'user_epassdbnotset'});

        # Databases to allow
        my @dbs;
        foreach my $db (split(/\r?\n/, $in{'dbs'})) {
                my ($type, $name) = split(/_/, $db, 2);
                push(@dbs, { 'type' => $type,
                             'name' => $name });
                }
        $user->{'dbs'} = \@dbs;

        # Create database user
        my ($err, $dts) = &create_databases_user($d, $user);
        &error($err) if ($err);
        # Add user to domain config
        foreach my $dt (@$dts) {
                &update_domain($d, "${dt}_users",
                        $user->{'user'},
                        { pass => $user->{'pass'},
                          dbs => $user->{'dbs'} });
                }
	}

# Save domain
&lock_domain($d);
&save_domain($d);
unlock_domain($d);

# Log
&webmin_log($in{'new'} ? "create" : "modify", "user",
                &remove_userdom($user->{'user'}, $d), $user);
# Redirect
&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");
