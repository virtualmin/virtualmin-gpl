
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

# script_django_depends(&domain, version)
# Check for ruby command, ruby gems, mod_proxy
sub script_django_depends
{
local ($d, $ver) = @_;
&has_command("python") || return "The python command is not installed";
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
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
	if ($dbtype) {
		$rv .= &ui_table_row("Rails database", $dbname);
		}
	}
else {
	# Show editable install options
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", "django", 30,
					     "At top level"));
	local @dbs = &domain_databases($d, [ "mysql" ]);
	if (@dbs) {
		$rv .= &ui_table_row("Configure Rails to use database",
		     &ui_radio("db_def", 1, [ [ 1, "None" ],
				     	    [ 0, "Selected database" ] ])."\n".
		     &ui_database_select("db", undef, \@dbs));
		}
	else {
		$rv .= &ui_hidden("db_def", 1)."\n";
		}
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
        local $mongrels = &parse_mongrels_ports_input($d, $in);
        return $mongrels if (!int($mongrels));
	return { 'db' => $in->{'db_def'} ? undef : $in->{'db'},
		 'dir' => $dir,
		 'path' => $in->{'dir_def'} ? "/" : "/$in->{'dir'}",
		 'mongrels' => $mongrels,
		 'server' => $in->{'server'},
		 'development' => $in->{'development'}, };
	}
}

# script_django_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_django_check
{
local ($d, $ver, $opts, $upgrade) = @_;
if (-r "$opts->{'dir'}/script/server") {
	return "Django appears to be already installed in the selected directory";
	}
$opts->{'mongrels'} ||= 1;
return undef;
}

# script_django_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by Rails, each of which is a hash ref
# containing a name, filename and URL
sub script_django_files
{
local ($d, $ver, $opts, $upgrade) = @_;
return ( );	# Nothing, as everything is downloaded
}

sub script_django_commands
{
local ($d, $ver, $opts) = @_;
return ("ruby", $opts->{'db'} ? ("gcc", "make") : ( ));
}

# script_django_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_django_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);

# Get database settings
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

# Need python MySQL support
# XXX

# Can only run under root directory
# XXX

# Setup fcgi wrapper, like
# #!/bin/sh
# export PYTHONPATH=/home/djangotest/public_html/django/lib/python
# exec python /home/djangotest/public_html/django/django.fcgi.py

# Setup python wrapper, like
# #!/usr/bin/python
# import sys, os

# # Add a custom Python path.
# sys.path.insert(0, "/home/djangotest/public_html/django/lib/python")
# sys.path.insert(0, "/home/djangotest/public_html/django")

# # Switch to the directory of your project. (Optional.)
# os.chdir("/home/djangotest/public_html/django")

# # Set the DJANGO_SETTINGS_MODULE environment variable.
# os.environ['DJANGO_SETTINGS_MODULE'] = "mysite.settings"

# from django.core.servers.fastcgi import runfastcgi
# runfastcgi(method="threaded", daemonize="false")

# Setup location block like 
# <Location /django>
# AddHandler fcgid-script .fcgi
# RewriteEngine On
# RewriteCond %{REQUEST_FILENAME} !django.fcgi
# RewriteRule /django/(.*) /django/django.fcgi/$1 [L]
# </Location>

# Configure settings.py

# Activate admin site

# Run python manage.py syncdb to create tables and users
# Input is 'yes', username, email, password, password again

if (!$upgrade && $dbname) {
	# Update database configuration file
	local $dbfile = "$opts->{'dir'}/config/database.yml";
	local $lref = &read_file_lines($dbfile);
	local $edit;
	foreach my $l (@$lref) {
		if ($l =~ /^(\S+):/) {
			$edit = $1 eq "development" || $1 eq "production";
			}
		elsif ($l =~ /^\s+database:/ && $edit) {
			$l = "  database: $dbname";
			}
		elsif ($l =~ /^\s+username:/ && $edit) {
			$l = "  username: $dbuser";
			}
		elsif ($l =~ /^\s+password:/ && $edit) {
			$l = "  password: $dbpass";
			}
		elsif ($l =~ /^\s+(socket|host):/ && $edit) {
			$l = "  host: $dbhost";
			}
		}
	&flush_file_lines($dbfile);
	}

if ($opts->{'server'} && !$upgrade) {
	# Find a free port for the server
	$opts->{'port'} = &allocate_mongrel_port(undef, $opts->{'mongrels'});
	}

local (@logs, @startcmds, @stopcmds);
local @ports = split(/\s+/, $opts->{'port'});
if ($opts->{'server'}) {
	# Start the servers
	local $err = &mongrel_django_start_servers($d, $opts, "django",
					\@startcmds, \@stopcmds, \@logs);
	return (0, $err) if ($err);
	$opts->{'log'} = join(" ", @logs);

	# Setup an Apache proxy for it
	&setup_mongrel_proxy($d, $opts->{'path'}, $opts->{'port'},
			     $opts->{'path'} eq '/' ? undef : $opts->{'path'});
	}

if ($opts->{'server'} && !$upgrade) {
	# Configure server to start at boot
	&setup_mongrel_startup($d,
			       join("\n", @startcmds),
			       join("\n", @stopcmds),
			       $opts,
			       1, "django-".$ports[0], "Django");
	}

if ($opts->{'server'} && !$upgrade) {
	# Deny regular web access to directory
	&protect_django_directory($d, $opts);
	}

local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "Initial Django installation complete. Go to <a target=_new href='$url'>$url</a> to use it. Rails is a development environment, so it doesn't do anything by itself!", "Under $rp", $url);
}

# script_django_uninstall(&domain, version, &opts)
# Un-installs a Rails installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_django_uninstall
{
local ($d, $version, $opts) = @_;

if ($opts->{'server'}) {
	# Shut down the server process
	&script_django_stop_server($d, $opts);

	# Remove bootup script
	&delete_mongrel_startup($d, $opts,
		"mongrel_django start", $opts->{'port'});
	&delete_mongrel_startup($d, $opts,
		"script/server", $opts->{'port'});
	}

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

if ($opts->{'server'}) {
	# Remove proxy Apache config entry for /django
	&delete_mongrel_proxy($d, $opts->{'path'});
	}
&register_post_action(\&restart_apache);

return (1, "Django directory deleted.");
}

# script_django_stop(&domain, &sinfo)
# Stop running mongrel process
sub script_django_stop
{
local ($d, $sinfo) = @_;
if ($sinfo->{'opts'}->{'server'}) {
	&script_django_stop_server($d, $sinfo->{'opts'});
	&delete_mongrel_startup($d, $sinfo->{'opts'},
			"mongrel_django start", $sinfo->{'opts'}->{'port'});
	&delete_mongrel_startup($d, $sinfo->{'opts'},
			"script/server", $sinfo->{'opts'}->{'port'});
	}
}

sub script_django_start_server
{
local ($d, $opts) = @_;
return &mongrel_django_start_servers($d, $opts, "django");
}

sub script_django_status_server
{
local ($d, $opts) = @_;
return &mongrel_django_status_servers($d, $opts);
}

# script_django_stop_server(&domain, &opts)
# Kill the running Rails server process
sub script_django_stop_server
{
local ($d, $opts) = @_;
&mongrel_django_stop_servers($d, $opts);
}

sub script_django_check_latest
{
local ($ver) = @_;
foreach my $nv (&ruby_gem_versions("django")) {
	return $nv if (&compare_versions($nv, $ver) > 0);
	}
return undef;
}

sub script_django_site
{
return 'http://www.rubyondjango.org/';
}

1;

