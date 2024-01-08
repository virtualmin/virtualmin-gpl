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

1;
