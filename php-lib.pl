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
	local @actions = &apache::find_directive("Action", $vconf);
	local $pdir = &public_html_dir($d);
	local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
			      $_->{'words'}->[0] eq $pdir."/" }
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
	foreach my $a (@actions) {
		if ($a =~ /^application\/x-httpd-php.\s+\/cgi-bin\/php\S+\.cgi/) {
			return 'cgi';
			}
		}
	}
return 'mod_php';
}

# save_domain_php_mode(&domain, mode, [port], [new-domain])
# Changes the method a virtual web server uses to run PHP.
sub save_domain_php_mode
{
local ($d, $mode, $port, $newdom) = @_;
local $p = &domain_has_website($d);
$p || return "Virtual server does not have a website";
local $tmpl = &get_template($d->{'template'});

# Work out source php.ini files
local (%srcini, %subs_ini);
local @vers = &list_available_php_versions($d, $mode);
@vers || &error("No PHP versions found for mode $mode");
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
local $defver = $vers[0]->[0];
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
			$inidata || &error("Failed to read $srcini, ".
					   "or file is empty");
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
			$ok || &error("Failed to copy $srcini to ".
				      "$inidir/php.ini : $err");
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
			&foreign_require("phpini", "phpini-lib.pl");
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

# Link ~/etc/php.ini to the per-version ini file
&create_php_ini_link($d, $mode);

# Call plugin-specific function to perform webserver setup
if ($p ne 'web') {
	return &plugin_call($p, "feature_save_web_php_mode",
			    $d, $mode, $port, $newdom);
	}
&require_apache();

# Create wrapper scripts
if ($mode ne "mod_php") {
	&create_php_wrappers($d, $mode);
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
			$dirstr || &error("No &lt;Directory&gt; section found ",
					  "for mod_fcgid directives");
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
		@actions = grep { $_ !~ /^application\/x-httpd-php\d+/ }
				@actions;
		local @types = &apache::find_directive("AddType", $phpconf);
		@types = grep { $_ !~ /^application\/x-httpd-php\d+/ }
			      @types;

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
		if ($mode eq "cgi" || $mode eq "mod_php") {
			foreach my $v (@avail) {
				push(@types,"application/x-httpd-php$v .php$v");
				}
			}
		if ($mode eq "cgi") {
			push(@types, "application/x-httpd-php$ver .php");
			}
		else {
			push(@types, "application/x-httpd-php .php");
			}
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
	&apache::save_directive("RemoveHandler", \@remove, $vconf, $conf);

	# For non-mod_php mode, use php_admin_value to turn off mod_php in
	# case it gets enabled in a .htaccess file
	if ($apache::httpd_modules{'mod_php4'} ||
	    $apache::httpd_modules{'mod_php5'}) {
		local @admin = &apache::find_directive("php_admin_value",
						       $vconf);
		@admin = grep { !/^engine\s+/ } @admin;
		if ($mode ne "mod_php" && !$config{'allow_modphp'}) {
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
				&foreign_require("phpini", "phpini-lib.pl");
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
			&foreign_require("software", "software-lib.pl");
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

&register_post_action(\&restart_apache);
$pfound || &error("Apache virtual host was not found");
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
foreach my $p (@ports) {
        local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
        next if (!$vconf);
	$pfound++;
	local @newdir = &apache::find_directive("FcgidIOTimeout", $vconf);
	local $dirname = @newdir ? "FcgidIOTimeout" : "IPCCommTimeout";
	if ($max) {
		&apache::save_directive($dirname, [ $max+1 ],
					$vconf, $conf);
		}
	else {
		&apache::save_directive($dirname, [ 9999 ],
					$vconf, $conf);
		}
	&flush_file_lines($virt->{'file'});
	}
&register_post_action(\&restart_apache);
$pfound || &error("Apache virtual host was not found");
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
# Updates the max execution time in all php.ini files
sub set_php_max_execution_time
{
local ($d, $max) = @_;
&foreign_require("phpini", "phpini-lib.pl");
foreach my $ini (&list_domain_php_inis($d)) {
	local $f = $ini->[1];
	local $conf = &phpini::get_config($f);
	&phpini::save_directive($conf, "max_execution_time", $max);
	&flush_file_lines($f);
	}
}

# get_php_max_execution_time(&domain)
# Returns the max execution time from a php.ini file
sub get_php_max_execution_time
{
local ($d, $max) = @_;
&foreign_require("phpini", "phpini-lib.pl");
foreach my $ini (&list_domain_php_inis($d)) {
	local $f = $ini->[1];
	local $conf = &phpini::get_config($f);
	local $max = &phpini::find_value("max_execution_time", $conf);
	return $max if ($max ne '');
	}
return undef;
}

# create_php_wrappers(&domain, phpmode)
# Creates all phpN.cgi wrappers for some domain
sub create_php_wrappers
{
local ($d, $mode) = @_;
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
				}
			$common .= "export PHP_FCGI_CHILDREN\n";
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

# supported_php_modes([&domain])
# Returns a list of PHP execution modes possible for a domain
sub supported_php_modes
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne 'web') {
	return &plugin_call($p, "feature_web_supported_php_modes", $d);
	}
&require_apache();
local @rv;
if ($apache::httpd_modules{'mod_php4'} || $apache::httpd_modules{'mod_php5'}) {
	# Check for Apache PHP module
	push(@rv, "mod_php");
	}
if ($d) {
	# Check for domain's cgi-bin directory
	local ($pvirt, $pconf) = &get_apache_virtual($d->{'dom'},
						     $d->{'web_port'});
	if ($pconf) {
		local @sa = grep { /^\/cgi-bin\s/ }
				 &apache::find_directive("ScriptAlias", $pconf);
		push(@rv, "cgi");
		}
	}
else {
	# Assume all domains have CGI
	push(@rv, "cgi");
	}
if ($apache::httpd_modules{'mod_fcgid'}) {
	# Check for Apache fcgi module
	push(@rv, "fcgid");
	}
return @rv;
}

# list_available_php_versions([&domain], [forcemode])
# Returns a list of PHP versions and their executables installed on the system,
# for use by a domain
sub list_available_php_versions
{
local ($d, $mode) = @_;
local @rv;

&require_apache();
if ($d) {
	# If the domain is using mod_php, we can only use one version
	$mode ||= &get_domain_php_mode($d);
	if ($mode eq "mod_php") {
		if ($apache::httpd_modules{'mod_php4'}) {
			return ([ 4, undef ]);
			}
		elsif ($apache::httpd_modules{'mod_php5'}) {
			return ([ 5, undef ]);
			}
		else {
			return ( );
			}
		}
	}
else {
	# If no domain is given, included mod_php versions if active
	if ($apache::httpd_modules{'mod_php4'}) {
		push(@rv, [ 4, undef ]);
		}
	elsif ($apache::httpd_modules{'mod_php5'}) {
		push(@rv, [ 5, undef ]);
		}
	}

# For CGI and fCGId modes, check which wrappers could exist
foreach my $v (@all_possible_php_versions) {
	local $phpn;
	if ($gconfig{'os_type'} eq 'solaris') {
		# On Solaris with CSW packages, php-cgi is in a directory named
		# after the PHP version
		$phpn = &has_command("/opt/csw/php$v/bin/php-cgi");
		}
	$phpn ||= &has_command("php$v-cgi") || &has_command("php$v");
	local $nodotv = $v;
	$nodotv =~ s/\.//;
	if ($nodotv ne $v) {
		# For a version like 5.4, check for binaries like php54 and
		# /opt/rh/php54/root/usr/bin/php
		$phpn ||= &has_command("php$nodotv-cgi") ||
			  &has_command("php-cgi$nodotv") ||
			  &has_command("/opt/rh/php$nodotv/root/usr/bin/php-cgi") ||
			  &has_command("/opt/rh/php$nodotv/bin/php-cgi") ||
			  &has_command("php$nodotv") ||
			  &has_command("/opt/rh/php$nodotv/root/usr/bin/php");
			  &has_command("/opt/rh/php$nodotv/bin/php") ||
			  &has_command(glob("/opt/phpfarm/inst/bin/php-cgi-$v.*"));
		}
	$vercmds{$v} = $phpn if ($phpn);
	}
local $php = &has_command("php-cgi") || &has_command("php");
if ($php && scalar(keys %vercmds) != scalar(@all_possible_php_versions)) {
	# What version is the php command? If it is a version we don't have
	# a command for yet, use it.
	&clean_environment();
	local $out = &backquote_command("$php -v 2>&1 </dev/null");
	&reset_environment();
	if ($out =~ /PHP\s+(\d+)\./ && !$vercmds{$1}) {
		$vercmds{$1} = $php;
		}
	}

# Return results as list
return map { [ $_, $vercmds{$_} ] } sort { $a <=> $b } (keys %vercmds);
}

# get_php_version(number|command, [&domain])
# Given a PHP based version like 4 or 5, or a path to PHP, return the real
# version number, like 5.2.
sub get_php_version
{
local ($cmd, $d) = @_;
if ($cmd !~ /^\//) {
	local ($phpn) = grep { $_->[0] == $cmd }
			     &list_available_php_versions($d);
	return undef if (!$phpn);
	$cmd = $phpn->[1] || &has_command("php$cmd") || &has_command("php");
	}
&clean_environment();
local $out = &backquote_command("$cmd -v 2>&1 </dev/null");
&reset_environment();
if ($out =~ /PHP\s+([0-9\.]+)/) {
	return $1;
	}
return undef;
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
	# All are run as version from Apache mod
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
				}
			}
		}
	}
return @rv;
}

# save_domain_php_directory(&domain, dir, phpversion)
# Sets up a directory to run PHP scripts with a specific version of PHP.
# Should only be called on domains in cgi or fcgid mode! Returns 1 if the
# directory version was set OK, 0 if not (because the virtualhost couldn't
# be found, or the PHP mode was wrong)
sub save_domain_php_directory
{
local ($d, $dir, $ver) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_save_web_php_directory",
			    $d, $dir, $ver);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
local $mode = &get_domain_php_mode($d);
return 0 if ($mode eq "mod_php");
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
local $any = 0;
local %allvers = map { $_, 1 } @all_possible_php_versions;
local $pfound = 0;
foreach my $p (@ports) {
	local $conf = &apache::get_config();
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	$pfound++;

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
			@types = grep { $_ !~ /^application\/x-httpd-php[45]/ }
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
		local @lines = (
			"<Directory $dir>",
			"Options +Indexes +IncludesNOEXEC +SymLinksifOwnerMatch +ExecCGI",
			"allow from all",
			"AllowOverride All".$olist,
			@phplines,
			"</Directory>"
			);
		local $lref = &read_file_lines($virt->{'file'});
		splice(@$lref, $virt->{'eline'}, 0, @lines);
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		}
	$any++;
	}
return 0 if (!$any);

# Make sure we have all the wrapper scripts
&create_php_wrappers($d, $mode);

# Re-create php.ini link
&create_php_ini_link($d, $mode);

&register_post_action(\&restart_apache);
$pfound || &error("Apache virtual host was not found");
return 1;
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

# cleanup_php_cgi_processes()
# Finds and kills and php-cgi, php4-cgi and php5-cgi processes which are
# orphans (owned by init). This can happen if they are not killed when Apache
# is restarted.
sub cleanup_php_cgi_processes
{
if (&foreign_check("proc") && $config{'web'}) {
	&foreign_require("proc", "proc-lib.pl");
	local @procs = &proc::list_processes();
	local @cgis = grep { $_->{'args'} =~ /^\S+php(4|5|)\-cgi/ &&
			     $_->{'ppid'} == 1 } @procs;
	foreach my $p (@cgis) {
		kill('KILL', $p->{'pid'});
		}
	return scalar(@cgis);
	}
return -1;
}

# list_domain_php_inis(&domain, [force-mode])
# Returns a list of php.ini files used by a domain, and their PHP versions
sub list_domain_php_inis
{
local ($d, $mode) = @_;
local @inis;
foreach my $v (&list_available_php_versions($d, $mode)) {
	local $ifile = "$d->{'home'}/etc/php$v->[0]/php.ini";
	if (-r $ifile) {
		push(@inis, [ $v->[0], $ifile ]);
		}
	}
if (!@inis) {
	local $ifile = "$d->{'home'}/etc/php.ini";
	if (-r $ifile) {
		push(@inis, [ undef, $ifile ]);
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
foreach my $i ("/opt/rh/php$nodotv/root/etc/php.ini",
	       "/opt/rh/php$nodotv/lib/php.ini",
	       "/etc/php.ini",
	       $mode eq "mod_php" ? ("/etc/php$ver/apache/php.ini",
				     "/etc/php$ver/apache2/php.ini",
				     "/etc/php$nodotv/apache/php.ini",
                                     "/etc/php$nodotv/apache2/php.ini")
				  : ("/etc/php$ver/cgi/php.ini",
				     "/etc/php$nodotv/cgi/php.ini"),
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
&foreign_require("phpini", "phpini-lib.pl");
local $gconf = &phpini::get_config($inifile);
local $sock = &phpini::find_value("mysql.default_socket", $gconf);
return $sock;
}

# get_domain_php_children(&domain)
# For a domain using fcgi to run PHP, returns the number of child processes.
# Returns 0 if not set, -1 if the file doesn't even exist, -2 if not supported
sub get_domain_php_children
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_php_children", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
local ($ver) = &list_available_php_versions($d, "fcgid");
return -2 if (!$ver);
local $childs = 0;
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
		for(my $e=0; $i<@$lref; $e++) {
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

# list_php_modules(&domain, php-version, php-command)
# Returns a list of PHP modules available for some domain. Uses caching.
sub list_php_modules
{
local ($d, $ver, $cmd) = @_;
local $mode = &get_domain_php_mode($d);
if (!defined($main::php_modules{$ver,$d->{'id'}})) {
	$cmd ||= &has_command("php".$ver) || &has_command("php");
	$main::php_modules{$ver} = [ ];
	if ($mode eq "mod_php") {
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
    ($mode = &get_domain_php_mode($d)) && $mode ne "mod_php" &&
    &foreign_check("phpini")) {
	&foreign_require("phpini", "phpini-lib.pl");
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

# fix_php_extension_dir(&domain)
# If the extension_dir in a domain's php.ini file is invalid, try to fix it
sub fix_php_extension_dir
{
local ($d) = @_;
return if (!&foreign_check("phpini"));
&foreign_require("phpini", "phpini-lib.pl");
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

# create_php_ini_link(&domain, [php-mode])
# Create a link from etc/php.ini to the PHP version used by the domain's
# public_html directory
sub create_php_ini_link
{
local ($d, $mode) = @_;
$mode ||= &get_domain_php_mode($d);
if ($mode ne "mod_php") {
	local @dirs = &list_domain_php_directories($d);
	local $phd = &public_html_dir($d);
	local ($hdir) = grep { $_->{'dir'} eq $phd } @dirs;
	$hdir ||= $dirs[0];
	local $etc = "$d->{'home'}/etc";
	if ($hdir) {
		&unlink_file_as_domain_user($d, "$etc/php.ini");
		&symlink_file_as_domain_user($d,
			"php".$hdir->{'version'}."/php.ini", "$etc/php.ini");
		}
	}
}

1;

