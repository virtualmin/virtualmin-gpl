# Functions for managing a domain's home directory

# setup_dir(&domain)
# Creates the home directory
sub setup_dir
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();
local $qh = quotemeta($_[0]->{'home'});
&$first_print($text{'setup_home'});

# Get Unix user, either for this domain or its parent
local $uinfo;
if ($_[0]->{'unix'} || $_[0]->{'parent'}) {
	local @users = &list_all_users();
	($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @users;
	}
if ($_[0]->{'unix'} && !$uinfo) {
	# If we are going to have a Unix user but none has been created
	# yet, fake his details here for use in chowning and skel copying
	# This should never happen!
	$uinfo ||= { 'uid' => $_[0]->{'uid'},
		     'gid' => $_[0]->{'ugid'},
		     'shell' => '/bin/sh',
		     'group' => $_[0]->{'group'} || $_[0]->{'ugroup'} };
	}

# Create and populate home directory
&create_domain_home_directory($_[0], $uinfo);

# Populate home dir
if ($tmpl->{'skel'} ne "none" && !$_[0]->{'nocopyskel'} &&
    !$_[0]->{'alias'}) {
	# Don't die if this fails due to quota issues
	eval {
	  local $main::error_must_die = 1;
	  &copy_skel_files(&substitute_domain_template($tmpl->{'skel'}, $_[0]),
	  		   $uinfo, $_[0]->{'home'},
	  		   $_[0]->{'group'} || $_[0]->{'ugroup'}, $_[0]);
	  };
	}

# If this is a sub-domain, move public_html from any skeleton to it's sub-dir
# under the parent
if ($_[0]->{'subdom'}) {
	local $phsrc = &public_html_dir($_[0], 0, 1);
	local $phdst = &public_html_dir($_[0], 0, 0);
	if (-d $phsrc && !-d $phdst) {
		&make_dir($phdst, 0755);
		&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'},
					   undef, $phdst);
		&copy_source_dest($phsrc, $phdst);
		&unlink_file($phsrc);
		}
	}

# Setup sub-directories
&create_standard_directories($_[0]);
&$second_print($text{'setup_done'});

# Create mail file
if (!$_[0]->{'parent'} && $uinfo) {
	&$first_print($text{'setup_usermail3'});
	eval {
		local $main::error_must_die = 1;
		&create_mail_file($uinfo, $_[0]);

		# Set the user's Usermin IMAP password
		&set_usermin_imap_password($uinfo);
		};
	if ($@) {
		&$second_print(&text('setup_eusermail3', "$@"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

return 1;
}

# create_domain_home_directory(&domain, &unix-user)
# Create the home directory for a server or sub-server
sub create_domain_home_directory
{
local ($d, $uinfo) = @_;
local $perms = oct($uconfig{'homedir_perms'});
if (&has_domain_user($d) && $d->{'parent'}) {
	# Run as domain owner, as this is a sub-server
	&make_dir_as_domain_user($d, $d->{'home'}, $perms);
	&set_permissions_as_domain_user($d, $perms, $d->{'home'});
	}
else {
	# Run commands as root, as user is missing
	if (!-d $d->{'home'}) {
		&make_dir($d->{'home'}, $perms);
		}
	&set_ownership_permissions(undef, undef, $perms, $d->{'home'});
	if ($uinfo) {
		&set_ownership_permissions($uinfo->{'uid'}, $uinfo->{'gid'},
					   undef, $d->{'home'});
		}
	}
}

# create_standard_directories(&domain)
# Create and set permissions on standard directories
sub create_standard_directories
{
local ($d) = @_;
foreach my $dir (&virtual_server_directories($d)) {
	local $path = "$d->{'home'}/$dir->[0]";
	&lock_file($path);
	if (&has_domain_user($d)) {
		# Do creation as domain owner
		if (!-d $path) {
			&make_dir_as_domain_user($d, $path, oct($dir->[1]), 1);
			}
		&set_permissions_as_domain_user($d, oct($dir->[1]), $path);
		}
	else {
		# Need to run as root
		if (!-d $path) {
			&make_dir($path, oct($dir->[1]), 1);
			}
		&set_ownership_permissions(undef, undef, oct($dir->[1]), $path);
		if ($d->{'uid'} && ($d->{'unix'} || $d->{'parent'})) {
			&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
						   undef, $path);
			}
		}
	&unlock_file($path);
        }
}

# modify_dir(&domain, &olddomain)
# Rename home directory if needed
sub modify_dir
{
# Special case .. converting alias to non-alias, so some directories need to
# be created
if ($_[1]->{'alias'} && !$_[0]->{'alias'}) {
	&$first_print($text{'save_dirunalias'});
	local $tmpl = &get_template($_[0]->{'template'});
	if ($tmpl->{'skel'} ne "none") {
		local $uinfo = &get_domain_owner($_[0], 1);
		&copy_skel_files(
			&substitute_domain_template($tmpl->{'skel'}, $_[0]),
			$uinfo, $_[0]->{'home'},
			$_[0]->{'group'} || $_[0]->{'ugroup'}, $_[0]);
		}
	&create_standard_directories($_[0]);
	&$second_print($text{'setup_done'});
	}

if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($_[1], 1);
	}
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Move the home directory if changed, and if not already moved as
	# part of parent
	if (-d $_[1]->{'home'}) {
		&$first_print($text{'save_dirhome'});
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($_[0], 1);
			}
		local $cmd = $config{'move_command'} || "mv";
		$cmd .= " ".quotemeta($_[1]->{'home'}).
			" ".quotemeta($_[0]->{'home'});
		$cmd .= " 2>&1 </dev/null";
		&set_domain_envs($_[1], "MODIFY_DOMAIN", $_[0]);
		local $out = &backquote_logged($cmd);
		&reset_domain_envs($_[1]);
		if ($?) {
			&$second_print(&text('save_dirhomefailed', "<tt>$out</tt>"));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($_[0], 0);
			}
		}
	}
if ($_[0]->{'unix'} && !$_[1]->{'unix'} ||
    $_[0]->{'uid'} ne $_[1]->{'uid'}) {
	# Unix user now exists or has changed! Set ownership of home dir
	&$first_print($text{'save_dirchown'});
	&set_home_ownership($_[0]);
	&$second_print($text{'setup_done'});
	}
if (!$_[0]->{'subdom'} && $_[1]->{'subdom'}) {
	# No longer a sub-domain .. move the HTML dir
	local $phsrc = &public_html_dir($_[1]);
	local $phdst = &public_html_dir($_[0]);
	&copy_source_dest($phsrc, $phdst);
	&unlink_file($phsrc);

	# And the CGI directory
	local $cgisrc = &cgi_bin_dir($_[1]);
	local $cgidst = &cgi_bin_dir($_[0]);
	&copy_source_dest($cgisrc, $cgidst);
	&unlink_file($cgisrc);
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($_[0], 0);
	}
}

# delete_dir(&domain, [preserve-remote])
# Delete the home directory
sub delete_dir
{
local ($d, $preserve) = @_;

# Delete homedir
if (-d $d->{'home'} && $d->{'home'} ne "/") {
	&$first_print($text{'delete_home'});

	# Don't delete if on remote
	my ($home_mtab, $home_fstab) = &mount_point($d->{'home'});
	my $tab = $home_mtab || $home_fstab;
	if ($preserve && $tab && $tab->[1] =~ /^[a-z0-9\.\_\-]+:/i) {
		&$second_print(&text('delete_homepreserve', $tab->[1]));
		return 1;
		}

	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($d, 1);
		}
	local $err = &backquote_logged("rm -rf ".quotemeta($d->{'home'}).
				       " 2>&1");
	if ($?) {
		# Try again after running chattr
		if (&has_command("chattr")) {
			&system_logged("chattr -i -R ".
				       quotemeta($d->{'home'}));
			$err = &backquote_logged(
				"rm -rf ".quotemeta($d->{'home'})." 2>&1");
			$err = undef if (!$?);
			}
		}
	else {
		$err = undef;
		}
	if ($err) {
		# Ignore an error deleting a mount point
		local @subs = &sub_mount_points($d->{'home'});
		if (@subs) {
			$err = undef;
			}
		}
	if ($err) {
		&$second_print(&text('delete_ehome', &html_escape($err)));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
}

# clone_dir(&domain, &src-domain)
# Copy home directory contents to a new cloned domain
sub clone_dir
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_dir'});
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 1);
	}

# Exclude sub-server directories, logs, SSL certs and .zfs files
local $xtemp = &transname();
&open_tempfile(XTEMP, ">$xtemp");
&print_tempfile(XTEMP, "domains\n");
&print_tempfile(XTEMP, "./domains\n");
&print_tempfile(XTEMP, "logs\n");
&print_tempfile(XTEMP, "./logs\n");
if ($gconfig{'os_type'} eq 'solaris') {
	open(FIND, "find ".quotemeta($d->{'home'})." -name .zfs |");
	while(<FIND>) {
		s/\r|\n//g;
		s/^\Q$d->{'home'}\E\///;
		&print_tempfile(XTEMP, "$_\n");
		&print_tempfile(XTEMP, "./$_\n");
		}
	close(FIND);
	}
foreach my $s ('ssl_cert', 'ssl_key', 'ssl_chain', 'ssl_csr', 'ssl_newkey') {
	my $p = $d->{$s};
	if ($p) {
		$p =~ s/^\Q$d->{'home'}\E\///;
		&print_tempfile(XTEMP, "$p\n");
		&print_tempfile(XTEMP, "./$p\n");
		}
	}
&close_tempfile(XTEMP);

# Clear any in-memory caches of files under home dir
if (defined(&list_domain_php_inis) && &foreign_check("phpini")) {
	my $mode = &get_domain_php_mode($d);
        $mode = "cgi" if ($mode eq "mod_php");
	foreach my $ini (&list_domain_php_inis($d, $mode)) {
		delete($phpini::get_config_cache{$ini->[1]});
		}
	}

# Do the copy
if (!$d->{'parent'}) {
	&disable_quotas($d);
	&disable_quotas($oldd);
	}
local $err = &backquote_logged(
	       "cd ".quotemeta($oldd->{'home'})." && ".
	       "tar cfX - $xtemp . | ".
	       "(cd ".quotemeta($d->{'home'})." && ".
	       " tar xpf -) 2>&1");
&set_home_ownership($d);
if (!$d->{'parent'}) {
	&enable_quotas($oldd);
	&enable_quotas($d);
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 0);
	}
if ($err) {
	&$second_print(&text('clone_edir', &html_escape($err)));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# validate_dir(&domain)
# Returns an error message if the directory is missing, or has the wrong
# ownership
sub validate_dir
{
local ($d) = @_;
if (!-d $d->{'home'}) {
	return &text('validate_edir', "<tt>$d->{'home'}</tt>");
	}
local @st = stat($d->{'home'});
if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
	local $owner = getpwuid($st[4]);
	return &text('validate_ediruser', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'user'})
	}
if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'}) {
	local $owner = getgrgid($st[5]);
	return &text('validate_edirgroup', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'group'})
	}
if (!$d->{'alias'}) {
	foreach my $sd (&virtual_server_directories($d)) {
		if (!-d "$d->{'home'}/$sd->[0]") {
			# Dir is missing
			return &text('validate_esubdir',
				     "<tt>$sd->[0]</tt>")
			}
		local @st = stat("$d->{'home'}/$sd->[0]");
		if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
			# UID is wrong
			local $owner = getpwuid($st[4]);
			return &text('validate_esubdiruser',
				     "<tt>$sd->[0]</tt>",
				     $owner, $d->{'user'})
			}
		if ($d->{'gid'} && $st[5] != $d->{'gid'} &&
				   $st[5] != $d->{'ugid'}) {
			# GID is wrong
			local $owner = getgrgid($st[5]);
			return &text('validate_esubdirgroup',
				     "<tt>$sd->[0]</tt>",
				     $owner, $d->{'group'})
			}
		}
	}
return undef;
}

# check_dir_clash(&domain, [field])
sub check_dir_clash
{
# Does nothing ..?
return 0;
}

# backup_dir(&domain, file, &options, home-format, incremental, [&as-domain],
# 	     &all-options, &key)
# Backs up the server's home directory in tar format to the given file
sub backup_dir
{
local ($d, $file, $opts, $homefmt, $increment, $asd, $allopts, $key) = @_;
&$first_print($homefmt && $config{'compression'} == 3 ? $text{'backup_dirzip'} :
	      $increment == 1 ? $text{'backup_dirtarinc'}
			      : $text{'backup_dirtar'});
local $out;
local $cmd;
local $gzip = $homefmt && &has_command("gzip");

# Create an indicator file in the home directory showing where this backup
# came from. This can be used when replicating to know that the home directory
# is shared.
my ($home_mtab, $home_fstab) = &mount_point($d->{'home'});
my $tab = $home_mtab || $home_fstab;
my %src = ( 'id' => $d->{'id'},
	    'host' => &get_system_hostname(),
	    'mount' => $tab ? $tab->[1] : undef );
if ($src{'mount'} !~ /^[a-z0-9_\-\.]+:/i) {
	# Doesn't look like an NFS mount
	delete($src{'mount'});
	}
&write_as_domain_user($d, sub {
	&write_file("$d->{'home'}/.virtualmin-src", \%src)
	});

# Create exclude file
local $xtemp = &transname();
local @xlist;
push(@xlist, "domains");
if ($opts->{'dirnologs'}) {
	push(@xlist, "logs");
	}
if ($opts->{'dirnohomes'}) {
	push(@xlist, "homes");
	}
push(@xlist, "virtualmin-backup");
push(@xlist, &get_backup_excludes($d));
push(@xlist, split(/\t+/, $opts->{'exclude'}));
push(@xlist, "backup.lock");

# Exclude all .zfs files, for Solaris
if ($gconfig{'os_type'} eq 'solaris') {
	open(FIND, "find ".quotemeta($d->{'home'})." -name .zfs |");
	while(<FIND>) {
		s/\r|\n//g;
		s/^\Q$d->{'home'}\E\///;
		push(@xlist, $_);
		}
	close(FIND);
	}
&open_tempfile(XTEMP, ">$xtemp");
foreach my $x (@xlist) {
	if ($homefmt && $config{'compression'} == 3) {
		&print_tempfile(XTEMP, "$x\n");
		}
	else {
		&print_tempfile(XTEMP, "./$x\n");
		}
	}
&close_tempfile(XTEMP);

# Work out incremental flags
local ($iargs, $iflag, $ifile, $ifilecopy);
if (&has_incremental_tar() && $increment != 2) {
	if (!-d $incremental_backups_dir) {
		&make_dir($incremental_backups_dir, 0700);
		}
	$ifile = "$incremental_backups_dir/$d->{'id'}";
	if (!$_[4]) {
		# Force full backup
		&unlink_file($ifile);
		}
	else {
		# Add a flag file indicating that this was an incremental,
		# and take a copy of the file so we can put it back as before
		# the backup (as tar modifies it)
		if (-r $ifile) {
			$iflag = "$d->{'home'}/.incremental";
			&open_tempfile_as_domain_user(
				$d, IFLAG, ">$iflag", 0, 1);
			&close_tempfile_as_domain_user($d, IFLAG);
			$ifilecopy = &transname();
			&copy_source_dest($ifile, $ifilecopy);
			}
		}
	$iargs = "--listed-incremental=$ifile";
	}

# Create the dest file with strict permissions
local $qf = quotemeta($file);
local $toucher = "touch $qf && chmod 600 $qf";
if ($asd && $homefmt) {
	$toucher = &command_as_user($asd->{'user'}, 0, $toucher);
	}
&execute_command($toucher);

# Create the writer command. This will be run as the domain owner if this
# is the final step of the backup process, and if the owner is doing the backup.
local $writer = "cat >$qf";
if ($asd && $homefmt) {
	$writer = &command_as_user($asd->{'user'}, 0, $writer);
	}

# If encrypting, add gpg to the pipeline - unless encryption is being done
# at a higher level
if ($key && $homefmt) {
	$writer = &backup_encryption_command($key)." | ".$writer;
	}

# Do the backup
if ($homefmt && $config{'compression'} == 0) {
	# With gzip
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, ".").
	       " | gzip -c $config{'zip_args'}";
	}
elsif ($homefmt && $config{'compression'} == 1) {
	# With bzip
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, ".").
	       " | ".&get_bzip2_command()." -c $config{'zip_args'}";
	}
elsif ($homefmt && $config{'compression'} == 3) {
	# ZIP archive
	$cmd = "zip -r -x\@$xtemp - .";
	}
else {
	# Plain tar
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, ".");
	}
$cmd .= " | $writer";
local $ex = &execute_command("cd ".quotemeta($d->{'home'})." && $cmd",
			     undef, \$out, \$out);
&unlink_file($iflag) if ($iflag);
&copy_source_dest($ifilecopy, $ifile) if ($ifilecopy);
if (-r $ifile) {
	# Make owned by domain owner, so tar can read in future
	&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
				   0700, $ifile);
	}
if ($ex || !-s $file) {
	&$second_print(&text($cmd =~ /^\S*zip/ ? 'backup_dirzipfailed'
					       : 'backup_dirtarfailed',
			     "<pre>".&html_escape($out)."</pre>"));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# show_backup_dir(&options)
# Returns HTML for the backup logs option
sub show_backup_dir
{
local ($opts) = @_;
return &ui_checkbox("dir_logs", 1, $text{'backup_dirlogs'},
		    !$opts->{'dirnologs'})." ".
       &ui_checkbox("dir_homes", 1, $text{'backup_dirhomes'},
		    !$opts->{'dirnohomes'});
}

# parse_backup_dir(&in)
# Parses the inputs for directory backup options
sub parse_backup_dir
{
local %in = %{$_[0]};
return { 'dirnologs' => $in{'dir_logs'} ? 0 : 1,
	 'dirnohomes' => $in{'dir_homes'} ? 0 : 1 };
}

# show_restore_dir(&options, &domain)
# Returns HTML for mail restore option inputs
sub show_restore_dir
{
local ($opts) = @_;
return &ui_checkbox("dir_homes", 1, $text{'restore_dirhomes'},
                    !$opts->{'dirnohomes'})."<br>\n".
       &ui_checkbox("dir_delete", 1, $text{'restore_dirdelete'},
		    $opts->{'delete'});
}

# parse_restore_dir(&in, &domain)
# Parses the inputs for mail backup options
sub parse_restore_dir
{
local %in = %{$_[0]};
return { 'dirnohomes' => !$in{'dir_homes'},
	 'delete' => $in{'dir_delete'} };
}

# restore_dir(&domain, file, &options, &all-options, homeformat?, &oldd,
# 	      asowner, &key)
# Extracts the given tar file into server's home directory
sub restore_dir
{
local ($d, $file, $opts, $allopts, $homefmt, $oldd, $asd, $key) = @_;

&$first_print($text{'restore_dirtar'});

# Check if in replication mode and restoring to the same NFS server
my ($home_mtab, $home_fstab) = &mount_point($d->{'home'});
my $tab = $home_mtab || $home_fstab;
my %src;
&write_as_domain_user($d, sub {
	&read_file("$d->{'home'}/.virtualmin-src", \%src)
	});
if ($allopts->{'repl'} && $src{'id'} && $src{'id'} eq $d->{'id'} &&
    $src{'mount'} && $src{'mount'} eq ($tab ? $tab->[1] : undef)) {
	&$second_print(&text('restore_dirsame', $src{'mount'}));
	return 1;
	}

# Check for free space, if possible
my $osize = &get_compressed_file_size($file, $key);
if ($osize && $config{'home_quotas'}) {
	&foreign_require("mount");
	my @space = &mount::disk_space(undef, $config{'home_quotas'});
	if (@space && $space[1]*1024 < $osize) {
		# Won't fit!
		&$first_print(&text('restore_edirspace', &nice_size($osize),
				    &nice_size($space[1]*1024)));
		}
	}

local $iflag = "$d->{'home'}/.incremental";
&unlink_file($iflag);
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 1, 1);
	}

# Create exclude file, to skip local system-specific files
local $xtemp = &transname();
&open_tempfile(XTEMP, ">$xtemp");
my @exc = ( "cgi-bin/lang",	# Used by AWstats, and created locally .. so
	    "cgi-bin/lib",	# no need to include in restore.
	    "cgi-bin/plugins",
	    "public_html/icon",
	    "public_html/awstats-icon",
	    ".backup");
if ($opts->{'dirnohomes'}) {
	push(@exc, "homes");
	}
foreach my $e (@exc) {
	&print_tempfile(XTEMP, $e,"\n");
	&print_tempfile(XTEMP, "./",$e,"\n");
	}
&close_tempfile(XTEMP);

# Check if Apache logs were links before the restore
local $alog = "$d->{'home'}/logs/access_log";
local $elog = "$d->{'home'}/logs/error_log";
local ($aloglink, $eloglink);
if ($d->{'web'}) {
	$aloglink = readlink($alog);
	$eloglink = readlink($elog);
	}

# If home dir is missing (perhaps due to deletion of /home), re-create it
if (!-e $d->{'home'}) {
	local $uinfo;
	if ($d->{'unix'} || $d->{'parent'}) {
		local @users = &list_all_users();
		($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @users;
		}
	&create_domain_home_directory($d, $uinfo);
	}

# Turn off quotas for the domain, to prevent the import failing
&disable_quotas($d);

local ($out, $err);
local $cf = &compression_format($file, $key);
local $q = quotemeta($file);
local $qh = quotemeta($d->{'home'});
local $catter;
if ($key && $homefmt) {
	$catter = &backup_decryption_command($key)." ".$q;
	}
else {
	$catter = "cat $q";
	}
if ($cf == 4) {
	# Unzip command does un-compression and un-archiving
	# XXX ZIP doesn't support excludes of paths :-(
	&execute_command("cd $qh && unzip -o $q", undef, \$out, \$out);
	}
else {
	local $comp = $cf == 1 ? "gunzip -c" :
		      $cf == 2 ? "uncompress -c" :
		      $cf == 3 ? &get_bunzip2_command()." -c" : "cat";
	local $tarcmd = &make_tar_command("xvfX", "-", $xtemp);
	local $reader = $catter." | ".$comp;
	if ($asd) {
		# Run as domain owner - disabled, as this prevents some files
		# from being written to by tar
		$tarcmd = &command_as_user($d->{'user'}, 0, $tarcmd);
		}
	&execute_command("cd $qh && $reader | $tarcmd", undef, \$out, \$err);
	}
local $ex = $?;
&enable_quotas($d);
if ($ex) {
	# Errors about utime in the tar extract are ignored when running
	# as the domain owner
	&$second_print(&text('backup_dirtarfailed',
			     "<pre>".&html_escape($err)."</pre>"));
	return 0;
	}
else {
	# Check for incremental restore of newly-created domain, which indicates
	# that is is not complete
	my $wasincr = -r $iflag;
	if ($d->{'wasmissing'} && $wasincr) {
		&$second_print($text{'restore_wasmissing'});
		}
	else {
		&$second_print($text{'setup_done'});
		}
	&unlink_file($iflag);

	if ($d->{'unix'} ||
	    $d->{'parent'} && &get_domain($d->{'parent'})->{'unix'}) {
		# Set ownership on extracted home directory, apart from
		# content of ~/homes - unless running as the domain owner,
		# in which case ~/homes is set too
		&$first_print($text{'restore_dirchowning'});
		&set_home_ownership($d);
		if ($asd && !$opts->{'dirnohomes'}) {
			&set_mailbox_homes_ownership($d);
			}
		&$second_print($text{'setup_done'});
		}
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($d, 0, 1);
		}
	
	# Incremental file is no longer valid, so clear it
	local $ifile = "$incremental_backups_dir/$d->{'id'}";
	&unlink_file($ifile);

	# Check if logs are links now .. if not, we need to move the files
	local $new_aloglink = readlink($alog);
	local $new_eloglink = readlink($elog);
	if ($d->{'web'} && !$d->{'subdom'} && !$d->{'alias'}) {
		local $new_alog = &get_website_log($d, 0);
		local $new_elog = &get_website_log($d, 1);
		if ($aloglink && !$new_aloglink) {
			&system_logged("mv ".quotemeta($alog)." ".
					     quotemeta($new_alog));
			}
		if ($eloglink && !$new_eloglink) {
			&system_logged("mv ".quotemeta($elog)." ".
					     quotemeta($new_elog));
			}
		}

	# For a non-incremental restore, delete files that weren't in the backup
	# XXX make optional
	if (!$wasincr && $cf != 4 && $opts->{'delete'}) {
		# Parse tar output to find files that were restored
		my %restored;
		foreach my $l (split(/\r?\n/, $out)) {
			$l =~ s/^\.\///;
			$l =~ s/\/$//;
			$restored{$l} = 1;
			}

		# Find files that exist now
		my @existing;
		&open_execute_command(FIND,
			"cd ".quotemeta($d->{'home'})." && ".
			"find . -print", 1, 1);
		while(my $l = <FIND>) {
			$l =~ s/\r|\n//g;
			$l =~ s/^\.\///;
			push(@existing, $l);
			}

		# Add standard dirs to exclude list
		foreach my $dir (&virtual_server_directories($d)) {
			push(@exc, $dir->[0]);
			}
		push(@exc, ".backup.lock");
		push(@exc, "virtualmin-backup");
		push(@exc, "logs");	# Some backups don't include logs
		push(@exc, "homes");	# or homes dirs
		push(@exc, &get_backup_excludes($d));

		# Delete those that weren't in tar, except for excluded dirs
		foreach my $f (@existing) {
			next if ($restored{$f});
			next if ($f eq "." || $f eq ".." ||
				 $f =~ /\/\.$/ || $f =~ /\/\.\.$/);
			next if ($f =~ /\/\.zfs$/ || $f eq ".zfs");

			# Check if on exclude list
			my $skip = 0;
			foreach my $e (@exc) {
				if ($f eq $e || $f =~ /^\Q$e\E\//) {
					$skip = 1;
					}
				}
			next if ($skip);

			# Can delete the file
			&unlink_logged("$d->{'home'}/$f");
			}
		}

	return 1;
	}
}

# set_home_ownership(&domain)
# Update the ownership of all files in a server's home directory, EXCEPT
# the homes directory which is used by mail users
sub set_home_ownership
{
local ($d) = @_;
local $hd = $config{'homes_dir'};
$hd =~ s/^\.\///;
local $gid = $d->{'gid'} || $d->{'ugid'};
foreach my $sd ($d, &get_domain_by("parent", $d->{'id'})) {
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($sd, 1);
		}
	}
my @subhomes;
if (!$d->{'parent'}) {
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		push(@subhomes, " | grep -v ".quotemeta("$sd->{'home'}/$hd/"));
		}
	}
&system_logged("find ".quotemeta($d->{'home'})." ! -type l ".
	       " | grep -v ".quotemeta("$d->{'home'}/$hd/").
	       " | grep -v .nodelete".
	       join("", @subhomes).
	       " | sed -e 's/^/\"/' | sed -e 's/\$/\"/' ".
	       " | xargs chown $d->{'uid'}:$gid");
&system_logged("chown $d->{'uid'}:$gid ".
	       quotemeta($d->{'home'})."/".$config{'homes_dir'});
foreach my $dir (&virtual_server_directories($d)) {
	&set_ownership_permissions(undef, undef, oct($dir->[1]),
				   $d->{'home'}."/".$dir->[0]);
	}
foreach my $user (&list_domain_users($d, 1, 1, 1, 1)) {
	next if ($user->{'webowner'});
	next if (!$user->{'unix'});
	next if ($user->{'nocreatehome'});
	next if (!&is_under_directory("$d->{'home'}/$hd", $user->{'home'}));
	next if ("$d->{'home'}/$hd" eq $user->{'home'});
	&system_logged("chown -R $user->{'uid'}:$user->{'gid'} ".
		       quotemeta($user->{'home'}));
	}
foreach my $sd ($d, &get_domain_by("parent", $d->{'id'})) {
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($sd, 0);
		}
	}
return undef;
}

# set_mailbox_homes_ownership(&domain)
# Set the owners of all directories under ~/homes to their mailbox users
sub set_mailbox_homes_ownership
{
local ($d) = @_;
local $hd = $config{'homes_dir'};
$hd =~ s/^\.\///;
local $homes = "$d->{'home'}/$hd";
foreach my $user (&list_domain_users($d, 1, 1, 1, 1)) {
	if (&is_under_directory($homes, $user->{'home'}) &&
	    !$user->{'webowner'} && $user->{'home'}) {
		&system_logged("find ".quotemeta($user->{'home'}).
			       " | sed -e 's/^/\"/' | sed -e 's/\$/\"/' ".
			       " | xargs chown $user->{'uid'}:$user->{'gid'}");
		}
	}
}

# virtual_server_directories(&dom)
# Returns a list of sub-directories that need to be created for virtual servers
sub virtual_server_directories
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $perms = $tmpl->{'web_html_perms'};
return ( $d->{'subdom'} || $d->{'alias'} ? ( ) :
		( [ &public_html_dir($d, 1), $perms ] ),
         $d->{'subdom'} || $d->{'alias'} ? ( ) :
		( [ &cgi_bin_dir($d, 1), $perms ] ),
         [ 'logs', '750' ],
         [ $config{'homes_dir'}, '755' ] );
}

# create_server_tmp(&domain)
# Creates the temporary files directory for a domain, and returns the path
sub create_server_tmp
{
local ($d) = @_;
if ($d->{'dir'}) {
	local $tmp = "$d->{'home'}/tmp";
	if (!-d $tmp) {
		&make_dir_as_domain_user($d, $tmp, 0750, 1);
		}
	return $tmp;
	}
else {
	# For domains without a home
	return "/tmp";
	}
}

# show_template_dir(&tmpl)
# Outputs HTML for editing directory-related template options
sub show_template_dir
{
local ($tmpl) = @_;

# The skeleton files directory
print &ui_table_row(&hlink($text{'tmpl_skel'}, "template_skel"),
	&none_def_input("skel", $tmpl->{'skel'}, $text{'tmpl_skeldir'}, 0,
			$tmpl->{'standard'} ? 1 : 0, undef,
			[ "skel", "skel_subs", "skel_nosubs",
			  "skel_onlysubs" ])."\n".
	&ui_textbox("skel", $tmpl->{'skel'} eq "none" ? undef
						      : $tmpl->{'skel'}, 40));

# Perform substitions on skel file contents
print &ui_table_row(&hlink($text{'tmpl_skel_subs'}, "template_skel_subs"),
	&ui_yesno_radio("skel_subs", int($tmpl->{'skel_subs'})));

# File patterns to exclude
print &ui_table_row(&hlink($text{'tmpl_skel_nosubs'}, "template_skel_nosubs"),
	&ui_textbox("skel_nosubs", $tmpl->{'skel_nosubs'}, 60));

# File patterns to include
print &ui_table_row(&hlink($text{'tmpl_skel_onlysubs'},
			   "template_skel_onlysubs"),
	&ui_textbox("skel_onlysubs", $tmpl->{'skel_onlysubs'}, 60));
}

# parse_template_dir(&tmpl)
# Updates directory-related template options from %in
sub parse_template_dir
{
local ($tmpl) = @_;

# Save skeleton directory
$tmpl->{'skel'} = &parse_none_def("skel");
if ($in{"skel_mode"} == 2) {
	-d $in{'skel'} || &error($text{'tmpl_eskel'});
	$tmpl->{'skel_subs'} = $in{'skel_subs'};
	$tmpl->{'skel_nosubs'} = $in{'skel_nosubs'};
	$tmpl->{'skel_onlysubs'} = $in{'skel_onlysubs'};
	}
}

# create_index_content(&domain, content)
# Create an index.html file containing the given text
sub create_index_content
{
local ($d, $content) = @_;
local $dest = &public_html_dir($d);
local @indexes = grep { -f $_ } glob("$dest/index.*");
if (@indexes) {
	&unlink_file(@indexes);
	}
&open_tempfile_as_domain_user($d, DESTOUT, ">$dest/index.html");
&print_tempfile(DESTOUT, $content);
&close_tempfile_as_domain_user($d, DESTOUT);
}

$done_feature_script{'dir'} = 1;

1;

