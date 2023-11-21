
# script_phpmyadmin_desc()
sub script_phpmyadmin_desc
{
return "phpMyAdmin";
}

sub script_phpmyadmin_uses
{
return ( "php" );
}

# script_phpmyadmin_longdesc()
sub script_phpmyadmin_longdesc
{
return "A browser-based MySQL database management interface";
}

# script_phpmyadmin_versions()
sub script_phpmyadmin_versions
{
return ( "5.2.1", "4.9.11" );
}

sub script_phpmyadmin_preferred_version
{
my @vers = grep { !/^6/ } &script_phpmyadmin_versions();
return $vers[0];
}

sub script_phpmyadmin_version_desc
{
local ($ver) = @_;
return &compare_versions($ver, "6") >= 0 ? "$ver (devel)" :
       &compare_versions($ver, "5") >= 0 ? "$ver" : "$ver (LTS)";
}

sub script_phpmyadmin_release
{
return 13;		# compare_versions is not compare_version_numbers
}

sub script_phpmyadmin_can_upgrade
{
local ($sinfo, $newver) = @_;
if (&compare_versions($newver, 6) >= 0 &&
    &compare_versions($sinfo->{'version'}, 5) <= 0) {
	# Cannot upgrade 5 -> 6 devel
	return 0;
	}
return 1;
}

sub script_phpmyadmin_category
{
return "Database";
}

sub script_phpmyadmin_php_vers
{
return ( 5 );
}

sub script_phpmyadmin_testable
{
return 1;
}

sub script_phpmyadmin_php_modules
{
return ("mysql", "json", "mbstring", "session",
        "zip", "gd", "openssl", "xml");
}

# script_phpmyadmin_php_vars()
# Returns an array of extra PHP variables needed for this script
sub script_phpmyadmin_php_vars
{
return ([ 'memory_limit', '128M', '+' ],
        [ 'max_execution_time', 300, '+' ],
        [ 'file_uploads', 'On' ],
        [ 'upload_max_filesize', '1G', '+' ],
        [ 'post_max_size', '1G', '+' ]);
}


sub script_phpmyadmin_php_optional_modules
{
my ($d, $ver, $phpver, $opts) = @_;
if (&compare_versions($phpver, "7.1") < 0) {
	return ("mcrypt");
	}
return ();
}

sub script_phpmyadmin_php_fullver
{
my ($d, $ver, $sinfo) = @_;
my $wantver = &compare_versions($ver, "5.0") > 0 ? 7.1 : 5.6;
return $wantver;
}

# script_phpmyadmin_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_phpmyadmin_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	$rv .= &ui_table_row("Allow logins with empty passwords",
		     $upgrade->{'opts'}->{'emptypass'} ? $text{'yes'} : $text{'no'});
	if ($d->{'mysql'}) {
		$rv .= &ui_table_row("Automatically login to phpMyAdmin",
			$upgrade->{'opts'}->{'auto'} ? $text{'yes'} : $text{'no'});
		}
	local @dbnames = split(/\s+/, $upgrade->{'opts'}->{'db'});
	$rv .= &ui_table_row("Databases to manage",
		join(" ", @dbnames) || "<i>All databases</i>");
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	$rv .= &ui_table_row("Allow logins with empty passwords",
		&ui_radio("emptypass", 0, [ [ 1, "Yes" ],
				       [ 0, "No" ] ]));
	if ($d->{'mysql'}) {
		$rv .= &ui_table_row("Automatically login to phpMyAdmin",
			&ui_radio("auto", 0, [ [ 1, "Yes" ],
					[ 0, "No" ] ]));
		}
	local @dbs = &domain_databases($d, [ "mysql" ]);
	$rv .= &ui_table_row("Database to manage",
		     &ui_radio("db_def", 1, [ [ 1, "All databases" ],
					      [ 0, "Only selected .." ] ]).
		     "<br>\n".
		     &ui_select("db", undef,
			[ map { [ $_->{'name'},
				  $_->{'name'}." ($_->{'type'})" ] } @dbs ],
			5, 1));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("phpmyadmin", $d), 30, "At top level"));
	if ($ver >= 3) {
		$rv .= &ui_table_row("Include all languages?",
				     &ui_yesno_radio("all_langs", 0));
		}
	}
return $rv;
}

# script_phpmyadmin_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_phpmyadmin_parse
{
local ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	local $hdir = &public_html_dir($d, 0);
	$in->{'dir_def'} || $in->{'dir'} =~ /\S/ && $in->{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	local $dir = $in->{'dir_def'} ? $hdir : "$hdir/$in->{'dir'}";
	if (!$in->{'db_def'} && !$in->{'db'}) {
		return "No MySQL database to manage selected";
		}
	return { 'db' => $in->{'db_def'} ? undef
				       : join(" ", split(/\0/, $in->{'db'})),
		 'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'emptypass' => $in->{'emptypass'},
		 'auto' => $in->{'auto'},
		 'all_langs' => $in->{'all_langs'} };
	}
}

# script_phpmyadmin_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_phpmyadmin_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
if (-r "$opts->{'dir'}/config.inc.php") {
	return "phpMyAdmin appears to be already installed in the selected directory";
	}
return undef;
}

# script_phpmyadmin_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by PHP-Nuke, each of which is a hash ref
# containing a name, filename and URL
sub script_phpmyadmin_files
{
my ($d, $ver, $opts, $upgrade) = @_;
my $origver = $ver;
my $url;
if (&compare_versions($ver, 6) >= 0) {
	# Fix version number to match snapshot
	$ver = $ver."+snapshot";
	}
if ($opts->{'all_langs'}) {
	$ver = $ver."-all-languages";
	}
else {
	$ver = $ver."-english";
	}
$url = "https://files.phpmyadmin.net/phpMyAdmin/$origver/phpMyAdmin-$ver.zip";
if (&compare_versions($ver, 6) >= 0) {
	$url = "https://files.phpmyadmin.net/snapshots/phpMyAdmin-$ver.zip";
	}
local @files = ( { 'name' => "source",
	   'file' => "phpMyAdmin-$ver.zip",
	   'url' => $url } );
return @files;
}

sub script_phpmyadmin_commands
{
return ("unzip");
}

# script_phpmyadmin_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs phpMyAdmin, and returns either 1 and an informational
# message, or 0 and an error
sub script_phpmyadmin_install
{
local ($d, $ver, $opts, $files, $upgrade) = @_;
local ($out, $ex);
local @dbs = map { s/^mysql_//; $_ } split(/\s+/, $opts->{'db'});
local $dbuser;
local $dbpass;
local $dbhost = 'localhost';
if ($d->{'mysql'}) {
	$dbuser = &mysql_user($d);
	$dbpass = &mysql_pass($d);
	$dbhost = &get_database_host("mysql", $d);
	}
# Delete old files known to be obsolete
if ($upgrade && $ver >= 4) {
	&unlink_file_as_domain_user($d, "$opts->{'dir'}/main.php");
	&unlink_file_as_domain_user($d, "$opts->{'dir'}/libraries/header_http.inc.php");
	}

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, "phpMyAdmin*");
$err && return (0, "Failed to extract source : $err");
local $cfile = "$opts->{'dir'}/config.inc.php";
if (!-r $cfile) {
	local $cdef = "$opts->{'dir'}/config.default.php";
	$cdef = "$opts->{'dir'}/libraries/config.default.php" if (!-r $cdef);
	$cdef = "$opts->{'dir'}/config.sample.inc.php" if (!-r $cdef);
	&run_as_domain_user($d, "cp ".quotemeta($cdef)." ".quotemeta($cfile));
	}
-r $cfile || return (0, "Failed to copy config file");

# Update the config file
local $lref = &read_file_lines_as_domain_user($d, $cfile);
local $l;
local $url = &script_path_url($d, $opts);
local $dbs = join(" ", @dbs);
local $dbsarray = @dbs ? "Array(".join(", ", map { "'$_'" } @dbs).")" : "''";
foreach $l (@$lref) {
	# These are for phpMyAdmin 2.6+
	if ($opts->{'emptypass'}) {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/) {
			$l = "\$cfg['Servers'][\$i]['AllowNoPassword'] = true;";
			}
		}
	if ($opts->{'auto'}) {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['auth_type'\]/) {
			$l = "\$cfg['Servers'][\$i]['auth_type'] = 'config';";
			}
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['user'\]/) {
			$l = "\$cfg['Servers'][\$i]['user'] = '$dbuser';";
			}
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['password'\]/) {
			$l = "\$cfg['Servers'][\$i]['password'] = '".
			     &php_quotemeta($dbpass, 1)."';";
			}
		}
	else {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['auth_type'\]/) {
			$l = "\$cfg['Servers'][\$i]['auth_type'] = 'cookie';";
			}
		}
	if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['host'\]/) {
		$l = "\$cfg['Servers'][\$i]['host'] = '$dbhost';";
		}
	if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['only_db'\]/) {
		$l = "\$cfg['Servers'][\$i]['only_db'] = $dbsarray;";
		}
	if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['hide_db'\]/) {
		$l = "\$cfg['Servers'][\$i]['hide_db'] = 'information_schema';";
		}

	# These are for version 2.2.7
	if ($opts->{'auto'}) {
		if ($l =~ /^\$cfgServers\[\$i\]\['user'\]/) {
			$l = "\$cfgServers[\$i]['user'] = '$dbuser';";
			}
		if ($l =~ /^\$cfgServers\[\$i\]\['password'\]/) {
			$l = "\$cfgServers[\$i]['password'] = '".
			     &php_quotemeta($dbpass, 1)."';";
			}
		}
	else {
		if ($l =~ /^\$cfgServers\[\$i\]\['auth_type'\]/) {
			$l = "\$cfgServers[\$i]['auth_type'] = 'cookie';";
			}
		}
	if ($l =~ /^\$cfgServers\[\$i\]\['host'\]/) {
		$l = "\$cfgServers[\$i]['host'] = '$dbhost';";
		}
	if ($l =~ /^\$cfgServers\[\$i\]\['only_db'\]/) {
		$l = "\$cfgServers[\$i]['only_db'] = '$dbs';";
		}
	if ($l =~ /^\$cfgPmaAbsoluteUri/) {
		$l = "\$cfgPmaAbsoluteUri = '$url';";
		}

	# These are for version 2.7
	if ($l =~ /^\$cfgServers\[\$i\]\['blowfish_secret'\]/) {
		local $rand = &random_password(32);
		$l = "\$cfgServers[\$i]['blowfish_secret'] = '$rand';";
		}

	# These are for version 2.8.1
	if ($l =~ /^\$cfg\['blowfish_secret'\]/) {
		local $rand = &random_password(32);
		$l = "\$cfg['blowfish_secret'] = '$rand';";
		}

	# Turn off warning message about config DB
	if ($l =~ /^\$cfg\['PmaNoRelation_DisableWarning'\]/) {
		$l = "\$cfg['PmaNoRelation_DisableWarning'] = true;";
		}
	}
&flush_file_lines_as_domain_user($d, $cfile);

# Delete the setup directory
&unlink_file_as_domain_user($d, "$opts->{'dir'}/setup");
&unlink_file_as_domain_user($d, "$opts->{'dir'}/scripts/setup.php");

# Return a URL for the user
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "phpMyAdmin installation complete. It can be accessed at <a target=_blank href='$url'>$url</a>.", "Under $rp", $url, $dbuser, $dbpass);
}

# script_phpmyadmin_uninstall(&domain, version, &opts)
# Un-installs a phpMyAdmin installation, by deleting the directory.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_phpmyadmin_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

return (1, "phpMyAdmin directory deleted.");
}

# script_phpmyadmin_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_phpmyadmin_latest
{
local ($ver) = @_;
if (&compare_versions($ver, "6") > 0) {
	return ( "http://www.phpmyadmin.net/home_page/downloads.php",
		 "phpMyAdmin-(6\\.[0-9\\.]+)\\+snapshot-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "5") > 0) {
	return ( "http://www.phpmyadmin.net/home_page/downloads.php",
		 "phpMyAdmin-(5\\.[0-9][0-9\\.]+)-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "4.5") > 0) {
	return ( "http://www.phpmyadmin.net/home_page/downloads.php",
		 "phpMyAdmin-(4\\.[5-9][0-9\\.]+)-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "4.3") > 0) {
	return ( "https://www.phpmyadmin.net/files/",
		 "phpMyAdmin-(4\\.[2-4][0-9\\.]+)-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "4.0") > 0) {
	return ( "https://www.phpmyadmin.net/files/",
		 "phpMyAdmin-(4\\.0\\.[0-9\\.]+)-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "3.0") > 0) {
	return ( "https://www.phpmyadmin.net/files/",
		 "(3\\.5\\.[0-9]+\\.[0-9\\.]+)" );
	}
else {
	return ( );
	}
}

sub script_phpmyadmin_site
{
return "http://www.phpmyadmin.net/";
}

sub script_phpmyadmin_gpl
{
return 1;
}

1;

