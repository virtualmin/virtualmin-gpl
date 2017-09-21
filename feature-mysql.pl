sub require_mysql
{
return if ($require_mysql++);
$mysql::use_global_login = 1;
&foreign_require("mysql");
if (!$mysql::config{'login'}) {
	$mysql::config{'login'} = 'root';
	$mysql::mysql_login ||= 'root';
	$mysql::authstr = &mysql::make_authstr();
	}
%mconfig = &foreign_config("mysql");
$password_func = $mysql::password_func || "password";
$mysql_user_size = $config{'mysql_user_size'} || 16;
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

# check_mysql_clash(&domain, [field])
# Returns 1 if some MySQL user or database is used by another domain
sub check_mysql_clash
{
local ($d, $field) = @_;
local @doms = grep { $_->{'mysql'} && $_->{'id'} ne $d->{'id'} }
		   &list_domains();

# Check for DB clash
if (!$field || $field eq 'db') {
	foreach my $od (@doms) {
		foreach my $db (split(/\s+/, $od->{'db_mysql'})) {
			if ($db eq $d->{'db'}) {
				return &text('setup_emysqldbdom', $d->{'db'},
						&show_domain_name($od));
				}
			}
		}
	}

# Check for user clash
if (!$d->{'parent'} && (!$field || $field eq 'user')) {
	foreach my $od (@doms) {
		if (&mysql_user($d) eq &mysql_user($od)) {
			return &text('setup_emysqluserdom', &mysql_user($d),
					&show_domain_name($od));
			}
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
if (!$d->{'mysql_module'}) {
	# Use the default module for this system
	$d->{'mysql_module'} = &get_default_mysql_module();
	}
&require_mysql();
$d->{'mysql_user'} = &mysql_user($d);
local $user = $d->{'mysql_user'};

if ($d->{'provision_mysql'}) {
	# Create the user on provisioning server
	if (!$d->{'parent'}) {
		&$first_print($text{'setup_mysqluser_provision'});
		my $info = { 'user' => $user,
			     'any-host' => '',
			     'domain-owner' => '' };
		if ($d->{'mysql_enc_pass'}) {
			$info->{'encpass'} = $d->{'mysql_enc_pass'};
			}
		else {
			$info->{'pass'} = &mysql_pass($d);
			}
		local @hosts = &unique(map { &to_ipaddress($_) }
				  	   &get_mysql_hosts($d, 2));
		$info->{'remote'} = \@hosts;
		my $conns = &get_mysql_user_connections($d, 0);
		$info->{'conns'} = $conns if ($conns);
		my ($ok, $msg) = &provision_api_call(
			"provision-mysql-login", $info, 0);
		if (!$ok) {
			&$second_print(
				&text('setup_emysqluser_provision', $msg));
			return 0;
			}

		# Find or create a MySQL module for that system
		my $mysql_host = $msg =~ /host=(\S+)/ ? $1 : undef;
		my $mysql_user = $msg =~ /owner_user=(\S+)/ ? $1 : undef;
		my $mysql_pass = $msg =~ /owner_pass=(\S+)/ ? $1 : undef;
		my @mymods = &list_remote_mysql_modules();
		my ($mymod) = grep { $_->{'config'}->{'host'} eq $mysql_host &&
				     $_->{'config'}->{'login'} eq $mysql_user &&
				     $_->{'config'}->{'pass'} eq $mysql_pass }
				   @mymods;
		if (!$mymod) {
			# Need to set one up
			$mymod = { 'minfo' => { },
				   'config' => {
					'host' => $mysql_host,
					'login' => $mysql_user,
					'pass' => $mysql_pass,
					'virtualmin_provision' => $d->{'id'},
					},
				 };
			&create_remote_mysql_module($mymod);
			}
		$d->{'mysql_module'} = $mymod->{'minfo'}->{'dir'};

		&$second_print(&text('setup_mysqluser_provisioned',
				     $mysql_host));
		}
	}
else {
	# Create the user
	local @hosts = &get_mysql_hosts($d, 1);
	if (&indexof("%", @hosts) >= 0 &&
	    &indexof("localhost", @hosts) < 0 &&
	    &indexof("127.0.0.1", @hosts) < 0) {
		# Always add localhost if % was allowed
		push(@hosts, "localhost");
		}
	local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $d);
	if (!$d->{'parent'}) {
		&$first_print($text{'setup_mysqluser'});
		local $cfunc = sub {
			local $encpass = &encrypted_mysql_pass($d);
			foreach my $h (@hosts) {
				&execute_dom_sql($d, $mysql::master_db,
				    "delete from user where host = '$h' ".
				    "and user = '$user'");
				&execute_user_creation_sql($d, $h, $user,
							   $encpass);
				if ($wild && $wild ne $d->{'db'}) {
					&add_db_table($d, $h, $wild, $user);
					}
				&set_mysql_user_connections($d, $h, $user, 0);
				}
			&execute_dom_sql(
				$d, $mysql::master_db, 'flush privileges');
			};
		&execute_for_all_mysql_servers($cfunc);
		&$second_print($text{'setup_done'});
		}
	}

# Create the initial DB (if requested)
local $ok;
if (!$nodb && $tmpl->{'mysql_mkdb'} && !$d->{'no_mysql_db'}) {
	local $opts = &default_mysql_creation_opts($d);
	$ok = &create_mysql_database($d, $d->{'db'}, $opts);
	if (!$ok) {
		# Failed, but instread of marking this whole feature as failed,
		# just record that there was no DB
		$d->{'db_mysql'} = "";
		$ok = 1;
		}
	}
else {
	# No DBs can exist
	$ok = 1;
	$d->{'db_mysql'} = "";
	}

# Save the initial password
if ($tmpl->{'mysql_nopass'}) {
	&set_mysql_pass($d, &mysql_pass($d, 1));
	}

return $ok;
}

# add_db_table(&domain, host, db, user)
# Adds an entry to the db table, with all permission columns set to Y
sub add_db_table
{
local ($d, $host, $db, $user) = @_;
local @str = &mysql::table_structure($mysql::master_db, 'db');
local ($s, @fields, @yeses);
foreach $s (@str) {
	if ($s->{'field'} =~ /_priv$/i) {
		push(@fields, $s->{'field'});
		push(@yeses, "'Y'");
		}
	}
local $qdb = &quote_mysql_database($db);
&execute_dom_sql($d, $mysql::master_db, "delete from db where host = '$host' and db = '$qdb' and user = '$user'");
&execute_dom_sql($d, $mysql::master_db, "insert into db (host, db, user, ".join(", ", @fields).") values ('$host', '$qdb', '$user', ".join(", ", @yeses).")");
}

# delete_mysql(&domain, [preserve-remote])
# Delete mysql databases, the domain's mysql user and all permissions for both
sub delete_mysql
{
local ($d, $preserve) = @_;
&require_mysql();
my @dblist = &unique(split(/\s+/, $d->{'db_mysql'}));
my $mymod = &get_domain_mysql_module($d);

# If MySQL is hosted remotely, don't delete the DB on the assumption that
# other servers sharing the DB will still be using it
if ($preserve && &remote_mysql($d)) {
	&$first_print(&text('delete_mysqldb', join(" ", @dblist)));
	&$second_print(&text('delete_mysqlpreserve',
			     $mymod->{'config'}->{'host'}));
	return 1;
	}

# Get the domain's users, so we can remove their MySQL logins
local @users = &list_domain_users($d, 1, 1, 1, 0);

# First remove the databases
if ($d->{'db_mysql'}) {
	&delete_mysql_database($d, @dblist);
	}

if ($d->{'provision_mysql'}) {
	# Remove the main user on the provisioning server
	if (!$d->{'parent'}) {
		&$first_print($text{'delete_mysqluser_provision'});
		my $info = { 'user' => &mysql_user($d),
			     'host' => $mymod->{'config'}->{'host'} };
		my ($ok, $msg) = &provision_api_call(
			"unprovision-mysql-login", $info, 0);
		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print(&text('delete_emysqluser_provision',
					     $msg));
			return 0;
			}
		}

	# Take away access from mailbox users
	foreach my $u (@users) {
		my @mydbs = grep { $_->{'type'} eq 'mysql' } @{$u->{'dbs'}};
		if (@mydbs) {
			&delete_mysql_database_user($d, $u->{'user'});
			}
		}

	my @mdoms = grep { $_->{'mysql'} &&
			   $_->{'id'} ne $d->{'id'} &&
			   ($_->{'mysql_module'} || 'mysql') eq
				$mymod->{'minfo'}->{'dir'} }
			 &list_domains();
	if ($mymod->{'minfo'}->{'dir'} eq 'mysql') {
		# If this was the last domain with MySQL enabled on the system,
		# turn off use of the remote host that if it gets enabled
		# again, new host and login are used
		if (!@mdoms && $mysql::config{'host'}) {
			delete($mysql::config{'host'});
			$mysql::authstr = &mysql::make_authstr();
			&mysql::save_module_config(\%mysql::config, 'mysql');
			}
		}
	else {
		# If this was the last domain that used the remote module,
		# remove it
		if (!@mdoms && $mymod->{'config'}->{'virtualmin_provision'}) {
			&delete_remote_mysql_module($mymod);
			}
		}

	# Remove record of remote MySQL host, so that it isn't re-used if
	# setup without Cloudmin Services later
	delete($d->{'mysql_module'});
	if (!$d->{'parent'}) {
		foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
			delete($sd->{'mysql_module'});
			&save_domain($sd);
			}
		}
	}
else {
	# Remove the main user locally
	&$first_print($text{'delete_mysqluser'}) if (!$d->{'parent'});
	local $dfunc = sub { 
		local $user = &mysql_user($d);
		local $tmpl = &get_template($d->{'template'});
		local $wild = &substitute_domain_template(
				$tmpl->{'mysql_wild'}, $d);
		if (!$d->{'parent'}) {
			# Delete the user and any database permissions
			&execute_dom_sql($d, $mysql::master_db,
				"delete from user where user = '$user'");
			&execute_dom_sql($d, $mysql::master_db,
				"delete from db where user = '$user'");
			}
		if ($wild && $wild ne $d->{'db'}) {
			# Remove any wildcard entry for the user
			&execute_dom_sql($d, $mysql::master_db,
				"delete from db where db = '$wild'");
			}
		# Remove any other users. This has to be done here, as when
		# users in the domain are deleted they won't be able to find
		# their database privileges anymore.
		foreach my $u (@users) {
			foreach my $udb (@{$u->{'dbs'}}) {
				if ($udb->{'type'} eq 'mysql') {
					local $myuser =
						&mysql_username($u->{'user'});
					&execute_dom_sql(
					    $d, $mysql::master_db,
					    "delete from user where user = ?",
					    $myuser);
					&execute_dom_sql(
					    $d, $mysql::master_db,
					    "delete from db where user = ?",
					    $myuser);
					}
				}
			}
		&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($dfunc);
	&$second_print($text{'setup_done'}) if (!$d->{'parent'});
	}
return 1;
}

# modify_mysql(&domain, &olddomain)
# Changes the mysql user's password if needed
sub modify_mysql
{
local ($d, $oldd) = @_;
local $tmpl = &get_template($d->{'template'});
&require_mysql();
my $mymod = &get_domain_mysql_module($d);
local $rv = 0;
local $changeduser = $d->{'user'} ne $oldd->{'user'} &&
		     !$tmpl->{'mysql_nouser'} ? 1 : 0;
local $olduser = &mysql_user($oldd);
local $user = &mysql_user($d, $changeduser);
local $oldencpass = &encrypted_mysql_pass($oldd);
local $encpass = &encrypted_mysql_pass($d);
local @dbnames = map { $_->{'name'} } &domain_databases($d, [ "mysql" ]);

if ($encpass ne $oldencpass && !$d->{'parent'} && !$oldd->{'parent'} &&
    (!$tmpl->{'mysql_nopass'} || $d->{'mysql_pass'})) {
	# Change MySQL password, for a top-level server that isn't being
	# converted from a sub-server
	if ($d->{'provision_mysql'}) {
		# Change on provisioning server
		&$first_print($text{'save_mysqlpass_provision'});
		my $info = { 'user' => &mysql_user($d),
			     'host' => $mymod->{'config'}->{'host'} };
		if ($d->{'mysql_enc_pass'}) {
			$info->{'encpass'} = $d->{'mysql_enc_pass'};
			}
		else {
			$info->{'pass'} = &mysql_pass($d);
			}
		my ($ok, $msg) = &provision_api_call("modify-mysql-login",
						     $info, 0);
		if (!$ok) {
			&$second_print(&text('save_emysqlpass_provision',$msg));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		$rv++;
		}
	else {
		# Change locally
		&$first_print($text{'save_mysqlpass'});
		if (&mysql_user_exists($d)) {
			local $pfunc = sub {
				&execute_password_change_sql(
					$d, $olduser, $encpass);
				};
			&execute_for_all_mysql_servers($pfunc);
			&$second_print($text{'setup_done'});
			$rv++;
			}
		else {
			&$second_print($text{'save_nomysql'});
			}
		}
	}
if (!$d->{'parent'} && $oldd->{'parent'}) {
	# Server has been converted to a parent .. need to create user, and
	# change access to old DBs
	$d->{'mysql_user'} = &mysql_user($d, 1);
	local $user = $d->{'mysql_user'};
	local @hosts = &get_mysql_hosts($d);

	# If hashed passwords are in use, generate a random MySQL password
	# for the new MySQL user
	if ($tmpl->{'hashpass'}) {
		$d->{'mysql_pass'} = &random_password(8);
		delete($d->{'mysql_enc_pass'});
		}

	if ($d->{'provision_mysql'}) {
		# Change on provisioning server .. first create new user
		&$first_print($text{'setup_mysqluser_provision'});
		my $info = { 'user' => $user,
			     'domain-owner' => '' };
		if ($d->{'mysql_enc_pass'}) {
			$info->{'encpass'} = $d->{'mysql_enc_pass'};
			}
		else {
			$info->{'pass'} = &mysql_pass($d);
			}
		local @hosts = map { &to_ipaddress($_) } @hosts;
		$info->{'remote'} = \@hosts;
		my $conns = &get_mysql_user_connections($d, 0);
		$info->{'conns'} = $conns if ($conns);
		my ($ok, $msg) = &provision_api_call(
			"provision-mysql-login", $info, 0);
		if (!$ok) {
			&$second_print(
				&text('setup_emysqluser_provision', $msg));
			}

		# Then take away DBs from old user
		if ($ok && @dbnames) {
			my $info = { 'user' => $olduser,
				     'host' => $mymod->{'config'}->{'host'},
				     'remove-database' => \@dbnames };
			($ok, $msg) = &provision_api_call(
				"modify-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser2_provision', $msg));
				}
			}

		# Grant to new user
		if ($ok && @dbnames) {
			my $info = { 'user' => $user,
				     'host' => $mymod->{'config'}->{'host'},
				     'add-database' => \@dbnames };
			($ok, $msg) = &provision_api_call(
				"modify-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser2_provision2', $msg));
				}
			}

		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		}
	else {
		# Change locally
		&$first_print($text{'setup_mysqluser'});
		local $wild = &substitute_domain_template(
				$tmpl->{'mysql_wild'}, $d);
		local $encpass = &encrypted_mysql_pass($d);
		local $pfunc = sub {
			local $h;
			foreach $h (@hosts) {
				&execute_user_creation_sql($d, $h, $user,
							   $encpass);
				if ($wild && $wild ne $d->{'db'}) {
					&add_db_table($d, $h, $wild, $user);
					}
				&set_mysql_user_connections($d, $h, $user, 0);
				}
			foreach my $db (@dbnames) {
				local $qdb = &quote_mysql_database($db);
				&execute_dom_sql($d, $mysql::master_db,
				  "update db set user = ? where user = ? and ".
				  "(db = ? or db = ?)",
				  $user, $olduser, $db, $qdb);
				}
			&execute_dom_sql($d, $mysql::master_db,
					 'flush privileges');
			};
		&execute_for_all_mysql_servers($pfunc);
		&$second_print($text{'setup_done'});
		}
	$rv++;
	}
elsif ($d->{'parent'} && !$oldd->{'parent'}) {
	# Server has changed from parent to sub-server .. need to remove the
	# old user and update all DB permissions
	if ($d->{'provision_mysql'}) {
		# Update on provisioning server .. first remove ownership
		# of all DBs
		&$first_print($text{'save_mysqluser_provision'});
		my ($ok, $msg) = (1, undef);
		if (@dbnames) {
			my $info = { 'user' => $olduser,
				     'host' => $mymod->{'config'}->{'host'},
				     'remove-database' => \@dbnames };
			($ok, $msg) = &provision_api_call(
				"modify-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser2_provision', $msg));
				}
			}

		# Then remove the user
		if ($ok && $mysql::config{'host'}) {
			my $info = { 'user' => $olduser,
				     'host' => $mymod->{'config'}->{'host'} };
			($ok, $msg) = &provision_api_call(
				"unprovision-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser_provision',$msg));
				}
			}

		# Then grant DBs to new user
		if ($ok && @dbnames) {
			my $info = { 'user' => $user,
				     'host' => $mymod->{'config'}->{'host'},
				     'add-database' => \@dbnames };
			($ok, $msg) = &provision_api_call(
				"modify-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser2_provision2', $msg));
				}
			}

		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		}
	else {
		# Update locally
		&$first_print($text{'save_mysqluser'});
		local $pfunc = sub {
			&execute_dom_sql($d, $mysql::master_db,
				"delete from user where user = ?", $olduser);
			&execute_dom_sql($d, $mysql::master_db,
				"update db set user = ? where user = ?",
				$user, $olduser);
			&execute_dom_sql($d, $mysql::master_db,
				'flush privileges');
			};
		&execute_for_all_mysql_servers($pfunc);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	}
elsif ($user ne $olduser && !$d->{'parent'}) {
	# MySQL user in a parent domain has changed, perhaps due to username
	# change. Need to update user in DB and all db entries
	if ($d->{'provision_mysql'}) {
		# Rename on provisioning server
		&$first_print($text{'save_mysqluser_provision'});
		my $info = { 'user' => $olduser,
			     'host' => $mymod->{'config'}->{'host'},
			     'new-user' => $user };
		my ($ok, $msg) = &provision_api_call(
			"modify-mysql-login", $info, 0);
		if (!$ok) {
			&$second_print(&text('save_emysqluser_provision',$msg));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		$rv++;
		}
	else {
		# Rename locally
		&$first_print($text{'save_mysqluser'});
		if (&mysql_user_exists($oldd)) {
			$d->{'mysql_user'} = $user;
			local $pfunc = sub {
				&execute_dom_sql($d, $mysql::master_db,
				  "update user set user = ? where user = ?",
				  $user, $olduser);
				&execute_dom_sql($d, $mysql::master_db,
				  "update db set user = ? where user = ?",
				  $user, $olduser);
				&execute_dom_sql($d, mysql::master_db,
				  "flush privileges");
				};
			&execute_for_all_mysql_servers($pfunc);
			&$second_print($text{'setup_done'});
			$rv++;
			}
		else {
			&$second_print($text{'save_nomysql'});
			}
		}
	}
elsif ($user ne $olduser && $d->{'parent'} && @dbnames) {
	# Sub-server has moved to a new user .. change ownership of DBs
	if ($d->{'provision_mysql'}) {
		# Change on provisioning server, by removing DBs from the old
		# owner's list, and added to new owner's list
		&$first_print($text{'save_mysqluser2_provision'});
		my $info = { 'user' => $olduser,
			     'host' => $mymod->{'config'}->{'host'},
			     'remove-database' => \@dbnames };
		my ($ok, $msg) = &provision_api_call(
			"modify-mysql-login", $info, 0);
		if (!$ok) {
			&$second_print(
				&text('save_emysqluser2_provision', $msg));
			}
		else {
			# Add databases back to the new owner
			my $info = { 'user' => $user,
				     'host' => $mymod->{'config'}->{'host'},
				     'add-database' => \@dbnames };
			my ($ok, $msg) = &provision_api_call(
				"modify-mysql-login", $info, 0);
			if (!$ok) {
				&$second_print(
				    &text('save_emysqluser2_provision2', $msg));
				}
			else {
				&$second_print($text{'setup_done'});
				}
			}
		$rv++;
		}
	else {
		# Change locally
		&$first_print($text{'save_mysqluser2'});
		local $pfunc = sub {
			foreach my $db (@dbnames) {
				local $qdb = &quote_mysql_database($db);
				&execute_dom_sql($d, $mysql::master_db,
				    "update db set user = ? where user = ? ".
				    "and (db = ? or db = ?)",
				    $user, $olduser, $db, $qdb);
				}
			&execute_dom_sql($d, $mysql::master_db,
				'flush privileges');
			};
		&execute_for_all_mysql_servers($pfunc);
		$rv++;
		&$second_print($text{'setup_done'});
		}
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

# clone_mysql(&domain, &old-domain)
# Copy all databases and their contents to a new domain
sub clone_mysql
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_mysql'});

# Re-create each DB with a new name
local %dbmap;
my @dbs = &domain_databases($oldd, [ 'mysql' ]);
foreach my $db (@dbs) {
	local $newname = $db->{'name'};
	local $newprefix = &fix_database_name($d->{'prefix'}, 'mysql');
	local $oldprefix = &fix_database_name($oldd->{'prefix'}, 'mysql');
	if ($newname eq $oldd->{'db'} &&
	    $oldd->{'db'} eq &database_name($oldd)) {
		# If the DB name was the primary database for the old domain,
		# set the new DB name to be the primary database for the new
		# domain
		$newname = $d->{'db'};
		}
	elsif ($newname !~ s/\Q$oldprefix\E/$newprefix/) {
		# Otherwise, just replace the DB name prefix. If that isn't
		# possible, prepend the new prefix as a last resort or just
		# use the new prefix if this is the only database in the domain
		&$second_print(&text('clone_mysqlprefix', $newname,
				     $oldprefix, $newprefix));
		if (@dbs == 1 && !&check_mysql_database_clash($d, $newprefix)) {
			# This domain has only one database, so we can just use
			# the new prefix directly (as long as it doesn't clash)
			$newname = $newprefix;
			}
		else {
			# Prepend new prefix
			$newname = $newprefix.$newname;
			}
		&$second_print(&text('clone_mysqlprefix2', $newname));
		}
	if (&check_mysql_database_clash($d, $newname)) {
		&$second_print(&text('clone_mysqlclash', $newname));
		next;
		}
	&push_all_print();
	&set_all_null_print();
	local $opts = &get_mysql_creation_opts($oldd, $db->{'name'});
	local $ok = &create_mysql_database($d, $newname, $opts);
	&pop_all_print();
	if (!$ok) {
		&$second_print(&text('clone_mysqlcreate', $newname));
		}
	else {
		$dbmap{$newname} = $db->{'name'};
		}
	}
&$second_print(&text('clone_mysqldone', scalar(keys %dbmap)));

# Copy across contents
if (%dbmap) {
	&require_mysql();
	&$first_print($text{'clone_mysqlcopy'});
	foreach my $db (&domain_databases($d, [ 'mysql' ])) {
		local $oldname = $dbmap{$db->{'name'}};
		local $temp = &transname();
		local $mymod = &require_dom_mysql($oldd);
		local $err = &foreign_call(
			$mymod, "backup_database", $oldname, $temp, 0, 1, 0,
			undef, undef, undef, undef, 1);
		if ($err) {
			&$second_print(&text('clone_mysqlbackup',
					     $oldname, $err));
			next;
			}
		local ($ex, $out) = &execute_dom_sql_file($d, $db->{'name'},
							  $temp);
		&unlink_file($temp);
		if ($ex) {
			&$second_print(&text('clone_mysqlrestore',
					     $db->{'name'}, $out));
			next;
			}
		}
	&$second_print($text{'setup_done'});
	}

if (!$d->{'parent'}) {
	# Duplicate allowed hosts
	local @allowed = &get_mysql_allowed_hosts($oldd);
	&save_mysql_allowed_hosts($d, \@allowed);
	}
}

# validate_mysql(&domain)
# Make sure all MySQL databases exist, and that the admin user exists
sub validate_mysql
{
local ($d) = @_;
my $mymod = &get_domain_mysql_module($d);
&require_mysql();
if ($d->{'provision_mysql'}) {
	# Check login on provisioning server
	my ($ok, $msg) = &provision_api_call(
		"check-mysql-login", { 'user' => &mysql_user($d) });
	if (!$ok) {
		return &text('validate_emysqlcheck', $msg);
		}
	elsif ($msg !~ /host=(\S+)/) {
		return &text('validate_emysqluser', &mysql_user($d));
		}
	elsif ($1 ne $mymod->{'config'}->{'host'}) {
		return &text('validate_emysqluserhost',
			     $1, $mymod->{'config'}->{'host'});
		}

	# Check DBs on provisioning server
	foreach my $db (&domain_databases($d, [ "mysql" ])) {
		my ($ok, $msg) = &provision_api_call(
		    "check-mysql-database", { 'database' => $db->{'name'} });
		if (!$ok) {
			return &text('validate_emysqlcheck',
				     $db->{'name'}, $msg);
			}
		elsif ($msg !~ /host=(\S+)/) {
			return &text('validate_emysql', $db->{'name'});
			}
		}
	}
else {
	# Check locally
	local %got = map { $_, 1 } &list_dom_mysql_databases($d);
	foreach my $db (&domain_databases($d, [ "mysql" ])) {
		$got{$db->{'name'}} ||
			return &text('validate_emysql', $db->{'name'});
		}
	if (!&mysql_user_exists($d)) {
		return &text('validate_emysqluser', &mysql_user($d));
		}
	}
return undef;
}

# disable_mysql(&domain)
# Modifies the mysql user for this domain so that he cannot login
sub disable_mysql
{
local ($d) = @_;
&require_mysql();
if ($d->{'parent'}) {
	&$second_print($text{'save_nomysqlpar'});
	}
elsif ($d->{'provision_mysql'}) {
	# Lock on provisioning server
	&$first_print($text{'disable_mysqluser_provision'});
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => &mysql_user($d),
		     'host' => $mymod->{'config'}->{'host'},
		     'lock' => '' };
	my ($ok, $msg) = &provision_api_call("modify-mysql-login", $info, 0);
	if (!$ok) {
		&$second_print(&text('disable_emysqluser_provision', $msg));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		return 1;
		}
	}
else {
	# Lock locally
	&$first_print($text{'disable_mysqluser'});
	local $user = &mysql_user($d);
	if ($oldpass = &mysql_user_exists($d)) {
		local $dfunc = sub {
			&execute_password_change_sql(
				$d, $user, "'".("0" x 41)."'");
			};
		&execute_for_all_mysql_servers($dfunc);
		$d->{'disabled_oldmysql'} = $oldpass;
		&$second_print($text{'setup_done'});
		return 1;
		}
	else {
		&$second_print($text{'save_nomysql'});
		return 0;
		}
	}
}

# enable_mysql(&domain)
# Puts back the original password for the mysql user so that he can login again
sub enable_mysql
{
local ($d) = @_;
&require_mysql();
if ($d->{'parent'}) {
	&$second_print($text{'save_nomysqlpar'});
	return 0;
	}
elsif ($d->{'provision_mysql'}) {
	# Unlock on provisioning server
	&$first_print($text{'enable_mysql_provision'});
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => &mysql_user($d),
		     'host' => $mymod->{'config'}->{'host'},
		     'unlock' => '' };
	my ($ok, $msg) = &provision_api_call(
		"modify-mysql-login", $info, 0);
	if (!$ok) {
		&$second_print(&text('enable_emysql_provision', $msg));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		return 1;
		}
	}
else {
	# Un-lock locally
	&$first_print($text{'enable_mysql'});
	local $user = &mysql_user($d);
	if (&mysql_user_exists($d)) {
		local $efunc = sub {
			if ($d->{'disabled_oldmysql'}) {
				local $qpass = &mysql_escape(
					$d->{'disabled_oldmysql'});
				&execute_password_change_sql(
					$d, $user, "'$qpass'");
				}
			else {
				local $pass = &mysql_pass($d);
				local $qpass = &mysql_escape($pass);
				&execute_password_change_sql(
					$d, $user, "$password_func('$qpass')");
				}
			&execute_dom_sql($d, $mysql::master_db,
					 'flush privileges');
			};
		&execute_for_all_mysql_servers($efunc);
		delete($d->{'disabled_oldmysql'});
		&$second_print($text{'setup_done'});
		return 1;
		}
	else {
		&$second_print($text{'save_nomysql'});
		return 0;
		}
	}
}

# mysql_user_exists(&domain)
# Returns his password if a mysql user exists for the domain's user, or undef
sub mysql_user_exists
{
my ($d) = @_;
&require_mysql();
local $user = &mysql_user($d);
local $u;
eval {
	# Try old password column first
	local $main::error_must_die = 1;
	$u = &execute_dom_sql($d, $mysql::master_db,
		"select password from user where user = ?", $user);
	};
if ($@ || @{$u->{'data'}} && $u->{'data'}->[0]->[0] eq '') {
	# Try new mysql user table format if the password query failed, or
	# if there was no password
	eval {
		local $main::error_must_die = 1;
		$u = &execute_dom_sql($d, $mysql::master_db,
			"select authentication_string from user where user = ?", $user);
		};
	}
foreach my $r (@{$u->{'data'}}) {
	return $r->[0] if ($r->[0]);
	}
return undef;
}

# check_warnings_mysql(&dom, &old-domain)
# Return warning if a MySQL database or user with a clashing name exists.
# This can be overridden to allow a takeover of the DB.
sub check_warnings_mysql
{
local ($d, $oldd) = @_;
$d->{'mysql'} && (!$oldd || !$oldd->{'mysql'}) || return undef;
if ($d->{'provision_mysql'}) {
	# DB clash on provisioning server
	my ($ok, $msg) = &provision_api_call(
		"check-mysql-database", { 'database' => $d->{'db'} });
	return &text('provision_emysqldbcheck', $msg) if (!$ok);
	if ($msg =~ /host=/) {
		return &text('provision_emysqldb', $d->{'db'});
		}

	# User clash on provisioning server
	if (!$d->{'parent'}) {
		my ($ok, $msg) = &provision_api_call(
			"check-mysql-login", { 'user' => &mysql_user($d) });
		return &text('provision_emysqlcheck', $msg) if (!$ok);
		if ($msg =~ /host=/) {
			return &text('provision_emysql', &mysql_user($d));
			}
		}
	}
else {
	# DB clash on local
	&require_mysql();
	local @dblist = &list_dom_mysql_databases($d);
	return &text('setup_emysqldb', $d->{'db'})
		if (&indexof($d->{'db'}, @dblist) >= 0);

	# User clash on local
	if (!$d->{'parent'}) {
		return &text('setup_emysqluser', &mysql_user($d))
			if (&mysql_user_exists($d));
		}
	}
return undef;
}

# backup_mysql(&domain, file)
# Dumps this domain's mysql database to a backup file
sub backup_mysql
{
local ($d, $file) = @_;
&require_mysql();

# Find all domain's databases
local $tmpl = &get_template($d->{'template'});
local $wild = &substitute_domain_template($tmpl->{'mysql_wild'}, $d);
local @alldbs = &list_all_mysql_databases($d);
local @dbs;
if ($wild) {
	$wild =~ s/\%/\.\*/g;
	$wild =~ s/_/\./g;
	@dbs = grep { /^$wild$/i } @alldbs;
	}
push(@dbs, split(/\s+/, $d->{'db_mysql'}));
@dbs = &unique(@dbs);

# Filter out any excluded DBs
my @exclude = &get_backup_db_excludes($d);
my %exclude = map { $_, 1 } @exclude;
@dbs = grep { !$exclude{$_} } @dbs;

# Create base backup file with meta-information
local @hosts = &get_mysql_allowed_hosts($d);
my $mymod = &get_domain_mysql_module($d);
local %info = ( 'hosts' => join(' ', @hosts),
		'remote' => $mymod->{'config'}->{'host'} );
&write_as_domain_user($d, sub { &write_file($file, \%info) });

# Back them all up
local $db;
local $ok = 1;
foreach $db (@dbs) {
	&$first_print(&text('backup_mysqldump', $db));
	local $dbfile = $file."_".$db;

	# Limit tables to those that aren't excluded
	my %texclude = map { $_, 1 }
			 map { (split(/\./, $_))[1] }
			   grep { /^\Q$db\E\./ || /^\*\./ } @exclude;
	my $tables;
	if (%texclude) {
		$tables = [ grep { !$texclude{$_} }
				 &list_dom_mysql_tables($d, $db) ];
		}

	my $mymod = &require_dom_mysql($d);
	local $err = &foreign_call(
		$mymod, "backup_database", $db, $dbfile, 0, 1, undef,
		undef, undef, $tables, $d->{'user'}, 1);
	if (!$err) {
		$err = &validate_mysql_backup($dbfile);
		}
	if ($err) {
		&$second_print(&text('backup_mysqldumpfailed',
				     "<pre>$err</pre>"));
		$ok = 0;
		}
	elsif ($config{'gzip_mysql'}) {
		# Backup worked .. gzip the file
		unlink($dbfile.".gz");	# Prevent malicious symlink
		my $out = &backquote_logged(
				"gzip ".quotemeta($dbfile)." 2>&1");
		if ($?) {
			&$second_print(&text('backup_mysqlgzipfailed',
					     "<pre>$out</pre>"));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	else {
		# No need to compress
		&$second_print($text{'setup_done'});
		}
	}
return $ok;
}

# restore_mysql(&domain, file,  &opts, &allopts, homeformat, &oldd, asowner)
# Restores this domain's mysql database from a backup file, and re-creates
# the mysql user.
sub restore_mysql
{
local ($d, $file, $opts, $allopts, $homefmt, $oldd, $asd) = @_;
local %info;
&read_file($file, \%info);
&require_mysql();

# Re-grant allowed hosts from backup + local
local @lhosts;
if (!$d->{'parent'} && $info{'hosts'}) {
	&$first_print($text{'restore_mysqlgrant'});
	@lhosts = &get_mysql_allowed_hosts($d);
	push(@lhosts, split(/\s+/, $info{'hosts'}));
	if (&indexof("%", @lhosts) >= 0 &&
	    &indexof("localhost", @lhosts) < 0 &&
	    &indexof("127.0.0.1", @lhosts) < 0) {
		# If all hosts were allowed previously via % but localhost was
		# not, add it now. This is needed because some MySQL versions
		# (such as the one seen on Ubuntu 12.04) do not allow localhost
		# connections even if % is granted
		push(@lhosts, "localhost");
		}
	@lhosts = &unique(@lhosts);
	my $err = &save_mysql_allowed_hosts($d, \@lhosts);
	if ($err) {
		&$second_print(&text('restore_emysqlgrant', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# If in replication mode, AND the remote MySQL system is the same on both
# systems, do nothing
my $mymod = &get_domain_mysql_module($d);
if ($allopts->{'repl'} && $mymod->{'config'}->{'host'} && $info{'remote'} &&
    $mymod->{'config'}->{'host'} eq $info{'remote'}) {
	&$first_print($text{'restore_mysqldummy'});
	&$second_print(&text('restore_mysqlsameremote', $info{'remote'}));
	return 1;
	}

# For DBs that exist already, save their user lists for later restore
local (%userdbs, %userpasses);
foreach my $db (&domain_databases($d, [ 'mysql' ])) {
	foreach my $u (&list_mysql_database_users($d, $db->{'name'})) {
		if ($u->[0] ne $d->{'user'} &&
		    $u->[0] ne 'root' &&
		    $u->[0] ne $mymod->{'config'}->{'login'}) {
			push(@{$userdbs{$u->[0]}}, $db->{'name'});
			$userpasses{$u->[0]} = $u->[1];
			}
		}
	}

if (!$d->{'wasmissing'}) {
	# Only delete and re-create databases if this domain was not created
	# as part of the restore process.
	&$first_print($text{'restore_mysqldrop'});
		{
		local $first_print = \&null_print;	# supress messages
		local $second_print = \&null_print;

		# First clear out all current databases and the MySQL login
		&delete_mysql($d);

		# Now re-set up the login only
		&setup_mysql($d, 1);
		}
	&$second_print($text{'setup_done'});
	}

# Re-grant allowed hosts, as deleting and re-creating DBs may have cleared them
if (@lhosts) {
	&save_mysql_allowed_hosts($d, \@lhosts);
	}

# Work out which databases are in backup
local ($dbfile, @dbs);
foreach $dbfile (glob($file."_*")) {
	if (-r $dbfile) {
		$dbfile =~ /\Q$file\E_(.*)\.gz$/ ||
			$dbfile =~ /\Q$file\E_(.*)$/;
		push(@dbs, [ $1, $dbfile ]);
		}
	}

# Turn off quotas for the domain, to prevent the import failing
&disable_quotas($d);

# Finally, import the data
my $rv = 1;
my %created;
foreach my $db (@dbs) {
	my $clash = &check_mysql_database_clash($d, $db->[0]);
	if ($clash && $d->{'wasmissing'}) {
		# DB already exists, silently ignore it if not empty.
		# This can happen during a restore when MySQL is on a remote
		# system.
		my @tables = &list_dom_mysql_tables($d, $db->[0], 1);
		if (@tables) {
			next;
			}
		}
	&$first_print(&text('restore_mysqlload', $db->[0]));
	if ($clash && !$d->{'wasmissing'}) {
		# DB already exists, and this isn't a newly created domain
		&$second_print($text{'restore_mysqlclash'});
		$rv = 0;
		last;
		}
	&$indent_print();
	if (!$clash) {
		&create_mysql_database($d, $db->[0]);
		$created{$db->[0]} = 1;
		}
	&$outdent_print();
	if ($db->[1] =~ /(.*)\.gz$/) {
		# Need to uncompress first
		unlink("$1");	# To prevent malicious link overwrite
		local $out = &backquote_logged(
			"gunzip ".quotemeta($db->[1])." 2>&1");
		if ($?) {
			&$second_print(&text('restore_mysqlgunzipfailed',
					     "<pre>$out</pre>"));
			$rv = 0;
			last;
			}
		$db->[1] =~ s/\.gz$//;
		}
	local ($ex, $out);
	if ($asd) {
		# As the domain owner
		($ex, $out) = &execute_dom_sql_file($d, $db->[0], $db->[1],
				&mysql_user($d), &mysql_pass($d, 1));
		}
	else {
		# As master admin
		($ex, $out) = &execute_dom_sql_file($d, $db->[0], $db->[1]);
		}
	if ($ex) {
		&$second_print(&text('restore_mysqlloadfailed',
				     "<pre>$out</pre>"));
		$rv = 0;
		last;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# If the restore re-created a domain, the list of databases should be synced
# to those in the backup
if ($d->{'wasmissing'}) {
	$d->{'db_mysql'} = join(" ", map { $_->[0] } @dbs);
	}

# Grant back permissions to any users who had access to the restored DBs
# previously
foreach my $uname (keys %userdbs) {
	my @grant = grep { $created{$_} } @{$userdbs{$uname}};
	if (@grant) {
		&create_mysql_database_user($d, \@grant, $uname, undef,
					    $userpasses{$uname});
		}
	}

# Put quotas back
&enable_quotas($d);

return $rv;
}

# validate_mysql_backup(file)
# Returns an error message if a file doesn't look like a valid MySQL backup
sub validate_mysql_backup
{
local ($dbfile) = @_;
open(DBFILE, $dbfile);
local $first = <DBFILE>;
close(DBFILE);
if ($first =~ /^mysqldump:.*error/) {
	return $first;
	}
return undef;
}

# mysql_user(&domain, [always-new])
# Returns the MySQL login name for a domain
sub mysql_user
{
&require_mysql();
if ($_[0]->{'parent'}) {
	# Get from parent domain
	return &mysql_user(&get_domain($_[0]->{'parent'}), $_[1]);
	}
return $_[0]->{'mysql_user'} if (defined($_[0]->{'mysql_user'}) && !$_[1]);
return length($_[0]->{'user'}) > $mysql_user_size ?
	  substr($_[0]->{'user'}, 0, $mysql_user_size) : $_[0]->{'user'};
}

# set_mysql_user(&domain, newuser)
# Updates a domain object with a new MySQL username
sub set_mysql_user
{
&require_mysql();
$_[0]->{'mysql_user'} = length($_[1]) > $mysql_user_size ?
	substr($_[1], 0, $mysql_user_size) : $_[1];
}

# mysql_username(username)
# Adjusts a username to be suitable for MySQL
sub mysql_username
{
&require_mysql();
return length($_[0]) > $mysql_user_size ?
	substr($_[0], 0, $mysql_user_size) : $_[0];
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
my ($d, $dbname, $sizeonly) = @_;
&require_mysql();
local ($size, $qsize);
local $dd = &get_mysql_database_dir($d, $dbname);
if ($dd) {
	# Can check actual on-disk size
	$size = &disk_usage_kb($dd)*1024;
	local @dst = stat($dd);
	if (&has_group_quotas() && &has_mysql_quotas() &&
            $dst[5] == $d->{'gid'}) {
		$qsize = $size;
		}
	}
else {
	# Use 'show table status'
	$size = 0;
	eval {
		local $main::error_must_die = 1;
		my $rv = &execute_dom_sql($d, $dbname, "show table status");
		foreach my $r (@{$rv->{'data'}}) {
			$size += $r->[6];
			}
		};
	}
local @tables;
if (!$sizeonly) {
	eval {
		# Make sure DBI errors don't cause a total failure
		local $main::error_must_die = 1;
		if ($d->{'provision_mysql'}) {
			# Stop supports_views from trying to access the
			# 'mysql' DB
			$mysql::supports_views_cache = 0;
			}
		@tables = &list_dom_mysql_tables($d, $dbname, 1);
		};
	}
return ($size, scalar(@tables), $qsize);
}

# check_mysql_database_clash(&domain, dbname)
# Check if some MySQL database already exists
sub check_mysql_database_clash
{
local ($d, $name) = @_;
&require_mysql();
if ($d->{'provision_mysql'}) {
	# Check on provisioning server
	my ($ok, $msg) = &provision_api_call(
		"check-mysql-database", { 'database' => $name });
	&error(&text('provision_emysqldbcheck', $msg)) if (!$ok);
	return $msg =~ /host=/ ? 1 : 0;
	}
else {
	# Check locally
	local @dblist = &list_dom_mysql_databases($d);
	return &indexof($name, @dblist) >= 0 ? 1 : 0;
	}
}

# create_mysql_database(&domain, dbname, &opts)
# Add one database to this domain, and grants access to it to the user
sub create_mysql_database
{
local ($d, $dbname, $opts) = @_;
&require_mysql();
local @dbs = split(/\s+/, $d->{'db_mysql'});

if ($d->{'provision_mysql'}) {
	# Create the database on the provisioning server
	&$first_print(&text('setup_mysqldb_provision', $dbname));
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => &mysql_user($d),
		     'host' => $mymod->{'config'}->{'host'},
		     'database' => $dbname };
	$info->{'charset'} = $opts->{'charset'} if ($opts->{'charset'});
	$info->{'collate'} = $opts->{'collate'} if ($opts->{'collate'});
	my ($ok, $msg) = &provision_api_call(
		"provision-mysql-database", $info, 0);
	if (!$ok) {
		&$second_print(&text('setup_emysqldb_provision', $msg));
		return 0;
		}
	&$second_print($text{'setup_done'});
	}
else {
	# Create the database locally, unless it already exists
	if (&indexof($dbname, &list_dom_mysql_databases($d)) < 0) {
		&$first_print(&text('setup_mysqldb', $dbname));
		&execute_dom_sql($d, $mysql::master_db,
				 "create database ".&mysql::quotestr($dbname).
				 ($opts->{'charset'} ?
				 " character set $opts->{'charset'}" : "").
				 ($opts->{'collate'} ?
				 " collate $opts->{'collate'}" : ""));
		}
	else {
		&$first_print(&text('setup_mysqldbimport', $dbname));
		}

	# Make the DB accessible to the domain owner
	&grant_mysql_database($d, $dbname);
	&$second_print($text{'setup_done'});
	}
push(@dbs, $dbname);
$d->{'db_mysql'} = join(" ", &unique(@dbs));
return 1;
}

# grant_mysql_database(&domain, dbname)
# Adds MySQL permission entries to grant the domain owner access to some DB,
# and sets file ownership so that quotas work.
sub grant_mysql_database
{
local ($d, $dbname) = @_;
&require_mysql();

if ($d->{'provision_mysql'}) {
	# Call remote API to grant access
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => &mysql_user($d),
		     'host' => $mymod->{'config'}->{'host'},
		     'add-database' => $dbname };
	my ($ok, $msg) = &provision_api_call("modify-mysql-login", $info, 0);
	&error(&text('user_emysqlprov', $msg)) if (!$ok);
	}
else {
	# Add db entries for the user for each host
	local $pfunc = sub {
		local $h;
		local @hosts = &get_mysql_hosts($d);
		local $user = &mysql_user($d);
		foreach $h (@hosts) {
			&add_db_table($d, $h, $dbname, $user);
			}
		&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($pfunc);

	# Set group ownership of database directory, to enforce quotas
	local $dd = &get_mysql_database_dir($d, $dbname);
	local $tmpl = &get_template($d->{'template'});
	if ($tmpl->{'mysql_chgrp'} && $dd) {
		&system_logged("chgrp -R $d->{'group'} ".quotemeta($dd));
		&system_logged("chmod +s ".quotemeta($dd));
		}
	}
}

# delete_mysql_database(&domain, dbname, ...)
# Remove one or more MySQL database from this domain
sub delete_mysql_database
{
local ($d, @dbnames) = @_;
&require_mysql();
local @dbs = split(/\s+/, $d->{'db_mysql'});
local @missing;
local $failed = 0;

if ($d->{'provision_mysql'}) {
	# Delete on provisioning server
	&$first_print(&text('delete_mysqldb_provision', join(", ", @dbnames)));
	my $mymod = &get_domain_mysql_module($d);
	foreach my $db (@dbnames) {
		my $info = { 'database' => $db,
			     'host' => $mymod->{'config'}->{'host'} };
		my ($ok, $msg) = &provision_api_call(
			"unprovision-mysql-database", $info, 0);
		if (!$ok) {
			&$second_print(
				&text('delete_emysqldb_provision', $msg));
			$failed++;
			}
		@dbs = grep { $_ ne $db } @dbs;
		}
	}
else {
	# Delete locally
	local @dblist = &list_dom_mysql_databases($d);
	&$first_print(&text('delete_mysqldb', join(", ", @dbnames)));
	foreach my $db (@dbnames) {
		local $qdb = &quote_mysql_database($db);
		if (&indexof($db, @dblist) >= 0) {
			# Drop the DB
			&execute_dom_sql($d, 
				$mysql::master_db, "drop database ".
				&mysql::quotestr($db));
			if (defined(&mysql::delete_database_backup_job)) {
				&mysql::delete_database_backup_job($db);
				}
			}
		else {
			push(@missing, $db);
			&$second_print(&text('delete_mysqlmissing', $db));
			$failed++;
			}
		@dbs = grep { $_ ne $db } @dbs;
		}

	# Drop permissions
	foreach my $db (@dbnames) {
		&revoke_mysql_database($d, $db);
		}
	}

$d->{'db_mysql'} = join(" ", &unique(@dbs));
if (!$failed) {
	&$second_print($text{'setup_done'});
	}
}

# revoke_mysql_database(&domain, dbname)
# Remove a domain's access to a MySQL database, by delete from the db table.
# Also resets group permissions.
sub revoke_mysql_database
{
local ($d, $dbname) = @_;
&require_mysql();
local @oldusers = &list_mysql_database_users($d, $dbname);
local @users = &list_domain_users($d, 1, 1, 1, 0);
local @unames = ( &mysql_user($d),
		  map { &mysql_username($_->{'user'}) } @users );

# Take away MySQL permissions for users in this domain
local $dfunc = sub {
	local $qdbname = &quote_mysql_database($dbname);
	foreach my $uname (@unames) {
		&execute_dom_sql($d, $mysql::master_db, "delete from db where (db = ? or db = ?) and user = ?", $dbname, $qdbname, $uname);
		}
	&execute_dom_sql($d, $mysql::master_db, "flush privileges");
	};
&execute_for_all_mysql_servers($dfunc);

# If any users had access to this DB only, remove them too
local $dfunc = sub {
	local $duser = &mysql_user($d);
	foreach my $up (grep { $_->[0] ne $duser } @oldusers) {
		local $o = &execute_dom_sql($d, $mysql::master_db, "select user from db where user = '$up->[0]'");
		if (!@{$o->{'data'}}) {
			&execute_dom_sql($d, $mysql::master_db, "delete from user where user = '$up->[0]'");
			}
		}
	&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
	};
&execute_for_all_mysql_servers($dfunc);

# Fix group owner, if the DB still exists, by setting to the owner of the
# 'mysql' database
local $tmpl = &get_template($d->{'template'});
local $dd = &get_mysql_database_dir($d, $dbname);
if ($tmpl->{'mysql_chgrp'} && $dd && -d $dd) {
	local @st = stat("$dd/../mysql");
	local $group = scalar(@st) ? $st[5] : "mysql";
	&system_logged("chgrp -R $group ".quotemeta($dd));
	}
}

# get_mysql_database_dir(&domain, db)
# Returns the directory in which a DB's files are stored, or undef if unknown.
# If MySQL is running remotely, this will always return undef.
sub get_mysql_database_dir
{
local ($d, $db) = @_;
&require_mysql();
return undef if ($d->{'provision_mysql'});
local $mymod = &require_dom_mysql($d);
local %myconfig = &foreign_config($mymod);
return undef if ($myconfig{'host'} &&
		 $myconfig{'host'} ne 'localhost' &&
		 &to_ipaddress($myconfig{'host'}) ne
			&to_ipaddress(&get_system_hostname()));
my $mysql_dir;
my $conf = &foreign_call($mymod, "get_mysql_config");
my ($mysqld) = grep { $_->{'name'} eq 'mysqld' } @$conf;
my $dir;
if ($mysqld) {
	$dir = &foreign_call($mymod, "find_value",
			     "datadir", $mysqld->{'members'});
	}
$dir ||= $myconfig{'mysql_data'};
return undef if (!-d $dir);
local $escdb = $db;
$escdb =~ s/-/\@002d/g;
if (-d "$myconfig{'mysql_data'}/$escdb") {
	return "$myconfig{'mysql_data'}/$escdb";
	}
else {
	return "$myconfig{'mysql_data'}/$db";
	}
}

# get_mysql_hosts(&domain, [always-from-template])
# Returns the allowed MySQL hosts for some domain, to be used when creating.
# Uses hosts the user has currently by default, or those from the template.
# If always-from-template == 1, then hosts already granted will never be used.
# Instead, those from the template will be used.
# If always-from-template == 2, then template hosts will be used AND we will
# assume that we're connecting to a remote system.
sub get_mysql_hosts
{
local ($d, $always) = @_;
&require_mysql();
local @hosts;
if (!$always) {
	@hosts = &get_mysql_allowed_hosts($d);
	}
if (!@hosts) {
	# Fall back to those from template
	local $tmpl = &get_template($d->{'template'});
	@hosts = $tmpl->{'mysql_hosts'} eq "none" ? ( ) :
	    split(/\s+/, &substitute_domain_template(
				$tmpl->{'mysql_hosts'}, $d));
	@hosts = ( 'localhost' ) if (!@hosts);
	local $mymod = &require_dom_mysql($d);
	local %myconfig = &foreign_config($mymod);
	if ($always == 2 ||
	    $myconfig{'host'} && $myconfig{'host'} ne 'localhost') {
		# Add this host too, as we are talking to a remote server
		push(@hosts, &get_system_hostname());
		local $myip = &to_ipaddress(&get_system_hostname());
		push(@hosts, $myip) if ($myip);
		}
	if (&indexof("%", @hosts) >= 0) {
		# All hosts allowed - no need for other entries
		@hosts = ( "%" );
		}
	}
return &unique(@hosts);
}

# list_mysql_database_users(&domain, db)
# Returns a list of MySQL users and passwords who can access some database
sub list_mysql_database_users
{
local ($d, $db) = @_;
&require_mysql();
if ($d->{'provision_mysql'}) {
	# Fetch from provisioning server
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'host' => $mymod->{'config'}->{'host'},
		     'database' => $db };
	my ($ok, $msg) = &provision_api_call(
		"list-provision-mysql-users", $info, 1);
	&error(&text('user_emysqllist', $msg)) if (!$ok);
	my @rv;
	foreach my $u (@$msg) {
		push(@rv, [ $u->{'name'}, $u->{'values'}->{'pass'} ]);
		}
	return @rv;
	}
else {
	# Query local MySQL server
	local $qdb = &quote_mysql_database($db);
	local $rv;
	eval {
		# Try old password column first
		local $main::error_must_die = 1;
		$rv = &execute_dom_sql($d, $mysql::master_db, "select user.user,user.password from user,db where db.user = user.user and (db.db = '$db' or db.db = '$qdb')");
		};
	if ($@ || @{$rv->{'data'}} && $rv->{'data'}->[0]->[1] eq '') {
		# Try new mysql user table format if the password query failed,
		# or if the password was empty
		eval {
			local $main::error_must_die = 1;
			$rv = &execute_dom_sql($d, $mysql::master_db, "select user.user,user.authentication_string from user,db where db.user = user.user and (db.db = '$db' or db.db = '$qdb')");
			};
		}
	local (@rv, %done);
	foreach my $u (@{$rv->{'data'}}) {
		push(@rv, $u) if (!$done{$u->[0]}++);
		}
	return @rv;
	}
}

# check_mysql_user_clash(&domain, username)
# Returns 1 if some user exists on the MySQL server
sub check_mysql_user_clash
{
local ($d, $user) = @_;
&require_mysql();
return 1 if ($user eq 'root');	# Never available
if ($d->{'provision_mysql'}) {
	# Query provisioning server
	my ($ok, $msg) = &provision_api_call(
		"check-mysql-login", { 'user' => $user });
	&error(&text('provision_emysqlcheck', $msg)) if (!$ok);
	return $msg =~ /host=/ ? 1 : 0;
	}
else {
	# Check locally
	local $rv = &execute_dom_sql($d, $mysql::master_db,
		"select user from user where user = ?", $user);
	return @{$rv->{'data'}} ? 1 : 0;
	}
}

# create_mysql_database_user(&domain, &dbs, username, password, [mysql-pass])
# Adds one mysql user, who can access multiple databases
sub create_mysql_database_user
{
local ($d, $dbs, $user, $pass, $encpass) = @_;
&require_mysql();
if ($d->{'provision_mysql'}) {
	# Create on provisioning server
	my $info = { 'user' => $user };
	if ($encpass) {
		$info->{'encpass'} = $encpass;
		}
	else {
		$info->{'pass'} = $pass;
		}
	local @hosts = map { &to_ipaddress($_) } &get_mysql_hosts($d, 2);
	$info->{'remote'} = \@hosts;
	$info->{'database'} = $dbs;
	my $conns = &get_mysql_user_connections($d, 1);
	$info->{'conns'} = $conns if ($conns);
	my ($ok, $msg) = &provision_api_call(
		"provision-mysql-login", $info, 0);
	if (!$ok) {
		&error(&text('setup_emysqluser_provision', $msg));
		}
	}
else {
	# Create locally
	local $myuser = &mysql_username($user);
	local @hosts = &get_mysql_hosts($d);
	local $qpass = &mysql_escape($pass);
	local $h;
	local $cfunc = sub {
		foreach $h (@hosts) {
			&execute_dom_sql($d, $mysql::master_db,
			    "delete from user where host = '$h' ".
			    "and user = '$user'");
			&execute_user_creation_sql($d, $h, $myuser, 
			      $encpass ? "'$encpass'"
				       : "$password_func('$qpass')");
			local $db;
			foreach $db (@$dbs) {
				&add_db_table($d, $h, $db, $myuser);
				}
			&set_mysql_user_connections($d, $h, $myuser, 1);
			}
		&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($cfunc);
	}
}

# delete_mysql_database_user(&domain, username)
# Removes one database user and his access to all databases
sub delete_mysql_database_user
{
local ($d, $user) = @_;
&require_mysql();
local $myuser = &mysql_username($user);
if ($d->{'provision_mysql'}) {
	# Delete on provisioning server
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => $myuser,
		     'host' => $mymod->{'config'}->{'host'} };
	my ($ok, $msg) = &provision_api_call(
		"unprovision-mysql-login", $info, 0);
	&error(&text('user_emysqldelete', $msg)) if (!$ok);
	}
else {
	# Delete locally
	local $dfunc = sub {
		&execute_dom_sql($d, $mysql::master_db,
			"delete from user where user = ?", $myuser);
		&execute_dom_sql($d, $mysql::master_db,
			"delete from db where user = ?", $myuser);
		&execute_dom_sql($d, $mysql::master_db,
			"flush privileges");
		};
	&execute_for_all_mysql_servers($dfunc);
	}
}

# modify_mysql_database_user(&domain, &olddbs, &dbs, oldusername, username,
#			     [password], [encrypted-password])
# Renames or changes the password for a database user, and his list of allowed
# mysql databases
sub modify_mysql_database_user
{
local ($d, $olddbs, $dbs, $olduser, $user, $pass, $encpass) = @_;
&require_mysql();
local $myuser = &mysql_username($user);
	local $myolduser = &mysql_username($olduser);
if ($d->{'provision_mysql'}) {
	# Update on provisioning server
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => $myolduser,
		     'host' => $mymod->{'config'}->{'host'} };
	if ($olduser ne $user) {
		$info->{'new-user'} = $myuser;
		}
	if ($encpass) {
		$info->{'encpass'} = $encpass;
		}
	elsif (defined($pass)) {
		$info->{'pass'} = $pass;
		}
	if (join(" ", @$dbs) ne join(" ", @$olddbs)) {
		$info->{'database'} = join("\0", @$dbs);
		}
	if (keys %$info > 1) {
		my ($ok, $msg) = &provision_api_call(
			"modify-mysql-login", $info, 0);
		&error(&text('user_emysqlprov', $msg)) if (!$ok);
		}
	}
else {
	# Update locally
	local $mfunc = sub {
		if ($olduser ne $user) {
			# Change the username
			&execute_dom_sql($d, $mysql::master_db,
				"update user set user = ? where user = ?",
				$myuser, $myolduser);
			&execute_dom_sql($d, $mysql::master_db,
				"update db set user = ? where user = ?",
				$myuser, $myolduser);
			}
		if (defined($pass)) {
			# Change the password
			if ($encpass) {
				&execute_password_change_sql(
					$d, $myuser, "'$encpass'");
				}
			else {
				local $qpass = &mysql_escape($pass);
				&execute_password_change_sql(
				    $d, $myuser, "$password_func('$qpass')");
				}
			}
		if (join(" ", @$dbs) ne join(" ", @$olddbs)) {
			# Update accessible database list
			local @hosts = &get_mysql_hosts($d);
			&execute_dom_sql($d, $mysql::master_db,
				"delete from db where user = ?", $myuser);
			local $h;
			foreach $h (@hosts) {
				local $db;
				foreach $db (@$dbs) {
					&add_db_table($d, $h, $db, $myuser);
					}
				}
			}
		&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($mfunc);
	}
}

# list_mysql_tables(&domain, database)
# Returns a list of tables in the given database
sub list_mysql_tables
{
my ($d, $db) = @_;
&require_mysql();
return &list_dom_mysql_tables($d, $db, 1);
}

# get_database_host_mysql([&domain])
# Returns the hostname of the server on which MySQL is actually running
sub get_database_host_mysql
{
my ($d) = @_;
my $mymod = &require_dom_mysql($d);
my %myconfig = &foreign_config($mymod);
return $myconfig{'host'} || 'localhost';
}

# sysinfo_mysql()
# Returns the MySQL version
sub sysinfo_mysql
{
&require_mysql();
return ( ) if ($config{'provision_mysql'});
return ( [ $text{'sysinfo_mysql'}, &get_dom_remote_mysql_version() ] );
}

sub startstop_mysql
{
local ($typestatus) = @_;
&require_mysql();
return ( ) if ($config{'provision_mysql'} ||
	       !&mysql::is_mysql_local());	# cannot stop/start remote
local $r = defined($typestatus->{'mysql'}) ?
		$typestatus->{'mysql'} == 1 :
		&mysql::is_mysql_running();
local @links = ( { 'link' => '/mysql/',
		   'desc' => $text{'index_mymanage'},
		   'manage' => 1 } );
if ($r == 1) {
	return ( { 'status' => 1,
		   'name' => $text{'index_myname'},
		   'desc' => $text{'index_mystop'},
		   'restartdesc' => $text{'index_myrestart'},
		   'longdesc' => $text{'index_mystopdesc'},
		   'links' => \@links } );
	}
elsif ($r == 0) {
	return ( { 'status' => 0,
		   'name' => $text{'index_myname'},
		   'desc' => $text{'index_mystart'},
		   'longdesc' => $text{'index_mystartdesc'},
		   'links' => \@links } );
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

# Default database name template
print &ui_table_row(&hlink($text{'tmpl_mysql'}, "template_mysql"),
	&none_def_input("mysql", $tmpl->{'mysql'}, $text{'tmpl_mysqlpat'}, 1,
			0, undef, [ "mysql" ]).
	&ui_textbox("mysql", $tmpl->{'mysql'}, 20));

# Enforced suffix for database names
print &ui_table_row(&hlink($text{'tmpl_mysql_suffix'}, "template_mysql_suffix"),
	&none_def_input("mysql_suffix", $tmpl->{'mysql_suffix'},
		        $text{'tmpl_mysqlpat'}, 0, 0, undef,
			[ "mysql_suffix" ]).
	&ui_textbox("mysql_suffix", $tmpl->{'mysql_suffix'} eq "none" ?
					undef : $tmpl->{'mysql_suffix'}, 20));

# Additional host wildcards to add
# Deprecated, so only show if already set
if ($tmpl->{'mysql_wild'}) {
	print &ui_table_row(&hlink($text{'tmpl_mysql_wild'},
				   "template_mysql_wild"),
		&none_def_input("mysql_wild", $tmpl->{'mysql_wild'},
				$text{'tmpl_mysqlpat'}, 1, 0, undef,
				[ "mysql_wild" ]).
		&ui_textbox("mysql_wild", $tmpl->{'mysql_wild'}, 20));
	}

# Additonal allowed hosts
print &ui_table_row(&hlink($text{'tmpl_mysql_hosts'}, "template_mysql_hosts"),
	&none_def_input("mysql_hosts", $tmpl->{'mysql_hosts'},
			$text{'tmpl_mysqlh'}, 0, 0, undef,
			[ "mysql_hosts" ]).
	&ui_textbox("mysql_hosts", $tmpl->{'mysql_hosts'} eq "none" ? "" :
					$tmpl->{'mysql_hosts'}, 40));

# Create DB at virtual server creation?
print &ui_table_row(&hlink($text{'tmpl_mysql_mkdb'}, "template_mysql_mkdb"),
	&ui_radio("mysql_mkdb", $tmpl->{'mysql_mkdb'},
		[ [ 1, $text{'yes'} ], [ 0, $text{'no'} ],
		  ($tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ) )]));

# Update MySQL username to match domain?
print &ui_table_row(&hlink($text{'tmpl_mysql_nouser'}, "template_mysql_nouser"),
	&ui_radio("mysql_nouser", $tmpl->{'mysql_nouser'},
		[ [ 0, $text{'yes'} ], [ 1, $text{'no'} ],
		  ($tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ) )]));

# Update MySQL password to match domain?
if (!$tmpl->{'hashpass'}) {
	print &ui_table_row(&hlink($text{'tmpl_mysql_nopass2'},
				   "template_mysql_nopass"),
		&ui_radio("mysql_nopass", $tmpl->{'mysql_nopass'},
			[ [ 0, $text{'tmpl_mysql_nopass_sync'} ],
			  [ 1, $text{'tmpl_mysql_nopass_same'} ],
			  [ 2, $text{'tmpl_mysql_nopass_random'} ],
			  ($tmpl->{'default'} ? ( ) :
			     ( [ "", $text{'default'} ] ) )]));
	}

# Make MySQL DBs group-owned by domain, for quotas?
if (-d $mysql::config{'mysql_data'} &&
    !$config{'provision_mysql'}) {
	print &ui_table_row(&hlink($text{'tmpl_mysql_chgrp'},
				   "template_mysql_chgrp"),
		&ui_radio("mysql_chgrp", $tmpl->{'mysql_chgrp'},
			[ [ 1, $text{'yes'} ],
			  [ 0, $text{'no'} ],
			  ($tmpl->{'default'} ? ( ) :
				( [ "", $text{'default'} ] ) )]));
	}

if (&get_dom_remote_mysql_version() >= 4.1 && $config{'mysql'}) {
	# Default MySQL character set
	print &ui_table_row(&hlink($text{'tmpl_mysql_charset'},
				   "template_mysql_charset"),
	    &ui_select("mysql_charset",  $tmpl->{'mysql_charset'},
		[ $tmpl->{'default'} ? ( ) :
		    ( [ "", "&lt;$text{'tmpl_mysql_charsetdef'}&gt;" ] ),
		  [ "none", "&lt;$text{'tmpl_mysql_charsetnone'}&gt;" ],
		  map { [ $_->[0], $_->[0]." (".$_->[1].")" ] }
		      &list_mysql_character_sets() ]));
	}

if (&get_dom_remote_mysql_version() >= 5 && $config{'mysql'}) {
	# Default MySQL collation order
	print &ui_table_row(&hlink($text{'tmpl_mysql_collate'},
				   "template_mysql_collate"),
	    &ui_select("mysql_collate",  $tmpl->{'mysql_collate'},
		[ $tmpl->{'default'} ? ( ) :
		    ( [ "", "&lt;$text{'tmpl_mysql_charsetdef'}&gt;" ] ),
		  [ "none", "&lt;$text{'tmpl_mysql_charsetnone'}&gt;" ],
		  map { $_->[0] } &list_mysql_collation_orders() ]));
	}

# Max DB connections for domain owner
my $c = $tmpl->{'mysql_conns'};
$c = "" if ($c eq "none");
print &ui_table_row(&hlink($text{'tmpl_mysql_conns'},
			   "template_mysql_conns"),
		    &none_def_input("mysql_conns", $tmpl->{'mysql_conns'},
				    $text{'tmpl_mysql_maxconns'}, 0, 0,
				    $text{'tmpl_mysql_unlimited'}).
		    &ui_textbox("mysql_conns", $c, 5));

# Max DB connections for mailbox users
my $uc = $tmpl->{'mysql_uconns'};
$uc = "" if ($uc eq "none");
print &ui_table_row(&hlink($text{'tmpl_mysql_uconns'},
			   "template_mysql_uconns"),
		    &none_def_input("mysql_uconns", $tmpl->{'mysql_uconns'},
				    $text{'tmpl_mysql_maxconns'}, 0, 0,
				    $text{'tmpl_mysql_unlimited'}).
		    &ui_textbox("mysql_uconns", $uc, 5));
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
if (defined($in{'mysql_wild_mode'})) {
	if ($in{'mysql_wild_mode'} == 1) {
		$tmpl->{'mysql_wild'} = undef;
		}
	else {
		$in{'mysql_wild'} =~ /^\S*$/ ||
			&error($text{'tmpl_emysql_wild'});
		$tmpl->{'mysql_wild'} = $in{'mysql_wild'};
		}
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
if (!$tmpl->{'hashpass'}) {
	$tmpl->{'mysql_nopass'} = $in{'mysql_nopass'};
	}
$tmpl->{'mysql_nouser'} = $in{'mysql_nouser'};
if (-d $mysql::config{'mysql_data'} &&
    !$config{'provision_mysql'}) {
	$tmpl->{'mysql_chgrp'} = $in{'mysql_chgrp'};
	}
if (&get_dom_remote_mysql_version() >= 4.1 && $config{'mysql'}) {
	$tmpl->{'mysql_charset'} = $in{'mysql_charset'};
	$tmpl->{'mysql_collate'} = $in{'mysql_collate'};
	}

$in{'mysql_conns_mode'} < 2 || $in{'mysql_conns'} =~ /^[1-9]\d*$/ ||
	&error($text{'tmpl_emysql_conns'});
$tmpl->{'mysql_conns'} = &parse_none_def("mysql_conns");

$in{'mysql_uconns_mode'} < 2 || $in{'mysql_uconns'} =~ /^[1-9]\d*$/ ||
	&error($text{'tmpl_emysql_conns'});
$tmpl->{'mysql_uconns'} = &parse_none_def("mysql_uconns");
}

# creation_form_mysql(&domain)
# Returns options for a new mysql database
sub creation_form_mysql
{
my ($d) = @_;
&require_mysql();
local $rv;
if (&get_dom_remote_mysql_version($d) >= 4.1) {
	local $tmpl = &get_template($d->{'template'});

	# Character set
	local @charsets = &list_mysql_character_sets($d);
	local $cs = $tmpl->{'mysql_charset'};
	$cs = "" if ($cs eq "none");
	$rv .= &ui_table_row($text{'database_charset'},
		     &ui_select("mysql_charset", $cs,
				[ [ undef, "&lt;$text{'default'}&gt;" ],
				  map { [ $_->[0], $_->[0]." (".$_->[1].")" ] }
				      @charsets ]));

	# Collation order
	local $cl = $tmpl->{'mysql_collate'};
	$cl = "" if ($cs eq "none");
	local @colls = &list_mysql_collation_orders($d);
	if (@colls) {
		local %csmap = map { $_->[0], $_->[1] } @charsets;
		$rv .= &ui_table_row($text{'database_collate'},
		     &ui_select("mysql_collate", $cl,
			[ [ undef, "&lt;$text{'default'}&gt;" ],
			  map { [ $_->[0], $_->[0]." (".$csmap{$_->[1]}.")" ] }
			      @colls ]));
		}
	}
return $rv;
}

# creation_parse_mysql(&domain, &in)
# Parse the form generated by creation_form_mysql, and return a structure
# for passing to create_mysql_database
sub creation_parse_mysql
{
local ($d, $in) = @_;
local $opts = { 'charset' => $in->{'mysql_charset'},
		'collate' => $in->{'mysql_collate'} };
return $opts;
}

# get_mysql_allowed_hosts(&domain)
# Returns a list of hostnames or IP addresses from which a domain's user is
# allowed to connect to MySQL.
sub get_mysql_allowed_hosts
{
local ($d) = @_;
&require_mysql();
if ($d->{'provision_mysql'}) {
	# Query provisioning server
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'host' => $mymod->{'config'}->{'host'},
		     'user' => &mysql_user($d) };
	my ($ok, $msg) = &provision_api_call(
		"list-provision-mysql-users", $info, 1);
	&error(&text('user_emysqllist', $msg)) if (!$ok);
	return split(/\s+/, $msg->[0]->{'values'}->{'hosts'}->[0]);
	}
else {
	# Get from local DB
	local $data = &execute_dom_sql($d, $mysql::master_db,
	    "select distinct host from user where user = ?", &mysql_user($d));
	return map { $_->[0] } @{$data->{'data'}};
	}
}

# save_mysql_allowed_hosts(&domain, &hosts)
# Sets the list of hosts from which this domain's MySQL user can connect.
# Returns undef on success, or an error message on failure.
sub save_mysql_allowed_hosts
{
local ($d, $hosts) = @_;
&require_mysql();
local $user = &mysql_user($d);

if ($d->{'provision_mysql'}) {
	# Call the remote API
	my $mymod = &get_domain_mysql_module($d);
	my $info = { 'user' => $user,
		     'host' => $mymod->{'config'}->{'host'},
		     'remote' => $hosts };
	my ($ok, $msg) = &provision_api_call("modify-mysql-login", $info, 0);
	return &text('user_emysqlprovips', $msg) if (!$ok);
	}
else {
	# Update MySQL permissions locally
	local @dbs = &domain_databases($d, [ 'mysql' ]);
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		push(@dbs, &domain_databases($sd, [ 'mysql' ]));
		}

	local $ufunc = sub {
		# Update the user table entry for the main user
		local $encpass = &encrypted_mysql_pass($d);
		&execute_dom_sql($d, $mysql::master_db,
			"delete from user where user = '$user'");
		&execute_dom_sql($d, $mysql::master_db,
			"delete from db where user = '$user'");
		foreach my $h (@$hosts) {
			&execute_user_creation_sql($d, $h, $user, $encpass);
			foreach my $db (@dbs) {
				&add_db_table($d, $h, $db->{'name'}, $user);
				}
			&set_mysql_user_connections($d, $h, $user, 0);
			}
		&execute_dom_sql($d, $mysql::master_db, 'flush privileges');
		};
	&execute_for_all_mysql_servers($ufunc);

	# Add db table entries for all users, and user table entries
	# for mailboxes
	my $mymod = &get_domain_mysql_module($d);
	local $ufunc = sub {
		my %allusers;
		foreach my $db (@dbs) {
			foreach my $u (&list_mysql_database_users(
					$d, $db->{'name'})) {
				# Re-populate db table for this db and user
				next if ($u->[0] eq $user ||
					 $u->[0] eq 'root' ||
					 $u->[0] eq $mymod->{'config'}->{'login'});
				&execute_dom_sql($d, $mysql::master_db,
					"delete from db where user = ? and ".
					"db = ?", $u->[0], $db->{'name'});
				foreach my $h (@$hosts) {
					&add_db_table($d, $h, $db->{'name'},
						      $u->[0]);
					}
				$allusers{$u->[0]} = $u;
				}
			}
		# Re-populate user table
		foreach my $u (values %allusers) {
			&execute_dom_sql($d, $mysql::master_db,
				"delete from user where user = ?", $u->[0]);
			foreach my $h (@$hosts) {
				&execute_user_creation_sql($d, $h, $u->[0],
							   "'$u->[1]'");
				&set_mysql_user_connections($d, $h, $u->[0], 1);
				}
			}
		&execute_dom_sql($d, $mysql::master_db,
					   'flush privileges');
		};
	&execute_for_all_mysql_servers($ufunc);
	}

return undef;
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

# check_mysql_login(&domain, dbname, dbuser, dbpass)
# Tries to login to MySQL with the given credentials, returning undef on failure
sub check_mysql_login
{
local ($d, $dbname, $dbuser, $dbpass) = @_;
&require_mysql();
local $main::error_must_die = 1;
local $mysql::mysql_login = $dbuser;
local $mysql::mysql_pass = $dbpass;
eval { &execute_dom_sql($d, $dbname, "show tables") };
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
	local %done;
	foreach my $host ($thishost, @repls) {
		local $ip = &to_ipaddress($host);
		next if ($ip && $done{$ip}++);
		$mysql::config{'host'} = $host;
		&$code;
		}
	$mysql::config{'host'} = $thishost;
	}
}

# list_mysql_collation_orders($d)
# Returns a list of supported collation orders. Each row is an array ref of
# a code and character set it can work with.
sub list_mysql_collation_orders
{
my ($d) = @_;
&require_mysql();
local @rv;
if ($config{'provision_mysql'}) {
	my $mymod = &get_domain_mysql_module($d);
	if ($mymod->{'config'}->{'host'}) {
		# Query provisioning DB system
		my $rv = &mysql::execute_sql(
			"information_schema", "show collation");
		@rv = map { [ $_->[0], $_->[1] ] } @{$rv->{'data'}};
		}
	else {
		# No MySQL host yet
		@rv = ( );
		}
	}
else {
	# Query local DB
	if (&get_dom_remote_mysql_version($d) >= 5) {
		my $rv = &execute_dom_sql($d, 
			$mysql::master_db, "show collation");
		@rv = map { [ $_->[0], $_->[1] ] } @{$rv->{'data'}};
		}
	}
return sort { lc($a->[0]) cmp lc($b->[0]) } @rv;
}

# list_mysql_character_sets(&domain)
# Returns a list of supported character sets. Each row is an array ref of
# a code and character set name
sub list_mysql_character_sets
{
my ($d) = @_;
&require_mysql();
if ($config{'provision_mysql'}) {
	my $mymod = &get_domain_mysql_module($d);
	if ($mymod->{'config'}->{'host'}) {
		# Query provisioning DB system
		return &mysql::list_character_sets("information_schema");
		}
	else {
		# No MySQL host yet
		return ( );
		}
	}
else {
	# Query local DB
	my $mod = &require_dom_mysql($d);
	return &foreign_call($mod, "list_character_sets");
	}
}

# validate_database_name_mysql(&domain, name)
# Checks if a MySQL database name is valid
sub validate_database_name_mysql
{
local ($d, $dbname) = @_;
$dbname =~ /^[a-z0-9\_\-]+$/i ||
	return $text{'database_ename'};
local $maxlen;
if ($d->{'provision_mysql'}) {
	# Just assume that the DB name max is 64 chars
	$maxlen = 64;
	}
else {
	# Get the DB name max from the mysql.db table
	&require_mysql();
	local @str = &mysql::table_structure($mysql::master_db, "db");
	local ($dbcol) = grep { lc($_->{'field'}) eq 'db' } @str;
	$maxlen = $dbcol && $dbcol->{'type'} =~ /\((\d+)\)/ ? $1 : 64;
	}
length($dbname) <= $maxlen ||
	return &text('database_enamelen', $maxlen);
return undef;
}

# default_mysql_creation_opts(&domain)
# Returns default options for a new MySQL DB in some domain
sub default_mysql_creation_opts
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local %opts;
if ($tmpl->{'mysql_charset'} && $tmpl->{'mysql_charset'} ne 'none') {
	$opts{'charset'} = $tmpl->{'mysql_charset'};
	}
if ($tmpl->{'mysql_collate'} && $tmpl->{'mysql_collate'} ne 'none') {
	$opts{'collate'} = $tmpl->{'mysql_collate'};
	}
return \%opts;
}

# get_mysql_creation_opts(&domain, db)
# Returns a hash ref of database creation options for an existing DB
sub get_mysql_creation_opts
{
local ($d, $dbname) = @_;
&require_mysql();
local $data = &execute_dom_sql($d, $dbname, "show create database ".
					    &mysql::quotestr($dbname));
local $sql = $data->{'data'}->[0]->[1];
local $opts = { };
if ($sql =~ /CHARACTER\s+SET\s+(\S+)/i) {
	$opts->{'charset'} = $1;
	}
if ($sql =~ /COLLATE\s+(\S+)/i) {
	$opts->{'collate'} = $1;
	}
return $opts;
}

# list_all_mysql_databases([&domain])
# Returns the names of all known MySQL databases
sub list_all_mysql_databases
{
local ($d) = @_;
local $prov = $d ? $d->{'provision_mysql'} : $config{'provision_mysql'};
&require_mysql();
if ($prov) {
	# From provisioning server
	local $info = { 'feature' => 'mysqldb' };
	my ($ok, $msg) = &provision_api_call(
		"list-provision-history", $info, 1);
	if (!$ok) {
		&error($msg);
		}
	return map { $_->{'values'}->{'mysql_database'}->[0] } @$msg;
	}
else {
	# Local list
	return &list_dom_mysql_databases($d);
	}
}

# set_mysql_user_connections(&domain, hostname, username, is-mailbox)
# Sets the max connections for a user if defined in the template
sub set_mysql_user_connections
{
local ($d, $host, $user, $mailbox) = @_;
local $conns = &get_mysql_user_connections($d, $mailbox);
if ($conns) {
	&execute_dom_sql($d, $mysql::master_db,
		"update user set max_user_connections = ? ".
		"where user = ? and host = ?", $conns, $user, $host);
	}
}

# get_mysql_user_connections(&domain, is-mailbox)
# Returns the max connections to MySQL from a template
sub get_mysql_user_connections
{
local ($d, $mailbox) = @_;
local $tmpl = &get_template($d->{'template'});
local $conns = $tmpl->{$mailbox ? 'mysql_uconns' : 'mysql_conns'};
$conns = undef if ($conns eq "none");
return $conns;
}

# list_mysql_size_settings("small"|"medium"|"large"|"huge")
# Returns an array of tupes for MySQL my.cnf settings for some size
# diff my-large.cnf my-huge.cnf  | grep ">" | grep -v "#" | grep = | perl -ne 'print "[ \"$1\", \"$2\" ],\n" if (/(\S+)\s*=\s*(\S+)/)'
sub list_mysql_size_settings
{
local ($size) = @_;
&require_mysql();
my $myver = &mysql::get_mysql_version();
my $cachedir = &compare_versions($myver, "5.1.3") > 0 ? "table_open_cache"
						      : "table_cache";
my $tc = &compare_versions($myver, "5.7") < 0;
if ($size eq "small") {
	return ([ "key_buffer_size", "16K" ],
		[ "max_allowed_packet", "1M" ],
		[ $cachedir, "4" ],
		[ "sort_buffer_size", "64K" ],
		[ "read_buffer_size", "256K" ],
		[ "read_rnd_buffer_size", "256K" ],
		[ "net_buffer_length", "2K" ],
		[ "myisam_sort_buffer_size", undef ],
		[ "thread_stack", "128K" ],
		[ "thread_cache_size", undef ],
		[ "query_cache_size", undef ],
		[ "thread_concurrency", undef ],

		[ "key_buffer_size", "8M", "isamchk" ],
		[ "sort_buffer_size", "8M", "isamchk" ],
		[ "read_buffer", undef, "isamchk" ],
		[ "write_buffer", undef, "isamchk" ],

		[ "key_buffer_size", "8M", "myisamchk" ],
		[ "sort_buffer_size", "8M", "myisamchk" ],
		[ "read_buffer", undef, "myisamchk" ],
		[ "write_buffer", undef, "myisamchk" ]);
	}
elsif ($size eq "medium") {
	return ([ "key_buffer_size", "16M" ],
		[ "max_allowed_packet", "1M" ],
		[ $cachedir, "64" ],
		[ "sort_buffer_size", "512K" ],
		[ "read_buffer_size", "256K" ],
		[ "net_buffer_length", "8K" ],
		[ "read_rnd_buffer_size", "512K" ],
		[ "myisam_sort_buffer_size", "8M" ],
		[ "thread_stack", undef ],
		[ "thread_cache_size", undef ],
		[ "query_cache_size", undef ],
		[ "thread_concurrency", undef ],

		[ "key_buffer_size", "20M", "isamchk" ],
		[ "sort_buffer_size", "20M", "isamchk" ],
		[ "read_buffer", "2M", "isamchk" ],
		[ "write_buffer", "2M", "isamchk" ],

		[ "key_buffer_size", "20M", "myisamchk" ],
		[ "sort_buffer_size", "20M", "myisamchk" ],
		[ "read_buffer", "2M", "myisamchk" ],
		[ "write_buffer", "2M", "myisamchk" ]);
	}
elsif ($size eq "large") {
	return ([ "key_buffer_size", "256M" ],
		[ "max_allowed_packet", "1M" ],
		[ $cachedir, "256" ],
		[ "sort_buffer_size", "1M" ],
		[ "read_buffer_size", "1M" ],
		[ "net_buffer_length", undef ],
		[ "read_rnd_buffer_size", "4M" ],
		[ "myisam_sort_buffer_size", "64M" ],
		[ "thread_stack", undef ],
		[ "thread_cache_size", "8" ],
		[ "query_cache_size", "16M" ],
		[ "thread_concurrency", $tc ? "8" : undef ],

		[ "key_buffer_size", "128M", "isamchk" ],
		[ "sort_buffer_size", "128M", "isamchk" ],
		[ "read_buffer", "2M", "isamchk" ],
		[ "write_buffer", "2M", "isamchk" ],

		[ "key_buffer_size", "128M", "myisamchk" ],
		[ "sort_buffer_size", "128M", "myisamchk" ],
		[ "read_buffer", "2M", "myisamchk" ],
		[ "write_buffer", "2M", "myisamchk" ]);
	}
elsif ($size eq "huge") {
	return ([ "key_buffer_size", "384M" ],
		[ "max_allowed_packet", "1M" ],
		[ $cachedir, "512" ],
		[ "sort_buffer_size", "2M" ],
		[ "read_buffer_size", "2M" ],
		[ "net_buffer_length", undef ],
		[ "read_rnd_buffer_size", "8M" ],
		[ "myisam_sort_buffer_size", "64M" ],
		[ "thread_stack", undef ],
		[ "thread_cache_size", "8" ],
		[ "query_cache_size", "32M" ],
		[ "thread_concurrency", $tc ? "8" : undef ],

		[ "key_buffer_size", "256M", "isamchk" ],
		[ "sort_buffer_size", "256M", "isamchk" ],
		[ "read_buffer", "2M", "isamchk" ],
		[ "write_buffer", "2M", "isamchk" ],

		[ "key_buffer_size", "256M", "myisamchk" ],
		[ "sort_buffer_size", "256M", "myisamchk" ],
		[ "read_buffer", "2M", "myisamchk" ],
		[ "write_buffer", "2M", "myisamchk" ]);
	}
return ( );
}

# execute_user_creation_sql(&domain, host, user, password-sql)
# Create a MySQL user and set his password
sub execute_user_creation_sql
{
my ($d, $host, $user, $encpass) = @_;
foreach my $sql (&get_user_creation_sql($d, $host, $user, $encpass)) {
	if ($sql =~ /^set\s+password/) {
		&execute_set_password_sql($d, $sql, $host);
		}
	else {
		&execute_dom_sql($d, $mysql::master_db, $sql);
		};
	if ($sql =~ /flush\s+privileges/) {
		sleep(1);
		}
	}
}

# execute_set_password_sql(&domain, sql, hostname)
# Runs a 'set password' SQL statement, with a re-try using an IP instead of host
sub execute_set_password_sql
{
my ($d, $sql, $host) = @_;
my $ip = $host =~ /%/ ? undef : &to_ipaddress($host);
eval {
	local $main::error_must_die = 1;
	&execute_dom_sql($d, $mysql::master_db, $sql);
	};
if ($@ && $ip && $ip ne $host) {
	# Try again, this time with IP instead of host
	$sql =~ s/'$host'/'$ip'/g;
	&execute_dom_sql($d, $mysql::master_db, $sql);
	}
elsif ($@) {
	# Some other failure .. re-throw it
	&error($@);
	}
}

# get_user_creation_sql(&domain, host, user, password-sql)
# Returns SQL to add a user, with SSL fields if needed
sub get_user_creation_sql
{
my ($d, $host, $user, $encpass) = @_;
if (&compare_versions(&get_dom_remote_mysql_version($d), "5.7.6") >= 0) {
	return ("insert into user (host, user, ssl_type, ssl_cipher, x509_issuer, x509_subject, plugin, authentication_string) values ('$host', '$user', '', '', '', '', 'mysql_native_password', $encpass)");
	}
elsif (&compare_versions(&get_dom_remote_mysql_version($d), 5) >= 0) {
	return ("insert into user (host, user, ssl_type, ssl_cipher, x509_issuer, x509_subject) values ('$host', '$user', '', '', '', '')", "flush privileges", "set password for '$user'\@'$host' = $encpass");
	}
else {
	return ("insert into user (host, user, password) values ('$host', '$user', $encpass)");
	}
}

# execute_password_change_sql(&domain, user, pass-str, [force-user-table],
# 			      [no-flush])
# Update a MySQL user's password for all hosts
sub execute_password_change_sql
{
my ($d, $user, $encpass, $forceuser, $noflush) = @_;
my $rv = &execute_dom_sql($d, $mysql::master_db,
		"select host from user where user = ?", $user);
my $flush = 0;
foreach my $host (&unique(map { $_->[0] } @{$rv->{'data'}})) {
	my $sql;
	if (&compare_versions(&get_dom_remote_mysql_version($d),
			      "5.7.6") >= 0) {
		$sql = "update user set authentication_string = $encpass ".
		       "where user = '$user' and host = '$host'";
		$flush++;
		}
	elsif ($forceuser) {
		$sql = "update user set password = $encpass ".
		       "where user = '$user' and host = '$host'";
		$flush++;
		}
	else {
		$sql = "set password for '$user'\@'$host' = $encpass";
		}
	if ($sql =~ /^set\s+password/) {
		&execute_set_password_sql($d, $sql, $host);
		}
	else {
		&execute_dom_sql($d, $mysql::master_db, $sql);
		};
	}
if ($flush && !$noflush) {
	&execute_dom_sql($d, $mysql::master_db, "flush privileges");
	}
}

# mysql_password_synced(&domain)
# Returns 1 if a domain's MySQL password will change along with its admin pass
sub mysql_password_synced
{
my ($d) = @_;
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	return &mysql_password_synced($parent);
	}
if ($d->{'hashpass'}) {
	# Hashed passwords are being used
	return 0;
	}
if ($d->{'mysql_pass'}) {
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

# remote_mysql(&domain)
# Returns 1 if the domain's MySQL DB is on a remote system
sub remote_mysql
{
local ($d) = @_;
my $mymod = &get_domain_mysql_module($d);
return $mymod->{'config'}->{'host'};
}

# force_set_mysql_password(user, pass)
# Forcibly change the MySQL password for some user by shutting down the server.
# May print stuff. Returns undef on success or an error message on failure.
sub force_set_mysql_password
{
my ($user, $pass) = @_;
&require_mysql();
&foreign_require("proc");

# This is only possible when run locally
if (&remote_mysql()) {
	&$second_print($text{'mysqlpass_eremote'});
	return $text{'mysqlpass_eremote'};
	}

# Find the mysqld_safe command
my $safe = &has_command("mysqld_safe");
if (!$safe) {
	&$second_print(&text('mysqlpass_esafecmd', "<tt>mysqld_safe</tt>"));
	return &text('mysqlpass_esafecmd', "<tt>mysqld_safe</tt>");
	}

# Shut down server if running
if (&mysql::is_mysql_running()) {
	&$first_print($text{'mysqlpass_shutdown'});
	my $err = &stop_service_mysql();
	if ($err) {
		&$second_print(&text('mysqlpass_eshutdown', $err));
		return &text('mysqlpass_eshutdown', $err);
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# Start up with skip-grants flag
&$first_print($text{'mysqlpass_safe'});
my $cmd = $safe." --skip-grant-tables";
my ($pty, $pid) = &proc::pty_process_exec($cmd, 0, 0);
my $rv = undef;
sleep(5);
if (!$pid || !kill(0, $pid)) {
	my $err = <$pty>;
	$rv = &text('mysqlpass_esafe', $err);
	&$second_print($rv);
	}
else {
	&$second_print($text{'setup_done'});
	}

if (!$rv) {
	# Change the password
	&$first_print(&text('mysqlpass_change', $user));
	my $qpass = &mysql_escape($pass);
	eval {
		local $main::error_must_die = 1;
		&execute_password_change_sql(
			undef, $user, "$password_func('$qpass')", 1, 1);
		};
	if ($@) {
		$rv = &text('mysqlpass_echange', "$@");
		&$second_print($rv);
		}
	else {
		&$second_print($text{'setup_done'});
		}

	# Shut down again, with the mysqladmin command
	&$first_print($text{'mysqlpass_kill'});
	my $out = &backquote_logged("$mysql::config{'mysqladmin'} shutdown 2>&1 </dev/null");
	if ($?) {
		$rv = &text('mysqlpass_eshutdown', $out);
		&$second_print($rv);
		return $rv;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# Finally, re-start in normal mode
&$first_print($text{'mysqlpass_startup'});
my $err = &start_service_mysql();
if ($err) {
	$rv = &text('mysqlpass_estartup', $err);
	&$second_print($rv);
	}
else {
	&$second_print($text{'setup_done'});
	}

return $rv;
}

# list_remote_mysql_modules()
# Returns a list of hash refs containing details of MySQL module clones for
# local or remote databases
sub list_remote_mysql_modules
{
my @rv;
foreach my $minfo (&get_all_module_infos()) {
	next if ($minfo->{'dir'} ne 'mysql' &&
		 $minfo->{'cloneof'} ne 'mysql');
	my %mconfig = &foreign_config($minfo->{'dir'});
	my $mm = { 'minfo' => $minfo,
		   'master' => $minfo->{'cloneof'} ? 0 : 1,
		   'config' => \%mconfig };
	if ($mconfig{'sock'}) {
		$mm->{'desc'} = &text('mysql_rsock',
				      "<tt>$mconfig{'sock'}</tt>");
		}
	elsif ($mconfig{'host'} && $mconfig{'port'}) {
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

# create_remote_mysql_module(&mod)
# Creates and configures a new clone of the mysql module
sub create_remote_mysql_module
{
my ($mm) = @_;

# Create the config dir
if (!$mm->{'minfo'}->{'dir'}) {
	my $sock = $mm->{'config'}->{'sock'};
	$sock =~ s/\//-/g;
	$mm->{'minfo'}->{'dir'} =
		"mysql-".($mm->{'config'}->{'host'} ||
			  $mm->{'config'}->{'port'} ||
			  $sock ||
			  'local');
	if (&foreign_check($mm->{'minfo'}->{'dir'})) {
		# Clash! Try appending username
		$mm->{'minfo'}->{'dir'} .= "-".($mm->{'config'}->{'user'} || 'root');
		if (&foreign_check($mm->{'minfo'}->{'dir'})) {
			&error("The module ".$mm->{'minfo'}->{'dir'}.
			       " already exists");
			}
		}
	}
$mm->{'minfo'}->{'cloneof'} = 'mysql';
my $cdir = "$config_directory/$mm->{'minfo'}->{'dir'}";
my $srccdir = "$config_directory/mysql";
-d $cdir && &error("Config directory $cdir already exists!");
&make_dir($cdir, 0700);
&copy_source_dest("$srccdir/config", "$cdir/config");

# Create the clone symlink
my $mdir = "$root_directory/$mm->{'minfo'}->{'dir'}";
&symlink_logged("mysql", $mdir);

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

# Grant access to the current (root) user
my %acl;
&read_acl(undef, \%acl);
&open_lock_tempfile(ACL, "> ".&acl_filename());
foreach $u (keys %acl) {
        my @mods = @{$acl{$u}};
        if ($u eq $base_remote_user) {
                @mods = &unique(@mods, $mm->{'minfo'}->{'dir'});
                }
        &print_tempfile(ACL, "$u: ",join(' ', @mods),"\n");
        }
&close_tempfile(ACL);

# Refresh visible modules cache
&flush_webmin_caches();
}

# delete_remote_mysql_module(&mod)
# Removes one MySQL module clone
sub delete_remote_mysql_module
{
my ($mm) = @_;
$mm->{'minfo'}->{'cloneof'} eq 'mysql' ||
	&error("Only MySQL clones can be removed!");
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

# get_remote_mysql_module(name)
# Returns a mysql module hash, looked up by hostname or socket file
sub get_remote_mysql_module
{
my ($name) = @_;
foreach my $mm (&list_remote_mysql_modules()) {
	my $c = $mm->{'config'};
	if ($c->{'sock'} && $name eq $c->{'sock'} ||
	    $c->{'host'} && $name eq $c->{'host'}.':'.($c->{'port'} || 3306) ||
	    $c->{'host'} && $name eq $c->{'host'} ||
	    !$c->{'host'} && $name eq "localhost:".($c->{'port'} || 3306) ||
	    !$c->{'host'} && $name eq "localhost") {
		return $mm;
		}
	}
return undef;
}

# require_dom_mysql(&domain)
# Finds and loads the MySQL module for a domain
sub require_dom_mysql
{
my ($d) = @_;
my $mod = !$d ? 'mysql' : $d->{'mysql_module'} || 'mysql';
&foreign_require($mod);
return $mod;
}

# get_domain_mysql_module(&domain)
# Returns the mysql module hash for a domain, or undef
sub get_domain_mysql_module
{
my ($d) = @_;
my @mymods = &list_remote_mysql_modules();
my ($mymod) = grep { $_->{'minfo'}->{'dir'} eq
		     ($d->{'mysql_module'} || 'mysql') } @mymods;
return $mymod;
}

# execute_dom_sql(&domain, db, sql, ...)
# Run some SQL, but in the module for the domain's MySQL connection
sub execute_dom_sql
{
my ($d, $db, $sql, @params) = @_;
my $mod = &require_dom_mysql($d);
if ($sql =~ /^(select|show)\s+/i) {
	return &foreign_call($mod, "execute_sql", $db, $sql, @params);
	}
else {
	return &foreign_call($mod, "execute_sql_logged", $db, $sql, @params);
	}
}

# execute_dom_sql_file(&domain, db, file, ...)
# Run some SQL file, but in the module for the domain's MySQL connection
sub execute_dom_sql_file
{
my ($d, $db, $file, @params) = @_;
my $mod = &require_dom_mysql($d);
return &foreign_call($mod, "execute_sql_file", $db, $file, @params);
}

# list_dom_mysql_tables(&domain, db, empty-if-denied, no-filter-views)
# Returns a list of mysql tables in some DB, from the server used by a domain
sub list_dom_mysql_tables
{
my ($d, $db, $empty_denied, $include_views) = @_;
my $mod = &require_dom_mysql($d);
return &foreign_call($mod, "list_tables", $db, $empty_denied, $include_views);
}

# list_dom_mysql_databases(&domain)
# Returns a list of mysql databases, from the server used by a domain
sub list_dom_mysql_databases
{
my ($d, $db) = @_;
my $mod = &require_dom_mysql($d);
return &foreign_call($mod, "list_databases");
}

# get_dom_remote_mysql_version(&domain)
# Returns the MySQL server version for a domain
sub get_dom_remote_mysql_version
{
my ($d) = @_;
my $mod = &require_dom_mysql($d);
if ($get_dom_remote_mysql_version_cache{$mod}) {
	return $get_dom_remote_mysql_version_cache{$mod};
	}
else {
	my $rv;
	eval {
		local $main::error_must_die = 1;
		$rv = &foreign_call($mod, "get_remote_mysql_version");
		};
	$rv ||= eval $mod.'::mysql_version';
	$rv ||= $mysql::mysql_version;
	$get_dom_remote_mysql_version_cache{$mod} = $rv;
	return $rv;
	}
}

# get_default_mysql_module()
# Returns the name of the default module for remote MySQL
sub get_default_mysql_module
{
my ($def) = grep { $_->{'config'}->{'virtualmin_default'} }
		 &list_remote_mysql_modules();
return $def ? $def->{'minfo'}->{'dir'} : 'mysql';
}

# move_mysql_server(&domain, new-mysql-module)
# Update the MySQL module for a domain, by moving across all databases and
# permissions. Prints progress, and returns 1 on success or 0 on failure.
sub move_mysql_server
{
my ($d, $newmod) = @_;
return 1 if (&require_dom_mysql($d) eq $newmod);	# Already using it

# Get all the domain objects being moved
my $oldd = { %$d };
my @doms = ( $d );
my @olddoms = ( $oldd );
if (!$d->{'parent'}) {
	foreach my $pd (&get_domain_by("parent", $d->{'id'})) {
		my $oldpd = { %$pd };
		push(@doms, $pd);
		push(@olddoms, $oldpd);
		}
	}

# Backup just mysql to a temp file
my $temp = &transname();
&$first_print($text{'mysql_movebackup'});
&$indent_print();
my ($ok) = &backup_domains($temp, \@olddoms, [ 'mysql' ], 0, 0, undef, 0, undef,
			   0, 0, 0);
&$outdent_print();
if (!$ok) {
	&unlink_file($temp);
	return 0;
	}

# Get all users and their DBs (deep copy so that subsequent calls don't re-use
# the same user objects)
my %umap;
foreach my $ad (@olddoms) {
	my @users = &list_domain_users($ad, 1, 1, 1, 0);
	$umap{$ad->{'id'}} = [ map { my %u = %$_; \%u } @users ];
	}

# Restore from the temp file on the new system
foreach my $ad (@doms) {
	$ad->{'mysql_module'} = $newmod;
	}
&$first_print($text{'mysql_moverestore'});
&$indent_print();
my $ok = &restore_domains($temp, \@doms, [ 'mysql' ]);
&$outdent_print();
if (!$ok) {
	&unlink_file($temp);
	return 0;
	}

# Delete users and databases on the old system
&$first_print($text{'mysql_movedelete'});
&$indent_print();
foreach my $dd (reverse(@olddoms)) {
	&delete_mysql($dd);
	}
&$outdent_print();

# Re-grant users access to their databases
foreach my $ad (@doms) {
	my @users = &list_domain_users($ad, 1);
	my @oldusers = @{$umap{$ad->{'id'}}};
	foreach my $u (@users) {
		my ($oldu) = grep { $_->{'user'} eq $u->{'user'} } @oldusers;
		next if (!$oldu);	# Should never happen!
		my $beforeu = { %$u };
		$u->{'dbs'} = $oldu->{'dbs'};
		$u->{'pass_mysql'} = $oldu->{'pass_mysql'};
		&modify_user($u, $beforeu, $ad);
		}
	}

foreach my $sd (@doms) {
	&save_domain($sd);
	}
return 1;
}

$done_feature_script{'mysql'} = 1;

1;

