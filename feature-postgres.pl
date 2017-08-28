sub require_postgres
{
return if ($require_postgres++);
$postgresql::use_global_login = 1;
&foreign_require("postgresql");
%qconfig = &foreign_config("postgresql");
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
	local @dblist = &postgresql::list_databases();
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

# postgres_user_exists(&domain)
# Returns 1 if some user exists in PostgreSQL
sub postgres_user_exists
{
&require_postgres();
local $user = &postgres_user($_[0]);
local $s = &postgresql::execute_sql($qconfig{'basedb'},
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
		if (&postgres_user($d) eq &postgres_user($od)) {
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
&require_postgres();
local $tmpl = &get_template($d->{'template'});
local $user = $d->{'postgres_user'} = &postgres_user($d);

# Check if only hashed passwords are stored, and if so generate a random
# PostgreSQL password now
if ($d->{'hashpass'} && !$d->{'parent'} && !$d->{'postgres_pass'}) {
	$d->{'postgres_pass'} = &random_password(16);
	delete($d->{'postgres_enc_pass'});
	}

if (!$d->{'parent'}) {
	&$first_print($text{'setup_postgresuser'});
	local $pass = &postgres_pass($d);
	if (&postgres_user_exists($user)) {
		&postgresql::execute_sql_logged($qconfig{'basedb'},
		  "drop user ".&postgres_uquote($user));
		}
	local $popts = &get_postgresql_user_flags();
	&postgresql::execute_sql_logged($qconfig{'basedb'},
		"create user ".&postgres_uquote($user).
		" with password $pass $popts");
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
if ($_[0]->{'parent'}) {
	# Password comes from parent domain
	local $parent = &get_domain($_[0]->{'parent'});
	return &postgres_pass($parent);
	}
&require_postgres();
local $pass = defined($_[0]->{'postgres_pass'}) ? $_[0]->{'postgres_pass'}
						: $_[0]->{'pass'};
return !$_[1] && &postgresql::get_postgresql_version() >= 7 ?
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
&require_postgres();
local $tmpl = &get_template($_[0]->{'template'});
local $changeduser = $_[0]->{'user'} ne $_[1]->{'user'} &&
		     !$tmpl->{'mysql_nouser'} ? 1 : 0;
local $user = &postgres_user($_[0], $changeduser);
local $olduser = &postgres_user($_[1]);

local $pass = &postgres_pass($_[0]);
local $oldpass = &postgres_pass($_[1]);
if ($pass ne $oldpass && !$_[0]->{'parent'} &&
    (!$tmpl->{'mysql_nopass'} || $_[0]->{'postgres_pass'})) {
	# Change PostgreSQL password ..
	&$first_print($text{'save_postgrespass'});
	if (&postgres_user_exists($_[1])) {
		&postgresql::execute_sql_logged($qconfig{'basedb'},
			"alter user ".&postgres_uquote($olduser).
			" with password $pass");
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nopostgres'});
		}
	}
if (!$_[0]->{'parent'} && $_[1]->{'parent'}) {
	# Server has been converted to a parent .. need to create user, and
	# change database ownerships
	delete($_[0]->{'postgres_user'});
	&$first_print($text{'setup_postgresuser'});
	local $pass = &postgres_pass($_[0]);
	local $popts = &get_postgresql_user_flags();
	&postgresql::execute_sql_logged($qconfig{'basedb'},
		"create user ".&postgres_uquote($user).
		" with password $pass $popts");
	if (&postgresql::get_postgresql_version() >= 8.0) {
		foreach my $db (&domain_databases($_[0], [ "postgres" ])) {
			&postgresql::execute_sql_logged($db,
			    "reassign owned by ".&postgres_uquote($olduser).
			    " to ".&postgres_uquote($user));
			&postgresql::execute_sql_logged($qconfig{'basedb'},
			  "alter database ".&postgres_uquote($db->{'name'}).
			  " owner to ".&postgres_uquote($user));
			}
		}
	&$second_print($text{'setup_done'});
	}
elsif ($_[0]->{'parent'} && !$_[1]->{'parent'}) {
	# Server has changed from parent to sub-server .. need to remove the
	# old user and update all DB permissions
	&$first_print($text{'save_postgresuser'});
	if (&postgresql::get_postgresql_version() >= 8.0) {
		foreach my $db (&domain_databases($_[0], [ "postgres" ])) {
			&postgresql::execute_sql_logged($db,
			    "reassign owned by ".&postgres_uquote($olduser).
			    " to ".&postgres_uquote($user));
			&postgresql::execute_sql_logged($qconfig{'basedb'},
			    "alter database ".&postgres_uquote($db->{'name'}).
			    " owner to ".&postgres_uquote($user));
			}
		}
	if (&postgres_user_exists($_[1])) {
		&postgresql::execute_sql_logged($qconfig{'basedb'},
			"drop user ".&postgres_uquote($olduser));
		}
	&$second_print($text{'setup_done'});
	}
elsif ($user ne $olduser && !$_[0]->{'parent'}) {
	# Rename PostgreSQL user ..
	&$first_print($text{'save_postgresuser'});
	if (&postgres_user_exists($_[1])) {
		if (&postgresql::get_postgresql_version() >= 7.4) {
			# Can use proper rename command
			&postgresql::execute_sql_logged($qconfig{'basedb'},
				"alter user ".&postgres_uquote($olduser).
				" rename to ".&postgres_uquote($user));
			&postgresql::execute_sql_logged($qconfig{'basedb'},
				"alter user ".&postgres_uquote($user).
				" with password $pass");
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
			&postgresql::execute_sql_logged($qconfig{'basedb'},
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

# If PostgreSQL is hosted remotely, don't delete the DB on the assumption that
# other servers sharing the DB will still be using it
if ($preserve && &remote_postgres($d)) {
	&$first_print(&text('delete_postgresdb', join(" ", @dblist)));
	&$second_print(&text('delete_mysqlpreserve',
			     $postgresql::config{'host'}));
	return 1;
	}

# Delete all databases
&delete_postgres_database($d, @dblist) if (@dblist);
local $user = &postgres_user($d);

if (!$d->{'parent'}) {
	# Delete the user
	&$first_print($text{'delete_postgresuser'});
	if (&postgres_user_exists($d)) {
		if (&postgresql::get_postgresql_version() >= 8.0) {
			local $s = &postgresql::execute_sql($qconfig{'basedb'},
				"select datname from pg_database ".
				"join pg_authid ".
				"on pg_database.datdba = pg_authid.oid ".
				"where rolname = '$user'");
			foreach my $db (map { $_->[0] } @{$s->{'data'}}) {
				&postgresql::execute_sql_logged(
					$db,
					"reassign owned by ".
					  &postgres_uquote($user).
					  " to ".
					  $postgresql::postgres_login);
				&postgresql::execute_sql_logged(
					$qconfig{'basedb'},
					"alter database $db owner to ".
					  $postgresql::postgres_login);
				}
			};
		&postgresql::execute_sql_logged($qconfig{'basedb'},
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
	foreach my $db (&domain_databases($d, [ 'postgres' ])) {
		local $oldname = $dbmap{$db->{'name'}};
		local $temp = &transname();
		if ($postgresql::postgres_sameunix) {
			# Create empty file postgres user can write to
			local @uinfo = getpwnam($postgresql::postgres_login);
			if (@uinfo) {
				&open_tempfile(EMPTY, ">$temp", 0, 1);
				&close_tempfile(EMPTY);
				&set_ownership_permissions($uinfo[2], $uinfo[3],
							   undef, $temp);
				}
			}
		local $err = &postgresql::backup_database($oldname, $temp,
							  'c', undef);
		if ($err) {
			&$second_print(&text('clone_postgresbackup',
					     $oldname, $err));
			next;
			}
		$err = &postgresql::restore_database($db->{'name'}, $temp,
						     0, 0);
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
local %got = map { $_, 1 } &postgresql::list_databases();
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
&$first_print($text{'disable_postgres'});
local $user = &postgres_user($_[0]);
if ($_[0]->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	return 0;
	}
elsif (&postgres_user_exists($_[0])) {
	&require_postgres();
	local $date = localtime(0);
	&postgresql::execute_sql_logged($qconfig{'basedb'},
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
&$first_print($text{'enable_postgres'});
local $user = &postgres_user($_[0]);
if ($_[0]->{'parent'}) {
	&$second_print($text{'save_nopostgrespar'});
	return 0;
	}
elsif (&postgres_user_exists($_[0])) {
	&require_postgres();
	&postgresql::execute_sql_logged($qconfig{'basedb'},
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
local ($d, $file) = @_;
&require_postgres();

# Find all the domains's databases
local @dbs = split(/\s+/, $d->{'db_postgres'});

# Filter out any excluded DBs
my @exclude = &get_backup_db_excludes($d);
my %exclude = map { $_, 1 } @exclude;
@dbs = grep { !$exclude{$_} } @dbs;

# Create base backup file with meta-information
local %info = ( 'remote' => $postgresql::config{'host'} );
&write_as_domain_user($d, sub { &write_file($file, \%info) });

# Back them all up
local $db;
local $ok = 1;
foreach $db (@dbs) {
	&$first_print(&text('backup_postgresdump', $db));
	local $dbfile = $file."_".$db;
	local $destfile = $dbfile;
	if ($postgresql::postgres_sameunix) {
		# For a backup done as the postgres user, create an empty file
		# owned by him first
		local @uinfo = getpwnam($postgresql::postgres_login);
		if (@uinfo) {
			$destfile = &transname();
			&open_tempfile(EMPTY, ">$destfile", 0, 1);
			&close_tempfile(EMPTY);
			&set_ownership_permissions($uinfo[2], $uinfo[3],
						   undef, $destfile);
			}
		}

	# Limit tables to those that aren't excluded
	my %texclude = map { $_, 1 }
			 map { (split(/\./, $_))[1] }
			   grep { /^\Q$db\E\./ || /^\*\./ } @exclude;
	my $tables;
	if (%texclude) {
		$tables = [ grep { !$texclude{$_} }
				 &postgresql::list_tables($db) ];
		}

	local $err = &postgresql::backup_database($db, $destfile, 'c', $tables);
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
local ($d, $file, $opts, $allopts, $homefmt, $oldd, $asd) = @_;
local %info;
&read_file($file, \%info);
&require_postgres();

# If in replication mode, AND the remote PostgreSQL system is the same on both
# systems, do nothing
if ($allopts->{'repl'} && $postgresql::config{'host'} && $info{'remote'} &&
    $postgresql::config{'host'} eq $info{'remote'}) {
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
		my @tables = &postgresql::list_tables($db->[0], 1);
		if (@tables) {
			# But grant access to the DB to the domain owner
			if (&postgresql::get_postgresql_version() >= 8.0) {
				local $q = &postgres_uquote(&postgres_user($d));
				&postgresql::execute_sql_logged(
                                        $qconfig{'basedb'},
                                        "alter database $db->[0] owner to $q");
				foreach my $t (@tables) {
					&postgresql::execute_sql_logged(
						$db->[0],
						"alter table $t owner to $q");
					}
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
	if ($postgresql::postgres_sameunix) {
		# Restore is running as the postgres user - make the backup
		# file owned by him, and the parent directory world-accessible
		local @uinfo = getpwnam($postgresql::postgres_login);
		if (@uinfo) {
			&set_ownership_permissions($uinfo[2], $uinfo[3],
						   undef, $db->[1]);
			local $dir = $file;
			$dir =~ s/\/[^\/]+$//;
			&set_ownership_permissions(undef, undef, 0711, $dir);
			}
		}
	local $err;
	if ($asd) {
		# As domain owner
		local $postgresql::postgres_login = &postgres_user($d);
		local $postgresql::postgres_pass = &postgres_pass($d, 1);
		$err = &postgresql::restore_database($db->[0], $db->[1], 0, 0);
		}
	else {
		# As master admin
		$err = &postgresql::restore_database($db->[0], $db->[1], 0, 0);
		}
	if ($err) {
		&$second_print(&text('restore_mysqlloadfailed', "<pre>$err</pre>"));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
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
&require_postgres();
local $size;
local @tables;
eval {
	# Make sure DBI errors don't cause a total failure
	local $main::error_must_die = 1;
	local $postgresql::force_nodbi = 1;
	local $d = &postgresql::execute_sql($_[1], "select sum(relpages) from pg_class where relname not like 'pg_%'");
	$size = $d->{'data'}->[0]->[0]*1024*2;
	if (!$_[2]) {
		@tables = &postgresql::list_tables($_[1], 1);
		}
	};
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

# create_postgres_database(&domain, db, &opts)
# Create one PostgreSQL database
sub create_postgres_database
{
&require_postgres();

if (!&check_postgres_database_clash($_[0], $_[1])) {
	# Build and run creation command
	&$first_print(&text('setup_postgresdb', $_[1]));
	local $user = &postgres_user($_[0]);
	local $sql = "create database ".&postgresql::quote_table($_[1]);
	local $withs;
	if (&postgresql::get_postgresql_version() >= 7) {
		$withs .= " owner=".&postgres_uquote($user);
		}
	if ($_[2]->{'encoding'}) {
		$withs .= " encoding ".&postgres_quote($_[2]->{'encoding'});
		}
	if ($withs) {
		$sql .= " with".$withs;
		}
	&postgresql::execute_sql_logged($qconfig{'basedb'}, $sql);
	}
else {
	&$first_print(&text('setup_postgresdbimport', $_[1]));
	}

# Make sure nobody else can access it
eval {
	local $main::error_must_die = 1;
	&postgresql::execute_sql_logged($qconfig{'basedb'},
		"revoke all on database ".&postgres_uquote($_[1]).
		" from public");
	};
local @dbs = split(/\s+/, $_[0]->{'db_postgres'});
push(@dbs, $_[1]);
$_[0]->{'db_postgres'} = join(" ", @dbs);
&$second_print($text{'setup_done'});
return 1;
}

# grant_postgres_database(&domain, dbname)
# Alters the owner of a PostgreSQL database to some domain
sub grant_postgres_database
{
local ($d, $dbname) = @_;
&require_postgres();
if (&postgresql::get_postgresql_version() >= 8.0) {
	local $user = &postgres_user($d);
	&postgresql::execute_sql_logged($qconfig{'basedb'},
		"alter database ".&postgres_uquote($dbname).
		" owner to ".&postgres_uquote($user));
	}
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
		&postgresql::execute_sql_logged($qconfig{'basedb'},
			"drop database ".&postgresql::quote_table($db));
		if (defined(&postgresql::delete_database_backup_job)) {
			&postgresql::delete_database_backup_job($db);
			}
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

# revoke_postgres_database(&domain, dbname)
# Takes away a domain's access to a PostgreSQL database, by setting the owner
# back to postgres
sub revoke_postgres_database
{
local ($d, $dbname) = @_;
&require_postgres();
if (&postgresql::get_postgresql_version() >= 8.0 &&
    &postgres_user_exists("postgres")) {
	&postgresql::execute_sql_logged($qconfig{'basedb'},
		"alter database ".&postgres_uquote($dbname).
		" owner to ".&postgres_uquote(postgres));
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
&require_postgres();
return &postgresql::list_tables($db, 1);
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
local @rv;
eval {
	# Protect against DBI errors
	local $main::error_must_die = 1;
	local $postgresql::force_nodbi = 1;
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

# check_postgres_login(dbname, dbuser, dbpass)
# Tries to login to PostgreSQL with the given credentials, returning undef
# on failure
sub check_postgres_login
{
local ($dbname, $dbuser, $dbpass) = @_;
&require_postgres();
local $main::error_must_die = 1;
local $postgresql::postgres_login = $dbuser;
local $postgresql::postgres_pass = $dbpass;
eval { &postgresql::execute_sql($dbname, "select version()") };
local $err = $@;
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
&require_postgres();
if (&postgresql::get_postgresql_version() >= 7.4) {
	local $tmpl = &get_template($_[0]->{'template'});
	local $cs = $tmpl->{'postgres_encoding'};
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
local ($d, $dbname) = @_;
&require_postgres();
local $opts = { };
eval {
	local $main::error_must_die = 1;
	local $rv = &postgresql::execute_sql($qconfig{'basedb'}, "\\l");
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
&require_postgres();
return &postgresql::list_databases();
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
&require_postgres();
return $postgresql::config{'host'};
}

sub get_postgresql_user_flags
{
&require_postgres();
my @rv = ( "nocreatedb" );
if (&postgresql::get_postgresql_version() < 9.5) {
	push(@rv, "nocreateuser");
	}
return join(" ", @rv);
}

$done_feature_script{'postgres'} = 1;

1;

