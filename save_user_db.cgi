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
        my $olduser_name = $in{'olduser'};
        my @dbuser = &list_extra_db_users($d, $olduser_name);
        $user = $dbuser[0];
        $user || &error(&text('user_edoesntexist', &html_escape($olduser_name)));
        my %olduser = %{$user};
        # If renaming user, check if new name is not already used
        if ($olduser_name ne $full_dbuser) {
                my ($user_check) = grep { $_->{'user'} eq $full_dbuser }
			&check_users_clash($d, $full_dbuser, 'db');
                !$user_check || &error(&text('user_ealreadyexist', &html_escape($full_dbuser)));
                }

        if ($in{'delete'}) {
                # Delete database user
                my ($err, $dts) = &delete_databases_user($d, $olduser_name);
                &error($err) if ($err);
                # Delete extra database user
                &delete_extra_user($d, $user);
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
                        $user->{'db_'.$type} = undef
                        	if (!$dbreset{$type}++);
                        $user->{'db_'.$type} .=
                                $user->{'db_'.$type} ? " $name" : $name;
                        }

                # Update database user and databases
                $user->{'dbs'} = \@dbs;
                &modify_database_user($user, \%olduser, $d);

                delete($user->{'dbs'});
                &update_extra_user($d, $user, \%olduser);
                }
        }
else {
        # Create initial user
        $user->{'user'} = $full_dbuser;
        $user->{'extra'} = 1;
        $user->{'type'} = 'db';
        my @dbusers = &list_domain_users($d, 1, 1, 1, 0, 1);
	my @userclash = &check_users_clash($d, $user->{'user'}, 'db');
        !@userclash || &error(&text('user_ealreadyexist', &html_escape($user->{'user'})));
        
        # Set initial password
        $user->{'pass'} = $in{'dbpass'};
        $user->{'pass'} || &error($text{'user_epassdbnotset'});

        # Databases to allow
        my @dbs;
        foreach my $db (split(/\r?\n/, $in{'dbs'})) {
                my ($type, $name) = split(/_/, $db, 2);
                push(@dbs, { 'type' => $type,
                             'name' => $name });
                $user->{'db_'.$type} .=
                        $user->{'db_'.$type} ? " $name" : $name;
                }
        $user->{'dbs'} = \@dbs;

        # Create database user
        my $err = &create_databases_user($d, $user);
        &error($err) if ($err);
        
        # Add extra database user
        delete($user->{'dbs'});
        &update_extra_user($d, $user);
        }

# Log
&webmin_log($in{'new'} ? "create" : "modify", "user",
                &remove_userdom($user->{'user'}, $d), $user);
# Redirect
&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");
