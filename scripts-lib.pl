# Functions for scripts

# list_scripts()
# Returns a list of installable script names
sub list_scripts
{
local (@rv, $s);
foreach $s (@scripts_directories) {
	opendir(DIR, $s);
	foreach $f (readdir(DIR)) {
		push(@rv, $1) if ($f =~ /^(.*)\.pl$/);
		}
	closedir(DIR);
	}
return &unique(@rv);
}

# list_available_scripts()
# Returns a list of installable script names, excluding those that are
# not available
sub list_available_scripts
{
local %unavail;
&read_file_cached($scripts_unavail_file, \%unavail);
local @rv = &list_scripts();
return grep { !$unavail{$_} } @rv;
}

# get_script(name)
# Returns the structure for some script
sub get_script
{
local ($name) = @_;
local ($s, $sdir);
foreach $s (@scripts_directories) {
	if (-r "$s/$name.pl") {
		$sdir = $s;
		last;
		}
	}
$sdir || return undef;
(do "$sdir/$name.pl") || return undef;
local $dfunc = "script_${name}_desc";
local $lfunc = "script_${name}_longdesc";
local $vfunc = "script_${name}_versions";
local $ufunc = "script_${name}_uses";
local $vdfunc = "script_${name}_version_desc";
local $catfunc = "script_${name}_category";
local %unavail;
&read_file_cached($scripts_unavail_file, \%unavail);
local $rv = { 'name' => $name,
	      'desc' => &$dfunc(),
	      'longdesc' => defined(&$lfunc) ? &$lfunc() : undef,
	      'versions' => [ &$vfunc() ],
	      'uses' => defined(&$ufunc) ? [ &$ufunc() ] : [ ],
	      'category' => defined(&$catfunc) ? &$catfunc() : undef,
	      'dir' => $sdir,
	      'depends_func' => "script_${name}_depends",
	      'params_func' => "script_${name}_params",
	      'parse_func' => "script_${name}_parse",
	      'check_func' => "script_${name}_check",
	      'install_func' => "script_${name}_install",
	      'uninstall_func' => "script_${name}_uninstall",
	      'files_func' => "script_${name}_files",
	      'php_vars_func' => "script_${name}_php_vars",
	      'php_vers_func' => "script_${name}_php_vers",
	      'php_mods_func' => "script_${name}_php_modules",
	      'pear_mods_func' => "script_${name}_pear_modules",
	      'latest_func' => "script_${name}_latest",
	      'check_latest_func' => "script_${name}_check_latest",
	      'avail' => !$unavail{$name},
	      'minversion' => $unavail{$name."_minversion"},
	    };
if (defined(&$vdfunc)) {
	foreach my $ver (@{$rv->{'versions'}}) {
		$rv->{'vdesc'}->{$ver} = &$vdfunc($ver);
		}
	}
return $rv;
}

# list_domain_scripts(&domain)
# Returns a list of scripts and versions already installed for a domain. Each
# entry in the list is a hash ref containing the id, name, version and opts
sub list_domain_scripts
{
local ($f, @rv, $i);
local $ddir = "$script_log_directory/$_[0]->{'id'}";
opendir(DIR, $ddir);
while($f = readdir(DIR)) {
	if ($f =~ /^(\S+)\.script$/) {
		local %info;
		&read_file("$ddir/$f", \%info);
		local @st = stat("$ddir/$f");
		$info{'id'} = $1;
		$info{'file'} = "$ddir/$f";
		foreach $i (keys %info) {
			if ($i =~ /^opts_(.*)$/) {
				$info{'opts'}->{$1} = $info{$i};
				delete($info{$i});
				}
			}
		$info{'time'} = $st[9];
		push(@rv, \%info);
		}
	}
closedir(DIR);
return @rv;
}

# add_domain_script(&domain, name, version, &opts, desc, url)
# Records the installation of a script for a domains
sub add_domain_script
{
local ($d, $name, $version, $opts, $desc) = @_;
local %info = ( 'id' => time().$$,
		'name' => $name,
		'version' => $version,
		'desc' => $desc,
		'url' => $url );
local $o;
foreach $o (keys %$opts) {
	$info{'opts_'.$o} = $opts->{$o};
	}
&make_dir($script_log_directory, 0700);
&make_dir("$script_log_directory/$d->{'id'}", 0700);
&write_file("$script_log_directory/$d->{'id'}/$info{'id'}.script", \%info);
}

# remove_domain_script(&domain, &script-info)
# Records the un-install of a script for a domain
sub remove_domain_script
{
local ($d, $info) = @_;
&unlink_file($info->{'file'});
}

# find_database_table(dbtype, dbname, table|regexp)
# Returns 1 if some table exists in the specified database (if the db exists)
sub find_database_table
{
local ($dbtype, $dbname, $table) = @_;
local $cfunc = "check_".$dbtype."_database_clash";
if (&$cfunc($dbname)) {
	local $lfunc = "list_".$dbtype."_tables";
	local @tables = &$lfunc($dbname);
	foreach my $t (@tables) {
		if ($t =~ /^$table$/i) {
			return $t;
			}
		}
	}
return undef;
}

# save_scripts_available(&scripts)
# Given a list of scripts with avail and minversion flags, update the 
# available file.
sub save_scripts_available
{
local ($scripts) = @_;
&lock_file($scripts_unavail_file);
&read_file_cached($scripts_unavail_file, \%unavail);
foreach my $script (@$scripts) {
	local $n = $script->{'name'};
	delete($unavail{$n});
	delete($unavail{$n."_minversion"});
	if (!$script->{'avail'}) {
		$unavail{$n} = 1;
		}
	if ($script->{'minversion'}) {
		$unavail{$n."_minversion"} = $script->{'minversion'};
		}
	}
&write_file($scripts_unavail_file, \%unavail);
&unlock_file($scripts_unavail_file);
}

# fetch_script_files(&domain, version, opts, &old-info, &gotfiles, [nocallback])
# Downloads or otherwise fetches all files needed by some script. Returns undef
# on success, or an error message on failure. Also prints out download progress.
sub fetch_script_files
{
local ($d, $ver, $opts, $sinfo, $gotfiles, $nocallback) = @_;

local $cb = $nocallback ? undef : \&progress_callback;
local @files = &{$script->{'files_func'}}($d, $ver, $opts, $sinfo);
foreach my $f (@files) {
	if (-r "$script->{'dir'}/$f->{'file'}") {
		# Included in script's directory
		$gotfiles->{$f->{'name'}} = "$script->{'dir'}/$f->{'file'}";
		}
	elsif (-r "$d->{'home'}/$f->{'file'}") {
		# User already has it
		$gotfiles->{$f->{'name'}} = "$d->{'home'}/$f->{'file'}";
		}
	else {
		# Need to fetch it
		my $temp = &transname($f->{'file'});
		if (defined(&convert_osdn_url)) {
			$f->{'url'} = &convert_osdn_url($f->{'url'});
			}
		$progress_callback_url = $f->{'url'};
		if ($f->{'url'} =~ /^http/) {
			# Via HTTP
			my ($host, $port, $page, $ssl) =
				&parse_http_url($f->{'url'});
			&http_download($host, $port, $page, $temp, \$error,
				       $cb, $ssl, undef, undef, undef, 0,
				       $f->{'nocache'});
			}
		elsif ($f->{'url'} =~ /^ftp:\/\/([^\/]+)(\/.*)/) {
			# Via FTP
			my ($host, $page) = ($1, $2);
			&ftp_download($host, $page, $temp, \$error, $cb);
			}
		else {
			return &text('scripts_eurl', $f->{'url'});
			}
		if ($error) {
			return &text('scripts_edownload', $error, $f->{'url'});
			}
		&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, undef,
					   $temp);

		# Make sure the downloaded file is in some archive format,
		# or is Perl or PHP.
		local $fmt = &compression_format($temp);
		if (!$fmt && $temp =~ /\.(pl|php)$/i) {
			local $cont = &read_file_contents($temp);
			}
		if (!$fmt &&
		    $cont !~ /^\#\!\s*\S+(perl|php)/i &&
		    $cont !~ /^\s*<\?php/i) {
			return &text('scripts_edownload2', $f->{'url'});
			}

		$gotfiles->{$f->{'name'}} = $temp;
		}
	}
return undef;
}

# compare_versions(ver1, ver2)
# Returns -1 if ver1 is older than ver2, 1 if newer, 0 if same
sub compare_versions
{
local @sp1 = split(/[\.\-]/, $_[0]);
local @sp2 = split(/[\.\-]/, $_[1]);
for(my $i=0; $i<@sp1 || $i<@sp2; $i++) {
	local $v1 = $sp1[$i];
	local $v2 = $sp2[$i];
	local $comp;
	if ($v1 =~ /^\d+$/ && $v2 =~ /^\d+$/) {
		$comp = $v1 <=> $v2;
		}
	else {
		$comp = $v1 cmp $v2;
		}
	return $comp if ($comp);
	}
return 0;
}

# ui_database_select(name, value, &dbs, [&domain, new-db-suffix])
# Returns a field for selecting a database, from those available for the
# domain. Can also include an option for a new database
sub ui_database_select
{
local ($name, $value, $dbs, $d, $newsuffix) = @_;
local ($newdbname, $newdbtype);
if ($newsuffix) {
	# Work out a name for the new DB (if one is allowed)
	local $tmpl = &get_template($d->{'template'});
	local ($dleft, $dreason, $dmax) = &count_feature("dbs");
	if ($dleft != 0 && &can_edit_databases()) {
		# Choose a name ether based on the allowed prefix, or the
		# default DB name
		if ($tmpl->{'mysql_suffix'} ne "none") {
			local $prefix = &substitute_domain_template(
						$tmpl->{'mysql_suffix'}, $d);
			$prefix =~ s/-/_/g;
			$prefix =~ s/\./_/g;
			$newdbname = $prefix.$newsuffix;
			}
		else {
			$newdbname = $d->{'db'}."_".$newsuffix;
			}
		$newdbtype = $d->{'mysql'} ? "mysql" : "postgres";
		$newdbdesc = $text{'databases_'.$newdbtype};
		local ($already) = grep { $_->{'type'} eq $newdbtype &&
					  $_->{'name'} eq $newdbname } @$dbs;
		if ($already) {
			# Don't offer to create if already exists
			$newdbname = $newdbtype = $newdbdesc = undef;
			}
		}
	}
return &ui_select($name, $value,
	[ (map { [ $_->{'type'}."_".$_->{'name'},
		   $_->{'name'}." (".$_->{'desc'}.")" ] } @$dbs),
	  $newdbname ? ( [ "*".$newdbtype."_".$newdbname,
			   &text('scripts_newdb', $newdbname, $newdbdesc) ] )
		     : ( ) ] );
}

# create_script_database(&domain, db-spec)
# Create a new database for a script. Returns undef on success, or an error
# message on failure.
sub create_script_database
{
local ($d, $dbspec) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);

# Check limits (again)
local ($dleft, $dreason, $dmax) = &count_feature("dbs");
if ($dleft == 1) {
	return "You are not allowed to create any more databases";
	}
if (!&can_edit_databases()) {
	return "You are not allowed to create databases";
	}

$cfunc = "check_".$dbtype."_database_clash";
&$cfunc($d, $dbname) && return "The database $dbname already exists";

# Do the creation
&push_all_print();
if (&indexof($dbtype, @database_plugins) >= 0) {
	&plugin_call($dbtype, "database_create", $d, $dbname);
	}
else {
	$crfunc = "create_".$dbtype."_database";
	&$crfunc($d, $dbname);
	}
&save_domain($d);
&refresh_webmin_user($d);
&pop_all_print();

return undef;
}

# delete_script_database(&domain, dbspec)
# Deletes the database that was created for some script, if it is empty
sub delete_script_database
{
local ($d, $dbspec) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);

local $cfunc = "check_".$dbtype."_database_clash";
if (!&$cfunc($d, $dbname)) {
	return "Database $dbname does not exist";
	}

local $lfunc = "list_".$dbtype."_tables";
local @tables = &$lfunc($dbname);
if (!@tables) {
	&push_all_print();
	local $dfunc = "delete_".$dbtype."_database";
	&$dfunc($d, $dbname);
	&save_domain($d);
	&refresh_webmin_user($d);
	&pop_all_print();
	}
else {
	return "Database $dbname still contains ".scalar(@tables)." tables";
	}
}

# setup_web_for_php(&domain, &script)
# Update a virtual server's web config to add any PHP settings from the template
sub setup_web_for_php
{
local ($d, $script) = @_;
local $tmpl = &get_template($d->{'template'});
local $any = 0;
local @tmplphpvars = $tmpl->{'php_vars'} eq 'none' ? ( ) :
			split(/\t+/, $tmpl->{'php_vars'});

if ($apache::httpd_modules{'mod_php4'} ||
    $apache::httpd_modules{'mod_php5'}) {
	# Add the PHP variables to the domain's <Virtualhost> in Apache config
	&require_apache();
	local $conf = &apache::get_config();
	local @ports;
	push(@ports, $d->{'web_port'}) if ($d->{'web'});
	push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
	foreach my $port (@ports) {
		local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		next if (!$virt);

		# Find currently set PHP variables
		local @phpv = &apache::find_directive("php_value", $vconf);
		local %got;
		foreach my $p (@phpv) {
			if ($p =~ /^(\S+)/) {
				$got{$1}++;
				}
			}

		# Get PHP variables from template
		local @oldphpv = @phpv;
		foreach my $pv (@tmplphpvars) {
			local ($n, $v) = split(/=/, $pv, 2);
			if (!$got{$n}) {
				push(@phpv, "$n $v");
				}
			}
		if ($script && defined(&{$script->{'php_vars_func'}})) {
			# Get from script too
			foreach my $v (&{$script->{'php_vars_func'}}($d)) {
				if (!$got{$v->[0]}) {
					push(@phpv, "$v->[0] $v->[1]");
					}
				}
			}

		# Update if needed
		if (scalar(@oldphpv) != scalar(@phpv)) {
			&apache::save_directive("php_value",
						\@phpv, $vconf, $conf);
			$any++;
			}
		&flush_file_lines();
		}
	}

local $phpini = "$d->{'home'}/etc/php.ini";
if (-r $phpini && &foreign_check("phpini")) {
	# Add the variables to the domain's php.ini file. Start by finding
	# the variables already set, including those that are commented out.
	&foreign_require("phpini", "phpini-lib.pl");
	local $conf = &phpini::get_config($phpini);

	# Find PHP variables from template and from script
	local @todo;
	foreach my $pv (@tmplphpvars) {
		push(@todo, [ split(/=/, $pv, 2) ]);
		}
	if ($script && defined(&{$script->{'php_vars_func'}})) {
		push(@todo, &{$script->{'php_vars_func'}}($d));
		}

	# Always set the session.save_path to ~/tmp, as on some systems
	# it is set by default to a directory only writable by Apache
	push(@todo, [ 'session.save_path', &create_server_tmp($d) ]);

	# Make and needed changes
	foreach my $t (@todo) {
		local ($n, $v) = @$t;
		if (&phpini::find_value($n, $conf) ne $v) {
			&phpini::save_directive($conf, $n, $v);
			$any++;
			}
		}

	&flush_file_lines();
	}

return $any;
}

# check_pear_module(mod, [php-version], [&domain])
# Returns 1 if some PHP Pear module is installed, 0 if not, or -1 if pear is
# missing.
sub check_pear_module
{
local ($mod, $ver, $d) = @_;
&foreign_require("php-pear", "php-pear-lib.pl");
local @cmds = &php_pear::get_pear_commands();
return -1 if (!@cmds);
if (!defined(@php_pear_modules)) {
	@php_pear_modules = &php_pear::list_installed_pear_modules();
	}
local ($got) = grep { $_->{'name'} eq $mod &&
		      (!$ver || $_->{'pear'} == $ver) } @php_pear_modules;
return $got ? 1 : 0;
}

# check_php_module(mod, [version], [&domain])
# Returns 1 if some PHP module is installed, 0 if not, or -1 if the php command
# is missing
sub check_php_module
{
local ($mod, $ver, $d) = @_;
local @vers = &list_available_php_versions();
local $verinfo;
if ($ver) {
	($verinfo) = grep { $_->[0] == $ver } @vers;
	}
$verinfo ||= $vers[0];
return -1 if (!$verinfo);
local $cmd = $verinfo->[1];
&has_command($cmd) || return -1;
if (!defined($php_modules{$ver})) {
	&clean_environment();
	if ($d) {
		$ENV{'PHPRC'} = "$d->{'home'}/etc";
		}
	local $_;
	&open_execute_command(PHP, "$cmd -m", 1);
	&reset_environment();
	while(<PHP>) {
		s/\r|\n//g;
		if (/^\S+$/ && !/\[/) {
			$php_modules{$ver}->{$_} = 1;
			}
		}
	close(PHP);
	}
return $php_modules{$ver}->{$mod} ? 1 : 0;
}

# check_php_version(&domain, [number])
# Returns true if the given version of PHP is supported by Apache. If no version
# is given, any is allowed.
sub check_php_version
{
local ($d, $ver) = @_;
local @avail = map { $_->[0] } &list_available_php_versions($d);
return $ver ? &indexof($ver, @avail) >= 0
	    : scalar(@avail);
}

# setup_php_version(&domain, &versions, path)
# Checks if one of the given PHP versions is available for the domain.
# If not, sets up a per-directory version if possible.
sub setup_php_version
{
local ($d, $vers, $path) = @_;

# Find the best matching directory
local $dirpath = &public_html_dir($d).$path;
local @dirs = &list_domain_php_directories($d);
foreach my $dir (sort { length($a->{'dir'}) cmp length($b->{'dir'}) } @dirs) {
	if (&is_under_directory($dir->{'dir'}, $dirpath) ||
	    $dir->{'dir'} eq $dirpath) {
		$bestdir = $dir;
		}
	}
$bestdir || &error("Could not find PHP version for $dirpath");

if (&indexof($bestdir->{'version'}, @$vers) >= 0) {
	# The best match dir supports this PHP version .. so we are OK!
	return $bestdir->{'version'};
	}

# Need to add a directory, or fix one
local $ok = &save_domain_php_directory($d, $dirpath, $vers->[0]);
return $ok ? $vers->[0] : undef;
}

# clear_php_version(&domain, &sinfo)
# Removes the custom PHP version setting for some script
sub clear_php_version
{
local ($d, $sinfo) = @_;
if ($sinfo->{'opts'}->{'dir'} &&
    $sinfo->{'opts'}->{'dir'} ne &public_html_dir($d)) {
	&delete_domain_php_directory($d, $sinfo->{'opts'}->{'dir'});
	}
}

# setup_php_modules(&domain, &script, version, php-version)
# If possible, downloads PHP module packages need by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
sub setup_php_modules
{
local ($d, $script, $ver, $phpver) = @_;
local $modfunc = $script->{'php_mods_func'};
return 1 if (!defined(&$modfunc));
local @mods = &$modfunc($d);
foreach my $m (@mods) {
	next if (&check_php_module($m, $phpver, $d) == 1);
	&$first_print(&text('scripts_needmod', "<tt>$m</tt>"));

	# Make sure the software module is installed and can do updates
	if (!&foreign_installed("software")) {
		&$second_print($text{'scripts_esoftware'});
		return 0;
		}
	&foreign_require("software", "software-lib.pl");
	if (!defined(&software::update_system_install)) {
		&$second_print($text{'scripts_eupdate'});
		return 0;
		}

	# Check if the package is already installed
	&$indent_print();
	local $pkg = "php$phpver-$m";
	local @pinfo = &software::package_info($pkg);
	if (!@pinfo) {
		&$first_print(&text('scripts_softwaremod', "<tt>$pkg</tt>"));
		&software::update_system_install($pkg);
		@pinfo = &software::package_info($pkg);
		if (@pinfo) {
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print($text{'scripts_esoftwaremod'});
			&$outdent_print();
			return 0;
			}
		}

	# Configure the domain's php.ini to load it, if needed
	&foreign_require("phpini", "phpini-lib.pl");
	local $mode = &get_domain_php_mode($d);
	local $inifile = $mode eq "mod_php" ? &get_global_php_ini($phpver)
					    : "$d->{'home'}/etc/php.ini";
	local $pconf = &phpini::get_config($inifile);
	local @exts = grep { $_->{'name'} eq 'extension' &&
			     $_->{'enabled'} } @$pconf;
	local ($got) = grep { $_->{'value'} eq "$m.so" } @exts;
	if (!$got) {
		# Needs to be enabled
		&$first_print($text{'scripts_addext'});
		local $lref = &read_file_lines($inifile);
		splice(@$lref, $exts[$#exts]->{'line'}+1, 0, "extension=$m.so");
		&flush_file_lines($inifile);
		undef($phpini::get_config_cache{$inifile});
		&$second_print($text{'setup_done'});
		}

	# Finally re-check to make sure it worked
	&$outdent_print();
	undef(%php_modules);
	if (&check_php_module($m, $phpver, $d) != 1) {
		&$second_print($text{'scripts_einstallmod'});
		return 0;
		}
	else {
		&$second_print(&text('scripts_gotmod', $m));
		}

	# If we are running via mod_php or fcgid, an Apache reload is needed
	if ($mode eq "mod_php" || $mode eq "fcgid") {
		&register_post_action(\&restart_apache);
		}
	}
return 1;
}

# setup_pear_modules(&domain, &script, version, php-version)
# If possible, downloads Pear PHP modules needed by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
sub setup_pear_modules
{
local ($d, $script, $ver, $phpver) = @_;
local $modfunc = $script->{'pear_mods_func'};
return 1 if (!defined(&$modfunc));
local @mods = &$modfunc($d);
foreach my $m (@mods) {
	next if (&check_pear_module($m, $phpver, $d) == 1);

	# Install if needed
	&$first_print(&text('scripts_needpear', "<tt>$m</tt>"));
	&foreign_require("php-pear", "php-pear-lib.pl");
	local $err = &php_pear::install_pear_module($m, $phpver);
	if ($err) {
		print $err;
		&$second_print($text{'scripts_esoftwaremod'});
		return 0;
		}

	# Finally re-check to make sure it worked
	undef(@php_pear_modules);
	if (&check_pear_module($m, $phpver, $d) != 1) {
		&$second_print($text{'scripts_einstallpear'});
		return 0;
		}
	else {
		&$second_print(&text('scripts_gotpear', $m));
		}
	}
return 1;
}

# get_global_php_ini(phpver, mode)
# Returns the full path to the global PHP config file
sub get_global_php_ini
{
local ($ver, $mode) = @_;
foreach my $i ("/etc/php.ini",
	       ($mode eq "mod_php" ? "/etc/php$ver/apache/php.ini"
				   : "/etc/php$ver/cgi/php.ini"),
	       "/usr/local/lib/php.ini") {
	return $i if (-r $i);
	}
return undef;
}

# validate_script_path(&opts, &script, &domain)
# Checks the 'path' in script options, and sets 'dir' and possibly
# modifies 'path'. Returns an error message if the path is not valid
sub validate_script_path
{
local ($opts, $script, $d) = @_;
if (&indexof("horde", @{$script->{'uses'}}) >= 0) {
	# Under Horde directory
	local @scripts = &list_domain_scripts($d);
	local ($horde) = grep { $_->{'name'} eq 'horde' } @scripts;
	$horde || return "Script uses Horde, but it is not installed";
	$opts->{'path'} eq '/' && return "A path of / is not valid for Horde scripts";
	$opts->{'db'} = $horde->{'opts'}->{'db'};
	$opts->{'dir'} = $horde->{'opts'}->{'dir'}.$opts->{'path'};
	$opts->{'path'} = $horde->{'opts'}->{'path'}.$opts->{'path'};
	}
elsif ($opts->{'path'} =~ /^\/cgi-bin/) {
	# Under cgi directory
	local $hdir = &cgi_bin_dir($d);
	$opts->{'dir'} = $opts->{'path'} eq "/" ?
				$hdir : $hdir.$opts->{'path'};
	}
else {
	# Under HTML directory
	local $hdir = &public_html_dir($d);
	$opts->{'dir'} = $opts->{'path'} eq "/" ?
				$hdir : $hdir.$opts->{'path'};
	}
return undef;
}

# script_path_url(&domain, &opts)
# Returns a URL for a script, based on the domain name and path from options.
# The path always ends with a /
sub script_path_url
{
local ($d, $opts) = @_;
local $pt = $d->{'web_port'} == 80 ? "" : ":$d->{'web_port'}";
local $pp = $opts->{'path'} eq '/' ? '' : $opts->{'path'};
if ($pp !~ /\.(cgi|pl|php)$/i) {
	$pp .= "/";
	}
return "http://$d->{'dom'}$pt$pp";
}

# show_template_scripts(&tmpl)
# Outputs HTML for editing script installer template options
sub show_template_scripts
{
local ($tmpl) = @_;
local $scripts = &list_template_scripts($tmpl);

print "<tr> <td colspan=2>\n";

print $text{'tscripts_what'},"\n";
print &ui_radio("def",
	$scripts eq "none" ? 2 :
	  @$scripts ? 0 :
	  $tmpl->{'default'} ? 2 : 1,
	[ [ 2, $text{'tscripts_none'} ],
	  $tmpl->{'default'} ? ( ) : ( [ 1, $text{'default'} ] ),
	  [ 0, $text{'tscripts_below'} ] ]),"<p>\n";

# Find scripts
@opts = ( );
foreach $sname (&list_available_scripts()) {
	$script = &get_script($sname);
	foreach $v (@{$script->{'versions'}}) {
		push(@opts, [ "$sname $v", "$script->{'desc'} $v" ]);
		}
	}
@opts = sort { lc($a->[1]) cmp lc($b->[1]) } @opts;
@dbopts = ( );
push(@dbopts, [ "mysql", $text{'databases_mysql'} ]) if ($config{'mysql'});
push(@dbopts, [ "postgres", $text{'databases_postgres'} ]) if ($config{'postgres'});

# Show table of scripts
print &ui_columns_start([ $text{'tscripts_name'},
			  $text{'tscripts_path'},
			  $text{'tscripts_db'},
			  $text{'tscripts_dbtype'} ]);
$empty = { 'db' => '${DB}' };
@list = $scripts eq "none" ? ( $empty ) : ( @$scripts, $empty );
$i = 0;
foreach $script (@list) {
	$db_def = $script->{'db'} eq '${DB}' ? 1 :
                        $script->{'db'} ? 2 : 0;
	print &ui_columns_row([
		&ui_select("name_$i", $script->{'name'},
		  [ [ undef, "&nbsp;" ], @opts ]),
		&ui_textbox("path_$i", $script->{'path'}, 25),
		&ui_radio("db_def_$i",
			$db_def,
			[ [ 0, $text{'tscripts_none'} ],
			  [ 1, $text{'tscripts_dbdef'}."<br>" ],
			  [ 2, $text{'tscripts_other'}." ".
			       &ui_textbox("db_$i",
				$db_def == 1 ? "" : $script->{'db'}, 10) ] ]),
		&ui_select("dbtype_$i", $script->{'dbtype'}, \@dbopts),
		], [ "valign=top", "valign=top", undef, "valign=top" ]);
		    
	$i++;
	}
print &ui_columns_end();

print "</td> </tr>\n";
}

# parse_template_scripts(&tmpl)
# Updates script installer template options from %in
sub parse_template_scripts
{
local ($tmpl) = @_;

local $scripts;
if ($in{'def'} == 2) {
	# None explicitly chosen
	$scripts = "none";
	}
elsif ($in{'def'} == 1) {
	# Fall back to default
	$scripts = [ ];
	}
else {
	# Parse script list
	$scripts = [ ];
	for($i=0; defined($name = $in{"name_$i"}); $i++) {
		next if (!$name);
		local $script = { 'id' => $i,
			    	  'name' => $name };
		local $path = $in{"path_$i"};
		$path =~ /^\/\S*$/ || &error(&text('tscripts_epath', $i+1));
		$script->{'path'} = $path;
		$script->{'dbtype'} = $in{"dbtype_$i"};
		if ($in{"db_def_$i"} == 1) {
			$script->{'db'} = '${DB}';
			}
		elsif ($in{"db_def_$i"} == 2) {
			$in{"db_$i"} =~ /^\S+$/ ||
				&error(&text('tscripts_edb', $i+1));
			$in{"db_$i"} =~ /\$/ ||
				&error(&text('tscripts_edb2', $i+1));
			$script->{'db'} = $in{"db_$i"};
			}
		push(@$scripts, $script);
		}
	@$scripts || &error($text{'tscripts_enone'});
	}
&save_template_scripts($tmpl, $scripts);
}

# osdn_package_versions(project, fileregexp, ...)
# Given a sourceforge project name and a regexp that matches filenames
# (like cpg([0-9\.]+).zip), returns a list of version numbers found, newest 1st
sub osdn_package_versions
{
local ($project, @res) = @_;
local ($alldata, $err);
&http_download($osdn_download_host, $osdn_download_port, "/$project/",
	       \$alldata, \$err);
return ( ) if ($err);
local @vers;
foreach my $re (@res) {
	local $data = $alldata;
	while($data =~ /$re(.*)/is) {
		push(@vers, $1);
		$data = $2;
		}
	}
@vers = sort { &compare_versions($b, $a) } &unique(@vers);
return @vers;
}

sub can_script_version
{
local ($script, $ver) = @_;
return 1 if (&master_admin() ||
	     !$script->{'minversion'} ||
	     &compare_versions($ver, $script->{'minversion'}) >= 0);
}

sub post_http_connection
{
local ($host, $port, $page, $params, $out, $err) = @_;

local $h = &make_http_connection($host, $port, 0, "POST", $page);
if (!ref($h)) {
	$$err = $h;
	return 0;
	}
&write_http_connection($h, "Host: $host\r\n");
&write_http_connection($h, "User-agent: Webmin\r\n");
&write_http_connection($h, "Content-type: application/x-www-form-urlencoded\r\n");
&write_http_connection($h, "Content-length: ".length($params)."\r\n");
&write_http_connection($h, "\r\n");
&write_http_connection($h, "$params\r\n");

# Read back the results
&complete_http_download($h, $out, $err);
}

# make_file_php_writable(&domain, file, [dir-only], [owner-too])
# Set permissions on a file so that it is writable by PHP
sub make_file_php_writable
{
local ($d, $file, $dironly, $setowner) = @_;
local $mode = &get_domain_php_mode($d);
local $perms = $mode eq "mod_php" ? 0777 : 0755;
if (-d $file && !$dironly) {
	if ($setowner) {
		&system_logged(sprintf("chown -R %d:%d %s",
			$d->{'uid'}, $d->{'gid'}, quotemeta($file)));
		}
	&system_logged(sprintf("chmod -R %o %s", $perms, quotemeta($file)));
	}
else {
	if ($setowner) {
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
					   $perms, $file);
		}
	else {
		&set_ownership_permissions(undef, undef, $perms, $file);
		}
	}
}

# make_file_php_nonwritable(&domain, file, [dir-only])
sub make_file_php_nonwritable
{
local ($d, $file, $dironly) = @_;
if (-d $file && !$dironly) {
	&system_logged("chmod -R 555 ".quotemeta($file));
	}
else {
	&set_ownership_permissions(undef, undef, 0555, $file);
	}
}

1;

