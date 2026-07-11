
$whmcs_api_key = "jCteD6q91a3";
$whmcs_api_host = "www.whmcs.com";
$whmcs_api_port = 443;
$whmcs_api_ssl = 1;
$whmcs_api_prefix = "/licenseapi/validate.php";

# script_whmcs_desc()
sub script_whmcs_desc
{
return "WHMCS";
}

sub script_whmcs_uses
{
return ( "php" );
}

sub script_whmcs_longdesc
{
return "WHMCS is an all-in-one client management, billing & support solution for online businesses";
}

# script_whmcs_versions()
sub script_whmcs_versions
{
return ( "9.0.6", "8.13.5" );
}

sub script_whmcs_version_desc
{
my ($ver) = @_;
return $ver =~ /^(\d+)\.(5|6|7|11|12)/ ? "$ver (LTS)" : $ver;
}

sub script_whmcs_gpl
{
return 1;
}

sub script_whmcs_release
{
return 7;	# To fix download URL
}

sub script_whmcs_category
{
return "Commerce";
}

sub script_whmcs_php_vers
{
return ( 5 );
}

sub script_whmcs_php_fullver
{
my ($d, $ver, $sinfo) = @_;
return &compare_versions($ver, 8) >= 0 ? 7.2 : 5.6;
}

sub script_whmcs_php_modules
{
return ("mysql", "curl", "gd", "pdo_mysql", "intl", "json",
	    "mbstring", "gmp", "openssl", "bcmath", "iconv", "xml");
}

sub script_whmcs_php_vars
{
return ( [ 'memory_limit', '128M', '+' ] );
}

sub script_whmcs_dbs
{
return ("mysql");
}

# script_whmcs_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing WHMCS
sub script_whmcs_params
{
my ($d, $ver, $upgrade) = @_;
my $rv;
my $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	my ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for WHMCS tables", $dbname);
	my $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	$rv .= &ui_table_row("WHMCS licence key",
			     $upgrade->{'opts'}->{'licensekey'});
	}
else {
	# Show editable install options
	my @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Database for WHMCS tables",
		     &ui_database_select("db", undef, \@dbs, $d, "whmcs"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("whmcs", $d), 30, "At top level"));
	$rv .= &ui_table_row("WHMCS license key",
			     &ui_textbox("licensekey", undef, 30));
	$rv .= &ui_table_row(" ",
		"You must purchase an <a href='https://www.whmcs.com/members/aff.php?aff=4115' target=_blank>WHMCS license</a> before installing this script");
	}
return $rv;
}

# script_whmcs_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_whmcs_parse
{
my ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	my $hdir = &public_html_dir($d, 0);
	$in{'dir_def'} || $in{'dir'} =~ /\S/ && $in{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	my $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
	my ($newdb) = ($in->{'db'} =~ s/^\*//);
	$in{'licensekey'} =~ s/^\s*//;
	$in{'licensekey'} =~ s/\s*$//;
	$in{'licensekey'} =~ /^\S+$/ ||
		return "Missing or invalid-looking licence key - should be ".
		       "like Owned-a8f06f0510547d80704b";
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}",
		 'licensekey' => $in{'licensekey'}, };
	}
}

# script_whmcs_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_whmcs_check
{
my ($d, $ver, $opts, $upgrade) = @_;
$opts->{'licensekey'} || return "Missing licensekey option - licenses can be purchased at http://www.whmcs.com/members/aff.php?aff=4115";
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/configuration.php") {
	return "WHMCS appears to be already installed in the selected directory";
	}
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $clash = &find_database_table($dbtype, $dbname, "tbl");
$clash && return "WHMCS appears to be already using the selected database (table $clash)";

# Check for PHP mode
&get_domain_php_mode($d) eq "mod_php" &&
	return "WHMCS cannot be installed when PHP is being run via mod_php";

# Check if ioncube loader can be found
my $io = &script_whmcs_get_ioncube_type();
$io || return "No ionCube loader for your operating system and CPU ".
	      "architecture could be found";

# Validate the licence
my $params = "key=".&urlize($whmcs_api_key).
	        "&licensekey=".&urlize($opts->{'licensekey'});

my ($out, $err);
&http_download($whmcs_api_host, $whmcs_api_port, $whmcs_api_prefix."?".$params,
	       \$out, \$err, undef, $whmcs_api_ssl, undef, undef, undef, 0, 1);
if ($err) {
	return "WHMCS licence check failed : $err";
	}
elsif ($out =~ /invalidkey/) {
	return "WHMCS API is invalid";
	}
elsif ($out =~ /licensekeynotfound/) {
	return "WHMCS licence key was not found";
	}
elsif ($out =~ /expired/) {
	return "WHMCS licence key has expired";
	}
elsif ($out =~ /suspended/) {
	return "WHMCS licence key has been suspended";
	}
elsif ($out =~ /invalid/) {
	return "WHMCS license key is registered to another IP address or directory. For more information, or to reissue your WHMCS  license, please see 'My Licenses and Services' in the Client Area at whmcs.com.";
	}
elsif ($out !~ /valid/) {
	return "Unknown WHMCS licence check code : $out";
	}

return undef;
}

# script_whmcs_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by WHMCS, each of which is a hash ref
# containing a name, filename and URL
sub script_whmcs_files
{
my ($d, $ver, $opts, $upgrade) = @_;
my $shortver = $ver;
$shortver =~ s/\.//g;
my @files = ( {
    'name' => "source",
    'file' => "whmcs_v${shortver}.zip",
    'url' => "https://scripts.virtualmin.com/whmcs_v${shortver}.zip" } );
my $io = &script_whmcs_get_ioncube_type();
push(@files, {
    'name' => "ioncube",
    'file' => "ioncube_loaders.zip",
    'url' => "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_$io.zip" });
return @files;
}

sub script_whmcs_get_ioncube_type
{
my $io;
my $arch = &backquote_command("uname -m");
if ($gconfig{'os_type'} eq 'solaris' && $arch =~ /sparc/) {
	$io = "sun_sparc";
	}
elsif ($gconfig{'os_type'} eq 'solaris' && $arch =~ /86/) {
	$io = "sun_x86";
	}
elsif ($gconfig{'os_type'} eq 'freebsd' && $arch =~ /64/) {
	$io = "fre_".int($gconfig{'os_version'})."_x86-64";
	}
elsif ($gconfig{'os_type'} eq 'freebsd' && $arch !~ /64/) {
	$io = "fre_".int($gconfig{'os_version'})."_x86";
	}
elsif ($gconfig{'os_type'} eq 'macos' && $arch =~ /64/) {
	$io = "dar_x86-64";
	}
elsif ($gconfig{'os_type'} eq 'macos' && $arch !~ /64/) {
	$io = "dar_x86";
	}
elsif ($gconfig{'os_type'} =~ /-linux/ && $arch =~ /aarch64/) {
	$io = "lin_aarch64";
	}
elsif ($gconfig{'os_type'} =~ /-linux/ && $arch =~ /x86_64/) {
	$io = "lin_x86-64";
	}
elsif ($gconfig{'os_type'} =~ /-linux/ && $arch =~ /i[0-9]86/) {
	$io = "lin_x86";
	}
elsif ($gconfig{'os_type'} =~ /-linux/ && $arch =~ /ppc/) {
	$io = "lin_ppc";
	}
return $io;
}

sub script_whmcs_commands
{
return ("unzip");
}

# script_whmcs_install(&domain, version, &opts, &files, &upgrade-info,
#			username, password)
# Actually installs WHMCS, and returns either 1 and an informational
# message, or 0 and an error
sub script_whmcs_install
{
my ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;

# Get DB details
my ($out, $ex);
if ($opts->{'newdb'} && !$upgrade) {
	my $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
my ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
my $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
my $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
my $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
my $dbhost = &get_database_host($dbtype, $d);
my $dberr = &check_script_db_connection(
	$d, $dbtype, $dbname, $dbuser, $dbpass);
return (0, "Database connection failed : $dberr") if ($dberr);

# Extract ioncube loader
my $iotemp = &transname();
my $err = &extract_script_archive($files->{'ioncube'}, $iotemp, $d);
$err && return (0, "Failed to extract ionCube files : $err");
my $io = &script_whmcs_get_ioncube_type();
my $phpver = &get_php_version($opts->{'phpver'});
$phpver =~ s/^(\d+\.\d+)\..*$/$1/;
my ($sofile) = glob("$iotemp/ioncube/ioncube_loader_*_$phpver.so");
$sofile ||
	return (0, "No ionCube loader for PHP version $phpver found in file");

# Extract tar file to temp dir and copy to target
my $temp = &transname();
my $cfile = "$opts->{'dir'}/configuration.php";
my $cfilesrc = "$opts->{'dir'}/configuration.php.new";
my $err = &extract_script_archive($files->{'source'}, $temp, $d,
				     $opts->{'dir'}, "whmcs");
$err && return (0, "Failed to extract source : $err");

# Apply security patches, if needed
foreach my $k (keys %$files) {
	if ($k =~ /^patch/) {
		my $ptemp = &transname();
		my $err = &extract_script_archive($files->{$k}, $ptemp, $d,
						     $opts->{'dir'});
		$err && return (0, "Failed to extract patch source : $err");
		}
	}

# Copy loader to ~/etc , adjust php.ini
my $inifile = &get_domain_php_ini($d, $opts->{'phpver'});
$inifile && -r $inifile || return (0, "PHP configuration file was not found!");
$sofile =~ /\/([^\/]+)$/;
my $sodest = "$d->{'home'}/etc/$1";
&copy_source_dest_as_domain_user($d, $sofile, $sodest);
&foreign_require("phpini", "phpini-lib.pl");
my $conf = &phpini::get_config($inifile);
my @allzends = grep { $_->{'name'} eq 'zend_extension' } @$conf;
my @zends = grep { $_->{'enabled'} } @allzends;
my ($got) = grep { $_->{'value'} eq $sodest } @zends;
if (!$got) {
	# Needs to be enabled
	my $lref = &read_file_lines($inifile);
	if (@zends) {
		# After current extensions
		splice(@$lref, $zends[$#zends]->{'line'}+1, 0,
		       "zend_extension=$sodest");
		}
	elsif (@allexts) {
		# After commented out extensions
		splice(@$lref, $allzends[$#allzends]->{'line'}+1, 0,
		       "zend_extension=$sodest");
		}
	else {
		# At end of file (should never happen, but..)
		push(@$lref, "zend_extension=$sodest");
		}
	&write_as_domain_user($d,
		sub { &flush_file_lines($inifile) });
	undef($phpini::get_config_cache{$inifile});
	}

# Apply apache config now, for later wgets
&push_all_print();
&restart_website_server();
my $p = &domain_has_website($d);
if ($p ne "web") {
	&plugin_call($p, "feature_restart_web_php", $d);
	}
sleep 5;
&pop_all_print();

if (!-r $cfile) {
	if (-r $cfilesrc) {
		# Use template config file
		&copy_source_dest_as_domain_user($d, $cfilesrc, $cfile);
		}
	else {
		# Create empty config file
		&open_tempfile_as_domain_user($d, CFILE, ">$cfile");
		&close_tempfile_as_domain_user($d, CFILE);
		}
	&make_file_php_writable($d, $cfile);
	}

# Run install script
my $ipath = $opts->{'path'}."/install/install.php";
if (!$upgrade) {
	# Fetch config check page
	my ($out, $err);
	&get_http_connection($d, $ipath."?step=2", \$out, \$err);
	if ($err) {
		return (-1, "Failed to fetch system check page : $err");
		}
	elsif ($out !~ /Continue|Begin\s+Installation/i) {
		return (-1, "System check failed");
		}

	# Post to DB setup page
	my @params = (
		[ "licenseKey", $opts->{'licensekey'} ],
		[ "databaseHost", $dbhost ],
		[ "databasePort", 3306 ],
		[ "databaseUsername", $dbuser ],
		[ "databasePassword", $dbpass ],
		[ "databaseName", $dbname ],
		);
	my $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	my ($out, $err);
	&post_http_connection($d, $ipath."?step=4", $params, \$out, \$err);
	if ($err) {
		return (-1, "Database setup page failed : $err");
		}
	elsif ($out !~ /Set\s*up\s+Administrator\s+Account/i) {
		return (-1, "Database setup did not succeed");
		}

	# Post to user creation page
	my $firstname = $d->{'owner'};
	$firstname =~ s/\s.*$//;
	$firstname =~ s/['"]//g;
	$firstname ||= $d->{'dom'};
	if (length($dompass) <= 5) {
		$dompass .= "1!aA45";
		}
	my @params = (
		[ "firstName", $firstname ],
		[ "lastName", "Virtualmin" ],
		[ "email", $d->{'emailto_addr'} ],
		[ "username", $domuser ],
		[ "password", $dompass ],
		[ "confirmPassword", $dompass ],
		);
	my $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	my ($out, $err);
	&post_http_connection($d, $ipath."?step=5", $params, \$out, \$err);
	if ($err) {
		return (-1, "Account creation page failed : $err");
		}
	elsif ($out !~ /Installation\s+Complete/i) {
		return (-1, "Account creation did not succeed");
		}
	}
else {
	# Fetch config check page
	my ($out, $err);
	&get_http_connection($d, $ipath."?step=2", \$out, \$err);
	if ($err) {
		return (-1, "Failed to fetch upgrade check page : $err");
		}
	elsif ($out !~ /Perform\s+Upgrade|already\s+running|currently\s+running/) {
		return (-1, "Upgrade check failed");
		}

	# Post to DB upgrade page
	my @params = (
		[ "confirmBackup", 1 ],
		);
	my $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	my ($out, $err);
	&post_http_connection($d, $ipath."?step=upgrade", $params, \$out, \$err);
	if ($err) {
		return (-1, "Database upgrade page failed : $err");
		}
	elsif ($out !~ /Upgrade\s+Complete|perform\s+a\s+backup/i) {
		return (-1, "Database upgrade did not succeed");
		}
	}

# Setup cron job
my $url = &script_path_url($d, $opts);
if (!$upgrade) {
	&create_script_wget_job($d, $url."admin/cron.php",
			        '0', int(rand()*24), 1);
	}

# Delete install folder
&unlink_file_as_domain_user($d, "$opts->{'dir'}/install");

# Return a URL for the user
my $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
my $adminurl = $url."admin/";
my $installtype = $upgrade ? 'upgrade' : 'installation';
return (1, "WHMCS $installtype complete. It can be accessed at <a href=$url target=_blank>$url</a> and managed at <a href=$adminurl target=_blank>$adminurl</a>. For more information, see <a href=http://docs.whmcs.com/Installing_WHMCS target=_blank>http://docs.whmcs.com/Installing_WHMCS</a> and <a href=http://docs.whmcs.com/Virtualmin_Pro target=_blank>http://docs.whmcs.com/Virtualmin_Pro</a>.",
	"Under $rp using $dbphptype database $dbname", $url,
	$domuser, $dompass);
}

# script_whmcs_uninstall(&domain, version, &opts)
# Un-installs a WHMCS installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_whmcs_uninstall
{
my ($d, $version, $opts) = @_;

# Remove tbl* tables from the database
&cleanup_script_database($d, $opts->{'db'}, "(tbl|mod_)");

# Delete the cron job
&delete_script_wget_job($d, $sinfo->{'url'}."admin/cron.php");

# Remove the contents of the target directory
my $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

return (1, "WHMCS directory and tables deleted.");
}

sub script_whmcs_db_conn_desc
{
my $db_conn_desc = 
    { 'configuration.php' =>
        {
           'dbpass' =>
           {
               'func'        => 'php_quotemeta',
               'func_params' => 1,
               'replace'     => [ '\$db_password\s*=' =>
                                  '$db_password = \'$$sdbpass\';' ],
           },
           'dbuser' =>
           {
               'replace'     => [ '\$db_username\s*=' =>
                                  '$db_username = \'$$sdbuser\';' ],
           },
        }
    };
return $db_conn_desc;
}

sub script_whmcs_latest
{
my ($ver) = @_;
my $vwant = &compare_versions($ver, "9") >= 0 ? "9" :
	       &compare_versions($ver, "8.13") >= 0 ? "8\\.13" : undef;
if ($vwant) {
	return ( "https://download.whmcs.com/assets/scripts/get-downloads.php",
		 "\"version\":\"($vwant\\.[0-9\\.]+)\",(\"type\":\"(MAINTENANCE|SECURITY)\"|\"compatibleWith\")" );
	}
return ( );
}

sub script_whmcs_site
{
my $minver = sprintf('%.2f', $module_info{'version'});
if ($minver >= "7.2") {
	return ['http://www.whmcs.com/members/aff.php?aff=4115', 'http://www.whmcs.com/'];
	}
else {
	return 'http://www.whmcs.com/members/aff.php?aff=4115';
	}
}

sub script_whmcs_passmode
{
return (1, 8, '^(?=.*[a-zA-Z])(?=.*\d)[\w\d]{8,}$');
}

1;

