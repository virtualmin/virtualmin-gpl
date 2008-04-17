
# script_django_desc()
sub script_django_desc
{
return "Django";
}

sub script_django_uses
{
return ( "python" );
}

sub script_django_longdesc
{
return "Django is a high-level Python Web framework that encourages rapid development and clean, pragmatic design.";
}

# script_django_versions()
sub script_django_versions
{
return ( "0.96.1" );
}

sub script_django_category
{
return "Development";
}

sub script_django_python_modules
{
return ( "MySQLdb" );
}

# script_django_depends(&domain, version)
# Check for ruby command, ruby gems, mod_proxy
sub script_django_depends
{
local ($d, $ver) = @_;
&has_command("python") || return "The python command is not installed";
&require_apache();
$apache::httpd_modules{'mod_fcgid'} ||
	return "Apache does not have the mod_fcgid module";
$apache::httpd_modules{'mod_rewrite'} ||
	return "Apache does not have the mod_rewrite module";
return undef;
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
	local @dbs = &domain_databases($d, [ "mysql" ]);
	$rv .= &ui_table_row("Django database",
		     &ui_database_select("db", undef, \@dbs, $d, "phpbb"));
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
if (-r "$opts->{'dir'}/django.fcgi") {
	return "Django appears to be already installed in the selected directory";
	}
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
	   'file' => "flup-0.5.tar.gz",
	   'url' => "http://www.saddi.com/software/flup/dist/flup-0.5.tar.gz" },
	);
return @files;
}

sub script_django_commands
{
local ($d, $ver, $opts) = @_;
return ("python");
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
local $dbuser = &mysql_user($d);
local $dbpass = &mysql_pass($d);
local $dbhost = &get_database_host($dbtype);
if ($dbtype) {
	local $dberr = &check_script_db_connection($dbtype, $dbname,
						   $dbuser, $dbpass);
	return (0, "Database connection failed : $dberr") if ($dberr);
	}

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Extract the source, then install to the target dir
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d);
$err && return (0, "Failed to extract Django source : $err");
local $icmd = "cd ".quotemeta("$temp/Django-$ver")." && ".
	      "python setup.py install --home ".quotemeta($opts->{'dir'});
local $out = &run_as_domain_user($d, $cmd);
if ($?) {
	return (0, "Django source install failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}
$ENV{'PYTHONPATH'} = "$opts->{'dir'}/lib/python";

# Extract and install the flup source
local $err = &extract_script_archive($files->{'flup'}, $temp, $d);
$err && return (0, "Failed to extract flup source : $err");
local $icmd = "cd ".quotemeta("$temp/flup-$ver")." && ".
	      "python setup.py install --home ".quotemeta($opts->{'dir'});
local $out = &run_as_domain_user($d, $cmd);
if ($?) {
	return (0, "flup source install failed : ".
		   "<pre>".&html_escape($out)."</pre>");
	}

if (!$upgrade) {
	# Create the initial project
	local $icmd = "cd ".quotemeta($opts->{'dir'})." && ".
		      "./bin/django-admin.py startproject ".
		      quotemeta($opts->{'project'});
	local $out = &run_as_domain_user($d, $cmd);
	if ($?) {
		return (0, "Project initialization install failed : ".
			   "<pre>".&html_escape($out)."</pre>");
		}

	# Fixup settings.py to use the MySQL DB
	local $pdir = "$opts->{'dir'}/$opts->{'project'}";
	local $sfile = "$pdir/settings.py";
	-r $sfile || return (0, "Project settings file $sfile was not found");
	local $lref = &read_file_lines($sfile);
	foreach my $l (@$lref) {
		if ($l =~ /DATABASE_ENGINE\s*=/) {
			$l = "DATABASE_ENGINE = 'mysql'";
			}
		if ($l =~ /DATABASE_NAME\s*=/) {
			$l = "DATABASE_NAME = '$dbname'";
			}
		if ($l =~ /DATABASE_USER\s*=/) {
			$l = "DATABASE_USER = '$dbuser'";
			}
		if ($l =~ /DATABASE_PASSWORD\s*=/) {
			$l = "DATABASE_PASSWORD = '$dbpass'";
			}
		if ($l =~ /DATABASE_HOST\s*=/) {
			$l = "DATABASE_HOST = '$dbhost'";
			}
		}
	&flush_file_lines($sfile);

	# Activate the admin site
	local $ufile = "$pdir/urls.py";
	local $lref = &read_file_lines($ufile);
	foreach my $l (@$lref) {
		if ($l =~ /^(\s*)#(.*django.contrib.admin.urls.*)/) {
			$l = $1.$2;
			}
		}
	&flush_file_lines($ufile);

	# Initialize the DB
	# Input is 'yes', username, email, password, password again
	local $qfile = &transname();
	&open_tempfile(QFILE, ">$qfile", 0, 1);
	&print_tempfile(QFILE, "yes\n");
	&print_tempfile(QFILE, "$domuser\n");
	&print_tempfile(QFILE, "$d->{'emailto'}\n");
	&print_tempfile(QFILE, "$dompass\n");
	&print_tempfile(QFILE, "$dompass\n");
	&close_tempfile(QFILE);
	local $icmd = "cd ".quotemeta($pdir)." && ".
		      "$python manage.py syncdb <$qfile";
	local $out = &run_as_domain_user($d, $cmd);
	if ($?) {
		return (0, "Database initialization failed : ".
			   "<pre>".&html_escape($out)."</pre>");
		}
	}

# Create fcgi wrapper script
local $fcgi = "$opts->{'dir'}/django.fcgi";
local $wrapper = "$opts->{'dir'}/django.fcgi.py";
local $python = &has_command("python");
&open_tempfile(FCGI, ">$fcgi");
&print_tempfile(FCGI, "#!/bin/sh\n");
&print_tempfile(FCGI, "export PYTHONPATH=$opts->{'dir'}/lib/python\n");
&print_tempfile(FCGI, "exec $python $wrapper\n");
&close_tempfile(FCGI);
&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755, $fcgi);

# Create python fcgi wrapper
if (!-r $wrapper) {
	&open_tempfile(WRAPPER, ">$wrapper");
	&print_tempfile(WRAPPER, "#!$python\n");
	&print_tempfile(WRAPPER, "import sys, os\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}/lib/python\")\n");
	&print_tempfile(WRAPPER, "sys.path.insert(0, \"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "os.chdir(\"$opts->{'dir'}\")\n");
	&print_tempfile(WRAPPER, "os.environ['DJANGO_SETTINGS_MODULE'] = \"$opts->{'project'}.settings\"\n");
	&print_tempfile(WRAPPER, "from django.core.servers.fastcgi import runfastcgi\n");
	&print_tempfile(WRAPPER, "runfastcgi(method=\"threaded\", daemonize=\"false\")\n");
	&close_tempfile(WRAPPER);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755, $wrapper);
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
	local $pfx = $opts->{'path'} eq '/' ? '' : $opts->{'path'};
	local $loc = { 'name' => 'Location',
		       'value' => $opts->{'path'},
		       'type' => 1,
		       'members' => [
			{ 'name' => 'AddHandler',
			  'value' => 'fcgid-script .fcgi' },
			{ 'name' => 'RewriteEngine',
			  'value' => 'On' },
			{ 'name' => 'RewriteCond',
			  'value' => '%{REQUEST_FILENAME} !django.fcgi' },
			{ 'name' => 'RewriteRule',
			  'value' => "${pfx}(.*) ${pfx}django.fcgi/\$1 [L]" },
			]
		     };
	&apache::save_directive_struct(undef, $dir, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
&register_post_action(\&restart_apache);

local $url = &script_path_url($d, $opts);
local $adminurl = $url."admin/";
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "Initial Django installation complete. Go to <a target=_new href='$adminurl'>$adminurl</a> to manage it. Rails is a development environment, so it doesn't do anything by itself!", "Under $rp", $url, $domuser, $dompass);
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

# XXX delete database?

# Remove <Location> block
# XXX

return (1, "Django directory deleted.");
}

sub script_django_check_latest
{
local ($ver) = @_;
# XXX
return undef;
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

