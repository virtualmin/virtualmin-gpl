
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
return ( "4.1.6", "3.5.8.2", "2.11.11.3" );
}

sub script_phpmyadmin_version_desc
{
local ($ver) = @_;
return &compare_versions($ver, "4.0") > 0 ? "$ver (Latest)" :
       &compare_versions($ver, "3.0") > 0 ? "$ver (Old)" :
					     "$ver (Un-supported)";
}

sub script_phpmyadmin_release
{
return 2;		# To fix remote host issue
}

sub script_phpmyadmin_category
{
return "Database";
}

sub script_phpmyadmin_php_vers
{
local ($d, $ver) = @_;
return $ver >= 3.1 ? ( 5 ) : ( 5, 4 );
}

sub script_phpmyadmin_php_modules
{
return ("mysql");
}

sub script_phpmyadmin_php_optional_modules
{
return ("mcrypt");
}

# Must have at least one existing DB, and PHP 5.2
sub script_phpmyadmin_depends
{
local ($d, $ver, $sinfo, $phpver) = @_;
local @rv;

&has_domain_databases($d, [ "mysql" ], 1) ||
	push(@rv, "phpMyAdmin requires a MySQL database");

# Check for PHP 5.2+ or 5.3+, if needed
my $wantver = &compare_versions($ver, "4.1.1") > 0 ? 5.3 :
	      &compare_versions($ver, "3.1") > 0 ? 5.2 : undef;
if ($wantver) {
	local $phpv = &get_php_version($phpver || 5, $d);
	if (!$phpv) {
		push(@rv, "Could not work out exact PHP version");
		}
	elsif ($phpv < $wantver) {
		push(@rv, "phpMyAdmin requires PHP version $wantver or later");
		}
	}

return @rv;
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
local ($d, $ver, $opts, $upgrade) = @_;
if (&compare_versions($ver, 2.2) < 0) {
	$ver = $ver."-php";
	}
elsif (&compare_versions($ver, "2.9.1.1") >= 0) {
	if ($opts->{'all_langs'}) {
		$ver = $ver."-all-languages";
		}
	else {
		$ver = $ver."-english";
		}
	}
elsif (&compare_versions($ver, "2.10.0") >= 0) {
	$ver = $ver."--all-languages-utf-8-only";
	}
local @files = ( { 'name' => "source",
	   'file' => "phpMyAdmin-$ver.zip",
	   'url' => "http://osdn.dl.sourceforge.net/sourceforge/phpmyadmin/phpMyAdmin-$ver.zip" } );
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
local $dbuser = &mysql_user($d);
local $dbpass = &mysql_pass($d);
local $dbhost = &get_database_host("mysql");

# Extract tar file to temp dir and copy to target
local $verdir = &compare_versions($ver, "2.9.1.1") >= 0 ?
	"phpMyAdmin-$ver-*" : "phpMyAdmin-$ver";
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, $verdir);
$err && return (0, "Failed to extract source : $err");
local $cfile = "$opts->{'dir'}/config.inc.php";
if (!-r $cfile) {
	local $cdef = "$opts->{'dir'}/config.default.php";
	$cdef = "$opts->{'dir'}/libraries/config.default.php" if (!-r $cdef);
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
	if ($opts->{'auto'}) {
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['user'\]/) {
			$l = "\$cfg['Servers'][\$i]['user'] = '$dbuser';";
			}
		if ($l =~ /^\$cfg\['Servers'\]\[\$i\]\['password'\]/) {
			$l = "\$cfg['Servers'][\$i]['password'] = '".
			     &php_quotemeta($dbpass)."';";
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
			     &php_quotemeta($dbpass)."';";
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
if (&compare_versions($ver, "4.0") > 0) {
	return ( "http://www.phpmyadmin.net/home_page/downloads.php",
		 "phpMyAdmin-([0-9\\.]+)-all-languages\\.zip" );
	}
elsif (&compare_versions($ver, "3.0") > 0) {
	return ( "https://sourceforge.net/projects/phpmyadmin/files/phpMyAdmin/",
		 "(3\\.[0-9\\.]+)" );
	}
elsif (&compare_versions($ver, "2.11") > 0) {
	return ( "https://sourceforge.net/projects/phpmyadmin/files/phpMyAdmin/",
		 "(2\\.11\\.[0-9\\.]+)" );
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

