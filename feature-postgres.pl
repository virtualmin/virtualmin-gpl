sub require_postgres
{
return if ($require_postgres++);
$postgresql::use_global_login = 1;
&foreign_require("postgresql", "postgresql-lib.pl");
%qconfig = &foreign_config("postgresql");
}

# check_postgres_clash(&domain, [field])
# Returns 1 if some PostgreSQL database already exists
sub check_postgres_clash
{
if (!$_[1] || $_[1] eq 'db') {
	&require_postgres();
	local @dblist = &postgresql::list_databases();
	return 1 if (&indexof($_[0]->{'db'}, @dblist) >= 0);
	}
if (!$_[0]->{'parent'} && (!$_[1] || $_[1] eq 'db')) {
	return 1 if (&postgres_user_exists($_[0]) ? 1 : 0);
	}
return 0;
}

# postgres_user_exists(&domain)
# Returns 1 if some user exists in PostgreSQL
sub postgres_user_exists
{
&require_postgres();
local $user = &postgres_user($_[0]);
local $s = &postgresql::execute_sql($qconfig{'basedb'}, "select * from pg_shadow where usename = '$user'");
return $s->{'data'}->[0] ? 1 : 0;
}

# setup_postgres(&domain, [no-dbs])
# Create a new PostgreSQL database and user
sub setup_postgres
{
&require_postgres();
local $tmpl = &get_template($_[0]->{'template'});
local $user = $_[0]->{'postgres_user'} = &postgres_user($_[0]);
if (!$_[0]->{'parent'}) {
	&$first_print($text{'setup_postgresuser'});
	local $pass = &postgres_pass($_[0]);
	&postgresql::execute_sql_logged($qconfig{'basedb'}, "create user \"$user\" with password $pass nocreatedb nocreateuser");
	&$second_print($text{'setup_done'});
	}
if (!$_[1] && $tmpl->{'mysql_mkdb'}) {
	# Create the initial DB
	&create_postgres_database($_[0], $_[0]->{'db'});
	}
else {
	# No DBs can exist
	$_[0]->{'db_postgres'} = "";
	}
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
if ($_[0]->{'parent'}) {
	# Password comes from parent domain
	local $parent = &get_domain($_[0]->{'parent'});
	return &postgres_pass($parent);
	}
&require_postgres();
local $pass = defined($_[0]->{'postgres_pass'}) ? $_[0]->{'postgres_pass'}
						: $_[0]->{'pass'};
return !$_[1] && &postgresql::get_postgresql_version() >= 7 ? "'$pass'" : $pass;
}

# modify_postgres(&domain, &olddomain)
# Change the PostgreSQL user's password if needed
sub modify_postgres
{
&require_postgres();
local $changeduser = $_[0]->{'user'} eq $_[1]->{'user'} ? 0 : 1;
local $user = &postgres_user($_[0], $changeduser);
local $olduser = &postgres_user($_[1]);

if ($_[0]->{'pass'} ne $_[1]->{'pass'} &&
    !$_[0]->{'parent'} && !$config{'mysql_nopass'}) {
	# Change PostgreSQL password ..
	local $pass = &postgres_pass($_[0]);
	local $oldpass = &postgres_pass($_[1]);
	&$first_print($text{'save_postgrespass'});
	if (&postgres_user_exists($_[1])) {
		&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter user \"$olduser\" with password $pass");
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
if (!$_[0]->{'parent'} && $_[1]->{'parent'}) {
	# Server has been converted to a parent .. need to create user, and
	# change database ownerships
	local $user = $_[0]->{'postgres_user'} = &postgres_user($_[0]);
	&$first_print($text{'setup_postgresuser'});
	local $pass = &postgres_pass($_[0]);
	&postgresql::execute_sql_logged($qconfig{'basedb'}, "create user \"$user\" with password $pass nocreatedb nocreateuser");
	if (&postgresql::get_postgresql_version() >= 8.0) {
		foreach my $db (&domain_databases($_[0], [ "mysql" ])) {
			&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter database \"$db->{'name'}\" owner to \"$user\"");
			}
		}
	&$second_print($text{'setup_done'});
	}
elsif ($user ne $olduser && !$_[0]->{'parent'}) {
	# Rename PostgreSQL user ..
	&$first_print($text{'save_postgresuser'});
	if (&postgres_user_exists($_[1])) {
		if (&postgresql::get_postgresql_version() >= 7.4) {
			# Can use proper rename command
			&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter user \"$olduser\" rename to \"$user\"");
			$_[0]->{'postgres_user'} = $user;
			&$second_print($text{'setup_done'});
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
elsif ($user ne $olduser && $_[0]->{'parent'}) {
	# Change owner of PostgreSQL databases
	&$first_print($text{'save_postgresuser2'});
	local $user = &postgres_user($_[0]);
	if (&postgresql::get_postgresql_version() >= 8.0) {
		foreach my $db (&domain_databases($_[0], [ "mysql" ])) {
			&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter database \"$db->{'name'}\" owner to \"$user\"");
			}
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgresuser2'});
		}
	}
}

# delete_postgres(&domain)
# Delete the PostgreSQL database and user
sub delete_postgres
{
# Delete all databases
&require_postgres();
&delete_postgres_database($_[0], &unique(split(/\s+/, $_[0]->{'db_postgres'})))
	if ($_[0]->{'db_postgres'});
local $user = &postgres_user($_[0]);

if (!$_[0]->{'parent'}) {
	# Delete the user
	&$first_print($text{'delete_postgresuser'});
	if (&postgres_user_exists($_[0])) {
		&postgresql::execute_sql_logged($qconfig{'basedb'}, "drop user \"$user\"");
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
}

# validate_postgres(&domain)
# Make sure all PostgreSQL databases exist
sub validate_postgres
{
local ($d) = @_;
&require_postgres();
local %got = map { $_, 1 } &postgresql::list_databases();
foreach my $db (&domain_databases($d, [ "postgres" ])) {
	$got{$db->{'name'}} || return &text('validate_epostgres',$db->{'name'});
	}
if (!&postgres_user_exists($d)) {
	return &text('validate_epostgresuser', &mysql_user($d));
	}
return undef;
}

# disable_postgres(&domain)
# Invalidate the domain's PostgreSQL user
sub disable_postgres
{
&$first_print($text{'disable_postgres'});
local $user = &postgres_user($_[0]);
if ($_[0]->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	}
elsif (&postgres_user_exists($_[0])) {
	&require_postgres();
	local $date = localtime(0);
	&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter user \"$user\" valid until '$date'");
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'save_nopostgres'});
	}
}

# enable_postgres(&domain)
# Validate the domain's PostgreSQL user
sub enable_postgres
{
&$first_print($text{'enable_postgres'});
local $user = &postgres_user($_[0]);
if ($_[0]->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	}
elsif (&postgres_user_exists($_[0])) {
	&require_postgres();
	&postgresql::execute_sql_logged($qconfig{'basedb'}, "alter user \"$user\" valid until 'Jan 1 2038'");
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'save_nopostgres'});
	}
}

# backup_postgres(&domain, file)
# Dumps this domain's postgreSQL database to a backup file
sub backup_postgres
{
&require_postgres();

# Find all the domains's databases
local @dbs = split(/\s+/, $_[0]->{'db_postgres'});

# Create empty 'base' backup file
&open_tempfile(EMPTY, ">$_[1]");
&close_tempfile(EMPTY);

# Back them all up
local $db;
foreach $db (@dbs) {
	&$first_print(&text('backup_postgresdump', $db));
	local $dbfile = $_[1]."_".$db;
	if ($postgresql::postgres_sameunix) {
		# For a backup done as the postgres user, create an empty file
		# owned by him first
		local @uinfo = getpwnam($postgresql::postgres_login);
		if (@uinfo) {
			&open_tempfile(EMPTY, ">$dbfile", 0, 1);
			&close_tempfile(EMPTY);
			&set_ownership_permissions($uinfo[2], $uinfo[3],
						   undef, $dbfile);
			}
		}
	local $err = &postgresql::backup_database($db, $dbfile, 'c', undef);
	if ($err) {
		&$second_print(&text('backup_postgresdumpfailed',
				     "<pre>$err</pre>"));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
return 1;
}

# restore_postgres(&domain, file)
# Restores this domain's postgresql database from a backup file, and re-creates
# the postgresql user.
sub restore_postgres
{
&require_postgres();
&foreign_require("proc", "proc-lib.pl");
&$first_print($text{'restore_postgresdrop'});
	{
	local $first_print = \&null_print;	# supress messages
	local $second_print = \&null_print;
	&require_mysql();

	# First clear out the databases
	&delete_postgres($_[0]);

	# Now re-set up the user only
	&setup_postgres($_[0], 1);
	}
&$second_print($text{'setup_done'});

# Work out which databases are in backup
local ($dbfile, @dbs);
push(@dbs, [ $_[0]->{'db'}, $_[1] ]) if (-s $_[1]);
foreach $dbfile (glob("$_[1]_*")) {
	if (-r $dbfile) {
		$dbfile =~ /\Q$_[1]\E_(.*)$/;
		push(@dbs, [ $1, $dbfile ]);
		}
	}

# Finally, import the data
local $db;
foreach $db (@dbs) {
	&create_postgres_database($_[0], $db->[0]);
	&$first_print(&text('restore_postgresload', $db->[0]));
	if ($postgresql::postgres_sameunix) {
		# Restore is running as the postgres user - make the backup
		# file owned by him
		local @uinfo = getpwnam($postgresql::postgres_login);
		if (@uinfo) {
			&set_ownership_permissions($uinfo[2], $uinfo[3],
						   undef, $db->[1]);
			}
		}
	$postgresql::in{'db'} = $db->[0];	# XXX bug work-around
	local $err = &postgresql::restore_database($db->[0], $db->[1], 0, 0);
	if ($err) {
		&$second_print(&text('restore_mysqlloadfailed', "<pre>$err</pre>"));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
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
&require_postgres();
local $size;
local $d = &postgresql::execute_sql($_[1], "select sum(relpages) from pg_class where relname not like 'pg_%'");
$size = $d->{'data'}->[0]->[0]*1024*2;
local @tables = $_[2] ? ( ) : &postgresql::list_tables($_[1], 1);
return ($size, scalar(@tables));
}

# check_postgres_database_clash(&domain, db)
# Returns 1 if some database name is already in use
sub check_postgres_database_clash
{
&require_postgres();
local @dblist = &postgresql::list_databases();
return 1 if (&indexof($_[1], @dblist) >= 0);
}

# create_postgres_database(&domain, db)
# Create one PostgreSQL database
sub create_postgres_database
{
&$first_print(&text('setup_postgresdb', $_[1]));
&require_postgres();
local $user = &postgres_user($_[0]);
local $owner = &postgresql::get_postgresql_version() >= 7 ?
		"with owner=\"$user\"" : "";
&postgresql::execute_sql_logged($qconfig{'basedb'}, "create database $_[1] $owner");
local @dbs = split(/\s+/, $_[0]->{'db_postgres'});
push(@dbs, $_[1]);
$_[0]->{'db_postgres'} = join(" ", @dbs);
&$second_print($text{'setup_done'});
}

# delete_postgres_database(&domain, dbname, ...)
# Delete one PostgreSQL database
sub delete_postgres_database
{
&require_postgres();
local @dblist = &postgresql::list_databases();
&$first_print(&text('delete_postgresdb', join(", ", @_[1..$#_])));
local @dbs = split(/\s+/, $_[0]->{'db_postgres'});
local @missing;
foreach my $db (@_[1..$#_]) {
	if (&indexof($db, @dblist) >= 0) {
		&postgresql::execute_sql_logged($qconfig{'basedb'}, "drop database $db");
		}
	else {
		push(@missing, $db);
		}
	@dbs = grep { $_ ne $db } @dbs;
	}
$_[0]->{'db_postgres'} = join(" ", @dbs);
if (@missing) {
	&$second_print(&text('delete_mysqlmissing', join(", ", @missing)));
	}
else {
	&$second_print($text{'setup_done'});
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

# list_postgres_tables(database)
# Returns a list of tables in the specified database
sub list_postgres_tables
{
&require_postgres();
return &postgresql::list_tables($_[0], 1);
}

# get_database_host_postgres()
# Returns the hostname of the server on which PostgreSQL is actually running
sub get_database_host_postgres
{
&require_postgres();
return $postgres::config{'host'} || 'localhost';
}

# sysinfo_postgres()
# Returns the PostgreSQL version
sub sysinfo_postgres
{
&require_postgres();
local $ver = &postgresql::get_postgresql_version();
return ( [ $text{'sysinfo_postgresql'}, $ver ] );
}

sub startstop_postgres
{
local ($typestatus) = @_;
&require_postgres();
return undef if (!&postgresql::is_postgresql_local());
local $r = defined($typestatus->{'postgresql'}) ?
                $typestatus->{'postgresql'} == 1 :
		&postgresql::is_postgresql_running();
if ($r == 1) {
	return { 'status' => 1,
		 'name' => $text{'index_pgname'},
		 'desc' => $text{'index_pgstop'},
		 'restartdesc' => $text{'index_pgrestart'},
		 'longdesc' => $text{'index_pgstopdesc'} };
	}
elsif ($r == 0) {
	return { 'status' => 0,
		 'name' => $text{'index_pgname'},
		 'desc' => $text{'index_pgstart'},
		 'longdesc' => $text{'index_pgstartdesc'} };
	}
else {
	return undef;
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

$done_feature_script{'postgres'} = 1;

1;

