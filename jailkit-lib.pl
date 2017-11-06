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
foreach $f (&mount::files_to_lock()) { &lock_file($f); }
my ($already) = grep { $_->[0] eq $jailhome } &mount::list_mounts();
if (!$already) {
	&mount::create_mount($jailhome, $d->{'home'}, "bind", "defaults");
	}
foreach $f (&mount::files_to_lock()) { &unlock_file($f); }

# Modify the domain user's home dir and shell
&require_useradmin();
my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } &list_all_users();
if (!$uinfo) {
	return &text('jailkit_euser', $d->{'user'});
	}
my $olduinfo = { %$uinfo };
if ($uinfo->{'shell'} !~ /\/jk_chrootsh$/) {
	$d->{'unjailed_shell'} = $uinfo->{'shell'};
	$uinfo->{'shell'} = &has_command("jk_chrootsh") ||
			    "/usr/sbin/jk_chrootsh";
	}
$uinfo->{'home'} = $dir."/.".$d->{'home'};
&foreign_call($usermodule, "set_user_envs", $uinfo,
	      'MODIFY_USER', $plainpass, [], $olduinfo);
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
&foreign_call($usermodule, "made_changes");

# Create a fake /etc/passwd file in the jail
&create_jailkit_passwd_file($d);

# Set chroot for all domains' PHP-FPM configs
foreach my $pd ($d, &get_domain_by("parent", $d->{'id'})) {
	my $mode = &get_domain_php_mode($pd);
	next if ($mode ne "fpm");
	&save_php_fpm_config_value($pd, "chroot", $dir);
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
	next if ($mode ne "fpm");
	&save_php_fpm_config_value($pd, "chroot", undef);
	}

# Switch back the user's shell and home dir
&require_useradmin();
my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } &list_all_users();
if (!$uinfo) {
	return &text('jailkit_euser', $d->{'user'});
	}
my $olduinfo = { %$uinfo };
if ($uinfo->{'shell'} =~ /\/jk_chrootsh$/) {
	$uinfo->{'shell'} = $d->{'unjailed_shell'};
	delete($d->{'unjailed_shell'});
	}
if ($uinfo->{'home'} =~ s/^\Q$dir\E\/\.//) {
	&foreign_call($usermodule, "set_user_envs", $uinfo,
		      'MODIFY_USER', $plainpass, [], $olduinfo);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
	&foreign_call($usermodule, "made_changes");
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
# Create limit /etc/passwd, /etc/shadow and /etc/group files inside a jail
# for a domain's users
sub create_jailkit_passwd_file
{
my ($d) = @_;
my $dir = &domain_jailkit_dir($d);
return undef if (!-d $dir);		# Jailing isn't enabled

# Build a list of users and groups that are either system-related, or
# associated with this domain
&require_useradmin();
my @ucreate;
foreach my $u (&list_all_users()) {
	push(@ucreate, $u) if ($u->{'uid'} < 500);
	}
push(@ucreate, &list_domain_users($d, 0, 1, 1, 1));
my @gcreate;
foreach my $g (&list_all_groups()) {
	push(@gcreate, $g) if ($g->{'gid'} < 500 ||
			       $g->{'group'} eq $d->{'group'} ||
			       $g->{'group'} eq $d->{'ugroup'});
	}

# Write out chosen users to the jail passwd file
my $pfile = $dir."/etc/passwd";
my $sfile = $dir."/etc/shadow";
&open_lock_tempfile(PASSWD, ">$pfile");
&open_lock_tempfile(SHADOW, ">$sfile");
foreach my $u (@ucreate) {
	my $shell = $u->{'shell'};
	if ($shell =~ /\/jk_chrootsh$/) {
		# Put back real shell
		$shell = $u->{'domainowner'} ? $d->{'unjailed_shell'}
					     : "/bin/false";
		}
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

# Write out chosen groups to the jail group file
my $gfile = $dir."/etc/group";
&open_lock_tempfile(GROUP, ">$gfile");
foreach my $g (@gcreate) {
	my @gline = ( $g->{'group'}, "x", $g->{'gid'}, $g->{'members'} );
	&print_tempfile(GROUP, join(":", @gline),"\n");
	}
&close_tempfile(GROUP);
}

# copy_jailkit_files(&domain, [dir])
# Copy files for various jail sections
sub copy_jailkit_files
{
my ($d, $dir) = @_;
$dir ||= &domain_jailkit_dir($d);
foreach my $sect ("perl", "basicshell", "extendedshell", "ssh", "scp",
		  "editors", "netutils", "php",
		  split(/\s+/, $config{'jail_sects'})) {
	my $cmd = "jk_init -f -j ".quotemeta($dir)." ".$sect;
	my ($out, $err);
	&execute_command($cmd, undef, \$out, \$err);
	if ($?) {
		return &text('jailkit_einit', $err);
		}
	&system_logged("chmod g-w ".quotemeta($dir)."/*");
	}
my $tmp = "$dir/tmp";
if (!-d $tmp) {
	&make_dir($tmp, 01777);
	}
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
		&copy_jailkit_files($d, $dir);
		$d->{'jail_last_copy'} = time();
		&save_domain($d);
		}
	}
}

1;
