# Functions for PHP configuration

# get_domain_php_mode(&domain)
# Returns 'mod_php' if PHP is run via Apache's mod_php, 'cgi' if run via
# a CGI script, 'fcgid' if run via fastCGI. This is detected by looking for the
# Action lines in httpd.conf.
sub get_domain_php_mode
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_php_mode", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
						   $d->{'web_port'});
if ($virt) {
	# First check for FPM socket, using a single ProxyPassMatch
	local @ppm = &apache::find_directive("ProxyPassMatch", $vconf);
	foreach my $ppm (@ppm) {
		if ($ppm =~ /unix:([^\|]+)/ ||
		    $ppm =~ /fcgi:\/\/(localhost|127\.0\.0\.1):\d+/) {
			return 'fpm';
			}
		}

	# Also check for FPM socket in a FilesMatch block
	foreach my $f (&apache::find_directive_struct("FilesMatch", $vconf)) {
		next if ($f->{'words'}->[0] ne '\.php$');
		foreach my $h (&apache::find_directive("SetHandler", $f->{'members'})) {
			if ($h =~ /proxy:fcgi:\/\/(localhost|127\.0\.0\.1)/ ||
			    $h =~ /proxy:unix:/) {
				return 'fpm';
				}
			}
		}

	# Look for an action, possibly in a directory, that runs the FCGI
	# wrapper for PHP scripts
	local @actions = &apache::find_directive("Action", $vconf);
	local $pdir = &public_html_dir($d);
	local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
			      $_->{'words'}->[0] eq $pdir."/" ||
			      &path_glob_match($_->{'words'}->[0], $pdir) }
		    &apache::find_directive_struct("Directory", $vconf);
	if ($dir) {
		push(@actions, &apache::find_directive("Action",
						       $dir->{'members'}));
		foreach my $f (&apache::find_directive("FCGIWrapper",
							$dir->{'members'})) {
			if ($f =~ /^\Q$d->{'home'}\E\/fcgi-bin\/php\S+\.fcgi/) {
				return 'fcgid';
				}
			}
		}

	# Look for an action that runs PHP via the CGI wrapper
	foreach my $a (@actions) {
		if ($a =~ /^application\/x-httpd-php[0-9\.]+\s+\/cgi-bin\/php\S+\.cgi/) {
			return 'cgi';
			}
		}

	# Look for a mapping from PHP scripts to plain text for 'none' mode
	if ($dir) {
		local @types = &apache::find_directive(
				"AddType", $dir->{'members'});
		foreach my $t (@types) {
			if ($t =~ /text\/plain\s+\.php/) {
				return 'none';
				}
			}
		}
	}

# Fall back to mod_php, if enabled
if (&get_apache_mod_php_version()) {
	return 'mod_php';
	}
return 'none';
}

# save_domain_php_mode(&domain, mode, [port], [new-domain])
# Changes the method a virtual web server uses to run PHP. Returns undef on
# success or an error message on failure.
sub save_domain_php_mode
{
local ($d, $mode, $port, $newdom) = @_;
local $p = &domain_has_website($d);
$p || return "Virtual server does not have a website";
local $tmpl = &get_template($d->{'template'});
local $oldmode = &get_domain_php_mode($d);
local @vers = sort { &compare_version_numbers($a->[0], $b->[0]) }
		   &list_available_php_versions($d, $mode);

# Work out the default PHP version for FPM
if ($mode eq "fpm") {
	local @fpms = grep { !$_->{'err'} } &list_php_fpm_configs();
	@fpms || return "No FPM versions found!";
	my $curr = &get_php_fpm_config($d->{'php_fpm_version'});
	if (!$curr) {
		# Current version isn't actually valid! Fall back to default
		delete($d->{'php_fpm_version'});
		}
	if (!$d->{'php_fpm_version'}) {
		# Work out the default FPM version from the template
		if (@vers) {
			# Use version from template, or the max version
			my $fpm;
			if ($tmpl->{'web_phpver'}) {
				($fpm) = grep { $_->[0] eq
					$tmpl->{'web_phpver'} } @vers;
				}
			$fpm ||= $vers[$#vers];
			$d->{'php_fpm_version'} = $fpm->[0];
			}
		else {
			# This should never happen?
			my $defconf = $tmpl->{'web_phpver'} ?
				&get_php_fpm_config($tmpl->{'web_phpver'}) : undef;
			$defconf ||= $fpms[0];
			$d->{'php_fpm_version'} = $defconf->{'shortversion'};
			}
		}
	}

if ($mode =~ /mod_php|none/ && $oldmode !~ /mod_php|none/) {
	# Save the PHP version for later recovery
	local $oldver = &get_domain_php_version($d, $oldmode);
	$d->{'last_php_version'} = $oldver;
	}

my $oldplog;
my $oldmail;
if ($mode ne $oldmode) {
	# Save the PHP error log path and mail mode
	$oldplog = &get_domain_php_error_log($d);
	$oldmail = &get_php_can_send_mail($d);
	}

# Work out source php.ini files
local (%srcini, %subs_ini);
$mode eq "none" || @vers || return "No PHP versions found for mode $mode";
foreach my $ver (@vers) {
	$subs_ini{$ver->[0]} = 0;
	local $srcini = $tmpl->{'web_php_ini_'.$ver->[0]};
	if (!$srcini || $srcini eq "none" || !-r $srcini) {
		$srcini = &get_global_php_ini($ver->[0], $mode);
		}
	else {
		$subs_ini{$ver->[0]} = 1;
		}
	$srcini{$ver->[0]} = $srcini;
	}
local @srcinis = &unique(values %srcini);

# Copy php.ini file into etc directory, for later per-site modification
local $etc = "$d->{'home'}/etc";
if (!-d $etc) {
	&make_dir_as_domain_user($d, $etc, 0755);
	}
foreach my $ver (@vers) {
	# Create separate .ini file for each PHP version, if missing
	local $subs_ini = $subs_ini{$ver->[0]};
	local $srcini = $srcini{$ver->[0]};
	local $inidir = "$etc/php$ver->[0]";
	if ($srcini && !-r "$inidir/php.ini") {
		# Copy file, set permissions, fix session.save_path, and
		# clear out extension_dir (because it can differ between
		# PHP versions)
		if (!-d $inidir) {
			&make_dir_as_domain_user($d, $inidir, 0755);
			}
		if (-r "$etc/php.ini" && !-l "$etc/php.ini") {
			# We are converting from the old style of a single
			# php.ini file to the new multi-version one .. just
			# copy the existing file for all versions, which is
			# assumed to be working
			&copy_source_dest_as_domain_user(
				$d, "$etc/php.ini", "$inidir/php.ini");
			}
		elsif ($subs_ini) {
			# Perform substitions on config file
			local $inidata = &read_file_contents($srcini);
			$inidata || return "Failed to read $srcini, ".
					   "or file is empty";
			$inidata = &substitute_virtualmin_template($inidata,$d);
			&open_tempfile_as_domain_user(
				$d, INIDATA, ">$inidir/php.ini");
			&print_tempfile(INIDATA, $inidata);
			&close_tempfile_as_domain_user($d, INIDATA);
			}
		else {
			# Just copy verbatim
			local ($ok, $err) = &copy_source_dest_as_domain_user(
				$d, $srcini, "$inidir/php.ini");
			$ok || return "Failed to copy $srcini to ".
				      "$inidir/php.ini : $err";
			}

		# Clear any caching on file
		&unflush_file_lines("$inidir/php.ini");
		undef($phpini::get_config_cache{"$inidir/php.ini"});

		local ($uid, $gid) = (0, 0);
		if (!$tmpl->{'web_php_noedit'}) {
			($uid, $gid) = ($d->{'uid'}, $d->{'ugid'});
			}
		if (&foreign_check("phpini") && -r "$inidir/php.ini") {
			# Fix up session save path, extension_dir and
			# gc_probability / gc_divisor
			&foreign_require("phpini");
			local $pconf = &phpini::get_config("$inidir/php.ini");
			local $tmp = &create_server_tmp($d);
			&phpini::save_directive($pconf, "session.save_path",
						$tmp);
			&phpini::save_directive($pconf, "upload_tmp_dir", $tmp);
			if (scalar(@srcinis) == 1 && scalar(@vers) > 1) {
				# Only if the same source is used for multiple
				# PHP versions.
				&phpini::save_directive($pconf, "extension_dir",
							undef);
				}

			# On some systems, these are not set and so sessions are
			# never cleaned up.
			local $prob = &phpini::find_value(
				"session.gc_probability", $pconf);
			local $div = &phpini::find_value(
				"session.gc_divisor", $pconf);
			&phpini::save_directive($pconf,
				"session.gc_probability", 1) if (!$prob);
			&phpini::save_directive($pconf,
				"session.gc_divisor", 100) if (!$div);

			# Set timezone to match system
			local $tz;
			if (&foreign_check("time")) {
				&foreign_require("time");
				if (&time::has_timezone()) {
					$tz = &time::get_current_timezone();
					}
				}
			if ($tz) {
				&phpini::save_directive($pconf,
					"date.timezone", $tz);
				}

			&flush_file_lines("$inidir/php.ini");
			}
		&set_ownership_permissions($uid, $gid, 0755, "$inidir/php.ini");
		}
	}

# Call plugin-specific function to perform webserver setup
if ($p ne 'web') {
	my $err = &plugin_call($p, "feature_save_web_php_mode",
			       $d, $mode, $port, $newdom);
	if (!$err) {
		$d->{'php_mode'} = $mode;
		&sync_alias_domain_php_mode($d);
		}
	return $err;
	}
&require_apache();

# Create wrapper scripts
if (&need_php_wrappers($d, $mode)) {
	&create_php_wrappers($d, $mode);
	}

# Setup PHP-FPM pool
if ($mode eq "fpm" && $oldmode ne "fpm") {
	&create_php_fpm_pool($d);
	}
elsif ($mode ne "fpm") {
	&delete_php_fpm_pool($d);
	}

# Add the appropriate directives to the Apache config
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
@ports = ( $port ) if ($port);	# Overridden to just do SSL or non-SSL
local $fdest = "$d->{'home'}/fcgi-bin";
local $pfound = 0;
foreach my $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$vconf);
	$pfound++;

	# Find <directory> sections containing PHP directives.
	# If none exist, add them in either the directory for
	# public_html, or the <virtualhost> if it already has them
	local @phpconfs;
	local @dirstrs = &apache::find_directive_struct("Directory",
							$vconf);
	foreach my $dirstr (@dirstrs) {
		local @wrappers = &apache::find_directive("FCGIWrapper",
					$dirstr->{'members'});
		local @actions =
			grep { $_ =~ /^application\/x-httpd-php/ }
			&apache::find_directive("Action",
						$dirstr->{'members'});
		if (@wrappers || @actions) {
			push(@phpconfs, $dirstr);
			}
		}
	if (!@phpconfs) {
		# No directory has them yet. Add to the <virtualhost> if it
		# already directives for cgi, the <directory> otherwise.
		# Unless we are using fcgid, in which case it must always be
		# added to the directory.
		local @pactions =
		    grep { $_ =~ /^application\/x-httpd-php\d+/ }
			&apache::find_directive("Action", $vconf);
		local $pdir = &public_html_dir($d);
		local ($dirstr) = grep { $_->{'words'}->[0] eq $pdir ||
					 $_->{'words'}->[0] eq $pdir."/" }
		    &apache::find_directive_struct("Directory", $vconf);
		if ($mode eq "fcgid") {
			$dirstr || return "No &lt;Directory&gt; section ".
					  "found for mod_fcgid directives";
			push(@phpconfs, $dirstr);
			}
		elsif ($dirstr && !@pactions) {
			push(@phpconfs, $dirstr);
			}
		else {
			push(@phpconfs, $virt);
			}
		}

	# Work out which PHP version each directory uses currently
	local %pdirs;
	if (!$newdom) {
		%pdirs = map { $_->{'dir'}, $_->{'version'} }
			     &list_domain_php_directories($d);
		}

	# Update all of the directories
	local @avail = map { $_->[0] }
			   &list_available_php_versions($d, $mode);
	local %allvers = map { $_, 1 } @all_possible_php_versions;
	foreach my $phpstr (@phpconfs) {
		# Remove all Action and AddType directives for suexec PHP
		local $phpconf = $phpstr->{'members'};
		local @actions = &apache::find_directive("Action", $phpconf);
		@actions = grep { !/^application\/x-httpd-php\d+/ }
				@actions;
		local @types = &apache::find_directive("AddType", $phpconf);
		@types = grep { !/^application\/x-httpd-php\d+/ &&
				!/\.php[0-9\.]*$/ } @types;

		# Remove all AddHandler and FCGIWrapper directives for fcgid
		local @handlers = &apache::find_directive("AddHandler",
							  $phpconf);
		@handlers = grep { !(/^fcgid-script\s+\.php(.*)$/ &&
				     ($1 eq '' || $allvers{$1})) } @handlers;
		local @wrappers = &apache::find_directive("FCGIWrapper",
							  $phpconf);
		@wrappers = grep {
			!(/^\Q$fdest\E\/php[0-9\.]+\.fcgi\s+\.php(.*)$/ &&
		        ($1 eq '' || $allvers{$1})) } @wrappers;

		# Add needed Apache directives. Don't add the AddHandler,
		# Alias and Directory if already there.
		local $ver = $pdirs{$phpstr->{'words'}->[0]} ||
			     $tmpl->{'web_phpver'} ||
			     $avail[$#avail];
		$ver = $avail[$#avail] if (&indexof($ver, @avail) < 0);
		if ($mode eq "cgi") {
			foreach my $v (@avail) {
				push(@actions, "application/x-httpd-php$v ".
					       "/cgi-bin/php$v.cgi");
				}
			}
		elsif ($mode eq "fcgid") {
			push(@handlers, "fcgid-script .php");
			foreach my $v (@avail) {
				push(@handlers, "fcgid-script .php$v");
				}
			push(@wrappers, "$fdest/php$ver.fcgi .php");
			foreach my $v (@avail) {
				push(@wrappers, "$fdest/php$v.fcgi .php$v");
				}
			}
		elsif ($mode eq "none") {
			foreach my $v (@avail) {
				push(@types, "text/plain .php$v");
				}
			push(@types, "text/plain .php");
			}
		if ($mode eq "cgi" || $mode eq "mod_php") {
			foreach my $v (@avail) {
				push(@types,"application/x-httpd-php$v .php$v");
				}
			}
		if ($mode eq "cgi") {
			push(@types, "application/x-httpd-php$ver .php");
			}
		elsif ($mode eq "mod_php") {
			push(@types, "application/x-httpd-php .php");
			}
		@types = &unique(@types);
		&apache::save_directive("Action", \@actions, $phpconf, $conf);
		&apache::save_directive("AddType", \@types, $phpconf, $conf);
		&apache::save_directive("AddHandler", \@handlers,
					$phpconf, $conf);
		&apache::save_directive("FCGIWrapper", \@wrappers,
					$phpconf, $conf);

		# For fcgid mode, the directory needs to have Options ExecCGI
		local ($opts) = &apache::find_directive("Options", $phpconf);
		if ($opts && $mode eq "fcgid" && $opts !~ /ExecCGI/) {
			$opts .= " +ExecCGI";
			&apache::save_directive("Options", [ $opts ],
						$phpconf, $conf);
			}
		}

	# For FPM mode, we need a proxy directive at the top level
	local $fsock = &get_php_fpm_socket_file($d, 1);
	local $fport = $d->{'php_fpm_port'};
	local $fmode = $fport ? 'port' :
		       -r $fsock ? 'socket' :
		       $tmpl->{'php_sock'} ? 'socket' : 'port';
	local @ppm = &apache::find_directive("ProxyPassMatch", $vconf);
	local @oldppm = grep { /unix:([^\|]+)/ || /fcgi:\/\/(localhost|127\.0\.0\.1):\d+/ } @ppm;
	if ($fsock) {
		@ppm = grep { !/unix:([^\|]+)/ } @ppm;
		}
	if ($fport) {
		@ppm = grep { !/fcgi:\/\/(localhost|127\.0\.0\.1):\d+/ } @ppm;
		}
	local $files;
	foreach my $f (&apache::find_directive_struct("FilesMatch", $vconf)) {
		$files = $f if ($f->{'words'}->[0] eq '\.php$');
		}
	if ($mode eq "fpm" && ($apache::httpd_modules{'core'} < 2.4 || @oldppm)) {
		# Use a proxy directive for older Apache or if this is what's
		# already in use
		local $phd = $phpconfs[0]->{'words'}->[0];
		if ($fmode eq 'socket') {
			# Use socket file
			push(@ppm, "^/(.*\.php(/.*)?)\$ unix:${fsock}|fcgi://127.0.0.1${phd}/\$1");
			}
		else {
			# Allocate and use a port number
			$fport = &get_php_fpm_socket_port($d);
			push(@ppm, "^/(.*\.php(/.*)?)\$ fcgi://127.0.0.1:${fport}${phd}/\$1");
			}
		}
	elsif ($mode eq "fpm" && $apache::httpd_modules{'core'} >= 2.4) {
		# Can use a FilesMatch block with SetHandler inside instead
		my $wanth;
		if ($fmode eq 'socket') {
			# Use a socket file
			$wanth = 'proxy:unix:'.$fsock."|fcgi://127.0.0.1";
			}
		else {
			# Allocate, save and use a TCP port
			my $fport = &get_php_fpm_socket_port($d);
			$wanth = 'proxy:fcgi://127.0.0.1:'.$fport;
			}
		if (!$files) {
			# Add a new FilesMatch block with the socket
			$files = { 'name' => 'FilesMatch',
			           'type' => 1,
			           'value' => '\.php$',
			           'words' => ['\.php$'],
			           'members' => [
			             { 'name' => 'SetHandler',
			               'value' => $wanth,
			             },
			           ],
			         };
			&apache::save_directive_struct(
				undef, $files, $vconf, $conf);
			}
		else {
			# Add the SetHandler directive to the FilesMatch block
			&apache::save_directive("SetHandler", [$wanth],
						$files->{'members'}, $conf);
			}
		}
	else {
		# For non-FPM mode, remove the whole files block,
		# and forget about any ports or sockets
		if ($files) {
			&apache::save_directive_struct(
				$files, undef, $vconf, $conf);
			}
		@ppm = grep { !/unix:|fcgi:/ } @ppm;
		delete($d->{'php_fpm_port'});
		}
	&apache::save_directive("ProxyPassMatch", \@ppm, $vconf, $conf);

	# For non-mod_php mode, we need a RemoveHandler .php directive at
	# the <virtualhost> level to supress mod_php which may still be active
	local @remove = &apache::find_directive("RemoveHandler", $vconf);
	@remove = grep { !(/^\.php(.*)$/ && ($1 eq '' || $allvers{$1})) }
		       @remove;
	if ($mode ne "mod_php") {
		push(@remove, ".php");
		foreach my $v (@avail) {
			push(@remove, ".php$v");
			}
		}
	@remove = &unique(@remove);
	&apache::save_directive("RemoveHandler", \@remove, $vconf, $conf);

	# For non-mod_php mode, use php_admin_value to turn off mod_php in
	# case it gets enabled in a .htaccess file
	if (&get_apache_mod_php_version()) {
		local @admin = &apache::find_directive("php_admin_value",
						       $vconf);
		@admin = grep { !/^engine\s+/ } @admin;
		if ($mode ne "mod_php") {
			push(@admin, "engine Off");
			}
		&apache::save_directive("php_admin_value", \@admin,
					$vconf, $conf);
		}

	# For fcgid mode, set IPCCommTimeout to either the configured value
	# or the PHP max execution time + 1, so that scripts run via fastCGI
	# aren't disconnected
	if ($mode eq "fcgid") {
		local $maxex;
		if ($config{'fcgid_max'} eq "*") {
			# Don't set
			$maxex = undef;
			}
		elsif ($config{'fcgid_max'} eq "") {
			# From PHP config
			local $inifile = &get_domain_php_ini($d, $ver);
			if (-r $inifile) {
				&foreign_require("phpini");
				local $iniconf = &phpini::get_config($inifile);
				$maxex = &phpini::find_value(
					"max_execution_time", $iniconf);
				}
			}
		else {
			# Fixed number
			$maxex = int($config{'fcgid_max'})-1;
			}
		if (defined($maxex)) {
			&set_fcgid_max_execution_time($d, $maxex, $mode, $p);
			}
		}
	else {
		# For other modes, don't set
		&apache::save_directive("IPCCommTimeout", [ ],
					$vconf, $conf);
		}

	# For fcgid mode, set max request size to 1GB, which is the default
	# in older versions of mod_fcgid but is smaller in versions 2.3.6 and
	# later.
	local $setmax;
	if ($mode eq "fcgid") {
		if ($gconfig{'os_type'} eq 'debian-linux' &&
                    $gconfig{'os_version'} >= 6) {
			# Debian 6 and Ubuntu 10 definately use mod_fcgid 2.3.6+
			$setmax = 1;
			}
		elsif ($gconfig{'os_type'} eq 'redhat-linux' &&
                       $gconfig{'os_version'} >= 14 &&
		       &foreign_check("software")) {
			# CentOS 6 and Fedora 14+ may have it..
			&foreign_require("software");
			local @pinfo = &software::package_info("mod_fcgid");
			if (&compare_versions($pinfo[4], "2.3.6") >= 0) {
				$setmax = 1;
				}
			}
		}
	&apache::save_directive("FcgidMaxRequestLen",
				$setmax ? [ 1024*1024*1024 ] : [ ],
				$vconf, $conf);

	&flush_file_lines();
	}

# Update PHP mode cache
$d->{'php_mode'} = $mode;
&sync_alias_domain_php_mode($d);

local @vlist = map { $_->[0] } &list_available_php_versions($d);
if ($mode !~ /mod_php|none/ && $oldmode =~ /mod_php|none/ &&
    $d->{'last_php_version'} &&
    &indexof($d->{'last_php_version'}, @vlist) >= 0) {
	# Restore PHP version from before mod_php or none modes
	my $err = &save_domain_php_directory($d, &public_html_dir($d),
				   $d->{'last_php_version'}, 1);
	return $err if ($err);
	}

if (defined($oldplog)) {
	# Restore the old PHP error log
	&save_domain_php_error_log($d, $oldplog);
	}
if (defined($oldmail)) {
	# Restore the old mail option
	&save_php_can_send_mail($d, $oldmail);
	}

# Link ~/etc/php.ini to the per-version ini file
&create_php_ini_link($d, $mode);
&create_php_bin_links($d, $mode);

&register_post_action(\&restart_apache);
$pfound || return "Apache virtual host was not found";

return undef;
}

# sync_alias_domain_php_mode(&domain)
# If a domain has an aliases, update their PHP modes to match this one
sub sync_alias_domain_php_mode
{
my ($d) = @_;
foreach my $ad (&get_domain_by("alias", $d->{'id'})) {
	&lock_domain($ad);
	$ad->{'php_mode'} = $d->{'php_mode'};
	&save_domain($ad);
	&unlock_domain($ad);
	}
}

# set_fcgid_max_execution_time(&domain, value, [mode], [port])
# Set the IPCCommTimeout directive to follow the given PHP max execution time
sub set_fcgid_max_execution_time
{
local ($d, $max, $mode, $port) = @_;
$mode ||= &get_domain_php_mode($d);
return 0 if ($mode ne "fcgid");
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_set_fcgid_max_execution_time",
			    $d, $max, $mode, $port);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
@ports = ( $port ) if ($port);	# Overridden to just do SSL or non-SSL
local $conf = &apache::get_config();
local $pfound = 0;
local $changed = 0;
foreach my $p (@ports) {
        local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
        next if (!$vconf);
	$pfound++;
	local @newdir = &apache::find_directive("FcgidIOTimeout", $vconf);
	local $dirname = @newdir ? "FcgidIOTimeout" : "IPCCommTimeout";
	local $oldvalue = &apache::find_directive($dirname, $vconf);
	local $want = $max ? $max + 1 : $max_php_fcgid_timeout;
	if ($oldvalue ne $want) {
		&apache::save_directive($dirname, [ $want ],
					$vconf, $conf);
		&flush_file_lines($virt->{'file'});
		$changed++;
		}
	}
$pfound || &error("Apache virtual host was not found");
if ($changed) {
	&register_post_action(\&restart_apache);
	}
}

# get_fcgid_max_execution_time(&domain)
# Returns the current max FCGId execution time, or undef for unlimited
sub get_fcgid_max_execution_time
{
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_fcgid_max_execution_time", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
local $v = &apache::find_directive("IPCCommTimeout", $vconf);
$v ||= &apache::find_directive("FcgidIOTimeout", $vconf);
return $v == 9999 ? undef : $v ? $v-1 : 40;
}

# set_php_max_execution_time(&domain, max)
# Updates the max execution time in all php.ini files, and possibly in the FPM
# config file
sub set_php_max_execution_time
{
my ($d, $max) = @_;
&foreign_require("phpini");
my @errs;
foreach my $ini (&list_domain_php_inis($d)) {
	eval {
		local $main::error_must_die = 1;
		local $f = $ini->[1];
		local $conf = &phpini::get_config($f);
		&phpini::save_directive($conf, "max_execution_time", $max);
		&flush_file_lines($f);
		};
	push(@errs, $@) if ($@);
	}
my $mode = &get_domain_php_mode($d);
if ($mode eq "fpm") {
	&save_php_fpm_ini_value($d, "max_execution_time",
				$max == 0 ? undef : $max);
	}
return @errs ? join(" ", @errs) : undef;
}

# get_php_max_execution_time(&domain)
# Returns the max execution time from a php.ini file
sub get_php_max_execution_time
{
local ($d, $max) = @_;
&foreign_require("phpini");
foreach my $ini (&list_domain_php_inis($d)) {
	local $f = $ini->[1];
	local $conf = &phpini::get_config($f);
	local $max = &phpini::find_value("max_execution_time", $conf);
	return $max if ($max ne '');
	}
return undef;
}

# need_php_wrappers(&domain, [&mode])
# Returns 1 if this PHP mode needs CGI wrappers
sub need_php_wrappers
{
local ($d, $mode) = @_;
$mode ||= &get_domain_php_mode($d);
return $mode ne "mod_php" && $mode ne "fpm" && $mode ne "none";
}

# create_php_wrappers(&domain, [phpmode])
# Creates all phpN.cgi wrappers for some domain
sub create_php_wrappers
{
local ($d, $mode) = @_;
$mode ||= &get_domain_php_mode($d);
local $dest = $mode eq "fcgid" ? "$d->{'home'}/fcgi-bin" : &cgi_bin_dir($_[0]);
local $tmpl = &get_template($d->{'template'});

if (!-d $dest) {
	# Need to create fcgi-bin
	&make_dir_as_domain_user($d, $dest, 0755);
	}

local $suffix = $mode eq "fcgid" ? "fcgi" : "cgi";
local $dirvar = $mode eq "fcgid" ? "PWD" : "DOCUMENT_ROOT";

# Make wrappers mutable
&set_php_wrappers_writable($d, 1);

# For each version of PHP, create a wrapper
local $pub = &public_html_dir($d);
local $children = &get_domain_php_children($d);
foreach my $v (&list_available_php_versions($d, $mode)) {
	next if (!$v->[1]);	# No executable available?!
	&open_tempfile_as_domain_user($d, PHP, ">$dest/php$v->[0].$suffix");
	local $t = "php".$v->[0].$suffix;
	if ($tmpl->{$t} && $tmpl->{$t} ne 'none') {
		# Use custom script from template
		local $s = &substitute_domain_template($tmpl->{$t}, $d);
		$s =~ s/\t/\n/g;
		$s .= "\n" if ($s !~ /\n$/);
		&print_tempfile(PHP, $s);
		}
	else {
		# Automatically generate
		local $shell = -r "/bin/bash" ? "/bin/bash" : "/bin/sh";
		local $common = "#!$shell\n".
				"PHPRC=\$$dirvar/../etc/php$v->[0]\n".
				"export PHPRC\n".
				"umask 022\n";
		if ($mode eq "fcgid") {
			local $defchildren = $tmpl->{'web_phpchildren'};
			$defchildren = undef if ($defchildren eq "none");
			if ($defchildren) {
				$common .= "PHP_FCGI_CHILDREN=$defchildren\n";
				$common .= "export PHP_FCGI_CHILDREN\n";
				}
			$common .= "PHP_FCGI_MAX_REQUESTS=99999\n";
			$common .= "export PHP_FCGI_MAX_REQUESTS\n";
			}
		elsif ($mode eq "cgi") {
			$common .= "if [ \"\$REDIRECT_URL\" != \"\" ]; then\n";
			$common .= "  SCRIPT_NAME=\$REDIRECT_URL\n";
			$common .= "  export SCRIPT_NAME\n";
			$common .= "fi\n";
			}
		&print_tempfile(PHP, $common);
		if ($v->[1] =~ /-cgi$/) {
			# php-cgi requires the SCRIPT_FILENAME variable
			&print_tempfile(PHP,
					"SCRIPT_FILENAME=\$PATH_TRANSLATED\n");
			&print_tempfile(PHP,
					"export SCRIPT_FILENAME\n");
			}
		&print_tempfile(PHP, "exec $v->[1]\n");
		}
	&close_tempfile_as_domain_user($d, PHP);
	&set_permissions_as_domain_user($d, 0755, "$dest/php$v->[0].$suffix");

	# Put back the old number of child processes
	if ($children >= 0) {
		&save_domain_php_children($d, $children, 1);
		}

	# Also copy the .fcgi wrapper to public_html, which is needed due to
	# broken-ness on some Debian versions!
	if ($mode eq "fcgid" && $gconfig{'os_type'} eq 'debian-linux' &&
            $gconfig{'os_version'} < 5) {
		&copy_source_dest_as_domain_user(
			$d, "$dest/php$v->[0].$suffix",
			"$pub/php$v->[0].$suffix");
		&set_permissions_as_domain_user(
			$d, 0755, "$pub/php$v->[0].$suffix");
		}
	}

# Re-apply resource limits
if (defined(&supports_resource_limits) && &supports_resource_limits()) {
	local $pd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	&set_php_wrapper_ulimits($d, &get_domain_resource_limits($pd));
	}

# Make wrappers immutable, to prevent deletion by users (which can crash Apache)
&set_php_wrappers_writable($d, 0);
}

# set_php_wrappers_writable(&domain, flag, [subdomains-too])
# If possible, make PHP wrapper scripts mutable or immutable
sub set_php_wrappers_writable
{
local ($d, $writable, $subs) = @_;
if (&has_command("chattr")) {
	foreach my $dir ("$d->{'home'}/fcgi-bin", &cgi_bin_dir($d)) {
		foreach my $f (glob("$dir/php?.*cgi")) {
			my @st = stat($f);
			if (-r $f && !-l $f && $st[4] == $d->{'uid'}) {
				&system_logged("chattr ".
				   ($writable ? "-i" : "+i")." ".quotemeta($f).
				   " >/dev/null 2>&1");
				}
			}
		}
	if ($subs) {
		# Also do sub-domains, as their CGI directories are under
		# parent's domain.
		foreach my $sd (&get_domain_by("subdom", $d->{'id'})) {
			&set_php_wrappers_writable($sd, $writable);
			}
		}
	}
}

# set_php_wrapper_ulimits(&domain, &resource-limits)
# Add, update or remove ulimit lines to set RAM and process restrictions
sub set_php_wrapper_ulimits
{
local ($d, $rv) = @_;
foreach my $dir ("$d->{'home'}/fcgi-bin", &cgi_bin_dir($d)) {
	foreach my $f (glob("$dir/php?.*cgi")) {
		local $lref = &read_file_lines_as_domain_user($d, $f);
		foreach my $u ([ 'v', int($rv->{'mem'}/1024) ],
			       [ 'u', $rv->{'procs'} ],
			       [ 't', $rv->{'time'}*60 ]) {
			if ($u->[0] eq 't' &&
			    $dir eq "$d->{'home'}/fcgi-bin") {
				# CPU time limit makes no sense for fcgi, as it
				# breaks the long-running php-cgi processes
				next;
				}

			# Find current line
			local $lnum;
			for(my $i=0; $i<@$lref; $i++) {
				if ($lref->[$i] =~ /^ulimit\s+\-(\S)\s+(\d+)/ &&
				    $1 eq $u->[0]) {
					$lnum = $i;
					last;
					}
				}
			if ($lnum && $u->[1]) {
				# Set value
				$lref->[$lnum] = "ulimit -$u->[0] $u->[1]";
				}
			elsif ($lnum && !$u->[1]) {
				# Remove limit
				splice(@$lref, $lnum, 1);
				}
			elsif (!$lnum && $u->[1]) {
				# Add at top of file
				splice(@$lref, 1, 0, "ulimit -$u->[0] $u->[1]");
				}
			}
		# If using process limits, we can't exec PHP as there will
		# be no chance for the limit to be applied :(
		local $ll = scalar(@$lref) - 1;
		if ($lref->[$ll] =~ /php/) {
			if ($rv->{'procs'} && $lref->[$ll] =~ /^exec\s+(.*)/) {
				# Remove exec
				$lref->[$ll] = $1;
				}
			elsif (!$rv->{'procs'} && $lref->[$ll] !~ /^exec\s+/) {
				# Add exec
				$lref->[$ll] = "exec ".$lref->[$ll];
				}
			}
		&flush_file_lines_as_domain_user($d, $f);
		}
	}
}

# set_php_fpm_ulimits(&domain, &resource-limits)
# Update the FPM config with resource limits
sub set_php_fpm_ulimits
{
my ($d, $res) = @_;
my $conf = &get_php_fpm_config($d);
return 0 if (!$conf);
if ($res->{'procs'}) {
	my $php_max_children =
		$res->{'procs'} > $max_php_fcgid_children ? 
			$max_php_fcgid_children : $res->{'procs'};
	&save_php_fpm_config_value($d, "pm.max_children", $php_max_children);
	&save_php_fpm_config_value($d, "pm.start_servers", &get_php_start_servers($php_max_children));
	&save_php_fpm_config_value($d, "pm.max_spare_servers", &get_php_max_spare_servers($php_max_children));
	}
else {
	my $tmpl = &get_template($d->{'template'});
	my $php_max_children = $tmpl->{'web_phpchildren'};
	$php_max_children = get_php_max_childred_allowed()
		if ($php_max_children eq "none" || !$php_max_children);
	&save_php_fpm_config_value($d, "pm.max_children", $php_max_children);
	&save_php_fpm_config_value($d, "pm.start_servers", &get_php_start_servers($php_max_children));
	&save_php_fpm_config_value($d, "pm.max_spare_servers", &get_php_max_spare_servers($php_max_children));
	}
&register_post_action(\&restart_php_fpm_server, $conf, $d->{'id'});
}

# supported_php_modes([&domain])
# Returns a list of PHP execution modes possible for a domain
sub supported_php_modes
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p ne 'web') {
	return &plugin_call($p, "feature_web_supported_php_modes", $d);
	}
my @rv = ( "none" );
foreach my $ver (&list_available_php_versions($d, "all")) {
	push(@rv, @{$ver->[2]});
	}
return &unique(@rv);
}

# php_mode_numbers_map()
# Returns a map from mode names (like 'cgi') to template numbers
sub php_mode_numbers_map
{
return { 'mod_php' => 0,
	 'cgi' => 1,
	 'fcgid' => 2,
	 'fpm' => 3,
	 'none' => 4, };
}

# list_available_php_versions([&domain], [forcemode|"all"])
# Returns a list of PHP versions and their executables installed on the system,
# for use by a domain. If forcemode is not set, the mode is taken from the
# domain.
sub list_available_php_versions
{
my ($d, $mode) = @_;
my $p = &domain_has_website($d);
if ($d) {
	$mode ||= &get_domain_php_mode($d);
	}
$mode ||= "all";
return () if ($mode eq "none");
&require_apache();

# In FPM mode, only the versions for which packages are installed can be used
my @rv;
if ($mode eq "fpm" || $mode eq "all") {
	foreach my $conf (grep { !$_->{'err'} } &list_php_fpm_configs()) {
		my $ver = $conf->{'shortversion'};
		my $cmd = $conf->{'cmd'} || &php_command_for_version($ver, 0);
		if (!$cmd && $ver =~ /^5\./) {
			# Try just PHP version 5
			$ver = 5;
			$cmd = &php_command_for_version($ver, 0);
			}
		$cmd ||= &has_command("php");
		if ($cmd) {
			push(@rv, [ $ver, $cmd, ["fpm"] ]);
			}
		}
	}

# Add the mod_php version if installed
if ($p eq 'web' && ($mode eq "mod_php" || $mode eq "all")) {
	my $v = &get_apache_mod_php_version();
	if ($v) {
		my $cmd = &has_command("php$v") ||
			  &has_command("php");
		push(@rv, [ $v, $cmd, ["mod_php"] ]);
		}
	}

# For CGI and fCGId modes, check which PHP commands exist
foreach my $v (@all_possible_php_versions) {
	my $phpn = &php_command_for_version($v, 1);
	$vercmds{$v} = $phpn if ($phpn);
	}

# Add extra configured PHP commands, and determine their versions
foreach my $path (split(/\t+/, $config{'php_paths'})) {
	next if (!-x $path);
	&clean_environment();
	local $out = &backquote_command("$path -v 2>&1 </dev/null");
	&reset_environment();
	if ($out =~ /PHP\s+(\d+.\d+)/ && !$vercmds{$1}) {
		$vercmds{$1} = $path;
		}
	}

local $php = &has_command("php-cgi");
if ($php && scalar(keys %vercmds) != scalar(@all_possible_php_versions)) {
	# What version is the php command? If it is a version we don't have
	# a command for yet, use it.
	if (!$php_command_version_cache) {
		&clean_environment();
		local $out = &backquote_command("$php -v 2>&1 </dev/null");
		&reset_environment();
		if ($out =~ /PHP\s+(\d+\.\d+)/) {
			my $v = $1;
			$v = int($v) if (int($v) <= 5);
			$php_command_version_cache = $v;
			}
		}
	if ($php_command_version_cache) {
		$vercmds{$php_command_version_cache} ||= $php;
		}
	}

# Add versions found to the final list for CGI and fcgid modes
my @hascgi;
if ($d) {
	my $m = get_domain_cgi_mode($d);
	push(@hascgi, $m) if ($m);
	}
else {
	@hascgi = &has_cgi_support();
	}
my @cgimodes;
if ($p eq 'web') {
	# Under Apache, CGI and fCGId modes need cgi-script support. But fcgid
	# mode only works with suexec
	push(@cgimodes, "fcgid") if (&indexof("suexec", @hascgi) >= 0);
	push(@cgimodes, "cgi") if (@hascgi);
	}
else {
	# Other webservers like Nginx have their own check for supported modes
	push(@cgimodes, grep { /^(cgi|fcgid)$/ }
		&plugin_call($p, "feature_web_supported_php_modes", $d));
	}
foreach my $v (sort { $a <=> $b } (keys %vercmds)) {
	my ($already) = grep { $_->[0] eq $v } @rv;
	if ($already) {
		$already->[2] = [ &unique(@{$already->[2]}, @cgimodes) ];
		}
	else {
		push(@rv, [ $v, $vercmds{$v}, [@cgimodes] ]);
		}
	}

# If a mode was given, filter down to it
if ($mode ne "all") {
	@rv = grep { &indexof($mode, @{$_->[2]}) >= 0 } @rv;
	}

@rv = sort { $a->[0] <=> $b->[0] } @rv;
return @rv;
}

# php_command_for_version(ver, [cgi-mode])
# Given a version like 5.4 or 5, returns the full path to the PHP executable
sub php_command_for_version
{
my ($v, $cgimode) = @_;
$cgimode ||= 0;
if (!$php_command_for_version_cache{$v,$cgimode}) {
	my @opts;
	if ($gconfig{'os_type'} eq 'solaris') {
		# On Solaris with CSW packages, php-cgi is in a directory named
		# after the PHP version
		push(@opts, "/opt/csw/php$v/bin/php-cgi");
		}
	push(@opts, "php$v-cgi", "php-cgi$v", "php$v");
	$v =~ s/^(\d+\.\d+)\.\d+$/$1/;
	my $nodotv = $v;
	$nodotv =~ s/\.//;
	if ($nodotv ne $v) {
		# For a version like 5.4, check for binaries like php54 and
		# /opt/rh/php54/root/usr/bin/php
		push(@opts, "php$nodotv-cgi",
			    "php-cgi$nodotv",
			    "/opt/rh/php$nodotv/root/usr/bin/php-cgi",
			    "/opt/rh/rh-php$nodotv/root/usr/bin/php-cgi",
			    "/opt/atomic/atomic-php$nodotv/root/usr/bin/php-cgi",
			    "/opt/atomic/atomic-php$nodotv/root/usr/bin/php",
			    "/opt/rh/php$nodotv/bin/php-cgi",
			    "/opt/remi/php$nodotv/root/usr/bin/php-cgi",
			    "php$nodotv",
			    "/opt/rh/php$nodotv/root/usr/bin/php",
			    "/opt/rh/rh-php$nodotv/root/usr/bin/php",
			    "/opt/rh/php$nodotv/bin/php",
			    glob("/opt/phpfarm/inst/bin/php-cgi-$v.*"));
		}
	if ($cgimode == 1) {
		# Only include -cgi commands
		@opts = grep { /-cgi/ } @opts;
		}
	elsif ($cgimode == 2) {
		# Skip -cgi commands
		@opts = grep { !/-cgi/ } @opts;
		}
	my $phpn;
	foreach my $o (@opts) {
		$phpn = &has_command($o);
		last if ($phpn);
		}
	$php_command_for_version_cache{$v,$cgimode} = $phpn;
	}
return $php_command_for_version_cache{$v,$cgimode};
}

# get_php_version(number|command, [&domain])
# Given a PHP based version like 4 or 5, or a path to PHP, return the real
# version number, like 5.2.7
sub get_php_version
{
local ($cmd, $d) = @_;
if (exists($get_php_version_cache{$cmd})) {
	return $get_php_version_cache{$cmd};
	}
if ($cmd !~ /^\//) {
	# A number was given .. find the matching command
	my $shortcmd = $cmd;
	$shortcmd =~ s/^(\d+\.\d+)\..*/$1/;  # Reduce version to 5.x
	local ($phpn) = grep { $_->[0] == $cmd ||
			       $_->[0] == $shortcmd }
			     &list_available_php_versions($d);
	if (!$phpn && $cmd =~ /^5\./) {
		# Also try just version '5'
		($phpn) = grep { $_->[0] == 5 }
			       &list_available_php_versions($d);
		}
	if (!$phpn && $cmd == 5) {
		# If the system ONLY has PHP 7, consider it compatible with
		# PHP major version 5
		($phpn) = grep { $_->[0] >= $cmd }
                             &list_available_php_versions($d);
		}
	if (!$phpn) {
		delete($get_php_version_cache{$cmd});
		return undef;
		}
	$cmd = $phpn->[1] || &has_command("php$cmd") || &has_command("php");
	}
&clean_environment();
local $out = &backquote_command("$cmd -v 2>&1 </dev/null");
&reset_environment();
if ($out =~ /PHP\s+([0-9\.]+)/) {
	$get_php_version_cache{$cmd} = $1;
	return $1;
	}
delete($get_php_version_cache{$cmd});
return undef;
}

# can_domain_php_directories(&domain, [mode])
# Returns 1 if the PHP version can be set on specific directories
sub can_domain_php_directories
{
my ($d, $mode) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web' &&
    &plugin_defined($p, "feature_can_domain_php_directories")) {
	return &plugin_call($p, "feature_can_domain_php_directories",
			    $d, $mode);
	}
$mode ||= &get_domain_php_mode($d);
return $mode eq "fpm" ? 0 : 1;
}

# list_domain_php_directories(&domain)
# Returns a list of directories for which different versions of PHP have
# been configured.
sub list_domain_php_directories
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_list_web_php_directories", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
local $mode = &get_domain_php_mode($d);
if ($mode eq "mod_php") {
	# All are run as version from Apache module
	local @avail = &list_available_php_versions($d, $mode);
	if (@avail) {
		return ( { 'dir' => &public_html_dir($d),
			   'version' => $avail[0]->[0],
			   'mode' => $mode } );
		}
	else {
		return ( );
		}
	}
elsif ($mode eq "fpm") {
	# Version is stored in the domain's config
	return ( { 'dir' => &public_html_dir($d),
		   'version' => $d->{'php_fpm_version'},
		   'mode' => $mode } );
	}
elsif ($mode eq "none") {
	# No PHP, so no directories
	return ( );
	}

# Find directories with either FCGIWrapper or AddType directives, and check
# which version they specify for .php files
local @dirs = &apache::find_directive_struct("Directory", $vconf);
local @rv;
foreach my $dir (@dirs) {
	local $n = $mode eq "cgi" ? "AddType" :
		   $mode eq "fcgid" ? "FCGIWrapper" : undef;
	foreach my $v (&apache::find_directive($n, $dir->{'members'})) {
		local $w = &apache::wsplit($v);
		if (&indexof(".php", @$w) > 0) {
			# This is for .php files .. look at the php version
			if ($w->[0] =~ /php([0-9\.]+)\.(cgi|fcgi)/ ||
			    $w->[0] =~ /x-httpd-php([0-9\.]+)/) {
				# Add version and dir to list
				push(@rv, { 'dir' => $dir->{'words'}->[0],
					    'version' => $1,
					    'mode' => $mode });
				last;
				}
			}
		}
	}
return @rv;
}

# save_domain_php_directory(&domain, dir, phpversion, [skip-ini-copy])
# Sets up a directory to run PHP scripts with a specific version of PHP.
# Should only be called on domains in cgi or fcgid mode! Returns undef on
# success, or an error message on failure (ie. because the virtualhost couldn't
# be found, or the PHP mode was wrong)
sub save_domain_php_directory
{
local ($d, $dir, $ver, $noini) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_save_web_php_directory",
			    $d, $dir, $ver);
	}
elsif (!$p) {
	return "Virtual server does not have a website!";
	}
&require_apache();
local $mode = &get_domain_php_mode($d);
return "PHP versions cannot be set in mod_php mode" if ($mode eq "mod_php");
local $oldlog = &get_domain_php_error_log($d);

if ($mode eq "fpm") {
	# Remove the old version pool and create a new one if needed.
	# Since it will be on the same port, no Apache changes are needed.
	my $phd = &public_html_dir($d);
	$dir eq $phd || return "FPM version can only be changed for the top-level directory";
	if ($ver ne $d->{'php_fpm_version'}) {
		my $oldlisten = &get_php_fpm_config_value($d, "listen");
		my $confs = &list_php_fpm_config_values($d);
		my @phpvs = &copyable_fpm_configs($confs);
		&delete_php_fpm_pool($d);
		&lock_domain($d);
		$d->{'php_fpm_version'} = $ver;
		&save_domain($d);
		&unlock_domain($d);
		&create_php_fpm_pool($d, $oldlisten);
		foreach my $pv (@phpvs) {
			&save_php_fpm_config_value($d, $pv->[0], $pv->[1]);
			}
		}
	}
else {
	# Config needs to be updated for each Apache virtualhost
	local $any = 0;
	local @ports = ( $d->{'web_port'},
			 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	local %allvers = map { $_, 1 } @all_possible_php_versions;
	foreach my $p (@ports) {
		local $conf = &apache::get_config();
		local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
		next if (!$virt);

		# Check for an existing <Directory> block
		local @dirs = &apache::find_directive_struct("Directory", $vconf);
		local ($dirstr) = grep { $_->{'words'}->[0] eq $dir } @dirs;
		if ($dirstr) {
			# Update the AddType or FCGIWrapper directives, so that
			# .php scripts use the specified version, and all other
			# .phpN use version N.
			if ($mode eq "cgi") {
				local @types = &apache::find_directive(
					"AddType", $dirstr->{'members'});
				@types = grep { $_ !~ /^application\/x-httpd-php[57]/ }
					      @types;
				foreach my $v (&list_available_php_versions($d)) {
					push(@types, "application/x-httpd-php$v->[0] ".
						     ".php$v->[0]");
					}
				push(@types, "application/x-httpd-php$ver .php");
				&apache::save_directive("AddType", \@types,
							$dirstr->{'members'}, $conf);
				&flush_file_lines($dirstr->{'file'});
				}
			elsif ($mode eq "fcgid") {
				local $dest = "$d->{'home'}/fcgi-bin";
				local @wrappers = &apache::find_directive(
					"FCGIWrapper", $dirstr->{'members'});
				@wrappers = grep {
					!(/^\Q$dest\E\/php\S+\.fcgi\s+\.php(\S*)$/ &&
					 ($1 eq '' || $allvers{$1})) } @wrappers;
				foreach my $v (&list_available_php_versions($d)) {
					push(@wrappers,
					     "$dest/php$v->[0].fcgi .php$v->[0]");
					}
				push(@wrappers, "$dest/php$ver.fcgi .php");
				@wrappers = &unique(@wrappers);
				&apache::save_directive("FCGIWrapper", \@wrappers,
							$dirstr->{'members'}, $conf);
				&flush_file_lines($dirstr->{'file'});
				}
			}
		else {
			# Add the directory
			local @phplines;
			if ($mode eq "cgi") {
				# Directives for plain CGI
				foreach my $v (&list_available_php_versions($d)) {
					push(@phplines,
					     "Action application/x-httpd-php$v->[0] ".
					     "/cgi-bin/php$v->[0].cgi");
					push(@phplines,
					     "AddType application/x-httpd-php$v->[0] ".
					     ".php$v->[0]");
					}
				push(@phplines,
				     "AddType application/x-httpd-php$ver .php");
				}
			elsif ($mode eq "fcgid") {
				# Directives for fcgid
				local $dest = "$d->{'home'}/fcgi-bin";
				push(@phplines, "AddHandler fcgid-script .php");
				push(@phplines, "FCGIWrapper $dest/php$ver.fcgi .php");
				foreach my $v (&list_available_php_versions($d)) {
					push(@phplines,
					     "AddHandler fcgid-script .php$v->[0]");
					push(@phplines,
					     "FCGIWrapper $dest/php$v->[0].fcgi ".
					     ".php$v->[0]");
					}
				}
			my $olist = $apache::httpd_modules{'core'} >= 2.2 ?
					" ".&get_allowed_options_list() : "";
			my $granteddir = "Require all granted";
			if ($apache::httpd_modules{'core'} < 2.4) {
				$granteddir = "Allow from all";
				}
			local @lines = (
				"    <Directory $dir>",
				"        Options +IncludesNOEXEC +SymLinksifOwnerMatch +ExecCGI",
				"        $granteddir",
				"        AllowOverride All".$olist,
				(map { "        ".$_ } @phplines),
				"    </Directory>"
				);
			local $lref = &read_file_lines($virt->{'file'});
			splice(@$lref, $virt->{'eline'}, 0, @lines);
			&flush_file_lines($virt->{'file'});
			undef(@apache::get_config_cache);
			}
		$any++;
		}
	return "No Apache virtualhosts found" if (!$any);
	}

# Make sure we have all the wrapper scripts
&create_php_wrappers($d, $mode);

# Re-create php.ini link
&create_php_ini_link($d, $mode);
&create_php_bin_links($d, $mode);

# Copy in php.ini file for version if missing
if (!$noini) {
	my @inifiles = &find_domain_php_ini_files($d);
	my ($iniver) = grep { $_->[0] eq $ver } @inifiles;
	if (!$iniver) {
		&save_domain_php_mode($d, $mode);
		}
	}

# Re-save PHP version
&save_domain_php_error_log($d, $oldlog);

&register_post_action(\&restart_apache);
return undef;
}

# delete_domain_php_directory(&domain, dir)
# Delete the <Directory> section for a custom PHP version in some directory
sub delete_domain_php_directory
{
local ($d, $dir) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_delete_web_php_directory", $d, $dir);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return 0 if (!$virt);
local $mode = &get_domain_php_mode($d);

local @dirs = &apache::find_directive_struct("Directory", $vconf);
local ($dirstr) = grep { $_->{'words'}->[0] eq $dir } @dirs;
if ($dirstr) {
	local $lref = &read_file_lines($dirstr->{'file'});
	splice(@$lref, $dirstr->{'line'},
	       $dirstr->{'eline'}-$dirstr->{'line'}+1);
	&flush_file_lines($dirstr->{'file'});
	undef(@apache::get_config_cache);

	&register_post_action(\&restart_apache);
	return 1;
	}
return 0;
}

# list_domain_php_inis(&domain, [force-mode])
# Returns a list of php.ini files used by a domain, and their PHP versions and
# commands.
sub list_domain_php_inis
{
local ($d, $mode) = @_;
local @inis;
foreach my $v (&list_available_php_versions($d, $mode)) {
	local $ifile = "$d->{'home'}/etc/php$v->[0]/php.ini";
	if (-r $ifile) {
		push(@inis, [ $v->[0], $ifile, $v->[1] ]);
		}
	}
if (!@inis) {
	local $ifile = "$d->{'home'}/etc/php.ini";
	if (-r $ifile) {
		push(@inis, [ undef, $ifile, undef ]);
		}
	}
return @inis;
}

# find_domain_php_ini_files(&domain)
# Returns the same information as list_domain_php_inis, but looks at files under
# the home directory only
sub find_domain_php_ini_files
{
local ($d) = @_;
local @inis;
foreach my $f (glob("$d->{'home'}/etc/php*/php.ini")) {
	if ($f =~ /php([0-9\.]+)\/php.ini$/) {
		push(@inis, [ $1, $f ]);
		}
	}
return @inis;
}

# get_domain_php_ini(&domain, php-version, [dir-only])
# Returns the php.ini file path for this domain and a PHP version
sub get_domain_php_ini
{
local ($d, $phpver, $dir) = @_;
local @inis = &list_domain_php_inis($d);
local ($ini) = grep { $_->[0] == $phpver } @inis;
if (!$ini) {
	($ini) = grep { !$_->[0]} @inis;
	}
if (!$ini && -r "$d->{'home'}/etc/php.ini") {
	# For domains with no matching version file
	$ini = [ undef, "$d->{'home'}/etc/php.ini" ];
	}
if (!$ini) {
	return undef;
	}
else {
	$ini->[1] =~ s/\/php.ini$//i if ($dir);
	return $ini->[1];
	}
}

# get_global_php_ini(phpver, mode)
# Returns the full path to the global PHP config file
sub get_global_php_ini
{
local ($ver, $mode) = @_;
local $nodotv = $ver;
$nodotv =~ s/\.//g;
local $shortv = $ver;
$shortv =~ s/^(\d+\.\d+)\..*$/$1/g;
foreach my $i ("/opt/rh/php$nodotv/root/etc/php.ini",
	       "/opt/rh/php$nodotv/lib/php.ini",
	       "/etc/opt/rh/rh-php$nodotv/php.ini",
	       "/opt/remi/php$nodotv/root/etc/php.ini",
	       "/etc/opt/remi/php$nodotv/php.ini",
	       "/opt/atomic/atomic-php$nodotv/root/etc/php.ini",
	       "/etc/php.ini",
	       $mode eq "mod_php" ? ("/etc/php$ver/apache/php.ini",
				     "/etc/php$ver/apache2/php.ini",
				     "/etc/php$nodotv/apache/php.ini",
                                     "/etc/php$nodotv/apache2/php.ini",
				     "/etc/php$shortv/apache/php.ini",
                                     "/etc/php$shortv/apache2/php.ini",
				    )
				  : ("/etc/php$ver/cgi/php.ini",
				     "/etc/php$nodotv/cgi/php.ini",
				     "/etc/php$shortv/cgi/php.ini",
				     "/etc/php/$ver/cgi/php.ini",
				     "/etc/php/$nodotv/cgi/php.ini",
				     "/etc/php/$shortv/cgi/php.ini",
				    ),
	       "/opt/csw/php$ver/lib/php.ini",
	       "/usr/local/lib/php.ini",
	       "/usr/local/etc/php.ini",
	       "/usr/local/etc/php.ini-production") {
	return $i if (-r $i);
	}
return undef;
}

# get_php_mysql_socket(&domain)
# Returns the PHP mysql socket path to use for some domain, from the
# global config file. Returns 'none' if not possible, or an empty string
# if not set.
sub get_php_mysql_socket
{
local ($d) = @_;
return 'none' if (!&foreign_check("phpini"));
local $mode = &get_domain_php_mode($d);
local @vers = &list_available_php_versions($d, $mode);
return 'none' if (!@vers);
local $tmpl = &get_template($d->{'template'});
local $inifile = $tmpl->{'web_php_ini_'.$vers[0]->[0]};
if (!$inifile || $inifile eq "none" || !-r $inifile) {
	$inifile = &get_global_php_ini($vers[0]->[0], $mode);
	}
&foreign_require("phpini");
local $gconf = &phpini::get_config($inifile);
local $sock = &phpini::find_value("mysql.default_socket", $gconf);
return $sock;
}

# get_domain_php_fpm_mode(&domain)
# Get the PHP-FPM process manager mode for some domain
sub get_domain_php_fpm_mode
{
my ($d) = @_;
my $pm = &get_php_fpm_config_value($d, "pm");
return $pm || 'dynamic';
}

# get_domain_php_children(&domain)
# For a domain using fcgi to run PHP, returns the number of child processes.
# Returns 0 if not set, -1 if the file doesn't even exist, -2 if not supported
sub get_domain_php_children
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_php_children", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
my $mode = &get_domain_php_mode($d);
if ($mode eq "fcgid") {
	# Set in wrapper script 
	my ($ver) = &list_available_php_versions($d, "fcgid");
	return -2 if (!$ver);
	my $childs = 0;
	&open_readfile_as_domain_user($d, WRAPPER,
		"$d->{'home'}/fcgi-bin/php$ver->[0].fcgi") || return -1;
	while(<WRAPPER>) {
		if (/^PHP_FCGI_CHILDREN\s*=\s*(\d+)/) {
			$childs = $1;
			}
		}
	&close_readfile_as_domain_user($d, WRAPPER);
	return $childs;
	}
elsif ($mode eq "fpm") {
	# Set in pool config file
	my $conf = &get_php_fpm_config($d);
	return -1 if (!$conf);
	my $file = $conf->{'dir'}."/".$d->{'id'}.".conf";
	my $lref = &read_file_lines($file, 1);
	my $childs = 0;
	foreach my $l (@$lref) {
		if ($l =~ /pm\.max_children\s*=\s*(\d+)/) {
			$childs = $1;
			}
		}
	&unflush_file_lines($file);
	return $childs == get_php_max_childred_allowed() ? 0 : $childs;
	}
else {
	return -2;
	}
}

# save_domain_php_fpm_mode(&domain, mode)
# Save the PHP-FPM process manager mode for some domain
sub save_domain_php_fpm_mode
{
my ($d, $modetype) = @_;
&save_php_fpm_config_value($d, 'pm', $modetype);
}

# save_domain_php_children(&domain, children, [no-writable])
# Update all of a domain's PHP wrapper scripts with the new number of children
sub save_domain_php_children
{
local ($d, $children, $nowritable) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_save_web_php_children", $d,
			    $children, $nowritable);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
my $mode = &get_domain_php_mode($d);
if ($mode eq "fcgid") {
	# Update in FCGI wrapper scripts
	local $count = 0;
	&set_php_wrappers_writable($d, 1) if (!$nowritable);
	foreach my $ver (&list_available_php_versions($d, "fcgi")) {
		local $wrapper = "$d->{'home'}/fcgi-bin/php$ver->[0].fcgi";
		next if (!-r $wrapper);

		# Find the current line
		local $lref = &read_file_lines_as_domain_user($d, $wrapper);
		local $idx;
		for(my $i=0; $i<@$lref; $i++) {
			if ($lref->[$i] =~ /PHP_FCGI_CHILDREN\s*=\s*\d+/) {
				$idx = $i;
				}
			}

		# Update, remove or add
		if ($children && defined($idx)) {
			$lref->[$idx] = "PHP_FCGI_CHILDREN=$children";
			}
		elsif (!$children && defined($idx)) {
			splice(@$lref, $idx, 1);
			}
		elsif ($children && !defined($idx)) {
			# Add before export line
			local $found = 0;
			for(my $e=0; $e<@$lref; $e++) {
				if ($lref->[$e] =~ /^export\s+PHP_FCGI_CHILDREN/) {
					splice(@$lref, $e, 0,
					       "PHP_FCGI_CHILDREN=$children");
					$found++;
					last;
					}
				}
			if (!$found) {
				# Add both lines at top
				splice(@$lref, 1, 0,
				       "PHP_FCGI_CHILDREN=$children",
				       "export PHP_FCGI_CHILDREN");
				}
			}
		&flush_file_lines_as_domain_user($d, $wrapper);
		}
	&set_php_wrappers_writable($d, 0) if (!$nowritable);
	&register_post_action(\&restart_apache);
	return 1;
	}
elsif ($mode eq "fpm") {
	# Update in FPM pool file
	my $conf = &get_php_fpm_config($d);
	return 0 if (!$conf);
	my $file = $conf->{'dir'}."/".$d->{'id'}.".conf";
	return 0 if (!-r $file);
	&lock_file($file);
	my $lref = &read_file_lines($file);
	$children = get_php_max_childred_allowed() if ($children == 0);	# Recommended default
	foreach my $l (@$lref) {
		if ($l =~ /pm\.max_children\s*=\s*(\d+)/) {
			$l = "pm.max_children = $children";
			}
		if ($l =~ /pm\.start_servers\s*=\s*(\d+)/) {
			$l = "pm.start_servers = " . get_php_start_servers($children) . "";
			}
		if ($l =~ /pm\.max_spare_servers\s*=\s*(\d+)/) {
			$l = "pm.max_spare_servers = " . get_php_max_spare_servers($children) . "";
			}
		}
	&flush_file_lines($file);
	&unlock_file($file);
	&register_post_action(\&restart_php_fpm_server, $conf, $d->{'id'});
	return 1;
	}
else {
	return 0;
	}
}

# check_php_configuration(&domain, php-version, php-command)
# Returns an error message if the domain's PHP config is invalid
sub check_php_configuration
{
local ($d, $ver, $cmd) = @_;
$cmd ||= &has_command("php".$ver) || &has_command("php");
local $mode = &get_domain_php_mode($d);
if ($mode eq "mod_php") {
	local $gini = &get_global_php_ini($ver, $mode);
	if ($gini) {
		$gini =~ s/\/php.ini$//;
		$ENV{'PHPRC'} = $gini;
		}
	}
else {
	$ENV{'PHPRC'} = &get_domain_php_ini($d, $ver, 1);
	}
&clean_environment();
local $out = &backquote_command("$cmd -d error_log= -m 2>&1");
local @errs;
foreach my $l (split(/\r?\n/, $out)) {
	$l = &html_tags_to_text($l);
	if ($l =~ /(PHP\s+)?Fatal\s+error:\s*(.*)/) {
		my $msg = $2;
		$msg =~ s/\s+in\s+\S+\s+on\s+line\s+\d+//;
		push(@errs, $msg);
		}
	}
&reset_environment();
delete($ENV{'PHPRC'});
return join(", ", @errs);
}

# list_php_modules(&domain, php-version, php-command)
# Returns a list of PHP modules available for some domain. Uses caching.
sub list_php_modules
{
local ($d, $ver, $cmd) = @_;
local $mode = &get_domain_php_mode($d);
if (!defined($main::php_modules{$ver,$d->{'id'}})) {
	$cmd ||= &has_command("php".$ver) || &has_command("php");
	$main::php_modules{$ver} = [ ];
	if ($mode eq "mod_php" || $mode eq "fpm") {
		# Use global PHP config, since with mod_php we can't do
		# per-domain configurations
		local $gini = &get_global_php_ini($ver, $mode);
		if ($gini) {
			$gini =~ s/\/php.ini$//;
			$ENV{'PHPRC'} = $gini;
			}
		}
	elsif ($d) {
		# Use domain's php.ini
		$ENV{'PHPRC'} = &get_domain_php_ini($d, $ver, 1);
		}
	&clean_environment();
	local $_;
	&open_execute_command(PHP, "$cmd -m", 1);
	while(<PHP>) {
		s/\r|\n//g;
		if (/^\S+$/ && !/\[/) {
			push(@{$main::php_modules{$ver,$d->{'id'}}}, $_);
			}
		}
	close(PHP);
	&reset_environment();
	delete($ENV{'PHPRC'});
	}
return @{$main::php_modules{$ver,$d->{'id'}}};
}

# fix_php_ini_files(&domain, &fixes)
# Updates values in all php.ini files in a domain. The fixes parameter is
# a list of array refs, containing old values, new value and regexp flag.
# If the old value is undef, anything matches. May print stuff. Returns the
# number of changes made.
sub fix_php_ini_files
{
local ($d, $fixes) = @_;
local ($mode, $rv);
if (defined(&get_domain_php_mode) &&
    ($mode = &get_domain_php_mode($d)) &&
    $mode ne "mod_php" &&
    $mode ne "fpm" &&
    &foreign_check("phpini")) {
	&foreign_require("phpini");
	&$first_print($text{'save_apache10'});
	foreach my $i (&list_domain_php_inis($d)) {
		&unflush_file_lines($i->[1]);	# In case cached
		undef($phpini::get_config_cache{$i->[1]});
		local $pconf = &phpini::get_config($i->[1]);
		foreach my $f (@$fixes) {
			local $ov = &phpini::find_value($f->[0], $pconf);
			local $nv = $ov;
			if (!defined($f->[1])) {
				# Always change
				$nv = $f->[2];
				}
			elsif ($f->[3] && $ov =~ /\Q$f->[1]\E/) {
				# Regexp change
				$nv =~ s/\Q$f->[1]\E/$f->[2]/g;
				}
			elsif (!$f->[3] && $ov eq $f->[1]) {
				# Exact match change
				$nv = $f->[2];
				}
			if ($nv ne $ov) {
				# Update in file
				&phpini::save_directive($pconf, $f->[0], $nv);
				&flush_file_lines($i->[1]);
				$rv++;
				}
			}
		}
	&$second_print($text{'setup_done'});
	}
return $rv;
}

# fix_php_fpm_pool_file(&domain, &fixes)
# Updates values in PHP FPM config file
sub fix_php_fpm_pool_file
{
my ($d, $fixes) = @_;
my ($mode, $rv, $conf, $file);
if (defined(&get_domain_php_mode) &&
    ($mode = &get_domain_php_mode($d)) &&
    $mode eq "fpm" &&
    &foreign_check("phpini")) {
	&foreign_require("phpini");
	$conf = &get_php_fpm_config($d);
	if ($conf) {
		$file = $conf->{'dir'}."/".$d->{'id'}.".conf";
		}
	if (-r $file) {
		&$first_print($text{'save_apache12'});
		&unflush_file_lines($file);	# In case cached
		undef($phpini::get_config_cache{$file});
		my $fpmconf = &phpini::get_config($file);
		foreach my $f (@{$fixes}) {
			my $ov = &phpini::find_value($f->[0], $fpmconf);
			my $nv = $ov;
			if (!defined($f->[1])) {
				# Always change
				$nv = $f->[2];
				}
			elsif ($f->[3] && $ov =~ /\Q$f->[1]\E/) {
				# Regexp change
				$nv =~ s/\Q$f->[1]\E/$f->[2]/;
				}
			elsif (!$f->[3] && $ov eq $f->[1]) {
				# Exact match change
				$nv = $f->[2];
				}
			if ($nv ne $ov) {
				# Update in file
				&phpini::save_directive($fpmconf, $f->[0], $nv);
				&flush_file_lines($file);
				$rv++;
				}
			}
		if ($rv) {
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print($text{'save_apache12none'});
			}
		}
	}
return $rv;
}

# fix_php_extension_dir(&domain)
# If the extension_dir in a domain's php.ini file is invalid, try to fix it
sub fix_php_extension_dir
{
local ($d) = @_;
return if (!&foreign_check("phpini"));
&foreign_require("phpini");
foreach my $i (&list_domain_php_inis($d)) {
	local $pconf = &phpini::get_config($i->[1]);
	local $ed = &phpini::find_value("extension_dir", $pconf);
	if ($ed && !-d $ed) {
		# Doesn't exist .. maybe can fix
		my $newed = $ed;
		if ($newed =~ /\/lib\//) {
			$newed =~ s/\/lib\//\/lib64\//;
			}
		elsif ($newed =~ /\/lib64\//) {
			$newed =~ s/\/lib64\//\/lib\//;
			}
		if (!-d $newed) {
			# Couldn't find it, give up and clear
			$newed = undef;
			}
		&phpini::save_directive($pconf, "extension_dir", $newed);
		}
	}
}

# get_domain_php_version(&domain, [php-mode])
# Get the PHP version used by the domain by default (for public_html)
sub get_domain_php_version
{
local ($d, $mode) = @_;
$mode ||= &get_domain_php_mode($d);
if ($mode ne "mod_php") {
	local @dirs = &list_domain_php_directories($d);
	local $phd = &public_html_dir($d);
        local ($hdir) = grep { $_->{'dir'} eq $phd } @dirs;
        $hdir ||= $dirs[0];
	return $hdir ? $hdir->{'version'} : undef;
	}
return undef;
}

# get_domain_php_version_for_directory(&domain, [directory])
# Get the PHP version used by the domain in some directory.
# If directory param is not specified, it defaults to the
# public_html directory.
# If PHP is disabled or not set, undef is returned.
sub get_domain_php_version_for_directory
{
my ($d, $dir) = @_;
return undef if (!$d);
$dir ||= &public_html_dir($d);
my $phpver;
my @pdirs = &list_domain_php_directories($d);
@pdirs = sort { length($a->{'dir'}) <=> length($b->{'dir'}) } @pdirs;
foreach my $pdir (@pdirs) {
	if (&is_under_directory($pdir->{'dir'}, $dir)) {
		$phpver = $pdir->{'version'};
		}
        }
if (!$phpver) {
	my @allvers = map { $_->[0] } &list_available_php_versions($d);
	$phpver = $allvers[0];
	}
return $phpver;
}

# create_php_ini_link(&domain, [php-mode])
# Create a link from etc/php.ini to the PHP version used by the domain's
# public_html directory
sub create_php_ini_link
{
local ($d, $mode) = @_;
local $ver = &get_domain_php_version($d, $mode);
if ($ver) {
	local $etc = "$d->{'home'}/etc";
	&unlink_file_as_domain_user($d, "$etc/php.ini");
	&symlink_file_as_domain_user($d, "php".$ver."/php.ini", "$etc/php.ini");
	}
}

# create_php_bin_links(&domain, [php-mode])
# Create a link from ~/bin/php to the PHP CLI for the primary version
sub create_php_bin_links
{
my ($d, $mode) = @_;
return if ($mode eq "none");
my $bindir = $d->{'home'}.'/bin';
&unlink_file_as_domain_user($d, $bindir.'/php');
my ($ver, $cli);
if (($ver = &get_domain_php_version($d, $mode)) &&
    ($cli = &php_command_for_version($ver, 2))) {
	&make_dir_as_domain_user($d, $bindir, 0755);
	&symlink_file_as_domain_user($d, $cli, $bindir.'/php');
	}
}

# find_php_fpm_config(&domain)
# Find known PHP-FPM pools for a domain
sub find_php_fpm_config
{
my ($d) = @_;
my @fpmconfs = &list_php_fpm_configs();
my @rv;
foreach my $fpmconf (@fpmconfs) {
	my $file = $fpmconf->{'dir'}."/".$d->{'id'}.".conf";
	if (-r $file) {
		push(@rv, $fpmconf);
		}
	}
return @rv;
}

# detect_php_fpm_version(&domain)
# Returns PHP-FPM version used by domain or undef if not found or on error
sub detect_php_fpm_version
{ 
my ($d) = @_;
my @dom_vers = map { $_->{'shortversion'} } &find_php_fpm_config($d);
return undef if (@dom_vers > 1); # Return error if more than one version found
my @vers = map { $_->[0] } &list_available_php_versions($d, 'fpm');
foreach $dom_ver (@dom_vers) {
	if (&indexof($dom_ver, @vers) >= 0) {
		return $dom_ver;
		}
	}
return $vers[0] if (@vers && @vers == 1); # Return the only available version
return undef;
}

# get_php_fpm_config([version|&domain])
# Returns the first valid FPM config for a domain
sub get_php_fpm_config
{
my ($ver) = @_;
if (ref($ver)) {
	$ver = $ver->{'php_fpm_version'};
	}
my @confs = grep { !$_->{'err'} } &list_php_fpm_configs();
if ($ver) {
	@confs = grep { $_->{'version'} eq $ver ||
			$_->{'shortversion'} eq $ver } @confs;
	}
return @confs ? $confs[0] : undef;
}

# get_php_fpm_config_file(&domain)
# Returns the FPM pool config file for a domain
sub get_php_fpm_config_file
{
my ($d) = @_;
my $conf = &get_php_fpm_config($d);
return undef if (!$conf);
return $conf->{'dir'}."/".$d->{'id'}.".conf";
}

# list_php_fpm_configs()
# Returns hash refs with details of the system's php-fpm configurations. Assumes
# use of standard packages.
sub list_php_fpm_configs
{
if ($php_fpm_config_cache) {
	return @$php_fpm_config_cache;
	}

# What version packages are installed?
return ( ) if (!&foreign_installed("software"));
&foreign_require("software");
return ( ) if (!defined(&software::package_info));
my @rv;
my %donever;

# Get all interesting packages
my @pkgnames = ("php-fpm",
		(map { "php${_}-fpm" } @all_possible_short_php_versions),
		(map { my $v = $_; $v =~ s/\.//g;
		     ("php${v}-php-fpm", "php${v}-fpm", "php${v}w-fpm",
			   "rh-php${v}-php-fpm", "php${_}-fpm",
			   "php${v}u-fpm") } @all_possible_php_versions));
if (&get_webmin_version() >= 1.985 ||
    $software::config{'package_system'} eq 'debian') {
	&software::list_packages(@pkgnames);
	}
else {
	&software::list_packages();
	}
my %pkgs;
for(my $i=0; $software::packages{$i,'name'}; $i++) {
	$pkgs{$software::packages{$i,'name'}} = [
		$software::packages{$i,'name'},
		$software::packages{$i,'class'},
		$software::packages{$i,'desc'},
		$software::packages{$i,'arch'},
		$software::packages{$i,'version'} ];
	}

foreach my $pname (@pkgnames) {
	my $pinfo = $pkgs{$pname};
	next if (!$pinfo);

	# The php-fpm package on Ubuntu is just a meta-package
	if ($pname eq "php-fpm" && $pinfo->[3] eq "all" &&
	    $gconfig{'os_type'} eq 'debian-linux') {
		next;
		}

	# Normalize the version
	my $rv = { 'package' => $pname };
	$rv->{'version'} = $pinfo->[4];
	$rv->{'version'} =~ s/\-.*$//;
	$rv->{'version'} =~ s/\+.*$//;
	$rv->{'version'} =~ s/^\d+://;
	next if ($donever{$rv->{'version'}}++);
	$rv->{'shortversion'} = $rv->{'version'};
	$rv->{'shortversion'} =~ s/^(\d+\.\d+)\..*/$1/;  # Reduce version to 5.x
	if (($pname eq "php-fpm" || $pname eq "php5-fpm") &&
	    $rv->{'shortversion'} =~ /^5/) {
		# For historic reasons, we just use the version number '5' for
		# the first PHP 5.x version on the system.
		$rv->{'shortversion'} = 5;
		}
	$rv->{'pkgversion'} = $rv->{'shortversion'};
	$rv->{'pkgversion'} =~ s/\.//g;
	push(@rv, $rv);

	# Config directory for per-domain pool files
	my @verdirs;
	DIR: foreach my $cdir ("/etc/php-fpm.d",
			       "/etc/php*/fpm/pool.d",
			       "/etc/php*/fpm/php-fpm.d",
			       "/etc/php/*/fpm/pool.d",
			       "/etc/opt/remi/php*/php-fpm.d",
			       "/etc/opt/rh/rh-php*/php-fpm.d",
			       "/usr/local/etc/php-fpm.d") {
		foreach my $realdir (glob($cdir)) {
			if ($realdir && -d $realdir) {
				my @files = glob("$realdir/*");
				if (@files) {
					push(@verdirs, $realdir);
					}
				}
			}
		}
	if (!@verdirs) {
		$rv->{'err'} = $text{'php_fpmnodir'};
		next;
		}
	my ($bestdir) = grep { /(php|\/)\Q$rv->{'version'}\E\// ||
			       /(php|\/)\Q$rv->{'pkgversion'}\E\// ||
			       /(php|\/)\Q$rv->{'shortversion'}\E\// } @verdirs;
	$bestdir ||= $verdirs[0];
	$rv->{'dir'} = $bestdir;

	# Init script for this version
	&foreign_require("init");
	my $shortver = $rv->{'version'};
	$shortver =~ s/^(\d+\.\d+)\..*/$1/g;
	my $nodot = $shortver;
	$nodot =~ s/\.//g;
	foreach my $init ("php${shortver}-fpm",
			  "php-fpm${shortver}",
			  "rh-php${nodot}-php-fpm",
			  "php${nodot}-php-fpm") {
		my $st = &init::action_status($init);
		if ($st) {
			$rv->{'init'} = $init;
			$rv->{'enabled'} = $st > 1;
			last;
			}
		}
	if (!$rv->{'init'}) {
		# Init script for any version as a fallback
		my @nodot = map { my $u = $_; $u =~ s/\.//g; $u }
				@all_possible_php_versions;
		foreach my $init ("php-fpm",
				  (map { "php${_}-fpm" }
				       @all_possible_short_php_versions),
				  (map { "php${_}-fpm" }
				       @all_possible_php_versions),
				  (map { "rh-php${_}-php-fpm" } @nodot),
				  (map { "php${_}-php-fpm" } @nodot)) {
			my $st = &init::action_status($init);
			if ($st) {
				$rv->{'init'} = $init;
				$rv->{'enabled'} = $st > 1;
				last;
				}
			}
		}
	if (!$rv->{'init'}) {
		$rv->{'err'} = $text{'php_fpmnoinit2'};
		next;
		}

	# Apache modules
	if ($config{'web'}) {
		&require_apache();
		if (!$apache::httpd_modules{'mod_proxy'}) {
			$rv->{'err'} = &text('php_fpmnomod', 'mod_proxy');
			}
		}
	}

# If FPM was setup without a package or init script, also allow it
if ($config{'php_fpm_cmd'} && -x $config{'php_fpm_cmd'} &&
    $config{'php_fpm_pool'} && -d $config{'php_fpm_pool'}) {
	my $rv = { 'cmd' => $config{'php_fpm_cmd'},
		   'fromconfig' => 1,
		   'init' => $config{'php_fpm_init'},
		   'dir' => $config{'php_fpm_pool'},
		 };
	$rv->{'version'} = &get_php_version($rv->{'cmd'});
	$rv->{'shortversion'} = $rv->{'version'};
	$rv->{'shortversion'} =~ s/^(\d+\.\d+)\..*/$1/;  # Reduce version to 5.x
	if ($rv->{'init'}) {
		my $st = &init::action_status($rv->{'init'});
		if ($st == 0) {
			$rv->{'err'} = &text('php_fpmnoinit3', $rv->{'init'});
			}
		elsif ($st == 2) {
			$rv->{'enabled'} = 1;
			}
		}
	push(@rv, $rv);
	}

$php_fpm_config_cache = \@rv;
return @rv;
}

# get_php_fpm_socket_file(&domain, [dont-make-dir])
# Returns the path to the default per-domain PHP-FPM socket file. Creates the
# directory if needed.
sub get_php_fpm_socket_file
{
my ($d, $nomkdir) = @_;
# Universal FPM socket dir
my $base = "/var/php-fpm";
# Accommodate old styles in read only mode
my $basefile = $base."/".$d->{'id'}.".sock";
return $basefile if (-r $basefile);
# Distro dependent FPM socket dirs (if exists)
my $rhelbase = "/run/php-fpm";
my $debbase = "/run/php";
if ($config{'fpm_socket_dir'}) {
	$base = $config{'fpm_socket_dir'};
	}
elsif (-d $rhelbase && $gconfig{'os_type'} eq 'redhat-linux') {
	$base = $rhelbase;
	}
elsif (-d $debbase && $gconfig{'os_type'} eq 'debian-linux') {
	$base = $debbase;
	}
if (!-d $base && !$nomkdir) {
	&make_dir($base, 0755);
	}
return $base."/".$d->{'id'}.".sock";
}

# get_php_fpm_socket_port(&domain)
# Selects a dynamic port number for a per-domain PHP FPM socket
sub get_php_fpm_socket_port
{
my ($d) = @_;
if ($d->{'php_fpm_port'}) {
	# Already chosen
	return $d->{'php_fpm_port'};
	}
my %used = map { $_->{'php_fpm_port'}, $_ }
	       grep { $_->{'php_fpm_port'} } &list_domains();
my $base = $config{'php_fpm_port'} || 8000;
my $rv = &allocate_free_tcp_port(\%used, $base);
$rv || &error("Failed to allocate FPM port starting at $base");
$d->{'php_fpm_port'} = $rv;
return $rv;
}

# get_domain_php_fpm_port(&domain)
# Returns a status code (0=error, 1=port, 2=file) and the actual TCP port or
# socket file used for FPM
sub get_domain_php_fpm_port
{
my ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne 'web') {
	if (!&plugin_defined($p, "feature_get_domain_php_fpm_port")) {
		return (-1, "Not supported by plugin $p");
		}
	return &plugin_call($p, "feature_get_domain_php_fpm_port", $d);
	}

# Find the Apache virtualhost
&require_apache();
my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
						$d->{'web_port'});
return (0, "No Apache virtualhost found") if (!$virt);

# What port is Apache on?
my $webport;
foreach my $p (&apache::find_directive("ProxyPassMatch", $vconf)) {
	if ($p =~ /fcgi:\/\/localhost:(\d+)/ ||
	    $p =~ /fcgi:\/\/127\.0\.0\.1:(\d+)/ ||
	    $p =~ /unix:([^\|]+)/) {
		$webport = $1;
		}
	}
foreach my $f (&apache::find_directive_struct("FilesMatch", $vconf)) {
	next if ($f->{'words'}->[0] ne '\.php$');
	foreach my $h (&apache::find_directive("SetHandler",
					       $f->{'members'})) {
		if ($h =~ /proxy:fcgi:\/\/localhost:(\d+)/ ||
		    $h =~ /proxy:fcgi:\/\/127\.0\.0\.1:(\d+)/ ||
		    $h =~ /proxy:unix:([^\|]+)/) {
			my $webport2 = $1;
			if ($webport && $webport != $webport2) {
				return (0, "Port $webport in ProxyPassMatch ".
					   "is different from port $webport2 ".
					   "in FilesMatch");
				}
			$webport ||= $webport2;
			}
		}
	}
return (0, "No FPM SetHandler or ProxyPassMatch directive found")
	if (!$webport);

# Which port is the FPM server actually using?
my $fpmport;
my $listen = &get_php_fpm_config_value($d, "listen");
if ($listen =~ /^\S+:(\d+)$/ ||
    $listen =~ /^(\d+)$/ ||
    $listen =~ /^(\/\S+)$/) {
	$fpmport = $1;
	}
return (0, "No listen directive found in FPM config") if (!$fpmport);

if ($fpmport ne $webport) {
	return (0, "Apache config port $webport does not ".
		   "match FPM config $fpmport");
	}
return ($fpmport =~ /^\d+$/ ? 1 : 2, $fpmport);
}

# save_domain_php_fpm_port(&domain, port|socket)
# Update the TCP port or socket used for FPM for a domain. Returns undef on
# success or an error message on failure.
sub save_domain_php_fpm_port
{
my ($d, $socket) = @_;
my $p = &domain_has_website($d);
if ($p ne 'web') {
	if (!&plugin_defined($p, "feature_save_domain_php_fpm_port")) {
		return "Not supported by plugin $p";
		}
	return &plugin_call($p, "feature_save_domain_php_fpm_port", $d,$socket);
	}

# First update the Apache config
&require_apache();
&obtain_lock_web($d);
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $found = 0;
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	foreach my $f (&apache::find_directive_struct("FilesMatch", $vconf)) {
		next if ($f->{'words'}->[0] ne '\.php$');
		my @sh = &apache::find_directive("SetHandler",
                                                 $f->{'members'});
		for(my $i=0; $i<@sh; $i++) {
			if ($sh[$i] =~ /proxy:fcgi:\/\/localhost:(\d+)/ ||
			    $sh[$i] =~ /proxy:fcgi:\/\/127\.0\.0\.1:(\d+)/ ||
			    $sh[$i] =~ /proxy:unix:([^\|]+)/) {
				# Found the directive to update
				if ($socket =~ /^\d+$/) {
					$sh[$i] = "proxy:fcgi://127.0.0.1:".$socket;
					}
				else {
					$sh[$i] = "proxy:unix:".$socket.
						  "|fcgi://127.0.0.1";
					}
				$found++;
				}
			}
		&apache::save_directive(
			"SetHandler", \@sh, $f->{'members'}, $conf);
		&flush_file_lines($virt->{'file'});
		}
	}
&release_lock_web($d);
$found || return "No Apache VirtualHost containing an FPM SetHandler found";

# Second update the FPM server port
my $conf = &get_php_fpm_config($d);
&save_php_fpm_config_value($d, "listen", $socket);
if ($socket =~ /^\//) {
	# Also set correct owner for the file if switching to socket mode
	&save_php_fpm_config_value($d, "listen.owner", $d->{'user'});
	&save_php_fpm_config_value($d, "listen.group", $d->{'ugroup'});
	}
&register_post_action(\&restart_php_fpm_server, $conf, $d->{'id'});
&register_post_action(\&restart_apache);

return undef;
}

# check_php_fpm_port_clash(&domain)
# Checks if any other FPM pool is using the same port or socket,
# and if so returns it and the port number or socket file name
sub check_php_fpm_port_clash
{
my ($d) = @_;
my (undef, $port) = &get_domain_php_fpm_port($d);
my $dconf = &get_php_fpm_config($d);
my @fpms = &list_php_fpm_configs();
foreach my $conf (@fpms) {
	my @pools = &list_php_fpm_pools($conf);
	foreach my $p (@pools) {
		next if ($p eq $d->{'id'} &&
			 $conf->{'version'} eq $dconf->{'version'});
		my $t = get_php_fpm_pool_config_value($conf, $p, "listen");
		next if (!$t);
		$t =~ s/^\S+:(\d+)$/$1/g;	# Remove listen:
		if ($t eq $port) {
			my $otherid = $port =~ /\/(\d+)\.sock/ ? $1 : undef;
			return ($p, $conf, $port, $otherid);
			}
		}
	}
return ();
}

# list_php_fpm_pools(&conf)
# Returns a list of all pool IDs for some FPM config
sub list_php_fpm_pools
{
my ($conf) = @_;
my @rv;
opendir(DIR, $conf->{'dir'});
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(\S+)\.conf$/) {
		push(@rv, $1);
		}
	}
closedir(DIR);
return @rv;
}

# create_php_fpm_pool(&domain, [force-listen])
# Create a per-domain pool config file
sub create_php_fpm_pool
{
my ($d, $forcelisten) = @_;
my $tmpl = &get_template($d->{'template'});
my $conf = &get_php_fpm_config($d);
return $text{'php_fpmeconfig'} if (!$conf);
my $file = $conf->{'dir'}."/".$d->{'id'}.".conf";
my $oldlisten = $forcelisten || &get_php_fpm_config_value($d, "listen");
my $mode;
if ($oldlisten) {
	$mode = $oldlisten =~ /^\// ? 1 : 0;
	}
else {
	$mode = $tmpl->{'php_sock'};
	}
my $port;
if ($mode) {
	$port = $oldlisten || &get_php_fpm_socket_file($d);
	}
else {
	$port = &get_php_fpm_socket_port($d);
	}
$port = "127.0.0.1:".$port if ($port =~ /^\d+$/);
&lock_file($file);
if (-r $file) {
	# Fix up existing one, in case user or group changed
	&save_php_fpm_config_value($d, "user", $d->{'user'});
	&save_php_fpm_config_value($d, "group", $d->{'ugroup'});
	&save_php_fpm_config_value($d, "listen", $port);
	if (&get_php_fpm_config_value($d, "listen.owner")) {
		&save_php_fpm_config_value($d, "listen.owner", $d->{'user'});
		&save_php_fpm_config_value($d, "listen.group", $d->{'ugroup'});
		}
	}
else {
	# Create a new file
	my $tmpl = &get_template($d->{'template'});
	my $defchildren = $tmpl->{'web_phpchildren'};
	if ($defchildren eq "none" || !$defchildren) {
		$defchildren = get_php_max_childred_allowed();
		}
	my $defmaxspare = get_php_max_spare_servers($defchildren);
	my $defstartservers = get_php_start_servers($defchildren);
	local $tmp = &create_server_tmp($d);
	my $lref = &read_file_lines($file);
	@$lref = ( "[$d->{'id'}]",
		   "user = ".$d->{'user'},
		   "group = ".$d->{'ugroup'},
		   "listen.owner = ".$d->{'user'},
		   "listen.group = ".$d->{'ugroup'},
		   "listen.mode = 0660",
		   "listen = ".$port,
		   "pm = dynamic", 
		   "pm.max_children = $defchildren",
		   "pm.start_servers = $defstartservers",
		   "pm.min_spare_servers = 1",
		   "pm.max_spare_servers = $defmaxspare",
	   	   "php_value[upload_tmp_dir] = $tmp",
		   "php_value[session.save_path] = $tmp" );
	&flush_file_lines($file);

	# Add / override custom options (with substitution)
	if ($tmpl->{'php_fpm'} ne 'none') {
		foreach my $l (split(/\t+/,
		    &substitute_domain_template($tmpl->{'php_fpm'}, $d))) {
			next if ($l !~ /^\s*(\S+)\s*=\s*(.*)/);
			my ($n, $v) = ($1, $2);
			&save_php_fpm_config_value($d, $n, $v);
			}
		}
	}
my $parent = $d->{'parent'} ? &get_domain_by($d->{'parent'}) : $d;
if ($parent->{'jail'}) {
	my $dir = &get_domain_jailkit($parent);
	&save_php_fpm_config_value($d, "chroot", $dir);
	}
&unlock_file($file);
if ($port =~ /^\// && !-e $port) {
	# Pre-create the socket file
	open(TOUCH, ">$port");
	close(TOUCH);
	&set_ownership_permissions($d->{'user'}, $d->{'ugroup'}, 0660, $port);
	}
&register_post_action(\&restart_php_fpm_server, $conf, $d->{'id'}, 1);
return undef;
}

# delete_php_fpm_pool(&domain)
# Remove the per-domain pool configuration file
sub delete_php_fpm_pool
{
my ($d) = @_;
my @fpms = &list_php_fpm_configs();
my $found = 0;
foreach my $conf (@fpms) {
	my @pools = &list_php_fpm_pools($conf);
	foreach my $p (@pools) {
		next if ($p ne $d->{'id'});
		my $file = $conf->{'dir'}."/".$d->{'id'}.".conf";
		next if (!-r $file);
		&unlink_logged($file);
		&unflush_file_lines($file);
		my $sock = &get_php_fpm_socket_file($d, 1);
		&unlink_logged($sock) if (-r $sock);
		&register_post_action(
			\&restart_php_fpm_server, $conf, $d->{'id'}, 1);
		}
	}
}

# restart_php_fpm_server([&config, domain-id, force-restart])
# Post-action script to reload or restart the server
sub restart_php_fpm_server
{
my ($conf, $id, $restart) = @_;
$conf ||= &get_php_fpm_config();
my $action_mode = $conf->{'init'} ? &init::get_action_mode($conf->{'init'})
				  : $init::init_mode;
my $listen = $id ? &get_php_fpm_pool_config_value($conf, $id, "listen")
		 : undef;
my $reload = !$restart &&
	     $action_mode eq "systemd" &&
	     ($listen !~ /^\// || -e $listen);
if ($reload) {
	&$first_print(&text('php_fpmreload', $conf->{'shortversion'}));
	}
else {
	&$first_print(&text('php_fpmrestart', $conf->{'shortversion'}));
	}
if ($conf->{'init'}) {
	&foreign_require("init");
	my ($ok, $err);
	if ($reload) {
		($ok, $err) = &init::reload_action($conf->{'init'});
		if (!$ok && $err =~ /Not\s+implemented/i) {
			($ok, $err) = &init::restart_action($conf->{'init'});
			}
		}
	else {
		($ok, $err) = &init::restart_action($conf->{'init'});
		}
	if ($ok) {
		&$second_print($text{'setup_done'});
		return 1;
		}
	else {
		&$second_print(&text('php_fpmeinit', $err));
		return 0;
		}
	}
else {
	&$second_print($text{'php_fpmnoinit'});
	return 0;
	}
}

# get_php_fpm_config_value(&domain, name)
# Returns the value of a config setting from the domain's pool file
sub get_php_fpm_config_value
{
my ($d, $name) = @_;
my $conf = &get_php_fpm_config($d);
return undef if (!$conf);
return &get_php_fpm_pool_config_value($conf, $d->{'id'}, $name);
}

# list_php_fpm_config_values(&domain)
# Returns an array ref of name/value pairs from the FPM config for a domain
sub list_php_fpm_config_values
{
my ($d) = @_;
my $conf = &get_php_fpm_config($d);
return undef if (!$conf);
return &list_php_fpm_pool_config_values($conf, $d->{'id'});
}

# get_php_fpm_pool_config_value(&conf, domain-id, name)
# Returns the value of a config setting from any pool file
sub get_php_fpm_pool_config_value
{
my ($conf, $id, $name) = @_;
my $file = $conf->{'dir'}."/".$id.".conf";
my $lref = &read_file_lines($file, 1);
foreach my $l (@$lref) {
	if ($l =~ /^\s*(\S+)\s*=\s*(.*)/ && $1 eq $name) {
		return $2;
		}
	}
return undef;
}

# list_php_fpm_pool_config_values(&conf, domain-id)
# Returns an array ref of name/value pairs from the FPM config
sub list_php_fpm_pool_config_values
{
my ($conf, $id) = @_;
my $file = $conf->{'dir'}."/".$id.".conf";
return &list_php_fpm_file_config_values($file);
}

# list_php_fpm_file_config_values(file)
# Returns an array ref of name/value pairs from an FPM pool file
sub list_php_fpm_file_config_values
{
my ($file) = @_;
my $lref = &read_file_lines($file, 1);
my @rv;
foreach my $l (@$lref) {
	if ($l =~ /^\s*(\S+)\s*=\s*(.*)/) {
		push(@rv, [ $1, $2 ]);
		}
	}
return \@rv;
}

# get_php_fpm_ini_value(&domain, name)
# Returns the value of a PHP ini setting from the domain's pool file
sub get_php_fpm_ini_value
{
my ($d, $name) = @_;
my $k = "php_value";
my $rv = &get_php_fpm_config_value($d, "php_value[${name}]");
if (!defined($rv)) {
	my $k = "php_admin_value";
	$rv = &get_php_fpm_config_value($d, "php_admin_value[${name}]");
	if (!defined($rv)) {
		$k = undef;
		}
	}
return wantarray ? ($rv, $k) : $rv;
}

# list_php_fpm_ini_values(&domain)
# Returns an array ref of name/value/admin triplets for FPM PHP ini settings
sub list_php_fpm_ini_values
{
my ($d) = @_;
my $all = &list_php_fpm_config_values($d);
return undef if (!$all);
my @rv;
foreach my $c (@$all) {
	if ($c->[0] =~ /^(php_value|php_admin_value)\[(\S+)\]$/) {
		push(@rv, [ $2, $c->[1], $1 eq "php_admin_value" ? 1 : 0 ]);
		}
	}
return \@rv;
}

# save_php_fpm_config_value(&domain, name, value)
# Adds, updates or deletes an config setting in the domain's pool file
sub save_php_fpm_config_value
{
my ($d, $name, $value) = @_;
my $conf = &get_php_fpm_config($d);
return 0 if (!$conf);
return &save_php_fpm_pool_config_value($conf, $d->{'id'}, $name, $value);
}

# save_php_fpm_pool_config_value(&conf, id, name, value)
# Adds, updates or deletes an config setting in a pool file
sub save_php_fpm_pool_config_value
{
my ($conf, $id, $name, $value) = @_;
my $file = $conf->{'dir'}."/".$id.".conf";
return if (!-r $file);
&lock_file($file);
my $lref = &read_file_lines($file);
my $found = -1;
my $lnum = 0;
foreach my $l (@$lref) {
	if ($l =~ /^\s*(\S+)\s*=\s*(.*)/ && $1 eq $name) {
		$found = $lnum;
		last;
		}
	$lnum++;
	}
if ($found >= 0 && defined($value)) {
	# Update existing line
	$lref->[$found] = "$name = $value";
	}
elsif ($found >=0 && !defined($value)) {
	# Remove existing line
	splice(@$lref, $found, 1);
	}
elsif ($found < 0 && defined($value)) {
	# Need to add new line
	push(@$lref, "$name = $value");
	}
&flush_file_lines($file);
&unlock_file($file);
&register_post_action(\&restart_php_fpm_server, $conf, $id);
return 1;
}

# save_php_fpm_ini_value(&domain, name, value, [admin?])
# Adds, updates or deletes an ini setting in the domain's pool file
sub save_php_fpm_ini_value
{
my ($d, $name, $value, $admin) = @_;
my (undef, $k) = &get_php_fpm_ini_value($d, $name);
$k ||= ($admin ? "php_admin_value" : "php_value");
return &save_php_fpm_config_value($d, $k."[".$name."]", $value);
}

# increase_fpm_port(string)
# Increase the number in a port string
sub increase_fpm_port
{
my ($t) = @_;
if ($t =~ /^(\d+)$/) {
	return $t + 1;
	}
elsif ($t =~ /^(.*):(\d+)$/) {
	return $1.":".($2 + 1);
	}
return undef;
}

# get_apache_mod_php_version()
# If Apache has mod_phpX installed, return the version number
sub get_apache_mod_php_version
{
return $apache_mod_php_version_cache if ($apache_mod_php_version_cache);
&require_apache();
my $major = $apache::httpd_modules{'mod_php5'} ? 5 :
            $apache::httpd_modules{'mod_php7'} ? "7.0" : undef;
return undef if (!$major);
foreach my $php ("php$major", "php") {
	next if (!&has_command($php));
	&clean_environment();
	my $out = &backquote_command("$php -v 2>&1 </dev/null");
	&reset_environment();
	if ($out =~ /PHP\s+(\d+\.\d+)/) {
		$major = $1;
		last;
		}
	}
$apache_mod_php_version_cache = $major;
return $major;
}

# cleanup_php_sessions(&domain, dry-run)
# Remove old PHP session files for some domain
sub cleanup_php_sessions
{
my ($d, $dryrun) = @_;
my $tmp;
my $mode = &get_domain_php_mode($d);
if ($mode eq "fpm") {
	# Find the session files dir from PHP-FPM config
	$tmp = &get_php_fpm_ini_value($d, "session.save_path");
	}
else {
	# Find the session files dir from PHP ini config
	my $etc = "$d->{'home'}/etc";
	&foreign_require("phpini");
	my $pconf = &phpini::get_config("$etc/php.ini");
	$tmp = &phpini::find_value("session.save_path", $pconf);
	}

# Default to ~/tmp
$tmp ||= $d->{'home'}."/tmp";

# Look for session files that are too old
my $days = $config{'php_session_age'} || 7;
my $cutoff = time() - $days * 24 * 60 * 60;
my @rv;
opendir(DIR, $tmp) || return ();
foreach my $f (readdir(DIR)) {
	next if ($f !~ /^sess_/);
	my @st = stat($tmp."/".$f);
	next if (!@st);
	if ($st[9] < $cutoff) {
		push(@rv, $tmp."/".$f);
		}
	}
closedir(DIR);

# Delete any found
if (!$dryrun) {
	&unlink_file_as_domain_user($d, @rv);
	}
return @rv;
}

# get_php_max_childred_allowed()
# Get PHP-FPM recommended allowed number for sub-processes,
# which is calculated as total available RAM devided by
# 64 MiB (aprox. cunsumed by each PHP-FPM process) and 
# devided by 4 (as we assume that a maximum recommended 
# default which PHP can use is 20% of all available RAM
# on the system). However, manually it will be possible
# to rase the number to use all available RAM as defined
# using `$max_php_fcgid_children` variable. Also on systems
# with a lot of RAM limit maximum recommended to sensible 16.
sub get_php_max_childred_allowed
{
return $main::get_real_memory_size_cache
	if (defined($main::get_real_memory_size_cache));
my $max;
my $mem = &get_real_memory_size();
if ($mem) {
	my $sysram_mb = $mem / 1024 / 1024;
	$max = int(($sysram_mb / 64) / 5);
	if ($max > 16) {
		$max = 16;
		}
	}
else {
 	$max = $max_php_fcgid_children;
	}

# Low memory systems should not
# return values lower than 1
$max ||= 1;
$main::get_real_memory_size_cache = $max;
return int($max);
}

sub get_php_max_spare_servers
{
my ($defchildren) = @_;
my $defmaxspare = $defchildren <= 1 ? $defchildren :
        $defchildren >= 4 ? int($defchildren / 2) : 2;
return int($defmaxspare);
}

sub get_php_start_servers
{
my ($defchildren) = @_;
my $min_spare_servers = 1;
my $max_spare_servers = get_php_max_spare_servers($defchildren);
my $start_servers = $min_spare_servers + ($max_spare_servers - $min_spare_servers) / 4;
return int($start_servers) || 1;
}

# get_domain_php_error_log(&domain)
# Returns the PHP error log for a domain, from it's php.ini file. Return a path
# if set, an empty string if unset, or undef if it's not possible to set.
sub get_domain_php_error_log
{
my ($d) = @_;
my $mode = &get_domain_php_mode($d);
my $phplog;
if ($mode eq "fpm") {
	$phplog = &get_php_fpm_ini_value($d, "error_log") || "";
	}
elsif ($mode ne "none" && $mode ne "mod_php") {
	$phplog = "";
	&foreign_require("phpini");
	foreach my $i (&list_domain_php_inis($d)) {
		my $pconf = &phpini::get_config($i->[1]);
		$phplog = &phpini::find_value("error_log", $pconf);
		last if ($phplog);
		}
	}
else {
	return undef;
	}
if ($phplog && $phplog !~ /^\//) {
	$phplog = $d->{'home'}.'/'.$phplog;
	}
return $phplog;
}

# save_domain_php_error_log(&domain, [logfile])
# Set or remove the PHP error log file for a domain in its php.ini file
sub save_domain_php_error_log
{
my ($d, $phplog) = @_;
$phplog = undef if (!$phplog);
my $oldd = { %$d };
my $mode = &get_domain_php_mode($d);
my $p = &domain_has_website($d);
if ($mode eq "fpm") {
	&save_php_fpm_ini_value($d, "error_log", $phplog, 0);
	my $loge = &get_php_fpm_ini_value($d, "log_errors");
	if (lc($loge) ne "on") {
		&save_php_fpm_ini_value($d, "log_errors", "On", 0);
		}
	}
elsif ($mode ne "none" && $mode ne "mod_php") {
	&foreign_require("phpini");
	foreach my $i (&list_domain_php_inis($d)) {
		&lock_file($i->[1]);
		my $pconf = &phpini::get_config($i->[1]);
		&phpini::save_directive($pconf, "error_log", $phplog);
		my $loge = &phpini::find_value("log_errors", $pconf);
		if (lc($loge) ne "on") {
			&phpini::save_directive($pconf, "log_errors", "On");
			}
		&flush_file_lines($i->[1], undef, 1);
		&unlock_file($i->[1]);
		}
	}
else {
	return "PHP error log cannot be set in $mode mode";
	}
&register_php_restart_action($d);
$d->{'php_error_log'} = $phplog || "";
if ($phplog && !-r $phplog) {
	# Make sure the log file exists
	&open_tempfile_as_domain_user($d, PHPLOG, ">$phplog", 1, 1);
	&close_tempfile_as_domain_user($d, PHPLOG);
	}
&push_all_print();
&set_all_null_print();
&modify_logrotate($d, $oldd);
&pop_all_print();
return undef;
}

# register_php_restart_action(&domain)
# Register an action to restart any PHP server for a domain
sub register_php_restart_action
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq "web") {
	my $mode = &get_domain_php_mode($d);
	if ($mode eq "fcgid") {
		&register_post_action(\&restart_apache);
		}
	elsif ($mode eq "fpm") {
		my $conf = &get_php_fpm_config($d);
		&register_post_action(\&restart_php_fpm_server, $conf, $d->{'id'});
		}
	}
else {
	&register_post_action(\&plugin_call, $p, "feature_restart_web_php", $d);
	}
}

# can_php_error_log(&domain|mode)
# Returns 1 if the PHP error log can be set for a domain or PHP mode
sub can_php_error_log
{
my ($mode) = @_;
$mode = &get_domain_php_mode($mode) if (ref($mode));
return $mode ne "none" && $mode ne "mod_php";
}

# get_default_php_error_log(&domain)
# Returns the default PHP log path for a domain, based on the template
sub get_default_php_error_log
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
my $path = $tmpl->{'php_log_path'} || "logs/php_log";
$path = &substitute_domain_template($path, $d);
$path = $d->{'home'}.'/'.$path if ($path !~ /^\//);
return $path;
}

# copyable_fpm_configs(&conf)
# Returns only FPM configs that should be copied when changing version,
# cloning or restoring a backup
sub copyable_fpm_configs
{
my ($confs) = @_;
my @rv;
foreach my $pv (@$confs) {
	push(@rv, $pv) if ($pv->[0] =~ /^(php_value|php_admin_value|env)\[/ ||
		           $pv->[0] eq 'pm' || $pv->[0] =~ /^pm\./);
	}
return @rv;
}

# setup_web_for_php(&domain, &script, php-version)
# Update a virtual server's web config to add any PHP settings from the template and optionally from a script
sub setup_web_for_php
{
my ($d, $script, $phpver) = @_;
$phpver ||= &get_domain_php_version($d);
my $tmpl = &get_template($d->{'template'});
my $varstr = &substitute_domain_template($tmpl->{'php_vars'}, $d);
my @tmplphpvars = $varstr eq 'none' ? ( ) : split(/\t+/, $varstr);

# Find PHP variables from template and from script
my @todo;
foreach my $pv (@tmplphpvars) {
	my ($n, $v) = split(/=/, $pv, 2);
	my $diff = $n =~ s/^(\+|\-)// ? $1 : undef;
	push(@todo, [ $n, $v, $diff ]);
	}
if ($script && defined(&{$script->{'php_vars_func'}})) {
	push(@todo, &{$script->{'php_vars_func'}}($d));
	}

# Always set the session.save_path to ~/tmp, as on some systems
# it is set by default to a directory only writable by Apache
push(@todo, [ 'session.save_path', &create_server_tmp($d) ]);

# Magic quotes directive not supported in PHP 5.4
if ($phpver) {
	my $realver = &get_php_version($phpver, $d);
	if ($realver >= 5.4) {
		@todo = grep { $_->[0] ne "magic_quotes_gpc" } @todo;
		}
	}

return &set_multiple_php_vars($d, \@todo, $phpver);
}

# set_multiple_php_vars(&domain, &variable-list, [php-version])
# Update the appropriate mod_php, php.ini and FPM configs to set variables
sub set_multiple_php_vars
{
my ($d, $todo, $phpver) = @_;
$phpver ||= &get_domain_php_version($d);
my $p = &domain_has_website($d);
my $any = 0;

if ($p eq "web" && &get_apache_mod_php_version()) {
	# Add the PHP variables to the domain's <Virtualhost> in Apache config
	&require_apache();
	my $conf = &apache::get_config();
	my @ports;
	push(@ports, $d->{'web_port'}) if ($d->{'web'});
	push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
	foreach my $port (@ports) {
		my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		next if (!$virt);

		# Find currently set PHP variables
		my @phpv = &apache::find_directive("php_value", $vconf);
		my %got;
		foreach my $p (@phpv) {
			if ($p =~ /^(\S+)/) {
				$got{$1}++;
				}
			}

		# Update or add PHP variables
		foreach my $t (@$todo) {
			my ($n, $v, $diff) = @$t;
			if (!$got{$n}) {
				push(@phpv, "$n $v");
				$changed++;
				}
			}

		# Update directives if needed
		if ($changed) {
			&apache::save_directive("php_value",
						\@phpv, $vconf, $conf);
			&register_post_action(\&restart_apache);
			$any += $changed;
			}
		&flush_file_lines();
		}
	}

my $phpini = &get_domain_php_ini($d, $phpver);
if ($phpini && -r $phpini && &foreign_check("phpini")) {
	# Add the variables to the domain's php.ini file. Start by finding
	# the variables already set, including those that are commented out.
	&foreign_require("phpini");
	my $conf = &phpini::get_config($phpini);
	my $anyini;

	# Make any needed changes. Variables can be either forced to a
	# particular value, or have maximums or minumums
	foreach my $t (@$todo) {
		my ($n, $v, $diff) = @$t;
		my $ov = &phpini::find_value($n, $conf);
		my $change = $diff eq '' && $ov ne $v ||
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
		}
	}

my $mode = &get_domain_php_mode($d);
if ($mode eq "fpm") {
	# Update PHP ini values in FPM config file as well
	foreach my $t (@$todo) {
		my ($n, $v, $diff) = @$t;
		my $ov = &get_php_fpm_ini_value($d, $n);
		my $change = $diff eq '' && $ov ne $v ||
				$diff eq '+' && &php_value_diff($ov, $v) < 0 ||
				$diff eq '-' && &php_value_diff($ov, $v) > 0;
		if ($change) {
			&save_php_fpm_ini_value($d, $n, $v, 1);
			$any++;
			}
		}
	}

if ($any) {
	&register_php_restart_action($d);
	}
return $any;
}

# php_value_diff(value1, value2)
# Compares two values like 32 and 64 or 8M and 32M. Returns -1 if v1 is < v2,
# +1 if v1 > v2, or 0 if same
sub php_value_diff
{
my ($v1, $v2) = @_;
$v1 = $v1 =~ /^(\d+)k/i ? $1*1024 :
      $v1 =~ /^(\d+)M/i ? $1*1024*1024 :
      $v1 =~ /^(\d+)G/i ? $1*1024*1024*1024 : $v1;
$v2 = $v2 =~ /^(\d+)k/i ? $1*1024 :
      $v2 =~ /^(\d+)M/i ? $1*1024*1024 :
      $v2 =~ /^(\d+)G/i ? $1*1024*1024*1024 : $v2;
return $v1 <=> $v2;
}

# get_php_can_send_mail(&domain)
# Returns 1 if PHP can send email on this domain
sub get_php_can_send_mail
{
my ($d) = @_;
my $mode = &get_domain_php_mode($d);
if ($mode eq "none" || $mode eq "mod_php") {
	return undef;
	}
my $dis;
if ($mode eq "fpm") {
	# Get from FPM pool file
	$dis = &get_php_fpm_ini_value($d, "disable_functions");
	}
else {
	# Get from php.ini
	&foreign_require("phpini");
	my @inis = &list_domain_php_inis($d);
	return undef if (!@inis);
	foreach my $i (@inis) {
		my $pconf = &phpini::get_config($i->[1]);
		$dis = &phpini::find_value("disable_functions", $pconf);
		last if ($dis);
		}
	}
my @dis = split(/\s*,\s*/, $dis);
return &indexof("mail", @dis) >= 0 ? 0 : 1;
}

# save_php_can_send_mail(&domain, can-send)
# Update the PHP config to allow or disallow sending email
sub save_php_can_send_mail
{
my ($d, $canmail) = @_;
my $mode = &get_domain_php_mode($d);
if ($mode eq "none" || $mode eq "mod_php") {
	return $text{'phpmode_esendmode'};
	}
my $dis;
my @inis;
if ($mode eq "fpm") {
	# Get the current value from the FPM pool
	$dis = &get_php_fpm_ini_value($d, "disable_functions");
	}
else {
	# Get the current value from php.ini
	&foreign_require("phpini");
	@inis = &list_domain_php_inis($d);
	foreach my $i (@inis) {
		my $pconf = &phpini::get_config($i->[1]);
		$dis = &phpini::find_value("disable_functions", $pconf);
		last if ($dis);
		}
	}

# Add or remove the mail disable
my @dis = split(/\s*,\s*/, $dis);
my $idx = &indexof("mail", @dis);
if ($idx < 0 && !$canmail) {
	push(@dis, "mail");
	}
elsif ($idx >= 0 && $canmail) {
	splice(@dis, $idx, 1);
	}
$dis = join(",", @dis);

if ($mode eq "fpm") {
	# Update the FPM pool file
	&save_php_fpm_ini_value($d, "disable_functions", $dis || undef, 0);
	}
else {
	# Update all php.ini files
	&foreign_require("phpini");
	@inis || return $text{'phpmode_ephpinis'};
	foreach my $i (@inis) {
		&lock_file($i->[1]);
		my $pconf = &phpini::get_config($i->[1]);
		&phpini::save_directive($pconf, "disable_functions", $dis || undef);
		&flush_file_lines($i->[1], undef, 1);
                &unlock_file($i->[1]);
                }
	}
&register_php_restart_action($d);
return undef;
}

# get_php_info_link(dom, [placement, subdir])
# Returns a link to the PHP info page for a domain.
# If subdir is set, the link will point to a
# specific directory.
sub get_php_info_link
{
my ($dom, $placement, $subdir) = @_;
$placement ||= 'cell';
return "&nbsp;&nbsp;" .
	&ui_link("showphpinfo.cgi?dom=$dom&dir=$subdir",
	&ui_help(&text('phpmode_phpinfo_show' . ($subdir ? '_dir' : ''), $subdir)),
			undef, "target=_blank data-placement=\"$placement\"");
}

1;

