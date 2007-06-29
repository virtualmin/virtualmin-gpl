sub require_mysql
{
return if ($require_mysql++);
$mysql::use_global_login = 1;
&foreign_require("mysql", "mysql-lib.pl");
%mconfig = &foreign_config("mysql");
$password_func = $mysql::password_func || "password";
}

# check_depends_mysql(&dom)
# Ensure that a sub-server has a parent server with MySQL enabled
sub check_depends_mysql
{
return undef if (!$_[0]->{'parent'});
local $parent = &get_domain($_[0]->{'parent'});
return $text{'setup_edepmysql'} if (!$parent->{'mysql'});
return undef;
}

# check_anti_depends_mysql(&dom)
# Ensure that a parent server without MySQL does not have any children with it
sub check_anti_depends_mysql
{
if (!$_[0]->{'mysql'}) {
	local @subs = &get_domain_by("parent", $_[0]->{'id'});
	foreach my $s (@subs) {
		return $text{'setup_edepmysqlsub'} if ($s->{'mysql'});
		}
	}
return undef;
}

# setup_mysql(&domain, [no-db])
# Create a new MySQL database, user and permissions
sub setup_mysql
{
local ($d, $nodb) = @_;
local $tmpl = &get_template($d->{'template'});
&require_mysql();

# Create the user
$d->{'mysql_user'} = &mysql_user($d);
local $user = $d->{'mysql_user'};
local @hosts = &get_mysql_hosts($d);
local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $d);
if (!$d->{'parent'}) {
	&$first_print($text{'setup_mysqluser'});
	local $cfunc = sub {
		local $encpass = &encrypted_mysql_pass($d);
		local $h;
		foreach $h (@hosts) {
			&mysql::execute_sql_logged($mysql::master_db, "insert into user (host, user, password) values ('$h', '$user', $encpass)");
			if ($wild && $wild ne $d->{'db'}) {
				&add_db_table($h, $wild, $user);
				}
			}
		&mysql::execute_sql_logged($mysql::master_db,
					   'flush privileges');
		};
	&execute_for_all_mysql_servers($cfunc);
	&$second_print($text{'setup_done'});
	}

# Create the initial DB (if requested)
if (!$nodb && $tmpl->{'mysql_mkdb'} && !$d->{'no_mysql_db'}) {
	&create_mysql_database($d, $d->{'db'});
	}
else {
	# No DBs can exist
	$d->{'db_mysql'} = "";
	}
}

# add_db_table(host, db, user)
# Adds an entry to the db table, with all permission columns set to Y
sub add_db_table
{
local ($host, $db, $user) = @_;
local @str = &mysql::table_structure($mysql::master_db, 'db');
local ($s, @fields, @yeses);
foreach $s (@str) {
	if ($s->{'field'} =~ /_priv$/i) {
		push(@fields, $s->{'field'});
		push(@yeses, "'Y'");
		}
	}
local $qdb = &quote_mysql_database($db);
&mysql::execute_sql_logged($mysql::master_db, "insert into db (host, db, user, ".join(", ", @fields).") values ('$host', '$qdb', '$user', ".join(", ", @yeses).")");
}

# delete_mysql(&domain)
# Delete a mysql database, the domain's mysql user and all permissions for both
sub delete_mysql
{
local ($d) = @_;

# First remove the databases
&require_mysql();
if ($d->{'db_mysql'}) {
	&delete_mysql_database($d, &unique(split(/\s+/, $d->{'db_mysql'})));
	}

# Then remove the user
&$first_print($text{'delete_mysqluser'}) if (!$d->{'parent'});
local $dfunc = sub { 
	local $user = &mysql_user($d);
	local $tmpl = &get_template($d->{'template'});
	local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $d);
	if (!$d->{'parent'}) {
		# Delete the user and any database permissions
		&mysql::execute_sql_logged($mysql::master_db, "delete from user where user = '$user'");
		&mysql::execute_sql_logged($mysql::master_db, "delete from db where user = '$user'");
		}
	if ($wild && $wild ne $d->{'db'}) {
		# Remove any wildcard entry for the user
		&mysql::execute_sql_logged($mysql::master_db, "delete from db where db = '$wild'");
		}
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($dfunc);
&$second_print($text{'setup_done'}) if (!$d->{'parent'});
}

# modify_mysql(&domain, &olddomain)
# Changes the mysql user's password if needed
sub modify_mysql
{
local ($d, $oldd) = @_;
&require_mysql();
local $rv = 0;
local $changeduser = $d->{'user'} eq $oldd->{'user'} ? 0 : 1;
local $olduser = &mysql_user($oldd);
local $user = &mysql_user($d, $changeduser);
$d->{'mysql_user'} = $user;
local $oldencpass = &encrypted_mysql_pass($oldd);
local $encpass = &encrypted_mysql_pass($d);
local $tmpl = &get_template($d->{'id'});
if ($encpass ne $oldencpass && !$d->{'parent'} && !$tmpl->{'mysql_nopass'}) {
	# Change MySQL password
	&$first_print($text{'save_mysqlpass'});
	if (&mysql_user_exists($d)) {
		local $pfunc = sub {
			&mysql::execute_sql_logged($mysql::master_db, "update user set password = $encpass where user = '$olduser'");
			&mysql::execute_sql_logged($master_db, 'flush privileges');
			};
		&execute_for_all_mysql_servers($pfunc);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	else {
		&$second_print($text{'save_nomysql'});
		}
	}
if (!$d->{'parent'} && $oldd->{'parent'}) {
	# Server has been converted to a parent .. need to create user, and
	# change access to old DBs
	&$first_print($text{'setup_mysqluser'});
	$d->{'mysql_user'} = &mysql_user($d, 1);
	local $user = $d->{'mysql_user'};
	local @hosts = &get_mysql_hosts($d);
	local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $d);
	local $encpass = &encrypted_mysql_pass($d);
	local $pfunc = sub {
		local $h;
		foreach $h (@hosts) {
			&mysql::execute_sql_logged($mysql::master_db, "insert into user (host, user, password) values ('$h', '$user', $encpass)");
			if ($wild && $wild ne $d->{'db'}) {
				&add_db_table($h, $wild, $user);
				}
			}
		foreach my $db (&domain_databases($d, [ "mysql" ])) {
			local $qdb = &quote_mysql_database($db->{'name'});
			&mysql::execute_sql_logged($mysql::master_db, "update db set user = '$user' where user = '$olduser' and (db = '$db->{'name'}' or db = '$qdb')");
			}
		&mysql::execute_sql_logged($mysql::master_db,
					   'flush privileges');
		};
	&execute_for_all_mysql_servers($pfunc);
	&$second_print($text{'setup_done'});
	}
elsif ($d->{'parent'} && !$oldd->{'parent'}) {
	# Server has changed from parent to sub-server .. need to remove the
	# old user and update all DB permissions
	&$first_print($text{'save_mysqluser'});
	local $pfunc = sub {
		&mysql::execute_sql_logged($mysql::master_db, "delete from user where user = '$olduser'");
		&mysql::execute_sql_logged($mysql::master_db, "update db set user = '$user' where user = '$olduser'");
		&mysql::execute_sql_logged($master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($pfunc);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif ($user ne $olduser && !$d->{'parent'}) {
	# MySQL user in a parent domain has changed, perhaps due to username
	# change. Need to update user in DB and all db entries
	&$first_print($text{'save_mysqluser'});
	if (&mysql_user_exists($oldd)) {
		local $pfunc = sub {
			&mysql::execute_sql_logged($mysql::master_db, "update user set user = '$user' where user = '$olduser'");
			&mysql::execute_sql_logged($mysql::master_db, "update db set user = '$user' where user = '$olduser'");
			&mysql::execute_sql_logged($master_db, 'flush privileges');
			};
		&execute_for_all_mysql_servers($pfunc);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	else {
		&$second_print($text{'save_nomysql'});
		}
	}
elsif ($user ne $olduser && $d->{'parent'}) {
	# Server has moved to a new user .. change ownership of DBs
	&$first_print($text{'save_mysqluser2'});
	local $pfunc = sub {
		foreach my $db (&domain_databases($d, [ "mysql" ])) {
			local $qdb = &quote_mysql_database($db->{'name'});
			&mysql::execute_sql_logged($mysql::master_db, "update db set user = '$user' where user = '$olduser' and (db = '$db->{'name'}' or db = '$qdb')");
			}
		&mysql::execute_sql_logged($master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($pfunc);
	$rv++;
	&$second_print($text{'setup_done'});
	}

if ($d->{'group'} ne $oldd->{'group'} && $tmpl->{'mysql_chgrp'}) {
	# Unix group has changed - fix permissions on all DB files
	&$first_print($text{'save_mysqlgroup'});
	foreach my $db (&domain_databases($d, [ "mysql" ])) {
		local $dd = &get_mysql_database_dir($db->{'name'});
		if ($dd) {
			&system_logged("chgrp -R $d->{'group'} ".
				       quotemeta($dd));
			}
		}
	&$second_print($text{'setup_done'});
	}
return $rv;
}

# validate_mysql(&domain)
# Make sure all MySQL databases exist, and that the admin user exists
sub validate_mysql
{
local ($d) = @_;
&require_mysql();
local %got = map { $_, 1 } &mysql::list_databases();
foreach my $db (&domain_databases($d, [ "mysql" ])) {
	$got{$db->{'name'}} || return &text('validate_emysql', $db->{'name'});
	}
if (!&mysql_user_exists($d)) {
	return &text('validate_emysqluser', &mysql_user($d));
	}
return undef;
}

# disable_mysql(&domain)
# Modifies the mysql user for this domain so that he cannot login
sub disable_mysql
{
local ($d) = @_;
&$first_print($text{'disable_mysqluser'});
if ($d->{'parent'}) {
	&$second_print($text{'save_nomysqlpar'});
	}
else {
	&require_mysql();
	local $user = &mysql_user($d);
	if ($oldpass = &mysql_user_exists($d)) {
		local $dfunc = sub {
			&mysql::execute_sql_logged($mysql::master_db, "update user set password = '*LK*' where user = '$user'");
			&mysql::execute_sql_logged($master_db, 'flush privileges');
			};
		&execute_for_all_mysql_servers($dfunc);
		$d->{'disabled_oldmysql'} = $oldpass;
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nomysql'});
		}
	}
}

# enable_mysql(&domain)
# Puts back the original password for the mysql user so that he can login again
sub enable_mysql
{
local ($d) = @_;
&$first_print($text{'enable_mysql'});
if ($d->{'parent'}) {
	&$second_print($text{'save_nomysqlpar'});
	}
else {
	&require_mysql();
	local $user = &mysql_user($d);
	if (&mysql_user_exists($d)) {
		local $efunc = sub {
			if ($d->{'disabled_oldmysql'}) {
				local $qpass = &mysql_escape(
					$d->{'disabled_oldmysql'});
				&mysql::execute_sql_logged($mysql::master_db, "update user set password = '$qpass' where user = '$user'");
				}
			else {
				local $pass = &mysql_pass($d);
				local $qpass = &mysql_escape($pass);
				&mysql::execute_sql_logged($mysql::master_db, "update user set password = $password_func('$qpass') where user = '$user'");
				}
			&mysql::execute_sql($master_db, 'flush privileges');
			};
		&execute_for_all_mysql_servers($efunc);
		delete($d->{'disabled_oldmysql'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nomysql'});
		}
	}
}

# mysql_user_exists(&domain)
# Returns his password if a mysql user exists for the domain's user, or undef
sub mysql_user_exists
{
&require_mysql();
local $user = &mysql_user($_[0]);
local $u = &mysql::execute_sql($mysql::master_db, "select password from user where user = '$user'");
return @{$u->{'data'}} ? $u->{'data'}->[0]->[0] : undef;
}

# check_mysql_clash(&domain, [field])
# Returns 1 if some MySQL database already exists
sub check_mysql_clash
{
if (!$_[1] || $_[1] eq 'db') {
	&require_mysql();
	local @dblist = &mysql::list_databases();
	return 1 if (&indexof($_[0]->{'db'}, @dblist) >= 0);
	}
if (!$_[0]->{'parent'} && (!$_[1] || $_[1] eq 'user')) {
	&require_mysql();
	return 1 if (&mysql_user_exists($_[0]));
	}
return 0;
}

# backup_mysql(&domain, file)
# Dumps this domain's mysql database to a backup file
sub backup_mysql
{
&require_mysql();

# Find all domain's databases
local $tmpl = &get_template($_[0]->{'template'});
local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $_[0]);
local @alldbs = &mysql::list_databases();
local @dbs;
if ($wild) {
	$wild =~ s/\%/\.\*/g;
	$wild =~ s/_/\./g;
	@dbs = grep { /^$wild$/i } @alldbs;
	}
push(@dbs, split(/\s+/, $_[0]->{'db_mysql'}));
@dbs = &unique(@dbs);

# Create empty 'base' backup file
&open_tempfile(EMPTY, ">$_[1]");
&close_tempfile(EMPTY);

# Back them all up
local $db;
foreach $db (@dbs) {
	&$first_print(&text('backup_mysqldump', $db));
	local $dbfile = $_[1]."_".$db;
	local $err = &mysql::backup_database($db, $dbfile, 0, 1, 0,
					     undef, undef, undef, undef);
	if ($err) {
		&$second_print(&text('backup_mysqldumpfailed',
				     "<pre>$err</pre>"));
		return 0;
		}
	else {
		# Backup worked .. gzip the file
		&execute_command("gzip ".quotemeta($dbfile), undef, \$out);
		if ($?) {
			&$second_print(&text('backup_mysqlgzipfailed',
					     "<pre>$out</pre>"));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}
return 1;
}

# restore_mysql(&domain, file)
# Restores this domain's mysql database from a backup file, and re-creates
# the mysql user.
sub restore_mysql
{
&$first_print($text{'restore_mysqldrop'});
	{
	local $first_print = \&null_print;	# supress messages
	local $second_print = \&null_print;
	&require_mysql();

	# First clear out all current databases and the MySQL login
	&delete_mysql($_[0]);

	# Now re-set up the login only
	&setup_mysql($_[0], 1);
	}
&$second_print($text{'setup_done'});

# Work out which databases are in backup
local ($dbfile, @dbs);
push(@dbs, [ $_[0]->{'db'}, $_[1] ]) if (-s $_[1]);
foreach $dbfile (glob("$_[1]_*")) {
	if (-r $dbfile) {
		$dbfile =~ /\Q$_[1]\E_(.*)\.gz$/ ||
			$dbfile =~ /\Q$_[1]\E_(.*)$/;
		push(@dbs, [ $1, $dbfile ]);
		}
	}

# Finally, import the data
local $db;
foreach $db (@dbs) {
	&create_mysql_database($_[0], $db->[0]);
	&$first_print(&text('restore_mysqlload', $db->[0]));
	if ($db->[1] =~ /\.gz$/) {
		# Need to uncompress first
		local $out = &backquote_logged(
			"gunzip ".quotemeta($db->[1])." 2>&1");
		if ($?) {
			&$second_print(&text('restore_mysqlgunzipfailed',
					     "<pre>$out</pre>"));
			return 0;
			}
		$db->[1] =~ s/\.gz$//;
		}
	local ($ex, $out) = &mysql::execute_sql_file($db->[0], $db->[1]);
	if ($ex) {
		&$second_print(&text('restore_mysqlloadfailed',
				     "<pre>$out</pre>"));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
return 1;
}

# mysql_user(&domain, [always-new])
# Returns the MySQL login name for a domain
sub mysql_user
{
if ($_[0]->{'parent'}) {
	# Get from parent domain
	return &mysql_user(&get_domain($_[0]->{'parent'}), $_[1]);
	}
return $_[0]->{'mysql_user'} if (defined($_[0]->{'mysql_user'}) && !$_[1]);
return length($_[0]->{'user'}) > 16 ?
	  substr($_[0]->{'user'}, 0, 16) : $_[0]->{'user'};
}

# set_mysql_user(&domain, newuser)
# Updates a domain object with a new MySQL username
sub set_mysql_user
{
$_[0]->{'mysql_user'} = length($_[1]) > 16 ? substr($_[1], 0, 16) : $_[1];
}

# mysql_username(username)
# Adjusts a username to be suitable for MySQL
sub mysql_username
{
return length($_[0]) > 16 ? substr($_[0], 0, 16) : $_[0];
}

# set_mysql_pass(&domain, [password])
# Updates a domain object to use the specified login for mysql. Does not
# actually change the database - that must be done by modify_mysql.
sub set_mysql_pass
{
local ($d, $pass) = @_;
if (defined($pass)) {
	$d->{'mysql_pass'} = $pass;
	}
else {
	delete($d->{'mysql_pass'});
	}
delete($d->{'mysql_enc_pass'});		# Clear encrypted password, as we
					# have a plain password now
}

# mysql_pass(&domain, [neverquote])
# Returns the plain-text password for the MySQL admin for this domain
sub mysql_pass
{
if ($_[0]->{'parent'}) {
	# Password comes from parent domain
	local $parent = &get_domain($_[0]->{'parent'});
	return &mysql_pass($parent);
	}
return defined($_[0]->{'mysql_pass'}) ? $_[0]->{'mysql_pass'} : $_[0]->{'pass'};
}

# mysql_enc_pass(&domain)
# If this domain has only a pre-encrypted MySQL password, return it
sub mysql_enc_pass
{
return $_[0]->{'mysql_enc_pass'};
}

# mysql_escape(string)
# Returns a string with quotes escaped, for use in SQL
sub mysql_escape
{
local $rv = $_[0];
$rv =~ s/'/''/g;
return $rv;
}

# mysql_size(&domain, dbname, [size-only])
# Returns the size, number of tables in a database, and size included in a
# domain's Unix quota.
sub mysql_size
{
&require_mysql();
local ($size, $qsize);
local $dd = &get_mysql_database_dir($_[1]);
if ($dd) {
	$size = &disk_usage_kb($dd)*1024;
	local @dst = stat($dd);
	if (&has_group_quotas() && &has_mysql_quotas() &&
            $dst[5] == $_[0]->{'gid'}) {
		$qsize = $size;
		}
	}
local @tables = $_[2] ? () : &mysql::list_tables($_[1], 1);
return ($size, scalar(@tables), $qsize);
}

# check_mysql_database_clash(&domain, dbname)
# Check if some MySQL database already exists
sub check_mysql_database_clash
{
&require_mysql();
local @dblist = &mysql::list_databases();
return 1 if (&indexof($_[1], @dblist) >= 0);
}

# create_mysql_database(&domain, dbname, &opts)
# Add one database to this domain, and grants access to it to the user
sub create_mysql_database
{
local ($d, $dbname, $opts) = @_;

# Create the database
&$first_print(&text('setup_mysqldb', $dbname));
local @dbs = split(/\s+/, $d->{'db_mysql'});
&mysql::execute_sql_logged($mysql::master_db,
		   "create database ".&mysql::quotestr($dbname).
		   ($opts->{'charset'} ?
		    " character set $_[2]->{'charset'}" : ""));
push(@dbs, $dbname);
$d->{'db_mysql'} = join(" ", @dbs);

# Add db entries for the user for each host
local $pfunc = sub {
	local $tmpl = &get_template($d->{'template'});
	local $h;
	local @hosts = &get_mysql_hosts($d);
	local $user = &mysql_user($d);
	foreach $h (@hosts) {
		&add_db_table($h, $dbname, $user);
		}
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($pfunc);

local $dd = &get_mysql_database_dir($dbname);
if ($tmpl->{'mysql_chgrp'} && $dd) {
	# Set group ownership of database directory, to enforce quotas
	&system_logged("chgrp -R $d->{'group'} ".quotemeta($dd));
	&system_logged("chmod +s ".quotemeta($dd));
	}
&$second_print($text{'setup_done'});
}

# delete_mysql_database(&domain, dbname, ...)
# Remove one or more MySQL database from this domain
sub delete_mysql_database
{
local ($d, @dbnames) = @_;

&require_mysql();
local @dblist = &mysql::list_databases();
&$first_print(&text('delete_mysqldb', join(", ", @dbnames)));
local @dbs = split(/\s+/, $d->{'db_mysql'});
local @missing;
foreach my $db (@dbnames) {
	local $qdb = &quote_mysql_database($db);
	if (&indexof($db, @dblist) >= 0) {
		# Drop the DB
		&mysql::execute_sql_logged($mysql::master_db, "drop database ".
			&mysql::quotestr($db));
		}
	else {
		push(@missing, $db);
		}
	@dbs = grep { $_ ne $db } @dbs;
	}
$d->{'db_mysql'} = join(" ", @dbs);

# Drop permissions
local $dfunc = sub {
	foreach my $db (@dbnames) {
		local $qdb = &quote_mysql_database($db);
		&mysql::execute_sql_logged($mysql::master_db, "delete from db where db = '$db' or db = '$qdb'");
		}
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($dfunc);
if (@missing) {
	&$second_print(&text('delete_mysqlmissing', join(", ", @missing)));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# get_mysql_database_dir(db)
# Returns the directory in which a DB's files are stored, or undef if unknown.
# If MySQL is running remotely, this will always return undef.
sub get_mysql_database_dir
{
local ($db) = @_;
&require_mysql();
return undef if (!-d $mysql::config{'mysql_data'});
return undef if ($mysql::config{'host'} &&
		 $mysql::config{'host'} ne 'localhost' &&
		 &to_ipaddress($mysql::config{'host'}) ne
			&to_ipaddress(&get_system_hostname()));
return "$mysql::config{'mysql_data'}/$db";
}

# get_mysql_hosts(&domain)
# Returns the allowed MySQL hosts for some domain
sub get_mysql_hosts
{
&require_mysql();
local $tmpl = &get_template($_[0]->{'template'});
local @hosts = $tmpl->{'mysql_hosts'} eq "none" ? ( ) :
    split(/\s+/, &substitute_domain_template($tmpl->{'mysql_hosts'}, $_[0]));
@hosts = ( 'localhost' ) if (!@hosts);
if ($mysql::config{'host'} && $mysql::config{'host'} ne 'localhost') {
	# Add this host too, as we are talking to a remote server
	push(@hosts, &get_system_hostname());
	}
return &unique(@hosts);
}

# list_mysql_database_users(&domain, db)
# Returns a list of MySQL users and passwords who can access some database
sub list_mysql_database_users
{
local ($d, $db) = @_;
&require_mysql();
local $qdb = &quote_mysql_database($db);
local $d = &mysql::execute_sql($mysql::master_db, "select user.user,user.password from user,db where db.user = user.user and (db.db = '$db' or db.db = '$qdb')");
local (@rv, %done);
foreach my $u (@{$d->{'data'}}) {
	push(@rv, $u) if (!$done{$u->[0]}++);
	}
return @rv;
}

# list_all_mysql_users()
# Returns a list of all MySQL usernames
sub list_all_mysql_users
{
&require_mysql();
local $d = &mysql::execute_sql($mysql::master_db, "select user from user");
return &unique(map { $_->[0] } @{$d->{'data'}});
}

# create_mysql_database_user(&domain, &dbs, username, password, [mysql-pass])
# Adds one mysql user, who can access multiple databases
sub create_mysql_database_user
{
local ($d, $dbs, $user, $pass, $encpass) = @_;
&require_mysql();
local $myuser = &mysql_username($user);
local @hosts = &get_mysql_hosts($d);
local $qpass = &mysql_escape($pass);
local $h;
local $cfunc = sub {
	foreach $h (@hosts) {
		&mysql::execute_sql_logged($mysql::master_db, "insert into user (host, user, password) values ('$h', '$myuser', ".($encpass ? "'$encpass'" : "$password_func('$qpass')").")");
		local $db;
		foreach $db (@$dbs) {
			&add_db_table($h, $db, $myuser);
			}
		}
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($cfunc);
}

# delete_mysql_database_user(&domain, username)
# Removes one database user and his access to all databases
sub delete_mysql_database_user
{
local ($d, $user) = @_;
&require_mysql();
local $myuser = &mysql_username($user);
local $dfunc = sub {
	&mysql::execute_sql_logged($mysql::master_db, "delete from user where user = '$myuser'");
	&mysql::execute_sql_logged($mysql::master_db, "delete from db where user = '$myuser'");
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($dfunc);
}

# modify_mysql_database_user(&domain, &olddbs, &dbs, oldusername, username,
#			     [password])
# Renames or changes the password for a database user, and his list of allowed
# mysql databases
sub modify_mysql_database_user
{
local ($d, $olddbs, $dbs, $olduser, $user, $pass) = @_;
&require_mysql();
local $myuser = &mysql_username($user);
local $mfunc = sub {
	if ($olduser ne $user) {
		# Change the username
		local $myolduser = &mysql_username($olduser);
		&mysql::execute_sql_logged($mysql::master_db, "update user set user = '$myuser' where user = '$myolduser'");
		&mysql::execute_sql_logged($mysql::master_db, "update db set user = '$myuser' where user = '$myolduser'");
		}
	if (defined($pass)) {
		# Change the password
		local $qpass = &mysql_escape($pass);
		&mysql::execute_sql_logged($mysql::master_db, "update user set password = $password_func('$qpass') where user = '$myuser'");
		}
	if (join(" ", @$dbs) ne join(" ", @$olddbs)) {
		# Update accessible database list
		local @hosts = &get_mysql_hosts($d);
		&mysql::execute_sql_logged($mysql::master_db, "delete from db where user = '$myuser'");
		local $h;
		foreach $h (@hosts) {
			local $db;
			foreach $db (@$dbs) {
				&add_db_table($h, $db, $myuser);
				}
			}
		}
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($mfunc);
}

# list_mysql_tables(database)
# Returns a list of tables in the given database
sub list_mysql_tables
{
&require_mysql();
return &mysql::list_tables($_[0], 1);
}

# get_database_host_mysql()
# Returns the hostname of the server on which MySQL is actually running
sub get_database_host_mysql
{
&require_mysql();
return $mysql::config{'host'} || 'localhost';
}

# sysinfo_mysql()
# Returns the MySQL version
sub sysinfo_mysql
{
&require_mysql();
local $ver = &mysql::get_mysql_version();
return ( [ $text{'sysinfo_mysql'}, $ver ] );
}

sub startstop_mysql
{
local ($typestatus) = @_;
&require_mysql();
return ( ) if (!&mysql::is_mysql_local());	# cannot stop/start remote
local $r = defined($typestatus->{'mysql'}) ?
		$typestatus->{'mysql'} == 1 :
		&mysql::is_mysql_running();
if ($r == 1) {
	return ( { 'status' => 1,
		   'name' => $text{'index_myname'},
		   'desc' => $text{'index_mystop'},
		   'restartdesc' => $text{'index_myrestart'},
		   'longdesc' => $text{'index_mystopdesc'} } );
	}
elsif ($r == 0) {
	return ( { 'status' => 0,
		   'name' => $text{'index_myname'},
		   'desc' => $text{'index_mystart'},
		   'longdesc' => $text{'index_mystartdesc'} } );
	}
else {
	return ( );
	}
}

sub stop_service_mysql
{
&require_mysql();
return &mysql::stop_mysql();
}

sub start_service_mysql
{
&require_mysql();
return &mysql::start_mysql();
}

# quote_mysql_database(name)
# Returns a mysql database name with % and _ characters escaped
sub quote_mysql_database
{
local ($db) = @_;
$db =~ s/_/\\_/g;
$db =~ s/%/\\%/g;
return $db;
}

# show_template_mysql(&tmpl)
# Outputs HTML for editing MySQL related template options
sub show_template_mysql
{
local ($tmpl) = @_;
&require_mysql();

print &ui_table_row(&hlink($text{'tmpl_mysql'}, "template_mysql"),
	&none_def_input("mysql", $tmpl->{'mysql'}, $text{'tmpl_mysqlpat'}, 1,
			0, undef, [ "mysql" ]).
	&ui_textbox("mysql", $tmpl->{'mysql'}, 20));

print &ui_table_row(&hlink($text{'tmpl_mysql_suffix'}, "template_mysql_suffix"),
	&none_def_input("mysql_suffix", $tmpl->{'mysql_suffix'},
		        $text{'tmpl_mysqlpat'}, 0, 0, undef,
			[ "mysql_suffix" ]).
	&ui_textbox("mysql_suffix", $tmpl->{'mysql_suffix'} eq "none" ?
					undef : $tmpl->{'mysql_suffix'}, 20));

print &ui_table_row(&hlink($text{'tmpl_mysql_wild'}, "template_mysql_wild"),
	&none_def_input("mysql_wild", $tmpl->{'mysql_wild'},
			$text{'tmpl_mysqlpat'}, 1, 0, undef,
			[ "mysql_wild" ]).
	&ui_textbox("mysql_wild", $tmpl->{'mysql_wild'}, 20));

print &ui_table_row(&hlink($text{'tmpl_mysql_hosts'}, "template_mysql_hosts"),
	&none_def_input("mysql_hosts", $tmpl->{'mysql_hosts'},
			$text{'tmpl_mysqlh'}, 0, 0, undef,
			[ "mysql_hosts" ]).
	&ui_textbox("mysql_hosts", $tmpl->{'mysql_hosts'} eq "none" ? "" :
					$tmpl->{'mysql_hosts'}, 40));

print &ui_table_row(&hlink($text{'tmpl_mysql_mkdb'}, "template_mysql_mkdb"),
	&ui_radio("mysql_mkdb", $tmpl->{'mysql_mkdb'},
		[ [ 1, $text{'yes'} ], [ 0, $text{'no'} ],
		  ($tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ) )]));

print &ui_table_row(&hlink($text{'tmpl_mysql_nopass'}, "template_mysql_nopass"),
	&ui_radio("mysql_nopass", $tmpl->{'mysql_nopass'},
		[ [ 0, $text{'yes'} ], [ 1, $text{'no'} ],
		  ($tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ) )]));

if (-d $mysql::config{'mysql_data'}) {
	print &ui_table_row(&hlink($text{'tmpl_mysql_chgrp'},
				   "template_mysql_chgrp"),
		&ui_radio("mysql_chgrp", $tmpl->{'mysql_chgrp'},
			[ [ 1, $text{'yes'} ],
			  [ 0, $text{'no'} ],
			  ($tmpl->{'default'} ? ( ) :
				( [ "", $text{'default'} ] ) )]));
	}
}

# parse_template_mysql(&tmpl)
# Updates MySQL related template options from %in
sub parse_template_mysql
{
local ($tmpl) = @_;
&require_mysql();

# Save MySQL-related settings
if ($in{'mysql_mode'} == 1) {
	$tmpl->{'mysql'} = undef;
	}
else {
	$in{'mysql'} =~ /^\S+$/ || &error($text{'tmpl_emysql'});
	$tmpl->{'mysql'} = $in{'mysql'};
	}
if ($in{'mysql_wild_mode'} == 1) {
	$tmpl->{'mysql_wild'} = undef;
	}
else {
	$in{'mysql_wild'} =~ /^\S*$/ || &error($text{'tmpl_emysql_wild'});
	$tmpl->{'mysql_wild'} = $in{'mysql_wild'};
	}
if ($in{'mysql_hosts_mode'} == 0) {
	$tmpl->{'mysql_hosts'} = "none";
	}
elsif ($in{'mysql_hosts_mode'} == 1) {
	$tmpl->{'mysql_hosts'} = undef;
	}
else {
	$in{'mysql_hosts'} =~ /\S/ || &error($text{'tmpl_emysql_hosts'});
	$tmpl->{'mysql_hosts'} = $in{'mysql_hosts'};
	}
if ($in{'mysql_suffix_mode'} == 0) {
	$tmpl->{'mysql_suffix'} = "none";
	}
elsif ($in{'mysql_suffix_mode'} == 1) {
	$tmpl->{'mysql_suffix'} = undef;
	}
else {
	$in{'mysql_suffix'} =~ /\S/ || &error($text{'tmpl_emysql_suffix'});
	$tmpl->{'mysql_suffix'} = $in{'mysql_suffix'};
	}
$tmpl->{'mysql_mkdb'} = $in{'mysql_mkdb'};
$tmpl->{'mysql_nopass'} = $in{'mysql_nopass'};
if (-d $mysql::config{'mysql_data'}) {
	$tmpl->{'mysql_chgrp'} = $in{'mysql_chgrp'};
	}
}

# creation_form_mysql(&domain)
# Returns options for a new mysql database
sub creation_form_mysql
{
&require_mysql();
if ($mysql::mysql_version >= 4.1) {
	return &ui_table_row($text{'database_charset'},
			     &ui_select("mysql_charset", undef,
					[ [ undef, "&lt;$text{'default'}&gt;" ],
					  &mysql::list_character_sets() ]));
	}
}

# creation_parse_mysql(&domain, &in)
# Parse the form generated by creation_form_mysql, and return a structure
# for passing to create_mysql_database
sub creation_parse_mysql
{
local ($d, $in) = @_;
local $opts = { 'charset' => $in->{'mysql_charset'} };
return $opts;
}

# has_mysql_quotas()
# Returns 1 if the filesystem for user quotas includes the MySQL data dir.
# Will never be true when using external quota programs.
sub has_mysql_quotas
{
&require_mysql();
return &has_home_quotas() &&
       $mysql::config{'mysql_data'} &&
       $config{'home_quotas'} &&
       &is_under_directory($config{'home_quotas'},
			   $mysql::config{'mysql_data'});
}

# encrypted_mysql_pass(&domain)
# Returns the encrypted MySQL password for a domain, suitable for use in SQL.
# This can either be a quoted string like 'xxxyyyzzz', or a function call
# like password('smeg')
sub encrypted_mysql_pass
{
local ($d) = @_;
if ($d->{'mysql_enc_pass'}) {
	return "'$d->{'mysql_enc_pass'}'";
	}
else {
	local $qpass = &mysql_escape(&mysql_pass($d));
	return "$password_func('$qpass')";
	}
}

# check_mysql_login(dbname, dbuser, dbpass)
# Tries to login to MySQL with the given credentials, returning undef on failure
sub check_mysql_login
{
local ($dbname, $dbuser, $dbpass) = @_;
&require_mysql();
local $main::error_must_die = 1;
local $mysql::mysql_login = $dbuser;
local $mysql::mysql_pass = $dbpass;
eval { &mysql::execute_sql($dbname, "show tables") };
local $err = $@;
if ($err) {
	$err =~ s/\s+at\s+.*\sline//g;
	return $err;
	}
return undef;
}

# execute_for_all_mysql_servers(code)
# Calls some code multiple times, once for each MySQL server on which users
# need to be created or managed.
sub execute_for_all_mysql_servers
{
local ($code) = @_;
&require_mysql();
local @repls = split(/\s+/, $config{'mysql_replicas'});
if (!@repls) {
	# Just do for this system
	&$code;
	}
else {
	# Call for this system and all replicas
	local $thishost = $mysql::config{'host'};
	foreach my $host ($thishost, @repls) {
		$mysql::config{'host'} = $host;
		&$code;
		}
	$mysql::config{'host'} = $thishost;
	}
}

$done_feature_script{'mysql'} = 1;

1;

