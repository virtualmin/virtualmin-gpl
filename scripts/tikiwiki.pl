
# script_tikiwiki_desc()
sub script_tikiwiki_desc
{
return "Tiki Wiki CMS Groupware";
}

sub script_tikiwiki_uses
{
return ( "php" );
}

sub script_tikiwiki_longdesc
{
return "A full featured free software Wiki/CMS/Groupware written in PHP";
}

# script_tikiwiki_versions()
sub script_tikiwiki_versions
{
return ( "27.1", "24.7", "21.10" );
}

sub script_tikiwiki_release
{
return 1; # Fix installer and rename htpasswd file
}

sub script_tikiwiki_testable
{
return 1;
}

sub script_tikiwiki_category
{
return "Wiki";
}

sub script_tikiwiki_php_vers
{
local ($d, $ver) = @_;
return ( 5 );
}

sub script_tikiwiki_php_modules
{
local ($d, $ver, $phpver, $opts) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local @rv = $dbtype eq "mysql" ? ("mysql") : ("pgsql");
push(@rv, "xml", "intl", "zip", "gd", "mbstring");
return @rv;
}

sub script_tikiwiki_dbs
{
return ("mysql", "postgres");
}

sub script_tikiwiki_php_fullver
{
local ($d, $ver, $sinfo) = @_;
return &compare_versions($ver, 13) < 0 ? undef :
       &compare_versions($ver, 22) >= 0 ? 7.4 : 5.5;
}

sub script_tikiwiki_can_upgrade
{
local ($sinfo, $newver) = @_;
if ($newver >= 26 &&
    $sinfo->{'version'} <= 25) {
	# Upgrades not yet working correctly
	# https://tiki.org/forumthread79198-Isssue-with-upgrade-from-Ver-25-to-26-1
	return 0;
	}
return 1;
}

sub script_tikiwiki_php_vars
{
return ( [ 'memory_limit', '128M', '+' ] );
}

# script_tikiwiki_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing TikiWiki
sub script_tikiwiki_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for TikiWiki tables", $dbname);
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Database for TikiWiki tables",
		     &ui_database_select("db", undef, \@dbs, $d, "tikiwiki"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("tikiwiki", $d), 30, "At top level"));
	}
return $rv;
}

# script_tikiwiki_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_tikiwiki_parse
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

# script_tikiwiki_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_tikiwiki_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
if (-r "$opts->{'dir'}/tiki-install.php") {
	return "TikiWiki appears to be already installed in the selected directory";
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $clash = &find_database_table($dbtype, $dbname, "tiki_.*");
$clash && return "TikiWiki appears to be already using the selected database (table $clash)";
return undef;
}

# script_tikiwiki_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by TikiWiki, each of which is a hash ref
# containing a name, filename and URL
sub script_tikiwiki_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = ( { 'name' => "source",
	   'file' => "tikiwiki-$ver.zip",
	   'url' => "http://osdn.dl.sourceforge.net/sourceforge/tikiwiki/tiki-$ver.zip" } );
return @files;
}

sub script_tikiwiki_commands
{
return ("unzip");
}

# script_tikiwiki_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_tikiwiki_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);
if ($opts->{'newdb'} && !$upgrade) {
	local $dbopts = { 'charset' => 'utf8' };
        local $err = &create_script_database($d, $opts->{'db'}, $dbopts);
        return (0, "Database creation failed : $err") if ($err);
        }
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = &mysql_user($d);
local $dbpass = &mysql_pass($d);
local $dbhost = &get_database_host($dbtype, $d);
local $dberr = &check_script_db_connection($d, $dbtype, $dbname, $dbuser, $dbpass);
return (0, "Database connection failed : $dberr") if ($dberr);

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, "tiki-$ver");
$err && return (0, "Failed to extract source : $err");
local $cfile = "$opts->{'dir'}/db/local.php";

if (!$upgrade) {
	# Create the config file
	&open_tempfile_as_domain_user($d, CONFIG, ">$cfile");
	&print_tempfile(CONFIG,
		"<?php\n".
		"\$db_tiki = 'mysql';\n".
		"\$dbversion_tiki = '8.0';\n".
		"\$host_tiki = '$dbhost';\n".
		"\$user_tiki = '$dbuser';\n".
		"\$pass_tiki = '$dbpass';\n".
		"\$dbs_tiki = '$dbname';\n".
		"\$client_charset = 'utf8';\n"
		);
	&close_tempfile_as_domain_user($d, CONFIG);

	# Rename _htaccess to .htaccess
	if (&domain_has_website($d) eq 'web') {
		&run_as_domain_user(
			$d, "mv $opts->{'dir'}/_htaccess $opts->{'dir'}/.htaccess");
		}
	}

# Delete install lock file
&unlink_file_as_domain_user($d, "$opts->{'dir'}/db/lock");

local $url = &script_path_url($d, $opts);
local $adminurl = $url."tiki-install.php";
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
if ($upgrade) {
	return (1, "Initial TikiWiki upgrade complete. Go to <a target=_blank href='$adminurl'>$adminurl</a> to complete the upgrade process.", "Under $rp using $dbtype database $dbname", $url, "admin", "admin");
	}
else {
	return (1, "Initial TikiWiki installation complete. Go to <a target=_blank href='$adminurl'>$adminurl</a> to finish installing it.", "Under $rp using $dbtype database $dbname", $url, "admin", "admin");
	}
}

# script_tikiwiki_uninstall(&domain, version, &opts)
# Un-installs a TikiWiki installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_tikiwiki_uninstall
{
local ($d, $version, $opts) = @_;

# Remove phpbb tables from the database
&cleanup_script_database($d, $opts->{'db'},
			 "(tiki_|galaxia_|messu_|sessions|users_|metrics_)");

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

if ($dbtype) {
	return (1, "TikiWiki directory and tables deleted.");
	}
else {
	return (1, "TikiWiki directory deleted.");
	}
}

sub script_tikiwiki_db_conn_desc
{
my $db_conn_desc = 
    { 'db/local.php' => 
        {
           'dbpass' =>
           {
               'func'        => 'php_quotemeta',
               'func_params' => 1,
               'replace'     => [ '\$pass_tiki\s*=' =>
                                  '$pass_tiki = \'$$sdbpass\';' ],
           },
           'dbuser' =>
           {
               'replace'     => [ '\$user_tiki\s*=' =>
                                  '$user_tiki = \'$$sdbuser\';' ],
           },
        }
    };
return $db_conn_desc;
}

# script_tikiwiki_check_latest(version)
# Checks if some version is the latest for this project, and if not returns
# a newer one. Otherwise returns undef.
sub script_tikiwiki_check_latest
{
local ($ver) = @_;
local @vers;
if ($ver >= 27) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_27.x_Miaplacidus",
				       "tiki-(27\.[0-9\\.]+)\\.zip");
	}
elsif ($ver >= 26) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_26.x_Alnilam",
				       "tiki-(26\.[0-9\\.]+)\\.zip");
	}
elsif ($ver >= 25) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_25.x_Sagittarius_A",
				       "tiki-(25\.[0-9\\.]+)\\.zip");
	}
elsif ($ver >= 24) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_24.x_Wolf_359",
				       "tiki-(24\.[0-9\\.]+)\\.zip");
	}
elsif ($ver >= 21) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_21.x_UY_Scuti",
				       "tiki-(21\.[0-9\\.]+)\\.zip");
	}
elsif ($ver >= 18) {
	@vers = &osdn_package_versions("tikiwiki/Tiki_18.x_Alcyone",
				       "tiki-(18\.[0-9\\.]+)\\.zip");
	}
return "Failed to find versions" if (!@vers);
return $ver eq $vers[0] ? undef : $vers[0];
}

sub script_tikiwiki_site
{
return 'http://www.tikiwiki.org/';
}

1;
