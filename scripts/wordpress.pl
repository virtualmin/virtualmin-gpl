
our (%in, %config);

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
return "A semantic personal publishing platform with a focus on aesthetics, web standards, and usability";
}

# script_wordpress_versions()
sub script_wordpress_versions
{
return ( "5.9.3" );
}

sub script_wordpress_category
{
return ("Blog", "CMS");
}

sub script_wordpress_php_vers
{
return ( 5 );
}

sub script_wordpress_php_modules
{
return ( "mysql", "gd", "json", "xml" );
}

sub script_wordpress_php_optional_modules
{
return ( "curl", "ssh2", "pecl-ssh2", "date",
         "hash", "imagick", "pecl-imagick", 
         "iconv", "mbstring", "openssl",
         "posix", "sockets", "tokenizer" );
}

sub script_wordpress_dbs
{
return ( "mysql" );
}

sub script_wordpress_release
{
return 5;	# Fix format of wp-config.php
}

sub script_wordpress_php_fullver
{
my ($d, $ver, $sinfo) = @_;
return "5.6.20";
}

sub script_wordpress_cli_virtualmin_support
{
local ($d, $ver, $sinfo, $phpver) = @_;
local @rv;
my $vm_ver = $module_info{'version'};
my ($vm_ver_parsed) = $vm_ver =~ /(\d+\.[\d]+)/;
if ($vm_ver && $vm_ver_parsed < 6.18) {
	return 0
	}
return 1;
}


# script_wordpress_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing Wordpress
sub script_wordpress_params
{
my ($d, $ver, $upgrade) = @_;
my $rv;
my $hdir = public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	my ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= ui_table_row("Database for WordPress tables", $dbname);
	my $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	my @dbs = domain_databases($d, [ "mysql" ]);
	$rv .= ui_table_row("Database for WordPress tables",
		     ui_database_select("db", undef, \@dbs, $d, "wordpress"));
	$rv .= ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			   ui_opt_textbox("dir", &substitute_scriptname_template("wordpress", $d), 30, "At top level"));
	if (script_wordpress_cli_virtualmin_support()) {
		# Can select the blog title
		$rv .= ui_table_row("WordPress Blog title",
			ui_textbox("title", $d->{'owner'} || "My Blog", 40));
		$rv .= &ui_table_row("Use WordPress CLI tool for complete setup",
			     &ui_yesno_radio("usecli", 1));
		}
	}
return $rv;
}

# script_wordpress_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_wordpress_parse
{
my ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	my $hdir = public_html_dir($d, 0);
	$in{'dir_def'} || $in{'dir'} =~ /\S/ && $in{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	if (script_wordpress_cli_virtualmin_support()) {
		$in{'title'} || return "Missing or invalid WordPress Blog title";
		}
	my $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
	my ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'usecli' => $in->{'usecli'},
		 'dbtbpref' => $in->{'dbtbpref'},
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}",
		 'title' => $in{'title'} };
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
$opts->{'dbtbpref'} =~ s/^\s+|\s+$//g;
$opts->{'dbtbpref'} = 'wp_' if (!$opts->{'dbtbpref'});
$opts->{'dbtbpref'} =~ /^\w+$/ || return "Database table prefix either not set or contains invalid characters";
$opts->{'dbtbpref'} .= "_" if($opts->{'dbtbpref'} !~ /_$/);
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $clash = find_database_table($dbtype, $dbname, "$opts->{'dbtbpref'}.*");
$clash && return "WordPress appears to be already using \"$opts->{'dbtbpref'}\" database table prefix";
return undef;
}

# script_wordpress_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Wordpress, each of which is a hash ref
# containing a name, filename and URL
sub script_wordpress_files
{
my ($d, $ver, $opts, $upgrade) = @_;
my @files;
if (script_wordpress_cli_virtualmin_support() && $opts->{'usecli'}) {
@files = (
	{ 'name' => "cli",
	   'file' => "wordpress-cli.phar",
	   'url' => "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar",
	   'nocache' => 1 } );
}
else {
@files = ( { 'name' => "source",
	   'file' => "wordpress-$ver.zip",
	   'url' => "http://wordpress.org/wordpress-$ver.zip",
	   'virtualmin' => 1 } );
	}
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
local ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;
my ($out, $ex);
if ($opts->{'newdb'} && !$upgrade) {
        my $err = create_script_database($d, $opts->{'db'});
        return (0, "Database creation failed : $err") if ($err);
        }
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $dbuser = $dbtype eq "mysql" ? mysql_user($d) : postgres_user($d);
my $dbpass = $dbtype eq "mysql" ? mysql_pass($d) : postgres_pass($d, 1);
my $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
my $dbhost = get_database_host($dbtype, $d);
my $dberr = check_script_db_connection($dbtype, $dbname, $dbuser, $dbpass);
my $d_proto = domain_has_ssl($d) ? "https://" : "http://";
my $url = script_path_url($d, $opts);
return (0, "Database connection failed : $dberr") if ($dberr);

my $dom_php_bin = &get_php_cli_command($opts->{'phpver'}) || &has_command("php");
my $wp = "cd $opts->{'dir'} && $dom_php_bin $opts->{'dir'}/wp-cli.phar";

my $script_wordpress_install_with_cli = sub
{
if (!$upgrade) {
	my $err_continue = "<br>Installation can be continued manually at <a target=_blank href='${url}wp-admin'>$url</a>.";

	# Execute the download command
	&make_dir_as_domain_user($d, $opts->{'dir'}, 0755);

	# Copy wordpress-cli
	&copy_source_dest($files->{'cli'}, "$opts->{'dir'}/wp-cli.phar");
	&set_permissions_as_domain_user($d, 0750, "$opts->{'dir'}/wp-cli.phar");

	# Start installation
	my $out = &run_as_domain_user($d, "$wp core download --version=$version 2>&1");
	if ($? && $out !~ /Success:\s+WordPress\s+downloaded/i) {
		return (-1, "\`wp core download\` failed` : $out");
		}

	# Configure the database
	my $out = &run_as_domain_user($d,
		"$wp config create --dbname=".quotemeta($dbname).
		" --dbuser=".quotemeta($dbuser)." --dbpass=".quotemeta($dbpass).
		" --dbhost=".quotemeta($dbhost)." 2>&1");
	if ($?) {
		return (-1, "\`wp config create\` failed : $out$err_continue");
		}

	# Set db prefix, if given
	if ($opts->{'dbtbpref'}) {
		my $out = &run_as_domain_user($d,
			"$wp config set table_prefix ".
			quotemeta($opts->{'dbtbpref'}).
			" --type=variable".
			" --path=".$opts->{'dir'}." 2>&1");
		if ($?) {
			return (-1, "\`wp config set table_prefix\` failed : $out$err_continue");
			}
		}
	
	# Do the install
	my $out = &run_as_domain_user($d,
		"$wp core install " .
		" --url=$d_proto".quotemeta("$d->{'dom'}$opts->{'path'}").
		" --title=".quotemeta($opts->{'title'} || $d->{'owner'}).
		" --admin_user=".quotemeta($domuser).
		" --admin_password=".quotemeta($dompass).
		" --admin_email=".quotemeta($d->{'emailto'})." 2>&1");
	if ($?) {
		return (-1, "\`wp core install\` failed : $out$err_continue");
		}

	# Force update site URL manually as suggested by the installer
	# Update `siteurl` option
	$out = &run_as_domain_user($d,
		"$wp option update siteurl \"$d_proto".quotemeta("$d->{'dom'}$opts->{'path'}")."\" 2>&1");
	if ($?) {
		return (-1, "\`wp option update siteurl\` failed : $out");
		}
	# Update `home` option
	$out = &run_as_domain_user($d,
		"$wp option update home \"$d_proto".quotemeta("$d->{'dom'}$opts->{'path'}")."\" 2>&1");
	if ($?) {
		return (-1, "\`wp option update home\` failed : $out");
		}
	# Update user `user_url` record
	$out = &run_as_domain_user($d,
		"$wp user update ".quotemeta($domuser)." --user_url=\"$d_proto".quotemeta("$d->{'dom'}$opts->{'path'}")."\" 2>&1");
	if ($?) {
		return (-1, "\`wp user update\` failed : $out");
		}
	}
else {
	# Copy latest wordpress-cli
	&copy_source_dest($files->{'cli'}, "$opts->{'dir'}/wp-cli.phar");
	&set_permissions_as_domain_user($d, 0750, "$opts->{'dir'}/wp-cli.phar");

	# Do the upgrade
	my $out = &run_as_domain_user($d,
                    "$wp core upgrade --version=$version 2>&1");
	if ($?) {
		return (-1, "\`wp core upgrade\` failed : $out");
		}
	}

# Delet edefault config
unlink_file("$opts->{'dir'}/wp-config-sample.php");

# Install is all done, return the base URL
my $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
my $msg_type = $upgrade ? "upgrade" : "installation";
return (1, "WordPress $msg_type completed. It can be accessed at <a target=_blank href='${url}wp-admin'>$url</a>.", "Under $rp using $dbphptype database $dbname", $url, $domuser, $dompass);
};

my $script_wordpress_install_no_cli = sub
{
# Extract tar file to temp dir and copy to target
my $verdir = "wordpress";
my $temp = transname();
my $err = extract_script_archive($files->{'source'}, $temp, $d,
                     $opts->{'dir'}, $verdir);
$err && return (0, "Failed to extract source : $err");
my $cfileorig = "$opts->{'dir'}/wp-config-sample.php";
my $cfile = "$opts->{'dir'}/wp-config.php";

# Create the 'wordpress' virtuser, if missing
if ($config{'mail'} && $d->{'mail'}) {
    my ($wpvirt) = grep { $_->{'from'} eq 'wordpress@'.$d->{'dom'} }
                   list_virtusers();
    if (!$wpvirt) {
        $wpvirt = { 'from' => 'wordpress@'.$d->{'dom'},
                'to' => [ $d->{'emailto_addr'} ] };
        create_virtuser($wpvirt);
        }
    }

# Copy and update the config file
if (!-r $cfile) {
    run_as_domain_user($d, "cp ".quotemeta($cfileorig)." ".
                      quotemeta($cfile));
    my $lref = read_file_lines_as_domain_user($d, $cfile);
    foreach my $l (@$lref) {
        if ($l =~ /^define\(\s*'DB_NAME',/) {
            $l = "define('DB_NAME', '$dbname');";
            }
        if ($l =~ /^define\(\s*'DB_USER',/) {
            $l = "define('DB_USER', '$dbuser');";
            }
        if ($l =~ /^define\(\s*'DB_HOST',/) {
            $l = "define('DB_HOST', '$dbhost');";
            }
        if ($l =~ /^define\(\s*'DB_PASSWORD',/) {
            $l = "define('DB_PASSWORD', '".
                 php_quotemeta($dbpass, 1)."');";
            }
        if ($l =~ /define\(\s*'(AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|AUTH_SALT|SECURE_AUTH_SALT|LOGGED_IN_SALT|NONCE_SALT)'/) {
            my $salt = random_password(64);
            $l = "define('$1', '$salt');";
            }
        if ($l =~ /^define\(\s*'WP_AUTO_UPDATE_CORE',/) {
            $l = "define('WP_AUTO_UPDATE_CORE', false);";
            }
        if ($l =~ /^\$table_prefix/) {
            $l = "\$table_prefix = '" . $opts->{'dbtbpref'} . "';";
            }
        }
    flush_file_lines_as_domain_user($d, $cfile);
    }

# Make content directory writable, for uploads
make_file_php_writable($d, "$opts->{'dir'}/wp-content", 0);

# Return a URL to complete the install
my $url = script_path_url($d, $opts).
     ($upgrade ? "wp-admin/upgrade.php" : "wp-admin/install.php");
my $userurl = script_path_url($d, $opts);
my $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
my $msg_type = $upgrade ? "upgrade" : "initial installation";
return (1, "WordPress $msg_type finished. It can be completed at <a target=_blank href='$url'>$url</a>.", "Under $rp using $dbphptype database $dbname", $userurl);
};

# Install using cli
if (script_wordpress_cli_virtualmin_support() && $dom_php_bin && $opts->{'usecli'}) {
	&$script_wordpress_install_with_cli();
	}
# Install standard way
else {
	&$script_wordpress_install_no_cli();
	}
}

# script_wordpress_uninstall(&domain, version, &opts)
# Un-installs a Wordpress installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_wordpress_uninstall
{
my ($d, $version, $opts) = @_;

# Remove the contents of the target directory
my $derr = delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Remove all wp_ tables from the database
cleanup_script_database($d, $opts->{'db'}, $opts->{'dbtbpref'});

# Take out the DB
if ($opts->{'newdb'}) {
        delete_script_database($d, $opts->{'db'});
        }

return (1, "WordPress directory and tables deleted.");
}

# script_wordpress_db_conn_desc()
# Returns a list of options for config file to update
sub script_wordpress_db_conn_desc
{
my $db_conn_desc = 
    { 'wp-config.php' => 
        {
           'dbpass' => 
           {
               'replace' => [ 'define\(\s*[\'"]DB_PASSWORD[\'"],' =>
                              'define(\'DB_PASSWORD\', \'$$sdbpass\');' ],
               'func' => 'php_quotemeta',
               'func_params' => 1,
           },
           'dbuser' => 
           {
               'replace' => [ 'define\(\s*[\'"]DB_USER[\'"],' => "define('DB_USER', '\$\$sdbuser');" ],
           },
        }
    };
return $db_conn_desc;
}

# script_wordpress_realversion(&domain, &opts)
# Returns the real version number of some script install, or undef if unknown
sub script_wordpress_realversion
{
my ($d, $opts, $sinfo) = @_;
my $lref = read_file_lines("$opts->{'dir'}/wp-includes/version.php", 1);
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
my ($ver) = @_;
return ( "http://wordpress.org/download/",
	 "Download\\s+WordPress\\s+([0-9\\.]+)" );
}

sub script_wordpress_site
{
return 'http://wordpress.org/';
}

sub script_wordpress_gpl
{
return 1;
}

sub script_wordpress_required_quota
{
return (128, 'M') ;
}

sub script_wordpress_passmode
{
return (script_wordpress_cli_virtualmin_support()) ? 1 : 0;
}

1;
