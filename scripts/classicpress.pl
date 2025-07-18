
our (%in, %config);

# script_classicpress_desc()
sub script_classicpress_desc
{
return "ClassicPress";
}

# script_classicpress_tmdesc()
sub script_classicpress_tmdesc
{
return "CP";
}

sub script_classicpress_uses
{
return ( "php" );
}

sub script_classicpress_longdesc
{
return "A lightweight, stable, instantly familiar free open-source content management system based on WordPress";
}

# script_classicpress_versions()
sub script_classicpress_versions
{
return ( "2.4.1", "1.7.3" );
}

sub script_classicpress_category
{
return ("Blog", "CMS");
}

sub script_classicpress_php_vers
{
return ( 5 );
}

sub script_classicpress_testable
{
return 1;
}

sub script_classicpress_php_modules
{
return ( "mysql", "gd", "json", "xml" );
}

sub script_classicpress_php_optional_modules
{
return ( "curl", "ssh2", "pecl-ssh2", "date",
	 "hash", "imagick", "pecl-imagick", 
	 "iconv", "mbstring", "openssl", "zip",
	 "posix", "sockets", "tokenizer" );
}

sub script_classicpress_php_vars
{
return ([ 'memory_limit', '128M', '+' ],
	[ 'max_execution_time', 60, '+' ],
	[ 'file_uploads', 'On' ],
	[ 'upload_max_filesize', '10M', '+' ],
	[ 'post_max_size', '10M', '+' ] );
}

sub script_classicpress_dbs
{
return ( "mysql" );
}

sub script_classicpress_release
{
return 13; # Fix to simplify versions for ClassicPress
}

sub script_classicpress_php_fullver
{
my ($d, $ver, $sinfo) = @_;
if (&compare_versions($ver, "6.6") >= 0) {
	return "7.2";
	}
elsif (&compare_versions($ver, "6.3") >= 0) {
	return "7.0.0";
	}
else {
	return "5.6.20";
	}
}

# script_classicpress_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing ClassicPress
sub script_classicpress_params
{
my ($d, $ver, $upgrade) = @_;
my $rv;
my $hdir = public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	my ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= ui_table_row("Database for ClassicPress tables", $dbname);
	my $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	my @dbs = domain_databases($d, [ "mysql" ]);
	$rv .= ui_table_row("Database for ClassicPress tables",
		     ui_database_select("db", undef, \@dbs, $d, "classicpress"));
	$rv .= ui_table_row("ClassicPress table prefix",
		     ui_textbox("dbtbpref", "cp_", 20));
	$rv .= ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			   ui_opt_textbox("dir", &substitute_scriptname_template("classicpress", $d), 30, "At top level"));
	$rv .= ui_table_row("ClassicPress site name",
		ui_textbox("title", $d->{'owner'} || "My Blog", 25).
			   "&nbsp;".ui_checkbox("noauto", 1, "Do not perform initial setup", 0,
			   	"onchange=\"form.title.disabled=this.checked;document.getElementById('title_row').nextElementSibling.style.visibility=(this.checked?'hidden':'visible')\""), undef, undef, ["id='title_row'"]);
	}
return $rv;
}

# script_classicpress_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_classicpress_parse
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
	(!$in{'title'} && !$in->{'noauto'}) && return "Missing or invalid ClassicPress site name";
	$in{'passmodepass'} =~ /['"\\]/ && return "ClassicPress password cannot contain single quotes, double quotes, or backslashes";
	my $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
	my ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'noauto' => $in->{'noauto'},
		 'dbtbpref' => $in->{'dbtbpref'},
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}",
		 'title' => $in{'title'} };
	}
}

# script_classicpress_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_classicpress_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/wp-login.php") {
	return "ClassicPress appears to be already installed in the selected directory";
	}
$opts->{'dbtbpref'} =~ s/^\s+|\s+$//g;
$opts->{'dbtbpref'} = 'cp_' if (!$opts->{'dbtbpref'});
$opts->{'dbtbpref'} =~ /^\w+$/ || return "Database table prefix either not set or contains invalid characters";
$opts->{'dbtbpref'} .= "_" if($opts->{'dbtbpref'} !~ /_$/);
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $clash = find_database_table($dbtype, $dbname, "$opts->{'dbtbpref'}.*");
$clash && return "ClassicPress appears to be already using \"$opts->{'dbtbpref'}\" database table prefix";
return undef;
}

# script_classicpress_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by ClassicPress, each of which is a hash ref
# containing a name, filename and URL
sub script_classicpress_files
{
my ($d, $ver, $opts, $upgrade) = @_;
return ( { 'name' => "cli",
	   'file' => "wordpress-cli.phar",
	   'url' => "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar",
	   'nocache' => 1 } );
}

sub script_classicpress_commands
{
return ("unzip");
}

# script_classicpress_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs ClassicPress, and returns either 1 and an informational
# message, or 0 and an error
sub script_classicpress_install
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
my $dberr = check_script_db_connection(
	$d, $dbtype, $dbname, $dbuser, $dbpass);
my $d_proto = domain_has_ssl($d) ? "https://" : "http://";
my $url = script_path_url($d, $opts);
return (0, "Database connection failed : $dberr") if ($dberr);

my $dom_php_bin = &get_php_cli_command($opts->{'phpver'}) || &has_command("php");
$dom_php_bin || return (0, "Could not find PHP CLI command");
my $homebin = "$d->{'home'}/bin";
&make_dir_as_domain_user($d, $homebin, 0755) if (!-d $homebin);
my $wpcli = "$homebin/wp";
my $wpcli_old = "$opts->{'dir'}/wp-cli.phar";
&unlink_file_as_domain_user($d, $wpcli_old) if (-f $wpcli_old);
my $wp = "cd $opts->{'dir'} && $dom_php_bin $wpcli --path=\"$opts->{'dir'}\"";

# Copy WP-CLI
&make_dir_as_domain_user($d, $opts->{'dir'}, 0755) if (!-d $opts->{'dir'});
&copy_source_dest($files->{'cli'}, $wpcli);
&set_permissions_as_domain_user($d, 0750, $wpcli);

# Source URL
my $download_server =
	"https://github.com/ClassicPress/ClassicPress-release/archive/refs/tags";

# Install using cli
if (!$upgrade) {
	my $err_continue = "<br>Installation can be continued manually at <a target=_blank href='${url}wp-admin'>$url</a>.";

	# Start installation
	my $out_aux = &run_as_domain_user($d, "$wp core download $download_server/$version.zip 2>&1");
	if ($? && $out_aux !~ /Success:\s+ClassicPress\s+downloaded/i) {
		return (-1, "\`wp core download\` failed` : $out : $out_aux");
		}

	if (!$opts->{'noauto'}) {
		# Configure the database
		$out = &run_as_domain_user($d,
			"$wp config create --dbname=".quotemeta($dbname).
			" --dbprefix=".quotemeta($opts->{'dbtbpref'}).
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
		$out = &run_as_domain_user($d,
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
	# Clean up an index.html file that might take precendence over index.php
	my $hfile = $opts->{'dir'}."/index.html";
	if (-r $hfile) {
		&unlink_file_as_domain_user($d, $hfile);
		}
	
	# Add webserver records
	&script_classicpress_webserver_add_records($d, $opts);
	}
else {
	# In case of reinstalling or downgrading use --force flag
	my $wp_force = "";
	if (&compare_versions($upgrade->{'version'}, $version) >= 0) {
		$wp_force = " --force";
		}
	# Do the upgrade
	my $out_aux = &run_as_domain_user($d,
		"$wp core upgrade $download_server/$version.zip$wp_force 2>&1");
	if ($? && $out !~ /Success:\s+ClassicPress\s+updated\s+successfully/i) {
		return (-1, "\`wp core upgrade\` failed : $out : $out_aux");
		}
	}

# Install is all done, return the base URL
my $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
my $msg_type = $upgrade ? "upgrade" : "installation";
my $access_msg = $upgrade || !$opts->{'noauto'} ? "It can be accessed" : "It can be configured";
my $dbcreds = $upgrade ? "" : 
	!$opts->{'noauto'} ? "" : "<br>For database credentials, use '<tt>$dbuser</tt>' for the user, '<tt>$dbpass</tt>' for the password, and '<tt>$dbname</tt>' for the database name.";
return (1, "ClassicPress $msg_type completed. $access_msg at <a target=_blank href='${url}wp-admin'>$url</a>$dbcreds", "Under $rp using $dbphptype database $dbname", $url, !$opts->{'noauto'} ? $domuser : undef, !$opts->{'noauto'} ? $dompass : undef);
}

# script_classicpress_uninstall(&domain, version, &opts)
# Un-installs a ClassicPress installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_classicpress_uninstall
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

# Remove the webserver records
&script_classicpress_webserver_delete_records($d, $opts);

return (1, "ClassicPress directory and tables deleted.");
}

# script_classicpress_db_conn_desc()
# Returns a list of options for config file to update
sub script_classicpress_db_conn_desc
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
	   'dbhost' => 
	   {
	       'replace' => [ 'define\(\s*[\'"]DB_HOST[\'"],' => "define('DB_HOST', '\$\$sdbhost');" ],
	   },
	   'dbname' => 
	   {
	       'replace' => [ 'define\(\s*[\'"]DB_NAME[\'"],' => "define('DB_NAME', '\$\$sdbname');" ],
	   },
	}
    };
return $db_conn_desc;
}

# script_classicpress_realversion(&domain, &opts)
# Returns the real version number of some script install, or undef if unknown
sub script_classicpress_realversion
{
my ($d, $opts, $sinfo) = @_;
my $lref = read_file_lines("$opts->{'dir'}/wp-includes/version.php", 1);
foreach my $l (@$lref) {
	if ($l =~ /cp_version\s*=\s*'([0-9\.]+)'/) {
		return $1;
		}
	}
return undef;
}

# script_classicpress_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_classicpress_latest
{
my ($ver) = @_;
return ( 'https://github.com/ClassicPress/ClassicPress-release/tags',
	 $ver >= 2.4 ?
	   'ClassicPress/ClassicPress-release/releases/tag/([\\d\\.]+)"' :
	   'ClassicPress/ClassicPress-release/releases/tag/(1\\.[\\d\\.]+)"'
	);
}

sub script_classicpress_site
{
return 'https://www.classicpress.net/';
}

sub script_classicpress_gpl
{
return 1;
}

sub script_classicpress_required_quota
{
return (128, 'M') ;
}

sub script_classicpress_passmode
{
return (1, 14, '^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$');
}

sub script_classicpress_webserver_add_records
{
my ($d, $opts) = @_;
# Add Nginx webserver records for permalinks to work
if (&domain_has_website($d) eq 'virtualmin-nginx' &&
    &indexof('virtualmin-nginx', @plugins) >= 0) {
	
	my $locdir = $opts->{'path'};
	$locdir =~ s/\/$//;
	$locdir ||= '/';
	my $locdirarg = $locdir;
	$locdirarg .= '/' if ($locdirarg !~ /\/$/);
	&virtualmin_nginx::lock_all_config_files();
	my $server = &virtualmin_nginx::find_domain_server($d);
	if ($server) {
		my @locs = &virtualmin_nginx::find("location", $server);
		my ($loc) = grep {
			if ($locdir eq '/') {
				$_->{'words'}->[0] eq $locdir
				}
			else {
				$_->{'words'}->[0] =~ /\Q$locdir\E$/ 
				}	
		} @locs;
		# We already have a location for this directory
		if ($loc) {
			my $locold = $loc;
			my ($contains_try_files) =
					grep { $_->{name} eq 'try_files' &&
					       $_->{'words'}->[0] eq '$uri' &&
					       $_->{'words'}->[1] eq '$uri/' &&
					       $_->{'words'}->[2] eq ($locdirarg.'index.php?$args') }
							@{$loc->{members}};
			if ($contains_try_files) {
				# Exact record already exists
				&virtualmin_nginx::unlock_all_config_files();
				return;
				}
			else {
				# Add try_files to existing location
				push(@{$loc->{'members'}},
					{ 'name' => 'try_files',
					  'words' => [ '$uri',
						       '$uri/',
						       ($locdirarg.'index.php?$args') ]});
				&virtualmin_nginx::save_directive($server, [ $locold ], [ $loc ]);
				}
			}
		else {
			# Add a new location for installed directory
			$loc = {
				'name' => 'location',
				'words' => [ $locdir ],
				'type' => 1,
				'members' => [
					{ 'name' => 'try_files',
					  'words' => [ '$uri',
						       '$uri/',
						       ($locdirarg.'index.php?$args') ]}]};
			&virtualmin_nginx::save_directive($server, [ ], [ $loc ]);
			}
		&virtualmin_nginx::flush_config_file_lines();
		&virtualmin_nginx::unlock_all_config_files();
		&register_post_action(\&virtualmin_nginx::print_apply_nginx);
		}
	}
}

sub script_classicpress_webserver_delete_records
{
my ($d, $opts) = @_;
# Remove Nginx webserver previously added records
if (&domain_has_website($d) eq 'virtualmin-nginx' &&
    &indexof('virtualmin-nginx', @plugins) >= 0) {
	my $locdir = $opts->{'path'};
	$locdir =~ s/\/$//;
	$locdir ||= '/';
	my $locdirarg = $locdir;
	$locdirarg .= '/' if ($locdirarg !~ /\/$/);
	&virtualmin_nginx::lock_all_config_files();
	my $server = &virtualmin_nginx::find_domain_server($d);
	if ($server) {
		my @locs = &virtualmin_nginx::find("location", $server);
		my ($loc) = grep {
			if ($locdir eq '/') {
				$_->{'words'}->[0] eq $locdir
				}
			else {
				$_->{'words'}->[0] =~ /\Q$locdir\E$/ 
				}	
		} @locs;
		# Found location directive for this directory
		if ($loc) {
			my $locold = $loc;
			my ($contains_try_files) =
					grep { $_->{name} eq 'try_files' &&
					       $_->{'words'}->[0] eq '$uri' &&
					       $_->{'words'}->[1] eq '$uri/' &&
					       $_->{'words'}->[2] eq ($locdirarg.'index.php?$args') }
							@{$loc->{members}};
			# If exact record exists alone remove the
			# location, otherwise remove record alone
			my $directives_to_remove =
				(grep { $_ ne $contains_try_files } @{$loc->{members}}) ?
					$contains_try_files : $loc;
			if ($directives_to_remove) {
				&virtualmin_nginx::save_directive($server, [ $directives_to_remove ], [ ]);
				&virtualmin_nginx::flush_config_file_lines();
				&register_post_action(\&virtualmin_nginx::print_apply_nginx);
				}
			&virtualmin_nginx::unlock_all_config_files();
			}
		}
	}
}

# script_classicpress_detect_file(&domain)
# Returns the file to search for to locate a ClassicPress install
sub script_classicpress_detect_file
{
return "wp-config.php";
}

# script_classicpress_detect(&domain, &files)
# If a ClassicPress install was found, return the script info object
sub script_classicpress_detect
{
my ($d, $files) = @_;
my @sinfos;
my $phd = &public_html_dir($d);
foreach my $wpconfig (@$files) {
	my $lref = &read_file_lines($wpconfig, 1);
	my %conf;
	foreach my $l (@$lref) {
		if ($l =~ /define\(\s*'(\S+)'\s*,\s*'(.*)'/) {
			$conf{$1} = $2;
			}
		}
	next if (!$conf{'DB_NAME'});
	my $wpdir = $wpconfig;
	$wpdir =~ s/\/wp-config.php$//;
	my $wppath = $wpdir;
	$wppath =~ s/^\Q$phd\E//;
	$wppath ||= "/";
	my $cpok = 0;
	foreach my $l (@{&read_file_lines("$wpdir/wp-includes/version.php", 1)}) {
		if ($l =~ /\$cp_version/) { # Found ClassicPress
			$cpok = 1;
			last;
			}
		}
	next if (!$cpok);
	my $sinfo = {
		'opts' => {
			'dir' => $wpdir,
			'path' => $wppath,
			'db' => 'mysql_'.$conf{'DB_NAME'},
			},
		'user' => $conf{'DB_USER'},
		'pass' => $conf{'DB_PASSWORD'},
		};
	push(@sinfos, $sinfo);
	}
return @sinfos;
}

1;
