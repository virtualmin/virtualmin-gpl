# Functions for PHP configuration

# get_domain_php_mode(&domain)
# Returns 'mod_php' if PHP is run via Apache's mod_php, 'cgi' if run via
# a CGI script, 'fcgid' if run via fastCGI. This is detected by looking for the
# Action lines in httpd.conf.
sub get_domain_php_mode
{
local ($d) = @_;
&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
if ($virt) {
	local @actions = &apache::find_directive("Action", $vconf);
	local ($dir) = grep { $_->{'words'}->[0] eq &public_html_dir($d) }
		    &apache::find_directive_struct("Directory", $vconf);
	if ($dir) {
		push(@actions, &apache::find_directive("Action",
						       $dir->{'members'}));
		}
	foreach my $a (@actions) {
		if ($a =~ /^application\/x-httpd-php.\s+\/cgi-bin\/php.\.cgi/) {
			return 'cgi';
			}
		}
	foreach my $f (&apache::find_directive("FCGIWrapper",
						$dir->{'members'})) {
		if ($f =~ /^\Q$d->{'home'}\E\/fcgi-bin\/php.\.fcgi/) {
			return 'fcgid';
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
&require_apache();
local $tmpl = &get_template($d->{'template'});
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
@ports = ( $port ) if ($port);	# Overridden to just do SSL or non-SSL
local $fdest = "$d->{'home'}/fcgi-bin";
foreach my $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$vconf);

	# Find <directory> sections containing PHP directives.
	# If none exist, add them in either the directory for
	# public_html, or the <virtualhost> if it already has them
	&lock_file($virt->{'file'});
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
		local ($dirstr) =
		  grep { $_->{'words'}->[0] eq &public_html_dir($d) }
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
		@handlers = grep { $_ !~ /^fcgid-script/ } @handlers;
		local @wrappers = &apache::find_directive("FCGIWrapper",
							  $phpconf);
		@wrappers = grep { $_ !~ /^\Q$fdest\E\/php.\.fcgi/ } @wrappers;

		# Add needed Apache directives. Don't add the AddHandler,
		# Alias and Directory if already there.
		local $ver = $pdirs{$phpstr->{'words'}->[0]} ||
			     $tmpl->{'web_phpver'} ||
			     $avail[0];
		$ver = $avail[0] if (&indexof($ver, @avail) < 0);
		if ($mode eq "cgi") {
			foreach my $v (@avail) {
				push(@actions, "application/x-httpd-php$v ".
					       "/cgi-bin/php$v.cgi");
				}
			foreach my $v (@avail) {
				push(@types,"application/x-httpd-php$v .php$v");
				}
			push(@types, "application/x-httpd-php$ver .php");
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
		&apache::save_directive("Action", \@actions, $phpconf, $conf);
		&apache::save_directive("AddType", \@types, $phpconf, $conf);
		&apache::save_directive("AddHandler", \@handlers,
					$phpconf, $conf);
		&apache::save_directive("FCGIWrapper", \@wrappers,
					$phpconf, $conf);

		# For fcgid mode, the directory needs to have Options ExecCGI
		local ($opts) = &apache::find_directive("Options", $phpconf);
		if ($opts && $mode eq "fcgid" && $opts !~ /ExecCGI/) {
			$opts .= " ExecCGI";
			&apache::save_directive("Options", [ $opts ],
						$phpconf, $conf);
			}
		}

	# For non-mod_php mode, we need a RemoveHandler .php directive at
	# the <virtualhost> level to supress mod_php which may still be active
	local @remove = &apache::find_directive("RemoveHandler", $vconf);
	@remove = grep { $_ !~ /^\.php/ } @remove;
	if ($mode ne "mod_php") {
		push(@remove, ".php");
		foreach my $v (@avail) {
			push(@remove, ".php$v");
			}
		}
	&apache::save_directive("RemoveHandler", \@remove, $vconf, $conf);

	&flush_file_lines();
	&unlock_file($virt->{'file'});
	}

# Create wrapper scripts
if ($mode ne "mod_php") {
	&create_php_wrappers($d, $mode);
	}

# Copy php.ini file into etc directory, for later per-site modification
local $etc = "$d->{'home'}/etc";
if (!-d $etc) {
	&make_dir($etc, 0755);
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'ugid'},
				   0755, $etc);
	}
if (!-r "$etc/php.ini") {
	# XXX ideally we would have separate 4 and 5 .ini files
	local $copied = 0;
	local @vers = &list_available_php_versions($d, $mode);
	local $defver = $vers[0]->[0];
	local $ini = $tmpl->{'web_php_ini'};
	local $subs_ini = 0;
	if (!$ini || $ini eq "none" || !-r $ini) {
		$ini = &get_global_php_ini($defver, $mode);
		}
	else {
		$subs_ini = 1;
		}
	if ($ini) {
		# Copy file, set permissions, fix session.save_path, and
		# clear out extension_dir (because it can differ between PHP
		# versions)
		if ($subs_ini) {
			# Perform substitions on config file
			local $inidata = &read_file_contents($ini);
			$inidata = &substitute_template($inidata, $d);
			&open_tempfile(INIDATA, ">$etc/php.ini");
			&print_tempfile(INIDATA, $inidata);
			&close_tempfile(INIDATA);
			}
		else {
			# Just copy verbatim
			&copy_source_dest($ini, "$etc/php.ini");
			}
		local ($uid, $gid) = (0, 0);
		if (!$tmpl->{'web_php_noedit'}) {
			($uid, $gid) = ($d->{'uid'}, $d->{'ugid'});
			}
		&set_ownership_permissions($uid, $gid, 0755, "$etc/php.ini");
		if (&foreign_check("phpini")) {
			&foreign_require("phpini", "phpini-lib.pl");
			local $pconf = &phpini::get_config("$etc/php.ini");
			&phpini::save_directive($pconf, "session.save_path",
						&create_server_tmp($d));
			&phpini::save_directive($pconf, "extension_dir", undef);
			&flush_file_lines("$etc/php.ini");
			}
		}
	}

&register_post_action(\&restart_apache);
}

# create_php_wrappers(&domain, phpmode)
# Creates all phpN.cgi wrappers for some domain
sub create_php_wrappers
{
local ($d, $mode) = @_;
local $dest = $mode eq "fcgid" ? "$d->{'home'}/fcgi-bin" : &cgi_bin_dir($_[0]);

if (!-d $dest) {
	# Need to create fcgi-bin
	&make_dir($dest, 0755);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755,
				   $dest);
	}

local $suffix = $mode eq "fcgid" ? "fcgi" : "cgi";
local $dirvar = $mode eq "fcgid" ? "PWD" : "DOCUMENT_ROOT";
local $common = "#!/bin/sh\n".
		"PHPRC=\$$dirvar/../etc\n".
		"PHP_FCGI_CHILDREN=4\n".
		"export PHP_FCGI_CHILDREN PHPRC\n";

# For each version of PHP, create a wrapper
local $pub = &public_html_dir($d);
foreach my $v (&list_available_php_versions($d, $mode)) {
	&open_tempfile(PHP, ">$dest/php$v->[0].$suffix");
	&print_tempfile(PHP, $common);
	if ($v->[1] =~ /-cgi$/) {
		# php-cgi requires the SCRIPT_FILENAME variable
		&print_tempfile(PHP, "SCRIPT_FILENAME=\$PATH_TRANSLATED\n");
		&print_tempfile(PHP, "export SCRIPT_FILENAME\n");
		}
	&print_tempfile(PHP, "exec $v->[1]\n");
	&close_tempfile(PHP);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755,
				   "$dest/php$v->[0].$suffix");

	# Also copy the .fcgi wrapper to public_html, which is needed due to
	# broken-ness on some Debian versions!
	if ($mode eq "fcgid") {
		&copy_source_dest("$dest/php$v->[0].$suffix",
				  "$pub/php$v->[0].$suffix");
		&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755,
					   "$pub/php$v->[0].$suffix");
		}
	}
}

# supported_php_modes([&domain])
# Returns a list of PHP execution modes possible for a domain
sub supported_php_modes
{
local ($d) = @_;
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

# If the domain is using mod_php, we can only use one version
&require_apache();
if ($d) {
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

# For CGI and fCGId modes, check which wrappers could exist
foreach my $v (@all_possible_php_versions) {
	local $phpn = &has_command("php$v-cgi") || &has_command("php$v");
	$vercmds{$v} = $phpn if ($phpn);
	}
local $php = &has_command("php-cgi") || &has_command("php");
if ($php && scalar(keys %vercmds) != scalar(@all_possible_php_versions)) {
	# What version is the php command?
	&clean_environment();
	local $out = `$php -v 2>&1 </dev/null`;
	&reset_environment();
	if ($out =~ /PHP\s+(\d+)\./) {
		$vercmds{$1} = $php;
		}
	}

# Return results as list
return map { [ $_, $vercmds{$_} ] } sort { $a <=> $b } (keys %vercmds);
}

# list_domain_php_directories(&domain)
# Returns a list of directories for which different versions of PHP have
# been configured.
sub list_domain_php_directories
{
local ($d) = @_;
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
			if ($w->[0] =~ /php(\d+)\.(cgi|fcgi)/ ||
			    $w->[0] =~ /x-httpd-php(\d+)/) {
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
&require_apache();
local $mode = &get_domain_php_mode($d);
return 0 if ($mode eq "mod_php");
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
local $any = 0;
foreach my $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);

	# Check for an existing <Directory> block
	&lock_file($virt->{'file'});
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
			}
		elsif ($mode eq "fcgid") {
			local $dest = "$d->{'home'}/fcgi-bin";
			local @wrappers = &apache::find_directive(
				"FCGIWrapper", $dirstr->{'members'});
			@wrappers = grep { $_ !~ /^\Q$dest\E\/php.\.fcgi/ }
					 @wrappers;
			foreach my $v (&list_available_php_versions($d)) {
				push(@wrappers,
				     "$dest/php$v->[0].fcgi .php$v->[0]");
				}
			push(@wrappers, "$dest/php$ver.fcgi .php");
			&apache::save_directive("FCGIWrapper", \@wrappers,
						$dirstr->{'members'}, $conf);
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
		local @lines = (
			"<Directory $dir>",
			"Options Indexes IncludesNOEXEC FollowSymLinks ExecCGI",
			"allow from all",
			"AllowOverride All",
			@phplines,
			"</Directory>"
			);
		local $lref = &read_file_lines($virt->{'file'});
		splice(@$lref, $virt->{'eline'}, 0, @lines);
		undef(@apache::get_config_cache);
		}
	&flush_file_lines($virt->{'file'});
	&unlock_file($virt->{'file'});
	$any++;
	}
return 0 if (!$any);

# Make sure we have all the wrapper scripts
&create_php_wrappers($d, $mode);

&register_post_action(\&restart_apache);
return 1;
}

# delete_domain_php_directory(&domain, dir)
# Delete the <Directory> section for a custom PHP version in some directory
sub delete_domain_php_directory
{
local ($d, $dir) = @_;

&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return 0 if (!$virt);
local $mode = &get_domain_php_mode($d);

local @dirs = &apache::find_directive_struct("Directory", $vconf);
local ($dirstr) = grep { $_->{'words'}->[0] eq $dir } @dirs;
if ($dirstr) {
	&lock_file($dirstr->{'file'});
	local $lref = &read_file_lines($dirstr->{'file'});
	splice(@$lref, $dirstr->{'line'},
	       $dirstr->{'eline'}-$dirstr->{'line'}+1);
	&flush_file_lines($dirstr->{'file'});
	undef(@apache::get_config_cache);
	&unlock_file($dirstr->{'file'});

	&register_post_action(\&restart_apache);
	return 1;
	}
return 0;
}

1;

