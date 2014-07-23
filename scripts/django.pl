
# script_django_desc()
sub script_django_desc
{
return "Django";
}

sub script_django_uses
{
return ( "python", "apache" );
}

sub script_django_longdesc
{
return "Django is a high-level Python Web framework that encourages rapid development and clean, pragmatic design.";
}

# script_django_versions()
sub script_django_versions
{
return ( "1.6.5", "1.4.13" );
}

sub script_django_release
{
return 3;		# To fix DB login issue
}

sub script_django_gpl
{
return 1;
}

sub script_django_category
{
return "Development";
}

sub script_django_python_modules
{
local ($d, $ver, $opts) = @_;
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
return ( "setuptools", $dbtype eq "mysql" ? "MySQLdb" :
		       $ver >= 1.6 ? "psycopg2" : "psycopg" );
}

# script_django_depends(&domain, version)
# Check for ruby command, ruby gems, mod_proxy
sub script_django_depends
{
local ($d, $ver) = @_;
local @rv;

# Check for python, and required version
my $python = &has_command($config{'python_cmd'} || "python");
$python || push(@rv, "The python command is not installed");
local $out = &backquote_command("$python --version 2>&1 </dev/null");
if ($out =~ /Python\s+([0-9\.]+)/i) {
	local $pyver = $1;
	if ($ver >= 1.5 && &compare_versions($pyver, "2.6.5") < 0) {
		push(@rv, "Django 1.5 requires Python 2.6.5 or later");
		}
	elsif (&compare_versions($pyver, "2.6") < 0) {
		push(@rv, "Django 1.4 requires Python 2.6 or later");
		}
	}
else {
	push(@rv, "Could not work out Python version : $out");
	}

&require_apache();
local $conf = &apache::get_config();
local $got_rewrite;
foreach my $l (&apache::find_directive("LoadModule", $conf)) {
	$got_rewrite++ if ($l =~ /mod_rewrite/);
	}
$apache::httpd_modules{'mod_fcgid'} ||
	push(@rv, "Apache does not have the mod_fcgid module");
$apache::httpd_modules{'mod_rewrite'} || $got_rewrite ||
	push(@rv, "Apache does not have the mod_rewrite module");
return @rv;
}

# script_django_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_django_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	$rv .= &ui_table_row("Django database", $dbname);
	$rv .= &ui_table_row("Initial project name",
		$upgrade->{'opts'}->{'project'});
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "mysql", "postgres" ]);
	$rv .= &ui_table_row("Django database",
		     &ui_database_select("db", undef, \@dbs, $d, "django"));
	$rv .= &ui_table_row("Initial project name",
		     &ui_textbox("project", "myproject", 30));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", undef, 30,
					     "At top level"));
	$rv .= &ui_table_row("",
	    "Warning - Django works best when installed at the top level.");
	}
return $rv;
}

# script_django_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_django_parse
{
local ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	local $hdir = &public_html_dir($d, 0);
	$in->{'dir_def'} || $in->{'dir'} =~ /\S/ && $in->{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	local $dir = $in->{'dir_def'} ? $hdir : "$hdir/$in->{'dir'}";
	$in{'project'} =~ /^[a-z0-9]+$/ ||
		return "Project name can only contain letters and numbers";
	local ($newdb) = ($in->{'db'} =~ s/^\*//);
	return { 'db' => $in->{'db'},
		 'newdb' => $newdb,
		 'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'project' => $in{'project'} };
	}
}

# script_django_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_django_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/django.fcgi") {
	return "Django appears to be already installed in the selected directory";
	}
$opts->{'project'} ||
	return "Missing initial project name";
$opts->{'project'} =~ /^[a-z0-9]+$/ ||
	return "Project name can only contain letters and numbers";
return undef;
}

# script_django_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Rails, each of which is a hash ref
# containing a name, filename and URL
sub script_django_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = (
	 { 'name' => "source",
	   'file' => "Django-$ver.tar.gz",
	   'url' => "http://www.djangoproject.com/download/$ver/tarball/" },
	 { 'name' => "flup",
	   'file' => "flup-1.0.tar.gz",
	   'url' => "http://www.saddi.com/software/flup/dist/flup-1.0.tar.gz" },
	);
return @files;
}

sub script_django_commands
{
local ($d, $ver, $opts) = @_;
return ($config{'python_cmd'} || "python");
}

# script_django_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_django_install
{
local ($d, $version, $opts, $files, $upgrade, $domuser, $dompass) = @_;
local ($out, $ex);

# Get database settings
if ($opts->{'newdb'} && !$upgrade) {
	local $err = &create_script_database($d, $opts->{'db'});
	return (0, "Database creation failed : $err") if ($err);
	}
local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
local $dbhost = &get_database_host($dbtype);
$dbhost = undef if ($dbhost eq "localhost" || $dbhost eq "127.0.0.1");
if ($dbtype) {
	local $dberr = &check_script_db_connection($dbtype, $dbname,
						   $dbuser, $dbpass);
	return (0, "Database connection failed : $dberr") if ($dberr);
	}
my $python = &has_command($config{'python_cmd'} || "python");

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Create python base dir
$ENV{'PYTHONPATH'} = "$opts->{'dir'}/lib/python";
&run_as_domain_user($d, "mkdir -p ".quotemeta($ENV{'PYTHONPATH'}));

# Extract the source
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d);
$err && return (0, "Failed to extract Django source : $err");

# Delete .pyc files from source that may be for an older python version
&run_as_domain_user($d,
	"find ".quotemeta($temp)." -name '*.pyc' | xargs rm -f");

# Install to target dir
local $icmd = "(cd ".quotemeta("$temp/Django-$ver")." && ".
      "$python setup.py install --home ".quotemeta($opts->{'dir'}).") 2>&1";
local $out = &run_as_domain_user($d, $icmd);
if ($?) {
	return (0, "Django source install failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}

# Extract and copy the flup source
local $err = &extract_script_archive($files->{'flup'}, $temp, $d);
$err && return (0, "Failed to extract flup source : $err");
local $out = &run_as_domain_user($d, 
	"cp -r ".quotemeta("$temp/flup-1.0/flup").
	" ".quotemeta("$opts->{'dir'}/lib/python"));
if ($?) {
	return (0, "flup source copy failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}

if (!$upgrade) {
	# Create the initial project
	local $icmd = "cd ".quotemeta($opts->{'dir'})." && ".
		      "./bin/django-admin.py startproject ".
		      quotemeta($opts->{'project'})." 2>&1";
	local $out = &run_as_domain_user($d, $icmd);
	if ($?) {
		return (-1, "Project initialization install failed : ".
			   "<pre>".&html_escape($out)."</pre>");
		}

	# Fixup settings.py to use the MySQL DB
	local $pdir = "$opts->{'dir'}/$opts->{'project'}";
	local $sfile = "$pdir/settings.py";
	if (!-r $sfile) {
		# New django moves this into a sub-directory
		$sfile = "$pdir/$opts->{'project'}/settings.py";
		}
	-r $sfile || return (-1, "Project settings file $sfile was not found");
	local $lref = &read_file_lines_as_domain_user($d, $sfile);
	my $i = 0;
	my $pdbtype = $dbtype eq "mysql" ? "mysql" :
		      $ver >= 1.6 ? "postgresql_psycopg2" : "postgresql";
	my ($engine, $gotname, $gotuser, $gotpass, $gothost);
	foreach my $l (@$lref) {
		# Django 1.1 style variables
		if ($l =~ /DATABASE_ENGINE\s*=/) {
			$l = "DATABASE_ENGINE = '$pdbtype'";
			}
		if ($l =~ /DATABASE_NAME\s*=/) {
			$l = "DATABASE_NAME = '$dbname'";
			}
		if ($l =~ /DATABASE_USER\s*=/) {
			$l = "DATABASE_USER = '$dbuser'";
			}
		if ($l =~ /DATABASE_PASSWORD\s*=/) {
			$l = "DATABASE_PASSWORD = '".
			     &php_quotemeta($dbpass, 1)."'";
			}
		if ($l =~ /DATABASE_HOST\s*=/) {
			$l = "DATABASE_HOST = '$dbhost'";
			}
		if ($l =~ /INSTALLED_APPS\s*=\s*\(/) {
			splice(@$lref, $i+1, 0,
			       "    'django.contrib.admin',");
			}

		# Django 1.2 variables
		if ($l =~ /'ENGINE':/) {
			$l = "        'ENGINE': 'django.db.backends.$pdbtype',";
			$engine = $i;
			}
		if ($l =~ /'NAME':/) {
			$l = "        'NAME': '$dbname',";
			$gotname++;
			}
		if ($l =~ /'USER':/) {
			$l = "        'USER': '$dbuser',";
			$gotuser++;
			}
		if ($l =~ /'PASSWORD':/) {
			$l = "        'PASSWORD': '$dbpass',";
			$gotpass++;
			}
		if ($l =~ /'HOST':/) {
			$l = "        'HOST': '$dbhost',";
			$gothost++;
			}
		$i++;
		}
	if (!$gotname) {
		splice(@$lref, $engine, 0, "        'NAME': '$dbname',");
		}
	if (!$gotuser) {
		splice(@$lref, $engine, 0, "        'USER': '$dbuser',");
		}
	if (!$gotpass) {
		splice(@$lref, $engine, 0, "        'PASSWORD': '$dbpass',");
		}
	if (!$gothost) {
		splice(@$lref, $engine, 0, "        'HOST': '$dbhost',");
		}
	&flush_file_lines_as_domain_user($d, $sfile);

	# Activate the admin site
	local $ufile = "$pdir/urls.py";
	if (!-r $ufile) {
		$ufile = "$pdir/$opts->{'project'}/urls.py";
		}
	local $lref = &read_file_lines_as_domain_user($d, $ufile);
	foreach my $l (@$lref) {
		if ($l =~ /^(\s*)#(.*django.contrib.admin.urls.*)/ ||
		    $l =~ /^(\s*)#(.*admin.site.root.*)/ ||
		    $l =~ /^(\s*)#(.*admin.site.urls.*)/) {
			# Un-comment /admin/ path
			$l = $1.$2;
			}
		elsif ($l =~ /^\s*#\s*(from django.contrib import admin)/ ||
		       $l =~ /^\s*#\s*(admin.autodiscover\(\))/) {
			# Un-comment admin includes
			$l = $1;
			}
		}
	&flush_file_lines_as_domain_user($d, $ufile);

	# Initialize the DB
	# Input is 'yes', username, email, password, password again
	local $icmd = &command_as_user($d->{'user'}, 0,
				       "$python manage.py syncdb");
	local $pwd = &get_current_dir();
	&foreign_require("proc", "proc-lib.pl");
	chdir($pdir);
	$ENV{'LANG'} = 'en_US';	# Needed because manage.py chokes with the
				# default locale
	local ($fh, $fpid) = &proc::pty_process_exec($icmd);
	chdir($pwd);
	local $out;
	$domuser =~ s/[\.\@\-]/_/g;
	foreach my $w ([ "yes.no", "yes" ],
		       [ "Username", $domuser ],
		       [ "E-?mail address", $d->{'emailto_addr'} ],
		       [ "Password", $dompass ],
		       [ "Password", $dompass ]) {
		local $rv = &wait_for($fh, $w->[0]);
		if ($rv < 0) {
			return (-1,
			   "Database initialization failed at $w->[0] : ".
			   "<pre>".&html_escape($wait_for_input)."</pre>");
			}
		&sysprint($fh, $w->[1]."\n");
		$out .= $wait_for_input;
		}
	&wait_for($fh, 'EOF');		# Wait till done
	close($fh);
	waitpid($fpid, 0);
	local $ex = $?;
	if ($ex || $out =~ /error/i) {
		return (-1, "Database initialization failed : ".
			    "<pre>".&html_escape($out)."</pre>");
		}
	}

# Create python fcgi wrapper script
local $wrapper = "$opts->{'dir'}/django.fcgi";
if (!-r $wrapper) {
	&open_tempfile_as_domain_user($d, WRAPPER, ">$wrapper");
	&print_tempfile(WRAPPER, "#!$python\n");
	&print_tempfile(WRAPPER, "import sys, os\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}/lib/python\")\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}/$opts->{'project'}\")\n");
	&print_tempfile(WRAPPER, "os.chdir(\"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "os.environ['DJANGO_SETTINGS_MODULE'] = \"$opts->{'project'}.settings\"\n");
	&print_tempfile(WRAPPER, "from django.core.servers.fastcgi import runfastcgi\n");
	&print_tempfile(WRAPPER, "runfastcgi(method=\"threaded\", daemonize=\"false\")\n");
	&close_tempfile_as_domain_user($d, WRAPPER);
	&set_permissions_as_domain_user($d, 0755, $wrapper);
	}

# Add <Location> block to Apache config
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @locs = &apache::find_directive_struct("Location", $vconf);
	local ($loc) = grep { $_->{'words'}->[0] eq $opts->{'path'} } @locs;
	next if ($loc);
	local $reldir = $opts->{'dir'};
	$reldir =~ s/^\Q$d->{'home'}\/\E//;
	local $loc = { 'name' => 'Location',
		       'value' => $opts->{'path'},
		       'type' => 1,
		       'members' => [
			{ 'name' => 'AddHandler',
			  'value' => 'fcgid-script .fcgi' },
			{ 'name' => 'RewriteEngine',
			  'value' => 'On' },
			{ 'name' => 'RewriteCond',
			  'value' =>
				'%{REQUEST_FILENAME} !django.fcgi|/media/|/static/' },
			{ 'name' => 'RewriteRule',
			  'value' => "$reldir(.*) django.fcgi/\$1 [L]" },
			]
		     };
	&apache::save_directive_struct(undef, $loc, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

# Add /media and /static/admin aliases to Apache config
local @paths;
push(@paths, $opts->{'path'} eq '/' ? "/media/"
                                    : "$opts->{'path'}/media/");
push(@paths, $opts->{'path'} eq '/' ? "/static/admin/"
                                    : "$opts->{'path'}/static/admin/");
local $mdir = "$opts->{'dir'}/lib/python/django/contrib/admin/static/admin/";
foreach my $path (@paths) {
	foreach my $port (@ports) {
		local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		next if (!$virt);
		local @al = &apache::find_directive("Alias", $vconf);
		local ($media) = grep { $_ =~ /^\Q$path\E\s/ } @al;
		next if ($media);
		push(@al, "$path $mdir");
		&apache::save_directive("Alias", \@al, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		}
	}

&register_post_action(\&restart_apache);

local $url = &script_path_url($d, $opts);
local $adminurl = $url."admin/";
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "Initial Django installation complete. Go to <a target=_blank href='$adminurl'>$adminurl</a> to manage it. Django is a development environment, so it doesn't do anything by itself!. Some applications may require you to set the PYTHONPATH environment variable to '$opts->{'dir'}/lib/python'.", "Under $rp", $url, $domuser, $dompass);
}

# script_django_uninstall(&domain, version, &opts)
# Un-installs a Rails installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_django_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

# Remove base Django tables from the database
&cleanup_script_database($d, $opts->{'db'}, "(django|auth)_");

# Remove <Location> block
&require_apache();
local $conf = &apache::get_config();
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @locs = &apache::find_directive_struct("Location", $vconf);
	local ($loc) = grep { $_->{'words'}->[0] eq $opts->{'path'} } @locs;
	next if (!$loc);
	&apache::save_directive_struct($loc, undef, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

# Remove /media and /static/admin aliases
local @paths;
push(@paths, $opts->{'path'} eq '/' ? "/media/"
                                    : "$opts->{'path'}/media/");
push(@paths, $opts->{'path'} eq '/' ? "/static/admin/"
                                    : "$opts->{'path'}/static/admin/");
foreach my $path (@paths) {
	foreach my $port (@ports) {
		local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		next if (!$virt);
		local @al = &apache::find_directive("Alias", $vconf);
		local ($media) = grep { $_ =~ /^\Q$path\E\s/ } @al;
		next if (!$media);
		@al = grep { $_ ne $media } @al;
		&apache::save_directive("Alias", \@al, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		}
	}

&register_post_action(\&restart_apache);

# Take out the DB
if ($opts->{'newdb'}) {
	&delete_script_database($d, $opts->{'db'});
	}

return (1, "Django directory and tables deleted.");
}

# script_django_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_django_latest
{
local ($ver) = @_;
return ( "http://www.djangoproject.com/download/",
	 $ver >= 1.5 ? "Django-([0-9\\.]+)\\.tar\\.gz" 
		     : "Django-(1\\.4\\.[0-9\\.]+)\\.tar\\.gz" );
}

sub script_django_site
{
return 'http://www.djangoproject.com/';
}

sub script_django_passmode
{
return 1;
}

1;

