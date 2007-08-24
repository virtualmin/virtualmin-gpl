# Functions for managing a domain's Unix user

$feature_depends{'unix'} = [ 'dir' ];

# setup_unix(&domain)
# Creates the Unix user and group for a domain
sub setup_unix
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();
local (%uinfo, %ginfo);

# Check if the UID or GID has been allocated to someone else, and if so
# re-allocate them. Also allocate if they haven't been done yet.
local @allusers = &list_all_users();
local ($clash) = grep { $_->{'uid'} == $_[0]->{'uid'} } @allusers;
if ($clash || !$_[0]->{'uid'}) {
	local (%taken, %utaken);
	&build_taken(\%taken, \%utaken, \@allusers);
	$_[0]->{'uid'} = &allocate_uid(\%taken);
	}
local @allgroups = &list_all_groups();
local ($gclash) = grep { $_->{'gid'} == $_[0]->{'gid'} } @allgroups;
if ($gclash || !$_[0]->{'gid'}) {
	local (%gtaken, %ggtaken);
	&build_group_taken(\%gtaken, \%ggtaken, \@allgroups);
	$_[0]->{'gid'} = &allocate_gid(\%gtaken);
	}

if (&mail_system_needs_group() || $_[0]->{'gid'} == $_[0]->{'ugid'}) {
	# Create the group
	&$first_print(&text('setup_group', $_[0]->{'group'}));
	&foreign_call($usermodule, "lock_user_files");
	%ginfo = ( 'group', $_[0]->{'group'},
		   'gid', $_[0]->{'gid'},
		 );
	&foreign_call($usermodule, "set_group_envs", \%ginfo, 'CREATE_GROUP');
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "create_group", \%ginfo);
	&foreign_call($usermodule, "made_changes");
	if (!defined(getgrnam($_[0]->{'group'}))) {
		&$second_print($text{'setup_ecrgroup'});
		exit;
		}
	&$second_print($text{'setup_done'});
	}
else {
	# Server has no group!
	delete($_[0]->{'gid'});
	delete($_[0]->{'group'});
	}

# Then the user
&$first_print(&text('setup_user', $_[0]->{'user'}));
%uinfo = ( 'user', $_[0]->{'user'},
	   'uid', $_[0]->{'uid'},
	   'gid', $_[0]->{'ugid'},
	   'pass', $_[0]->{'enc_pass'} ||
		   &foreign_call($usermodule, "encrypt_password",
				 $_[0]->{'pass'}),
	   'real', $_[0]->{'owner'},
	   'home', $_[0]->{'home'},
	   'shell', $config{'unix_shell'},
	   'mailbox', $_[0]->{'user'},
	   'dom', $_[0]->{'dom'},
	   'dom_prefix', substr($_[0]->{'dom'}, 0, 1),
	 );
&set_pass_change(\%uinfo);
&foreign_call($usermodule, "set_user_envs", \%uinfo, 'CREATE_USER', $_[0]->{'pass'}, [ ]);
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "create_user", \%uinfo);
&foreign_call($usermodule, "made_changes");
&foreign_call($usermodule, "unlock_user_files");
if ($config{'other_doms'}) {
	&foreign_call($usermodule, "other_modules", "useradmin_create_user",
		      \%uinfo);
	}
if (!defined(getpwnam($_[0]->{'user'}))) {
	&$second_print($text{'setup_ecruser'});
	exit;
	}
&$second_print($text{'setup_done'});

# Set the user's quota
if (&has_home_quotas()) {
	&set_server_quotas($_[0]);
	}

# Create mail file
&create_mail_file(\%uinfo);

# Create virtuser pointing to new user, and possibly generics entry
if ($_[0]->{'mail'}) {
	local @virts = &list_virtusers();
	local $email = $_[0]->{'user'}."\@".$_[0]->{'dom'};
	local ($virt) = grep { $_->{'from'} eq $email } @virts;
	if (!$virt) {
		$virt = { 'from' => $email,
			  'to' => [ $_[0]->{'user'} ] };
		&create_virtuser($virt);
		}
	if ($config{'generics'}) {
		&create_generic($_[0]->{'user'}, $email);
		}
	}

# Add to denied SSH group and domain owner group
&build_denied_ssh_group($_[0]);
&update_domain_owners_group($_[0]);
}

# modify_unix(&domain, &olddomain)
# Change the password and real name for a domain unix user
sub modify_unix
{
if (!$_[0]->{'parent'}) {
	# Check for a user change
	&require_useradmin();
	local @allusers = &list_domain_users($_[1]);
	local ($uinfo) = grep { $_->{'user'} eq $_[1]->{'user'} } @allusers;
	if ($uinfo && ($_[0]->{'pass_set'} ||
		       $_[0]->{'user'} ne $_[1]->{'user'} ||
		       $_[0]->{'home'} ne $_[1]->{'home'} ||
		       $_[0]->{'owner'} ne $_[1]->{'owner'})) {
		&foreign_call($usermodule, "lock_user_files");
		local %old = %$uinfo;
		&$first_print($text{'save_user'});
		$uinfo->{'real'} = $_[0]->{'owner'};
		if ($_[0]->{'pass_set'}) {
			# Update the Unix user's password
			local $enc = &foreign_call($usermodule,
				"encrypt_password", $_[0]->{'pass'});
			if ($d->{'disabled'}) {
				# Just keep for later use when enabling
				$d->{'disabled_oldpass'} = $enc;
				}
			else {
				# Set password now
				$uinfo->{'pass'} = $enc;
				}
			delete($d->{'enc_pass'});	# Any stored encrypted
							# password is not valid
			$uinfo->{'plainpass'} = $_[0]->{'pass'};
			&set_pass_change($uinfo);
			}

		if ($_[0]->{'user'} ne $_[1]->{'user'}) {
			# Unix user was re-named
			$uinfo->{'olduser'} = $_[1]->{'user'};
			$uinfo->{'user'} = $_[0]->{'user'};
			&rename_mail_file($uinfo, \%old);
			&rename_unix_cron_jobs($_[0]->{'user'},
					       $_[1]->{'user'});
			}

		if ($_[0]->{'home'} ne $_[1]->{'home'}) {
			# Home directory was changed
			$uinfo->{'home'} = $_[0]->{'home'};
			}

		if ($_[0]->{'owner'} ne $_[1]->{'owner'}) {
			# Domain description was changed
			$uinfo->{'real'} = $_[0]->{'owner'};
			}

		&modify_user($uinfo, \%old, undef);

		if ($config{'other_doms'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_modify_user", $uinfo, \%old);
			}

		&$second_print($text{'setup_done'});
		&foreign_call($usermodule, "unlock_user_files");
		}

	if (&has_home_quotas() && $access{'edit'} == 1) {
		# Update the unix user's and domain's quotas (if changed)
		if ($_[0]->{'quota'} != $_[1]->{'quota'} ||
		    $_[0]->{'uquota'} != $_[1]->{'uquota'}) {
			&$first_print($text{'save_quota'});
			&set_server_quotas($_[0]);
			&$second_print($text{'setup_done'});
			}
		}

	# Check for a group change
	local ($ginfo) = grep { $_->{'group'} eq $_[1]->{'group'} }
			      &list_all_groups();
	if ($ginfo && $_[0]->{'group'} ne $_[1]->{'group'}) {
		&foreign_call($usermodule, "lock_user_files");
		local %old = %$ginfo;
		&$first_print($text{'save_group'});
		$ginfo->{'group'} = $_[0]->{'group'};
		&foreign_call($usermodule, "set_group_envs", $ginfo,
					   'MODIFY_GROUP', \%old);
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "modify_group", \%old, $ginfo);
		&foreign_call($usermodule, "made_changes");
		&foreign_call($usermodule, "unlock_user_files");
		&$second_print($text{'setup_done'});
		}
	}
elsif ($_[0]->{'parent'} && !$_[1]->{'parent'}) {
	# Unix feature has been turned off .. so delete the user and group
	&delete_unix($_[1]);
	}
}

# delete_unix(&domain)
# Delete the unix user and group for a domain
sub delete_unix
{
&require_useradmin();
local @allusers = &foreign_call($usermodule, "list_users");
local ($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @allusers;

if (!$_[0]->{'parent'}) {
	# Zero his quotas
	if ($uinfo) {
		&set_user_quotas($uinfo->{'user'}, 0, 0, $_[0]);
		}

	# Delete his cron jobs
	&delete_unix_cron_jobs($_[0]->{'user'});

	# Delete virtuser and generic
	local @virts = &list_virtusers();
	local $email = $_[0]->{'user'}."\@".$_[0]->{'dom'};
	local ($virt) = grep { $_->{'from'} eq $email } @virts;
	if ($virt) {
		&delete_virtuser($virt);
		}
	if ($config{'generics'}) {
		local %generics = &get_generics_hash();
		local $g = $generics{$_[0]->{'user'}};
		if ($g) {
			&delete_generic($g);
			}
		}

	# Delete unix user
	&foreign_call($usermodule, "lock_user_files");
	if ($uinfo) {
		&$first_print($text{'delete_user'});
		&delete_user($uinfo, $_[0]);
		if ($config{'other_doms'}) {
			&foreign_call($usermodule, "other_modules",
				      "useradmin_delete_user", $uinfo);
			}
		&$second_print($text{'setup_done'});
		}

	# Delete unix group
	local @allgroups = &foreign_call($usermodule, "list_groups");
	local ($ginfo) = grep { $_->{'group'} eq $_[0]->{'group'} } @allgroups;
	if ($ginfo) {
		&$first_print($text{'delete_group'});
		&foreign_call($usermodule, "set_group_envs", $ginfo, 'DELETE_GROUP');
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "delete_group", $ginfo);
		&foreign_call($usermodule, "made_changes");
		&$second_print($text{'setup_done'});
		}
	&foreign_call($usermodule, "unlock_user_files");
	}

# Update any groups
&build_denied_ssh_group(undef, $_[0]);
&update_domain_owners_group(undef, $_[0]);
}

# validate_unix(&domain)
# Check for the Unix user and group
sub validate_unix
{
local ($d) = @_;
return undef if ($d->{'parent'});	# sub-servers have no user
local @users = &list_all_users();
local ($user) = grep { $_->{'user'} eq $d->{'user'} } @users;
return &text('validate_euser', $d->{'user'}) if (!$user);
if (&mail_system_needs_group() || $d->{'gid'} == $d->{'ugid'}) {
	local @groups = &list_all_groups();
	local ($group) = grep { $_->{'group'} eq $d->{'group'} } @groups;
	return &text('validate_egroup', $d->{'group'}) if (!$group);
	}
return undef;
}

# check_unix_clash(&domain, [field])
sub check_unix_clash
{
return 0 if ($_[0]->{'parent'});	# user already exists!
if (!$_[1] || $_[1] eq 'user') {
	return 1 if (defined(getpwnam($_[0]->{'user'})));
	}
if (!$_[1] || $_[1] eq 'group') {
	return 1 if ($_[0]->{'group'} &&
		     defined(getgrnam($_[0]->{'group'})));
	}
return 0;
}

# disable_unix(&domain)
# Lock out the password of this domain's Unix user
sub disable_unix
{
if (!$_[0]->{'parent'}) {
	&require_useradmin();
	&foreign_call($usermodule, "lock_user_files");
	local @allusers = &foreign_call($usermodule, "list_users");
	local ($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @allusers;
	if ($uinfo) {
		&$first_print($text{'disable_unix'});
		&foreign_call($usermodule, "set_user_envs", $uinfo,
			      'MODIFY_USER', "", $uinfo, "");
		&foreign_call($usermodule, "making_changes");
		$_[0]->{'disabled_oldpass'} = $uinfo->{'pass'};
		$uinfo->{'pass'} = $uconfig{'lock_string'};
		&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
		&foreign_call($usermodule, "made_changes");
		&$second_print($text{'setup_done'});
		}
	&foreign_call($usermodule, "unlock_user_files");
	}
}

# enable_unix(&domain)
# Re-enable this domain's Unix user
sub enable_unix
{
if (!$_[0]->{'parent'}) {
	&require_useradmin();
	&foreign_call($usermodule, "lock_user_files");
	local @allusers = &foreign_call($usermodule, "list_users");
	local ($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @allusers;
	if ($uinfo) {
		&$first_print($text{'enable_unix'});
		&foreign_call($usermodule, "set_user_envs", $uinfo,
			      'MODIFY_USER', "", $uinfo, "");
		&foreign_call($usermodule, "making_changes");
		$uinfo->{'pass'} = $_[0]->{'disabled_oldpass'};
		delete($_[0]->{'disabled_oldpass'});
		&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
		&foreign_call($usermodule, "made_changes");
		&$second_print($text{'setup_done'});
		}
	&foreign_call($usermodule, "unlock_user_files");
	}
}

# backup_unix(&domain, file)
# Backs up the users crontab file
sub backup_unix
{
local ($d, $file) = @_;
&foreign_require("cron", "cron-lib.pl");
local $cronfile = &cron::cron_file({ 'user' => $d->{'user'} });
&$first_print(&text('backup_cron'));
if (-r $cronfile) {
	&copy_source_dest($cronfile, $file);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'backup_cronnone'});
	}
return 1;
}

# restore_unix(&domain, file, &options)
# Extracts the given tar file into a user's home directory
sub restore_unix
{
local ($d, $file, $opts) = @_;
&$first_print($text{'restore_unixuser'});

# Also re-set quotas
if (&has_home_quotas()) {
	&set_server_quotas($_[0]);
	}

# And update password and description
&require_useradmin();
local @allusers = &foreign_call($usermodule, "list_users");
local ($uinfo) = grep { $_->{'user'} eq $d->{'user'} } @allusers;
if ($uinfo && !$d->{'parent'}) {
	local $olduinfo = { %$uinfo };
	&foreign_call($usermodule, "lock_user_files");
	$uinfo->{'real'} = $d->{'owner'};
	local $enc = &foreign_call($usermodule, "encrypt_password",
			$d->{'pass'});
	$uinfo->{'pass'} = $enc;
	&set_pass_change($uinfo);
	&foreign_call($usermodule, "set_user_envs",
		      $uinfo, 'MODIFY_USER', $d->{'pass'}, $olduinfo);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "modify_user", $uinfo, $uinfo);
	&foreign_call($usermodule, "made_changes");
	&foreign_call($usermodule, "lock_user_files");
	}
&$second_print($text{'setup_done'});

# Copy cron jobs file
if (-r $file) {
	&$first_print($text{'restore_cron'});
	&foreign_require("cron", "cron-lib.pl");
	&copy_source_dest($file, $cron::cron_temp_file);
	&cron::copy_crontab($d->{'user'});
	&$second_print($text{'setup_done'});
	}

return 1;
}

# bandwidth_unix(&domain, start, &bw-hash)
# Updates the bandwidth count for FTP traffic by the domain's unix user, and
# any mail users with FTP access
sub bandwidth_unix
{
local $log = $config{'bw_ftplog'} || &get_proftpd_log();
if ($log) {
	local @users;
	if (!$_[0]->{'parent'}) {
		# Only do the domain owner if this is the parent domain, to
		# avoid double-counting in subdomains
		push(@users, $_[0]->{'user'});
		}
	foreach $u (&list_domain_users($_[0], 0, 1, 1, 1)) {
		push(@users, $u->{'user'}) if ($u->{'unix'});
		}
	return &count_ftp_bandwidth($log, $_[1], $_[2], \@users, "ftp",
				    $config{'bw_ftplog_rotated'});
	}
else {
	return $_[1];
	}
}

# show_template_unix(&tmpl)
# Outputs HTML for editing unix-user-related template options
sub show_template_unix
{
local ($tmpl) = @_;

# Quota-related defaults
print &ui_table_row(&hlink($text{'tmpl_quotatype'}, "template_quotatype"),
    &ui_radio("quotatype", $tmpl->{'quotatype'},
	      [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
		[ "hard", $text{'tmpl_hard'} ],
		[ "soft", $text{'tmpl_soft'} ] ]));

print &ui_table_row(&hlink($text{'tmpl_quota'}, "template_quota"),
    &none_def_input("quota", $tmpl->{'quota'}, $text{'tmpl_quotasel'}, 1,
		    0, undef, [ "quota", "quota_units" ])."\n".
    &quota_input("quota", $tmpl->{'quota'} eq "none" ?
				"" : $tmpl->{'quota'}, "home"));

print &ui_table_row(&hlink($text{'tmpl_uquota'}, "template_uquota"),
    &none_def_input("uquota", $tmpl->{'uquota'}, $text{'tmpl_quotasel'}, 1,
		    0, undef, [ "uquota", "uquota_units" ])."\n".
    &quota_input("uquota", $tmpl->{'uquota'} eq "none" ?
				"" : $tmpl->{'uquota'}, "home"));

print &ui_table_row(&hlink($text{'tmpl_defmquota'}, "template_defmquota"),
    &none_def_input("defmquota", $tmpl->{'defmquota'}, $text{'tmpl_quotasel'},
		    0, 0, $text{'form_unlimit'},
		    [ "defmquota", "defmquota_units" ])."\n".
    &quota_input("defmquota", $tmpl->{'defmquota'} eq "none" ?
				"" : $tmpl->{'defmquota'}, "home"));

# Domain owner primary group
print &ui_table_row(&hlink($text{'tmpl_ugroup'}, "template_ugroup_mode"),
    &none_def_input("ugroup", $tmpl->{'ugroup'}, $text{'tmpl_ugroupsel'},
		    0, 0, undef, [ "ugroup" ])."\n".
    &ui_textbox("ugroup", $tmpl->{'ugroup'} eq "none" ?
				"" : $tmpl->{'ugroup'}, 13)."\n".
    &group_chooser_button("ugroup", 0, 1));
}

# parse_template_unix(&tmpl)
# Updates unix-user-related template options from %in
sub parse_template_unix
{
local ($tmpl) = @_;

# Save quota-related defaults
$tmpl->{'quotatype'} = $in{'quotatype'};
$tmpl->{'quota'} = &parse_none_def("quota");
if ($in{"quota_mode"} == 2) {
	$in{'quota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_equota'});
	$tmpl->{'quota'} = &quota_parse("quota", "home");
	}
$tmpl->{'uquota'} = &parse_none_def("uquota");
if ($in{"uquota_mode"} == 2) {
	$in{'uquota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_euquota'});
	$tmpl->{'uquota'} = &quota_parse("uquota", "home");
	}
$tmpl->{'defmquota'} = &parse_none_def("defmquota");
if ($in{"defmquota_mode"} == 2) {
	$in{'defmquota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_edefmquota'});
	$tmpl->{'defmquota'} = &quota_parse("defmquota", "home");
	}

# Save domain owner primary group option
$tmpl->{'ugroup'} = &parse_none_def("ugroup");
if ($in{"ugroup_mode"} == 2) {
	getgrnam($in{'ugroup'}) || &error($text{'tmpl_eugroup'});
	}
}

# get_unix_shells()
# Returns a list of tuples containing shell types and paths, like :
# [ 'nologin', '/dev/null' ], [ 'ftp', '/bin/false' ], [ 'ssh', '/bin/sh' ]
sub get_unix_shells
{
# Read FTP-capable shells
local $_;
local @shells;
open(SHELLS, "/etc/shells");
while(<SHELLS>) {
	s/\r|\n//g;
	s/#.*$//;
	push(@shells, $_) if (/\S/);
	}
close(SHELLS);
local %shells = map { $_, 1 } @shells;

# Find no-login shells
local @nologin = ($config{'shell'}, '/dev/null', '/sbin/nologin',
		  '/bin/nologin', '/sbin/noshell', '/bin/noshell');
push(@rv, map { [ 'nologin', $_ ] } grep { !$shells{$_} } @nologin);

# Find a good FTP-capable shell
local @ftp = ( $config{'ftp_shell'}, '/bin/false', '/bin/true' );
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
local ($newd, $deld) = @_;

# First make sure the group exists
&require_useradmin();
local @allgroups = &list_all_groups();
local ($group) = grep { $_->{'group'} eq $denied_ssh_group } @allgroups;
return 0 if (!$group);

# Find domain owners who can't login
local @shells = &get_unix_shells();
foreach my $d (&list_domains(), $newd) {
	next if ($d->{'parent'} || !$d->{'unix'} || $d eq $deld);
	local $user = &get_domain_owner($d);
	local ($sinfo) = grep { $_->[1] eq $user->{'shell'} } @shells;
	if ($sinfo && $sinfo->[0] ne 'ssh') {
		# On the denied list..
		push(@members, $user->{'user'});
		}
	}

# Update the group
local $oldgroup = { %$group };
$group->{'members'} = join(",", &unique(@members));
if ($group->{'members'} ne $oldgroup->{'members'}) {
	&foreign_call($group->{'module'}, "lock_user_files");
	&foreign_call($group->{'module'}, "set_group_envs", $group,
				   	  'MODIFY_GROUP', $oldgroup);
	&foreign_call($group->{'module'}, "making_changes");
	&foreign_call($group->{'module'}, "modify_group", $oldgroup, $group);
	&foreign_call($group->{'module'}, "made_changes");
	&foreign_call($group->{'module'}, "unlock_user_files");
	}
}

# update_domain_owners_group([&new-domain], [&deleting-domain])
# If configure, update the member list of a secondary group which should
# contain all domain owners.
sub update_domain_owners_group
{
local ($newd, $deld) = @_;
return 0 if (!$config{'domains_group'});

# First make sure the group exists
&require_useradmin();
local @allgroups = &list_all_groups();
local ($group) = grep { $_->{'group'} eq $config{'domains_group'} } @allgroups;
return 0 if (!$group);

# Find domain owners with Unix logins
local @members;
foreach my $d (&list_domains(), $newd) {
	if ($d->{'unix'} && $d ne $deld) {
		push(@members, $d->{'user'});
		}
	}

# Update the group
local $oldgroup = { %$group };
$group->{'members'} = join(",", &unique(@members));
if ($group->{'members'} ne $oldgroup->{'members'}) {
	&foreign_call($group->{'module'}, "lock_user_files");
	&foreign_call($group->{'module'}, "set_group_envs", $group,
				      'MODIFY_GROUP', $oldgroup);
	&foreign_call($group->{'module'}, "making_changes");
	&foreign_call($group->{'module'}, "modify_group", $oldgroup, $group);
	&foreign_call($group->{'module'}, "made_changes");
	&foreign_call($group->{'module'}, "unlock_user_files");
	}
}

sub startstop_unix
{
if (!$config{'ftp'} && &foreign_installed("proftpd")) {
	# Even if the FTP feature is not enabled, show the proftpd start/stop
	# buttons.
	return &startstop_ftp();
	}
return ( );
}

sub stop_service_unix
{
return &stop_service_ftp();
}

sub start_service_unix
{
return &start_service_ftp();
}



$done_feature_script{'unix'} = 1;

1;

