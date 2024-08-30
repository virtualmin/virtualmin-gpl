# Functions for setting up jails for domain owners

# check_jailkit_support()
# Returns an error message if jailing users is not available, undef otherwise
sub check_jailkit_support
{
if (!&has_command('jk_init')) {
	return &text('jailkit_ecmd', '<tt>jk_init</tt>');
	}
if ($gconfig{'os_type'} !~ /-linux$/) {
	return $text{'jailkit_elinux'};
	}
return undef;
}

# domain_jailkit_dir(&domain)
# Returns the jailkit directory for a domain
sub domain_jailkit_dir
{
my ($d) = @_;
return $config{'jailkit_root'}."/".$d->{'id'};
}

# enable_domain_jailkit(&domain)
# Sets up a chroot jail for a domain
sub enable_domain_jailkit
{
my ($d) = @_;
$d->{'parent'} && return $text{'jailkit_eparent'};

# Create root dir if missing
if (!-d $config{'jailkit_root'}) {
	&make_dir($config{'jailkit_root'}, 0755) ||
		return &text('jailkit_emkdir', $!);
	}

# Create a jail for the domain
my $dir = &domain_jailkit_dir($d);
my $err = &copy_jailkit_files($d, $dir);
return $err if ($err);

# Bind mount the home dir into the chroot
&foreign_require("mount");
my $jailhome = $dir.$d->{'home'};
if (!-d $jailhome) {
	&make_dir($jailhome, 755, 1);
	}
my ($already) = grep { $_->[0] eq $jailhome } &mount::list_mounted();
if (!$already) {
	my $err = &mount::mount_dir(
		$jailhome, $d->{'home'}, "bind", "defaults");
	if ($err) {
		return &text('jailkit_emount', $err);
		}
	}
foreach $f (&mount::files_to_lock()) {
	&lock_file($f);
	}
my ($already) = grep { $_->[0] eq $jailhome } &mount::list_mounts();
if (!$already) {
	&mount::create_mount($jailhome, $d->{'home'}, "bind", "defaults");
	}
foreach $f (&mount::files_to_lock()) {
	&unlock_file($f);
	}

# Create a fake /etc/passwd file in the jail
&create_jailkit_passwd_file($d);

# Modify the domain user's home dir and shell
&require_useradmin();
foreach my $uinfo (&list_domain_users($d, 0, 0, 1, 1, 0)) {
	my $duser = $uinfo->{'user'};
	my $olduinfo = { %$uinfo };
	if ($uinfo->{'shell'} !~ /\/jk_chrootsh$/) {
		$uinfo->{'shell'} = &has_command("jk_chrootsh") ||
				    "/usr/sbin/jk_chrootsh";
		}
	$uinfo->{'home'} = $dir."/.".$uinfo->{'home'}
		if ($uinfo->{'home'} !~ /^\Q$dir\E\/\./);
	&foreign_call($usermodule, "set_user_envs", $uinfo,
		'MODIFY_USER', $plainpass, [], $olduinfo);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
	&foreign_call($usermodule, "made_changes");
	}

# Set chroot for all domains' PHP-FPM configs
foreach my $pd ($d, &get_domain_by("parent", $d->{'id'})) {
	my $mode = &get_domain_php_mode($pd);
	if ($mode eq "fpm") {
		&save_php_fpm_config_value($pd, "chroot", $dir);
		}
	}

# If MySQL has a socket file, duplicate it in
if ($config{'mysql'}) {
	&require_mysql();
	my $cnf = &mysql::get_mysql_config();
	my $socket;
	if ($cnf) {
		my ($mysqld) = grep { $_->{'name'} eq 'mysqld' } @$cnf;
		if ($mysqld) {
			$socket = &mysql::find_value("socket", $mysqld->{'members'});
			}
		}
	if ($socket) {
		# Got a path to copy into the chroot
		my $socketdir = $socket;
		$socketdir =~ s/\/[^\/]+$//;
		&make_dir($dir.$socketdir, 0755, 1);
		&system_logged("ln ".quotemeta($socket)." ".
			       quotemeta($dir.$socket)." >/dev/null 2>&1");
		}
	}

# Add the jailkit shell to /etc/shells if missing
my $sf = "/etc/shells";
my $lref = &read_file_lines($sf);
my $found = 0;
foreach my $l (@$lref) {
	my $ll = $l;
	$ll =~ s/#.*$//;
	$found++ if ($ll eq $uinfo->{'shell'});
	}
if ($found) {
	&unflush_file_lines($sf);
	}
else {
	push(@$lref, $uinfo->{'shell'});
	&flush_file_lines($sf);
	}

return undef;
}

# disable_domain_jailkit(&domain, [deleting-domain])
# Return a domain to regular non-chroot mode
sub disable_domain_jailkit
{
my ($d, $deleting) = @_;
$d->{'parent'} && return $text{'jailkit_eparent'};
my $dir = &domain_jailkit_dir($d);

# Turn off chroot for all domains' PHP-FPM configs
foreach my $pd ($d, &get_domain_by("parent", $d->{'id'})) {
	my $mode = &get_domain_php_mode($pd);
	if ($mode eq "fpm") {
		&save_php_fpm_config_value($pd, "chroot", undef);
		}
	}

# Switch back the user's shell and home dir
&require_useradmin();
foreach my $uinfo (&list_domain_users($d, 0, 0, 1, 1, 0)) {
	my $duser = $uinfo->{'user'};
	my $olduinfo = { %$uinfo };
	if ($uinfo->{'shell'} =~ /\/jk_chrootsh$/) {
		$uinfo->{'shell'} = $uinfo->{'jailed'}->{'shell'} ||
				    '/bin/false'; # must never happen
		}
	if ($uinfo->{'home'} =~ s/^\Q$dir\E\/\.//) {
		&foreign_call($usermodule, "set_user_envs", $uinfo,
			'MODIFY_USER', $plainpass, [], $olduinfo);
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
		&foreign_call($usermodule, "made_changes");
		}
	}

# Remove the BIND mount
&foreign_require("mount");
my $jailhome = $dir.$d->{'home'};
foreach $f (&mount::files_to_lock()) { &lock_file($f); }
my @mounted = &mount::list_mounted();
my ($mounted) = grep { $_->[0] eq $jailhome } @mounted;
if ($mounted) {
	my $err = &mount::unmount_dir(
		$mounted->[0], $mounted->[1], $mounted->[2], undef, 1);
	if ($err) {
		return &text('jailkit_eumount', $err);
		}
	}
foreach $f (&mount::files_to_lock()) { &unlock_file($f); }
my @mounts = &mount::list_mounts();
my ($mount) = grep { $_->[0] eq $jailhome } @mounts;
if ($mount) {
	my $idx = &indexof($mount, @mounts);
	if ($idx > 0) {
		&mount::delete_mount($idx);
		}
	}

# Delete the jail dir, but only if completely removing the domain
if ($deleting && $dir && -d $dir &&
    &is_under_directory($config{'jailkit_root'}, $dir)) {
	&unlink_logged($dir);
	}

return undef;
}

# get_domain_jailkit(&domain)
# Returns the root if jailing is enabled for the domain, undef otherwise
sub get_domain_jailkit
{
my ($d) = @_;
my $dir = &domain_jailkit_dir($d);
my $uinfo = &get_domain_owner($d, 1, 1, 1);
return $uinfo && $uinfo->{'home'} =~ /^\Q$dir\E\/\.\// ? $dir : undef;
}

# create_jailkit_passwd_file(&domain)
# Create limited /etc/passwd, /etc/shadow and /etc/group files inside a jail
# for a domain's users
sub create_jailkit_passwd_file
{
my ($d) = @_;
my $dir = &domain_jailkit_dir($d);
return undef if (!-d $dir);		# Jailing isn't enabled
return undef if (!-d "$dir/etc");	# Jail directory is invalid

# Build a list of users and groups that are either system-related, or
# associated with this domain
&require_useradmin();
my (@ucreate, @gcreate);
foreach my $u (&list_all_users()) {
	push(@ucreate, $u) if ($u->{'uid'} < 500);
	}
foreach my $g (&list_all_groups()) {
	push(@gcreate, $g) if ($g->{'gid'} < 500 ||
			       $g->{'group'} eq $d->{'group'} ||
                               $g->{'group'} eq $d->{'ugroup'});
	}
foreach my $sd ($d, &get_domain_by("parent", $d->{'id'})) {
	push(@ucreate, &list_domain_users($sd, 0, 1, 1, 1));
	}

# Write out chosen users to the jail passwd file
my $pfile = $dir."/etc/passwd";
my $sfile = $dir."/etc/shadow";
my %jail_shell = map { $_->{'user'} => $_->{'shell'} }
		     &get_domain_jailed_users_shell($d);
&open_lock_tempfile(PASSWD, ">$pfile");
&open_lock_tempfile(SHADOW, ">$sfile");
foreach my $u (@ucreate) {
	my $shell = $u->{'shell'};
	$shell = $jail_shell{$u->{'user'}} if ($shell =~ /\/jk_chrootsh$/);
	my $home = $u->{'home'};
	$home =~ s/^\Q$dir\E\/\.//;
	my @pline = ( $u->{'user'}, "x", $u->{'uid'}, $u->{'gid'},
		      $u->{'real'}, $home, $shell );
	my @sline = ( $u->{'user'}, $u->{'pass'}, "", "", "", "", "", "", "" );
	&print_tempfile(PASSWD, join(":", @pline),"\n");
	&print_tempfile(SHADOW, join(":", @sline),"\n");
	}
&close_tempfile(SHADOW);
&close_tempfile(PASSWD);
&set_ownership_permissions(undef, undef, 0644, $pfile);
&set_ownership_permissions(undef, undef, 0600, $sfile);

# Write out chosen groups to the jail group file
my $gfile = $dir."/etc/group";
&open_lock_tempfile(GROUP, ">$gfile");
foreach my $g (@gcreate) {
	my @gline = ( $g->{'group'}, "x", $g->{'gid'}, $g->{'members'} );
	&print_tempfile(GROUP, join(":", @gline),"\n");
	}
&close_tempfile(GROUP);
}

# rename_jailkit_passwd_file(&domain, old-user, new-user)
# Rename one user in a jail's /etc/passwd file
sub rename_jailkit_passwd_file
{
my ($d, $olduser, $newuser) = @_;
my $dir = &domain_jailkit_dir($d);
foreach my $file ($dir."/etc/passwd", $dir."/etc/shadow") {
	next if (!-r $file);
	&lock_file($file);
	my $lref = &read_file_lines($file);
	foreach my $l (@$lref) {
		if ($l =~ /^\Q$olduser\E:/) {
			$l =~ s/^\Q$olduser\E/$newuser/;
			}
		}
	&flush_file_lines($file);
	&unlock_file($file);
	}
}

# modify_jailkit_user(&domain, username)
# Update a real Unix user in a jailed domain to have the correct jailed
# shell and home directory
sub modify_jailkit_user
{
my ($d, $user) = @_;
return if (!$d->{'jail'});	# Jailing isn't enabled
my $dir = &domain_jailkit_dir($d);
return if (!-d $dir);		# Jailing isn't enabled
return if (!-d "$dir/etc");	# Jail directory is invalid
my $olduser = { %$user };
$user->{'shell'} = &has_command("jk_chrootsh") ||
			"/usr/sbin/jk_chrootsh";
$user->{'home'} = $dir."/.".$user->{'home'}
	if ($user->{'home'} !~ /^\Q$dir\E/);
&foreign_call($usermodule, "set_user_envs", $user,
	'MODIFY_USER', $plainpass, [], $olduser);
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "modify_user", $olduser, $user);
&foreign_call($usermodule, "made_changes");
}

# copy_jailkit_files(&domain, [dir])
# Copy files for various jail sections
sub copy_jailkit_files
{
my ($d, $dir) = @_;
$dir ||= &domain_jailkit_dir($d);
$dir || return $text{'jailkit_edir'};

# Use jk_init to copy in standard file sets
foreach my $sect ("perl", "basicshell", "extendedshell", "ssh", "scp", "sftp",
		  "editors", "netutils", "php", "logbasics",
		  split(/\s+/, $config{'jail_sects'}),
		  split(/\s+/, $d->{'jail_esects'})) {
	my $cmd = "jk_init -f -j ".quotemeta($dir)." ".$sect;
	my ($out, $err);
	&execute_command($cmd, undef, \$out, \$err);
	if ($?) {
		return &text('jailkit_einit', $err);
		}
	}

# Use jk_cp to copy in any other files/directories
foreach my $jail_cmd (split(/\s+/, $d->{'jail_ecmds'})) {
	my $jail_cmd_real = &has_command($jail_cmd);
	next if (!$jail_cmd_real && $jail_cmd !~ /^\/\S+$/);
	my $cmd = "jk_cp -j ".quotemeta($dir)." -f ". ($jail_cmd_real || $jail_cmd);
	my ($out, $err);
	&execute_command($cmd, undef, \$out, \$err);
	if ($?) {
		return &text('jailkit_einit2', $jail_cmd, $err);
		}
	}

# Make sure /tmp exists
my $tmp = "$dir/tmp";
if (!-d $tmp) {
	&make_dir($tmp, 01777);
	}

# Copy in timezone files
foreach my $zdir ("/usr/share/zoneinfo") {
	next if (!-d $zdir);
	&make_dir($dir.$zdir, 0755, 1) if (!-d $dir.$zdir);
	&copy_source_dest($zdir, $dir.$zdir);
	}

# Remove write permissions for group
&remove_write_permissions_for_group($dir,
	["$dir/tmp", 
	 "$dir$d->{'home'}/$home_virtualmin_backup"]);

$d->{'jail_last_copy'} = time();
return undef;
}

# copy_all_domain_jailkit_files()
# For all domains with a jail enabled and which haven't copied files in the
# last 24 hours, copy them now
sub copy_all_domain_jailkit_files
{
foreach my $d (&list_domains()) {
	next if ($d->{'parent'});
	my $dir = &domain_jailkit_dir($d);
	next if (!$dir || !-d $dir);
	if ($config{'jail_age'} &&
	    time() - $d->{'jail_last_copy'} > $config{'jail_age'}*3600) {
		# Time to sync
		&lock_domain($d);
		$d = &get_domain($d->{'id'}, undef, 1);
		&copy_jailkit_files($d, $dir);
		$d->{'jail_last_copy'} = time();
		&save_domain($d);
		&unlock_domain($d);
		}
	}
}

# get_domain_jailed_users_shell(&domain)
# Get the actual jailed users info in the domain
sub get_domain_jailed_users_shell
{
my ($d) = @_;
return if (!$d->{'jail'});
my $dir = &domain_jailkit_dir($d);
my $pfile = $dir."/etc/passwd";
return if (!-r $pfile);
my $sfile = $dir."/etc/shadow";
return &list_users_from($pfile, $sfile);
}

1;
