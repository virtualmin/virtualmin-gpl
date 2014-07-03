
# script_dokuwiki_desc()
sub script_dokuwiki_desc
{
return "DokuWiki";
}

sub script_dokuwiki_uses
{
return ( "php" );
}

sub script_dokuwiki_longdesc
{
return "DokuWiki is a standards compliant, simple to use Wiki, mainly aimed at creating documentation of any kind.";
}

# script_dokuwiki_versions()
sub script_dokuwiki_versions
{
return ( "2014-05-05a" );
}

sub script_dokuwiki_category
{
return "Wiki";
}

sub script_dokuwiki_php_vers
{
return ( 5 );
}

# script_dokuwiki_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_dokuwiki_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", &substitute_scriptname_template("dokuwiki", $d), 30, "At top level"));
	}
return $rv;
}

# script_dokuwiki_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_dokuwiki_parse
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
	return { 'dir' => $dir,
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}", };
	}
}

# script_dokuwiki_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_dokuwiki_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
if (-r "$opts->{'dir'}/doku.php") {
	return "DokuWiki appears to be already installed in the selected directory";
	}
return undef;
}

# script_dokuwiki_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by PHP-Nuke, each of which is a hash ref
# containing a name, filename and URL
sub script_dokuwiki_files
{
local ($d, $ver, $opts, $upgrade) = @_;
local @files = ( { 'name' => "source",
	   'file' => "dokuwiki-$ver.tgz",
	   'nocache' => 1,
	   'url' => "http://download.dokuwiki.org/src/dokuwiki/dokuwiki-stable.tgz" } );
return @files;
}

sub script_dokuwiki_commands
{
return ("tar", "gunzip");
}

# script_dokuwiki_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_dokuwiki_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);

# Extract tar file to temp dir and copy to target
local $temp = &transname();
local $err = &extract_script_archive($files->{'source'}, $temp, $d,
                                     $opts->{'dir'}, "dokuwiki-$ver");
$err && return (0, "Failed to extract source : $err");
local $cfile = "$opts->{'dir'}/doku.php";

# Set permissions
&open_tempfile_as_domain_user($d, CHANGES, ">$opts->{'dir'}/data/changes.log", 0, 1);
&close_tempfile_as_domain_user($d, CHANGES);
&set_permissions_as_domain_user($d, 0777, "$opts->{'dir'}/data/changes.log");
&make_file_php_writable($d, "$opts->{'dir'}/data");

local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "DokuWiki installation complete. Go to <a target=_blank href='$url'>$url</a> to use it.", "Under $rp", $url);
}

# script_dokuwiki_uninstall(&domain, version, &opts)
# Un-installs a PHP-Nuke installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_dokuwiki_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

return (1, "DokuWiki directory deleted.");
}

# script_dokuwiki_latest()
# Returns a URL and regular expression or callback func to get the version
sub script_dokuwiki_latest
{
return ( "http://download.dokuwiki.org/",
	 "(201[4-9]-[0-9][0-9]-[0-9][0-9][a-z]+)" );
}

sub script_dokuwiki_site
{
return 'https://www.dokuwiki.org/';
}

1;

