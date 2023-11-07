# Functions for scripts

# list_scripts([core-only])
# Returns a list of installable script names
sub list_scripts
{
local ($coreonly) = @_;
local @rv;

# From core directories
my @sd = @scripts_directories;
if ($coreonly) {
	@sd = grep { /^\Q$module_root_directory\// } @sd;
	}
foreach my $s (@sd) {
	opendir(DIR, $s);
	foreach $f (readdir(DIR)) {
		push(@rv, $1) if ($f =~ /^(.*)\.pl$/);
		}
	closedir(DIR);
	}

# From plugins
if (!$coreonly) {
	foreach my $p (&list_script_plugins()) {
		push(@rv, &plugin_call($p, "scripts_list"));
		}
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
if (!&master_admin() || !$unavail{'allowmaster'}) {
	# Remove globally disabled scripts
	@rv = grep { $unavail{$_} eq '0' ||
		     $unavail{$_} eq '' && !$unavail{'denydefault'} } @rv;
	}
if ($access{'allowedscripts'}) {
	# Remove per-user disallowed scripts
	local %allow = map { $_, 1 } split(/\s+/, $access{'allowedscripts'});
	@rv = grep { $allow{$_} } @rv;
	}
return @rv;
}

# get_script(name, [core-only])
# Returns the structure for some script
sub get_script
{
local ($name, $coreonly) = @_;

# Find all .pl files for this script, which may come from plugins or
# the core
local @sfiles;
foreach my $s ($coreonly ? "$module_root_directory/scripts"
		         : @scripts_directories) {
	local $spath = "$s/$name.pl";
	local @st = stat($spath);
	if (@st) {
		push(@sfiles, [ $spath, $st[9],
			&guess_script_version($spath),
			$s eq $scripts_directories[0] ? 'custom' :
			 $s eq $scripts_directories[1] ? 'latest' : 'core' ]);
		}
	}
if (!$coreonly) {
	foreach my $p (&list_script_plugins()) {
		local $spath = &module_root_directory($p)."/$name.pl";
		local @st = stat($spath);
		if (@st) {
			push(@sfiles, [ $spath, $st[9],
				&guess_script_version($spath), 'plugin' ]);
			}
		}
	}
return undef if (!@sfiles);

# Work out the newest one, so that plugins can override Virtualmin and
# vice-versa
if (@sfiles > 1) {
	local @notver = grep { !$_->[2] } @sfiles;
	if (@notver) {
		# Need to use time-based comparison
		@sfiles = sort { $b->[1] <=> $a->[1] } @sfiles;
		}
	else {
		# Use version numbers
		@sfiles = sort { &compare_versions($b->[2], $a->[2]) } @sfiles;
		}
	}
local $spath = $sfiles[0]->[0];
local $sdir = $spath;
$sdir =~ s/\/[^\/]+$//;

# Read in the .pl file
(do $spath) || return undef;
local $dfunc = "script_${name}_desc";
local $lfunc = "script_${name}_longdesc";
local $vfunc = "script_${name}_versions";
local $nvfunc = "script_${name}_numeric_version";
local $rvfunc = "script_${name}_release_version";
local $rfunc = "script_${name}_release";
local $ufunc = "script_${name}_uses";
local $vdfunc = "script_${name}_version_desc";
local $catfunc = "script_${name}_category";
local $disfunc = "script_${name}_disabled";
local $sitefunc = "script_${name}_site";
local $authorfunc = "script_${name}_author";
local $overlapfunc = "script_${name}_overlap";
local $migratedfunc = "script_${name}_migrated";
local $testpathfunc = "script_${name}_testpath";
local $testargsfunc = "script_${name}_testargs";

# Check for critical functions
return undef if (!defined(&$dfunc) || !defined(&$vfunc));

# Work out availability
local %unavail;
&read_file_cached($scripts_unavail_file, \%unavail);
local $disabled;
if (defined(&$disfunc)) {
	$disabled = &$disfunc();
	}
local $allowmaster;
if (&master_admin()) {
	($allowmaster) = &get_script_master_permissions();
	}
local $avail = $unavail{$name} eq '0' ||
	       $unavail{$name} eq '' && !$unavail{'denydefault'};
local $avail_only = !$unavail{$name};
if ($access{'allowedscripts'}) {
	local %allow = map { $_, 1 } split(/\s+/, $access{'allowedscripts'});
	$avail = 0 if (!$allow{$name});
	}

# Create script structure
local $rv = { 'name' => $name,
	      'desc' => &$dfunc(),
	      'longdesc' => defined(&$lfunc) ? &$lfunc() : undef,
	      'versions' => [ &$vfunc(0) ],
	      'install_versions' => [ &$vfunc(1) ],
	      'preferred_version_func' => "script_${name}_preferred_version",
	      'numeric_version' => defined(&$nvfunc) ? &$nvfunc() : 0,
	      'release_version' => defined(&$rvfunc) ? &$rvfunc() : 0,
	      'release' => defined(&$rfunc) ? &$rfunc() : 0,
	      'uses' => defined(&$ufunc) ? [ &$ufunc() ] : [ ],
	      'site' => defined(&$sitefunc) ? &$sitefunc() : undef,
	      'author' => defined(&$authorfunc) ? &$authorfunc() : undef,
	      'overlap' => defined(&$overlapfunc) ? &$overlapfunc() : undef,
	      'dir' => $sdir,
	      'filename' => $spath,
	      'source' => $sfiles[0]->[3],
	      'depends_func' => "script_${name}_depends",
	      'dbs_func' => "script_${name}_dbs",
	      'db_conn_desc_func' => "script_${name}_db_conn_desc",
	      'params_func' => "script_${name}_params",
	      'parse_func' => "script_${name}_parse",
	      'check_func' => "script_${name}_check",
	      'install_func' => "script_${name}_install",
	      'uninstall_func' => "script_${name}_uninstall",
	      'realversion_func' => "script_${name}_realversion",
	      'can_upgrade_func' => "script_${name}_can_upgrade",
	      'stop_func' => "script_${name}_stop",
	      'stop_server_func' => "script_${name}_stop_server",
	      'start_server_func' => "script_${name}_start_server",
	      'status_server_func' => "script_${name}_status_server",
	      'files_func' => "script_${name}_files",
	      'php_vars_func' => "script_${name}_php_vars",
	      'php_mods_func' => "script_${name}_php_modules",
	      'php_opt_mods_func' => "script_${name}_php_optional_modules",
	      'php_fullver_func' => "script_${name}_php_fullver",
	      'php_maxver_func' => "script_${name}_php_maxver",
	      'pear_mods_func' => "script_${name}_pear_modules",
	      'perl_mods_func' => "script_${name}_perl_modules",
	      'perl_opt_mods_func' => "script_${name}_opt_perl_modules",
	      'python_fullver_func' => "script_${name}_python_fullver",
	      'python_maxver_func' => "script_${name}_python_maxver",
	      'python_mods_func' => "script_${name}_python_modules",
	      'python_opt_mods_func' => "script_${name}_opt_python_modules",
	      'gem_version_func' => "script_${name}_gem_version",
	      'gems_func' => "script_${name}_gems",
	      'latest_func' => "script_${name}_latest",
	      'check_latest_func' => "script_${name}_check_latest",
	      'commands_func' => "script_${name}_commands",
	      'packages_func' => "script_${name}_packages",
	      'passmode_func' => "script_${name}_passmode",
	      'gpl_func' => "script_${name}_gpl",
	      'avail' => $avail && !$disabled || $allowmaster,
	      'avail_only' => $avail_only,
	      'enabled' => !$disabled,
	      'nocheck' => $disabled == 2,
	      'minversion' => $unavail{$name."_minversion"},
	      'abandoned_func' => "script_${name}_abandoned",
	      'migrated_func' => "script_${name}_migrated",
	      'testable_func' => "script_${name}_testable",
	      'testpath_func' => "script_${name}_testpath",
	      'testargs_func' => "script_${name}_testargs",
	    };
if (defined(&$catfunc)) {
	my @cats = &$catfunc();
	$rv->{'category'} = $cats[0];
	$rv->{'categories'} = \@cats;
	}
if (defined(&$vdfunc)) {
	foreach my $ver (@{$rv->{'versions'}},
			 @{$rv->{'install_versions'}}) {
		$rv->{'vdesc'}->{$ver} = &$vdfunc($ver);
		}
	}
if (defined(&$migratedfunc)) {
	$rv->{'migrated'} = 1;
	}
return $rv;
}

# list_domain_scripts(&domain)
# Returns a list of scripts and versions already installed for a domain. Each
# entry in the list is a hash ref containing the id, name, version and opts
sub list_domain_scripts
{
my ($d) = @_;
my $ddir = "$script_log_directory/$d->{'id'}";
my @rv;
opendir(DIR, $ddir);
while(my $f = readdir(DIR)) {
	if ($f =~ /^(\S+)\.script$/) {
		my %info;
		&read_file("$ddir/$f", \%info);
		my @st = stat("$ddir/$f");
		$info{'id'} = $1;
		$info{'file'} = "$ddir/$f";
		foreach my $i (keys %info) {
			if ($i =~ /^opts_(.*)$/) {
				$info{'opts'}->{$1} = $info{$i};
				delete($info{$i});
				}
			}
		$info{'time'} = $st[9];
		if ($info{'opts'}->{'dir'} && !-e $info{'opts'}->{'dir'}) {
			$info{'deleted'} = 1;
			}
		else {
			$info{'deleted'} = 0;
			}
		if ($info{'url'} =~ /^(http|https):\/\/([^\/]+)(\/.*)/) {
			# Fix URL to match actual domain name
			my $url = &get_domain_url($d, $1 eq "https");
			$info{'url'} = $url.$3;
			}
		push(@rv, \%info);
		}
	}
closedir(DIR);
return @rv;
}

# add_domain_script(&domain, name, version, &opts, desc, url,
#		    [login, password], [partial-failure])
# Records the installation of a script for a domains
sub add_domain_script
{
local ($d, $name, $version, $opts, $desc, $url, $user, $pass, $partial) = @_;
$main::add_domain_script_count++;
local %info = ( 'id' => time().$$.$main::add_domain_script_count,
		'name' => $name,
		'version' => $version,
		'desc' => $desc,
		'url' => $url,
		'user' => $user,
		'pass' => $pass,
		'partial' => $partial );
local $o;
foreach $o (keys %$opts) {
	$info{'opts_'.$o} = $opts->{$o};
	}
&make_dir($script_log_directory, 0700);
&make_dir("$script_log_directory/$d->{'id'}", 0700);
&write_file("$script_log_directory/$d->{'id'}/$info{'id'}.script", \%info);
return \%info;
}

# save_domain_script(&domain, &sinfo)
# Updates a script object for a domain on disk
sub save_domain_script
{
local ($d, $sinfo) = @_;
local %info;
foreach my $k (keys %$sinfo) {
	if ($k eq 'id' || $k eq 'file') {
		next;	# No need to save
		}
	elsif ($k eq 'opts') {
		local $opts = $sinfo->{'opts'};
		foreach my $o (keys %$opts) {
			$info{'opts_'.$o} = $opts->{$o};
			}
		}
	else {
		$info{$k} = $sinfo->{$k};
		}
	}
&write_file("$script_log_directory/$d->{'id'}/$sinfo->{'id'}.script", \%info);
}

# remove_domain_script(&domain, &script-info)
# Records the un-install of a script for a domain
sub remove_domain_script
{
local ($d, $info) = @_;
&unlink_file($info->{'file'});
}

# find_database_table([&domain], dbtype, dbname, table|regexp)
# Returns 1 if some table exists in the specified database (if the db exists)
# XXX horrible hack - this handles the case where $d is defined in the local
#     scope by script callers, because they can't be all updated at once to
#     pass in the database
sub find_database_table
{
my $myd = ref($_[0]) ? shift(@_) : $d;
my ($dbtype, $dbname, $table) = @_;
local $cfunc = "check_".$dbtype."_database_clash";
if (&$cfunc(undef, $dbname)) {
	local $lfunc = "list_".$dbtype."_tables";
	local @tables = &$lfunc($myd, $dbname);
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
	delete($unavail{$n."_minversion"});
	if (!$script->{'avail_only'}) {
		$unavail{$n} = 1;
		}
	else {
		$unavail{$n} = 0;
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
local %serial;
&read_env_file($virtualmin_license_file, \%serial);

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
		# Need to fetch it .. build list of possible URLs, from script
		# and from Virtualmin
		local @urls;
		my $temp = &transname($f->{'file'});
		local $newurl = &convert_osdn_url($f->{'url'});
		push(@urls, [ $newurl || $f->{'url'}, $f->{'nocache'},
			      $f->{'user'}, $f->{'pass'} ]);
		local $vurl = "http://$script_download_host:$script_download_port$script_download_dir$f->{'file'}";
		if ($f->{'virtualmin'}) {
			# Use Virtualmin site first, for scripts that don't
			# have a version-specific name
			unshift(@urls, [ $vurl, $f->{'nocache'},
					 $serial{'SerialNumber'},
					 $serial{'LicenseKey'} ]);
			}
		else {
			push(@urls, [ $vurl, $f->{'nocache'},
				      $serial{'SerialNumber'},
				      $serial{'LicenseKey'} ]);
			}

		# Add to URL list attempts with no cache, for cached URLs
		my @firsturls = @urls;
		foreach my $urlcache (@firsturls) {
			next if ($urlcache->[0] !~ /^(http|https):/);
			my ($host, $port, $page, $ssl) =
				&parse_http_url($urlcache->[0]);
			my $canonical = ($ssl ? "https" : "http")."://".
					$host.":".$port.$page;
			if (&check_in_http_cache($canonical) &&
			    !$urlcache->[1]) {
				push(@urls, [ $urlcache->[0], 1,
					      $urlcache->[2], $urlcache->[3] ]);
				}
			}

		# Try each URL
		local $firsterror;
		foreach my $urlcache (@urls) {
			my ($url, $nocache, $user, $pass) = @$urlcache;
			local $error;
			$progress_callback_url = $url;
			local %headers;
			if ($f->{'referer'}) {
				$headers{'Referer'} = $f->{'referer'};
				}
			if ($url =~ /^http/) {
				# Via HTTP
				my ($host, $port, $page, $ssl) =
					&parse_http_url($url);
				&http_download($host, $port, $page, $temp,
					       \$error, $cb, $ssl, $user, $pass,
					       undef, 0, $nocache,
					       \%headers);
				}
			elsif ($url =~ /^ftp:\/\/([^\/]+)(\/.*)/) {
				# Via FTP
				my ($host, $page) = ($1, $2);
				&ftp_download($host, $page, $temp, \$error,
					    $cb, $user, $pass, undef, $nocache);
				}
			else {
				$firsterror ||= &text('scripts_eurl', $url);
				next;
				}
			if ($error) {
				$firsterror ||=
				    &text('scripts_edownload', $error, $url);
				next;
				}
			&set_ownership_permissions($d->{'uid'}, $d->{'ugid'},
						   undef, $temp);

			# Make sure the downloaded file is in some archive
			# format, or is Perl or PHP.
			local $fmt = &compression_format($temp);
			local $cont;
			if (!$fmt && $temp =~ /\.(pl|php|phar)$/i) {
				$cont = &read_file_contents($temp);
				}
			if (!$fmt &&
			    $cont !~ /^\#\!\s*\S+(perl|php)/i &&
			    $cont !~ /^\#\!\/usr\/bin\/env\s+(perl|php)/i &&
			    $cont !~ /^\s*<\?php/i) {
				$firsterror ||=
					&text('scripts_edownload2', $url);
				next;
				}

			# Check that it is a valid compressed file
			if ($fmt) {
				local $e = &extract_compressed_file($temp);
				if ($e) {
					$firsterror ||=
					  &text('scripts_edownload3', $url, $e);
					next;
					}
				}

			# If we got this far, it must have worked!
			&set_ownership_permissions(undef, undef, 0644, $temp);
			$firsterror = undef;
			last;
			}
		return $firsterror if ($firsterror);

		$gotfiles->{$f->{'name'}} = $temp;
		}
	}
return undef;
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
		$newdbtype = $d->{'mysql'} ? "mysql" :
		             $d->{'postgres'} ? "postgres" : undef;
		if (!$newdbtype) {
			return &text('scripts_nodbavail',
				&vui_edit_link_icon("edit_domain.cgi?dom=$d->{'id'}"));
			}
		if ($tmpl->{'mysql_suffix'} ne "none") {
			local $prefix = &substitute_domain_template(
						$tmpl->{'mysql_suffix'}, $d);
			$prefix =~ s/-/_/g;
			$prefix =~ s/\./_/g;
			if ($prefix && $prefix !~ /_$/) {
				# Always use _ as separator
				$prefix .= "_";
				}
			$newdbname = &fix_database_name($prefix.$newsuffix,
							$newdbtype);
			}
		else {
			$newdbname = &database_name($d)."_".$newsuffix;
			}
		$newdbdesc = $text{'databases_'.$newdbtype};

		# Check if an existing DB with the same name already exists,
		# and if so add a suffix for the new DB
		local $count = 1;
		while(1) {
			my ($already) = grep { $_->{'type'} eq $newdbtype &&
				       $_->{'name'} eq $newdbname } @$dbs;
			last if (!$already);
			$newdbname =~ s/_(\d+)$//;
			$newdbname .= "_".(++$count);
			}
		$value ||= "*".$newdbtype."_".$newdbname;
		}
	}
return &ui_select($name, $value,
	[ sort { $a->[0] cmp $b->[0] }
	  (map { [ $_->{'type'}."_".$_->{'name'},
		   $_->{'name'}." (".$_->{'desc'}.")" ] } @$dbs),
	  $newdbname ? ( [ "*".$newdbtype."_".$newdbname,
			   &text('scripts_newdb', $newdbname, $newdbdesc) ] )
		     : ( ) ] );
}

# create_script_database(&domain, db-spec, [&options])
# Create a new database for a script. Returns undef on success, or an error
# message on failure.
sub create_script_database
{
my ($d, $dbspec, $opts) = @_;
local ($dbtype, $dbname) = split(/_/, $dbspec, 2);

# Check limits (again)
local ($dleft, $dreason, $dmax) = &count_feature("dbs");
if ($dleft == 0) {
	return "You are not allowed to create any more databases";
	}
if (!&can_edit_databases()) {
	return "You are not allowed to create databases";
	}

$cfunc = "check_".$dbtype."_database_clash";
&$cfunc($d, $dbname) && return "The database $dbname already exists";

# Work out default creation options
$ofunc = "default_".$dbtype."_creation_opts";
if (!$opts && defined(&$ofunc)) {
	$opts = &$ofunc($d);
	}

# Do the creation
&push_all_print();
if (&indexof($dbtype, &list_database_plugins()) >= 0) {
	&plugin_call($dbtype, "database_create", $d, $dbname);
	}
else {
	$crfunc = "create_".$dbtype."_database";
	&$crfunc($d, $dbname, $opts);
	}
&save_domain($d);
&refresh_webmin_user($d);
&pop_all_print();

return undef;
}

# cleanup_script_database(&domain, dbspec, &tables|table-re)
# Delete all tables in some database owned by some script. Returns an error
# on failure, or undef on success.
sub cleanup_script_database
{
local ($d, $dbspec, $tables) = @_;
local ($dbtype, $dbname) = split(/_/, $dbspec, 2);
local $droperr;
eval {
	local $main::error_must_die = 1;
	if ($dbtype eq "mysql") {
		# Delete from MySQL
		&require_mysql();
		foreach my $t (&list_dom_mysql_tables($d, $dbname)) {
			if (ref($tables) && &indexoflc($t, @$tables) >= 0 ||
			    !ref($tables) && $t =~ /^$tables/i) {
				eval {
					&execute_dom_sql($d, $dbname,
						"drop table ".
						&mysql::quotestr($t));
					};
				$droperr ||= $@;
				}
			}
		}
	elsif ($dbtype eq "postgres") {
		# Delete from PostgreSQL
		&require_postgres();
		foreach my $t (&list_postgres_tables($d, $dbname)) {
			if (ref($tables) && &indexoflc($t, @$tables) >= 0 ||
			    !ref($tables) && $t =~ /^$tables/i) {
				eval {
					&execute_dom_psql(
						$d, $dbname,
						"drop table ".
						&postgresql::quote_table($t));
					};
				$droperr ||= $@;
				}
			}
		}
	};
return $@ || $droperr;
}

# delete_script_database(&domain, dbspec)
# Deletes the database that was created for some script, if it is empty
sub delete_script_database
{
local ($d, $dbspec) = @_;
local ($dbtype, $dbname) = split(/_/, $dbspec, 2);

local $cfunc = "check_".$dbtype."_database_clash";
if (!&$cfunc($d, $dbname)) {
	return "Database $dbname does not exist";
	}

local $lfunc = "list_".$dbtype."_tables";
local @tables = &$lfunc($d, $dbname);
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

# get_script_database_credentials(&domain, &script-opts)
# Returns database credentials for a given script under certain domain
sub get_script_database_credentials
{
my ($d, $opts) = @_;
my ($sdbtype, $sdbname) = split(/_/, $opts->{'db'}, 2);
my $sdbhost = &get_database_host($sdbtype, $d);
my $sdbuser = $sdbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
my $sdbpass = $sdbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
return ($sdbhost, $sdbtype, $sdbname, $sdbuser, $sdbpass);
}

# update_all_installed_scripts_database_credentials(&domain, &olddomain, option-record-type, option-record-value, database-type)
# Updates script's given database related setting option (db-username, db-password, db-name)
# with a new value for all installed scripts under the given virtual server, considering database type,
# in case installed script supports it (uses database).
sub update_all_installed_scripts_database_credentials
{
my ($d, $oldd, $type, $value, $dbtype) = @_;
my @domain_scripts = &list_domain_scripts($d);
my ($printed_type, @printed_name);
foreach my $script (@domain_scripts) {
	my $sname = $script->{'name'};
	my $sdata = &get_script($sname);
	my $sproject = $script->{'opts'}->{'project'};
	my $db_conn_desc = $sdata->{'db_conn_desc_func'};
	my ($sdbtype) = split(/_/, $script->{'opts'}->{'db'}, 2);
	my $sdir = $script->{'opts'}->{'dir'};
	my ($dhome, $olddhome) = ($d->{'home'}, $oldd->{'home'});
	if ($dhome ne $olddhome) {
		$sdir =~ s/^\Q$olddhome\E/$dhome/;
		}
	if (defined(&$db_conn_desc) && $dbtype eq $sdbtype) {
		# Check if a script has a description sub
		$db_conn_desc = &{$db_conn_desc};
		if (ref($db_conn_desc)) {
			&$first_print($text{"save_installed_scripts_${type}_${dbtype}"}) if (!$printed_type++);
			# Extract script config file(s) to operate on
			my @script_config_files = keys %{$db_conn_desc};
			my $script_config_files_count = scalar(@script_config_files);
			my $script_config_file_count;
			foreach my $script_config_file (@script_config_files) {
				my $script_config_types = $db_conn_desc->{$script_config_file};
				if (ref($script_config_types)) {
					# Check if described type in a script file equals the one from the caller
					my ($config_type_current) = grep {$_ eq $type} keys %{$script_config_types};
					if ($config_type_current) {
						&$indent_print() if(!$script_config_file_count++);
						&$first_print("$sdata->{'desc'} ..") if (!$printed_name[$sdata->{'desc'}]), push(@printed_name, $sdata->{'desc'});
						my $script_options_to_update = $script_config_types->{$config_type_current};
						my ($replace_target, $replace_with, $value_func, @value_func_params, $script_option_multi, $script_option_after, %options_multi);
						foreach my $script_option (keys %{$script_options_to_update}) {
							# Parse repalce
							if ($script_option eq 'replace') {
								$replace_target = $script_options_to_update->{$script_option}->[0];
								$replace_with = $script_options_to_update->{$script_option}->[1];
								}
							# Parse optional function to run on the replacement
							if ($script_option eq 'func') {
								$value_func = $script_options_to_update->{$script_option};
								}
							# Parse optional function params
							if ($script_option eq 'func_params') {
								@value_func_params = split(',', $script_options_to_update->{$script_option});
								}
							# Check if multi params must be replaced (complex replacement)
							if ($script_option eq 'multi') {
								$script_option_multi++;
								}
							# Include after regexp type (e.g. Drupal multiformat array (multi and single line))
							if ($script_option eq 'after') {
								$script_option_after++;
								}
							}

						# If value is not set, use existing data to just update
						if (!$value) {
							my ($sdbhost, $sdbtype, $sdbname, $sdbuser, $sdbpass) =
							    &get_script_database_credentials($d, $script->{'opts'});
							if ($type =~ /host$/) {
								$value = $sdbhost;
								}
							elsif ($type =~ /name$/) {
								$value = $sdbname;
								}
							elsif ($type =~ /user$/) {
								$value = $sdbuser;
								}
							elsif ($type =~ /pass$/) {
								$value = $sdbpass;
								}
							}

						# Pass new value through optional function if defined
						if (defined(&$value_func)) {
							$value = &$value_func($value, @value_func_params);
						}
						
						# Prepare substitution for complex replacement for multiple
						# options by getting other credentials from current config
						if ($script_option_multi) {
							my ($sdbhost, $sdbtype, $sdbname, $sdbuser, $sdbpass) =
							    &get_script_database_credentials($d, $script->{'opts'});
							%options_multi = ('sdbhost' => $sdbhost,
							                  'sdbtype' => $sdbtype,
							                  'sdbname' => $sdbname,
							                  'sdbuser' => $sdbuser,
							                  'sdbpass' => $sdbpass
							                 );
							}

						# Construct simple replacement based on type
						else {
							$replace_with =~ s/\$\$s$type/$value/;
							}

						# Run substitution if target and replacement are fine
						my ($error, $success);

						# Config file to run replacements on
						my $script_config_file_path = "$sdir/$script_config_file";

						# If script project is set, change config file path accordingly
						if ($sproject) {
							if (-r "$sdir/$sproject/$sproject/$script_config_file") {
								$script_config_file_path = "$sdir/$sproject/$sproject/$script_config_file";
								}
							elsif (-r "$sdir/$sproject/$script_config_file") {
								$script_config_file_path = "$sdir/$sproject/$script_config_file";
								}
							}
						if (-w $script_config_file_path) {
							&set_filepath_permissions_as_domain_user($d, $script_config_file_path, 0755, $sdir);
							my $script_config_file_lines = &read_file_lines_as_domain_user($d, $script_config_file_path);
							if ($replace_target && $replace_with) {
								foreach my $config_file_line (@{$script_config_file_lines}) {
									if ($config_file_line =~ /(?<before>.*)(?<replace_target>$replace_target)(?<after>.*)/) {
										my $include_after = $script_option_after ? "$+{after}" : "";
										if ($script_option_multi) {
											# Construct replacement first
											foreach my $option_multi (keys %options_multi) {
												# Substitute with new value
												my $option_multi_value = $options_multi{$option_multi};
												if ($option_multi eq "s$type") {
													$option_multi_value = $value;
													}
												$replace_with =~ s/\$\$$option_multi/$option_multi_value/;
												}
											# Perform complex replacement (multi)
											$config_file_line = "$+{before}$+{replace_target}$replace_with$include_after";
											}
										else {
											# Perform simple replacement
											$config_file_line = "$+{before}$replace_with$include_after";
											}
										$success++;
										}
									}
								}
							&flush_file_lines_as_domain_user($d, $script_config_file_path);
							&restore_filepath_permissions_as_domain_user($d, $script_config_file_path, $sdir);
							if ($success) {
								$success = 
									$script_config_files_count > 1 ?
									   &text('save_installed_scripts_done', $script_config_file) :
									   $text{'setup_done'};
								}
							else {
								$error = &text('save_installed_scripts_err_file_lines', $script_config_file);
								}
						}
						else {
							$error = &text('save_installed_scripts_err_file', $script_config_file);
							}
						&$first_print($error || $success);
						&$outdent_print() if($script_config_file_count == $script_config_files_count);
						}
					}
				}
			}
		}
	}
&$second_print($text{"setup_done"}) if ($printed_type);
}

# setup_web_for_php(&domain, &script, php-version)
# Update a virtual server's web config to add any PHP settings from the template
sub setup_web_for_php
{
local ($d, $script, $phpver) = @_;
local $tmpl = &get_template($d->{'template'});
local $any = 0;
local $varstr = &substitute_domain_template($tmpl->{'php_vars'}, $d);
local @tmplphpvars = $varstr eq 'none' ? ( ) : split(/\t+/, $varstr);
local $p = &domain_has_website($d);

if ($p eq "web" && &get_apache_mod_php_version()) {
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
		local $changed;
		foreach my $pv (@tmplphpvars) {
			local ($n, $v) = split(/=/, $pv, 2);
			local $diff = $n =~ s/^(\+|\-)// ? $1 : undef;
			if (!$got{$n}) {
				push(@phpv, "$n $v");
				$changed++;
				}
			}
		if ($script && defined(&{$script->{'php_vars_func'}})) {
			# Get from script too
			foreach my $v (&{$script->{'php_vars_func'}}($d)) {
				if (!$got{$v->[0]}) {
					if ($v->[1] =~ /\s/) {
						push(@phpv,
						     "$v->[0] \"$v->[1]\"");
						}
					else {
						push(@phpv, "$v->[0] $v->[1]");
						}
					$changed++;
					}
				}
			}

		# Update if needed
		if ($changed) {
			&apache::save_directive("php_value",
						\@phpv, $vconf, $conf);
			$any++;
			}
		&flush_file_lines();
		}
	}

# Find PHP variables from template and from script
local @todo;
foreach my $pv (@tmplphpvars) {
	local ($n, $v) = split(/=/, $pv, 2);
	local $diff = $n =~ s/^(\+|\-)// ? $1 : undef;
	push(@todo, [ $n, $v, $diff ]);
	}
if ($script && defined(&{$script->{'php_vars_func'}})) {
	push(@todo, &{$script->{'php_vars_func'}}($d));
	}

# Always set the session.save_path to ~/tmp, as on some systems
# it is set by default to a directory only writable by Apache
push(@todo, [ 'session.save_path', &create_server_tmp($d) ]);

# Magic quotes directive not supported in PHP 5.4
local $realver = &get_php_version($phpver, $d);
if ($realver >= 5.4) {
	@todo = grep { $_->[0] ne "magic_quotes_gpc" } @todo;
	}

local $phpini = &get_domain_php_ini($d, $phpver);
if (-r $phpini && &foreign_check("phpini")) {
	# Add the variables to the domain's php.ini file. Start by finding
	# the variables already set, including those that are commented out.
	&foreign_require("phpini");
	local $conf = &phpini::get_config($phpini);
	local $anyini;

	# Make any needed changes. Variables can be either forced to a
	# particular value, or have maximums or minumums
	foreach my $t (@todo) {
		local ($n, $v, $diff) = @$t;
		local $ov = &phpini::find_value($n, $conf);
		local $change = $diff eq '' && $ov ne $v ||
				$diff eq '+' && &php_value_diff($ov, $v) < 0 ||
				$diff eq '-' && &php_value_diff($ov, $v) > 0;
		if ($change) {
			&phpini::save_directive($conf, $n, $v);
			if ($n eq "max_execution_time" &&
			    $config{'fcgid_max'} eq "") {
				&set_fcgid_max_execution_time($d, $v);
				}
			$any++;
			$anyini++;
			}
		}

	if ($anyini) {
		&write_as_domain_user($d, sub { &flush_file_lines($phpini) });
		local $p = &domain_has_website($d);
		if ($p ne "web") {
			&plugin_call($p, "feature_restart_web_php", $d);
			}
		}
	}

my $mode = &get_domain_php_mode($d);
if ($mode eq "fpm") {
	# Update PHP ini values in FPM config file as well
	foreach my $t (@todo) {
		local ($n, $v, $diff) = @$t;
		local $ov = &get_php_fpm_ini_value($d, $n);
		local $change = $diff eq '' && $ov ne $v ||
				$diff eq '+' && &php_value_diff($ov, $v) < 0 ||
				$diff eq '-' && &php_value_diff($ov, $v) > 0;
		if ($change) {
			&save_php_fpm_ini_value($d, $n, $v, 1);
			}
		}
	}

# Call web plugin specific variable function
if ($p && $p ne "web") {
	&plugin_call($p, "feature_setup_web_for_php", $d, $script, $phpver);
	}

return $any;
}

# php_value_diff(value1, value2)
# Compares two values like 32 and 64 or 8M and 32M. Returns -1 if v1 is < v2,
# +1 if v1 > v2, or 0 if same
sub php_value_diff
{
local ($v1, $v2) = @_;
$v1 = $v1 =~ /^(\d+)k/i ? $1*1024 :
      $v1 =~ /^(\d+)M/i ? $1*1024*1024 :
      $v1 =~ /^(\d+)G/i ? $1*1024*1024*1024 : $v1;
$v2 = $v2 =~ /^(\d+)k/i ? $1*1024 :
      $v2 =~ /^(\d+)M/i ? $1*1024*1024 :
      $v2 =~ /^(\d+)G/i ? $1*1024*1024*1024 : $v2;
return $v1 <=> $v2;
}

# check_pear_module(mod, [php-version], [&domain])
# Returns 1 if some PHP Pear module is installed, 0 if not, or -1 if pear is
# missing.
sub check_pear_module
{
local ($mod, $ver, $d) = @_;
local ($mod, $modver) = split(/\-/, $mod);
return -1 if (!&foreign_check("php-pear"));
&foreign_require("php-pear");
local @cmds = &php_pear::get_pear_commands();
return -1 if (!@cmds);
if ($ver) {
	# Check if we have Pear for this PHP version
	local ($vercmd) = grep { $_->[1] == $ver } @cmds;
	return -1 if (!$vercmd);
	}
if (!scalar(@php_pear_modules)) {
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
local @vers = &list_available_php_versions($d);
local $verinfo;
if ($ver) {
	($verinfo) = grep { $_->[0] == $ver } @vers;
	}
$verinfo ||= $vers[0];
return -1 if (!$verinfo);
local $cmd = $verinfo->[1];
&has_command($cmd) || return -1;
local @mods = &list_php_modules($d, $verinfo->[0], $verinfo->[1]);
return &indexof($mod, @mods) >= 0 ? 1 : 0;
}

# check_perl_module(mod, &domain)
# Checks if some Perl module exists
sub check_perl_module
{
local ($mod, $d) = @_;
local $perl = &get_perl_path();
local $out = &backquote_command("$perl -e 'use $mod' 2>&1");
return $? ? 0 : 1;
}

# check_python_module(mod, &domain, python-ver)
# Checks if some Python module exists
sub check_python_module
{
local ($mod, $d, $pyver) = @_;
my $python = &get_python_path($pyver);
local $out = &backquote_command("echo import ".quotemeta($mod).
				" | $python 2>&1");
return $? ? 0 : 1;
}

# setup_python_version(&domain, &script, version, path)
# Checks if a script needs a specific Python version, and if so returns it.
# Otherwise returns undef and an error message.
sub setup_python_version
{
local ($d, $script, $scriptver, $path) = @_;
my $minfunc = $script->{'python_fullver_func'};
my $maxfunc = $script->{'python_maxver_func'};
return (undef, undef) if (!defined(&$minfunc));
my $ver = &$minfunc($scriptver);
return (undef, undef) if (!$ver);
my $maxver = defined(&$maxfunc) ? &$maxfunc($scriptver) : undef;
my $basever = substr($ver, 0, 1);
my $path = get_python_path($basever);
return (undef, "Python version $ver is not available") if (!$path);
my $gotver = &get_python_version($path);
return (undef, "Could not find version of Python command $path") if (!$gotver);
&compare_versions($gotver, $ver) >= 0 ||
	return (undef, "Python version $ver is required, ".
		       "but $path is version $gotver");
if ($maxver) {
	&compare_versions($gotver, $maxver) < 0 ||
		return (undef, "Python version below $maxver is required, ".
			       "but $path is version $gotver");
	}
return ($gotver, undef);
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

# expand_php_versions(&domain, &versions)
# Given a list of versions for a domain, expands it to include 5.x versions
# if available
sub expand_php_versions
{
local ($d, $vers) = @_;
local @rv = @$vers;
if (&indexof(5, @rv) >= 0) {
	# If the script indicates that it supports PHP 5 but we have separate
	# 5.3+ versions detected, allow them too
	local @fiveplus = grep { $_ > 5 } map { $_->[0] }
			       &list_available_php_versions($d);
	push(@rv, @fiveplus);
	}
return sort { $b <=> $a } &unique(@rv);
}

# setup_php_version(&domain, &script, version, path)
# Checks if one of the given PHP versions is available for the domain.
# If not, sets up a per-directory version if possible. Returns the chosen
# version, or undef and an error message.
sub setup_php_version
{
local ($d, $script, $scriptver, $path) = @_;

# Figure out which PHP versions the script supports
my @vers;
my %vmap;
foreach my $v (&list_available_php_versions($d)) {
	my $fullv = &get_php_version($v->[0]);
	push(@vers, $fullv);
	$vmap{$fullv} = $v->[0];
	}
if (!@vers) {
	return (undef, $text{'scripts_enophpvers'});
	}
my @allvers = @vers;
my $minfunc = $script->{'php_fullver_func'};
my $maxfunc = $script->{'php_maxver_func'};
my ($minver, $maxver);
if (defined(&$minfunc)) {
	$minver = &$minfunc($d, $scriptver);
	if ($minver) {
		@vers = grep { &compare_versions($_, $minver) >= 0 } @vers;
		}
	}
if (defined(&$maxfunc)) {
	$maxver = &$maxfunc($d, $scriptver);
	if ($maxver) {
		@vers = grep { &compare_versions($_, $maxver) < 0 } @vers;
		}
	}
if (!@vers) {
	my $msg = $minver && $maxver ? 'scripts_ephpminmax' :
		  $minver ? 'scripts_ephpmin' : 'scripts_ephpmax';
	return (undef, &text($msg, join(", ", @allvers), $minver, $maxver));
	}

# Find the best matching directory with a PHP version set
local $dirpath = &public_html_dir($d);
my $candirs = &can_domain_php_directories($d);
if ($candirs && $path ne '/') {
	$dirpath .= $path;
	}
local @dirs = &list_domain_php_directories($d);
local $bestdir;
foreach my $dir (sort { length($a->{'dir'}) cmp length($b->{'dir'}) } @dirs) {
	if (&is_under_directory($dir->{'dir'}, $dirpath) ||
	    $dir->{'dir'} eq $dirpath) {
		$bestdir = $dir;
		}
	}
if (!$bestdir) {
	return (undef, &text('scripts_enophpdir', $dirpath));
	}

my $bestver = &get_php_version($bestdir->{'version'});
if (&indexof($bestdir->{'version'}, @vers) >= 0 ||
    &indexof($bestver, @vers) >= 0) {
	# The best match dir supports one of the PHP versions .. so we are OK!
	return ($bestdir->{'version'}, undef);
	}

if (!$candirs) {
	# PHP mode doesn't allow per-directory versions
	return ($bestver, undef);
	}

# Need to add a directory, or fix one. Use the lowest PHP version that
# is supported.
my ($setver) = sort { &compare_versions($a, $b) } @vers;
$setver = $vmap{$setver} || $setver;
local $err = &save_domain_php_directory($d, $dirpath, $setver);
if ($err) {
	return (undef, &text('scripts_ephpverchange', $dirpath, $vers[0]));
	}
else {
	return ($vers[0], undef);
	}
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

# setup_php_modules(&domain, &script, version, php-version, &opts, [&installed])
# If possible, downloads PHP module packages need by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
sub setup_php_modules
{
local ($d, $script, $ver, $phpver, $opts, $installed) = @_;
local $modfunc = $script->{'php_mods_func'};
local $optmodfunc = $script->{'php_opt_mods_func'};
return 1 if (!defined(&$modfunc) && !defined(&$optmodfunc));
local (@mods, @optmods);
if (defined(&$modfunc)) {
	push(@mods, &$modfunc($d, $ver, $phpver, $opts));
	}
if (defined(&$optmodfunc)) {
	@optmods = &$optmodfunc($d, $ver, $phpver, $opts);
	push(@mods, @optmods);
	}

my $installing;
foreach my $m (@mods) {
	if ($phpver >= 7 && $m eq "mysql") {
		# PHP 7 only supports mysqli, but that's OK because most scripts
		# can use it
		$m = "mysqli";
		}
	# Module name can never contain `pecl-`, unlike package name!
	my $mphp = $m;
	$mphp =~ s/^pecl-//;
	next if (&check_php_module($mphp, $phpver, $d) == 1);
	if (!$installing++) {
		&$first_print($text{'scripts_install_phpmods_check'});
		&$indent_print();
		}
	local $opt = &indexof($m, @optmods) >= 0 ? 1 : 0;
	&$first_print(&text($opt ? 'scripts_optmod' : 'scripts_needmod',
			    "<tt>$m</tt>"));

	# Find the php.ini file
	&foreign_require("phpini");
	local $mode = &get_domain_php_mode($d);
	local $inifile = $mode eq "mod_php" || $mode eq "fpm" ?
			&get_global_php_ini($phpver, $mode) :
			&get_domain_php_ini($d, $phpver);
	if (!$inifile) {
		# Could not find php.ini
		&$second_print($mode eq "mod_php" || $mode eq "fpm" ?
			$text{'scripts_noini'} : $text{'scripts_noini2'});
		if ($opt) { next; }
		else { return 0; }
		}

	# Make sure the software module is installed and can do updates
	if (!&foreign_installed("software")) {
		&$second_print($text{'scripts_esoftware'});
		if ($opt) { next; }
		else { return 0; }
		}
	&foreign_require("software");
	if (!defined(&software::update_system_install)) {
		&$second_print($text{'scripts_eupdate'});
		if ($opt) { next; }
		else { return 0; }
		}

	# Check if the package is already installed
	local $iok = 0;
	local @poss;
	local @allphps = map{ $_->[0] } list_available_php_versions($d);
	local $phpvercurr = $phpver;
	local $nodotphpvercurr = $phpvercurr;
	$nodotphpvercurr =~ s/\.//;
	foreach my $phpverall (@allphps) {
		my $fullphpver = &get_php_version($phpverall, $d);
		my $nodotphpver = $phpverall;
		$nodotphpver =~ s/\.//;
		my $phpverdistrobased = $software::update_system eq "apt" ? $phpverall : $nodotphpver;
		if ($software::update_system eq "csw") {
			# On Solaris, packages are named like php52_mysql
			push(@poss, "php".$nodotphpver."_".$m);
			}
		elsif ($software::update_system eq "ports") {
			# On FreeBSD, names are like php52-mysql
			push(@poss, "php".$nodotphpver."-".$m);
			}
		else {
			push(@poss, "php".$phpverdistrobased."-".$m, "php-".$m);
			if ($software::update_system eq "apt" &&
				$m eq "pdo_mysql") {
				# On Debian, the pdo_mysql module is in the mysql module
				push(@poss, "php".$phpverdistrobased."-mysql", "php-mysql");
				}
			elsif ($software::update_system eq "yum" &&
				   ($m eq "domxml" || $m eq "dom") && $phpverall >= 5) {
				# On Redhat, the domxml module is in php-domxml
				push(@poss, "php".$nodotphpver."-xml", "php-xml");
				}
			if ($phpverall =~ /\./ && $software::update_system eq "yum") {
				# PHP 5.3+ packages from software collections are
				# named like php54-php-mysql or sometimes even
				# php54-php-mysqlnd
				unshift(@poss, "php".$nodotphpver."-php-".$m);
				unshift(@poss, "rh-php".$nodotphpver."-php-".$m);
				if ($m eq "mysql") {
					unshift(@poss, "rh-php".$nodotphpver.
							   "-php-mysqlnd");
					}
				}
			elsif ($software::update_system eq "yum" &&
				   $fullphpver =~ /^5\.3/) {
				# If PHP 5.3 is being used, packages may start with
				# php53- or rh-php53-
				my @vposs = grep { /^php5-/ } @poss;
				push(@poss, map { my $p = $_;
							 $p =~ s/php5/php53/;
						  ($p, "rh-".$p) } @vposs);
				}
			}
		}
	@poss = sort { $a cmp $b } &unique(@poss);
	my @newpkgs;
	# &$first_print($text{'scripts_phpmodinst'});
	foreach my $pkg (@poss) {
		my @pinfo = &software::package_info($pkg);
		my $nodotverpkg = $pkg;
		$nodotverpkg =~ s/\.//;
		
		if (!@pinfo) {
			# Not installed .. try to fetch it
			my ($out, $rs) = &capture_function_output(
				\&software::update_system_install, $pkg);
			$iok = 1 if (scalar(@$rs));
			local $newpkg = $pkg;
			if ($software::update_system eq "csw") {
				# Real package name is different
				$newpkg = "CSWphp".$phpver.$m;
				}
			local @pinfo2 = &software::package_info($newpkg);
			if (@pinfo2 && $pinfo2[0] eq $newpkg) {
				# Yep, it worked
				$iok = 1;
				push(@newpkgs, $m);
				}
			}
		else {
			# Already installed .. we're done
			$iok = 1;
			}
		}
	push(@$installed, @newpkgs) if ($installed);
	if (!$iok) {
		&$second_print(&text('scripts_phpmodfailed', scalar(@poss)));
		if ($opt) { next; }
		else { return 0; }
		}

	# Finally re-check to make sure it worked
	undef(%main::php_modules);
	if (&check_php_module($mphp, $phpver, $d) != 1) {
		&$second_print($text{'scripts_einstallmod'});
		if ($opt) { next; }
		else { return 0; }
		}
	else {

		# On success configure the domain's php.ini to load it, if needed
		local $pconf = &phpini::get_config($inifile);
		local @allexts = grep { $_->{'name'} eq 'extension' } @$pconf;
		local @exts = grep { $_->{'enabled'} } @allexts;
		local ($got) = grep { $_->{'value'} eq "${mphp}.so" ||
		                      $_->{'value'} eq $mphp } @exts;
		if (!$got && &check_php_module($mphp, $phpver, $d) != 1) {
			# Needs to be enabled
			local $lref = &read_file_lines($inifile);
			if (@exts) {
				# After current extensions
				splice(@$lref, $exts[$#exts]->{'line'}+1, 0,
				       "extension=${mphp}.so");
				}
			elsif (@allexts) {
				# After commented out extensions
				splice(@$lref, $allexts[$#allexts]->{'line'}+1, 0,
				       "extension=${mphp}.so");
				}
			else {
				# At end of file (should never happen, but..)
				push(@$lref, "extension=${mphp}.so");
				}
			if ($mode eq "mod_php" || $mode eq "fpm") {
				&flush_file_lines($inifile);
				}
			else {
				&write_as_domain_user($d,
					sub { &flush_file_lines($inifile) });
				}
			undef($phpini::get_config_cache{$inifile});
			undef(%main::php_modules);
			}

		&$second_print(&text('setup_done', $m));
		}

	# If we are running via mod_php or fcgid, an Apache reload is needed
	if ($mode eq "mod_php" || $mode eq "fcgid") {
		local $p = &domain_has_website($d);
		if ($p eq "web") {
			&register_post_action(\&restart_apache);
			}
		elsif ($p) {
			&plugin_call($p, "feature_restart_web_php", $d);
			}
		}

	# In FPM mode, a pool server reload is needed
	if ($mode eq "fpm") {
		&register_post_action(\&restart_php_fpm_server);
		}
	}
if ($installing) {
	&$outdent_print();
	&$second_print($text{'scripts_install_phpmods_check_done'});
	}
return 1;
}

# setup_pear_modules(&domain, &script, version, php-version, &opts)
# If possible, downloads Pear PHP modules needed by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
sub setup_pear_modules
{
local ($d, $script, $ver, $phpver) = @_;
local $modfunc = $script->{'pear_mods_func'};
return 1 if (!defined(&$modfunc));
local @mods = &$modfunc($d, $opts);
return 1 if (!@mods);

# Make sure we have the pear module
if (!&foreign_check("php-pear")) {
	# Cannot do anything
	&$first_print(&text('scripts_nopearmod',
			    "<tt>".join(" ", @mods)."</tt>"));
	return 1;
	}

# And that we have Pear for this PHP version
&foreign_require("php-pear");
local @cmds = &php_pear::get_pear_commands();
local ($vercmd) = grep { $_->[1] == $phpver } @cmds;
if (!$vercmd) {
	# No pear .. cannot do anything
	&$first_print(&text('scripts_nopearcmd',
			    "<tt>".join(" ", @mods)."</tt>", $phpver));
	return 1;
	}

foreach my $m (@mods) {
	next if (&check_pear_module($m, $phpver, $d) == 1);
	local ($mname, $mver) = split(/\-/, $m);

	# Install if needed
	&$first_print(&text('scripts_needpear', "<tt>$mname</tt>"));
	&foreign_require("php-pear");
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

# setup_perl_modules(&domain, &script, version, &opts)
# If possible, downloads Perl needed by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
# At the moment, auto-install of modules is done only from APT or YUM.
sub setup_perl_modules
{
local ($d, $script, $ver, $opts) = @_;
local $modfunc = $script->{'perl_mods_func'};
local $optmodfunc = $script->{'perl_opt_mods_func'};
return 1 if (!defined(&$modfunc) && !defined(&$optmodfunc));
if (defined(&$modfunc)) {
	push(@mods, &$modfunc($d, $ver, $opts));
	}
if (defined(&$optmodfunc)) {
	@optmods = &$optmodfunc($d, $ver, $opts);
	push(@mods, @optmods);
	}

# Check if the software module is installed and can do update
local $canpkgs = 0;
if (&foreign_installed("software")) {
	&foreign_require("software");
	if (defined(&software::update_system_install)) {
		$canpkgs = 1;
		}
	}

foreach my $m (@mods) {
	next if (&check_perl_module($m, $d) == 1);
	local $opt = &indexof($m, @optmods) >= 0 ? 1 : 0;
	&$first_print(&text($opt ? 'scripts_optperlmod' : 'scripts_needperlmod',
			    "<tt>$m</tt>"));

	local $pkg;
	local $done = 0;
	if ($canpkgs) {
		# Work out the package name
		local $mp = $m;
		if ($software::config{'package_system'} eq 'rpm') {
			# We can use RPM's tracking of perl dependencies
			# to install the exact module.
			# However, to make it work, we need to wrap pkg name in quotes,
			# like dnf install 'perl(Email::Send)' which doesn't 	
			# seem to be working correctly on underlying API.	
			# Simply build a name for it on RHEL too	
			$mp =~ s/::/\-/g;	
			$pkg = "perl-$mp";
			}
		elsif ($software::config{'package_system'} eq 'debian') {
			# Most Debian package perl modules are named
			# like libfoo-bar-perl
			if ($mp eq "Date::Format") {
				$pkg = "libtimedate-perl";
				}
			elsif ($mp eq "Template::Toolkit") {	
				$pkg = "libtemplate-perl";	
				}	
			elsif ($mp eq "DBD::SQLite") {	
				$pkg = "libdbd-sqlite3-perl";	
				}
			else {
				$mp = lc($mp);
				$mp =~ s/::/\-/g;
				$pkg = "lib$mp-perl";
				}
			}
		elsif ($software::config{'package_system'} eq 'pkgadd') {
			$mp = lc($mp);
			$mp =~ s/:://g;
			$pkg = "pm_$mp";
			}
		}

	if ($pkg) {
		# Install the RPM, Debian or CSW package
		&$first_print(&text('scripts_softwaremod', "<tt>$pkg</tt>"));
		&$indent_print();
		&software::update_system_install($pkg);
		&$outdent_print();
		@pinfo = &software::package_info($pkg);
		if (@pinfo && $pinfo[0] eq $pkg) {
			# Yep, it worked
			&$second_print($text{'setup_done'});
			$done = 1;
			}
		}

	if (!$done) {
		# Fall back to CPAN
		&$first_print(&text('scripts_perlmod', "<tt>$m</tt>"));
		eval "use CPAN";
		if ($@) {
			# Cpan is missing??
			&$second_print($text{'scripts_ecpan'});
			if ($opt) { next; }
			else { return 0; }
			}
		else {
			local $perl = &get_perl_path();
			&open_execute_command(CPAN,
			    "echo n | $perl -MCPAN -e 'install $m' 2>&1", 1);
			&$indent_print();
			print "<pre>";
			while(<CPAN>) {
				print &html_escape($_);
				}
			print "</pre>";
			close(CPAN);
			&$outdent_print();
			if ($?) {
				&$second_print($text{'scripts_eperlmod'});
				if ($opt) { next; }
				else { return 0; }
				}
			else {
				&$second_print($text{'setup_done'});
				}
			}
		}
	}
return 1;
}

# setup_python_modules(&domain, &script, version, &opts)
# If possible, downloads Python needed by the given script. Progress
# of the install is written to STDOUT. Returns 1 if successful, 0 if not.
# At the moment, auto-install of modules is done only from APT or YUM.
sub setup_python_modules
{
local ($d, $script, $ver, $opts) = @_;
local $modfunc = $script->{'python_mods_func'};
local $optmodfunc = $script->{'python_opt_mods_func'};
local (@mods, @optmods);
if (defined(&$modfunc)) {
	push(@mods, &$modfunc($d, $ver, $opts));
	}
if (defined(&$optmodfunc)) {
	push(@optmods, &$optmodfunc($d, $ver, $opts));
	push(@mods, @optmods);
	}
return 1 if (!@mods);

# Check if the software module is installed and can do update
local $canpkgs = 0;
if (&foreign_installed("software")) {
	&foreign_require("software");
	if (defined(&software::update_system_install)) {
		$canpkgs = 1;
		}
	}
my $python = &get_python_path($opts->{'pyver'});
my $pyver = &get_python_version($python);
foreach my $m (@mods) {
	next if (&check_python_module($m, $d, $pyver) == 1);
	local $opt = &indexof($m, @optmods) >= 0 ? 1 : 0;
	&$first_print(&text($opt ? 'scripts_optpythonmod'
				 : 'scripts_needpythonmod', "<tt>$m</tt>"));
	if (!$canpkgs) {
		&$second_print($text{'scripts_epythonmod'});
		if ($opt) { next; }
		else { return 0; }
		}

	# Work out the package name
	local @pkgs;
	local $done = 0;
	local $mp = $m;
	if ($software::config{'package_system'} eq 'debian') {
		# For APT, the package name is python- followed
		# by the lower-case module name, except for the svn module
		# which is in python-subversion
		$mp = lc($mp);
		if ($mp eq "svn") {
			push(@pkgs, "python-subversion");
			}
		elsif ($mp eq "psycopg2") {
			push(@pkgs, $pyver >= 3 ? "python3-psycopg2" :
				         	  "python-psycopg2");
			}
		elsif ($m eq "MySQLdb" && $pyver >= 3) {
			push(@pkgs, "python3-mysqldb");
			}
		else {
			my $python_package = $pyver >= 3 ? "python3" : "python";
			push(@pkgs, "$python_package-$mp");
			}
		}
	elsif ($software::config{'package_system'} eq 'rpm') {
		# For YUM, naming is less standard .. the MySQLdb package
		# is in MySQL-python
		if ($m eq "MySQLdb") {
			# XXX
			if ($pyver =~ /^3\.(\d)/) {
				push(@pkgs, "python3-mysqlclient",
					    "python3-mysql",
					    "python3$1-mysql");
				}
			else {
				push(@pkgs, "python-mysqlclient",
					    "python-mysql");
				}
			}
		elsif ($m eq "setuptools") {
			push(@pkgs, "setuptools", "python-setuptools");
			}
		elsif ($mp eq "psycopg2") {
			# Try to install old and new versions
			if ($pyver =~ /^3\.(\d)/) {
				push(@pkgs, "python3-psycopg2");
				push(@pkgs, "python3$1-psycopg2");
				push(@pkgs, "python3$1-pg8000");
				}
			else {
				push(@pkgs, "python-psycopg2");
				}
			}
		elsif ($m eq "svn") {
			push(@pkgs, "subversion-python");
			}
		else {
			$mp = lc($mp);
			if ($pyver =~ /^3\.(\d)/) {
				push(@pkgs, "python3-$mp");
				push(@pkgs, "python3$1-$mp");
				}
			else {
				push(@pkgs, "python-$mp");
				}
			}
		}
	elsif ($software::config{'package_system'} eq 'pkgadd') {
		# For CSW, the package is py_ and the module name. Very few
		# seem to be packaged though
		$mp = lc($mp);
		$mp =~ s/:://g;
		push(@pkgs, "py_$mp");
		}
	else {
		&$second_print($text{'scripts_epythonmod'});
		if ($opt) { next; }
		else { return 0; }
		}

	# Install the RPM, Debian or CSW package. If any work, then we are done
	local $anyok;
	foreach my $pkg (@pkgs) {
		&$first_print(&text('scripts_softwaremod', "<tt>$pkg</tt>"));
		&$indent_print();
		&software::update_system_install($pkg);
		&$outdent_print();
		local @pinfo = &software::package_info($pkg);
		if (@pinfo && $pinfo[0] eq $pkg) {
			# Yep, it worked
			&$second_print($text{'setup_done'});
			$anyok = 1;
			last;
			}
		else {
			&$second_print($text{'scripts_epythoninst'});
			}
		}
	return 0 if (!$anyok && !$opt);
	}
return 1;
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
local $pp = $opts->{'path'} eq '/' ? '' : $opts->{'path'};
if ($pp !~ /\.(cgi|pl|php)$/i) {
	$pp .= "/";
	}
return &get_domain_url($d, 1).$pp;
}

# show_template_scripts(&tmpl)
# Outputs HTML for editing script installer template options
sub show_template_scripts
{
local ($tmpl) = @_;
local $scripts = &list_template_scripts($tmpl);
local $empty = { 'db' => '${DB}' };
local @list = $scripts eq "none" ? ( $empty ) : ( @$scripts, $empty );

# Build field list and disablers
local @sfields = map { ("name_".$_, "path_".$_,
			"version_".$_, "version_".$_."_def",
			"db_def_".$_, "db_".$_, "dbtype_".$_) }
		     (0..scalar(@list)-1);
local $dis1 = &js_disable_inputs(\@sfields, [ ]);
local $dis2 = &js_disable_inputs([ ], \@sfields);

# None/default/listed selector
local $stable = $text{'tscripts_what'}."\n";
$stable .= &ui_radio("def",
	$scripts eq "none" ? 2 :
	  @$scripts ? 0 :
	  $tmpl->{'default'} ? 2 : 1,
	[ [ 2, $text{'tscripts_none'}, "onClick='$dis1'" ],
	  $tmpl->{'default'} ? ( ) : ( [ 1, $text{'default'}, "onClick='$dis1'" ] ),
	  [ 0, $text{'tscripts_below'}, "onClick='$dis2'" ] ]),"<p>\n";

# Find scripts
local @opts = ( );
foreach $sname (&list_available_scripts()) {
	$script = &get_script($sname);
	push(@opts, [ $sname, $script->{'desc'} ]);
	}
@opts = sort { lc($a->[1]) cmp lc($b->[1]) } @opts;
local @dbopts = ( );
push(@dbopts, [ "mysql", $text{'databases_mysql'} ]) if ($config{'mysql'});
push(@dbopts, [ "postgres", $text{'databases_postgres'} ]) if ($config{'postgres'});

# Show table of scripts
local $i = 0;
local @table;
foreach $script (@list) {
	$db_def = $script->{'db'} eq '${DB}' ? 1 :
                        $script->{'db'} ? 2 : 0;
	local ($name, $ver) = split(/\s+/, $script->{'name'});
	push(@table, [
		&ui_select("name_$i", $name,
			   [ [ undef, "&nbsp;" ], @opts ]),
		&ui_opt_textbox("version_$i", $ver eq "latest" ? undef : $ver,
				10, $text{'tscripts_latest'}."<br>",
				$text{'tscripts_exact'}),
		&ui_textbox("path_$i", $script->{'path'}, 25),
		&ui_radio("db_def_$i",
			$db_def,
			[ [ 0, $text{'tscripts_none'} ],
			  [ 1, $text{'tscripts_dbdef'}."<br>" ],
			  [ 2, $text{'tscripts_other'}." ".
			       &ui_textbox("db_$i",
				$db_def == 1 ? "" : $script->{'db'}, 10) ] ]),
		&ui_select("dbtype_$i", $script->{'dbtype'}, \@dbopts),
		]);
	$i++;
	}
$stable .= &ui_columns_table(
	[ $text{'tscripts_name'}, $text{'tscripts_version'},
	  $text{'tscripts_path'}, $text{'tscripts_db'},
	  $text{'tscripts_dbtype'} ],
	undef,
	\@table,
	undef,
	0,
	undef,
	undef,
	);
$stable = "<div data-table-name='template-script'>$stable</div>";
print &ui_table_row(undef, $stable, 2);
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
		local $ver = $in{"version_${i}_def"} ? "latest"
						     : $in{"version_${i}"};
		$ver =~ /^\S+$/ || &error(&text('tscripts_eversion', $i+1));
		local $script = { 'id' => $i,
			    	  'name' => $name." ".$ver };
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
local $subdir;
if ($project =~ /^([^\/]+)(\/\S+)$/) {
	$project = $1;
	$subdir = $2;
	}
local ($alldata, $err);
&http_download($osdn_website_host, $osdn_website_port,
	       "/projects/$project/files".$subdir,
	       \$alldata, \$err, undef, 0, undef, undef, undef, 0, 1);
return ( ) if ($err);

# Search for sub-directories
local @data = ( $alldata );
local $data = $alldata;
local %donepath;
while($data =~ /href="(\/projects\/$project\/files\Q$subdir\E\/[^: ]+)"(.*)/is) {
	$data = $2;
	local $spath = $1;
	next if ($donepath{$spath}++ || $spath =~ /\/stats\/timeline/ ||
		 $spath =~ /\.\.$/ || $spath =~ /\/download$/);
	local ($sdata, $err);
	&http_download($osdn_website_host, $osdn_website_port, $spath,
		       \$sdata, \$err, undef, 0, undef, undef, undef, 0, 1);
	push(@data, $sdata) if (!$err);
	$data .= $sdata;
	}

# Check them all for files
local @vers;
foreach my $alldata (@data) {
	foreach my $re (@res) {
		local $data = $alldata;
		while($data =~ /$re(.*)/is) {
			push(@vers, $1);
			$data = $2;
			}
		}
	}
@vers = sort { &compare_versions($b, $a) } &unique(@vers);
return @vers;
}

# can_script_version(&script, version-number)
# Returns 1 if the current user can install some version of a script
sub can_script_version
{
local ($script, $ver) = @_;
local ($allowmaster, $allowvers) = &get_script_master_permissions();
if (&master_admin() && $allowvers) {
	# No limits for master admin
	return 1;
	}
elsif (!$script->{'minversion'}) {
	return 1;	# No restrictions
	}
elsif ($script->{'minversion'} =~ /^<=(.*)$/) {
	return &compare_versions($ver, "$1", $script) <= 0;	# At or below
	}
elsif ($script->{'minversion'} =~ /^=(.*)$/) {
	return $ver eq $1;				# At exact version
	}
elsif ($script->{'minversion'} =~ /^>=(.*)$/ ||
       $script->{'minversion'} =~ /^(.*)$/) {
	return &compare_versions($ver, "$1", $script) >= 0;	# At or above
	}
else {
	return 1;	# Can never happen!
	}
}

# post_http_connection(&domain, page, &cgi-params, &out, &err,
#		       &moreheaders, &returnheaders, &returnheaders-array,
#		       form-data-mode, [timeout])
# Makes an HTTP post to some URL, sending the given CGI parameters as data.
sub post_http_connection
{
local ($d, $page, $params, $out, $err, $headers,
       $returnheaders, $returnheaders_array, $formdata, $timeout) = @_;
local $ip = $d->{'ip'};
local $host = &get_domain_http_hostname($d);
my $usessl = &domain_has_ssl($d);
my $port = $usessl ? $d->{'web_sslport'} : $d->{'web_port'};

local $oldproxy = $gconfig{'http_proxy'};	# Proxies mess up connection
$gconfig{'http_proxy'} = '';			# to the IP explicitly
$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm($timeout || 300);
local $h = &make_http_connection($ip, $port, $usessl, "POST", $page,
			 undef, undef, { 'host' => $host, 'nocheckhost' => 1 });
$gconfig{'http_proxy'} = $oldproxy;
if (!ref($h)) {
	$$err = $h;
	return 0;
	}
&write_http_connection($h, "Host: $host\r\n");
&write_http_connection($h, "User-agent: Webmin\r\n");
my $gotcookie = 0;
if ($headers) {
	foreach my $hd (keys %$headers) {
		&write_http_connection($h, "$hd: $headers->{$hd}\r\n");
		$gotcookie++ if (lc($hd) eq 'cookie');
		}
	}
if (!$gotcookie) {
	foreach my $hd (&http_connection_cookies($d)) {
		&write_http_connection($h, "$hd->[0]: $hd->[1]\r\n");
		}
	}
if ($formdata) {
	# Use multipart format, suiteable for file uploads
	my $bound = time().$$;
	&write_http_connection($h, "Content-type: multipart/form-data; boundary=----${bound}\r\n");
	&write_http_connection($h, "\r\n");
	foreach my $i (split(/\&/, $params)) {
		my ($k, $v) = split(/=/, $i, 2);
		$k =~ tr/\+/ /;
		$v =~ tr/\+/ /;
		$k =~ s/%(..)/pack("c",hex($1))/ge;
		$v =~ s/%(..)/pack("c",hex($1))/ge;
		&write_http_connection($h, "------${bound}\r\n");
		&write_http_connection($h, "Content-Disposition: form-data; name=\"$k\"\r\n");
		&write_http_connection($h, "\r\n");
		&write_http_connection($h, "$v\r\n");
		}
	&write_http_connection($h, "------${bound}--\r\n");
	}
else {
	# Use regular POST format
	&write_http_connection($h, "Content-type: application/x-www-form-urlencoded\r\n");
	&write_http_connection($h, "Content-length: ".length($params)."\r\n");
	&write_http_connection($h, "\r\n");
	&write_http_connection($h, "$params\r\n");
	}

alarm(0);
$h = $main::download_timed_out if ($main::download_timed_out);
if (!ref($h)) {
	if ($err) { $$err = $h; return; }
	else { &error($h); }
	}

# Read back the results
$post_http_headers = undef;
$post_http_headers_array = undef;
&complete_http_connection($d, $h, $out, $err, \&capture_http_headers, 0,
			  $host, $port, $page, $headers);
if ($returnheaders && $post_http_headers) {
	%$returnheaders = %$post_http_headers;
	}
if ($returnheaders_array && $post_http_headers_array) {
	@$returnheaders_array = @$post_http_headers_array;
	}
}

sub capture_http_headers
{
if ($_[0] == 4) {
	$post_http_headers = %WebminCore::header ?
				\%WebminCore::header : \%header;
	$post_http_headers_array = scalar(@WebminCore::header) ?
				\@WebminCore::header : \@headers;
	}
}

# get_http_connection(&domain, page, &output, [&error], [&callback],
#  [sslmode], [user, pass], [timeout], [osdn-convert], [no-cache], [&headers])
# Does effectively the same thing as http_download, but connects to the right
# IP, hostname and port. For use by scripts needing to call wizards and such.
sub get_http_connection
{
local ($d, $page, $dest, $error, $cbfunc, $ssl, $user, $pass,
       $timeout, $osdn, $nocache, $headers) = @_;
local $ip = $d->{'ip'};
local $host = &get_domain_http_hostname($d);
my $usessl = &domain_has_ssl($d);
my $port = $usessl ? $d->{'web_sslport'} : $d->{'web_port'}  || 80;
$ssl = $usessl;

# Build headers
local @headers;
push(@headers, [ "Host", $host ]);
push(@headers, [ "User-agent", "Webmin" ]);
if ($user) {
	local $auth = &encode_base64("$user:$pass");
	$auth =~ tr/\r\n//d;
	push(@headers, [ "Authorization", "Basic $auth" ]);
	}
my $gotcookie = 0;
foreach my $hname (keys %$headers) {
	push(@headers, [ $hname, $headers->{$hname} ]);
	$gotcookie++ if (lc($hname) eq 'cookie');
	}
if (!$gotcookie) {
	push(@headers, &http_connection_cookies($d));
	}

# Actually download it
$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm($timeout || 60);
local $h = &make_http_connection($ip, $port, $ssl, "GET", $page, \@headers,
			 undef, { 'host' => $host, 'nocheckhost' => 1 });
alarm(0);
$h = $main::download_timed_out if ($main::download_timed_out);
if (!ref($h)) {
	if ($error) { $$error = $h; return; }
	else { &error($h); }
	}
&complete_http_connection($d, $h, $dest, $error, $cbfunc, $osdn, $host, $port,
			  $page, $headers);
}

# complete_http_connection(&domain, &handle, dest, &error, &callback, osdn,
# 			   [host], [port], [page], &headers)
# Once an HTTP connection is active, complete the download
sub complete_http_connection
{
local ($d, $h, $dest, $error, $cbfunc, $osdn, $oldhost,
       $oldport, $oldpage, $headers) = @_;

# Kept local so that callback funcs can access them.
local (%WebminCore::header, @WebminCore::headers);

# read headers
alarm(60);
my $line;
($line = &read_http_connection($h)) =~ tr/\r\n//d;
if ($line !~ /^HTTP\/1\..\s+(200|30[0-9])(\s+|$)/) {
	alarm(0);
	if ($error) { $$error = $line; return; }
	else { &error("Download failed : $line"); }
	}
my $rcode = $1;
&$cbfunc(1, $rcode >= 300 && $rcode < 400 ? 1 : 0)
	if ($cbfunc);
while(1) {
	$line = &read_http_connection($h);
	$line =~ tr/\r\n//d;
	$line =~ /^(\S+):\s+(.*)$/ || last;
	$WebminCore::header{lc($1)} = $2;
	push(@WebminCore::headers, [ lc($1), $2 ]);
	}

# Parse out cookies set in the response
foreach my $h (grep { $_->[0] eq 'set-cookie' } @WebminCore::headers) {
	my @w = split(/;\s*/, $h->[1]);
	if (@w && $w[0] =~ /^\S+=/) {
		my ($cn, $cv) = split(/=/, $w[0], 2);
		$http_connection_cookies{$d->{'id'}} ||= [ ];
		push(@{$http_connection_cookies{$d->{'id'}}}, [ $cn, $cv ]);
		}
	}

# Complete the download, and possibly follow a redirect
alarm(0);
if ($main::download_timed_out) {
	if ($error) { $$error = $main::download_timed_out; return 0; }
	else { &error($main::download_timed_out); }
	}
&$cbfunc(2, $WebminCore::header{'content-length'}) if ($cbfunc);
if ($rcode >= 300 && $rcode < 400) {
	# follow the redirect
	&$cbfunc(5, $WebminCore::header{'location'}) if ($cbfunc);
	my ($host, $port, $page, $ssl);
	if ($WebminCore::header{'location'} =~ /^(http|https):\/\/([^:]+):(\d+)(\/.*)?$/) {
		$ssl = $1 eq 'https' ? 1 : 0;
		$host = $2;
		$port = $3;
		$page = $4 || "/";
		}
	elsif ($WebminCore::header{'location'} =~ /^(http|https):\/\/([^:\/]+)(\/.*)?$/) {
		$ssl = $1 eq 'https' ? 1 : 0;
		$host = $2;
		$port = $ssl ? 443 : 80;
		$page = $3 || "/";
		}
	elsif ($WebminCore::header{'location'} =~ /^\// && $oldhost) {
		# Relative to same server
		$host = $oldhost;
		$port = $oldport;
		$ssl = 0;	# ???
		$page = $WebminCore::header{'location'};
		}
	elsif ($WebminCore::header{'location'} && $oldhost && $oldpage) {
		# Assume relative to same dir
		$host = $oldhost;
		$port = $oldport;
		$page = $oldpage;
		$page =~ s/\/[^\/]+$/\//;
		$page .= $WebminCore::header{'location'};
		}
	else {
		if ($error) { $$error = "Missing Location header"; return; }
		else { &error("Missing Location header"); }
		}
	my $params;
	($page, $params) = split(/\?/, $page);
	$page =~ s/ /%20/g;
	$page .= "?".$params if (defined($params));

	# Download from the new URL
	if ($host eq &get_domain_http_hostname($d) &&
	    $port eq ($d->{'web_sslport'} || $d->{'web_port'} || 80)) {
		# Same domain, so use Virtualmin's function
		&get_http_connection($d, $page, $dest, $error, $cbfunc, $ssl,
				     undef, undef, 0, $osdn, 0, $headers);
		}
	else {
		# Redirect elsewhere
		&http_download($host, $port, $page, $dest, $error, $cbfunc,
			       $ssl, undef, undef, undef, $osdn, 0, $headers);
		}
	}
else {
	# read data
	if (ref($dest)) {
		# Append to a variable
		while(defined($buf = &read_http_connection($h, 1024))) {
			$$dest .= $buf;
			&$cbfunc(3, length($$dest)) if ($cbfunc);
			}
		}
	else {
		# Write to a file
		my $got = 0;
		if (!&open_tempfile(PFILE, ">$dest", 1)) {
			if ($error) { $$error = "Failed to write to $dest : $!"; return; }
			else { &error("Failed to write to $dest : $!"); }
			}
		binmode(PFILE);		# For windows
		while(defined($buf = &read_http_connection($h, 1024))) {
			&print_tempfile(PFILE, $buf);
			$got += length($buf);
			&$cbfunc(3, $got) if ($cbfunc);
			}
		&close_tempfile(PFILE);
		if ($WebminCore::header{'content-length'} &&
		    $got != $WebminCore::header{'content-length'}) {
			if ($error) { $$error = "Download incomplete"; return; }
			else { &error("Download incomplete"); }
			}
		}
	&$cbfunc(4) if ($cbfunc);
	}
&close_http_connection($h);
}

# http_connection_cookies(&domain)
# Returns a list of array refs of Cookie headers saved from past requests
sub http_connection_cookies
{
my ($d) = @_;
my @rv;
if ($http_connection_cookies{$d->{'id'}}) {
	foreach my $c (@{$http_connection_cookies{$d->{'id'}}}) {
		push(@rv, [ 'Cookie', $c->[0]."=".$c->[1] ]);
		}
	}
return @rv;
}

# make_file_php_writable(&domain, file, [dir-only], [owner-too])
# Set permissions on a file so that it is writable by PHP
sub make_file_php_writable
{
local ($d, $file, $dironly, $setowner) = @_;
local $mode = &get_domain_php_mode($d);
local $perms = $mode eq "mod_php" ? 0777 : 0755;
local @st = stat($file);
if (-d $file && !$dironly) {
	if ($setowner && $st[4] != $d->{'uid'}) {
		&system_logged(sprintf("chown -R %d:%d %s",
			$d->{'uid'}, $d->{'gid'}, quotemeta($file)));
		}
	&run_as_domain_user(
		$d, sprintf("chmod -R %o %s", $perms, quotemeta($file)));
	}
else {
	if ($setowner && $st[4] != $d->{'uid'}) {
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
					   undef, $file);
		}
	&set_permissions_as_domain_user($d, $perms, $file);
	}
}

# make_file_php_nonwritable(&domain, file, [dir-only])
sub make_file_php_nonwritable
{
local ($d, $file, $dironly) = @_;
if (-d $file && !$dironly) {
	&execute_as_domain_user($d, "chmod -R 555 ".quotemeta($file));
	}
else {
	&set_permissions_as_domain_user($d, 0555, $file);
	}
}

# delete_script_install_directory(&domain, &opts)
# Delete all files installed by a script, based on the 'dir' option. Returns
# an error message on failure.
sub delete_script_install_directory
{
local ($d, $opts) = @_;
$opts->{'dir'} || return "Missing install directory!";
&is_under_directory($d->{'home'}, $opts->{'dir'}) ||
	return "Invalid install directory $opts->{'dir'}";

# Check for overlapping script dirs
local @others = &list_domain_scripts($d);
local %overlap;
foreach my $sinfo (@others) {
	if ($sinfo->{'opts'}->{'dir'} =~ /^\Q$opts->{'dir'}\E\/(\S+)$/) {
		$overlap{$1} = 1;
		}
	}

# Add sub-dirs used by plugins
if ($opts->{'dir'} eq &public_html_dir($d)) {
	if ($d->{'virtualmin-git'}) {
		$overlap{'git'} = 1;
		}
	}

if (!scalar(keys %overlap)) {
	# Delete all sub-directories
	local $out = &backquote_logged(
		"rm -rf ".quotemeta($opts->{'dir'})."/* ".
			  quotemeta($opts->{'dir'})."/.??* 2>&1");
	$? && return "Failed to delete files : <tt>$out</tt>";

	if ($opts->{'dir'} ne &public_html_dir($d, 0)) {
		# Take out the directory too
		&run_as_domain_user($d, "rmdir ".quotemeta($opts->{'dir'}));
		}
	}
else {
	# Only delete those not belonging to other scripts
	opendir(DIR, $opts->{'dir'});
	foreach my $f (readdir(DIR)) {
		if ($f ne '.' && $f ne '..' && !$overlap{$f}) {
			&unlink_file_as_domain_user($d, "$opts->{'dir'}/$f");
			}
		}
	closedir(DIR);
	}
return undef;
}

# check_script_db_connection([&domain], dbtype, dbname, dbuser, dbpass)
# Returns an error message if connection to the database with the given details
# would fail, undef otherwise
sub check_script_db_connection
{
my $myd = ref($_[0]) ? shift(@_) : $d;
my ($dbtype, $dbname, $dbuser, $dbpass) = @_;
if (&indexof($dbtype, @database_features) >= 0) {
	# Core feature
	local $cfunc = "check_".$dbtype."_login";
	if (defined(&$cfunc)) {
		return &$cfunc($d, $dbname, $dbuser, $dbpass);
		}
	}
elsif (&indexof($dbtype, &list_database_plugins()) >= 0) {
	# Plugin database
	return &plugin_call($dbtype, "feature_database_check_login",
			    $dbname, $dbuser, $dbpass);
	}
return undef;
}

# setup_ruby_modules(&domain, &script, version, &opts)
# Attempt to install any support programs needed by this script for Ruby.
# At the moment, all it does is try to install 'gem'
sub setup_ruby_modules
{
local ($d, $script, $ver, $opts) = @_;

if (!&has_command("gem") &&
    &indexof("ruby", @{$script->{'uses'}}) >= 0) {
	# Try to install gem from YUM or APT
	&$first_print($text{'scripts_installgem'});

	# Make sure the software module is installed and can do updates
	if (!&foreign_installed("software")) {
		&$second_print($text{'scripts_esoftware'});
		return 0;
		}
	&foreign_require("software");
	if (!defined(&software::update_system_install)) {
		&$second_print($text{'scripts_eupdate'});
		return 0;
		}

	# Try to install it. We assume that the package is always called
	# 'rubygems' on all update systems.
	&software::update_system_install("rubygems");
	delete($main::has_command_cache{'gem'});
	local $newpkg = $software::update_system eq "csw" ? "CSWrubygems"
							  : "rubygems";
	local @pinfo = &software::package_info($newpkg);
	if (@pinfo && $pinfo[0] eq $newpkg) {
		# Worked
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'scripts_esoftwaremod'});
		return 0;
		}
	}

# Check if a Gem version was requested, and if so update to it
local $vfunc = $script->{'gem_version_func'};
if (defined(&$vfunc)) {
	local $needver = &$vfunc($d, $ver, $opts);
	local $gotver = &get_gem_version();
	if (&compare_versions($needver, $gotver) > 0) {
		# Need a newer Gem version! Try to update
		&$first_print(&text('scripts_gemver', $gotver));
		local $gempath = &has_command("gem");
		local $rver = &get_ruby_version();
		$rver =~ s/^(\d+\.\d+).*/$1/;	# Make it like just 1.8
		local $oldgemverpath = &has_command("gem".$rver);
		&execute_command("gem list --remote");	# Force cache init
		$out = &backquote_logged(
			"gem update --system 2>&1 </dev/null");
		if ($?) {
			# Failed
			&$second_print(&text('scripts_gemverfailed',
					   "<tt>".&html_escape($out)."</tt>"));
			return 0;
			}
		elsif (&get_gem_version() eq $gotver) {
			# Appeared to be OK, but really failed
			&$second_print(&text('scripts_gemverfailed2', $gotver,
					   "<tt>".&html_escape($out)."</tt>"));
			return 0;
			}
		else {
			&$second_print($text{'setup_done'});

			# If the update installed gem1.8, link the old gem
			# command to it instead
			local $newgemverpath = &has_command("gem".$rver);
			if ($newgemverpath && !$oldgemverpath &&
			    $gempath &&
			    !&same_file($gempath, $newgemverpath)) {
				&$first_print(&text('scripts_gemlink',
						"<tt>$gempath</tt>",
						"<tt>$newgemverpath</tt>"));
				&unlink_file($gempath);
				&symlink_file($newgemverpath, $gempath);
				&$second_print($text{'setup_done'});
				}
			}
		}
	}

# Check if any Gems were needed
local $gfunc = $script->{'gems_func'};
if (defined(&$gfunc)) {
	local @gems = &$gfunc($d, $ver, $opts);
	foreach my $g (@gems) {
		local ($name, $version, $nore, $optional) = @$g;
		&$first_print(
		  $version ? &text('scripts_geminstall2',
				   "<tt>$name</tt>", $version) :
			     &text('scripts_geminstall', "<tt>$name</tt>"));
		local $err = &install_ruby_gem($name, $version, $nore);
		if ($err) {
			&$second_print(&text('scripts_gemfailed',
					"<tt>".&html_escape($err)."</tt>"));
			return 0 if (!$optional);
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}

return 1;
}

# check_script_required_commands(&domain, &script, version)
# Checks for commands required by some script, and returns a list of those
# that are missing.
sub check_script_required_commands
{
local ($d, $script, $ver, $opts) = @_;
local $cfunc = $script->{'commands_func'};
local @missing;
if ($cfunc && defined(&$cfunc)) {
	foreach my $c (&$cfunc($d, $ver, $opts)) {
		if (!&has_command($c)) {
			push(@missing, $c);
			}
		}
	}
return @missing;
}

# create_script_wget_job(&domain, url, mins, hours, [call-now])
# Creates a cron job running as some domain owner which regularly wget's
# some URL, to perform some periodic task for a script
sub create_script_wget_job
{
local ($d, $url, $mins, $hours, $callnow) = @_;
return 0 if (!&foreign_check("cron"));
&foreign_require("cron");
local $wget = &has_command("wget");
return 0 if (!$wget);
local $job = { 'user' => $d->{'user'},
	       'active' => 1,
	       'command' => "$wget -q -O /dev/null $url",
	       'mins' => $mins,
	       'hours' => $hours,
	       'days' => '*',
	       'months' => '*',
	       'weekdays' => '*' };
&cron::create_cron_job($job);
if ($callnow) {
	# Fetch the URL now
	local ($host, $port, $page, $ssl) = &parse_http_url($url);
	if ($host eq $d->{'dom'} && $port == ($d->{'web_sslport'} || $d->{'web_port'} || 80)) {
		# On this domain .. can use internal function which handles
		# use of internal IP
		local ($out, $err);
		&get_http_connection($d, $page, \$out, \$err);
		}
	else {
		# Need to call wget
		&system_logged("$wget -q -O /dev/null ".quotemeta($url).
			       " >/dev/null 2>&1 </dev/null");
		}
	}
return 1;
}

# delete_script_wget_job(&domain, url)
# Deletes the cron job that regularly fetches some URL
sub delete_script_wget_job
{
local ($d, $url) = @_;
return 0 if (!&foreign_check("cron"));
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq $d->{'user'} &&
		      $_->{'command'} =~ /^\S*wget\s.*\s(\S+)$/ &&
		      $1 eq $url } @jobs;
return 0 if (!$job);
&cron::delete_cron_job($job);
return 1;
}

# create_script_php_cron(&domain, full-command, phpver, mins, hours, callnow)
# If missing, create a cron job to run some PHP command
sub create_script_php_cron
{
local ($d, $cmd, $phpver, $mins, $hours, $callnow) = @_;
return 0 if (!&foreign_check("cron"));
&foreign_require("cron");
$cmd =~ /^(.*)\//;
local $dir = $1;
local $php = &php_command_for_version($phpver, 2);
local $fullcmd = "cd $dir && $php -f $cmd >/dev/null 2>&1";
local $job = { 'user' => $d->{'user'},
	       'active' => 1,
	       'command' => $fullcmd,
	       'mins' => $mins,
	       'hours' => $hours,
	       'days' => '*',
	       'months' => '*',
	       'weekdays' => '*' };
&cron::create_cron_job($job);
if ($callnow) {
	&system_logged(&command_as_user($d->{'user'}, 0, $fullcmd));
	}
}

# delete_script_php_cron(&domain, cmd)
# Remove the cron job that runs some PHP command
sub delete_script_php_cron
{
local ($d, $cmd) = @_;
return 0 if (!&foreign_check("cron"));
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq $d->{'user'} &&
		      $_->{'command'} =~ /-f\s+\Q$cmd\E/ } @jobs;
return 0 if (!$job);
&cron::delete_cron_job($job);
return 1;
}

# list_script_upgrades(&domains)
# Returns a list of script updates that can be done in the given domains
sub list_script_upgrades
{
local ($doms) = @_;
local (%scache, @rv);
foreach my $d (@$doms) {
	&detect_real_script_versions($d);
	foreach my $sinfo (&list_domain_scripts($d)) {
		# Find the lowest version better or equal to the one we have
		$script = $scache{$sinfo->{'name'}} ||
			    &get_script($sinfo->{'name'});
		$scache{$sinfo->{'name'}} = $script;
		local @vers = grep { &can_script_version($script, $_) }
			     @{$script->{'versions'}};
		local $canupfunc = $script->{'can_upgrade_func'};
		if (defined(&$canupfunc)) {
			@vers = grep { &$canupfunc($sinfo, $_) > 0 } @vers;
			}
		@vers = sort { &compare_versions($b, $a, $script) } @vers;
		local @better = grep { &compare_versions($_,
				$sinfo->{'version'}, $script) > 0 } @vers;
		local $ver = @better ? $better[$#better] : undef;
		next if (!$ver);

		# Don't upgrade if we are already running this version
		next if ($ver eq $sinfo->{'version'});

		# Don't upgrade if deleted
		next if ($sinfo->{'deleted'});

		# We have one - add to the results
		push(@rv, { 'sinfo' => $sinfo,
			    'script' => $script,
			    'dom' => $d,
			    'ver' => $ver });
		}
	}
return @rv;
}

# extract_script_archive(file, dir, &domain, [copy-to-dir], [sub-dir],
#			 [single-file], [ignore-errors], [&skip-files])
# Attempts to extract a tar.gz or tar or zip file for a script. Returns undef
# on success, or an HTML error message on failure.
sub extract_script_archive
{
local ($file, $dir, $d, $copydir, $subdir, $single, $ignore, $skip) = @_;

# Create the target dir if missing
if (!$single && $copydir && !-d $copydir) {
	local $out = &run_as_domain_user(
		$d, "mkdir -p ".quotemeta($copydir)." 2>&1");
	if ($?) {
		return "Failed to create target directory : ".
		       "<tt>".&html_escape($out)."</tt>";
		}
	elsif (!-d $copydir) {
		return "Command to create target directory did not work!";
		}
	&set_permissions_as_domain_user($d, 0755, $copydir);
	}

# Extract compressed file to a temp dir
if (!-d $dir) {
	# Can be done as root, as it is in /tmp
	&make_dir($dir, 0755);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, undef, $dir);
	}
local $fmt = &compression_format($file);
local $qfile = quotemeta($file);
local $cmd;
if ($fmt == 0) {
	return "Not a compressed file";
	}
elsif ($fmt == 1) {
	$cmd = "(gunzip -c $qfile | ".&make_tar_command("xf", "-").")";
	}
elsif ($fmt == 2) {
	$cmd = "(uncompress -c $qfile | ".&make_tar_command("xf", "-").")";
	}
elsif ($fmt == 3) {
	$cmd = "(".&get_bunzip2_command()." -c $qfile | ".
	       &make_tar_command("xf", "-").")";
	}
elsif ($fmt == 4) {
	$cmd = "unzip $qfile";
	}
elsif ($fmt == 5) {
	$cmd = &make_tar_command("xf", $file);
	}
else {
	return "Unknown compression format";
	}
local $out = &run_as_domain_user($d, "(cd ".quotemeta($dir)." && ".$cmd.") 2>&1");
return "Uncompression failed : <pre>".&html_escape($out)."</pre>"
	if ($? && !$ignore);

# Fix .htaccess files that use disallowed directives
if (!$config{'allow_symlinks'}) {
	&fix_script_htaccess_files($d, $dir);
	}

# Make sure the target files are owner-writable, so we can copy over them
if ($copydir && -e $copydir) {
	&run_as_domain_user($d, "chmod -R u+w ".quotemeta($copydir));
	}

# Copy to a target dir, if requested
if ($copydir) {
	local $path = "$dir/$subdir";
	if (!-e $path) {
		# Subdir might be a glob
		($path) = glob(quotemeta($dir)."/$subdir")
		}

	# Remove files to skip copying
	if ($skip) {
		foreach my $s (@$skip) {
			&run_as_domain_user($d,
				"rm -rf ".quotemeta($path)."/".$s);
			}
		}

	# Make sure all dirs to copy from are readable
	if (-d $path) {
		my $try = 0;
		while($try++ < 50) {
			my $out = &run_as_domain_user($d,
				"(find ".quotemeta($path).
				" -type d | xargs chmod +x) 2>&1");
			last if ($out !~ /permission\s+denied/i);
			}
		}

	# Make sure all files to copy from are readable
	my $try = 0;
	while($try++ < 50) {
		my $out = &run_as_domain_user($d,
			"(find ".quotemeta($path).
			" -type f | xargs chmod ug+rx) 2>&1");
		last if ($out !~ /permission\s+denied/i);
		}

	# If the destination has an index.html file and the source does not,
	# but does have index.php, remove the HTML
	my $hfile = $copydir."/index.html";
	$hfile = $copydir."/index.htm" if (!-r $hfile);
	my $pfile = $dir.($subdir ? "/$subdir" : "")."/index.php";
	$pfile = glob($pfile);
	if (-r $hfile && -r $pfile) {
		&unlink_file_as_domain_user($d, $hfile);
		}

	local $out;
	if (-f $path) {
		# Copy one file
		$out = &run_as_domain_user($d, "cp ".quotemeta($dir).
				   "/$subdir ".quotemeta($copydir)." 2>&1");
		}
	elsif (-d $path) {
		# Copy a directory's contents
		$out = &run_as_domain_user($d, "cp -r ".quotemeta($dir).
				   ($subdir ? "/$subdir/*" : "/*").
				   " ".quotemeta($copydir)." 2>&1");
		}
	else {
		return "Sub-directory $subdir was not found";
		}
	$out = undef if ($out !~ /\S/);
	if ($? && !$ignore) {
		return "<pre>".&html_escape($out || "Exit status $?")."</pre>";
		}

	# Copy any dot-files too
	if (-d $path) {
		$out = &run_as_domain_user($d, "cp -r ".quotemeta($dir).
				   ($subdir ? "/$subdir/.??*" : "/.??*").
				   " ".quotemeta($copydir)." 2>&1");
		}

	# Make dest files non-world-readable and user writable, unless we don't
	# add Apache to a group, or if the home is world-readable
	local $mode = &get_domain_php_mode($d);
	local @st = stat($d->{'home'});
	if (&apache_in_domain_group($d) && ($st[2]&07) == 0) {
		# Apache is a member of the domain's group, so we can make
		# all script files non-world-readable
		&run_as_domain_user($d, "chmod -R o-rxw ".quotemeta($copydir));
		}
	elsif ($mode ne "mod_php") {
		# Running via FPM, CGI or fastCGI, so make .php, .cgi and .pl
		# files non-world-readable
		&run_as_domain_user($d,
		  "find ".quotemeta($copydir)." -type f ".
		  "-name '*.php' -o -name '*.php?' -o -name '*.cgi' ".
		  "-o -name '*.pl' | xargs chmod -R o-rxw 2>/dev/null");
		}
	&run_as_domain_user($d, "chmod -R u+rwx ".quotemeta($copydir));
	&run_as_domain_user($d, "chmod -R g+rx ".quotemeta($copydir));
	}

return undef;
}

# has_domain_databases($d, &types, [dont-create])
# Returns 1 if a domain has any databases of the given types, or if one can
# be created by the script install process.
sub has_domain_databases
{
local ($d, $types, $nocreate) = @_;
local @dbs = &domain_databases($d, $types);
if (@dbs) {
	return 1;
	}
if (!$nocreate) {
	# Can we create one?
	local ($dleft, $dreason, $dmax) = &count_feature("dbs");
	local @ftypes = grep { $d->{$_} } @$types;
	if (@ftypes && $dleft != 0 && &can_edit_databases()) {
		return 1;
		}
	}
return 0;
}

# guess_script_version(file)
# Returns the highest version number from some script file
sub guess_script_version
{
local ($file) = @_;
local $lref = &read_file_lines($file, 1);
for(my $i=0; $i<@$lref; $i++) {
	if ($lref->[$i] =~ /^\s*sub\s+script_\S+_versions/) {
		if ($lref->[$i+2] =~ /^\s*return\s+\(([^\)]*)\)/ ||
		    $lref->[$i+1] =~ /^\s*return\s+\(([^\)]*)\)/) {
			local $verlist = $1;
			$verlist =~ s/^\s+//; $verlist =~ s/\s+$//;
			local @vers = &split_quoted_string($verlist);
			return $vers[0];
			}
		return undef;	# Versions not found where expected
		}
	}
return undef;
}

# setup_noproxy_path(&domain, &script, ver, &opts, add-even-if-no-clash)
# If a script isn't using proxying, ensure that it's path is not blocked.
# Prints messages, and returns 1 on success, 0 on failure.
sub setup_noproxy_path
{
local ($d, $script, $ver, $opts, $forceadd) = @_;

# Check if the script doesn't use proxying, and if Apache supports negatives
return 1 if (&indexof("proxy", @{$script->{'uses'}}) >= 0);
return 1 if (!&has_proxy_balancer($d) || !&has_proxy_none($d));

# Check if a proxy exists for a parent path
local @proxies = &list_proxy_balancers($d);
local $clash;
foreach my $p (@proxies) {
	if (!$p->{'none'} &&
	    ($p->{'path'} eq '/' ||
	     $p->{'path'} eq $opts->{'path'} ||
	     substr($opts->{'path'}, 0, length($p->{'path'})+1) eq
	     $p->{'path'}."/")) {
		$clash = $p;
		last;
		}
	}

# Check if we are already negating this path
foreach my $p (@proxies) {
	if ($p->{'path'} eq $opts->{'path'} && $p->{'none'}) {
		return 1;
		}
	}

local $err;
if ($clash && $clash->{'path'} eq $opts->{'path'}) {
	# Remove direct clash
	&$first_print(&text('scripts_delproxy', $opts->{'path'}));
	$err = &delete_proxy_balancer($d, $clash);
	}
elsif ($clash || $forceadd) {
	# Add a negative override
	&$first_print(&text('scripts_addover', $opts->{'path'}));
	local $over = { 'path' => $opts->{'path'}, 'none' => 1 };
	$err = &create_proxy_balancer($d, $over);
	}
else {
	# Nothing needs to be done
	return 1;
	}
if ($err) {
	&$second_print(&text('scripts_proxyfailed', $err));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# delete_noproxy_path(&domain, &script, ver, &opts)
# Delete any negative proxy for a script, as created by setup_noproxy_path
sub delete_noproxy_path
{
local ($d, $script, $ver, $opts) = @_;

# Check if the script doesn't use proxying, and if Apache supports negatives
return 0 if (&indexof("proxy", @{$script->{'uses'}}) >= 0);
return 0 if (!&has_proxy_balancer($d) || !&has_proxy_none($d));

# Find and remove the negator
local @proxies = &list_proxy_balancers($d);
foreach my $p (@proxies) {
	if ($p->{'path'} eq $opts->{'path'} && $p->{'none'}) {
		&delete_proxy_balancer($d, $p);
		return 1;
		}
	}
return 0;
}

# setup_script_requirements(&domain, &script, ver, &phpver, &opts)
# Install any needed PHP modules or other dependencies for some script.
# Returns 1 on success, 0 on failure. May print stuff.
sub setup_script_requirements
{
local ($d, $script, $ver, $phpver, $opts) = @_;

# Install modules needed for various scripting languages
&setup_php_modules($d, $script, $ver, $phpver, $opts) || return 0;
&setup_pear_modules($d, $script, $ver, $phpver, $opts) || return 0;
&setup_perl_modules($d, $script, $ver, $opts) || return 0;
&setup_ruby_modules($d, $script, $ver, $opts) || return 0;
&setup_python_modules($d, $script, $ver, $opts) || return 0;
&setup_noproxy_path($d, $script, $ver, $opts) || return 0;

# Setup PHP variables
if (&indexof("php", @{$script->{'uses'}}) >= 0) {
	&$first_print($text{'scripts_apache'});
	if (&setup_web_for_php($d, $script, $phpver)) {
		&$second_print($text{'setup_done'});
		&register_post_action(\&restart_apache) if ($d->{'web'});
		}
	else {
		&$second_print($text{'scripts_aalready'});
		}
	}

return 1;
}

# setup_script_packages(&script, &domain, version)
# Install any software packages requested by the script
sub setup_script_packages
{
local ($script, $d, $ver) = @_;
local $pkgfunc = $script->{'packages_func'};
return 1 if (!defined(&$pkgfunc));
local @pkgs = &$pkgfunc($d, $ver);
return 1 if (!@pkgs);
&$first_print(&text('scripts_needpackages', scalar(@pkgs)));
local $canpkgs = 0;
if (&foreign_installed("software")) {
	&foreign_require("software");
	if (defined(&software::update_system_install)) {
		$canpkgs = 1;
		}
	}
if (!$canpkgs) {
	&$second_print($text{'scripts_epackages'});
	return 0;
	}
&$indent_print();
local $count = 0;
foreach my $p (@pkgs) {
	&$first_print(&text('scripts_installpackage', $p));
	local @pinfo = &software::package_info($p);
	if (@pinfo && $pinfo[0] eq $p) {
		# Looks like we already have it!
		&$second_print($text{'scripts_gotpackage'});
		next;
		}

	# Install it
	if ($first_print eq \&null_print) {
		# Suppress output
		&capture_function_output(
		    \&software::update_system_install, $p);
		}
	elsif ($first_print eq \&first_text_print) {
		# Make output text
		local $out = &capture_function_output(
		    \&software::update_system_install, $p);
		print &html_tags_to_text($out);
		}
	else {
		# Show HTML output
		&software::update_system_install($p);
		}

	# Did it work?
	local @pinfo = &software::package_info($p);
	if (@pinfo && $pinfo[0] eq $p) {
		&$second_print($text{'setup_done'});
		$count++;
		}
	else {
		&$second_print($text{'scripts_failedpackage'});
		}
	}
&$outdent_print();
&$second_print($count == 0 ? $text{'scripts_packageall'}
			   : &text('scripts_packagecount', $count));
return 1;
}

# check_script_depends(&script, &domain, &ver, [&upgrade-info], [php-version])
# Returns a list of dependency problems found for this script, including
# missing commands.
sub check_script_depends
{
local ($script, $d, $ver, $sinfo, $phpver) = @_;
local @rv;

if (&indexof("php", @{$script->{'uses'}}) >= 0) {
	# If the script uses PHP, make sure it's enabled for the domain
	local $mode = &get_domain_php_mode($d);
	if ($mode eq "none") {
		push(@rv, $text{'scripts_iphpneed'});
		}

	# Also check the PHP version
	my $minfunc = $script->{'php_fullver_func'};
	my $maxfunc = $script->{'php_maxver_func'};
	my $fullver = &get_php_version($phpver, $d);
	if (!$fullver && $mode ne "none") {
		push(@rv, $text{'scripts_iphpnover'});
		}
	if ($fullver && defined(&$minfunc)) {
		my $minver = &$minfunc($d, $ver, $sinfo);
		if ($minver && &compare_versions($fullver, $minver) < 0) {
			return &text('scripts_iphpfullver', $minver, $fullver);
			}
		}
	if ($fullver && defined(&$maxfunc)) {
		my $maxver = &$maxfunc($d, $ver, $sinfo);
		if ($maxver && &compare_versions($fullver, $maxver) >= 0) {
			return &text('scripts_iphpmaxver', $maxver, $fullver);
			}
		}
	}

# Call script's depends function
if (defined(&{$script->{'depends_func'}})) {
	push(@rv, grep { $_ } &{$script->{'depends_func'}}($d, $ver, $sinfo, $phpver));
	}

# Check for DB type
if (defined(&{$script->{'dbs_func'}})) {
	local @dbs = &{$script->{'dbs_func'}}($d, $ver);
	if (!&has_domain_databases($d, \@dbs)) {
		local @dbnames = map { $text{'databases_'.$_} || $_ } @dbs;
		local $dbneed = @dbnames == 1 ?
			$dbnames[0] :
			&text('scripts_idbneedor', @dbnames[0..$#dbnames-1],
						   $dbnames[$#dbnames]);
		push(@rv, &text('scripts_idbneed', $dbneed) .
			(&can_edit_domain($d) ? 
			 &text_html('scripts_idbneed_link',
				        "edit_domain.cgi?dom=$d->{'id'}", $text{'edit_title'}) : ""));
		}
	}

# Check for required commands
push(@rv, map { &text('scripts_icommand', "<tt>$_</tt>") }
      &check_script_required_commands($d, $script, $ver, $sinfo->{'opts'}));

# Check for webserver CGI or PHP support
local $p = &domain_has_website($d);
local $cancgi = &has_cgi_support($d);
if (&indexof("cgi", @{$script->{'uses'}}) >= 0 && !$cancgi) {
	return $text{'scripts_inocgi'};
	}
if ($p ne "web" && &indexof("apache", @{$script->{'uses'}}) >= 0) {
	return $text{'scripts_inoapache'};
	}
my @supp = grep { $_ ne "none" } &supported_php_modes($d);
if (&indexof("php", @{$script->{'uses'}}) >= 0 && !@supp) {
	return $text{'scripts_inophp'};
	}

return wantarray ? @rv : join(", ", @rv);
}

# get_script_master_permissions()
# Returns flags indicating if the master admin is allowed to use
# disabled scripts or versions, and if new scripts are denied by default
sub get_script_master_permissions
{
local %unavail;
&read_file_cached($scripts_unavail_file, \%unavail);
return ($unavail{'allowmaster'}, $unavail{'allowvers'},
	$unavail{'denydefault'});
}

# save_script_master_permissions(allow-disabled, allow-versions, deny-default)
# Updates flags indicating what the master is allow to do for disabled scripts
sub save_script_master_permissions
{
local ($allow, $allowvers, $denydefault) = @_;
local %unavail;
&lock_file($scripts_unavail_file);
&read_file_cached($scripts_unavail_file, \%unavail);
($unavail{'allowmaster'}, $unavail{'allowvers'},
 $unavail{'denydefault'}) = ($allow, $allowvers, $denydefault);
&write_file($scripts_unavail_file, \%unavail);
&unlock_file($scripts_unavail_file);
}

# setup_scriptwarn_job(enabled, when)
# Create, update or delete the cron job that sends script update notifications
sub setup_scriptwarn_job
{
local ($enabled, $when) = @_;
&foreign_require("cron");
local $job = &find_cron_script($scriptwarn_cron_cmd);
if ($job && !$enabled) {
	# Delete job
	&delete_cron_script($job);
	}
elsif (!$job && $enabled) {
	# Create daily job
	$job = { 'user' => 'root',
		 'command' => $scriptwarn_cron_cmd,
		 'active' => 1 };
	&apply_cron_schedule($job, $when || 'daily');
	&setup_cron_script($job);
	}
elsif ($job && $enabled && $when &&
       $when ne &parse_cron_schedule($job)) {
	# Update schedule if needed
	&apply_cron_schedule($job, $when);
	&setup_cron_script($job);
	}
}

# setup_scriptlatest_job(enabled)
# Create or delete the cron job that downloads script updates
sub setup_scriptlatest_job
{
local ($enabled) = @_;
&foreign_require("cron");
local $job = &find_cron_script($scriptlatest_cron_cmd);
if ($job && !$enabled) {
	# Delete job
	&delete_cron_script($job);
	}
elsif (!$job && $enabled) {
	# Create daily job
	$job = { 'user' => 'root',
		 'command' => $scriptlatest_cron_cmd,
		 'active' => 1,
		 'mins' => int(rand()*60),
		 'hours' => int(rand()*24),
		 'days' => '*',
		 'months' => '*',
		 'weekdays' => '*', };
	&setup_cron_script($job);
	}
}

# apply_cron_schedule(&job, 'daily'|'weekly'|'monthly')
# Sets attributes of a Cron job to match some named schedule
sub apply_cron_schedule
{
my ($job, $sched) = @_;
$job->{'mins'} = int(rand()*60);
$job->{'hours'} = 0;
if ($sched eq 'daily') {
	$job->{'days'} = $job->{'months'} = $job->{'weekdays'} = '*';
	}
elsif ($sched eq 'weekly') {
	$job->{'weekdays'} = '1';
	$job->{'months'} = $job->{'days'} = '*';
	}
elsif ($sched eq 'monthly') {
	$job->{'days'} = '1';
	$job->{'months'} = $job->{'weekdays'} = '*';
	}
}

# parse_cron_schedule(&job)
# Returns 'daily', 'weekly', 'monthly' or undef depending on how often a Cron
# job runs
sub parse_cron_schedule
{
my ($job) = @_;
return $job->{'hours'} eq '0' && $job->{'days'} eq '*' &&
	 $job->{'months'} eq '*' && $job->{'weekdays'} eq '*' ? 'daily' :
       $job->{'days'} eq '1' &&
	  $job->{'months'} eq '*' && $job->{'weekdays'} eq '*' ? 'monthly' :
       $job->{'days'} eq '*' &&
	  $job->{'months'} eq '*' && $job->{'weekdays'} eq '1' ? 'weekly' :
								 undef;
}

# detect_real_script_versions(&domain)
# Scan the list of installed scripts for some domain, and update the real
# version number where necessary. Used to detect scripts that have been updated
# manually via some internal function, like Wordpress
sub detect_real_script_versions
{
local ($d) = @_;
foreach my $sinfo (&list_domain_scripts($d)) {
	my $script = &get_script($sinfo->{'name'});
	my $rfunc = $script->{'realversion_func'};
	if (defined(&$rfunc)) {
		local $realver = &$rfunc($d, $sinfo->{'opts'}, $sinfo);
		if ($realver && $realver ne $sinfo->{'version'}) {
			# Version has changed .. fix
			$sinfo->{'version'} = $realver;
			&save_domain_script($d, $sinfo);
			}
		}
	}
}

# php_quotemeta(string, [for-single-quotes])
# Quote ' and " characters in a PHP string
sub php_quotemeta
{
local ($str, $single) = @_;
$str =~ s/\\/\\\\/g;
$str =~ s/'/\\'/g;
if (!$single) {
	$str =~ s/"/\\"/g;
	$str =~ s/\$/\\\$/g;
	}
return $str;
}

# substitute_scriptname_template(scriptname, &domain)
# Returns an install script directory name, based on the config
sub substitute_scriptname_template
{
local ($name, $d) = @_;
if ($config{'scriptdir'} eq '*') {
	# Public HTML dir
	return "";
	}
elsif ($config{'scriptdir'}) {
	# Template for directory
	local %hash = &make_domain_substitions($d, 0);
	$hash{'SCRIPTNAME'} = $name;
	return &substitute_virtualmin_template($config{'scriptdir'}, \%hash);
	}
else {
	# Just the script name
	return $name;
	}
}

# describe_script_status(&sinfo, &script)
# Returns an HTML string describing the upgradability of a script
sub describe_script_status
{
my ($sinfo, $script) = @_;
my @everyvers = grep { &can_script_version($script, $_) }
		     @{$script->{'versions'}};
my @vers = @everyvers;
my @allvers = @everyvers;
my $canupfunc = $script->{'can_upgrade_func'};
if (defined(&$canupfunc)) {
	@allvers = grep { &$canupfunc($sinfo, $_) >= 0 } @allvers;
	@vers = grep { &$canupfunc($sinfo, $_) > 0 } @vers;
	}
my ($status, $canup);
if ($sinfo->{'deleted'}) {
	$status = "<font color=#ff0000>".
		  $text{'scripts_deleted'}."</font>";
	}
elsif (&indexof($sinfo->{'version'}, @vers) < 0) {
	# Not on list of possible versions that can be installed
	my @better = grep { &compare_versions($_, $sinfo->{'version'},
					      $script) > 0 } @vers;
	my @allbetter = grep { &compare_versions($_, $sinfo->{'version'},
					         $script) > 0 } @allvers;
	if (@better) {
		# Some newer version exists and we can upgrade to it
		$status = "<font color=#ffaa00>".
		  &text('scripts_newer', $better[$#better]).
		  "</font>";
		$canup = 1;
		}
	elsif (@allbetter) {
		# Some newer version exists, but cannot upgrade to it
		$status = "<font color=#ffaa00>".
		  &text('scripts_newer2', $allbetter[$#allbetter]).
		  "</font>";
		}
	elsif (&indexof($sinfo->{'version'}, @everyvers) >= 0) {
		# On the newest version that can be installed
		$status = "<font color=#00aa00>".
			  $text{'scripts_newest'}."</font>";
		}
	else {
		$status = $text{'scripts_nonewer'};
		}
	}
else {
	$status = "<font color=#00aa00>".
		  $text{'scripts_newest'}."</font>";
	}
return wantarray ? ($status, $canup) : $status;
}

# disable_script_php_timeout(&domain)
# Temporarily disable any PHP execution timeout for a domain, to allow long
# running install scripts to complete
# XXX fpm mode support
sub disable_script_php_timeout
{
local ($d) = @_;
local $mode = &get_domain_php_mode($d);
if ($mode eq "fcgid") {
	local $max = &get_fcgid_max_execution_time($d);
	return undef if (!$max);
	&set_fcgid_max_execution_time($d, $max_php_fcgid_timeout);
	&set_php_max_execution_time($d, $max_php_fcgid_timeout);
	return $max;
	}
elsif ($mode eq "cgi") {
	local $max = &get_php_max_execution_time($d);
	return undef if (!$max);
	&set_php_max_execution_time($d, $max_php_fcgid_timeout);
	return $max;
	}
else {
	return undef;
	}
}

# enable_script_php_timeout(&domain, old-timeout)
# Undoes the changes made by disable_script_php_timeout
# XXX fpm mode support
sub enable_script_php_timeout
{
local ($d, $max) = @_;
if (defined($max)) {
	local $mode = &get_domain_php_mode($d);
	if ($mode eq "fcgid") {
		&set_fcgid_max_execution_time($d, $max);
		&set_php_max_execution_time($d, $max);
		return 1;
		}
	elsif ($mode eq "cgi") {
		&set_php_max_execution_time($d, $max);
		return 1;
		}
	}
return 0;
}

# fix_script_htaccess_files(&domain, dir, [find-only], [filename])
# Find all .htaccess files under some dir to change FollowSymLinks to
# SymLinksifOwnerMatch
sub fix_script_htaccess_files
{
local ($d, $dir, $findonly, $filename) = @_;
$filename ||= ".htaccess";
local $out = &run_as_domain_user($d, "find ".quotemeta($dir).
				     " -type f -name ".quotemeta($filename).
				     " 2>/dev/null");
local @fixed;
foreach my $file (split(/\r?\n/, $out)) {
	next if (!-r $file);
	eval {
		local $main::error_must_die = 1;
		&lock_file($file) if (!$findonly);
		local $lref = $findonly ?
			&read_file_lines($file) :
			&read_file_lines_as_domain_user($d, $file);
		local $fixed = 0;
		local $allowed = &get_allowed_options_list();
		$allowed =~ s/^Options=//;
		$allowed =~ s/,/ /g;
		foreach my $l (@$lref) {
			if ($l =~ /^\s*Options.*(\s|\+)FollowSymLinks/) {
				$l =~ s/FollowSymLinks/SymLinksifOwnerMatch/g;
				$fixed++;
				}
			elsif ($l =~ /^\s*Options.*(\s|\+)All(\s|$)/) {
				$l =~ s/All/$allowed/g;
				$fixed++;
				}
			}
		if ($fixed) {
			push(@fixed, $file);
			}
		if ($fixed && !$findonly) {
			&flush_file_lines_as_domain_user($d, $file);
			}
		else {
			&unflush_file_lines($file);
			}
		&unlock_file($file) if (!$findonly);
		};
	}
return @fixed;
}

# get_python_path([major-version])
# Returns the full path to python
sub get_python_path
{
my ($ver) = @_;
my $basever = substr($ver, 0, 1);
my @opts = ( $config{'python_cmd'} );
if (!$basever || $basever == 3) {
	push(@opts, "python3", "python30",
		    "python3.9", "python39",
		    "python3.8", "python38",
		    "python3.7", "python37",
		    "python3.6", "python36");
	}
if (!$basever || $basever == 2) {
	push(@opts, "python2.7", "python27",
		    "python2.6", "python26");
	}
push(@opts, "python");
foreach my $o (@opts) {
	my $p = &has_command($o);
	next if (!$p);
	next if ($ver && &get_python_version($p) !~ /^\Q$ver\E(\.|$)/);
	return $p;
	}
return undef;
}

# list_used_tcp_ports()
# Returns an array of TCP ports in use by lsof
sub list_used_tcp_ports
{
my @rv;
my $out = &backquote_command("lsof -i tcp -n -l -P");
foreach my $l (split(/\r?\n/, $out)) {
	if ($l =~ /\s+([^:]+|\[[0-9a-f:]+\]):(\d+)\s+\(LISTEN\)/) {
		push(@rv, $2);
		}
	}
return @rv;
}

# allocate_free_tcp_port(&used-ports-map, starting-port)
# Returns a free port number starting at the base and not in the used ports
# map, by making probing TCP connections
sub allocate_free_tcp_port
{
my ($used, $rport) = @_;
my $lsof = { };
foreach my $p (&list_used_tcp_ports()) {
	$lsof->{$p} = 1;
	}
while($rport < 65536) {
	if (!$used->{$rport} &&
	    !$lsof->{$rport} &&
	    !getservbyname($rport, "tcp")) {
		my $err;
		if (!&open_socket("127.0.0.1", $rport, RSOCK, \$err)) {
			last;
			}
		close(RSOCK);
		}
	$rport++;
	}
return $rport >= 65536 ? undef : $rport;
}

# get_php_cli_command(script-php-version) 
# Returns the path to the non-CGI version of the PHP command
sub get_php_cli_command
{
local ($v) = @_;
local ($p5) = grep { $_->[0] == $v } &list_available_php_versions($d);
local $cmd = $p5->[1];
$cmd ||= &has_command("php5") || &has_command("php");
$cmd =~ s/-cgi//;
return $cmd;
}

# script_migrated_disallowed()
# Check if given script migrated from GPL
sub script_migrated_disallowed
{
my ($migrated) = @_;
return $migrated && !$virtualmin_pro
}

# script_migrated_status()
# If script cannot be installed or upgraded anymore
# because of migration display appropriate message
sub script_migrated_status
{
my ($status, $migrated, $can_upgrade) = @_;
return script_migrated_disallowed($script->{'migrated'}) ?
         &ui_link("https://virtualmin.com/shop/",
           $text{'scripts_gpl_to_pro'.($can_upgrade ? "_upgrade" : "").''}, 
             ($can_upgrade ? " text-warning" : ""), " target=_blank") :
           $status;
}

# check_script_quota(&domain, &script-info, version)
# Returns 1 if a domain has enough quota, or 0 and the amount of quota needed
sub check_script_quota
{
my ($d, $script, $ver) = @_;
if ($d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	}
return (1, undef, undef, undef)
	if (!$d->{'quota'});
my $qfunc = "script_".$script->{'name'}."_required_quota";
if (defined(&$qfunc)) {
	my ($need, $units) = &$qfunc($ver);
	if ($units) {
		$units = lc($units);
		my $f = $units eq 'k' ? 1024 :
			$units eq 'm' ? 1024*1024 :
			$units eq 'g' ? 1024*1024*1024 : 1;
		$need *= $f;
		}
	my ($usage) = &get_domain_quota($d);
	my $bsize = &quota_bsize("home");
	my $ok = $usage*$bsize + $need <= $d->{'quota'}*$bsize;
	return ($ok, $need, $usage*$bsize, $d->{'quota'}*$bsize);
	}
return (1, undef, undef, undef);
}

# script_link(link, [lang], [text])
# Returns script link, if array ref is passed returns link
# and name, if language returns formatted language string,
# if text just returns plain link
sub script_link
{
my ($link, $lang, $text) = @_;
my ($shref, $slname);
if (ref($link) eq 'ARRAY') {
	$shref = $link->[0];
	$slname = $link->[1];
	}
else {
	$shref = $link;
	$slname = $link;
	}
return $slname if ($text == 2);
return $shref if ($text == 1);
return &text($lang, $shref, $slname) if ($lang);
return &ui_link($shref, $slname, undef, "target=_blank");
}

# get_script_link(&dom, &script-info, [full-url])
# Returns script link, if partially installed
# still returns a link in italic
sub get_script_link
{
my ($d, $sinfo, $fullurl) = @_;
my $path = $sinfo->{'opts'}->{'path_real'} ||
           $sinfo->{'opts'}->{'path'} ||
           $sinfo->{'path'};
my $surl = $sinfo->{'url'} ? $sinfo->{'url'} :
	((&domain_has_ssl($d) ? 'https://' : 'http://') ."$d->{'dom'}${path}/");
my $slabel = $fullurl ? $surl : $path;
my $slink = "<a href='$surl' target=_blank>$slabel</a>";
return $sinfo->{'url'} ? $slink : "<i>$slink</i>";
}

# filetimestamp_to_version(filename-path)
# Given file name, returns versions number like 53.310.48
sub filetimestamp_to_version {
    my $filetimestamp = (stat(shift))[9];
    my $seconds_in_a_day = 86400;
    my $major = int($filetimestamp / ($seconds_in_a_day * 365));
    my $minor = int(($filetimestamp % ($seconds_in_a_day * 365)) / $seconds_in_a_day);
    my $patch = int(100 * (($filetimestamp % $seconds_in_a_day) / $seconds_in_a_day));
    return "$major.$minor.$patch";
}

# filetimestamp_to_date(filename-path)
# Given file name, returns its date like 10/25/2023 12:39 pm
sub filetimestamp_to_date {
    return &make_date((stat(shift))[9]);
}

1;

