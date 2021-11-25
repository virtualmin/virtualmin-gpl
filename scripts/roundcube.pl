# script_roundcube_desc()
sub script_roundcube_desc
{
return "RoundCube";
}

sub script_roundcube_uses
{
return ( "php" );
}

sub script_roundcube_longdesc
{
return "RoundCube Webmail is a browser-based multilingual IMAP client with an application-like user interface";
}

# script_roundcube_versions()
sub script_roundcube_versions
{
return ( "1.5.0", "1.4.12", "1.3.17" );
}

sub script_roundcube_version_desc
{
local ($ver) = @_;
return &compare_versions($ver, "1.5") >= 0 ? $ver : "$ver (LTS)";
}

sub script_roundcube_category
{
return "Email";
}

sub script_roundcube_php_modules
{
local ($d, $ver, $phpver, $opts) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local @modules = ( "xml", "zip", "dom", "iconv", "mbstring" );
push(@modules, $dbtype eq "mysql" ? "mysql" : "pgsql");
return @modules;
}

sub script_roundcube_php_optional_modules
{
return ( "openssl", "sockets", "intl",
         "fileinfo", "pspell", "json" );
}

sub script_roundcube_dbs
{
return ("mysql", "postgres");
}

# script_roundcube_php_vars(&domain)
# Returns an array of extra PHP variables needed for this script
sub script_roundcube_php_vars
{
return ([ 'memory_limit', '64M', '+' ],
        [ 'max_execution_time', 300, '+' ],
        [ 'file_uploads', 'On' ],
        [ 'upload_max_filesize', '25M', '+' ],
        [ 'post_max_size', '25M', '+' ],
        [ 'session.auto_start', 'Off' ],
        [ 'mbstring.func_overload', 'Off' ]);
}


sub script_roundcube_php_vers
{
return ( 5 );
}

sub script_roundcube_release
{
return 3;	# For folders path fix
}

sub script_roundcube_php_fullver
{
local ($d, $ver, $sinfo, $phpver) = @_;
return $ver >= 0.9 ? "5.4.1" : 5.2;
}

# script_roundcube_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_roundcube_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for RoundCube preferences", $dbname);
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Database for RoundCube preferences",
		     &ui_database_select("db", undef, \@dbs, $d, "roundcube"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("roundcube", $d), 30, "At top level"));
	}
return $rv;
}

# script_roundcube_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_roundcube_parse
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
	local ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}", };
	}
}

# script_roundcube_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_roundcube_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/config/db.inc.php") {
	return "RoundCube appears to be already installed in the selected directory";
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $clash = &find_database_table($dbtype, $dbname, "system|filestore|contacts|users");
$clash && return "RoundCube appears to be already using the selected database (table $clash)";
return undef;
}

# script_roundcube_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by RoundCube, each of which is a hash ref
# containing a name, filename and URL
sub script_roundcube_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = ( { 'name' => "source",
	           'file' => "roundcube-$ver.tar.gz",
	           'url' => $ver >= 1.1 ?
			"https://github.com/roundcube/roundcubemail/releases/download/${ver}/roundcubemail-${ver}-complete.tar.gz" :
			    $ver >= 1.0 ?
			"https://github.com/roundcube/roundcubemail/releases/download/${ver}/roundcubemail-${ver}.tar.gz" :
			"http://easynews.dl.sourceforge.net/sourceforge/roundcubemail/roundcubemail-${ver}.tar.gz" },
	    );
return @files;
}

sub script_roundcube_commands
{
return ("tar", "gunzip");
}

# script_roundcube_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs RoundCube, and returns either 1 and an informational
# message, or 0 and an error
sub script_roundcube_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);

# Create and get DB
if ($opts->{'newdb'} && !$upgrade) {
	local $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
local $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
local $dbhost = &get_database_host($dbtype, $d);
local $dberr = &check_script_db_connection($dbtype, $dbname, $dbuser, $dbpass);
return (0, "Database connection failed : $dberr") if ($dberr);

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $verdir = $ver;
$verdir =~ s/-complete$//;
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, "roundcubemail-$verdir");
$err && return (0, "Failed to extract source : $err");

if (!$upgrade) {
	# Fix up the DB config file
	local $dbcfileorig = "$opts->{'dir'}/config/db.inc.php.dist";
	local $dbcfile = "$opts->{'dir'}/config/db.inc.php";
	if (-r $dbcfileorig) {
		&copy_source_dest_as_domain_user($d, $dbcfileorig, $dbcfile);
		local $lref = &read_file_lines_as_domain_user($d, $dbcfile);
		foreach my $l (@$lref) {
			if ($l =~ /^\$rcmail_config\['db_dsnw'\]\s+=/) {
				$l = "\$rcmail_config['db_dsnw'] = 'mysql://$dbuser:".
				     &php_quotemeta($dbpass, 1).
				     "\@$dbhost/$dbname';";
				}
			elsif ($l =~ /^\$rcmail_config\['db_backend'\]\s+=/) {
				$l = "\$rcmail_config['db_backend'] = 'db';";
				}
			}
		&flush_file_lines_as_domain_user($d, $dbcfile);
		}

	# Figure out folder names
	local %fmap;
	$fmap{'drafts'} = $config{'drafts_folder'} || 'drafts';
	$fmap{'sent'} = $config{'sent_folder'} || 'sent';
	$fmap{'trash'} = $config{'trash_folder'} || 'sent';
	local ($sdmode, $sdpath) = &get_domain_spam_delivery($d);
	if (($sdmode == 6 || $sdmode == 4) && $sdpath) {
		$fmap{'junk'} = $sdpath;
		}
	elsif ($sdmode == 1 && $sdpath =~ /^Maildir\/\.?(\S+)\/$/) {
		$fmap{'junk'} = $1;
		}

	# Fix up the main config file
	local $mcfileorig = "$opts->{'dir'}/config/main.inc.php.dist";
	local $mcfile = "$opts->{'dir'}/config/main.inc.php";
	if (!-r $mcfileorig) {
		$mcfileorig = "$opts->{'dir'}/config/config.inc.php.sample";
		$mcfile = "$opts->{'dir'}/config/config.inc.php";
		}
	&copy_source_dest_as_domain_user($d, $mcfileorig, $mcfile);
	local $lref = &read_file_lines_as_domain_user($d, $mcfile);
	local $vuf = &get_mail_virtusertable();
	local $added_vuf = 0;
	foreach my $l (@$lref) {
		if ($l =~ /^\$(rcmail_config|config)\['enable_caching'\]\s+=/) {
			$l = "\$${1}['enable_caching'] = FALSE;";
			}
		if ($l =~ /^\$(rcmail_config|config)\['default_host'\]\s+=/) {
			$l = "\$${1}['default_host'] = 'localhost';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['default_port'\]\s+=/) {
			$l = "\$${1}['default_port'] = 143;";
			}
		if ($l =~ /^\$(rcmail_config|config)\['smtp_server'\]\s+=/) {
			$l = "\$${1}['smtp_server'] = 'localhost';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['smtp_port'\]\s+=/) {
			$l = "\$${1}['smtp_port'] = 25;";
			}
		if ($l =~ /^\$(rcmail_config|config)\['smtp_user'\]\s+=/) {
			$l = "\$${1}['smtp_user'] = '%u';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['smtp_pass'\]\s+=/) {
			$l = "\$${1}['smtp_pass'] = '%p';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['mail_domain'\]\s+=/) {
			$l = "\$${1}['mail_domain'] = '$d->{'dom'}';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['virtuser_file'\]\s+=/ && $vuf) {
			$added_vuf = 1;
			$l = "\$${1}['virtuser_file'] = '$vuf';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['plugins'\]\s+=\s+array\(\s*$/) {
			$l = "\$${1}['plugins'] = array(\n    'virtuser_file',";
			}
		elsif ($l =~ /^\$(rcmail_config|config)\['plugins'\]\s*=\s*\[/) {
			$l = "\$${1}['plugins'] = [\n    'virtuser_file',";
			}
		if ($l =~ /^\$(rcmail_config|config)\['db_dsnw'\]\s+=/) {
			$l = "\$${1}['db_dsnw'] = 'mysql://$dbuser:".
			     &php_quotemeta($dbpass, 1)."\@$dbhost/$dbname';";
			}
		if ($l =~ /^\$(rcmail_config|config)\['(\S+)_mbox'\]\s+=/ &&
		    $fmap{$2} && $fmap{$2} ne "*") {
                        $l = "\$${1}['${2}_mbox'] = '$fmap{$2}';";
                        }
		}
	if (!$added_vuf && $vuf) {
		# Need to add virtuser_file directive, as no default exists
		push(@$lref, "\$rcmail_config['virtuser_file'] = '$vuf';");
		push(@$lref, "\$config['virtuser_file'] = '$vuf';");
		}
	&flush_file_lines_as_domain_user($d, $mcfile);

	# Run SQL setup script
	&require_mysql();
	local $sqlfile;
	if ($dbtype eq "mysql") {
		$sqlfile = "$opts->{'dir'}/SQL/mysql.initial.sql";
		}
	else {
		$sqlfile = "$opts->{'dir'}/SQL/postgres.initial.sql";
		}
	local ($ex, $out) = &mysql::execute_sql_file($dbname, $sqlfile,
					       	     $dbuser, $dbpass);
	$ex && return (-1, "Failed to run database setup script : ".
			   "<tt>$out</tt>.");
	}
else {
	# Create script of upgrade SQL to run, by extracting SQL from the old
	# version onwards from mysql.update.sql
	&require_mysql();
	local $sqltemp = &transname();
	&open_tempfile(SQLTEMP, ">$sqltemp", 0, 1);
	open(SQLIN, "<$opts->{'dir'}/SQL/mysql.update.sql");
	local $foundver = 0;
	while(<SQLIN>) {
		if (/Updates\s+from\s+version\s+(\S+)/ &&
		    &compare_versions("$1", $upgrade->{'version'}) >= 0) {
			$foundver = 1;
			}
		if ($foundver) {
			&print_tempfile(SQLTEMP, $_);
			}
		}
	close(SQLIN);
	&close_tempfile(SQLTEMP);
	if ($foundver) {
		local ($ex, $out) = &mysql::execute_sql_file($dbname, $sqltemp,
							     $dbuser, $dbpass);
		$ex && return (-1, "Failed to run database date script : ".
				   "<tt>$out</tt>.");
		}
	&unlink_file($sqltemp);
	}

# Return a URL for the user
local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "RoundCube installation complete. It can be accessed at <a target=_blank href='$url'>$url</a>.", "Under $rp using $dbphptype database $dbname", $url);
}

# script_wordpress_db_conn_desc()
# Returns a list of options for config file to update
sub script_roundcube_db_conn_desc
{
my $conn_desc =
    {
      'replace' => [ '\$(rcmail_config|config)\[[\'"]db_dsnw[\'"]\]\s*=\s*' =>
                     '\'$$sdbtype://$$sdbuser:$$sdbpass@$$sdbhost/$$sdbname\';' ],
      'func' => 'php_quotemeta',
      'func_params' => 1,
      'multi' => 1,
    };
my $db_conn_desc = 
    { 'config/config.inc.php' => 
        {
           'dbtype' => $conn_desc,
           'dbuser' => $conn_desc,
           'dbpass' => $conn_desc,
           'dbhost' => $conn_desc,
           'dbname' => $conn_desc,
        }
    };
return $db_conn_desc;
}

# script_roundcube_uninstall(&domain, version, &opts)
# Un-installs a RoundCube installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_roundcube_uninstall
{
local ($d, $version, $opts) = @_;

# Remove roundcube tables from the database
&cleanup_script_database($d, $opts->{'db'}, "(.*)");

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

return (1, "RoundCube directory and tables deleted.");
}

# script_roundcube_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_roundcube_latest
{
local ($ver) = @_;
return ( "http://roundcube.net/download/",
         $ver >= 1.5 ? "roundcubemail-([0-9\\.]+)-complete.tar.gz" :
         $ver >= 1.4 ? "roundcubemail-(1\\.4\\.[0-9\\.]+)-complete.tar.gz" :
		       "roundcubemail-(1\\.3\\.[0-9\\.]+)-complete.tar.gz" );
}

sub script_roundcube_site
{
return 'https://www.roundcube.net/';
}

sub script_roundcube_gpl
{
return 1;
}

1;

