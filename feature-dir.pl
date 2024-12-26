# Functions for managing a domain's home directory

# check_depends_dir(&domain)
# A top-level domain with no Unix user makes no sense, because who's going to
# own the files?
sub check_depends_dir
{
local ($d) = @_;
if (!$d->{'parent'} && !$d->{'unix'}) {
	return $text{'setup_edepunixdir'};
	}
return undef;
}

# setup_dir(&domain)
# Creates the home directory
sub setup_dir
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
&require_useradmin();
my $qh = quotemeta($d->{'home'});
&$first_print($text{'setup_home'});

# Get Unix user, either for this domain or its parent
my $uinfo;
if ($d->{'unix'} || $d->{'parent'}) {
	my @users = &list_all_users();
	($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @users;
	}
if ($d->{'unix'} && !$uinfo) {
	# If we are going to have a Unix user but none has been created
	# yet, fake his details here for use in chowning and skel copying
	# This should never happen!
	$uinfo ||= { 'uid' => $d->{'uid'},
		     'gid' => $d->{'ugid'},
		     'shell' => '/bin/sh',
		     'group' => $d->{'group'} || $d->{'ugroup'} };
	}

# Create and populate home directory
&create_domain_home_directory($d, $uinfo);

# Populate home dir
if ($tmpl->{'skel'} ne "none" && !$d->{'nocopyskel'} &&
    !$d->{'alias'}) {
	# Don't die if this fails due to quota issues
	eval {
	  local $main::error_must_die = 1;
	  &copy_skel_files(&substitute_domain_template($tmpl->{'skel'}, $d),
	  		   $uinfo, $d->{'home'},
	  		   $d->{'group'} || $d->{'ugroup'}, $d);
	  };
	}

# If this is a sub-domain, move public_html from any skeleton to it's sub-dir
# under the parent
if ($d->{'subdom'}) {
	my $phsrc = &public_html_dir($d, 0, 1);
	my $phdst = &public_html_dir($d, 0, 0);
	if (-d $phsrc && !-d $phdst) {
		&make_dir($phdst, 0755, 1);
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
					   undef, $phdst);
		&copy_source_dest($phsrc, $phdst);
		&unlink_file($phsrc);
		}
	}

# Setup sub-directories
&create_standard_directories($d);
&$second_print($text{'setup_done'});

# Create mail file
if (!$d->{'parent'} && $uinfo) {
	&$first_print($text{'setup_usermail3'});
	eval {
		local $main::error_must_die = 1;
		&create_mail_file($uinfo, $d);

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

# Copy excludes from template
if ($tmpl->{'exclude'} ne 'none') {
	$d->{'backup_excludes'} = $tmpl->{'exclude'};
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
	&make_dir_as_domain_user($d, $d->{'home'}, $perms, 1);
	&set_permissions_as_domain_user($d, $perms, $d->{'home'});
	}
else {
	# Run commands as root, as user is missing
	if (!-d $d->{'home'}) {
		&make_dir($d->{'home'}, $perms, 1);
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
	my $path = "$d->{'home'}/$dir->[0]";
	&create_standard_directory_for_domain($d, $path, $dir->[1]);
	}
}

# create_standard_directory_for_domain(&domain, path, perms)
# Create one directory that should be owned by the domain user
sub create_standard_directory_for_domain
{
my ($d, $path, $perm) = @_;
&lock_file($path);
if (&has_domain_user($d)) {
	# Do creation as domain owner
	if (!-d $path) {
		&make_dir_as_domain_user($d, $path, oct($perm), 1);
		&set_permissions_as_domain_user($d, oct($perm), $path);
		}
	}
else {
	# Need to run as root
	if (!-d $path) {
		&make_dir($path, oct($perm), 1);
		&set_ownership_permissions(undef, undef, oct($perm), $path);
		}
	if ($d->{'uid'} && ($d->{'unix'} || $d->{'parent'})) {
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
					   undef, $path);
		}
	}
&unlock_file($path);
}

# modify_dir(&domain, &olddomain)
# Rename home directory if needed
sub modify_dir
{
local ($d, $oldd) = @_;

# Special case .. converting alias to non-alias, so some directories need to
# be created
if ($oldd->{'alias'} && !$d->{'alias'}) {
	&$first_print($text{'save_dirunalias'});
	local $tmpl = &get_template($d->{'template'});
	if ($tmpl->{'skel'} ne "none") {
		local $uinfo = &get_domain_owner($d, 1);
		&copy_skel_files(
			&substitute_domain_template($tmpl->{'skel'}, $d),
			$uinfo, $d->{'home'},
			$d->{'group'} || $d->{'ugroup'}, $d);
		}
	&create_standard_directories($d);
	&$second_print($text{'setup_done'});
	}

if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($oldd, 1);
	}
if ($d->{'home'} ne $oldd->{'home'}) {
	# Move the home directory if changed, and if not already moved as
	# part of parent
	if (-d $oldd->{'home'}) {
		&$first_print($text{'save_dirhome'});
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($d, 1);
			}
		local $wasjailed = 0;
		if (!&check_jailkit_support() && !$oldd->{'parent'} &&
		    &get_domain_jailkit($oldd)) {
			# Turn off jail for the old home
			&disable_domain_jailkit($oldd);
			$wasjailed = 1;
			}
		local $cmd = $config{'move_command'} || "mv";
		$cmd .= " ".quotemeta($oldd->{'home'}).
			" ".quotemeta($d->{'home'});
		$cmd .= " 2>&1 </dev/null";
		&set_domain_envs($oldd, "MODIFY_DOMAIN", $d);
		local $out = &backquote_logged($cmd);
		&reset_domain_envs($oldd);
		if ($?) {
			&$second_print(&text('save_dirhomefailed',
					     "<tt>$out</tt>"));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		if ($wasjailed) {
			# Turn jail back on for the new home
			my $err = &enable_domain_jailkit($d);
			if ($err) {
				&$second_print(&text('setup_ejail', $err));
				}
			}
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($d, 0);
			}
		}
	}
if ($d->{'unix'} && !$oldd->{'unix'} ||
    $d->{'uid'} ne $oldd->{'uid'}) {
	# Unix user now exists or has changed! Set ownership of home dir
	&$first_print($text{'save_dirchown'});
	&set_home_ownership($d);
	&$second_print($text{'setup_done'});
	}
if (!$d->{'subdom'} && $oldd->{'subdom'}) {
	# No longer a sub-domain .. move the HTML dir
	local $phsrc = &public_html_dir($oldd);
	local $phdst = &public_html_dir($d);
	&copy_source_dest($phsrc, $phdst);
	&unlink_file($phsrc);

	# And the CGI directory
	local $cgisrc = &cgi_bin_dir($oldd);
	local $cgidst = &cgi_bin_dir($d);
	&copy_source_dest($cgisrc, $cgidst);
	&unlink_file($cgisrc);
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 0);
	}
}

# delete_dir(&domain, [preserve-remote])
# Delete the home directory
sub delete_dir
{
local ($d, $preserve) = @_;

# Delete homedir
&require_useradmin();
if (-d $d->{'home'} && &safe_delete_dir($d, $d->{'home'})) {
	&$first_print($text{'delete_home'});

	# Don't delete if on remote
	if ($preserve && &remote_dir($d)) {
		&$second_print(&text('delete_homepreserve', &remote_dir($d)));
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
return 1;
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
if ($d->{'ssl'}) {
	# Exclude SSL certs because they are covered by backup_ssl, unless
	# Nginx is being used
	foreach my $s ('ssl_cert', 'ssl_key', 'ssl_chain', 'ssl_csr',
		       'ssl_newkey') {
		my $p = $d->{$s};
		if ($p) {
			$p =~ s/^\Q$d->{'home'}\E\///;
			&print_tempfile(XTEMP, "$p\n");
			&print_tempfile(XTEMP, "./$p\n");
			}
		}
	}
&close_tempfile(XTEMP);

# Clear any in-memory caches of files under home dir
if (defined(&list_domain_php_inis) && &foreign_check("phpini")) {
	my $mode = &get_domain_php_mode($d);
        $mode = "cgi" if ($mode eq "mod_php" || $mode eq "fpm");
	foreach my $ini (&list_domain_php_inis($d, $mode)) {
		delete($phpini::get_config_cache{$ini->[1]});
		}
	}

# Do the copy
if (!$d->{'parent'}) {
	&disable_quotas($d);
	&disable_quotas($oldd);
	}
if ($d->{'mail'}) {
	&break_autoreply_alias_links($oldd);
	}
local $err = &backquote_logged(
	       "cd ".quotemeta($oldd->{'home'})." && ".
	       "tar cfX - ".quotemeta($xtemp)." . | ".
	       "(cd ".quotemeta($d->{'home'})." && ".
	       " tar xpf -) 2>&1");
if ($d->{'mail'}) {
	&create_autoreply_alias_links($oldd);
	}
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

# Make sure home dir exists and has the correct owner
if (!-d $d->{'home'}) {
	return &text('validate_edir', "<tt>$d->{'home'}</tt>");
	}
local @st = stat($d->{'home'});
local $auser = &get_apache_user($d);
local @ainfo = getpwnam($auser);
if ($d->{'uid'} && $st[4] != $d->{'uid'} && $st[4] != $ainfo[2]) {
	local $owner = getpwuid($st[4]);
	return &text('validate_ediruser', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'user'})
	}
if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'} &&
    $st[5] != $ainfo[3]) {
	local $owner = getgrgid($st[5]);
	return &text('validate_edirgroup', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'group'})
	}

if (!$d->{'alias'}) {
	# Make sure common sub-directories exist
	foreach my $sd (&virtual_server_directories($d)) {
		next if ($sd->[0] eq 'virtualmin-backup' ||   # Not all domains
			 $sd->[0] eq $home_virtualmin_backup);
		next if ($sd->[2] eq 'ssl' && !&domain_has_ssl_cert($d));
		if (!-d "$d->{'home'}/$sd->[0]") {
			# Dir is missing
			return &text('validate_esubdir',
				     "<tt>$sd->[0]</tt>")
			}
		local @st = stat("$d->{'home'}/$sd->[0]");
		if ($d->{'uid'} && $st[4] != $d->{'uid'} && $st[4] != $ainfo[2]) {
			# UID is wrong
			local $owner = getpwuid($st[4]);
			return &text('validate_esubdiruser',
				     "<tt>$sd->[0]</tt>",
				     $owner, $d->{'user'})
			}
		if ($d->{'gid'} && $st[5] != $d->{'gid'} &&
		    $st[5] != $d->{'ugid'} && $st[5] != $ainfo[3]) {
			# GID is wrong
			local $owner = getgrgid($st[5]);
			return &text('validate_esubdirgroup',
				     "<tt>$sd->[0]</tt>",
				     $owner, $d->{'group'})
			}
		}
	}

# Make sure cert files are valid
if (!$d->{'ssl_same'} && &domain_has_ssl_cert($d)) {
	foreach my $t ('key', 'cert', 'ca') {
		my $file = &get_website_ssl_file($d, $t);
		next if (!$file);
		my $err = &validate_cert_format($file, $t);
		if ($err) {
			return &text('validate_esslfile', $t, $err);
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

# backup_dir(&domain, file, &options, home-format, differential, [&as-domain],
# 	     &all-options, &key)
# Backs up the server's home directory in tar format to the given file
sub backup_dir
{
local ($d, $file, $opts, $homefmt, $increment, $asd, $allopts, $key) = @_;
local $compression = $opts->{'compression'};
&$first_print($compression == 3 ? $text{'backup_dirzip'} :
	      $increment == 1 ? $text{'backup_dirtarinc'}
			      : $text{'backup_dirtar'});
local $out;
local $cmd;
local $destfile = $file;
if (!$homefmt) {
	$destfile .= ".".&compression_to_suffix_inner($compression);
	}

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

# If this is a home-format backup, create a dummy file in .backup even though
# it's not used so that the restore process knows what domain this came from
if ($homefmt) {
	my $backupdir = "$d->{'home'}/.backup";
	my $dummy = $backupdir."/".$d->{'dom'}."_dir";
	&make_dir_as_domain_user($d, $backupdir, 0755);
	&write_as_domain_user($d, sub {
		&write_file_contents($dummy, "")
		});
	}

# Create exclude file
local $xtemp = &transname();
local @xlist;
local @ilist;
if ($opts->{'include'}) {
	# Include only specific files
	@ilist = split(/\t+/, $opts->{'exclude'});
	push(@ilist, ".backup") if ($homefmt);
	if ($compression != 3) {
		@ilist = map { "./".$_ } @ilist;
		}
	}
else {
	# Build list of files to exclude
	push(@xlist, "domains");
	if ($opts->{'dirnologs'}) {
		push(@xlist, "logs");
		}
	if ($opts->{'dirnohomes'}) {
		push(@xlist, "homes");
		}
	push(@xlist, $home_virtualmin_backup);
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
	@ilist = (".");
	if ($compression != 3) {
		@xlist = map { "./".$_ } @xlist;
		}
	else {
		@xlist = map {
			if (-d "$d->{'home'}/$_" && $_ !~ /\/[*]+$/) {
				"$_/\*\*";
				}
			else {
				"$_";
				}
			} @xlist;
		}
	}
&open_tempfile(XTEMP, ">$xtemp");
foreach my $x (@xlist) {
	&print_tempfile(XTEMP, "$x\n");
	}
&close_tempfile(XTEMP);

# Work out differential flags
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
		# Add a flag file indicating that this was an differential,
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
local $qf = quotemeta($destfile);
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

# Do the backup, using a compressed format if this is the outermost archive
# or if using ZIP. Otherwise just use tar, since there will be another level
# of compression.
if ($homefmt && $compression == 0) {
	# With gzip
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, @ilist).
	       " | ".&get_gzip_command();
	}
elsif ($homefmt && $compression == 1) {
	# With bzip
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, @ilist).
	       " | ".&get_bzip2_command();
	}
elsif ($compression == 3) {
	# ZIP archive
	$cmd = &make_zip_command("-x\@".quotemeta($xtemp), "-", @ilist);
	}
elsif ($homefmt && $compression == 4) {
	# With zstd
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, @ilist).
	       " | ".&get_zstd_command();
	}
else {
	# Plain tar
	$cmd = &make_tar_command("cfX", "-", $xtemp, $iargs, @ilist);
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
if ($ex || !-s $destfile) {
	&unlink_file($destfile);
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
       &ui_checkbox("dir_homes", 1,
		    &text('backup_dirhomes2', $config{'homes_dir'}),
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
local $srcfile = $file;
if (!-r $srcfile) {
	($srcfile) = glob("$file.*");
	}

local $cf = &compression_format($srcfile, $key);
&$first_print($cf == 4 ? $text{'restore_dirzip'}
	    	       : $text{'restore_dirtar'});

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
my $osize = &get_compressed_file_size($srcfile, $key);
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

local $outfile = &transname();
local $errfile = &transname();
local $q = quotemeta($srcfile);
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
	&execute_command("cd $qh && unzip -o $q", undef, $outfile, $outfile);
	}
else {
	local $comp = $cf == 1 ? &get_gunzip_command()." -c" :
		      $cf == 2 ? "uncompress -c" :
		      $cf == 3 ? &get_bunzip2_command()." -c" :
		      $cf == 6 ? &get_unzstd_command() : "cat";
	local $tarcmd = &make_tar_command("xvfX", "-", $xtemp);
	local $reader = $catter." | ".$comp;
	if ($asd) {
		# Run as domain owner - disabled, as this prevents some files
		# from being written to by tar
		$tarcmd = &command_as_user($d->{'user'}, 0, $tarcmd);
		}
	&execute_command("cd $qh && $reader | $tarcmd", undef, $outfile,$errfile);
	}
local $out = &read_file_contents($outfile);
$out =~ s/\\([0-7]+)/chr(oct($1))/ge;
local $err = &read_file_contents($errfile);
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
	# Check for differential restore of newly-created domain, which
	# indicates that is is not complete
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
	
	# differential file is no longer valid, so clear it
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

	# For a non-differential restore, delete files that weren't in
	# the backup
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

		# Add standard dirs to exclude list (exclude public_html and
		# cgi-bin)
		my $phd = &public_html_dir($d, 1);
		my $cgd = &cgi_bin_dir($d, 1);
		foreach my $dir (&virtual_server_directories($d)) {
			next if ($dir->[0] eq $phd || $dir->[0] eq $cgd);
			push(@exc, $dir->[0]);
			}

		# Exclude other transient dirs
		push(@exc, ".backup.lock");
		push(@exc, $home_virtualmin_backup);
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
local @users = grep { $_->{'unix'} && !$_->{'webowner'} }
		    &list_domain_users($d, 1, 1, 1, 1);
local $gid = $d->{'gid'} || $d->{'ugid'};
foreach my $sd ($d, &get_domain_by("parent", $d->{'id'})) {
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($sd, 1);
		}
	}

# Build list of dirs to skip (sub-domain homes and user homes)
my @subhomes;
if (!$d->{'parent'}) {
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		push(@subhomes, "$sd->{'home'}/$hd/");
		}
	}
foreach my $user (@users) {
	push(@subhomes, $user->{'home'});
	}

&open_execute_command(FIND, "find ".quotemeta($d->{'home'})." ! -type l", 1);
LOOP: while(my $f = <FIND>) {
	$f =~ s/\r|\n//;
	next LOOP if ($f =~ /\/\.nodelete$/);
	next LOOP if ($f =~ /^\Q$d->{'home'}\/$hd\/\E/);
	foreach my $s (@subhomes) {
		next LOOP if ($f =~ /^\Q$s\E/);
		}
	&set_ownership_permissions($d->{'uid'}, $gid, undef, $f);
	}
close(FIND);
&set_ownership_permissions($d->{'uid'}, $gid, undef, $d->{'home'}."/".$hd);
foreach my $dir (&virtual_server_directories($d)) {
	&set_ownership_permissions(undef, undef, oct($dir->[1]),
				   $d->{'home'}."/".$dir->[0]);
	}
foreach my $user (@users) {
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
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
my $perms = $tmpl->{'web_html_perms'};
my @rv;
if (!$d->{'subdom'} && !$d->{'alias'}) {
	push(@rv, [ &public_html_dir($d, 1), $perms, 'html' ]);
	push(@rv, [ &cgi_bin_dir($d, 1), $perms, 'cgi' ]);
	}
push(@rv, [ 'logs', '750', 'logs' ]);
push(@rv, [ $config{'homes_dir'}, '755', 'homes' ]);
if (!$d->{'parent'}) {
	push(@rv, [ $home_virtualmin_backup, '700', 'backup' ]);
	}
if (!$d->{'ssl_same'}) {
	push(@rv, map { [ $_, '700', 'ssl' ] }
		      &ssl_certificate_directories($d));
	}
return @rv;
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

# File patterns to exclude from skeleton dir
print &ui_table_row(&hlink($text{'tmpl_skel_nosubs'}, "template_skel_nosubs"),
	&ui_textbox("skel_nosubs", $tmpl->{'skel_nosubs'}, 60));

# File patterns to include from skeleton dir
print &ui_table_row(&hlink($text{'tmpl_skel_onlysubs'},
			   "template_skel_onlysubs"),
	&ui_textbox("skel_onlysubs", $tmpl->{'skel_onlysubs'}, 60));

print &ui_table_hr();

# Default excludes for backups
print &ui_table_row(&hlink($text{'tmpl_exclude'}, "template_exclude"),
	&none_def_input("exclude", $tmpl->{'exclude'}, $text{'tmpl_exdirs'}, 0,
			$tmpl->{'standard'} ? 1 : 0)."<br>\n".
	&ui_textarea("exclude", $tmpl->{'exclude'} eq "none" ? undef :
			join("\n", split(/\t+/, $tmpl->{'exclude'})), 5, 60));
}

# parse_template_dir(&tmpl)
# Updates directory-related template options from %in
sub parse_template_dir
{
local ($tmpl) = @_;

# Save skeleton directory
$tmpl->{'skel'} = &parse_none_def("skel");
if ($in{'skel_mode'} == 2) {
	-d $in{'skel'} || &error($text{'tmpl_eskel'});
	$tmpl->{'skel_subs'} = $in{'skel_subs'};
	$tmpl->{'skel_nosubs'} = $in{'skel_nosubs'};
	$tmpl->{'skel_onlysubs'} = $in{'skel_onlysubs'};
	}

# Save excludes
if ($in{'exclude_mode'} == 0) {
	$tmpl->{'exclude'} = 'none';
	}
elsif ($in{'exclude_mode'} == 1) {
	delete($tmpl->{'exclude'});
	}
else {
	$tmpl->{'exclude'} = join("\t", split(/\r?\n/, $in{'exclude'}));
	}
}

# create_index_content(&domain, content, [overwrite])
# Copy default content files to the domain's HTML directory
sub create_index_content
{
local ($d, $content, $over) = @_;

# Remove any existing index.* files that might be used instead
local $dest = &public_html_dir($d);
local @indexes = grep { -f $_ } glob("$dest/index.*");
if ($over) {
	if (@indexes) {
		&unlink_file(@indexes);
		}
	}
else {
	return if (@indexes);
	}

# Find all the files to copy using a stack
my @srcs = ( $default_content_dir );
while(@srcs) {
	my @newsrcs;
	foreach my $s (@srcs) {
		foreach my $f (glob("$s/*")) {
			next if ($f =~ /^\./);
			my $rf = $f;
			$rf =~ s/^\Q$default_content_dir\E\///;
			if (-d $f) {
				&make_dir_as_domain_user($d, $dest."/".$rf, 0755);
				push(@newsrcs, $f);
				}
			else {
				my $data = &read_file_contents($f);
				my $destfile = $dest."/".$rf;
				next if (-e $destfile && !$over);
				&open_tempfile_as_domain_user(
					$d, DATA, ">".$destfile);
				if ($f =~ /\.(html|htm|txt|php|php4|php5)$/i) {
					my %hash = %$d;
					# Use default Virtualmin index.html page
					if (!$content) {
						%hash = &populate_default_index_page($d, %hash);
						$data = &replace_default_index_page($d, $data);
						$data = &substitute_virtualmin_template($data, \%hash);
						}
					# Use provided content
					else {
						# If content is a file
						if (-f $content && -r $content) {
							if (&master_admin()) {
								$data = &read_file_contents($content);
								}
							else {
								$data = &read_file_contents_as_domain_user($d, $content);
								}
							}
						else {
							$data = $content;
							}
						$data = &substitute_virtualmin_template($data, \%hash);
						}
					}
				&print_tempfile(DATA, $data);
				&close_tempfile_as_domain_user($d, DATA);
				}
			}
		}
	@srcs = @newsrcs;
	}
}

# remote_dir(&domain)
# Returns 1 if the domain's home dir is on a remote server
sub remote_dir
{
local ($d) = @_;
my ($home_mtab, $home_fstab) = &mount_point($d->{'home'});
my $tab = $home_mtab || $home_fstab;
return $tab && $tab->[1] =~ /^[a-z0-9\.\_\-]+:/i ? $tab->[1] : undef;
}

# can_reset_dir(&domain)
# Resetting the home directory feature doesn't make any sense ever
sub can_reset_dir
{
return 0;
}

# safe_delete_dir(&domain, dir)
# Returns 1 if a directory for a domain can be safely removed
sub safe_delete_dir
{
my ($d, $dir) = @_;
return 0 if ($dir eq '');
$dir = &simplify_path($dir);
return 0 if (!defined($dir));
return $dir eq '/' ||
       &is_under_directory('/root', $dir) ||
       &is_under_directory('/etc', $dir) ||
       &same_file($dir, '/usr') ||
       &same_file($dir, $home_base) ||
       &is_under_directory($root_directory, $dir) ||
       !&is_under_directory($d->{'home'}, $dir) ? 0 : 1;
}

$done_feature_script{'dir'} = 1;

1;

