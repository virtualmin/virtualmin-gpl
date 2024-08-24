# Functions for managing extra users

# list_extra_users(&domain, user-type)
# Returns a list of extra users for some domain
sub list_extra_users
{
my ($d, $t) = @_;
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
return @rv;
}

# get_extra_user(&domain, user-type, username)
# Returns a single extra user
sub get_extra_user
{
my ($d, $t, $u) = @_;
my $extra_user_file = "$extra_users_dir/$d->{'id'}/$t/$u.user";
my %user;
&read_file_cached($extra_user_file, \%user)
	if (-r $extra_user_file);
return keys %user ? \%user : undef;
}

# check_extra_user_clash(&domain, username, type)
# Check for a username clash with all Unix
# users and given type of extra user
sub check_extra_user_clash
{
my ($d, $u, $t) = @_;
my ($userclash, @rv);

# Check for clash with extra users if type is given
if ($t) {
        $userclash = &get_extra_user($d, $t, $u);
        }
# Check for clash with any existing database users
if (!$userclash && $t eq 'db') {
	$userclash = &check_any_database_user_clash($d, $u);
	# If user under the same domain, we can re-import it
	if ($userclash &&
	    $u ne &remove_userdom($u, $d)) {
		$userclash = undef
		}
	}
# Check for clash with Unix users first
if (!$userclash) {
	($userclash) = grep { $_->{'user'} eq $u }
		&list_domain_users($d, 0, 0, 1, 1);
	}
return $userclash ?
	(ref($userclash) ? &text("user_e${t}clash", &html_escape($u)) : $userclash) :
	undef;
}

# check_any_database_user_clash(&domain, database-username)
# Check for a username clash with any database user
sub check_any_database_user_clash
{
my ($d, $dbusername) = @_;
foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($d))) {
	my $cfunc = "check_".$dt."_user_clash";
	next if (!defined(&$cfunc));
	my $ufunc = $dt."_username";
	if (&$cfunc($d, &$ufunc($dbusername))) {
		return &text("user_edbclash_$dt", &html_escape($dbusername));
		}
	}
}

# list_extra_db_users(&domain, [&user])
# Returns a list of extra users for some domain with database list
sub list_extra_db_users
{
my ($d, $u) = @_;
my @dbusers = $u ? (&get_extra_user($d, 'db', $u)) : &list_extra_users($d, 'db');
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

# get_extra_db_user(&domain, username)
# Returns a single extra database user
sub get_extra_db_user
{
my ($d, $u) = @_;
my ($extra_db_user) = grep { $_->{'user'} eq $u }
	&list_extra_db_users($d, $u);
return $extra_db_user;
}

# list_extra_web_users(&domain)
# Return a list of extra web users for some domain
sub list_extra_web_users
{
my ($d) = @_;
return &list_extra_users($d, 'web');
}

# get_extra_web_user(&domain, username)
# Returns a single extra web user
sub get_extra_web_user
{
my ($d, $u) = @_;
return &get_extra_user($d, 'web', $u);
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
my $f = &extra_user_filename($user, $d);
lock_file($f);
&write_file($f, &extra_user_object($user, $d));
&unlock_file($f);
}

# extra_user_object(&user)
# Returns a hash refence ready for
# writing to an extra user file
sub extra_user_object
{
my ($user, $d) = @_;
my %user = %{$user};
%user = map { $_, $user{$_} }
	grep { /^(user|pass|extra|type)$|^(pass_)|(_pass)$/ } keys %user;
$user{'pass'} = $user->{'plainpass'} if ($user->{'plainpass'});
if ($d->{'hashpass'} && $user->{'pass'} && $user->{'type'} eq 'db') {
	my $hashes = &generate_password_hashes($user, $user->{'pass'}, $d);
	$user{'mysql_pass'} = $hashes->{'mysql'};
	}
delete($user{'mysql_pass'}) if (!$d->{'hashpass'});
delete($user{'pass'}) if ($d->{'hashpass'});
if (@{$user->{'dbs'}}) {
	foreach my $db (@{$user->{'dbs'}}) {
		$user{'db_'.$db->{'type'}} .=
			$user{'db_'.$db->{'type'}} ?
				" $db->{'name'}" : $db->{'name'};
		}
	}
return \%user;
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

# merge_extra_user(&unix-user, &domain)
# Remove records of extra user that
# cannot coexist with Unix user
sub merge_extra_user
{
my ($unix_user, $d) = @_;
foreach (&suppressible_extra_users_types()) {
	my $extra_user = &get_extra_user($d, $_, $unix_user->{'user'});
	&delete_extra_user($d, $extra_user) if ($extra_user);
        }
}

# get_user_shell(&user)
# Returns the actual shell for the user either jailed
# if the user is jailed or the default shell
sub get_user_shell
{
my ($user) = @_;
my $shell = $user->{'shell'};
if ($user->{'jailed'} && $user->{'jailed'}->{'shell'}) {
	$shell = $user->{'jailed'}->{'shell'};
	}
return $shell;
}

# list_users_from(passwd-file, [shadow-file])
# Returns a list of users from the passed passwd file, with
# additional fields from the shadow file if given
sub list_users_from
{
my ($passwd_file, $shadow_file) = @_;
my (@rv, %idx);
my $clean = sub {
	my ($val) = @_;
	return ($val < 0 ? "" : $val);
	};

# Read "passwd" file
open(my $PASSWD, '<', $passwd_file) or return;
my $line_num = 0;
while (my $line = <$PASSWD>) {
	chomp($line);
	next if ($line =~ /^[#\+\-]/ || $line !~ /\S/);
	my @fields = split(/:/, $line, -1);
	my $entry = {
		'user' => $fields[0],
		'pass' => $fields[1],
		'uid' => $fields[2],
		'gid' => $fields[3],
		'real' => $fields[4],
		'home' => $fields[5],
		'shell' => $fields[6],
		'line' => $line_num,
		'num'  => scalar(@rv),
		};
	push(@rv, $entry);
	$idx{$fields[0]} = $entry;
	$line_num++;
	}
close($PASSWD);

# Read "shadow" file (if given)
if (open(my $SHADOW, '<', $shadow_file)) {
	my $line_num = 0;
	while (my $line = <$SHADOW>) {
		chomp($line);
		next if ($line =~ /^[#\+\-]/ || $line !~ /\S/);
		my @fields = split(/:/, $line, -1);
		if (my $p = $idx{$fields[0]}) {
			$p->{'pass'}     = $fields[1];
			$p->{'change'}   = $clean->($fields[2]);
			$p->{'min'}      = $clean->($fields[3]);
			$p->{'max'}      = $clean->($fields[4]);
			$p->{'warn'}     = $clean->($fields[5]);
			$p->{'inactive'} = $clean->($fields[6]);
			$p->{'expire'}   = $clean->($fields[7]);
			$p->{'sline'}    = $line_num;
			}
		$line_num++;
		}
	close($SHADOW);

	# Remove entries not in shadow
	@rv = grep { defined $_->{'sline'} } @rv;
	}

# Update 'num' field
$rv[$_]->{'num'} = $_ for (0 .. $#rv);
return @rv;
}

1;
