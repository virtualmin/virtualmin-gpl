# Functions for managing extra users

# list_extra_users(&domain, user-type, [username])
# Returns a list of extra users for some domain
sub list_extra_users
{
my ($d, $t, $u) = @_;
my @rv;
my $path = "$extra_users_dir/$d->{'id'}/$t";
return @rv if (!-d $path);
opendir(DIR, $path);
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(.*)\.user$/) {
		my %user;
		&read_file_cached("$path/$f", \%user);
		push(@rv, \%user);
		}
	}
closedir(DIR);
@rv = grep { $_->{'user'} eq $u } @rv if ($u);
return @rv;
}

# check_users_clash(&domain, username, type)
# Check for a username clash with all Unix
# users and given type of extra users
sub check_users_clash
{
my ($d, $u, $t) = @_;
my @rv;
# Check for clash with Unix users first
my (@userclash) = grep { $_->{'user'} eq $u }
        &list_domain_users($d, 0, 0, 1, 1);
# Check for clash with extra users if type is given
if ($t && !@userclash) {
        @userclash = &list_extra_users($d, $t, $u);
        }
return @userclash;
}

# list_extra_db_users(&domain, [username])
# Returns a list of extra users for some domain with database list
sub list_extra_db_users
{
my ($d, $u) = @_;
my @dbusers = &list_extra_users($d, 'db', $u);
foreach my $dbuser (@dbusers) {
        my (@dbt) = grep { /^db_/ } keys %{$dbuser};
        my @dbs;
        foreach my $dbt (@dbt) {
                my $type = $dbt;
                $type =~ s/^db_//;
                foreach my $db (split(/\s+/, $dbuser->{$dbt})) {
                        push(@dbs, { 'type' => $type,
                                     'desc' => $text{"databases_$type"},
                                     'name' => $db });
                        }
                delete($dbuser->{$dbt});
                }
        $dbuser->{'dbs'} = \@dbs;
        }
return @dbusers;
}

# list_extra_web_users(&domain, [username])
# Return a list of extra web users for some domain
sub list_extra_web_users
{
my ($d, $u) = @_;
my @rv = &list_extra_users($d, 'web', $u);
return @rv;
}

# delete_extra_user(&domain, &user)
# Remove an extra user account
sub delete_extra_user
{
my ($d, $user) = @_;
unlink(&extra_user_filename($user, $d));
}

# update_extra_user(&domain, &user, [&olduser])
# Update an extra user
sub update_extra_user
{
my ($d, $user, $olduser) = @_;
my $path = "$extra_users_dir/$d->{'id'}/$user->{'type'}";
&make_dir($path, 0700, 1) if (!-d $path);
if ($olduser->{'user'} && $user->{'user'} &&
    $olduser->{'user'} ne $user->{'user'}) {
        unlink(&extra_user_filename($olduser, $d));
	}
&write_file(&extra_user_filename($user, $d), $user);
}

# extra_user_filename(&user, &domain)
# Returns the path to a file for some extra
# user of some type in some domain
sub extra_user_filename
{
my ($user, $d) = @_;
return "$extra_users_dir/$d->{'id'}/$user->{'type'}/$user->{'user'}.user";
}

# suppressible_extra_users_types()
# Returns a list of all extra user types
# that cannot coexist with Unix users
sub suppressible_extra_users_types
{
return ('db', 'web');
}

# suppress_extra_user(&unix-user, &domain)
# Remove records of extra user that
# cannot coexist with Unix user
sub suppress_extra_user
{
my ($unix_user, $d) = @_;
foreach (&suppressible_extra_users_types()) {
	my @extra_user = &list_extra_users($d, $_, $unix_user->{'user'});
	&delete_extra_user($d, $extra_user[0]) if ($extra_user[0]);
        }
}

1;
