
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
return "A browser-based MySQL database management interface.";
}

# script_phpmyadmin_versions()
sub script_phpmyadmin_versions
{
return ( "2.10.1", "2.9.2", "2.8.2.4" );
}

sub script_phpmyadmin_version_desc
{
local ($ver) = @_;
return &compare_versions($ver, "2.10") > 0 ? "$ver (Latest)" : "$ver (Old)";
}

sub script_phpmyadmin_category
{
return "Database";
}

sub script_phpmyadmin_php_vers
{
return ( 4, 5 );
}

sub script_phpmyadmin_php_modules
{
return ("mysql");
}

# script_phpmyadmin_depends(&domain, version)
sub script_phpmyadmin_depends
{
local ($d, $ver) = @_;
local @dbs = &domain_databases($d, [ "mysql" ]);
return "phpMyAdmin requires a MySQL database" if (!@dbs);
return undef;
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
	$rv .= &ui_table_row("Automatically login to MySQL?",
		     $upgrade->{'opts'}->{'auto'} ? $text{'yes'} : $text{'no'});
	local @dbnames = split(/\s+/, $upgrade->{'opts'}->{'db'});
	$rv .= &ui_table_row("Databases to manage",
		join(" ", @dbnames) || "<i>All databases</i>");
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	$rv .= &ui_table_row("Automatically login to MySQL?",
		&ui_radio("auto", 0, [ [ 1, "Yes (Possibly dangerous)" ],
				       [ 0, "No" ] ]));
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
			     &ui_opt_textbox("dir", "phpmyadmin", 30,
					     "At top level"));
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
		 'auto' => $in->{'auto'} };
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
local ($d, $ver, $opts, $upgrade) = @_;
if (&compare_versions($ver, 2.2) < 0) {
	$ver = $ver."-php";
	}
elsif (&compare_versions($ver, "2.9.1.1") >= 0) {
	$ver = $ver."-english";
	}
elsif (&compare_versions($ver, "2.10.0") >= 0) {
	$ver = $ver."--all-languages-utf-8-only";
	}
local @files = ( { 'name' => "source",
	   'file' => "phpMyAdmin-$ver.zip",
	   'url' => "http://osdn.dl.sourceforge.net/sourceforge/phpmyadmin/phpMyAdmin-$ver.zip" } );
return @files;
}

# script_phpmyadmin_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs phpMyAdmin, and returns either 1 and an informational
# message, or 0 and an error
sub script_phpmyadmin_install
{
local ($d, $ver, $opts, $files, $upgrade) = @_;
local ($out, $ex);
&has_command("unzip") ||
	return (0, "The unzip command is needed to extract the phpMyAdmin source");
local @dbs = split(/\s+/, $opts->{'db'});
local $dbuser = &mysql_user($d);
local $dbpass = &mysql_pass($d);
local $dbhost = &get_database_host("mysql");

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Extract tar file to temp dir
local $temp = &transname();
mkdir($temp, 0755);
chown($d->{'uid'}, $d->{'gid'}, $temp);
$out = &run_as_domain_user($d, "cd ".quotemeta($temp).
			       " && unzip $files->{'source'}");
local $verdir = &compare_versions($ver, "2.9.1.1") >= 0 ?
	"phpMyAdmin-$ver-english" : "phpMyAdmin-$ver";
if (&compare_versions($ver, "2.9.1.1") >= 0) {
	$version = $ver."-english";
	}
-r "$temp/$verdir/config.inc.php" ||
  -r "$temp/$verdir/config.default.php" ||
    -r "$temp/$verdir/libraries/config.default.php" ||
      return (0, "Failed to extract source ($temp/$verdir/config.inc.php) : <tt>$out</tt>.");

# Move source dir to target
$out = &run_as_domain_user($d, "cp -rp ".quotemeta($temp)."/$verdir/* ".
			       quotemeta($opts->{'dir'}));
local $cfile = "$opts->{'dir'}/config.inc.php";
if (!-r $cfile) {
	local $cdef = "$opts->{'dir'}/config.default.php";
	$cdef = "$opts->{'dir'}/libraries/config.default.php" if (!-r $cdef);
	&run_as_domain_user($d, "cp ".quotemeta($cdef)." ".quotemeta($cfile));
	}
-r $cfile || return (0, "Failed to copy source : <tt>$out</tt>.");

# Update the config file
local $lref = &read_file_lines($cfile);
local $l;
local $url = &script_path_url($d, $opts);
local $dbs = join(" ", @dbs);
foreach $l (@$lref) {
	# These are for phpMyAdmin 2.6+
	if ($opts->{'auto'}) {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['user'\]/) {
			$l = "\$cfg['Servers'][\$i]['user'] = '$dbuser';";
			}
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['password'\]/) {
			$l = "\$cfg['Servers'][\$i]['password'] = '$dbpass';";
			}
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['host'\]/) {
			$l = "\$cfg['Servers'][\$i]['host'] = '$dbhost';";
			}
		}
	else {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['auth_type'\]/) {
			$l = "\$cfg['Servers'][\$i]['auth_type'] = 'cookie';";
			}
		}
	if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['only_db'\]/) {
		$l = "\$cfg['Servers'][\$i]['only_db'] = '$dbs';";
		}

	# These are for version 2.2.7
	if ($opts->{'auto'}) {
		if ($l =~ /^\$cfgServers\[\$i\]\['user'\]/) {
			$l = "\$cfgServers[\$i]['user'] = '$dbuser';";
			}
		if ($l =~ /^\$cfgServers\[\$i\]\['password'\]/) {
			$l = "\$cfgServers[\$i]['password'] = '$dbpass';";
			}
		if ($l =~ /^\$cfgServers\[\$i\]\['host'\]/) {
			$l = "\$cfgServers[\$i]['host'] = '$dbhost';";
			}
		}
	else {
		if ($l =~ /^\$cfgServers\[\$i\]\['auth_type'\]/) {
			$l = "\$cfgServers[\$i]['auth_type'] = 'cookie';";
			}
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
	}
&flush_file_lines($cfile);

# Return a URL for the user
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "phpMyAdmin installation complete. It can be accessed at <a href='$url'>$url</a>.", "Under $rp", $url);
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
if (&compare_versions($ver, "2.10") > 0) {
	return ( "http://www.phpmyadmin.net/home_page/index.php",
		 "http://prdownloads.sourceforge.net/phpmyadmin/phpMyAdmin-([0-9\\.]+)-all-languages-utf-8-only\\.zip" );
	}
else {
	return ( );
	}
}

1;

