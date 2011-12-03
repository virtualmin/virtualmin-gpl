
$whmcs_api_key = "jCteD6q91a3";
$whmcs_api_host = "www.whmcs.com";
$whmcs_api_port = 80;
$whmcs_api_ssl = 0;
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
return "WHMCS is an all-in-one client management, billing & support solution for online businesses.";
}

# script_whmcs_versions()
sub script_whmcs_versions
{
return ( "4.5.2" );
}

sub script_whmcs_release
{
return 1;	# New patch doesn't update version
}

sub script_whmcs_category
{
return "Commerce";
}

sub script_whmcs_php_vers
{
return ( 5 );
}

sub script_whmcs_php_modules
{
return ("mysql", "curl");
}

sub script_whmcs_dbs
{
return ("mysql");
}

# script_whmcs_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing WHMCS
sub script_whmcs_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Database for WHMCS tables", $dbname);
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	$rv .= &ui_table_row("WHMCS licence key", $opts->{'licensekey'});
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Database for WHMCS tables",
		     &ui_database_select("db", undef, \@dbs, $d, "whmcs"));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", "whmcs", 30,
					     "At top level"));
	$rv .= &ui_table_row("WHMCS license key",
			     &ui_textbox("licensekey", undef, 30));
	$rv .= &ui_table_row(" ",
		"You must purchase an <a href='http://www.whmcs.com/members/aff.php?aff=4115' target=_blank/g>WHMCS license</a> before installing this script");
	}
return $rv;
}

# script_whmcs_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_whmcs_parse
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
	$in{'licensekey'} =~ /^\S+\-\S+$/ ||
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
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'licensekey'} || return "Missing licensekey option - licenses can be purchased at http://www.whmcs.com/members/aff.php?aff=4115";
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/configuration.php") {
	return "WHMCS appears to be already installed in the selected directory";
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $clash = &find_database_table($dbtype, $dbname, "tbl");
$clash && return "WHMCS appears to be already using the selected database (table $clash)";

# Check for PHP mode
&get_domain_php_mode($d) eq "mod_php" &&
	return "WHMCS cannot be installed when PHP is being run via mod_php";

# Check if ioncube loader can be found
local $io = &script_whmcs_get_ioncube_type();
$io || return "No ionCube loader for your operating system and CPU ".
	      "architecture could be found";

# Validate the licence
local $params = "key=".&urlize($whmcs_api_key).
	        "&licensekey=".&urlize($opts->{'licensekey'}).
	        "&domain=".&urlize($d->{'dom'}).
	        "&ipaddress=".&urlize($d->{'ip'}).
	        "&directory=".&urlize($opts->{'dir'});
local ($out, $err);
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
local ($d, $ver, $opts, $upgrade) = @_;
local $shortver = $ver;
$shortver =~ s/\.//g;
local @files = ( { 'name' => "source",
	   'file' => "whmcs_v$shortver.zip",
	   'url' => "http://software.virtualmin.com/download/whmcs_v$shortver.zip" } );
local $io = &script_whmcs_get_ioncube_type();
push(@files, { 'name' => "ioncube",
	       'file' => "ioncube_loaders.zip",
	       'url' => "http://downloads2.ioncube.com/".
			"loader_downloads/ioncube_loaders_$io.zip" });
if (&compare_versions($ver, "4.5.2") <= 0) {
	# Also need security path
	push(@files, { 'name' => 'patch',
		       'file' => 'patch.zip',
		       'url' => 'http://www.whmcs.com/go/21/download' });
	}
if (&compare_versions($ver, "4.5.2") <= 0) {
	# New security path
	push(@files, { 'name' => 'patch2',
		       'file' => 'patch2.zip',
		       'url' => 'http://www.whmcs.com/members/dl.php?type=d&id=112' });
	}
return @files;
}

sub script_whmcs_get_ioncube_type
{
local $io;
local $arch = &backquote_command("uname -m");
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
local ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;

# Get DB details
local ($out, $ex);
if ($opts->{'newdb'} && !$upgrade) {
	local $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
local $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
local $dbhost = &get_database_host($dbtype);
local $dberr = &check_script_db_connection($dbtype, $dbname, $dbuser, $dbpass);
return (0, "Database connection failed : $dberr") if ($dberr);

# Extract ioncube loader
local $iotemp = &transname();
local $err = &extract_script_archive($files->{'ioncube'}, $iotemp, $d);
$err && return (0, "Failed to extract ionCube files : $err");
local $io = &script_whmcs_get_ioncube_type();
local $phpver = &get_php_version(5);
$phpver =~ s/^(\d+\.\d+)\..*$/$1/;
local ($sofile) = glob("$iotemp/ioncube/ioncube_loader_*_$phpver.so");
$sofile ||
	return (0, "No ionCube loader for PHP version $phpver found in file");

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $cfile = "$opts->{'dir'}/configuration.php";
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
				     $opts->{'dir'}, "whmcs");
$err && return (0, "Failed to extract source : $err");

# Apply security patches, if needed
foreach my $k (keys %$files) {
	if ($k =~ /^patch/) {
		local $ptemp = &transname();
		local $err = &extract_script_archive($files->{$k}, $ptemp, $d,
						     $opts->{'dir'});
		$err && return (0, "Failed to extract patch source : $err");
		}
	}

# Copy loader to ~/etc , adjust php.ini
local $inifile = &get_domain_php_ini($d, 5);
$inifile && -r $inifile || return (0, "PHP configuration file was not found!");
$sofile =~ /\/([^\/]+)$/;
local $sodest = "$d->{'home'}/etc/$1";
&copy_source_dest_as_domain_user($d, $sofile, $sodest);
&foreign_require("phpini", "phpini-lib.pl");
local $conf = &phpini::get_config($inifile);
local @allzends = grep { $_->{'name'} eq 'zend_extension' } @$conf;
local @zends = grep { $_->{'enabled'} } @allzends;
local ($got) = grep { $_->{'value'} eq $sodest } @zends;
if (!$got) {
	# Needs to be enabled
	local $lref = &read_file_lines($inifile);
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
&restart_apache();
&pop_all_print();

# Create empty config file
if (!-r $cfile) {
	&open_tempfile_as_domain_user($d, CFILE, ">$cfile");
	&close_tempfile_as_domain_user($d, CFILE);
	&make_file_php_writable($d, $cfile);
	}

# Run install script
local $ipath = $opts->{'path'}."/install/install.php";
if (!$upgrade) {
	# Fetch config check page
	local ($out, $err);
	&get_http_connection($d, $ipath."?step=2", \$out, \$err);
	if ($err) {
		return (-1, "Failed to fetch system check page : $err");
		}
	elsif ($out !~ /Continue/) {
		return (-1, "System check failed");
		}

	# Post to DB setup page
	local @params = (
		[ "licensekey", $opts->{'licensekey'} ],
		[ "dbhost", $dbhost ],
		[ "dbname", $dbname ],
		[ "dbusername", $dbuser ],
		[ "dbpassword", $dbpass ],
		);
	local $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	local ($out, $err);
	&post_http_connection($d, $ipath."?step=4", $params, \$out, \$err);
	if ($err) {
		return (-1, "Database setup page failed : $err");
		}
	elsif ($out !~ /Setup\s+Administrator\s+Account/i) {
		return (-1, "Database setup did not succeed");
		}

	# Post to user creation page
	local $firstname = $d->{'owner'};
	$firstname =~ s/\s.*$//;
	$firstname =~ s/['"]//g;
	local @params = (
		[ "firstname", $firstname ],
		[ "lastname", "" ],
		[ "email", $d->{'emailto'} ],
		[ "username", $domuser ],
		[ "password", $dompass ],
		);
	local $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	local ($out, $err);
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
	local ($out, $err);
	&get_http_connection($d, $ipath."?step=2", \$out, \$err);
	if ($err) {
		return (-1, "Failed to fetch upgrade check page : $err");
		}
	elsif ($out !~ /Perform\s+Upgrade/) {
		return (-1, "Upgrade check failed");
		}

	# Post to DB upgrade page
	local $oldver = $upgrade->{'version'};
	$oldver =~ s/\.//g;
	local @params = (
		[ "step", "upgrade" ],
		[ "version", $oldver ],
		[ "confirmbackup", 1 ],
		);
	local $params = join("&", map { $_->[0]."=".&urlize($_->[1]) } @params);
	local ($out, $err);
	&post_http_connection($d, $ipath, $params, \$out, \$err);
	if ($err) {
		return (-1, "Database upgrade page failed : $err");
		}
	elsif ($out !~ /Upgrade\s+Complete/i) {
		return (-1, "Database upgrade did not succeed");
		}
	}

# Setup cron job
local $url = &script_path_url($d, $opts);
if (!$upgrade) {
	&create_script_wget_job($d, $url."admin/cron.php",
			        '0', int(rand()*24), 1);
	}

# Delete install folder
&unlink_file_as_domain_user($d, "$opts->{'dir'}/install");

# Return a URL for the user
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
local $adminurl = $url."admin/";
return (1, "WHMCS installation complete. It can be accessed at <a href=$url target=_blank/g>$url</a> and managed at <a href=$adminurl target=_blank/g>$adminurl</a>. For more information, see <a href=http://wiki.whmcs.com/Installing_WHMCS target=_blank/g>http://wiki.whmcs.com/Installing_WHMCS</a> and <a href=http://wiki.whmcs.com/Virtualmin_Pro target=_blank/g>http://wiki.whmcs.com/Virtualmin_Pro</a>.",
	"Under $rp using $dbphptype database $dbname", $url,
	$domuser, $dompass);
}

# script_whmcs_uninstall(&domain, version, &opts)
# Un-installs a WHMCS installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_whmcs_uninstall
{
local ($d, $version, $opts) = @_;

# Remove tbl* tables from the database
&cleanup_script_database($d, $opts->{'db'}, "tbl");

# Delete the cron job
&delete_script_wget_job($d, $sinfo->{'url'}."admin/cron.php");

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

return (1, "WHMCS directory and tables deleted.");
}

# script_whmcs_latest(version)
# Returns a URL and regular expression or callback func to get the version
#sub script_whmcs_latest
#{
#local ($ver) = @_;
#return ( "http://forum.whmcs.com/forumdisplay.php?s=f0986c5381d494b7b6b6a0923fef97e0&f=9",
#	 "WHMCS\\s+V([0-9\\.]+)\\s[^>]*Release" );
#}

sub script_whmcs_site
{
return 'http://www.whmcs.com/members/aff.php?aff=4115';
}

sub script_whmcs_passmode
{
return 1;
}

1;

