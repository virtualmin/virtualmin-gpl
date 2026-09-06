
our (%in, %config);

# script_piwik_desc()
sub script_piwik_desc
{
return "Matomo";
}

sub script_piwik_uses
{
return ( "php" );
}

sub script_piwik_longdesc
{
return "Matomo is an open source web analytics software. It gives interesting reports on your website visitors, your popular pages and more";
}

# script_piwik_versions()
sub script_piwik_versions
{
return ( "5.13.0" );
}

sub script_piwik_can_upgrade
{
my ($sinfo, $newver) = @_;
if ($sinfo->{'version'} < 2 && $newver >= 2) {
	return 0;
	}
return 1;
}

sub script_piwik_testable
{
return 1;
}

sub script_piwik_php_vers
{
return ( 5 );
}

# script_piwik_php_modules()
# The PDO MySQL adapter is always selected by the installer, so it is required
sub script_piwik_php_modules
{
return ( "curl", "gd", "xml", "mbstring", "pdo", "pdo_mysql" );
}

sub script_piwik_dbs
{
return ("mysql");
}

sub script_piwik_php_fullver
{
my ($d, $ver, $sinfo) = @_;
return "7.2.5";
}

# script_piwik_php_vars(&domain)
# Returns an array of extra PHP variables needed for this script, matching
# the minimum memory limit advised and the session setting required by the
# Matomo system check
sub script_piwik_php_vars
{
return ( [ 'memory_limit', '128M', '+' ],
	 [ 'session.auto_start', 'Off' ] );
}

# script_piwik_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing Matomo
sub script_piwik_params
{
my ($d, $ver, $upgrade) = @_;
my $rv;
my $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	my ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for Matomo tables", $dbname);
	my $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	my @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Database for Matomo tables",
		     &ui_database_select("db", undef, \@dbs, $d, "matomo"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("matomo", $d), 30, "At top level"));
	if ($d->{'virtualmin-google-analytics'}) {
		$rv .= &ui_table_row("Use this Matomo installation for ".
				     "analytics by default?",
			&ui_yesno_radio("analytics", 1));
		}
	}
return $rv;
}

# script_piwik_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_piwik_parse
{
my ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	my $hdir = &public_html_dir($d, 0);
	$in->{'dir_def'} || $in->{'dir'} =~ /\S/ && $in->{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	my $dir = $in->{'dir_def'} ? $hdir : "$hdir/$in->{'dir'}";
	my ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
	         'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'analytics' => $in->{'analytics'}, };
	}
}

# script_piwik_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_piwik_check
{
my ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/matomo.php" || -r "$opts->{'dir'}/piwik.php") {
	return "Matomo appears to be already installed in the selected directory";
	}
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $clash = &find_database_table($dbtype, $dbname, "(piwik|matomo)_");
$clash && return "Matomo appears to be already using the selected database (table $clash)";
return undef;
}

# script_piwik_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Matomo, each of which is a hash ref
# containing a name, filename and URL
sub script_piwik_files
{
my ($d, $ver, $opts, $upgrade) = @_;
my @files = ( { 'name' => "source",
	   'file' => "matomo-$ver.zip",
	   'url' => "https://builds.matomo.org/matomo-$ver.zip" } );
return @files;
}

sub script_piwik_commands
{
return ("unzip");
}

# script_piwik_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs Matomo, and returns either 1 and an informational
# message, or 0 and an error
sub script_piwik_install
{
my ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;
my ($out, $ex);

# Create and get the DB
if ($opts->{'newdb'} && !$upgrade) {
	my $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $dbuser = &mysql_user($d);
my $dbpass = &mysql_pass($d);
my $dbhost = &get_database_host($dbtype, $d);
my $dberr = &check_script_db_connection($d, $dbtype, $dbname, $dbuser, $dbpass);
return (0, "Database connection failed : $dberr") if ($dberr);

# Extract archive to temp dir and copy to target
my $temp = &transname();
my $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, "matomo");
$err && return (0, "Failed to extract source : $err");

my $url = &script_path_url($d, $opts);
my $longpass = $dompass;
if (!$upgrade) {
	# Make config directory writable
	&make_file_php_writable($d, "$opts->{'dir'}/config");
	my $path = $opts->{'path'};
	$path .= "/" if ($path !~ /\/$/);

	my $d_ssl = domain_has_ssl($d);
	my $protocol = ($d_ssl ? 'https' : 'http');

	# Call first page of install wizard, to get the cookie
	my ($iout, $ierr);
	&get_http_connection(
		       $d, $path, \$iout, \$ierr, \&piwik_cookie_callback,
		       0, undef, undef, undef, 0, 1);
	$ierr && return (-1, "Initial install page failed : $ierr");

	# Call config verification page
	my $cheaders = { 'Cookie' => $piwik_session_cookie };
	($iout, $ierr) = (undef, undef);
	&get_http_connection(
		       $d, $path."?action=systemCheck", \$iout, \$ierr,
		       undef, 0, undef, undef, 0, 0, 1, $cheaders);
	if ($ierr) {
		return (-1, "System check page failed : $ierr");
		}
	elsif ($iout !~ /databaseSetup/) {
		return (-1, "System check failed - ".
			    "some dependencies may be missing");
		}

	# Get the DB setup form
	($iout, $ierr) = (undef, undef);
	&get_http_connection($d, $path."?action=databaseSetup&module=Installation&clientProtocol=$protocol", \$iout, \$ierr,
			     undef, 0, undef, undef, 0, 0, 1, $cheaders);

	# Submit the DB setup form
	my @params = (
		[ "type", 'InnoDB' ],
		[ "host", $dbhost ],
		[ "username", $dbuser ],
		[ "password", $dbpass ],
		[ "dbname", $dbname ],
		[ "tables_prefix", "matomo_" ],
		[ "adapter", "PDO\\MYSQL" ],
		[ "submit", "Go!" ],
		);
	my $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	my $ipage = $path."?action=databaseSetup&module=Installation&clientProtocol=$protocol";
	my %gotheaders;
	($iout, $ierr) = (undef, undef);
	&post_http_connection($d, $ipage, $params, \$iout, \$ierr, $cheaders,
			      \%gotheaders);
	if ($ierr) {
		if ($ierr !~ /tablesCreation|databaseCheck/) {
			return (-1, "Database setup failed : $ierr");
			}
		}
	elsif ($iout !~ /Tables\s+created/i) {
		return (-1, "Database setup failed");
		}

	# Call table creation page
	($iout, $ierr) = (undef, undef);
	&get_http_connection($d,
			     $path."?action=tablesCreation&module=Installation&deleteTables=1&clientProtocol=$protocol",
			     \$iout, \$ierr,
			     undef, 0, undef, undef, 0, 0, 1, $cheaders);
	if ($ierr) {
		return (-1, "Failed to create tables : $ierr");
		}

	# Call user creation form
	if (length($longpass) < 6) {
		# Matomo requires a 6-character password!
		$longpass .= "123456";
		}
	@params = (
		[ "login", $domuser ],
		[ "password", $longpass ],
		[ "password_bis", $longpass ],
		[ "email", $d->{'emailto_addr'} ],
		);
	$params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	$ipage = $path."?action=setupSuperUser&module=Installation&clientProtocol=$protocol";
	($iout, $ierr) = (undef, undef);
	&post_http_connection($d, $ipage, $params, \$iout, \$ierr, $cheaders);
	if ($ierr) {
		if ($ierr !~ /firstWebsiteSetup/) {
			return (-1, "Administrator setup failed : $ierr");
			}
		}
	elsif ($iout !~ /General\s+Setup\s+configured|Setup\s+a\s+website|Super\s+User\s+created|Superuser\s+created/i) {
		return (-1, "Administrator setup failed");
		}

	# Call initial website form
	@params = (
		[ "siteName", $d->{'owner'} || 'Analyst' ],
		[ "url", ($d_ssl ? 'https' : 'http') . "://$d->{'dom'}" ],
		[ "timezone", "UTC" ],
		[ "ecommerce", "0" ],
		[ "submit", "Next" ],
		);
	$params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	$ipage = $path."?action=firstWebsiteSetup&module=Installation&clientProtocol=$protocol";
	($iout, $ierr) = (undef, undef);
	&post_http_connection($d, $ipage, $params, \$iout, \$ierr, $cheaders);
	if ($ierr) {
		if ($ierr !~ /trackingCode/) {
			return (-1, "First website setup failed : $ierr");
			}
		}
	elsif ($iout !~ /created\s+successfully|website\s+created/i) {
		return (-1, "First website setup failed");
		}

	# Call finished page
	($iout, $ierr) = (undef, undef);
	&get_http_connection($d, $path."?action=finished&module=Installation&clientProtocol=$protocol",
			     \$iout, \$ierr,
			     undef, 0, undef, undef, 0, 0, 1, $cheaders);
	if ($ierr) {
		return (-1, "Failed to finish install : $ierr");
		}

	# Submit the finished page form
	@params = (
		[ "do_not_track", 1 ],
		[ "anonymise_ip", 1 ],
		[ "submit", "Next" ],
		);
	$params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	$ipage = $path."?action=finished&module=Installation&clientProtocol=$protocol";
	($iout, $ierr) = (undef, undef);
	&post_http_connection($d, $ipage, $params, \$iout, \$ierr, $cheaders);

	# Configure analytics module to use this Matomo URL
	if ($opts->{'analytics'} && $d->{'virtualmin-google-analytics'}) {
		&foreign_require("virtualmin-google-analytics",
				 "virtualmin-google-analytics-lib.pl");
		if (defined(
		     &virtualmin_google_analytics::save_piwik_default_url)) {
			&virtualmin_google_analytics::save_piwik_default_url(
				$d, $url);
			}
		}
	}

# Apply pending database schema changes using the Matomo console, as the
# install wizard only creates the base tables and an upgrade needs migrations
my $php = &get_php_cli_command($opts->{'phpver'}, $d) || &has_command("php");
$php || return (-1, "Could not find PHP CLI command");
my $ini = &get_domain_php_ini($d, $opts->{'phpver'}, 1);
$out = &run_as_domain_user($d, "cd ".quotemeta($opts->{'dir'})." && ".
			      "PHPRC=".quotemeta($ini)." ".quotemeta($php).
			      " console core:update --yes 2>&1");
if ($?) {
	return (-1, "Database update failed : $out");
	}

# Create an API token, so that the tracking code can be fetched from Matomo
# later. This must be done after the database update, as the API returns an
# error until it is applied. Failure is not fatal, as standard code is used
if (!$upgrade) {
	my $path = $opts->{"path"};
	$path .= "/" if ($path !~ /\/$/);
	my $tpage = $path."index.php?module=API&method=UsersManager.".
		    "createAppSpecificTokenAuth&format=json";
	my $tparams = join("&", map { $_->[0]."=".&urlize($_->[1]) }
		( [ "userLogin", $domuser ],
		  [ "passwordConfirmation", $longpass ],
		  [ "description", "Virtualmin" ] ));
	my ($tout, $terr);
	&post_http_connection($d, $tpage, $tparams, \$tout, \$terr);
	if (!$terr && $tout =~ /"value"\s*:\s*"([0-9a-f]+)"/) {
		$opts->{"token"} = $1;
		}
	}

# Tell the user about the new install
my $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
my $updmsg = $upgrade ? "Matomo upgrade" : "Initial Matomo installation";
return (1, "$updmsg complete. Go to <a target=_blank href='$url'>$url</a> to use it.", "Under $rp", $url, $domuser, $longpass );
}

# script_piwik_uninstall(&domain, version, &opts)
# Un-installs a Matomo installation, by removing it's files
# Returns 1 on success and a message, or 0 on failure and an error
sub script_piwik_uninstall
{
my ($d, $version, $opts) = @_;

# Clear database
if ($opts->{'newdb'}) {
	# Remove all tables from the database
	&cleanup_script_database($d, $opts->{'db'}, '(.*)');
	}
else {
	# Remove only default matomo_ tables from the database
	&cleanup_script_database($d, $opts->{'db'}, "(piwik|matomo)_");
	}

# Remove the contents of the target directory
my $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

return (1, "Deleted Matomo directory and tables.");
}

# script_piwik_embed_code(&domain, &opts, [&script-info])
# Returns the JavaScript tracking code that has to be added to the pages of
# a website for Matomo to record its visitors
sub script_piwik_embed_code
{
my ($d, $opts, $sinfo) = @_;
my $url = &script_path_url($d, $opts);
# Older releases only ship the piwik.js and piwik.php tracker files
my $tracker = -r "$opts->{'dir'}/matomo.js" ? "matomo" : "piwik";
# The website created during installation always has ID 1
my $siteid = 1;

# Ask Matomo for the exact code it would show, using the API token created
# at install time
my $code = &piwik_api_embed_code($d, $opts, $siteid);
return $code if ($code);

# Fall back to the standard code, as for detected installs with no token
# or when Matomo cannot be reached
return <<EOF;
<!-- Matomo -->
<script>
  var _paq = window._paq = window._paq || [];
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u="$url";
    _paq.push(['setTrackerUrl', u+'$tracker.php']);
    _paq.push(['setSiteId', '$siteid']);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
    g.async=true; g.src=u+'$tracker.js'; s.parentNode.insertBefore(g,s);
  })();
</script>
<!-- End Matomo Code -->
EOF
}

# piwik_api_embed_code(&domain, &opts, site-id)
# Fetches the tracking code from the Matomo API, or returns undef on failure
sub piwik_api_embed_code
{
my ($d, $opts, $siteid) = @_;
return undef if (!$opts->{"token"});
eval "use JSON::PP";
return undef if ($@);
my $path = $opts->{"path"};
$path .= "/" if ($path !~ /\/$/);
my $page = $path."index.php?module=API&method=SitesManager.getJavascriptTag".
	   "&idSite=".$siteid."&format=json".
	   "&piwikUrl=".&urlize(&script_path_url($d, $opts));
my $params = "token_auth=".&urlize($opts->{"token"});
my ($out, $err);
&post_http_connection($d, $page, $params, \$out, \$err);
return undef if ($err || !$out);
my $rv = eval { JSON::PP->new->decode($out) };
return undef if (ref($rv) ne "HASH" || !$rv->{"value"});
return $rv->{"value"};
}

sub script_piwik_realversion
{
my ($d, $opts, $sinfo) = @_;
my $lref = read_file_lines("$opts->{'dir'}/core/Version.php", 1);
foreach my $l (@$lref) {
	if ($l =~ /const\s+VERSION\s*=\s*'([0-9\.]+)'/) {
		return $1;
		}
	}
return undef;
}

# script_piwik_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_piwik_latest
{
my ($ver) = @_;
if ($ver >= 5) {
	return ( 'https://matomo.org/download/',
		 'Download\\s+Matomo\\s+([0-9\\.]+)' );
	}
else {
	return ( 'https://matomo.org/download/',
		 'Download\\s+Matomo\\s+(4\\.[0-9\\.]+)' );
	}
}

sub script_piwik_site
{
return 'http://matomo.org/';
}

sub script_piwik_gpl
{
return 1;
}

sub script_piwik_passmode
{
# Minimum password 6 chars length
return (1, 6, '\s*(\S\s*){6,}');
}

sub piwik_cookie_callback
{
foreach my $h (@headers, @WebminCore::headers) {
	if (lc($h->[0]) eq 'set-cookie' &&
	    $h->[1] =~ /((PHPSESSID|MATOMO_SESSID)=([^ ;]+))/) {
		$piwik_session_cookie = $1;
		}
	}
}

# script_piwik_detect_file(&domain)
# Returns the file to search for to locate a Matomo install
sub script_piwik_detect_file
{
return "config.ini.php";
}

# script_piwik_detect(&domain, &files)
# If a Matomo install was found, return the script info object
sub script_piwik_detect
{
my ($d, $files) = @_;
my @sinfos;
my $phd = &public_html_dir($d);
foreach my $mconfig (@$files) {
	# The config file must be under the config sub-directory of an
	# install that has a tracker file
	my $mdir = $mconfig;
	next if ($mdir !~ s/\/config\/config\.ini\.php$//);
	next if (!-r "$mdir/matomo.php" && !-r "$mdir/piwik.php");
	next if (!-r "$mdir/core/Version.php");

	# Parse the database section of the INI file
	my $lref = &read_file_lines($mconfig, 1);
	my ($section, %conf);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*\[(\S+)\]/) {
			$section = $1;
			}
		elsif ($section eq 'database' &&
		       $l =~ /^\s*(\w+)\s*=\s*"?([^"]*)"?\s*$/) {
			$conf{$1} = $2;
			}
		}
	next if (!$conf{'dbname'});
	my $mpath = $mdir;
	$mpath =~ s/^\Q$phd\E//;
	$mpath ||= "/";
	my $sinfo = {
		'opts' => {
			'dir' => $mdir,
			'path' => $mpath,
			'db' => 'mysql_'.$conf{'dbname'},
			},
		'user' => $conf{'username'},
		'pass' => $conf{'password'},
		};
	push(@sinfos, $sinfo);
	}
return @sinfos;
}

1;
