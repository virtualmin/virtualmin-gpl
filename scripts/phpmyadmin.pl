
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
return ( "5.2.3", "4.9.11" );
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

# script_phpmyadmin_httpdauth_text()
# Returns help text for the HTTP Basic auth option
sub script_phpmyadmin_httpdauth_text
{
my $txt = $text{'script_phpmyadmin_httpdauth'} ||
	  'Protect phpMyAdmin with login and password';
return $txt;
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
	my $httpdauth_enabled =
		&script_phpmyadmin_httpdauth_is_enabled($d, $upgrade->{'opts'});
	my $httpdauth_row = &ui_table_row(
		&hlink(&script_phpmyadmin_httpdauth_text(),
		       "script_phpmyadmin_httpdauth"),
		$httpdauth_enabled
			? $text{'yes'}
			: $text{'no'});
	if ($upgrade->{'opts'}->{'global_def'}) {
		$rv .= &ui_table_row(
			&hlink($text{'script_phpmyadmin_def'},
			       "script_phpmyadmin_def"),
			$text{'yes'});
		$rv .= $httpdauth_row;
		}
	else {
		$rv .= $httpdauth_row;
		$rv .= &ui_table_row("Allow logins with empty passwords",
			$upgrade->{'opts'}->{'emptypass'}
				? $text{'yes'}
				: $text{'no'});
		if ($d->{'mysql'}) {
			$rv .= &ui_table_row("Automatically login to phpMyAdmin",
				$upgrade->{'opts'}->{'auto'}
					? $text{'yes'}
					: $text{'no'});
			}
		local @dbnames = split(/\s+/, $upgrade->{'opts'}->{'db'});
		$rv .= &ui_table_row("Databases to manage",
			join(" ", @dbnames) || "<i>All databases</i>");
		}
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# If installing as master admin as a question to make global default
	if (&master_admin() && defined &list_all_global_def_scripts_cached) {
		my $js = <<'EOF';
		<script>
		(function () {
			function byName(n) {
				return document.querySelectorAll('input[name="'+n+'"]');
			}
		
			function checkedVal(n) {
				var els = byName(n);
				for (var i = 0; i < els.length; i++) {
					if (els[i].checked) return els[i].value;
				}
				return null;
			}
		
			function setRadio(n, v) {
				var els = byName(n);
				for (var i = 0; i < els.length; i++) {
					if (els[i].value == v) {
						els[i].checked = true;
						return;
					}
				}
			}
		
			function rowForName(n) {
				var el = document.querySelector('input[name="'+n+'"], select[name="'+n+'"]');
				if (!el) return null;
				while (el && el.tagName !== 'TR') el = el.parentNode;
				return el;
			}
		
			function setRowHidden(row, hide) {
				if (!row) return;
				row.style.display = hide ? 'none' : '';
			}
		
			function setSelectDisabled(n, dis) {
				var sel = document.querySelector('select[name="'+n+'"]');
				if (sel) sel.disabled = !!dis;
			}
		
			function applyGlobal() {
				var g = checkedVal('global_def') === '1';
		
				var r1 = rowForName('emptypass');
				var r2 = rowForName('auto');
				var r3 = rowForName('db_def');
		
				if (g) {
					/* Reset hidden options to safe defaults */
					setRadio('emptypass', '0');
					setRadio('auto', '0');
					setRadio('db_def', '1');
					setSelectDisabled('db', true);
		
					setRowHidden(r1, true);
					setRowHidden(r2, true);
					setRowHidden(r3, true);
				}
				else {
					setRowHidden(r1, false);
					setRowHidden(r2, false);
					setRowHidden(r3, false);
		
					/* Re-apply current db_def state to enable/disable the db select */
					setSelectDisabled('db', checkedVal('db_def') !== '0');
				}
			}
		
			/* React to global default toggle */
			var g = byName('global_def');
			for (var i = 0; i < g.length; i++) {
				g[i].addEventListener('change', applyGlobal);
			}
		
			/* React to db_def changes when not global */
			var d = byName('db_def');
			for (var j = 0; j < d.length; j++) {
				d[j].addEventListener('change', function () {
					if (checkedVal('global_def') === '1') return;
					setSelectDisabled('db', checkedVal('db_def') !== '0');
				});
			}
		
			/* Initial state */
			applyGlobal();
		})();
		</script>
EOF
		$rv .= &ui_table_row(
			&hlink($text{'script_phpmyadmin_def'},
			       "script_phpmyadmin_def"),
			&ui_yesno_radio("global_def", 0).$js);
		}
	# Show editable install options
	$rv .= &ui_table_row(
		&hlink(&script_phpmyadmin_httpdauth_text(),
		       "script_phpmyadmin_httpdauth"),
		&ui_yesno_radio("httpdauth", 0));
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
	return { 'db' => $in->{'db_def'}
				? undef
				: join(" ", split(/\0/, $in->{'db'})),
		 'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'global_def' => &master_admin()
		 	? $in->{'global_def'}
				? 1 
				: 0 
			: 0,
		 'emptypass' => $in->{'emptypass'},
		 'auto' => $in->{'auto'},
		 'httpdauth' => $in->{'httpdauth'} ? 1 : 0,
		 'all_langs' => $in->{'all_langs'} };
	}
}

# script_phpmyadmin_httpdauth_paths(&domain, &opts)
# Returns .htaccess and .htpasswd paths for phpMyAdmin auth
sub script_phpmyadmin_httpdauth_paths
{
local ($d, $opts) = @_;
local $htaccess = ".htaccess";
local $htpasswd = ".htpasswd";
if (&foreign_check("htaccess-htpasswd")) {
	&foreign_require("htaccess-htpasswd");
	$htaccess = $htaccess_htpasswd::config{'htaccess'} || $htaccess;
	$htpasswd = $htaccess_htpasswd::config{'htpasswd'} || $htpasswd;
	}
return ("$opts->{'dir'}/$htaccess", "$opts->{'dir'}/$htpasswd", $htpasswd);
}

# script_phpmyadmin_httpdauth_is_enabled(&domain, &opts)
# Returns 1 if HTTP Basic auth files currently exist for this install
sub script_phpmyadmin_httpdauth_is_enabled
{
local ($d, $opts) = @_;
local ($htaccess_path, $htpasswd_path) =
	&script_phpmyadmin_httpdauth_paths($d, $opts);
return (-r $htaccess_path && -r $htpasswd_path) ? 1 : 0;
}

# script_phpmyadmin_httpdauth_user_pass(&domain)
# Returns username and encrypted password for basic auth
sub script_phpmyadmin_httpdauth_user_pass
{
local ($d) = @_;
local $huser = $d->{'user'};
local $hpass = $d->{'enc_pass'} || $d->{'md5_enc_pass'} ||
	       $d->{'crypt_enc_pass'};
if ((!$huser || !$hpass) && $d->{'parent'}) {
	local $pd = &get_domain($d->{'parent'});
	$huser ||= $pd->{'user'};
	$hpass ||= $pd->{'enc_pass'} || $pd->{'md5_enc_pass'} ||
		   $pd->{'crypt_enc_pass'};
	}
return ($huser, $hpass);
}

# script_phpmyadmin_httpdauth_cleanup(&domain, &opts)
# Removes protected-dir metadata for phpMyAdmin basic auth
sub script_phpmyadmin_httpdauth_cleanup
{
local ($d, $opts) = @_;
local ($htaccess_path, $htpasswd_path) =
	&script_phpmyadmin_httpdauth_paths($d, $opts);

# Remove protected directory in webserver plugins
foreach my $p (&list_feature_plugins()) {
	if (&plugin_defined($p, "feature_delete_protected_dir")) {
		&plugin_call($p, "feature_delete_protected_dir",
			     $d,
			     { 'protected_dir' => $opts->{'dir'},
			       'protected_user_file_path' => $htpasswd_path });
		}
	}

# Remove from list of protected directories
if (&foreign_check("htaccess-htpasswd")) {
	&foreign_require("htaccess-htpasswd");
	&lock_file($htaccess_htpasswd::directories_file);
	local @pdirs = &htaccess_htpasswd::list_directories();
	@pdirs = grep { ref($_) ? $_->[0] ne $opts->{'dir'}
				: $_ ne $opts->{'dir'} } @pdirs;
	&htaccess_htpasswd::save_directories(\@pdirs);
	&unlock_file($htaccess_htpasswd::directories_file);
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
# If already global check and show error if it is
if ($opts->{'global_def'} && defined &list_all_global_def_scripts_cached) {
	# Invalidate global scripts default cache
	&invalidate_global_def_scripts_cache();
	# Check if another global default exists
	my @all_glob_cache = &list_all_global_def_scripts_cached();
	@all_glob_cache = grep { $_->{'name'} eq 'phpmyadmin' } @all_glob_cache;
	return @all_glob_cache
		? "phpMyAdmin is already installed as a global default in domain ".
			&get_domain($all_glob_cache[0]->{'dom_id'})->{'dom'}
		: undef;
	}
if ($opts->{'httpdauth'}) {
	local ($huser, $hpass) = &script_phpmyadmin_httpdauth_user_pass($d);
	$huser || return "Cannot enable HTTP Basic authentication because ".
			 "this domain has no owner username";
	$hpass || return "Cannot enable HTTP Basic authentication because ".
			 "this domain has no encrypted password";
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

# Invalidate global scripts default cache
if ($opts->{'global_def'} && defined &invalidate_global_def_scripts_cache) {
	&invalidate_global_def_scripts_cache();
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

# Enable optional HTTP basic auth for the install directory
if ($opts->{'httpdauth'} && !$upgrade) {
	my ($huser, $hpass) = &script_phpmyadmin_httpdauth_user_pass($d);
	my ($htaccess_path, $htpasswd_path, $htpasswd_file) =
		&script_phpmyadmin_httpdauth_paths($d, $opts);
	my $authname = "phpMyAdmin";
	my $htaccess_content =
		"AuthType Basic\n".
		"AuthName \"$authname\"\n".
		"AuthUserFile \"$htpasswd_path\"\n".
		"Require valid-user\n".
		"<Files \"$htpasswd_file\">\n".
		"    Require all denied\n".
		"</Files>\n";
	&lock_file($htaccess_path);
	&write_as_domain_user($d,
		sub { &write_file_contents($htaccess_path, $htaccess_content); });
	&unlock_file($htaccess_path);
	&lock_file($htpasswd_path);
	&write_as_domain_user($d,
		sub { &write_file_contents($htpasswd_path,
					   "$huser:$hpass\n"); });
	&unlock_file($htpasswd_path);
	foreach my $p (&list_feature_plugins()) {
		if (&plugin_defined($p, "feature_add_protected_dir")) {
			&plugin_call($p, "feature_add_protected_dir",
				     $d,
				     { 'protected_dir' => $opts->{'dir'},
				       'protected_user_file_path' =>
					$htpasswd_path,
				       'protected_user_file' => $htpasswd_file,
				       'protected_name' => $authname });
			}
		}
	if (&foreign_check("htaccess-htpasswd")) {
		&foreign_require("htaccess-htpasswd");
		&lock_file($htaccess_htpasswd::directories_file);
		local @pdirs = &htaccess_htpasswd::list_directories();
		if (!grep { $_->[0] eq $opts->{'dir'} &&
			    $_->[1] eq $htpasswd_path } @pdirs) {
			push(@pdirs, [ $opts->{'dir'}, $htpasswd_path ]);
			&htaccess_htpasswd::save_directories(\@pdirs);
			}
		&unlock_file($htaccess_htpasswd::directories_file);
		}
	}

# Invalidate global scripts default cache
if ($opts->{'global_def'} && defined &invalidate_global_def_scripts_cache) {
	&invalidate_global_def_scripts_cache();
	}

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

# Invalidate global scripts default cache
if ($opts->{'global_def'} && defined &invalidate_global_def_scripts_cache) {
	&invalidate_global_def_scripts_cache();
	}

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Cleanup basic auth metadata
if ($opts->{'httpdauth'}) {
	&script_phpmyadmin_httpdauth_cleanup($d, $opts);
	}

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

