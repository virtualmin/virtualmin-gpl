# Functions for setting up jails for domain owners

# check_jailkit_support()
# Returns an error message if jailing users is not available, undef otherwise
sub check_jailkit_support
{
if (!&foreign_check("jailkit")) {
	return $text{'jailkit_emodule'};
	}
if (!&foreign_installed("jailkit")) {
	return $text{'jailkit_emodule2'};
	}
if ($gconfig{'os_type'} !~ /^linux-/) {
	return $text{'jailkit_elinux'};
	}
return undef;
}

# domain_jailkit_dir(&domain)
# Returns the jailkit directory for a domain
sub domain_jailkit_dir
{
my ($d) = @_;
return $config{'jailkit_root'}."/".$d->{'dom'};
}

# enable_domain_jailkit(&domain)
# Sets up a chroot jail for a domain
sub enable_domain_jailkit
{
my ($d) = @_;
&foreign_require("jailkit");

# Create root dir if missing
if (!-d $config{'jailkit_root'}) {
	&make_dir($config{'jailkit_root'}, 0755);
	}

# Create a jail for the domain
my $dir = &domain_jailkit_dir($d);
my $sect = "perl";
my $cmd = "jk_init -j ".quotemeta($dir)." ".$sect;
my ($out, $err);
&execute_command($cmd, undef, \$out, \$err);
if ($?) {
	return &text('jailkit_einit', $err);
	}

# Bind mount the home dir into the chroot
&foreign_require("mount");
my $jailhome = $dir.$d->{'home'};
&make_dir($jailhome, 755);
my $err = &mount::mount_dir($jailhome, $d->{'home'}, "bind", "defaults");
if ($err) {
	return &text('jailkit_emount', $err);
	}
&mount::create_mount($jailhome, $d->{'home'}, "bind", "defaults");

# Modify the domain user's home dir and shell
&require_useradmin();
my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } &list_all_users();
if (!$uinfo) {
	return &text('jailkit_euser', $d->{'user'});
	}
my $olduinfo = { %$uinfo };
$uinfo->{'shell'} = &has_command("jk_chrootsh") || "/usr/sbin/jk_chrootsh";
$uinfo->{'home'} = $dir."/.".$d->{'home'};
&foreign_call($usermodule, "set_user_envs", $uinfo,
	      'MODIFY_USER', $plainpass, [], $olduinfo);
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
&foreign_call($usermodule, "made_changes");

return undef;
}

# disable_domain_jailkit(&domain)
# Return a domain to regular non-chroot mode
sub disable_domain_jailkit
{
my ($d) = @_;
&foreign_require("jailkit");
}

# get_domain_jailkit(&domain)
sub get_domain_jailkit
{
my ($d) = @_;
&foreign_require("jailkit");
}

1;
