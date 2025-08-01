# Functions for managing a domain's Unix user

$feature_depends{'unix'} = [ 'dir' ];

# setup_unix(&domain)
# Creates the Unix user and group for a domain
sub setup_unix
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
&obtain_lock_unix($d);
&require_useradmin();
my (%uinfo, %ginfo);

# Do some sanity checks
if ($d->{'user'} eq '') {
	&error("Domain is missing Unix username!");
	}
if ($d->{'group'} eq '') {
	&error("Domain is missing Unix group name!");
	}
if ($d->{'ugroup'} eq '') {
	&error("Domain is missing Unix group name for the domain owner!");
	}
if ($d->{'group'} ne $d->{'ugroup'} && !getgrnam($d->{'ugroup'})) {
	&error("Unix group for the domain owner $d->{'ugroup'} does not exist!");
	}

# Check if the UID or GID has been allocated to someone else, and if so
# re-allocate them. Also allocate if they haven't been done yet.
my @allusers = &list_all_users();
my ($uclash) = grep { $_->{'user'} eq $d->{'user'} } @allusers;
if ($uclash && &remote_unix() && $d->{'wasmissing'}) {
	# Domain is being re-created as part of a restore and users are stored
	# remotely, and the user already exists. Assume shared LDAP storage.
	goto QUOTAS;
	}
my ($clash) = grep { $_->{'uid'} == $d->{'uid'} } @allusers;
if ($clash || !$d->{'uid'}) {
	my (%taken, %utaken);
	&build_taken(\%taken, \%utaken, \@allusers);
	$d->{'uid'} = &allocate_uid(\%taken);
	}
my @allgroups = &list_all_groups();
my ($gclash) = grep { $_->{'gid'} == $d->{'gid'} } @allgroups;
if ($gclash || !$d->{'gid'}) {
	my (%gtaken, %ggtaken);
	&build_group_taken(\%gtaken, \%ggtaken, \@allgroups);
	$d->{'gid'} = &allocate_gid(\%gtaken);
	}
$d->{'ugid'} = $d->{'gid'} if ($d->{'ugid'} eq '');

if ($d->{'gid'} == $d->{'ugid'}) {
	# Create the group
	&$first_print(&text('setup_group', $d->{'group'}));
	%ginfo = ( 'group', $d->{'group'},
		   'gid', $d->{'gid'},
		 );
	eval {
		local $main::error_must_die = 1;
		&foreign_call($usermodule, "set_group_envs", \%ginfo,
			      'CREATE_GROUP');
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "create_group", \%ginfo);
		&foreign_call($usermodule, "made_changes");
		};
	my $err = $@;
	if ($err || !&wait_for_group_to_exist($d->{'group'})) {
		&delete_partial_group(\%ginfo);
		&$second_print($err ? &text('setup_ecrgroup2', $err)
				    : $text{'setup_ecrgroup'});
		&release_lock_unix($d);
		return 0;
		}
	&$second_print($text{'setup_done'});
	}
else {
	# Server has no group!
	delete($d->{'gid'});
	delete($d->{'group'});
	}

# Work out the shell, which can come from the template
my $shell = $d->{'defaultshell'} || $tmpl->{'ushell'};
if ($shell eq 'none' || !$shell) {
	$shell = &default_available_shell('owner');
	}

# Then the user
&$first_print(&text('setup_user', $d->{'user'}));
%uinfo = ( 'user', $d->{'user'},
	   'uid', $d->{'uid'},
	   'gid', $d->{'ugid'},
	   'pass', $d->{'enc_pass'} ||
		   &useradmin::encrypt_password($d->{'pass'}),
	   'real', $d->{'owner'},
	   'home', $d->{'home'},
	   'shell', $shell,
	   'mailbox', $d->{'user'},
	   'dom', $d->{'dom'},
	   'dom_prefix', substr($d->{'dom'}, 0, 1),
	   'plainpass', $d->{'pass'},
	   'domainowner', 1,
	   'unix', 1,
	   'email', $d->{'user'}.'\@'.$d->{'dom'},
	 );
&set_pass_change(\%uinfo);
eval {
	local $main::error_must_die = 1;
	&foreign_call($usermodule, "set_user_envs", \%uinfo,
		      'CREATE_USER', $d->{'pass'}, [ ]);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "create_user", \%uinfo);
	&foreign_call($usermodule, "made_changes");
	if ($config{'other_users'} || $config{'other_doms'}) {
		&create_domain_home_directory($d, \%uinfo);
		&foreign_call($usermodule, "other_modules",
			      "useradmin_create_user", \%uinfo);
		}
	};
my $err = $@;
if ($err || !&wait_for_user_to_exist($d->{'user'})) {
	&delete_partial_group(\%ginfo) if (%ginfo);
	&delete_partial_user(\%uinfo);
	&$second_print($err ? &text('setup_ecruser2', $err)
			    : $text{'setup_ecruser'});
	&release_lock_unix($d);
	return 0;
	}
&$second_print($text{'setup_done'});

# Set the user's quota
QUOTAS:
if (&has_home_quotas()) {
	&set_server_quotas($d);
	}

# Create virtuser pointing to new user, and possibly generics entry
if ($d->{'mail'}) {
	&$first_print($text{'setup_usermail2'});
	&create_email_for_unix($d);
	&$second_print($text{'setup_done'});
	}

# Add to denied SSH group and domain owner group. Don't let the failure of
# this block the whole user creation though
&$first_print($text{'setup_usergroups'});
eval {
	local $main::error_must_die = 1;
	&build_denied_ssh_group($d);
	&update_domain_owners_group($d);
	};
if ($@) {
	&$second_print(&text('setup_eusergroups', "$@"));
	}
else {
	&$second_print($text{'setup_done'});
	}

# Setup resource limits from template
if (defined(&supports_resource_limits) && $tmpl->{'resources'} ne 'none' &&
    &supports_resource_limits()) {
	my $rv = { map { split(/=/, $_) }
		split(/\s+/, $tmpl->{'resources'}) };
	&save_domain_resource_limits($d, $rv, 1);
	}

&release_lock_unix($d);
return 1;
}

# modify_unix(&domain, &olddomain)
# Change the password and real name for a domain unix user
sub modify_unix
{
my ($d, $oldd) = @_;
if (!$d->{'pass_set'} &&
    $d->{'user'} eq $oldd->{'user'} &&
    $d->{'home'} eq $oldd->{'home'} &&
    $d->{'mail'} == $oldd->{'mail'} &&
    $d->{'owner'} eq $oldd->{'owner'} &&
    $d->{'group'} eq $oldd->{'group'} &&
    $d->{'quota'} eq $oldd->{'quota'} &&
    $d->{'uquota'} eq $oldd->{'uquota'} &&
    $d->{'parent'} eq $oldd->{'parent'}) {
	# Nothing important has changed, so return now
	return 1;
	}
if (!$d->{'parent'}) {
	# Check for a user change
	&obtain_lock_unix($d);
	&require_useradmin();
	my @allusers = &list_domain_users($oldd);
	my ($uinfo) = grep { $_->{'user'} eq $oldd->{'user'} } @allusers;
	my $rv;
	if (defined(&supports_resource_limits) &&
	    &supports_resource_limits() &&
	    ($d->{'user'} ne $oldd->{'user'} ||
	     $d->{'group'} ne $oldd->{'group'})) {
		# Get old resource limits, and clear
		$rv = &get_domain_resource_limits($oldd);
		&save_domain_resource_limits($oldd, { }, 1);
		}
	if ($uinfo) {
		my %old = %$uinfo;
		&$first_print($text{'save_user'});
		$uinfo->{'real'} = $d->{'owner'};
		if ($d->{'pass_set'}) {
			# Update the Unix user's password
			my $enc;
			if ($d->{'pass'}) {
				$enc = &foreign_call($usermodule,
					"encrypt_password", $d->{'pass'});
				delete($d->{'enc_pass'});# Any stored encrypted
							 # password is not valid
				}
			else {
				$enc = $d->{'enc_pass'};
				}
			if ($d->{'disabled'}) {
				# Just keep for later use when enabling
				$d->{'disabled_oldpass'} = $enc;
				}
			else {
				# Set password now
				$uinfo->{'pass'} = $enc;
				$uinfo->{'pass_unix'} = $enc;
				}
			$uinfo->{'plainpass'} = $d->{'pass'};
			&set_pass_change($uinfo);
			&set_usermin_imap_password($uinfo);
			foreach my $f (&list_mail_plugins()) {
				&plugin_call($f, "mailbox_modify", $uinfo, \%old, $d);
				}
			}
		else {
			# Password not changing
			$uinfo->{'passmode'} = 4;
			}

		if ($d->{'user'} ne $oldd->{'user'}) {
			# Unix user was re-named
			$uinfo->{'olduser'} = $oldd->{'user'};
			$uinfo->{'user'} = $d->{'user'};
			&rename_mail_file($uinfo, \%old);
			&obtain_lock_cron($d);
			&rename_unix_cron_jobs($d->{'user'},
					       $oldd->{'user'});
			if (&is_domain_jailed($d)) {
				&rename_jailkit_passwd_file(
				    $d, $oldd->{'user'}, $d->{'user'});
				}
			&release_lock_cron($d);
			}

		if ($d->{'home'} ne $oldd->{'home'}) {
			# Home directory was changed
			if ($uinfo->{'home'} =~ /^(.*)\/\.\//) {
				# Under a chroot, separated by /.
				$uinfo->{'home'} = $1."/.".$d->{'home'};
				}
			else {
				$uinfo->{'home'} = $d->{'home'};
				}
			}

		if ($d->{'owner'} ne $oldd->{'owner'}) {
			# Domain description was changed
			$uinfo->{'real'} = $d->{'owner'};
			}

		&modify_user($uinfo, \%old, undef);

		if ($config{'other_doms'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_modify_user", $uinfo, \%old);
			}

		&$second_print($text{'setup_done'});
		}

	if (&has_home_quotas() && $access{'edit'} == 1) {
		# Update the unix user's and domain's quotas (if changed)
		if ($d->{'quota'} != $oldd->{'quota'} ||
		    $d->{'uquota'} != $oldd->{'uquota'}) {
			&$first_print($text{'save_quota'});
			&set_server_quotas($d);
			&$second_print($text{'setup_done'});
			}
		}

	# Check for a group change
	my ($ginfo) = grep { $_->{'group'} eq $oldd->{'group'} }
			      &list_all_groups();
	if ($ginfo && $d->{'group'} ne $oldd->{'group'}) {
		my %old = %$ginfo;
		&$first_print($text{'save_group'});
		$ginfo->{'group'} = $d->{'group'};
		&foreign_call($usermodule, "set_group_envs", $ginfo,
					   'MODIFY_GROUP', \%old);
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "modify_group", \%old, $ginfo);
		&foreign_call($usermodule, "made_changes");
		&$second_print($text{'setup_done'});
		}

	if ($rv) {
		# Put back resource limits, perhaps under new name
		&save_domain_resource_limits($d, $rv, 1);
		}
	&release_lock_unix($d);
	}
elsif ($d->{'parent'} && !$oldd->{'parent'}) {
	# Unix feature has been turned off .. so delete the user and group
	&delete_unix($oldd);
	}
if ($d->{'mail'} && !$oldd->{'mail'}) {
	# Add email for the domain user
	&$first_print($text{'setup_usermail2'});
	&create_email_for_unix($d);
	&$second_print($text{'setup_done'});
	}
}

# delete_unix(&domain)
# Delete the unix user and group for a domain
sub delete_unix
{
my ($d, $preserve) = @_;

if (!$d->{'parent'}) {
	# Get the user object
	&obtain_lock_unix($d);
	&obtain_lock_cron($d);
	&require_useradmin();
	my @allusers = &foreign_call($usermodule, "list_users");
	my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @allusers;

	# Zero his quotas
	if ($uinfo) {
		&set_user_quotas($uinfo->{'user'}, 0, 0, $d);
		}

	# Delete his cron jobs
	&delete_unix_cron_jobs($d->{'user'});

	# Delete virtuser and generic
	my @virts = &list_virtusers();
	my $email = $d->{'user'}."\@".$d->{'dom'};
	my ($virt) = grep { $_->{'from'} eq $email } @virts;
	if ($virt) {
		&delete_virtuser($virt);
		&sync_alias_virtuals($d);
		}
	if ($config{'generics'}) {
		my %generics = &get_generics_hash();
		my $g = $generics{$d->{'user'}};
		if ($g) {
			&delete_generic($g);
			}
		}

	# Delete his mail file
	if ($uinfo && !$uinfo->{'nomailfile'}) {
		&delete_mail_file($uinfo);
		}

	# Clear any resource limits
	if (defined(&supports_resource_limits) && &supports_resource_limits()) {
		&save_domain_resource_limits($d, { }, 1);
		}

	# Undo the chroot, if any
	if (!&check_jailkit_support() && &get_domain_jailkit($d)) {
		&disable_domain_jailkit($d);
		}

	# Delete unix user (unless on remote and we are keeping
	# remote resources)
	if (!$preserve || !&remote_unix($d)) {
		if ($uinfo) {
			&$first_print($text{'delete_user'});
			&delete_user($uinfo, $d);
			if ($config{'other_doms'}) {
				&foreign_call($usermodule, "other_modules",
					      "useradmin_delete_user", $uinfo);
				}
			&$second_print($text{'setup_done'});
			}

		# Delete unix group
		my @allgroups = &foreign_call($usermodule, "list_groups");
		my ($ginfo) = grep { $_->{'group'} eq $d->{'group'} }
				      @allgroups;
		if ($ginfo) {
			&$first_print($text{'delete_group'});
			&foreign_call($usermodule, "set_group_envs", $ginfo,
				      'DELETE_GROUP');
			&foreign_call($usermodule, "making_changes");
			&foreign_call($usermodule, "delete_group", $ginfo);
			&foreign_call($usermodule, "made_changes");
			&$second_print($text{'setup_done'});
			}
		&record_old_uid($uinfo->{'uid'}, $uinfo->{'gid'});
		}
	else {
		&$first_print($text{'delete_user'});
		&$second_print(&text('delete_remoteuser',
				     &get_user_database_url()));
		}
	&release_lock_unix($d);
	&release_lock_cron($d);
	}

# Update any groups
&build_denied_ssh_group(undef, $d);
&update_domain_owners_group(undef, $d);
return 1;
}

# clone_unix(&domain, &src-domain)
# Copy crontab for a Unix user to a new cloned domain
sub clone_unix
{
my ($d, $oldd) = @_;
&$first_print($text{'clone_unix'});
&obtain_lock_unix($d);
&obtain_lock_cron($d);

# Copy cron jobs, adjust paths
&copy_unix_cron_jobs($d->{'user'}, $oldd->{'user'});

# Copy resource limits
if (defined(&supports_resource_limits) && &supports_resource_limits()) {
	my $olimits = &get_domain_resource_limits($oldd);
	&save_domain_resource_limits($d, $olimits);
	}

# Copy mail file
if (&mail_under_home()) {
	my $oldmf = &user_mail_file($oldd->{'user'});
	my $newmf = &user_mail_file($d->{'user'});
	if (-r $oldmf) {
		my @st = stat($newmf);
		&copy_source_dest($oldmf, $newmf);
		if (@st) {
			&set_ownership_permissions(
				$st[5], $st[5], $st[2]&0777, $newmf);
			}
		else {
			&set_ownership_permissions(
				$d->{'uid'}, $d->{'gid'}, undef, $newmf);
			}
		}
	}

&release_lock_cron($d);
&release_lock_unix($d);
&$second_print($text{'setup_done'});
}

# check_warnings_unix(&domain, &old-domain)
# Check if quota is being lowered below what is actually being used
sub check_warnings_unix
{
my ($d, $oldd) = @_;
return undef if (!$oldd);
my $bsize = &quota_bsize("home");
if ($d->{'quota'} && $d->{'quota'} < $oldd->{'quota'}) {
	# Has a domain quota, which was just lowered .. check if under usage
	my ($usage) = &get_domain_quota($d);
	if ($d->{'quota'} < $usage) {
		return &text('save_edomainquota',
			     &nice_size($usage*$bsize),
			     &nice_size($d->{'quota'}*$bsize));
		}
	}
if ($d->{'uquota'} && $d->{'uquota'} < $oldd->{'uquota'}) {
	# Has a user quota, which was just lowered .. check if under usage
	my ($uinfo) = &get_domain_owner($d);
	if ($d->{'uquota'} < $uinfo->{'uquota'}) {
		return &text('save_euserquota',
			     &nice_size($uinfo->{'uquota'}*$bsize),
			     &nice_size($d->{'uquota'}*$bsize));
		}
	}
return undef;
}

# validate_unix(&domain)
# Check for the Unix user and group
sub validate_unix
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
return undef if ($d->{'parent'});	# sub-servers have no user
&require_useradmin();

# Make sure user exists and has right UID
my @users = &list_all_users_quotas(0);
my ($user) = grep { $_->{'user'} eq $d->{'user'} } @users;
return &text('validate_euser', $d->{'user'}) if (!$user);
return &text('validate_euid', $d->{'user'}, $d->{'uid'}, $user->{'uid'})
	if ($d->{'uid'} != $user->{'uid'});

# Make sure group exists and has right ID
my $group;
if ($d->{'gid'} == $d->{'ugid'}) {
	my @groups = &list_all_groups_quotas(0);
	($group) = grep { $_->{'group'} eq $d->{'group'} } @groups;
	return &text('validate_egroup', $d->{'group'}) if (!$group);
	return &text('validate_egid', $d->{'group'}, $d->{'gid'},
				      $group->{'gid'})
		if ($d->{'gid'} != $group->{'gid'});
	}

# Make sure home matches the domain (or it's chroot)
return &text('validate_euserhome', $user->{'user'}, $d->{'home'}, $user->{'home'})
	if ($user->{'home'} ne $d->{'home'} &&
	    $user->{'home'} !~ /\/\.\Q$d->{'home'}\E$/);

# Make sure encrypted password matches
if (!$cannot_rehash_password && $d->{'pass'}) {
	my $encmd5 = &encrypt_user_password($user, $d->{'pass'});
	my $encdes = &unix_crypt($d->{'pass'}, $user->{'pass'});
	if (!&useradmin::validate_password($d->{'pass'}, $user->{'pass'}) &&
	    $user->{'pass'} ne $encmd5 &&
	    $user->{'pass'} ne $encdes &&
	    !$d->{'disabled'}) {
		return &text('validate_eenc', $user->{'user'});
		}
	}
elsif ($d->{'enc_pass'}) {
	if ($user->{'pass'} ne $d->{'enc_pass'} && !$d->{'disabled'}) {
		return &text('validate_eenc2', $user->{'user'});
		}
	}

# Compare the domain's user and group quotas with reality (unless a backup is
# in progress, as this can disable quotas temporarily)
&require_useradmin();
my $backing = 0;
foreach my $r (&list_running_backups()) {
	if ($r->{'all'}) {
		$backing = 1;
		}
	elsif ($r->{'doms'} &&
	       &indexof($d->{'id'}, split(/\s+/, $r->{'doms'})) >= 0) {
		$backing = 1;
		}
	}
if (&has_home_quotas() && !$backing) {
	# Domain owner's Unix quota
	my $want = $tmpl->{'quotatype'} eq 'hard' ? $user->{'hardquota'}
						     : $user->{'softquota'};
	my $bsize = &quota_bsize("home");
	if ($want != $d->{'uquota'}) {
		return &text('validate_euquota',
		     $user->{'user'},
		     $want ? &nice_size($want*$bsize)
			   : $text{'form_unlimit'},
		     $d->{'uquota'} ? &nice_size($d->{'uquota'}*$bsize)
				    : $text{'form_unlimit'});
		}

	# Domain group's quota
	if ($group) {
		my $want = $tmpl->{'quotatype'} eq 'hard' ?
			$group->{'hardquota'} : $group->{'softquota'};
		if ($want != $d->{'quota'}) {
			return &text('validate_egquota',
			     $group->{'group'},
			     $want ? &nice_size($want*$bsize)
				   : $text{'form_unlimit'},
			     $d->{'quota'} ? &nice_size($d->{'quota'}*$bsize)
					   : $text{'form_unlimit'});
			}
		}
	}

if ($config{'check_ports'}) {
	# Check for user of any ports that the domain shouldn't allow
	my @porterrs;
	foreach my $p (&disallowed_domain_server_ports($d)) {
		push(@porterrs, &text('validate_eport',
				      $p->{'lport'},
				      $p->{'user'}->{'user'},
				      $p->{'proc'}->{'args'}));
		}
	return join(", ", @porterrs) if (@porterrs);
	}

return undef;
}

# check_unix_clash(&domain, [field])
# Returns 1 if a Unix user or group with this name already exists
sub check_unix_clash
{
my ($d, $field) = @_;
return 0 if ($d->{'parent'});	# user already exists!
return 0 if (&remote_unix() && $d->{'wasmissing'});
if (!$field || $field eq 'user') {
	# Check for username clash
	return &text('setup_eunixclash1', $d->{'user'})
		if (defined(getpwnam($d->{'user'})));
	}
if (!$field || $field eq 'group') {
	# Check for group name clash
	return &text('setup_eunixclash2', $d->{'group'})
		 if ($d->{'group'} &&
		     defined(getgrnam($d->{'group'})));
	}
if (!$field || $field eq 'uid') {
	# Check for UID clash
	return &text('setup_eunixclash3', $d->{'uid'})
		 if ($d->{'uid'} &&
		     defined(getpwuid($d->{'uid'})));
	}
if (!$field || $field eq 'gid') {
	# Check for GID clash
	return &text('setup_eunixclash4', $d->{'gid'})
		 if ($d->{'gid'} &&
		     defined(getgrgid($d->{'gid'})));
	}
return 0;
}

# disable_unix(&domain)
# Lock out the password and shell of this domain's Unix user
sub disable_unix
{
my ($d) = @_;
if (!$d->{'parent'}) {
	&obtain_lock_unix($d);
	&require_useradmin();
	my @allusers = &foreign_call($usermodule, "list_users");
	my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @allusers;
	if ($uinfo) {
		&$first_print($text{'disable_unix'});
		&foreign_call($usermodule, "set_user_envs", $uinfo,
			      'MODIFY_USER', "", undef, $uinfo, "");
		&foreign_call($usermodule, "making_changes");
		$d->{'disabled_oldpass'} = $uinfo->{'pass'};
		$uinfo->{'pass'} = $uconfig{'lock_string'};
		my ($nologin_shell) = &get_common_available_shells();
		if ($nologin_shell &&
		    $uinfo->{'shell'} ne $nologin_shell->{'shell'}) {
			# Also switch to no-login shell
			$d->{'disabled_shell'} = $uinfo->{'shell'};
			$uinfo->{'shell'} = $nologin_shell->{'shell'};
			}
		else {
			delete($d->{'disabled_shell'});
			}
		&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
		&foreign_call($usermodule, "made_changes");
		&disable_unix_cron_jobs($uinfo->{'user'});
		&$second_print($text{'setup_done'});
		}
	&release_lock_unix($d);
	}
return 1;
}

# enable_unix(&domain)
# Re-enable this domain's Unix user
sub enable_unix
{
my ($d) = @_;
if (!$d->{'parent'}) {
	&obtain_lock_unix($d);
	&require_useradmin();
	my @allusers = &foreign_call($usermodule, "list_users");
	my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @allusers;
	if ($uinfo) {
		&$first_print($text{'enable_unix'});
		&foreign_call($usermodule, "set_user_envs", $uinfo,
			      'MODIFY_USER', "", undef, $uinfo, "");
		&foreign_call($usermodule, "making_changes");
		$uinfo->{'pass'} = $d->{'disabled_oldpass'};
		delete($d->{'disabled_oldpass'});
		if ($d->{'disabled_shell'}) {
			# Also put back old shell
			$uinfo->{'shell'} = $d->{'disabled_shell'};
			delete($d->{'disabled_shell'});
			}
		&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
		&foreign_call($usermodule, "made_changes");
		&enable_unix_cron_jobs($uinfo->{'user'});
		&$second_print($text{'setup_done'});
		}
	&release_lock_unix($d);
	}
return 1;
}

# backup_unix(&domain, file)
# Backs up the users crontab file
sub backup_unix
{
my ($d, $file) = @_;
&foreign_require("cron");
my $cronfile = &cron::cron_file({ 'user' => $d->{'user'} });
&$first_print(&text('backup_cron'));
if (-r $cronfile) {
	&copy_write_as_domain_user($d, $cronfile, $file);
	&$second_print($text{'setup_done'});
	}
else {
	&open_tempfile_as_domain_user($d, TOUCH, ">$file", 0, 1);
	&close_tempfile_as_domain_user($d, TOUCH);
	&$second_print($text{'backup_cronnone'});
	}

# Save backup source
my $url = &get_user_database_url() || "";
&write_as_domain_user($d, sub { &uncat_file($file."_url", $url."\n") });

return 1;
}

# restore_unix(&domain, file, &options)
# Update's the domain's unix user's password, description, and cron jobs.
# Note - quotas are not set here, as they get set in restore_domain
sub restore_unix
{
my ($d, $file, $opts, $allopts) = @_;
&obtain_lock_unix($_[0]);
&obtain_lock_cron($_[0]);
&$first_print($text{'restore_unixuser'});

# Check if users are being stored in the same remote storage, if replicating
my $url = &get_user_database_url();
my $burl = &read_file_contents($file."_url");
chop($burl);
if ($url && $burl && $url eq $burl && $allopts->{'repl'}) {
	$url =~ s/^\S+:\/\///g;
	&$second_print(&text('restore_unixsame', $url));
	return 1;
	}

# Update domain owner user password and description
&require_useradmin();
my @allusers = &foreign_call($usermodule, "list_users");
my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @allusers;
if ($uinfo && !$d->{'parent'}) {
	my $olduinfo = { %$uinfo };
	$uinfo->{'real'} = $d->{'owner'};
	my $enc;
	if ($d->{'pass'}) {
		 $enc = &foreign_call($usermodule, "encrypt_password",
				      $d->{'pass'});
		}
	else {
		$enc = $d->{'enc_pass'};
		}
	if ($d->{'backup_encpass'} &&
	    ($enc =~ /^\$[1-9]\$/ || $d->{'backup_encpass'} !~ /^\$[1-9]\$/ ||
	     $uinfo->{'pass'} =~ /^\$[1-9]\$/)) {
		# Use saved encrypted password, if available and if either
		# we support MD5 or the password isn't in MD5
		$uinfo->{'pass'} = $d->{'backup_encpass'};
		}
	else {
		# Use re-hashed pass
		$uinfo->{'pass'} = $enc;
		}
	&set_pass_change($uinfo);
	&foreign_call($usermodule, "set_user_envs",
		      $uinfo, 'MODIFY_USER', $d->{'pass'}, undef, $olduinfo);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
	&foreign_call($usermodule, "made_changes");
	}
&$second_print($text{'setup_done'});

# Copy cron jobs file
if (-r $file) {
	&$first_print($text{'restore_cron'});
	&foreign_require("cron");
	&copy_source_dest($file, $cron::cron_temp_file);
	&cron::copy_crontab($d->{'user'});
	&$second_print($text{'setup_done'});
	}
&release_lock_unix($_[0]);
&release_lock_cron($_[0]);

return 1;
}

# bandwidth_unix(&domain, start, &bw-hash)
# Updates the bandwidth count for FTP traffic by the domain's unix user, and
# any mail users with FTP access
sub bandwidth_unix
{
my ($d, $start, $bw) = @_;
my $log = $config{'bw_ftplog'} ? $config{'bw_ftplog'} :
	  $config{'ftp'} ? &get_proftpd_log() : undef;
if ($log) {
	my @users;
	my @ashells = grep { $_->{'mailbox'} } &list_available_shells();
	if (!$d->{'parent'}) {
		# Only do the domain owner if this is the parent domain, to
		# avoid double-counting in subdomains
		push(@users, $d->{'user'});
		}
	foreach $u (&list_domain_users($d, 0, 1, 1, 1)) {
		# Only add Unix users with FTP access
		my ($shell) = grep { $_->{'shell'} eq $u->{'shell'} }
                                      @ashells;
		if (!$shell || $shell->{'id'} ne 'nologin') {
			push(@users, $u->{'user'});
			}
		}
	if (@users) {
		return &count_ftp_bandwidth($log, $start, $bw, \@users, "ftp",
					    $config{'bw_ftplog_rotated'});
		}
	}
return $start;
}

# show_template_unix(&tmpl)
# Outputs HTML for editing unix-user-related template options
sub show_template_unix
{
my ($tmpl) = @_;

# Quota type (hard or soft)
print &ui_table_row(&hlink($text{'tmpl_quotatype'}, "template_quotatype"),
    &ui_radio("quotatype", $tmpl->{'quotatype'},
	      [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
		[ "hard", $text{'tmpl_hard'} ],
		[ "soft", $text{'tmpl_soft'} ] ]));

# Domain owner primary group
if ($config{'show_ugroup'}) {
	print &ui_table_row(&hlink($text{'tmpl_ugroup'},
				   "template_ugroup_mode"),
	    &none_def_input("ugroup", $tmpl->{'ugroup'},$text{'tmpl_ugroupsel'},
			    0, 0, undef, [ "ugroup" ])."\n".
	    &ui_textbox("ugroup", $tmpl->{'ugroup'} eq "none" ?
					"" : $tmpl->{'ugroup'}, 13)."\n".
	    &group_chooser_button("ugroup", 0, 1));
	}

# Domain owner secondary groups
print &ui_table_row(&hlink($text{'tmpl_sgroup'}, "template_sgroup"),
    &none_def_input("sgroup", $tmpl->{'sgroup'}, $text{'tmpl_ugroupsel'},
		    0, 0, undef, [ "sgroup" ])."\n".
    &ui_textbox("sgroup", $tmpl->{'sgroup'} eq "none" ?
				"" : $tmpl->{'sgroup'}, 13)."\n".
    &group_chooser_button("sgroup", 0, 1));

# Default shell
print &ui_table_row(&hlink($text{'tmpl_ushell'}, "template_ushell"),
    &none_def_input("ushell", $tmpl->{'ushell'},
	&available_shells_menu("ushell",
		$tmpl->{'ushell'} eq "none" ? undef : $tmpl->{'ushell'},
		"owner"),
	0, 0, $text{'tmpl_ushelldef'}, [ "ushell" ]));

# Chroot by default
if (!&check_jailkit_support()) {
	print &ui_table_row(&hlink($text{'tmpl_jail'}, "template_jail"),
	    &ui_radio("ujail", $tmpl->{'ujail'},
		      [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
			[ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));
	}

# Store plaintext passwords?
print &ui_table_row(&hlink($text{'tmpl_uplainpass'}, "template_uplainpass"),
    &ui_radio("hashpass", $tmpl->{'hashpass'},
	      [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
		[ 0, $text{'yes'} ], [ 1, $text{'tmpl_uplainpassno'} ] ]));

# Hash types to store
my @hashtypes = &list_password_hash_types();
print &ui_table_row(&hlink($text{'tmpl_hashtypes'}, "template_hashtypes"),
    &ui_radio("hashtypes_def", $tmpl->{'hashtypes'} eq "*" ? 1 :
			       $tmpl->{'hashtypes'} eq "none" ? 3 :
			       $tmpl->{'hashtypes'} eq "" ? 2 : 0,
	      [ $tmpl->{'default'} ? ( ) : ( [ 2, $text{'default'} ] ),
		[ 1, $text{'tmpl_hashtypes1'} ],
		[ 3, $text{'tmpl_hashtypes3'} ],
		[ 0, $text{'tmpl_hashtypes0'} ] ])."<br>\n".
    &ui_select("hashtypes", [ split(/\s+/, $tmpl->{'hashtypes'}) ],
	       \@hashtypes, scalar(@hashtypes), 1));
}

# parse_template_unix(&tmpl)
# Updates unix-user-related template options from %in
sub parse_template_unix
{
my ($tmpl) = @_;

# Save quota type (hard or soft)
$tmpl->{'quotatype'} = $in{'quotatype'};

# Save domain owner primary group option
if ($config{'show_ugroup'}) {
	$tmpl->{'ugroup'} = &parse_none_def("ugroup");
	if ($in{"ugroup_mode"} == 2) {
		getgrnam($in{'ugroup'}) || &error($text{'tmpl_eugroup'});
		}
	}

# Save domain owner secondary group
$tmpl->{'sgroup'} = &parse_none_def("sgroup");
if ($in{"sgroup_mode"} == 2) {
	getgrnam($in{'sgroup'}) || &error($text{'tmpl_esgroup'});
	}

# Save initial shell
$tmpl->{'ushell'} = &parse_none_def("ushell");

# Chroot setting
if (!&check_jailkit_support()) {
	$tmpl->{'ujail'}= $in{'ujail'};
	}

# Save password type
$tmpl->{'hashpass'} = $in{'hashpass'};
if ($in{'hashtypes_def'} == 2) {
	$tmpl->{'hashtypes'} = '';
	}
elsif ($in{'hashtypes_def'} == 1) {
	$tmpl->{'hashtypes'} = '*';
	}
elsif ($in{'hashtypes_def'} == 3) {
	$tmpl->{'hashtypes'} = 'none';
	}
else {
	$tmpl->{'hashtypes'} = join(" ", split(/\0/, $in{'hashtypes'}));
	$tmpl->{'hashtypes'} || &error($text{'tmpl_ehashtypes'});
	}
}

# get_unix_shells()
# Returns a list of tuples containing shell types and paths, like :
# [ 'nologin', '/dev/null' ], [ 'ftp', '/bin/false' ], [ 'ssh', '/bin/sh' ]
sub get_unix_shells
{
# Read FTP-capable shells
my @rv;
my @shells;
open(SHELLS, "</etc/shells");
while(my $l = <SHELLS>) {
	$l =~ s/\r|\n//g;
	$l =~ s/#.*$//;
	push(@shells, $l) if ($l =~ /\S/);
	}
close(SHELLS);
my %shells = map { $_, 1 } @shells;

# Find no-login shells
my @nologin = ($config{'shell'}, '/dev/null', '/sbin/nologin',
		'/bin/nologin', '/sbin/noshell', '/bin/noshell');
push(@rv, map { [ 'nologin', $_ ] } grep { !$shells{$_} } @nologin);

# Find a good FTP-capable shell
my @ftp = ( $config{'ftp_shell'}, '/bin/false', '/bin/true',
	    '/sbin/nologin', '/bin/nologin' );
push(@rv, map { [ 'ftp', $_ ] } grep { $shells{$_} } @ftp);

# Find FTP and SSH login shells
foreach my $s (keys %shells) {
	if (&indexof($s, @nologin) < 0 && &indexof($s, @ftp) < 0) {
		push(@rv, [ 'ssh', $s ]);
		}
	}
return @rv;
}

# build_denied_ssh_group([&new-domain])
# Update the deniedssh Unix group's membership list with all domain owners
# who don't get to login (based on their shell)
sub build_denied_ssh_group
{
my ($newd, $deld) = @_;
return 0 if ($config{'nodeniedssh'});	# Disabled in config

# First make sure the group exists
&obtain_lock_unix($newd);
&require_useradmin();
my @allgroups = &list_all_groups();
my ($group) = grep { $_->{'group'} eq $denied_ssh_group } @allgroups;
if (!$group) {
	&release_lock_unix($newd);
	return 0;
	}

# Find domain owners who can't login
my @shells = &list_available_shells();
foreach my $d (&list_domains(), $newd) {
	next if ($d->{'parent'} || !$d->{'unix'} || $d eq $deld);
	my $user = &get_domain_owner($d, 1);
	my ($sinfo) = grep { $_->{'shell'} eq $user->{'shell'} } @shells;
	if ($sinfo && $sinfo->{'id'} ne 'ssh' &&
	    $user->{'shell'} !~ /\/(sh|bash|ksh|csh|tcsh|zsh|scponly)$/) {
		# Has a non-SSH shell
		push(@members, $user->{'user'});
		}
	}

# Update the group
my $oldgroup = { %$group };
$group->{'members'} = join(",", &unique(@members));
if ($group->{'members'} ne $oldgroup->{'members'}) {
	&foreign_call($group->{'module'}, "set_group_envs", $group,
				   	  'MODIFY_GROUP', $oldgroup);
	&foreign_call($group->{'module'}, "making_changes");
	&foreign_call($group->{'module'}, "modify_group", $oldgroup, $group);
	&foreign_call($group->{'module'}, "made_changes");
	}

&release_lock_unix($newd);
return 1;
}

# update_domain_owners_group([&new-domain], [&deleting-domain])
# If configured, update the member list of a secondary group which should
# contain all domain owners.
sub update_domain_owners_group
{
my ($newd, $deld) = @_;
my $tmpl = $newd ? &get_template($newd->{'template'}) :
	   $deld ? &get_template($deld->{'template'}) : undef;
return 0 if (!$tmpl || !$tmpl->{'sgroup'});

# First make sure the group exists
&obtain_lock_unix($newd);
&require_useradmin();
my @allgroups = &list_all_groups();
my ($group) = grep { $_->{'group'} eq $tmpl->{'sgroup'} } @allgroups;
if (!$group) {
	&release_lock_unix($newd);
	return 0;
	}

# Find domain owners with Unix logins
my @members;
foreach my $d (&list_domains(), $newd) {
	if ($d->{'unix'} && $d ne $deld) {
		push(@members, $d->{'user'});
		}
	}

# Update the group
my $oldgroup = { %$group };
$group->{'members'} = join(",", &unique(@members));
if ($group->{'members'} ne $oldgroup->{'members'}) {
	&foreign_call($group->{'module'}, "set_group_envs", $group,
				      'MODIFY_GROUP', $oldgroup);
	&foreign_call($group->{'module'}, "making_changes");
	&foreign_call($group->{'module'}, "modify_group", $oldgroup, $group);
	&foreign_call($group->{'module'}, "made_changes");
	}
&release_lock_unix($newd);
}

sub startstop_unix
{
my @rv;
if (&foreign_installed("sshd")) {
	# Add SSH server status
	my @links = ( { 'link' => '/sshd/',
			'desc' => $text{'index_sshmanage'},
			'manage' => 1 } );
	&foreign_require("sshd");
	if (&sshd::get_sshd_pid()) {
		push(@rv, { 'status' => 1,
			    'feature' => 'sshd',
			    'name' => $text{'index_sshname'},
			    'desc' => $text{'index_sshstop'},
			    'restartdesc' => $text{'index_sshrestart'},
			    'longdesc' => $text{'index_sshstopdesc'},
			    'links' => \@links } );
		}
	else {
		push(@rv, { 'status' => 0,
			    'feature' => 'sshd',
			    'name' => $text{'index_sshname'},
			    'desc' => $text{'index_sshstart'},
			    'longdesc' => $text{'index_sshstartdesc'},
			    'links' => \@links } );
		}
	}
return @rv;
}

sub stop_service_unix
{
return &stop_service_ftp();
}

sub start_service_unix
{
return &start_service_ftp();
}

sub stop_service_sshd
{
&foreign_require("sshd");
return &sshd::stop_sshd();
}

sub start_service_sshd
{
&foreign_require("sshd");
return &sshd::start_sshd();
}

# delete_partial_group(&group)
# Deletes a group that may not have been created completely
sub delete_partial_group
{
my ($group) = @_;
eval {
	local $main::error_must_die = 1;
	my @allgroups = &list_all_groups();
	my ($ginfo) = grep { $_->{'group'} eq $group->{'group'} &&
				$_->{'module'} eq $usermodule } @allgroups;
	if ($ginfo) {
		&foreign_call($ginfo->{'module'}, "set_group_envs", $ginfo,
			      'DELETE_GROUP');
		&foreign_call($ginfo->{'module'}, "making_changes");
		&foreign_call($ginfo->{'module'}, "delete_group", $ginfo);
		&foreign_call($ginfo->{'module'}, "made_changes");
		}
	};
}

# delete_partial_user(&user)
# Deletes a user that may not have been created completely
sub delete_partial_user
{
my ($user) = @_;
eval {
	local $main::error_must_die = 1;
	my @allusers = &list_all_users();
	my ($uinfo) = grep { $_->{'user'} eq $user->{'user'} &&
				$_->{'module'} eq $usermodule } @allusers;
	if ($uinfo) {
		&foreign_call($uinfo->{'module'}, "set_user_envs", $uinfo,
			      'DELETE_USER');
		&foreign_call($uinfo->{'module'}, "making_changes");
		&foreign_call($uinfo->{'module'}, "delete_user", $uinfo);
		&foreign_call($uinfo->{'module'}, "made_changes");
		}
	};
}

# wait_for_group_to_exist(group)
# Wait 10 seconds for a new group to become visible
sub wait_for_group_to_exist
{
my ($g) = @_;
for(my $i=0; $i<10; $i++) {
	return 1 if (defined(getgrnam($g)));
	return 1 if (system("getent group ".
			    quotemeta($g)." >/dev/null 2>&1") == 0);
	sleep(1);
	}
return 0;
}

# wait_for_user_to_exist(user)
# Wait 10 seconds for a new user to become visible
sub wait_for_user_to_exist
{
my ($u) = @_;
for(my $i=0; $i<10; $i++) {
	return 1 if (defined(getpwnam($u)));
	return 1 if (system("getent passwd ".
			    quotemeta($u)." >/dev/null 2>&1") == 0);
	sleep(1);
	}
return 0;
}

# is_hashed_password(string)
# Returns non-null if some string looks like a hashed password
sub is_hashed_password
{
my ($pass) = @_;
if ($pass =~ /^\{[a-zA-Z0-9]+\}\S+$/) {
	return "ldap";
	}
elsif ($pass =~ /^\$1\$[a-z0-9\.\/\$]+$/) {
	return "md5";
	}
elsif ($pass =~ /^\$2a\$/) {
	return "blowfish";
	}
else {
	return undef;
	}
}

# Lock all Unix password files
sub obtain_lock_unix
{
&obtain_lock_anything();
if ($main::got_lock_unix == 0) {
	&require_useradmin();
	&foreign_call($usermodule, "lock_user_files");
	undef(@useradmin::list_users_cache);
	undef(@useradmin::list_groups_cache);
	undef(%main::soft_home_quota);
	undef(%main::hard_home_quota);
	undef(%main::used_home_quota);
	undef(%main::soft_mail_quota);
	undef(%main::hard_mail_quota);
	if (defined(&supports_resource_limits)) {
		# Lock resource limits file too
		if ($gconfig{'os_type'} =~ /-linux$/) {
			&lock_file($linux_limits_config);
			undef(@get_linux_limits_config_cache);
			}
		}
	}
$main::got_lock_unix++;
}

# Unlock all Unix password files
sub release_lock_unix
{
if ($main::got_lock_unix == 1) {
	&require_useradmin();
	&foreign_call($usermodule, "unlock_user_files");
	if (defined(&supports_resource_limits)) {
		if ($gconfig{'os_type'} =~ /-linux$/) {
			&unlock_file($linux_limits_config);
			}
		}
	}
$main::got_lock_unix-- if ($main::got_lock_unix);
&release_lock_anything();
}

# obtain_lock_cron(&domain)
# Locks a domain's user's crontab file, and root's
sub obtain_lock_cron
{
my ($d) = @_;
&obtain_lock_anything($d);
foreach my $u ($d ? ( $d->{'user'} ) : ( ), 'root') {
	if ($main::got_lock_cron_user{$u} == 0) {
		&foreign_require("cron");
		&lock_file(&cron::cron_file({ 'user' => $u }));
		}
	$main::got_lock_cron_user{$u}++;
	}
}

# release_lock_cron(&domain)
# Un-locks a domain's user's crontab file
sub release_lock_cron
{
my ($d) = @_;
foreach my $u ($d ? ( $d->{'user'} ) : ( ), 'root') {
	if ($main::got_lock_cron_user{$u} == 1) {
		&foreign_require("cron");
		&unlock_file(&cron::cron_file({ 'user' => $u }));
		}
	$main::got_lock_cron_user{$u}--
		if ($main::got_lock_cron_user{$u});
	}
&release_lock_anything($d);
}

# remote_unix(&domain)
# Returns true if Unix users are stored on a remote system
sub remote_unix
{
my ($d) = @_;
return &get_user_database_url() ? 1 : 0;
}

sub can_reset_unix
{
return 2;	# On/off reset isn't allowed
}

# reset_unix(&domain)
# Re-write the Unix user and group for this domain
sub reset_unix
{
my ($d) = @_;
&$first_print($text{'reset_unix'});
&require_useradmin();
my ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } &list_all_users();
my ($ginfo) = grep { $_->{'group'} eq $d->{'group'} } &list_all_groups();
if (!$uinfo) {
	# User does not exist! Re-create it by re-running setup
	&$second_print(&text('reset_eunixuser', $d->{'user'}));
	&setup_unix();
	return;
	}
elsif (!$ginfo) {
	# Group does not exist! Re-create it
	$ginfo = { 'group', $d->{'group'},
		   'gid', $d->{'gid'},
		 };
	&foreign_call($usermodule, "set_group_envs", $ginfo,
		      'CREATE_GROUP');
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "create_group", $ginfo);
	&foreign_call($usermodule, "made_changes");
	return;
	}

# Update all key fields
my $olduinfo = { %$uinfo };
my $oldginfo = { %$ginfo };
if (defined(&supports_resource_limits) && &supports_resource_limits()) {
	# Update ulimits
	my $rv = &get_domain_resource_limits($d);
	&save_domain_resource_limits($d, $rv, 1);
	}
$uinfo->{'real'} = $d->{'owner'};
$uinfo->{'home'} = $d->{'home'};
if ($d->{'pass'} ne '' && !$d->{'disabled'}) {
	# Re-save password, if changed
	# XXX really?
	my $enc = &foreign_call($usermodule, "encrypt_password", $d->{'pass'});
	if ($uinfo->{'pass'} ne $enc) {
		$uinfo->{'pass'} = $enc;
		$uinfo->{'plainpass'} = $d->{'pass'};
		&set_pass_change($uinfo);
		}
	}
$uinfo->{'gid'} = $d->{'ugid'} || $d->{'gid'};

&foreign_call($usermodule, "set_user_envs", $uinfo, 'MODIFY_USER',
      $uinfo->{'plainpass'}, undef, $olduinfo, $olduinfo->{'plainpass'});
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "modify_user", $olduinfo, $uinfo);
&foreign_call($usermodule, "made_changes");

&set_server_quotas($d);
&$second_print($text{'setup_done'});
}

# create_email_for_unix(&domain)
# Setup email for the virtual server's unix user
sub create_email_for_unix
{
my ($d) = @_;
my @virts = &list_virtusers();
my $email = $d->{'user'}."\@".$d->{'dom'};
my ($virt) = grep { $_->{'from'} eq $email } @virts;
if (!$virt) {
	$virt = { 'from' => $email,
		  'to' => [ $d->{'user'} ] };
	&create_virtuser($virt);
	&sync_alias_virtuals($d);
	}
if ($config{'generics'}) {
	&create_generic($d->{'user'}, $email, 1);
	}
}

$done_feature_script{'unix'} = 1;

1;

