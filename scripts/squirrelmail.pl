
# script_squirrelmail_desc()
sub script_squirrelmail_desc
{
return "SquirrelMail";
}

sub script_squirrelmail_uses
{
return ( "php" );
}

sub script_squirrelmail_longdesc
{
return "SquirrelMail is a standards-based webmail package written in PHP";
}

# script_squirrelmail_versions()
sub script_squirrelmail_versions
{
return ( "1.4.22" );
}

sub script_squirrelmail_release
{
return 2;	# Remove set_user_data
}

sub script_squirrelmail_version_desc
{
local ($ver) = @_;
return $ver < 1.5 ? "$ver (Stable)" : "$ver (Development)";
}

sub script_squirrelmail_category
{
return "Email";
}

sub script_squirrelmail_php_vers
{
return ( 5 );
}

sub script_squirrelmail_php_fullver
{
return 5;
}

sub script_squirrelmail_abandoned
{
return 1;
}

sub script_squirrelmail_pear_modules
{
local ($d, $opts) = @_;
return $opts->{'db'} ? ( "DB" ) : ( );
}

# script_squirrelmail_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_squirrelmail_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	if ($dbtype) {
		$rv .= &ui_table_row("Database for SquirrelMail preferences", $dbname);
		}
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql" ]);
	if (@dbs) {
		$rv .= &ui_table_row("Database for SquirrelMail preferences",
		     &ui_radio("db_def", 1, [ [ 1, "None" ],
				     	    [ 0, "Selected database" ] ])."\n".
		     &ui_database_select("db", undef, \@dbs));
		}
	else {
		$rv .= &ui_hidden("db_def", 1)."\n";
		}
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("squirrelmail", $d), 30, "At top level"));
	}
return $rv;
}

# script_squirrelmail_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_squirrelmail_parse
{
local ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	local $hdir = &public_html_dir($d, 0);
	$in{'dir_def'} || $in{'dir'} =~ /\S/ && $in{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	local $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
	return { 'db' => $in{'db_def'} ? undef : $in->{'db'},
		 'dir' => $dir,
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}", };
	}
}

# script_squirrelmail_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_squirrelmail_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
if (-r "$opts->{'dir'}/config/config.php") {
	return "SquirrelMail appears to be already installed in the selected directory";
	}
if ($opts->{'db'}) {
	local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	local $clash = &find_database_table($dbtype, $dbname, "userprefs|address|global_abook");
	$clash && return "SquirrelMail appears to be already using the selected database (table $clash)";
	}
return undef;
}

# script_squirrelmail_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by SquirrelMail, each of which is a hash ref
# containing a name, filename and URL
sub script_squirrelmail_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = ( { 'name' => "source",
	   'file' => "squirrelmail-$ver.tar.gz",
	   'nocheck' => 1,
	   'url' => "http://prdownloads.sourceforge.net/squirrelmail/squirrelmail-webmail-$ver.tar.gz" },
	   { 'name' => 'locales',
	     'file' => 'locales.tar.gz',
	     'nocheck' => 1,
	     'url' => "http://sourceforge.net/projects/squirrelmail/files/locales/1.4.18-20090526/all_locales-1.4.18-20090526.tar.gz" },
	    );
return @files;
}

sub script_squirrelmail_commands
{
return ("tar", "gunzip");
}

# script_squirrelmail_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs SquirrelMail, and returns either 1 and an informational
# message, or 0 and an error
sub script_squirrelmail_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
local $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
local $dbhost = &get_database_host($dbtype, $d);
if ($dbtype) {
	local $dberr = &check_script_db_connection($dbtype, $dbname, $dbuser, $dbpass);
	return (0, "Database connection failed : $dberr") if ($dberr);
	}

# Delete doc/ReleaseNotes, as this changed from a file to a directory!
if ($upgrade) {
	&unlink_file_as_domain_user($d, "$opts->{'dir'}/doc/ReleaseNotes");
	}

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
			     $opts->{'dir'}, "squirrelmail-webmail-$ver");
$err && return (0, "Failed to extract source : $err");
local $cprog = "$opts->{'dir'}/config/conf.pl";

# Extract locales
local $temp2 = &transname();
local $err2 = &extract_script_archive($files->{'locales'}, $temp2, $d,
			     $opts->{'dir'}."/locale", "locale");
$err2 && return (0, "Failed to extract locales : $err2");

if (!$upgrade) {
	# Run the config program
	&foreign_require("proc", "proc-lib.pl");
	local $confcmd = &command_as_user($d->{'user'}, 0,
					  "$opts->{'dir'}/config/conf.pl");
	&clean_environment();
	local ($fh, $fpid) = &proc::pty_process_exec($confcmd);
	&reset_environment();
	if (&wait_for($fh, "SquirrelMail", "different one") == 1) {
		&sysprint($fh, "n\n");
		}
	foreach my $cmd ([ ">>", "D" ], [ ">>", "courier" ],
			 [ "any key|enter", "" ], [ ">>", "S" ],
			 [ "enter", "" ], [ "Q", "Exiting" ]) {
		local $rv = &wait_for($fh, $cmd->[0]);
		return (0, "Configuration program failed : $wait_for_input")
			if ($rv < 0);
		&sysprint($fh, "$cmd->[1]\n");
		}
	close($fh);

	# Kill off conf.pl
	kill('KILL', $fpid);
	if (&foreign_check("proc")) {
		&foreign_require("proc", "proc-lib.pl");
		local @cprocs = grep { $_->{'user'} eq $d->{'user'} &&
				       $_->{'args'} =~ /conf\.pl/ }
				     &proc::list_processes();
		foreach my $cproc (@cprocs) {
			kill('KILL', $cproc->{'pid'});
			}
		}

	local $cfile = "$opts->{'dir'}/config/config.php";
	-r $cfile || return (-1, "Failed to create config file");

	# Create data directories
	local $data_dir = "$opts->{'dir'}/data";
	&make_dir_as_domain_user($d, $data_dir, 0700) if (!-d $data_dir);
	&make_file_php_writable($d, $data_dir, 1, 1);
	local $attachment_dir = "$opts->{'dir'}/attach";
	&make_dir_as_domain_user($d, $attachment_dir, 0700) if (!-d $attachment_dir);
	&make_file_php_writable($d, $attachment_dir, 1, 1);

	# Update the config file
	local $lref = &read_file_lines_as_domain_user($d, $cfile);
	local $dburl = "$dbphptype://$dbuser:".&php_quotemeta($dbpass, 1).
		       "\@$dbhost/$dbname";
	foreach $l (@$lref) {
		if ($l =~ /^\$domain\s*=\s*/) {
			$l = "\$domain = '$d->{'dom'}';";
			}
		if ($dbtype && $l =~ /^\$addrbook_dsn\s*=\s*/) {
			$l = "\$addrbook_dsn = '$dburl';";
			}
		if ($dbtype && $l =~ /^\$addrbook_global_dsn\s*=\s*/) {
			$l = "\$addrbook_global_dsn = '$dburl';";
			}
		if ($dbtype && $l =~ /^\$prefs_dsn\s*=\s*/) {
			$l = "\$prefs_dsn = '$dburl';";
			}
		if ($l =~ /^\$optional_delimiter\s*=\s*/) {
			$l = "\$optional_delimiter = '.';";
			}
		if ($l =~ /^\$default_folder_prefix\s*=\s*/) {
			$l = "\$default_folder_prefix = '';";
			}
		if ($l =~ /^\$data_dir\s*=\s*/) {
			$l = "\$data_dir = '$data_dir';";
			}
		if ($l =~ /^\$attachment_dir\s*=\s*/) {
			$l = "\$attachment_dir = '$attachment_dir';";
			}
		}
	&flush_file_lines_as_domain_user($d, $cfile);

	if ($dbname) {
		# Create the database tables
		&require_mysql();
		&mysql::execute_sql_logged($dbname, "
			CREATE TABLE address (
				owner varchar(128) DEFAULT '' NOT NULL,
				nickname varchar(16) DEFAULT '' NOT NULL,
				firstname varchar(128) DEFAULT '' NOT NULL,
				lastname varchar(128) DEFAULT '' NOT NULL,
				email varchar(128) DEFAULT '' NOT NULL,
				label varchar(255),
				PRIMARY KEY (owner,nickname),
				KEY firstname (firstname,lastname)
			)");
		&mysql::execute_sql_logged($dbname, "
			CREATE TABLE global_abook (
				owner varchar(128) DEFAULT '' NOT NULL,
				nickname varchar(16) DEFAULT '' NOT NULL,
				firstname varchar(128) DEFAULT '' NOT NULL,
				lastname varchar(128) DEFAULT '' NOT NULL,
				email varchar(128) DEFAULT '' NOT NULL,
				label varchar(255),
				PRIMARY KEY (owner,nickname),
				KEY firstname (firstname,lastname)
			)");
		&mysql::execute_sql_logged($dbname, "
			CREATE TABLE userprefs (
				user varchar(128) DEFAULT '' NOT NULL,
				prefkey varchar(64) DEFAULT '' NOT NULL,
				prefval BLOB DEFAULT '' NOT NULL,
				PRIMARY KEY (user,prefkey)
			)");
		}
	}

# Return a URL for the user
local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "SquirrelMail installation complete. It can be accessed at <a target=_blank href='$url'>$url</a>.", $dbname ? "Under $rp using $dbphptype database $dbname" : "Under $rp", $url);
}

# script_squirrelmail_uninstall(&domain, version, &opts)
# Un-installs a SquirrelMail installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_squirrelmail_uninstall
{
local ($d, $version, $opts) = @_;

# Remove squirrelmail tables from the database
&cleanup_script_database($d, $opts->{'db'},
			 [ "address", "global_abook", "userprefs" ]);

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

return (1, $dbname ? "SquirrelMail directory and tables deleted."
		   : "SquirrelMail directory deleted.");
}

# script_squirrelmail_check_latest(version)
# Checks if some version is the latest for this project, and if not returns
# a newer one. Otherwise returns undef.
sub script_squirrelmail_check_latest
{
local ($ver) = @_;
local @vers = &osdn_package_versions("squirrelmail", "squirrelmail-webmail-([a-z0-9\\.]+)\\.tar\\.gz");
@vers = grep { !/RC/ } @vers;
if (&compare_versions($ver, 1.5) > 0) {
	@vers = grep { &compare_versions($_, 1.5) > 0 } @vers;
	}
else {
	@vers = grep { &compare_versions($_, 1.5) < 0 } @vers;
	}
return "Failed to find versions" if (!@vers);
return $ver eq $vers[0] ? undef : $vers[0];
}

sub script_squirrelmail_site
{
return 'http://www.squirrelmail.org/';
}

sub script_squirrelmail_gpl
{
return 1;
}

1;

