
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
return ( "2006-11-06" );
}

sub script_dokuwiki_category
{
return "Wiki";
}

sub script_dokuwiki_php_vers
{
return ( 4, 5 );
}

# script_dokuwiki_depends(&domain, version)
sub script_dokuwiki_depends
{
local ($d, $ver) = @_;
return undef;
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
			     &ui_opt_textbox("dir", "dokuwiki", 30,
					     "At top level"));
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
	   'url' => "http://www.splitbrain.org/_media/projects/dokuwiki/dokuwiki-$ver.tgz" } );
return @files;
}

# script_dokuwiki_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs PhpWiki, and returns either 1 and an informational
# message, or 0 and an error
sub script_dokuwiki_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);
&has_command("tar") ||
   return (0, "The tar command is needed to extract the DokuWiki source");
&has_command("gunzip") ||
   return (0, "The gunzip command is needed to extract the DokuWiki source");

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Extract tar file to temp dir
local $temp = &transname();
mkdir($temp, 0755);
chown($d->{'uid'}, $d->{'gid'}, $temp);
$out = &run_as_domain_user($d, "cd ".quotemeta($temp).
			       " && (gunzip -c $files->{'source'} | tar xf -)");
-r "$temp/dokuwiki-$ver/doku.php" ||
	return (0, "Failed to extract source : <tt>$out</tt>.");

# Move all files to target
$out = &run_as_domain_user($d, "cp -rp ".quotemeta($temp)."/dokuwiki-$ver/* ".
			       quotemeta($opts->{'dir'}));
local $cfile = "$opts->{'dir'}/doku.php";
-r $cfile || return (0, "Failed to copy source : <tt>$out</tt>.");

# Set permissions
open(CHANGES, ">$opts->{'dir'}/data/changes.log");
close(CHANGES);
&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0777,
			   "$opts->{'dir'}/data/changes.log");
&make_file_php_writable($d, "$opts->{'dir'}/data");

local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "DokuWiki installation complete. Go to <a href='$url'>$url</a> to use it.", "Under $rp", $url);
}

# script_dokuwiki_uninstall(&domain, version, &opts)
# Un-installs a PHP-Nuke installation, by deleting the directory and database.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_dokuwiki_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
&is_under_directory($d->{'home'}, $opts->{'dir'}) ||
	return (0, "Invalid install directory $opts->{'dir'}");
local $out = &backquote_logged("rm -rf ".quotemeta($opts->{'dir'})."/* 2>&1");
$? && return (0, "Failed to delete files : <tt>$out</tt>");

if ($opts->{'dir'} ne &public_html_dir($d, 0)) {
	# Take out the directory too
	&run_as_domain_user($d, "rmdir ".quotemeta($opts->{'dir'}));
	}

return (1, "DokuWiki directory deleted.");
}

# script_dokuwiki_latest()
# Returns a URL and regular expression or callback func to get the version
sub script_dokuwiki_latest
{
return ( "http://www.splitbrain.org/projects/dokuwiki",
	 "dokuwiki-([0-9\\-]+)\\.tgz" );
}



1;

