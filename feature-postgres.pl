sub require_postgres
{
return if ($require_postgres++);
$postgresql::use_global_login = 1;
&foreign_require("postgresql");
%qconfig = &foreign_config("postgresql");
}

sub check_module_postgres
{
return &foreign_available("postgresql");
}

# check_depends_postgres(&dom)
# Ensure that a sub-server has a parent server with MySQL enabled
sub check_depends_postgres
{
return undef if (!$_[0]->{'parent'});
local $parent = &get_domain($_[0]->{'parent'});
return $text{'setup_edeppostgres'} if (!$parent->{'postgres'});
return undef;
}

# check_anti_depends_postgres(&dom)
# Ensure that a parent server without MySQL does not have any children with it
sub check_anti_depends_postgres
{
if (!$_[0]->{'postgres'}) {
	local @subs = &get_domain_by("parent", $_[0]->{'id'});
	foreach my $s (@subs) {
		return $text{'setup_edeppostgressub'} if ($s->{'postgres'});
		}
	}
return undef;
}

# obtain_lock_postgres(&domain)
# Lock the PostgreSQL config for a domain
sub obtain_lock_postgres
{
my ($d) = @_;
return if (!$config{'postgres'});
&obtain_lock_anything($d);
}

# release_lock_postgres(&domain)
# Un-lock the PostgreSQL config file for some domain
sub release_lock_postgres
{
local ($d) = @_;
return if (!$config{'postgres'});
&release_lock_anything($d);
}

# check_warnings_postgres(&dom, &old-domain)
# Return warning if a PosgreSQL database or user with a clashing name exists.
# This can be overridden to allow a takeover of the DB.
sub check_warnings_postgres
{
local ($d, $oldd) = @_;
$d->{'postgres'} && (!$oldd || !$oldd->{'postgres'}) || return undef;
if (!$d->{'provision_postgres'}) {
	# DB clash
	&require_postgres();
	local @dblist = &list_dom_postgres_databases($d);
	return &text('setup_epostgresdb', $d->{'db'})
		if (&indexof($d->{'db'}, @dblist) >= 0);

	# User clash
	if (!$d->{'parent'}) {
		return &text('setup_epostgresuser', &postgres_user($d))
			if (&postgres_user_exists($d));
		}
	}
return undef;
}

# postgres_user_exists(&domain, [user])
# Returns 1 if some user exists in PostgreSQL
sub postgres_user_exists
{
my ($d, $user) = @_;
&require_postgres();
$user ||= &postgres_user($d);
my $s = &execute_dom_psql($d, undef,
		"select * from pg_shadow where usename = ?", $user);
return $s->{'data'}->[0] ? 1 : 0;
}

# check_postgres_clash(&domain, [field])
# Returns 1 if some PostgreSQL user or database is used by another domain
sub check_postgres_clash
{
local ($d, $field) = @_;
local @doms = grep { $_->{'postgres'} && $_->{'id'} ne $d->{'id'} }
		   &list_domains();

# Check for DB clash
if (!$field || $field eq 'db') {
	foreach my $od (@doms) {
		foreach my $db (split(/\s+/, $od->{'db_postgres'})) {
			if ($db eq $d->{'db'}) {
				return &text('setup_epostgresdbdom',
					$d->{'db'}, &show_domain_name($od));
				}
			}
		}
	}

# Check for user clash
if (!$d->{'parent'} && (!$field || $field eq 'user')) {
	foreach my $od (@doms) {
		if (!$od->{'parent'} && &postgres_user($d) eq &postgres_user($od)) {
			return &text('setup_epostgresuserdom',
				     &postgres_user($d),
				     &show_domain_name($od));
			}
		}
	}

return undef;
}

# setup_postgres(&domain, [no-dbs])
# Create a new PostgreSQL database and user
sub setup_postgres
{
local ($d, $nodb) = @_;
local $tmpl = &get_template($d->{'template'});
if (!$d->{'postgres_module'}) {
        # Use the default module for this system
        $d->{'postgres_module'} = &get_default_postgres_module();
	}
&require_postgres();
local $user = $d->{'postgres_user'} = &postgres_user($d);

if (!$d->{'parent'}) {
	if ($d->{'postgres_module'} ne 'postgresql') {
		my $host = &get_database_host_postgres($d);
		&$first_print(&text('setup_postgresuser2', $host));
		}
	else {
		&$first_print($text{'setup_postgresuser'});
		}
	local $pass = &postgres_pass($d);
	if (&postgres_user_exists($d, $user)) {
		&execute_dom_psql($d, undef,
			"alter user ".&postgres_uquote($user).
			" with password $pass");
		}
	else {
		local $popts = &get_postgresql_user_flags();
		&execute_dom_psql($d, undef,
			"create user ".&postgres_uquote($user).
			" with password $pass $popts");
		}
	&$second_print($text{'setup_done'});
	}
if (!$nodb && $tmpl->{'mysql_mkdb'} && !$d->{'no_mysql_db'}) {
	# Create the initial DB
	local $opts = &default_postgres_creation_opts($d);
	&create_postgres_database($d, $d->{'db'}, $opts);
	}
else {
	# No DBs can exist
	$d->{'db_postgres'} = "";
	}

# Save the initial password
if ($tmpl->{'postgres_nopass'}) {
	&set_postgres_pass(&postgres_pass($d, 1));
	}
return 1;
}

# set_postgres_pass(&domain, [password])
# Updates a domain object to use the specified login for PostgreSQL. Does not
# actually change the database - that must be done by modify_postgres.
sub set_postgres_pass
{
local ($d, $pass) = @_;
if (defined($pass)) {
	$d->{'postgres_pass'} = $pass;
	}
else {
	delete($d->{'postgres_pass'});
	}
}

# postgres_pass(&domain, [neverquote])
sub postgres_pass
{
my ($d, $noquote) = @_;
if ($d->{'parent'}) {
	# Password comes from parent domain
	my $parent = &get_domain($d->{'parent'});
	return &postgres_pass($parent);
	}
&require_postgres();
local $pass = defined($d->{'postgres_pass'}) ? $d->{'postgres_pass'}
					     : $d->{'pass'};
return !$noquote && &get_dom_remote_postgres_version($d) >= 7 ?
	&postgres_quote($pass) : $pass;
}

# postgres_quote(string)
# Returns a string in '' quotes, with escaping if needed
sub postgres_quote
{
local ($str) = @_;
$str =~ s/'/''/g;
return "'$str'";
}

# postgres_uquote(string)
# Returns a string in "" quotes, with escaping if needed
sub postgres_uquote
{
local ($str) = @_;
if ($str =~ /^[A-Za-z0-9\.\_\-]+$/) {
	return "\"".$str."\"";
	}
else {
	return "\"".quotemeta($str)."\"";
	}
}

# modify_postgres(&domain, &olddomain)
# Change the PostgreSQL user's password if needed
sub modify_postgres
{
my ($d, $oldd) = @_;
&require_postgres();
my $ver = &get_dom_remote_postgres_version($d);
my $tmpl = &get_template($d->{'template'});
my $changeduser = $d->{'user'} ne $oldd->{'user'} &&
		     !$tmpl->{'mysql_nouser'} ? 1 : 0;
my $user = &postgres_user($d, $changeduser);
my $olduser = &postgres_user($oldd);

my $pass = &postgres_pass($d);
my $oldpass = &postgres_pass($oldd);
if ($pass ne $oldpass && !$d->{'parent'} &&
    (!$tmpl->{'mysql_nopass'} || $d->{'postgres_pass'})) {
	# Change PostgreSQL password ..
	&$first_print($text{'save_postgrespass'});
	if (&postgres_user_exists($oldd)) {
		&execute_dom_psql($d, undef,
			"alter user ".&postgres_uquote($olduser).
			" with password $pass");
		&$second_print($text{'setup_done'});

		# Update all installed scripts database password which are
		# using PostgreSQL
		&update_scripts_creds(
			$d, $oldd, 'dbpass', &postgres_pass($d), 'psql');
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
if (!$d->{'parent'} && $oldd->{'parent'}) {
	# Server has been converted to a parent .. need to create user, and
	# change database ownerships
	delete($d->{'postgres_user'});
	&$first_print($text{'setup_postgresuser'});
	my $pass = &postgres_pass($d);
	my $popts = &get_postgresql_user_flags();
	&execute_dom_psql($d, undef,
		"create user ".&postgres_uquote($user).
		" with password $pass $popts");
	if ($ver >= 8.0) {
		foreach my $db (&domain_databases($d, [ "postgres" ])) {
			&execute_dom_psql($d, $db,
			    "reassign owned by ".&postgres_uquote($olduser).
			    " to ".&postgres_uquote($user));
			&execute_dom_psql($d, undef,
			  "alter database ".&postgres_uquote($db->{'name'}).
			  " owner to ".&postgres_uquote($user));
			}
		}
	&$second_print($text{'setup_done'});
	}
elsif ($d->{'parent'} && !$oldd->{'parent'}) {
	# Server has changed from parent to sub-server .. need to remove the
	# old user and update all DB permissions
	&$first_print($text{'save_postgresuser'});
	if ($ver >= 8.0) {
		foreach my $db (&domain_databases($d, [ "postgres" ])) {
			&execute_dom_psql($d, $db,
			    "reassign owned by ".&postgres_uquote($olduser).
			    " to ".&postgres_uquote($user));
			&execute_dom_psql($d, undef,
			    "alter database ".&postgres_uquote($db->{'name'}).
			    " owner to ".&postgres_uquote($user));
			}
		}
	if (&postgres_user_exists($oldd)) {
		&execute_dom_psql($d, undef,
			"drop user ".&postgres_uquote($olduser));
		}
	&$second_print($text{'setup_done'});
	}
elsif ($user ne $olduser && !$d->{'parent'}) {
	# Rename PostgreSQL user ..
	&$first_print($text{'save_postgresuser'});
	if (&postgres_user_exists($oldd)) {
		if ($ver >= 7.4) {
			# Can use proper rename command
			&execute_dom_psql($d, undef,
				"alter user ".&postgres_uquote($olduser).
				" rename to ".&postgres_uquote($user));
			&execute_dom_psql($d, undef,
				"alter user ".&postgres_uquote($user).
				" with password $pass");
			$d->{'postgres_user'} = $user;
			&$second_print($text{'setup_done'});

			# Update all installed scripts database username which
			# are using PostgreSQL
			&update_scripts_creds(
				$d, $oldd, 'dbuser', $user, 'psql');
			}
		else {
			# Cannot
			&$second_print($text{'save_norename'});
			}
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
elsif ($user ne $olduser && $d->{'parent'}) {
	# Change owner of PostgreSQL databases
	&$first_print($text{'save_postgresuser2'});
	my $user = &postgres_user($d);
	if ($ver >= 8.0) {
		foreach my $db (&domain_databases($d, [ "mysql" ])) {
			&execute_dom_psql($d, undef,
			    "alter database ".&postgres_uquote($db->{'name'}).
			    " owner to ".&postgres_uquote($user));
			}
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgresuser2'});
		}
	}
}

# delete_postgres(&domain, [preserve-remote])
# Delete the PostgreSQL database and user
sub delete_postgres
{
local ($d, $preserve) = @_;
&require_postgres();
my @dblist = &unique(split(/\s+/, $d->{'db_postgres'}));
my $pghost = &get_database_host_postgres($d);

# If PostgreSQL is hosted remotely, don't delete the DB on the assumption that
# other servers sharing the DB will still be using it
if ($preserve && &remote_postgres($d)) {
	&$first_print(&text('delete_postgresdb', join(" ", @dblist)));
	&$second_print(&text('delete_mysqlpreserve', $pghost));
	return 1;
	}

# Delete all databases
&delete_postgres_database($d, @dblist) if (@dblist);
local $user = &postgres_user($d);

if (!$d->{'parent'}) {
	# Delete the user
	&$first_print($text{'delete_postgresuser'});
	if (&postgres_user_exists($d)) {
		my $ver = &get_dom_remote_postgres_version($d);
		if ($ver >= 8.0) {
			my ($sameunix, $login) = &get_dom_postgres_creds($d);
			my $s = &execute_dom_psql($d, undef,
				"select datname from pg_database ".
				"join pg_authid ".
				"on pg_database.datdba = pg_authid.oid ".
				"where rolname = '$user'");
			foreach my $db (map { $_->[0] } @{$s->{'data'}}) {
				&execute_dom_psql(
					$d,
					$db,
					"reassign owned by ".
					  &postgres_uquote($user).
					  " to ".
					  $login);
				&execute_dom_psql(
					$d,
					undef,
					"alter database $db owner to ".
					  $login);
				}
			};
		&execute_dom_psql($d, undef,
			"drop user ".&postgres_uquote($user));
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
return 1;
}

# clone_postgres(&domain, &old-domain)
# Copy all databases and their contents to a new domain
sub clone_postgres
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_postgres'});

# Re-create each DB with a new name
local %dbmap;
foreach my $db (&domain_databases($oldd, [ 'postgres' ])) {
	local $newname = $db->{'name'};
	local $newprefix = &fix_database_name($d->{'prefix'}, 'postgres');
	local $oldprefix = &fix_database_name($oldd->{'prefix'}, 'postgres');
	if ($newname eq $oldd->{'db'}) {
		$newname = $d->{'db'};
		}
	elsif ($newname !~ s/\Q$oldprefix\E/$newprefix/) {
		&$second_print(&text('clone_postgresprefix', $newname,
				     $oldprefix, $newprefix));
		next;
		}
	if (&check_postgres_database_clash($d, $newname)) {
		&$second_print(&text('clone_postgresclash', $newname));
		next;
		}
	&push_all_print();
	&set_all_null_print();
	local $opts = &get_postgres_creation_opts($oldd, $db->{'name'});
	local $ok = &create_postgres_database($d, $newname, $opts);
	&pop_all_print();
	if (!$ok) {
		&$second_print(&text('clone_postgrescreate', $newname));
		}
	else {
		$dbmap{$newname} = $db->{'name'};
		}
	}
&$second_print(&text('clone_postgresdone', scalar(keys %dbmap)));

# Copy across contents
if (%dbmap) {
	&require_postgres();
	&$first_print($text{'clone_postgrescopy'});
	my $mod = &require_dom_postgres($d);
	foreach my $db (&domain_databases($d, [ 'postgres' ])) {
		local $oldname = $dbmap{$db->{'name'}};
		local $temp = &transname();
		local ($sameunix, $login) = &get_dom_postgres_creds($d);
		if ($sameunix && (my @uinfo = getpwnam($login))) {
			# Create empty file postgres user can write to
			&open_tempfile(EMPTY, ">$temp", 0, 1);
			&close_tempfile(EMPTY);
			&set_ownership_permissions($uinfo[2], $uinfo[3],
						   undef, $temp);
			}
		local $err = &foreign_call($mod, "backup_database",
					   $oldname, $temp, 'c', undef);
		if ($err) {
			&$second_print(&text('clone_postgresbackup',
					     $oldname, $err));
			next;
			}
		$err = &foreign_call($mod, "restore_database",
				     $db->{'name'}, $temp, 0, 0);
		&unlink_file($temp);
		if ($err) {
			&$second_print(&text('clone_postgresrestore',
					     $db->{'name'}, $err));
			next;
			}
		}
	&$second_print($text{'setup_done'});
	}
}

# validate_postgres(&domain)
# Make sure all PostgreSQL databases exist
sub validate_postgres
{
local ($d) = @_;
&require_postgres();
local %got = map { $_, 1 } &list_dom_postgres_databases($d);
foreach my $db (&domain_databases($d, [ "postgres" ])) {
	$got{$db->{'name'}} || return &text('validate_epostgres',$db->{'name'});
	}
if (!&postgres_user_exists($d)) {
	return &text('validate_epostgresuser', &postgres_user($d));
	}
return undef;
}

# disable_postgres(&domain)
# Invalidate the domain's PostgreSQL user
sub disable_postgres
{
my ($d) = @_;
&$first_print($text{'disable_postgres'});
my $user = &postgres_user($d);
if ($d->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	return 0;
	}
elsif (&postgres_user_exists($d)) {
	&require_postgres();
	my $date = localtime(0);
	&execute_dom_psql($d, undef,
		"alter user ".&postgres_uquote($user).
		" valid until ".&postgres_quote($date));
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'save_nopostgres'});
	return 0;
	}
}

# enable_postgres(&domain)
# Validate the domain's PostgreSQL user
sub enable_postgres
{
my ($d) = @_;
&$first_print($text{'enable_postgres'});
my $user = &postgres_user($d);
if ($d->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	return 0;
	}
elsif (&postgres_user_exists($d)) {
	&require_postgres();
	&execute_dom_psql($d, undef,
		"alter user ".&postgres_uquote($user).
		" valid until ".&postgres_quote("Jan 1 2038"));
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'save_nopostgres'});
	return 0;
	}
}

# backup_postgres(&domain, file)
# Dumps this domain's postgreSQL database to a backup file
sub backup_postgres
{
my ($d, $file) = @_;
&require_postgres();
my $mod = &require_dom_postgres($d);

# Find all the domains's databases
my @dbs = split(/\s+/, $d->{'db_postgres'});

# Filter out any excluded DBs
my @exclude = &get_backup_db_excludes($d);
my %exclude = map { $_, 1 } @exclude;
@dbs = grep { !$exclude{$_} } @dbs;

# Create base backup file with meta-information
my $host = &get_database_host_postgres($d);
my %info = ( 'remote' => $host );
&write_as_domain_user($d, sub { &write_file($file, \%info) });

# Back them all up
my $ok = 1;
foreach my $db (@dbs) {
	&$first_print(&text('backup_postgresdump', $db));
	my $dbfile = $file."_".$db;
	my $destfile = $dbfile;
	my ($sameunix, $login) = &get_dom_postgres_creds($d);
	if ($sameunix && (my @uinfo = getpwnam($login))) {
		# For a backup done as the postgres user, create an empty file
		# owned by him first
		$destfile = &transname();
		&open_tempfile(EMPTY, ">$destfile", 0, 1);
		&close_tempfile(EMPTY);
		&set_ownership_permissions($uinfo[2], $uinfo[3],
					   undef, $destfile);
		}

	# Limit tables to those that aren't excluded
	my %texclude = map { $_, 1 }
			 map { (split(/\./, $_))[1] }
			   grep { /^\Q$db\E\./ || /^\*\./ } @exclude;
	my $tables;
	if (%texclude) {
		$tables = [ grep { !$texclude{$_} }
				 &list_postgres_tables($d, $db) ];
		}

	my $err = &foreign_call($mod, "backup_database", $db,
				$destfile, 'c', $tables);
	if ($err) {
		&$second_print(&text('backup_postgresdumpfailed',
				     "<pre>$err</pre>"));
		$ok = 0;
		}
	else {
		if ($destfile ne $dbfile) {
			&copy_write_as_domain_user($d, $destfile, $dbfile);
			&unlink_file($destfile);
			}
		&$second_print($text{'setup_done'});
		}
	}
return $ok;
}

# restore_postgres(&domain, file,  &opts, &allopts, homeformat, &oldd, asowner)
# Restores this domain's postgresql database from a backup file, and re-creates
# the postgresql user.
sub restore_postgres
{
my ($d, $file, $opts, $allopts, $homefmt, $oldd, $asd) = @_;
my %info;
&read_file($file, \%info);
&require_postgres();

# If in replication mode, AND the remote PostgreSQL system is the same on both
# systems, do nothing
my $host = &get_database_host_postgres($d);
if ($allopts->{'repl'} && $host ne "localhost" && $info{'remote'} &&
    $host eq $info{'remote'}) {
	&$first_print($text{'restore_postgresdummy'});
	&$second_print(&text('restore_postgressameremote', $info{'remote'}));
	return 1;
	}

if (!$d->{'wasmissing'}) {
	# Only delete and re-create databases if this domain was not created
	# as part of the restore process.
	&$first_print($text{'restore_postgresdrop'});
		{
		local $first_print = \&null_print;	# supress messages
		local $second_print = \&null_print;
		&require_mysql();

		# First clear out the databases
		&delete_postgres($d);

		# Now re-set up the user only
		&setup_postgres($d, 1);
		}
	&$second_print($text{'setup_done'});
	}

# Work out which databases are in backup
local ($dbfile, @dbs);
foreach $dbfile (glob($file."_*")) {
	if (-r $dbfile) {
		$dbfile =~ /\Q$file\E_(.*)$/;
		push(@dbs, [ $1, $dbfile ]);
		}
	}

# Finally, import the data
local $db;
foreach $db (@dbs) {
	my $clash = &check_postgres_database_clash($d, $db->[0]);
	if ($clash && $d->{'wasmissing'}) {
		# DB already exists, silently ignore it if not empty.
		# This can happen during a restore when PostgreSQL is on a
		# remote system.
		my @tables = &list_postgres_tables($d, $db->[0]);
		my $ver = &get_dom_remote_postgres_version($d);
		if (@tables && $ver >= 8.0) {
			# But grant access to the DB to the domain owner
			local $q = &postgres_uquote(&postgres_user($d));
			&execute_dom_psql(
				$d, undef,
				"alter database $db->[0] owner to $q");
			foreach my $t (@tables) {
				&execute_dom_psql(
					$d, $db->[0],
					"alter table $t owner to $q");
				}
			next;
			}
		}
	&$first_print(&text('restore_postgresload', $db->[0]));
	if ($clash && !$d->{'wasmissing'}) {
                # DB already exists, and this isn't a newly created domain
		&$second_print(&text('restore_postgresclash'));
		return 0;
		}
	&$indent_print();
	if (!$clash) {
		&create_postgres_database($d, $db->[0]);
		}
	&$outdent_print();
	my ($sameunix, $login) = &get_dom_postgres_creds($d);
	if ($sameunix && (my @uinfo = getpwnam($login))) {
		# Restore is running as the postgres user - make the backup
		# file owned by him, and the parent directory world-accessible
		&set_ownership_permissions($uinfo[2], $uinfo[3],
					   undef, $db->[1]);
		local $dir = $file;
		$dir =~ s/\/[^\/]+$//;
		&set_ownership_permissions(undef, undef, 0711, $dir);
		}
	my $mod = &require_dom_postgres($d);
	my $err = &foreign_call($mod, "restore_database",
		$db->[0], $db->[1], 0, 0);
	if ($err) {
		&$second_print(&text('restore_mysqlloadfailed', "<pre>$err</pre>"));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# Restoring virtual PostgreSQL users 
my @dbusers_virt = &list_extra_db_users($d);
if (@dbusers_virt) {
	&$first_print($text{'restore_postgresudummy'});
	&$indent_print();
	foreach my $dbuser_virt (@dbusers_virt) {
		&$first_print(&text('restore_mysqludummy2', $dbuser_virt->{'user'}));
		# If restored user not under the same domain already
		# exists, delete extra user record, and skip it
		if (&check_any_database_user_clash($d, $dbuser_virt->{'user'}) &&
		    $dbuser_virt->{'user'} eq &remove_userdom($dbuser_virt->{'user'}, $d)) {
			&$second_print($text{'restore_emysqluimport2'});
			&delete_extra_user($d, $dbuser_virt);
			next;
			}
		my $err = &create_databases_user($d, $dbuser_virt, 'postgres');
		if ($err) {
			&$second_print(&text('restore_emysqluimport', $err));
			}
		else {
			&$second_print($text{'setup_done'});
			}

		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

# If the restore re-created a domain, the list of databases should be synced
# to those in the backup
if ($d->{'wasmissing'}) {
	$d->{'db_postgres'} = join(" ", map { $_->[0] } @dbs);
	}

return 1;
}

# postgres_user(&domain, [always-new])
sub postgres_user
{
if ($_[0]->{'parent'}) {
	# Get from parent domain
	return &postgres_user(&get_domain($_[0]->{'parent'}), $_[1]);
	}
return defined($_[0]->{'postgres_user'}) && !$_[1] ?
	$_[0]->{'postgres_user'} : &postgres_username($_[0]->{'user'}); 
}

# set_postgres_user(&domain, newuser)
# Updates a domain object with a new PostgreSQL username
sub set_postgres_user
{
$_[0]->{'postgres_user'} = $_[1];
}

sub postgres_username
{
return $_[0];
}

# postgres_size(&domain, db, [size-only])
sub postgres_size
{
my ($d, $db, $sizeonly) = @_;
&require_postgres();
my $size;
my $count;
my @tables;
eval {
	# Make sure DBI errors don't cause a total failure
	local $main::error_must_die = 1;
	my $rv = &execute_dom_psql($d, $db, "select sum(relpages),count(relpages) from pg_class where relname not like 'pg_%'");
	$size = $rv->{'data'}->[0]->[0]*1024*2;
	$size = $rv->{'data'}->[0]->[1];
	if (!$sizeonly) {
		@tables = &list_postgres_tables($d, $db);
		}
	};
return ($size, scalar(@tables), 0, $count);
}

# check_postgres_database_clash(&domain, db)
# Returns 1 if some database name is already in use
sub check_postgres_database_clash
{
my ($d, $db) = @_;
&require_postgres();
my @dblist = &list_dom_postgres_databases($d);
return 1 if (&indexof($db, @dblist) >= 0);
}

# create_postgres_database(&domain, db, &opts)
# Create one PostgreSQL database
sub create_postgres_database
{
my ($d, $db, $opts) = @_;
&require_postgres();
&obtain_lock_postgres($d);

if (!&check_postgres_database_clash($d, $db)) {
	# Build and run creation command
	if ($d->{'postgres_module'} ne 'postgresql') {
		my $host = &get_database_host_postgres($d);
		&$first_print(&text('setup_postgresdb2', $db, $host));
		}
	else {
		&$first_print(&text('setup_postgresdb', $db));
		}
	my $user = &postgres_user($d);
	my $sql = "create database ".&postgresql::quote_table($db);
	my $withs;
	my $ver = &get_dom_remote_postgres_version($d);
	if ($ver >= 7) {
		$withs .= " owner=".&postgres_uquote($user);
		}
	if ($opts->{'encoding'}) {
		$withs .= " encoding ".&postgres_quote($opts->{'encoding'});
		}
	if ($withs) {
		$sql .= " with".$withs;
		}
	&execute_dom_psql($d, undef, $sql);
	}
else {
	&$first_print(&text('setup_postgresdbimport', $db));
	}

# Make sure nobody else can access it
eval {
	local $main::error_must_die = 1;
	&execute_dom_psql($d, undef,
		"revoke all on database ".&postgres_uquote($db).
		" from public");
	};
local @dbs = split(/\s+/, $d->{'db_postgres'});
push(@dbs, $db);
$d->{'db_postgres'} = join(" ", @dbs);
&release_lock_postgres($d);
&$second_print($text{'setup_done'});
return 1;
}

# grant_postgres_database(&domain, dbname)
# Alters the owner of a PostgreSQL database to some domain
sub grant_postgres_database
{
my ($d, $dbname) = @_;
&require_postgres();
my $ver = &get_dom_remote_postgres_version($d);
if ($ver >= 8.0) {
	my $user = &postgres_user($d);
	&execute_dom_psql($d, undef,
		"alter database ".&postgres_uquote($dbname).
		" owner to ".&postgres_uquote($user));
	}
}

# delete_postgres_database(&domain, dbname, ...)
# Delete one PostgreSQL database
sub delete_postgres_database
{
my ($d, @deldbs) = @_;
&require_postgres();
&obtain_lock_postgres($d);
my @dblist = &list_dom_postgres_databases($d);
&$first_print(&text('delete_postgresdb', join(", ", @deldbs)));
my @dbs = split(/\s+/, $d->{'db_postgres'});
my @missing;
foreach my $db (@deldbs) {
	if (&indexof($db, @dblist) >= 0) {
		eval {
			local $main::error_must_die = 1;
			&execute_dom_psql($d, undef,
				"drop database ".&postgresql::quote_table($db).
				" with force");
			};
		if ($@) {
			# Force command not supported, fall back to regular
			# drop with cleanup of connections
			eval {
				local $main::error_must_die = 1;
				&execute_dom_psql(
					$d, undef,
					"revoke connection on database ".
					&postgresql::quote_table($db).
					" from public");
				};
			&execute_dom_psql($d, undef,
				"drop database ".&postgresql::quote_table($db));
			}
		}
	else {
		push(@missing, $db);
		}
	@dbs = grep { $_ ne $db } @dbs;
	}
$d->{'db_postgres'} = join(" ", @dbs);
&release_lock_postgres($d);
if (@missing) {
	&$second_print(&text('delete_mysqlmissing', join(", ", @missing)));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# revoke_postgres_database(&domain, dbname)
# Takes away a domain's access to a PostgreSQL database, by setting the owner
# back to postgres
sub revoke_postgres_database
{
local ($d, $dbname) = @_;
&require_postgres();
my $ver = &get_dom_remote_postgres_version($d);
if ($ver && &postgres_user_exists($d, "postgres")) {
	&execute_dom_psql($d, undef,
		"alter database ".&postgres_uquote($dbname).
		" owner to ".&postgres_uquote("postgres"));
	}
}

# list_postgres_database_users(&domain, db)
# Returns a list of PostgreSQL users and passwords who can access some database
sub list_all_postgres_users
{
local ($d, $db) = @_;
return ( );	# XXX not possible
}

# list_all_postgres_users()
# Returns a list of all PostgreSQL users
sub list_postgres_database_users
{
local ($d, $db) = @_;
return ( );	# XXX not possible
}

# create_postgres_database_user(&domain, &dbs, username, password)
sub create_postgres_database_user
{
}

# list_postgres_tables(&domain, database)
# Returns a list of tables in the specified database
sub list_postgres_tables
{
my ($d, $db) = @_;
my $mod = &require_dom_postgres($d);
return &foreign_call($mod, "list_tables", $db);
}

# get_database_host_postgres([&domain])
# Returns the hostname of the server on which PostgreSQL is actually running
sub get_database_host_postgres
{
my ($d) = @_;
my $pgmod = &require_dom_postgres($d);
my %pgconfig = &foreign_config($pgmod);
return $pgconfig{'host'} || 'localhost';
}

# get_database_port_postgres([&domain])
# Returns the port number the server on which PostgreSQL is actually running
sub get_database_port_postgres
{
my ($d) = @_;
my $pgmod = &require_dom_postgres($d);
my %pgconfig = &foreign_config($pgmod);
return $pgconfig{'port'} || 5432;
}

# sysinfo_postgres()
# Returns the PostgreSQL version
sub sysinfo_postgres
{
&require_postgres();
local @rv;
eval {
	# Protect against DBI errors
	local $main::error_must_die = 1;
	local $ver = &postgresql::get_postgresql_version();
	@rv = ( [ $text{'sysinfo_postgresql'}, $ver ] );
	};
return @rv;
}

sub startstop_postgres
{
local ($typestatus) = @_;
&require_postgres();
return ( ) if (!&postgresql::is_postgresql_local());
local $r = defined($typestatus->{'postgresql'}) ?
                $typestatus->{'postgresql'} == 1 :
		&postgresql::is_postgresql_running();
local @links = ( { 'link' => '/postgresql/',
		   'desc' => $text{'index_pgmanage'},
		   'manage' => 1 } );
if ($r == 1) {
	return ( { 'status' => 1,
		   'name' => $text{'index_pgname'},
		   'desc' => $text{'index_pgstop'},
		   'restartdesc' => $text{'index_pgrestart'},
		   'longdesc' => $text{'index_pgstopdesc'},
		   'links' => \@links } );
	}
elsif ($r == 0) {
	return ( { 'status' => 0,
		   'name' => $text{'index_pgname'},
		   'desc' => $text{'index_pgstart'},
		   'longdesc' => $text{'index_pgstartdesc'},
		   'links' => \@links } );
	}
else {
	return ( );
	}
}

sub stop_service_postgres
{
&require_postgres();
local $rv = &postgresql::stop_postgresql();
sleep(5);
return $rv;
}

sub start_service_postgres
{
&require_postgres();
return &postgresql::start_postgresql();
}

# check_postgres_login(&domain, dbname, dbuser, dbpass)
# Tries to login to PostgreSQL with the given credentials, returning undef
# on failure
sub check_postgres_login
{
local ($d, $dbname, $dbuser, $dbpass) = @_;
&require_postgres();
my $mod = &require_dom_postgres($d);
my @defcreds = &get_dom_postgres_creds($d);
&foreign_call($mod, "set_login_pass", $defcreds[0], $dbuser, $dbpass);
eval {
	local $main::error_must_die = 1;
	&execute_dom_psql($d, $dbname, "select version()");
	};
local $err = $@;
&foreign_call($mod, "set_login_pass", @defcreds);
if ($err) {
	$err =~ s/\s+at\s+.*\sline//g;
	return $err;
	}
return undef;
}

# creation_form_postgres(&domain)
# Returns options for a new PostgreSQL database
sub creation_form_postgres
{
my ($d) = @_;
&require_postgres();
my $ver = &get_dom_remote_postgres_version($d);
if ($ver >= 7.4) {
	my $tmpl = &get_template($d->{'template'});
	my $cs = $tmpl->{'postgres_encoding'};
	$cs = "" if ($cs eq "none");
	return &ui_table_row($text{'database_encoding'},
			     &ui_select("postgres_encoding", $cs,
					[ [ undef, "&lt;$text{'default'}&gt;" ],
					  &list_postgres_encodings() ]));
	}
}

# creation_parse_postgres(&domain, &in)
# Parse the form generated by creation_form_postgres, and return a structure
# for passing to create_postgres_database
sub creation_parse_postgres
{
local ($d, $in) = @_;
local $opts = { 'encoding' => $in->{'postgres_encoding'} };
return $opts;
}

# list_postgres_encodings()
# Returns a list of available PostgreSQL encodings for new DBs, each of which
# is a 2-element hash ref containing a code and description
sub list_postgres_encodings
{
if (!scalar(@postgres_encodings_cache)) {
	@postgres_encodings_cache = ( );
	&open_readfile(ENCS, "$module_root_directory/postgres-encodings");
	while(<ENCS>) {
		s/\r|\n//g;
		local @w = split(/\t/, $_);
		if ($w[2] !~ /\Q$w[0]\E/i) {
			$w[2] .= " ($w[0])";
			}
		push(@postgres_encodings_cache, [ $w[0], $w[2] ]);
		}
	close(ENCS);
	@postgres_encodings_cache = sort { lc($a->[1]) cmp lc($b->[1]) }
					 @postgres_encodings_cache;
	}
return @postgres_encodings_cache;
}

# show_template_postgres(&tmpl)
# Outputs HTML for editing PostgreSQL related template options
sub show_template_postgres
{
local ($tmpl) = @_;
&require_postgres();

# Default encoding
print &ui_table_row(&hlink($text{'tmpl_postgres_encoding'},
			   "template_postgres_encoding"),
    &ui_select("postgres_encoding",  $tmpl->{'postgres_encoding'},
	[ $tmpl->{'default'} ? ( ) :
	    ( [ "", "&lt;$text{'tmpl_postgres_encodingdef'}&gt;" ] ),
	  [ "none", "&lt;$text{'tmpl_postgres_encodingnone'}&gt;" ],
	  &list_postgres_encodings() ]));
}

# parse_template_postgres(&tmpl)
# Updates PostgreSQL related template options from %in
sub parse_template_postgres
{
local ($tmpl) = @_;
&require_postgres();
$tmpl->{'postgres_encoding'} = $in{'postgres_encoding'};
}

# default_postgres_creation_opts(&domain)
# Returns default options for a new PostgreSQL DB in some domain
sub default_postgres_creation_opts
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local %opts;
if ($tmpl->{'postgres_encoding'} &&
    $tmpl->{'postgres_encoding'} ne 'none') {
	$opts{'encoding'} = $tmpl->{'postgres_encoding'};
	}
return \%opts;
}

# get_postgres_creation_opts(&domain, db)
# Returns a hash ref of database creation options for an existing DB
sub get_postgres_creation_opts
{
my ($d, $dbname) = @_;
&require_postgres();
my $opts = { };
eval {
	local $main::error_must_die = 1;
	my $rv = &execute_dom_psql($d, undef, "\\l");
	foreach my $r (@{$rv->{'data'}}) {
		if ($r->[0] eq $dbname) {
			$opts->{'encoding'} = $r->[2];
			}
		}
	};
return $opts;
}

# list_all_postgres_databases([&domain])
# Returns the names of all known databases
sub list_all_postgres_databases
{
my ($d) = @_;
&require_postgres();
return &list_dom_postgres_databases($d);
}

# postgres_password_synced(&domain)
# Returns 1 if a domain's MySQL password will change along with its admin pass
sub postgres_password_synced
{
my ($d) = @_;
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	return &postgres_password_synced($parent);
	}
if ($d->{'hashpass'}) {
	# Hashed passwords are being used
	return 0;
	}
if ($d->{'postgres_pass'}) {
	# Separate password set
	return 0;
	}
my $tmpl = &get_template($d->{'template'});
if ($tmpl->{'mysql_nopass'}) {
	# Syncing disabled in the template
	return 0;
	}
return 1;
}

# remote_postgres(&domain)
# Returns true if the domain's PostgreSQL DB is on a remote system
sub remote_postgres
{
local ($d) = @_;
my $host = &get_database_host_postgres($d);
return $host eq "localhost" ? undef : $host;
}

# get_postgresql_user_flags(&domain)
# Returns flags for the PostgreSQL create user command
sub get_postgresql_user_flags
{
my ($d) = @_;
&require_postgres();
my @rv = ( "nocreatedb" );
my $ver = &get_dom_remote_postgres_version($d);
if ($ver < 9.5) {
	push(@rv, "nocreateuser");
	}
return join(" ", @rv);
}

# check_reset_postgres(&domain)
# Returns an error message if the reset would delete any databases
sub check_reset_postgres
{
my ($d) = @_;
return undef if ($d->{'alias'});
my @dbs = &domain_databases($d, ["postgres"]);
return undef if (!@dbs);
if (@dbs == 1 && $dbs[0]->{'name'} eq $d->{'db'}) {
	# There is just one default database .. but is it empty?
	my @tables = &list_postgres_tables($d, $dbs[0]->{'name'});
	return undef if (!@tables);
	}
return &text('reset_epostgres', join(" ", map { $_->{'name'} } @dbs));
}

# list_remote_postgres_modules()
# Returns a list of hash refs containing details of PostgreSQL module clones for
# local or remote databases
sub list_remote_postgres_modules
{
my @rv;
foreach my $minfo (&get_all_module_infos()) {
	next if ($minfo->{'dir'} ne 'postgresql' &&
		 $minfo->{'cloneof'} ne 'postgresql');
	my %mconfig = &foreign_config($minfo->{'dir'});
	my $mm = { 'minfo' => $minfo,
		   'dbtype' => 'postgres',
		   'master' => $minfo->{'cloneof'} ? 0 : 1,
		   'config' => \%mconfig };
	if ($mconfig{'host'} && $mconfig{'port'}) {
		$mm->{'desc'} = &text('mysql_rhostport',
			"<tt>$mconfig{'host'}</tt>", $mconfig{'port'});
		}
	elsif ($mconfig{'host'}) {
		$mm->{'desc'} = &text('mysql_rhost',
			"<tt>$mconfig{'host'}</tt>");
		}
	elsif ($mconfig{'port'}) {
		$mm->{'desc'} = &text('mysql_rport', $mconfig{'port'});
		}
	else {
		$mm->{'desc'} = $text{'mysql_rlocal'};
		}
	$mm->{'desc'} .= " (SSL)"
		if ($mconfig{'sslmode'} =~ /require|verify_ca|verify_full/);
	push(@rv, $mm);
	}
@rv = sort { $a->{'minfo'}->{'dir'} cmp $b->{'minfo'}->{'dir'} } @rv;
my ($def) = grep { $_->{'config'}->{'virtualmin_default'} } @rv;
if (!$def) {
	# Assume core module is the default
	$rv[0]->{'config'}->{'virtualmin_default'} = 1;
	}
return @rv;
}

# create_remote_postgres_module(&mod)
# Creates and configures a new clone of the postgres module
sub create_remote_postgres_module
{
my ($mm) = @_;

# Create the config dir
if (!$mm->{'minfo'}->{'dir'}) {
	$mm->{'minfo'}->{'dir'} =
		"postgresql-".($mm->{'config'}->{'host'} ||
			       $mm->{'config'}->{'port'} || 'local');
	$mm->{'minfo'}->{'dir'} =~ s/\./-/g;
	if (&foreign_check($mm->{'minfo'}->{'dir'})) {
		# Clash! Try appending username
		$mm->{'minfo'}->{'dir'} .= "-".($mm->{'config'}->{'user'} || 'root');
		$mm->{'minfo'}->{'dir'} =~ s/\./-/g;
		if (&foreign_check($mm->{'minfo'}->{'dir'})) {
			&error("The module ".$mm->{'minfo'}->{'dir'}.
			       " already exists");
			}
		}
	}
$mm->{'minfo'}->{'cloneof'} = 'postgresql';
my $cdir = "$config_directory/$mm->{'minfo'}->{'dir'}";
my $srccdir = "$config_directory/postgresql";
-d $cdir && &error("Config directory $cdir already exists!");
&make_dir($cdir, 0700);
&copy_source_dest("$srccdir/config", "$cdir/config");

# Create the clone symlink
my $mdir = "$root_directory/$mm->{'minfo'}->{'dir'}";
&symlink_logged("postgresql", $mdir);

# Populate the config dir
my %mconfig = &foreign_config($mm->{'minfo'}->{'dir'});
foreach my $k (keys %{$mm->{'config'}}) {
	$mconfig{$k} = $mm->{'config'}->{$k};
	}
foreach my $k (keys %mconfig) {
	if ($k =~ /^(backup_|sync_)/) {
		delete($mconfig{$k});
		}
	}
&save_module_config(\%mconfig, $mm->{'minfo'}->{'dir'});

# Create the clone description
my %myinfo = &get_module_info('postgresql');
my $defdesc = $mm->{'config'}->{'host'} ? 
		"PostgreSQL Server on ".$mm->{'config'}->{'host'} :
	      $mm->{'config'}->{'port'} ?
		"PostgreSQL Server on port ".$mm->{'config'}->{'host'} :
		"PostgreSQL Server on local";
my %cdesc = ( 'desc' => $mm->{'minfo'}->{'desc'} || $defdesc );
&write_file("$config_directory/$mm->{'minfo'}->{'dir'}/clone", \%cdesc);

# Grant access to the current (root) user
&add_user_module_acl($base_remote_user, $mm->{'minfo'}->{'dir'});

# Refresh visible modules cache
&flush_webmin_caches();
}

# delete_remote_postgres_module(&mod)
# Removes one PostgreSQL module clone
sub delete_remote_postgres_module
{
my ($mm) = @_;
$mm->{'minfo'}->{'cloneof'} eq 'postgresql' ||
	&error("Only PostgreSQL clones can be removed!");
$mm->{'minfo'}->{'dir'} || &error("Module has no directory!");
my $cdir = "$config_directory/$mm->{'minfo'}->{'dir'}";
my $rootdir = &module_root_directory($mm->{'minfo'}->{'dir'});
-l $rootdir || &error("Module is not actually a clone!");
&unlink_logged($cdir);
&unlink_logged($rootdir);

# Refresh visible modules cache
unlink("$config_directory/module.infos.cache");
unlink("$var_directory/module.infos.cache");
}

# get_remote_postgres_module(name)
# Returns a postgres module hash, looked up by hostname or socket file
sub get_remote_postgres_module
{
my ($name) = @_;
foreach my $mm (&list_remote_postgres_modules()) {
	my $c = $mm->{'config'};
	if ($c->{'host'} && $name eq $c->{'host'}.':'.($c->{'port'} || 5432) ||
	    $c->{'host'} && $name eq $c->{'host'} ||
	    !$c->{'host'} && $name eq "localhost:".($c->{'port'} || 5432) ||
	    !$c->{'host'} && $name eq "localhost") {
		return $mm;
		}
	}
return undef;
}

# require_dom_postgres([&domain])
# Finds and loads the PostgreSQL module for a domain
sub require_dom_postgres
{
my ($d) = @_;
my $mod = !$d ? 'postgresql' : $d->{'postgres_module'} || 'postgresql';
my $pkg = $mod;
$pkg =~ s/[^A-Za-z0-9]/_/g;
eval "\$${pkg}::use_global_login = 1;";
&foreign_require($mod);
return $mod;
}

# get_dom_remote_postgres_version([&domain|module])
# Returns the PostgreSQL server version for a domain
sub get_dom_remote_postgres_version
{
my ($d) = @_;
my $mod;
if ($d && !ref($d)) {
	# Asking for a specific module
	$mod = $d;
	&foreign_require($mod);
	}
else {
	# Get module based on domain
	$mod = &require_dom_postgres($d);
	}
my $rv;
my $err;
if ($get_dom_remote_postgres_version_cache{$mod}) {
	$rv = $get_dom_remote_postgres_version_cache{$mod};
	}
else {
	$rv = &foreign_call($mod, "get_postgresql_version", 0);
	$err = "Failed to get version" if (!$rv);
	if (!$err) {
		$get_dom_remote_postgres_version_cache{$mod} = $rv;
		}
	}
return wantarray ? ($rv, "postgresql", $err) : $rv;
}

# get_default_postgres_module()
# Returns the name of the default module for remote PostgreSQL
sub get_default_postgres_module
{
my ($def) = grep { $_->{'config'}->{'virtualmin_default'} }
		 &list_remote_postgres_modules();
return $def ? $def->{'minfo'}->{'dir'} : 'postgresql';
}

# execute_dom_psql(&domain, db, sql, ...)
# Run some SQL, but in the module for the domain's PostgreSQL connection
sub execute_dom_psql
{
my ($d, $db, $sql, @params) = @_;
my $mod = &require_dom_postgres($d);
if (!$db) {
	my %rqconfig = &foreign_config($mod);
	$db = $rqconfig{'basedb'};
	}
if ($sql =~ /^(select|show)\s+/i) {
        return &foreign_call($mod, "execute_sql", $db, $sql, @params);
        }
else {
        return &foreign_call($mod, "execute_sql_logged", $db, $sql, @params);
        }
}

# list_dom_mysql_databases(&domain)
# Returns a list of postgres databases, from the server used by a domain
sub list_dom_postgres_databases
{
my ($d, $db) = @_;
my $mod = &require_dom_postgres($d);
return &foreign_call($mod, "list_databases");
}

# get_dom_postgres_creds(&domain)
# Returns the sameunix and login variables for the PostgreSQL module for
# this domain
sub get_dom_postgres_creds
{
my $mod = &require_dom_postgres($d);
my %rqconfig = &foreign_config($mod);
return ($rqconfig{'sameunix'}, $rqconfig{'login'}, $rqconfig{'pass'});
}

$done_feature_script{'postgres'} = 1;

1;

