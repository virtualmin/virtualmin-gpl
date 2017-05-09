
# script_wordpress_desc()
sub script_wordpress_desc
{
return "WordPress";
}

sub script_wordpress_uses
{
return ( "php" );
}

sub script_wordpress_longdesc
{
return "A semantic personal publishing platform with a focus on aesthetics, web standards, and usability.";
}

# script_wordpress_versions()
sub script_wordpress_versions
{
return ( "4.7.4" );
}

sub script_wordpress_category
{
return "Blog";
}

sub script_wordpress_php_vers
{
local ($d, $ver) = @_;
if ($ver >= 3.2) {
	return ( 5 );
	}
else {
	return ( 4, 5 );
	}
}

sub script_wordpress_php_modules
{
return ("mysql", "gd");
}

sub script_wordpress_php_optional_modules
{
return ("curl");
}

sub script_wordpress_dbs
{
return ("mysql");
}

# script_wordpress_depends(&domain, version)
sub script_wordpress_depends
{
local ($d, $ver, $sinfo, $phpver) = @_;
local @rv;

# Check for MySQL 4+
&require_mysql();
if (&mysql::get_mysql_version() < 4) {
	push(@rv, "WordPress requires MySQL version 4 or higher");
	}

# Check for PHP 5.2+
local $phpv = &get_php_version($phpver || 5, $d);
if (!$phpv) {
	push(@rv, "Could not work out exact PHP version");
	}
elsif ($phpv < 5.2) {
	push(@rv, "Wordpress requires PHP version 5.2 or later");
	}

return @rv;
}

# script_wordpress_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing Wordpress
sub script_wordpress_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for WordPress tables", $dbname);
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql" ]);
	$rv .= &ui_table_row("Database for WordPress tables",
		     &ui_database_select("db", undef, \@dbs, $d, "wordpress"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("wordpress", $d), 30, "At top level"));
	}
return $rv;
}

# script_wordpress_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_wordpress_parse
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

# script_wordpress_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_wordpress_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/wp-login.php") {
	return "WordPress appears to be already installed in the selected directory";
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $clash = &find_database_table($dbtype, $dbname, "wp_.*");
$clash && return "WordPress appears to be already using the selected database (table $clash)";
return undef;
}

# script_wordpress_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Wordpress, each of which is a hash ref
# containing a name, filename and URL
sub script_wordpress_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = ( { 'name' => "source",
	   'file' => "wordpress-$ver.zip",
	   'url' => "http://wordpress.org/latest.zip",
	   'virtualmin' => 1,
	   'nocache' => 1 } );
return @files;
}

sub script_wordpress_commands
{
return ("unzip");
}

# script_wordpress_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs WordPress, and returns either 1 and an informational
# message, or 0 and an error
sub script_wordpress_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);
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
local $verdir = "wordpress";
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, $verdir);
$err && return (0, "Failed to extract source : $err");
local $cfileorig = "$opts->{'dir'}/wp-config-sample.php";
local $cfile = "$opts->{'dir'}/wp-config.php";

# Create the 'wordpress' virtuser, if missing
if ($config{'mail'} && $d->{'mail'}) {
	local ($wpvirt) = grep { $_->{'from'} eq 'wordpress@'.$d->{'dom'} }
			       &list_virtusers();
	if (!$wpvirt) {
		$wpvirt = { 'from' => 'wordpress@'.$d->{'dom'},
			    'to' => [ $d->{'emailto_addr'} ] };
		&create_virtuser($wpvirt);
		}
	}

# Copy and update the config file
if (!-r $cfile) {
	&run_as_domain_user($d, "cp ".quotemeta($cfileorig)." ".
				      quotemeta($cfile));
	local $lref = &read_file_lines_as_domain_user($d, $cfile);
	local $l;
	foreach $l (@$lref) {
		if ($l =~ /^define\('DB_NAME',/) {
			$l = "define('DB_NAME', '$dbname');";
			}
		if ($l =~ /^define\('DB_USER',/) {
			$l = "define('DB_USER', '$dbuser');";
			}
		if ($l =~ /^define\('DB_HOST',/) {
			$l = "define('DB_HOST', '$dbhost');";
			}
		if ($l =~ /^define\('DB_PASSWORD',/) {
			$l = "define('DB_PASSWORD', '".
			     &php_quotemeta($dbpass, 1)."');";
			}
		if ($l =~ /define\('(AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|AUTH_SALT|SECURE_AUTH_SALT|LOGGED_IN_SALT|NONCE_SALT)'/) {
			my $salt = &random_password(64);
			$l = "define('$1', '$salt');";
			}
		if ($l =~ /^define\('WP_AUTO_UPDATE_CORE',/) {
			$l = "define('WP_AUTO_UPDATE_CORE', false);";
			}
		}
	&flush_file_lines_as_domain_user($d, $cfile);
	}

# Make content directory writable, for uploads
&make_file_php_writable($d, "$opts->{'dir'}/wp-content", 0);

# Return a URL for the user
local $url = &script_path_url($d, $opts).
	     ($upgrade ? "wp-admin/upgrade.php" : "wp-admin/install.php");
local $userurl = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "WordPress installation complete. It can be accessed at <a target=_blank href='$url'>$url</a>.", "Under $rp using $dbphptype database $dbname", $userurl);
}

# script_wordpress_uninstall(&domain, version, &opts)
# Un-installs a Wordpress installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_wordpress_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Remove all wp_ tables from the database
&cleanup_script_database($d, $opts->{'db'}, "wp_");

# Take out the DB
if ($opts->{'newdb'}) {
        &delete_script_database($d, $opts->{'db'});
        }

return (1, "WordPress directory and tables deleted.");
}

# script_wordpress_realversion(&domain, &opts)
# Returns the real version number of some script install, or undef if unknown
sub script_wordpress_realversion
{
local ($d, $opts, $sinfo) = @_;
local $lref = &read_file_lines("$opts->{'dir'}/wp-includes/version.php", 1);
foreach my $l (@$lref) {
	if ($l =~ /wp_version\s*=\s*'([0-9\.]+)'/) {
		return $1;
		}
	}
return undef;
}

# script_wordpress_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_wordpress_latest
{
local ($ver) = @_;
return ( "http://wordpress.org/download/",
	 "Version\\s+([0-9\\.]+)" );
}

sub script_wordpress_site
{
return 'http://wordpress.org/';
}

sub script_phpmyadmin_gpl
{
return 1;
}

1;

