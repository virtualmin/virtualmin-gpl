#!/usr/local/bin/perl
# save_user_db.cgi
# Create, update or delete database
# user without creating a Unix user

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'user_err'});
my $d;
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'users_ecannot'});
	}
else {
	&can_edit_local() || &error($text{'users_ecannot2'});
	}
&can_edit_users() || &error($text{'users_ecannot'});

# User to edit or create
my $user;

if (!$in{'new'}) {
        # Edit user
	$user || &error("User does not exist!");
	}
if ($in{'delete'}) {
        # Delete user
	}
else {
	# Create new user
        $user = &create_initial_user($d);

        # Databases to allow
        my ($db, @dbs);
        foreach $db (split(/\r?\n/, $in{'dbs'})) {
                my ($type, $name) = split(/_/, $db, 2);
                push(@dbs, { 'type' => $type,
                             'name' => $name });
                }
        $user->{'dbs'} = \@dbs;
        $user->{'user'} = "$in{'dbuser'}"."@".$d->{'dom'};

        #
	foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($d))) {
			local $main::error_must_die = 1;
			my @dbs = map { $_->{'name'} }
					 grep { $_->{'type'} eq $dt } @{$user->{'dbs'}};
			if (@dbs && &indexof($dt, &list_database_plugins()) < 0) {
				# Create in core database
				my $crfunc = "create_${dt}_database_user";
				&$crfunc($d, \@dbs, $user->{'user'}, $in{'dbpass'});
				}
			elsif (@dbs && &indexof($dt, &list_database_plugins()) >= 0) {
				# Create in plugin database
				&plugin_call($dt, "database_create_user",
					     $d, \@dbs, $user->{'user'},
					     $in{'dbpass'});
				}
		if ($@) {
			&error($text{'restore_eusersql'});
			}
		}

	}

# &set_all_null_print();
# &run_post_actions();

# Domain lock

# Log
&webmin_log($in{'new'} ? "create" : "modify", "user",
                &remove_userdom($user->{'user'}, $d), $user);
# Redirect
&redirect($d ? "list_users.cgi?dom=$in{'dom'}" : "index.cgi");

