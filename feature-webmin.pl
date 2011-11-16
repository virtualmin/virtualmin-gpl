sub require_acl
{
return if ($require_acl++);
&foreign_require("acl", "acl-lib.pl");
}

# setup_webmin(&domain)
# Creates a new user to manage this domain, with access to the appropriate
# modules with the right permissions
sub setup_webmin
{
&$first_print($text{'setup_webmin'});
&obtain_lock_webmin($_[0]);
&require_acl();
local $tmpl = &get_template($_[0]->{'template'});
local ($wuser) = grep { $_->{'name'} eq $_[0]->{'user'} }
		      &acl::list_users();
if ($wuser) {
	# Update the modules for existing Webmin user
	&set_user_modules($_[0], $wuser);
	}
else {
	# Create a new user
	local @modules;
	local %wuser = ( 'name' => $_[0]->{'user'},
			 'pass' => $_[0]->{'unix'} ? 'x' :
					&webmin_password($_[0]),
			 'notabs' => !$config{'show_tabs'},
			 'modules' => [ ],
			 'theme' => $config{'webmin_theme'} eq '*' ? undef :
				    $config{'webmin_theme'} eq '' ? '' :
				     $config{'webmin_theme'},
			 'real' => $_[0]->{'owner'},
			 );
	&acl::create_user(\%wuser);
	&set_user_modules($_[0], \%wuser);

	# Add to Webmin group
	if ($tmpl->{'webmin_group'} ne 'none') {
		local ($group) = grep { $_->{'name'} eq
				$tmpl->{'webmin_group'} } &acl::list_groups();
		if ($group) {
			push(@{$group->{'members'}}, $wuser{'name'});
			&acl::modify_group($group->{'name'}, $group);
			}
		}
	}
&update_extra_webmin($_[0]);
&release_lock_webmin($_[0]);
&register_post_action(\&restart_webmin);
&$second_print($text{'setup_done'});
}

# webmin_password(&domain)
# Returns an encrypted password for a virtual server
sub webmin_password
{
&require_acl();
return $_[0]->{'pass'} ? &acl::encrypt_password($_[0]->{'pass'})
		       : $_[0]->{'crypt_enc_pass'};
}

# delete_webmin(&domain)
# Delete the webmin user for the domain, and all his permissions
sub delete_webmin
{
&$first_print($text{'delete_webmin'});
&obtain_lock_webmin($_[0]);
&require_acl();

# Delete the user
&acl::delete_user($_[0]->{'user'});
local $m;
foreach $m (&get_all_module_infos()) {
	&unlink_logged("$config_directory/$m->{'dir'}/$_[0]->{'user'}.acl");
	}
&update_extra_webmin($_[0]);

# Delete from any groups
foreach my $group (&acl::list_groups()) {
	local $idx = &indexof($_[0]->{'user'}, @{$group->{'members'}});
	if ($idx >= 0) {
		splice(@{$group->{'members'}}, $idx, 1);
		&acl::modify_group($group->{'name'}, $group);
		}
	}

&release_lock_webmin($_[0]);
&register_post_action(\&restart_webmin);
&$second_print($text{'setup_done'});
}

# modify_webmin(&domain, &olddomain)
sub modify_webmin
{
if ($_[0]->{'home'} ne $_[1]->{'home'} && &foreign_check("htaccess-htpasswd")) {
	# If home has changed, update protected web directories that
	# referred to old dir
	&$first_print($text{'save_htaccess'});
	&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
	local @dirs = &htaccess_htpasswd::list_directories(1);
	foreach $d (@dirs) {
		if ($d->[0] eq $_[1]->{'home'}) {
			$d->[0] = $_[0]->{'home'};
			}
		else {
			$d->[0] =~ s/^$_[1]->{'home'}\//$_[0]->{'home'}\//;
			}
		if ($d->[1] =~ /^$_[1]->{'home'}\/(.*)$/) {
			# Need to update file too!
			$d->[1] = "$_[0]->{'home'}/$1";
			&require_apache();
			local $f = $d->[0]."/".
				   $htaccess_htpasswd::config{'htaccess'};
			local $conf = &apache::get_htaccess_config($f);
			&apache::save_directive(
				"AuthUserFile", [ $d->[1] ], $conf, $conf);
			&write_as_domain_user($_[0],
				sub { &flush_file_lines($f) });
			}
		}
	&htaccess_htpasswd::save_directories(\@dirs);
	&$second_print($text{'setup_done'});
	}
if (!$_[0]->{'parent'}) {
	# Update the Webmin user
	&obtain_lock_webmin($_[0]);
	&require_acl();
	local ($wuser) = grep { $_->{'name'} eq $_[1]->{'user'} }
			      &acl::list_users();
	if ($_[0]->{'unix'} ne $_[1]->{'unix'}) {
		# Turn on or off password synchronization
		$wuser->{'pass'} = $_[0]->{'unix'} ? 'x' :
					&webmin_password($_[0]);
		&acl::modify_user($_[1]->{'user'}, $wuser);
		}
	if ($_[0]->{'user'} ne $_[1]->{'user'}) {
		# Need to re-name user
		&$first_print($text{'save_webminuser'});
		$wuser->{'real'} = $_[0]->{'owner'};
		$wuser->{'name'} = $_[0]->{'user'};
		&acl::modify_user($_[1]->{'user'}, $wuser);

		# Rename in groups too
		foreach my $group (&acl::list_groups()) {
			local $idx = &indexof($_[1]->{'user'},
					      @{$group->{'members'}});
			if ($idx >= 0) {
				$group->{'members'}->[$idx] = $_[0]->{'user'};
				&acl::modify_group($group->{'name'}, $group);
				}
			}
		}
	elsif ($_[0]->{'owner'} ne $_[1]->{'owner'}) {
		# Need to update owner
		&$first_print($text{'save_webminreal'});
		$wuser->{'real'} = $_[0]->{'owner'};
		&acl::modify_user($_[0]->{'user'}, $wuser);
		}
	else {
		# Leave name unchanged
		&$first_print($text{'save_webmin'});
		}
	&set_user_modules($_[0], $wuser) if ($wuser);
	&update_extra_webmin($_[0]);
	&release_lock_webmin($_[0]);
	&register_post_action(\&restart_webmin);
	&$second_print($text{'setup_done'});
	return 1;
	}
elsif ($_[0]->{'parent'} && !$_[1]->{'parent'}) {
	# Webmin feature has been turned off .. so delete the user
	&delete_webmin($_[1]);
	}
return 0;
}

# clone_webmin(&old-domain, &domain)
# Does nothing, as the webmin user is re-created as part of the clone process
sub clone_webmin
{
return 1;
}

# validate_webmin(&domain)
# Make sure all Webmin users exist
sub validate_webmin
{
local ($d) = @_;
&require_acl();
local @users = &acl::list_users();
local ($wuser) = grep { $_->{'name'} eq $d->{'user'} } @users;
return &text('validate_ewebmin', $d->{'user'}) if (!$wuser);
foreach my $admin (&list_extra_admins($d)) {
	local ($wuser) = grep { $_->{'name'} eq $admin->{'name'} }
			      @users;
	return &text('validate_ewebminextra', $admin->{'name'})
		if (!$wuser);
	}
return undef;
}

# disable_webmin(&domain)
# Lock the password of the domains's Webmin user
sub disable_webmin
{
&$first_print($text{'disable_webmin'});
&obtain_lock_webmin($_[0]);
&require_acl();
local ($wuser) = grep { $_->{'name'} eq $_[0]->{'user'} } &acl::list_users();
if ($wuser) {
	$wuser->{'pass'} = "*LK*";
	&acl::modify_user($wuser->{'name'}, $wuser);
	&register_post_action(\&restart_webmin);
	}
&release_lock_webmin($_[0]);
&$second_print($text{'setup_done'});
}

# enable_webmin(&domain)
# Changes the password of the domain's Webmin user back to unix auth
sub enable_webmin
{
&$first_print($text{'enable_webmin'});
&obtain_lock_webmin($_[0]);
&require_acl();
local ($wuser) = grep { $_->{'name'} eq $_[0]->{'user'} } &acl::list_users();
if ($wuser) {
	$wuser->{'pass'} = "x";
	&acl::modify_user($wuser->{'name'}, $wuser);
	&register_post_action(\&restart_webmin);
	}
&release_lock_webmin($_[0]);
&$second_print($text{'setup_done'});
}

# restart_webmin()
sub restart_webmin
{
&$first_print($text{'setup_webminpid2'});
local %miniserv;
&get_miniserv_config(\%miniserv);
if (&check_pid_file($miniserv{'pidfile'})) {
	&reload_miniserv();
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'setup_webmindown'});
	}
}

# restart_usermin()
sub restart_usermin
{
&foreign_require("usermin", "usermin-lib.pl");
&$first_print($text{'setup_userminpid'});
&usermin::restart_usermin_miniserv();
&$second_print($text{'setup_done'});
}

# set_user_modules(&domain, &webminuser, [&acs-for-this-module], [no-features],
#		   [no-extra], [is-extra-admin], [&only-domain-ids])
sub set_user_modules
{
local ($d, $wuser, $acls, $nofeatures, $noextras, $isextra, $onlydoms) = @_;
local @mods;
local $tmpl = &get_template($_[0]->{'template'});

# Work out which module's ACLs to leave alone
local %hasmods = map { $_, 1 } @{$_[1]->{'modules'}};
%hasmods = ( ) if (!$config{'leave_acl'});

# Work out which domains and features exist
local @doms = ( $_[0], &get_domain_by("parent", $_[0]->{'id'}) );
local %doneid;
@doms = grep { !$doneid{$_->{'id'}}++ } @doms;
local (%features, $d, $f);
if (!$nofeatures) {
	foreach $d (@doms) {
		foreach $f (@features) {
			$features{$f}++ if ($d->{$f});
			}
		}
	}
if ($onlydoms) {
	local %onlydoms = map { $_, 1 } @$onlydoms;
	@doms = grep { $onlydoms{$_->{'id'}} } @doms;
	}

# Work out which extra (non feature-related) modules are available
local %avail = map { split(/=/, $_) } split(/\s+/, $tmpl->{'avail'});
local @extramods = grep { $avail{$_} } keys %avail;
if ($noextras) {
	@extramods = ( );
	}
local %extramods = map { $_, $avail{$_} }
		       grep { my $m=$_; { local $_; &foreign_check($m) } }
			@extramods;

# Grant access to BIND module if needed
if ($features{'dns'} && $avail{'dns'} && !$_[0]->{'provision_dns'}) {
	# Allow user to manage just this domain
	push(@mods, "bind8");
	local %acl = ( 'noconfig' => 1,
		       'zones' => join(" ",
				    map { $_->{'dom'} }
				     grep { $_->{'dns'} &&
				       !$_->{'provision_dns'} } @doms),
		       'dir' => &resolve_links($_[0]->{'home'}),
		       'master' => 0,
		       'slave' => 0,
		       'forward' => 0,
		       'delegation' => 0,
		       'defaults' => 0,
		       'reverse' => 0,
		       'multiple' => 1,
		       'ro' => 0,
		       'apply' => 2,
		       'file' => 0,
		       'params' => 1,
		       'opts' => 0,
		       'delete' => 0,
		       'gen' => 1,
		       'whois' => 1,
		       'findfree' => 1,
		       'slaves' => 0,
		       'remote' => 0,
		       'views' => 0,
		       'vlist' => '' );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "bind8")
		if (!$hasmods{'bind8'});
	}
else {
	@mods = grep { $_ ne "bind8" } @mods;
	}

# Grant access to MySQL module if needed
if ($features{'mysql'} && $avail{'mysql'}) {
	# Allow user to manage just the domain's DB
	push(@mods, "mysql");
	local %acl = ( 'noconfig' => 1,
		       'dbs' => join(" ", map { split(/\s+/, $_->{'db_mysql'}) }
					      grep { $_->{'mysql'} } @doms),
		       'create' => 0,
		       'delete' => 0,
		       'stop' => 0,
		       'perms' => 0,
		       'edonly' => 0,
		       'user' => &mysql_user($_[0]),
		       'pass' => &mysql_pass($_[0]),
		       'buser' => $_[0]->{'user'},
		       'bpath' => "/" );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "mysql")
		if (!$hasmods{'mysql'});
	}
else {
	@mods = grep { $_ ne "mysql" } @mods;
	}

# Grant access to PostgreSQL module if needed
if ($features{'postgres'} && $avail{'postgres'}) {
	# Allow user to manage just the domain's DB
	push(@mods, "postgresql");
	local %acl = ( 'noconfig' => 1,
		       'dbs' => join(" ",
				   map { split(/\s+/, $_->{'db_postgres'}) }
				       grep { $_->{'postgres'} } @doms),
		       'create' => 0,
		       'delete' => 0,
		       'stop' => 0,
		       'users' => 0,
		       'user' => &postgres_user($_[0]),
		       'pass' => &postgres_pass($_[0], 1),
		       'sameunix' => 1,
		       'backup' => 0,
		       'restore' => 0 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "postgresql")
		if (!$hasmods{'postgresql'});
	}
else {
	@mods = grep { $_ ne "postgresql" } @mods;
	}

# Grant access to Apache module if needed
if ($features{'web'} && $avail{'web'}) {
	# Allow user to manage just this website
	&require_apache();
	push(@mods, "apache");
	local @webdoms = grep { $_->{'web'} &&
				(!$_->{'alias'} || !$_->{'alias_mode'}) } @doms;
	local %acl = ( 'noconfig' => 1,
		       'virts' => join(" ",
			  map { $_->{'dom'}, "$_->{'dom'}:$_->{'web_port'}" }
			      @webdoms),
		       'global' => 0,
		       'create' => 0,
		       'vuser' => 0,
		       'vaddr' => 0,
		       'names' => 0,
		       'pipe' => 0,
		       'stop' => 0,
		       'dir' => &resolve_links($_[0]->{'home'}),
		       'aliasdir' => &resolve_links($_[0]->{'home'}),
		       'test_always' => 1,
		       'types' => join(" ",
				(0 .. 7, 9 .. 16,
				 18 .. $apache::directive_type_count)),
		       'dirsmode' => 2,
		       'dirs' => 'ServerName ServerAlias SSLEngine SSLCertificateFile SSLCertificateKeyFile SSLCACertificateFile',
		      );
	if (!$extramods{'phpini'}) {
		# If cannot access the php.ini module, deny access to PHP
		# directives in Apache too
		$acl{'dirs'} .= ' php_value php_flag php_admin_value php_admin_flag';
		}
	local @ssldoms = grep { $_->{'ssl'} } @webdoms;
	if (@ssldoms) {
		$acl{'virts'} .= " ".join(" ",
			map { $_->{'dom'}, "$_->{'dom'}:$_->{'web_sslport'}" }
			    @ssldoms);
		}
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "apache")
		if (!$hasmods{'apache'});
	}
else {
	@mods = grep { $_ ne "apache" } @mods;
	}

# Grant access to Webalizer module if needed
if ($features{'webalizer'} && $avail{'webalizer'}) {
	push(@mods, "webalizer");
	local @logs;
	local $d;
	foreach $d (grep { $_->{'webalizer'} } @doms) {
		push(@logs, &resolve_links(&get_website_log($d)));
		}
	@logs = &unique(@logs);
	local %acl = ( 'noconfig' => 1,
		       'view' => $tmpl->{'web_stats_noedit'},
		       'global' => 0,
		       'add' => 0,
		       'user' => $_[0]->{'user'},
		       'dir' => join(" ", @logs) );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "webalizer")
		if (!$hasmods{'webalizer'});
	}
else {
	@mods = grep { $_ ne "webalizer" } @mods;
	}

# Grant access to SpamAssassin module if needed, and if per-domain spamassassin
# configs are available
local @spamassassin_doms;
if (defined(&get_domain_spam_client)) {
	@spamassassin_doms = grep { &get_domain_spam_client($_) ne 'spamc' }
				  grep { $_->{'spam'} } @doms;
	}
if ($features{'spam'} && $avail{'spam'} && @spamassassin_doms) {
	push(@mods, "spam");
	local $sd = $spamassassin_doms[0];
	local %acl = ( 'noconfig' => 1,
		       'avail' => 'white,score,report,user,header,awl',
		       'procmailrc' => "$procmail_spam_dir/$sd->{'id'}",
		       'file' => "$spam_config_dir/$sd->{'id'}/virtualmin.cf",
		       'awl_groups' => $_[0]->{'group'},
		     );
	$acl{'files'} = join(' ',
			     map { "$spam_config_dir/$_->{'id'}/virtualmin.cf" }
			         @spamassassin_doms);
	$acl{'procmailrcs'} = join(' ',
			     map { "$procmail_spam_dir/$_->{'id'}" }
			         @spamassassin_doms);
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "spam")
		if (!$hasmods{'spam'});
	}
else {
	@mods = grep { $_ ne "spam" } @mods;
	}

# All users get access to virtualmin at least
local $can_create = $_[0]->{'domslimit'} && !$_[0]->{'no_create'} &&
		    $_[0]->{'unix'};
push(@mods, $module_name);
local %acl = ( 'noconfig' => 1,
	       'edit' => $_[0]->{'edit_domain'} ? 2 : 0,
	       'create' => $can_create ? 2 : 0,
	       'import' => 0,
	       'stop' => 0,
	       'local' => 0,
	       'nodbname' => $_[0]->{'nodbname'},
	       'norename' => $_[0]->{'norename'},
	       'forceunder' => $_[0]->{'forceunder'},
	       'safeunder' => $_[0]->{'safeunder'},
	       'domains' => join(" ", map { $_->{'id'} } @doms),
	       'admin' => $_[2] ? $_[0]->{'id'} : undef,
	      );
foreach $f (@opt_features, &list_feature_plugins(), 'virt') {
	$acl{"feature_$f"} = $_[0]->{"limit_$f"};
	}
foreach my $ed (@edit_limits) {
	$acl{'edit_'.$ed} = $_[0]->{'edit_'.$ed};
	}
$acl{'allowedscripts'} = $_[0]->{'allowedscripts'};
if ($acls) {
	foreach my $k (keys %$acls) {
		$acl{$k} = $acls->{$k};
		}
	}
&save_module_acl_logged(\%acl, $_[1]->{'name'});
%uaccess = %acl;

# Set global ACL options
local %acl = ( 'feedback' => 0,
	       'rpc' => 0,
	       'negative' => 1,
	       'readonly' => $_[0]->{'demo'},
	       'fileunix' => $_[0]->{'user'} );
$acl{'root'} = &resolve_links(
	&substitute_domain_template($tmpl->{'gacl_root'}, $_[0]));
if ($tmpl->{'gacl_umode'} == 1) {
	$acl{'uedit_mode'} = 5;
	$acl{'uedit'} = &substitute_domain_template($tmpl->{'gacl_ugroups'}, $_[0]);
	}
else {
	$acl{'uedit_mode'} = 2;
	$acl{'uedit'} = &substitute_domain_template($tmpl->{'gacl_uusers'}, $_[0]);
	}
$acl{'gedit_mode'} = 2;
$acl{'gedit'} = &substitute_domain_template($tmpl->{'gacl_groups'}, $_[0]);
if (!$_[0]->{'domslimit'}) {
	$acl{'desc_'.$module_name} = $text{'index_title2'};
	}
&save_module_acl_logged(\%acl, $_[1]->{'name'}, ".");

if ($extramods{'file'} && $_[0]->{'unix'}) {
	# Limit file manager to user's directory, as unix user
	local %acl = ( 'noconfig' => 1,
		       'uid' => $_[0]->{'uid'},
		       'follow' => 0,
		       'root' => &resolve_links($_[0]->{'home'}),
		       'home' => 0,
		       'goto' => 1 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "file")
		if (!$hasmods{'file'});
	push(@mods, "file");
	}

if ($_[0]->{'unix'}) {
	if ($extramods{'passwd'} == 1 && !$isextra) {
		# Can only change domain owners password
		local %acl = ( 'noconfig' => 1,
			       'mode' => 1,
			       'users' => $_[0]->{'user'},
			       'repeat' => 1,
			       'old' => 1,
			       'expire' => 0,
			       'others' => 1 );
		&save_module_acl_logged(\%acl, $_[1]->{'name'}, "passwd")
			if (!$hasmods{'passwd'});
		push(@mods, "passwd");
		}
	elsif ($extramods{'passwd'} == 2) {
		# Can change all mailbox passwords (except for the domain
		# owner, if this is an extra admin)
		local %acl = ( 'noconfig' => 1,
			       'mode' => 5,
			       'users' => $_[0]->{'group'},
			       'notusers' => $_[0]->{'user'},
			       'repeat' => 1,
			       'old' => 0,
			       'expire' => 0,
			       'others' => 1 );
		&save_module_acl_logged(\%acl, $_[1]->{'name'}, "passwd")
			if (!$hasmods{'passwd'});
		push(@mods, "passwd");
		}
	}

if ($extramods{'proc'} && $_[0]->{'unix'}) {
	# Can only manage and see his own processes
	local %acl = ( 'noconfig' => 1,
		       'uid' => $_[0]->{'uid'},
		       'edit' => 1,
		       'run' => 1,
		       'users' => $_[0]->{'user'},
		       'only' => ($extramods{'proc'} == 2) );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "proc")
		if (!$hasmods{'proc'});
	push(@mods, "proc");
	}

if ($extramods{'cron'} && $_[0]->{'unix'}) {
	# Can only manage his cron jobs
	local %acl = ( 'noconfig' => 1,
		       'mode' => 1,
		       'users' => $_[0]->{'user'},
		       'allow' => 0 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "cron")
		if (!$hasmods{'cron'});
	push(@mods, "cron");
	}

if ($extramods{'at'} && $_[0]->{'unix'}) {
	# Can only manage his at jobs
	local %acl = ( 'noconfig' => 1,
		       'mode' => 1,
		       'users' => $_[0]->{'user'},
		       'allow' => 0 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "at")
		if (!$hasmods{'at'});
	push(@mods, "at");
	}

if ($extramods{'telnet'} && $_[0]->{'unix'}) {
	# Cannot configure module
	local %acl = ( 'noconfig' => 1 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "telnet")
		if (!$hasmods{'telnet'});
	push(@mods, "telnet");
	}

if ($extramods{'custom'}) {
	# Cannot edit or create commands
	local %acl = ( 'noconfig' => 1,
		       'cmd' => '*',
		       'edit' => 0 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "custom")
		if (!$hasmods{'custom'});
	push(@mods, "custom");
	}

if ($extramods{'shell'} && $_[0]->{'unix'}) {
	# Can only run commands as server owner
	local %acl = ( 'noconfig' => 1,
		       'user' => $_[0]->{'user'} );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "shell")
		if (!$hasmods{'shell'});
	push(@mods, "shell");
	}

if ($extramods{'updown'} && $_[0]->{'unix'}) {
	# Can upload and download to home dir only
	local %acl = ( 'noconfig' => 1,
		       'dirs' => $_[0]->{'home'},
		       'home' => 0,
		       'mode' => 3, );
	if ($extramods{'updown'} == 2) {
		# Can only upload
		$acl{'download'} = 0;
		$acl{'fetch'} = 0;
		}
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "updown")
		if (!$hasmods{'updown'});
	push(@mods, "updown");

	# Set defaults for upload and download directories for this user
	local %udconfig;
	local $udfile = "$config_directory/updown/config";
	&lock_file($udfile);
	&read_file($udfile, \%udconfig);
	$udfile{'dir_'.$_[1]->{'name'}} ||= &resolve_links($_[0]->{'home'});
	$udfile{'ddir_'.$_[1]->{'name'}} ||= &resolve_links($_[0]->{'home'});
	&write_file($udfile, \%udconfig);
	&unlock_file($udfile);
	}

if ($extramods{'change-user'}) {
	# This module is always safe, so no ACL needs to be set
	push(@mods, "change-user");
	}

if ($extramods{'htaccess-htpasswd'} && $_[0]->{'unix'}) {
	# Can create .htaccess files in home dir, as user
        local %acl = ( 'noconfig' => 1,
                       'home' => 0,
                       'dirs' => $_[0]->{'home'},
                       'sync' => 0,
                       'user' => $_[0]->{'user'} );
        &save_module_acl_logged(\%acl, $_[1]->{'name'}, "htaccess-htpasswd")
                if (!$hasmods{'htaccess-htpasswd'});
        push(@mods, "htaccess-htpasswd");
        }

if ($extramods{'mailboxes'} && $_[0]->{'mail'}) {
	# Can read mailboxes of users
	local %acl = ( 'noconfig' => 1,
		       'fmode' => 1,
		       'from' => join(" ", map { $_->{'dom'} }
					       grep { $_->{'mail'} } @doms),
		       'canattach' => 0,
		       'candetach' => 0,
		       'dir' => &mail_domain_base($_[0]) );
	if (!&mail_system_needs_group()) {
		# For vpopmail, mailboxes are identified by domain
		$acl{'mmode'} = 6;
		$acl{'musers'} = ".*\@(".
				 join("|", map { $_->{'dom'} } @doms).")";
		}
	else {
		# By server GID
		$acl{'mmode'} = 5;
		$acl{'musers'} = $_[0]->{'gid'};
		}
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "mailboxes")
		if (!$hasmods{'mailboxes'});
	push(@mods, "mailboxes");
	}
else {
	@mods = grep { $_ ne "mailboxes" } @mods;
	}

if ($extramods{'webminlog'} && $_[0]->{'webmin'}) {
	# Can view own actions, and those of extra admins
	local @users = ( $_[0]->{'user'} );
	if ($virtualmin_pro) {
		push(@users, map { $_->{'name'} } &list_extra_admins($_[0]));
		}
	local %acl = ( 'users' => join(" ", @users),
		       'rollback' => 0 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "webminlog")
		if (!$hasmods{'webminlog'});
	push(@mods, "webminlog");
	}
else {
	@mods = grep { $_ ne "webminlog" } @mods;
	}

if ($extramods{'syslog'} && $_[0]->{'webmin'}) {
	# Can view log files for Apache and ProFTPd
	local @extras;
	local %done;
	foreach my $sd (@doms) {
		# Add Apache logs, for domains with websites and separate logs
		if ($sd->{'web'} && !$sd->{'alias_mode'}) {
			local $alog = &get_website_log($sd, 0);
			local $elog = &get_website_log($sd, 1);
			push(@extras, $alog." ".&text('webmin_alog',
						      $sd->{'dom'}))
				if ($alog && !$done{$alog}++);
			push(@extras, $elog." ".&text('webmin_elog',
						      $sd->{'dom'}))
				if ($elog && !$done{$elog}++);
			}
		# Add FTP logs
		if ($sd->{'ftp'}) {
			local $flog = &get_proftpd_log($sd->{'ip'});
			push(@extras, $flog." ".&text('webmin_flog',
						     $sd->{'dom'}))
				if ($flog && !$done{$flog}++);
			}
		}
	if (@extras) {
		local %acl = ( 'extras' => join("\t", @extras),
			       'any' => 0,
			       'noconfig' => 1,
			       'noedit' => 1,
			       'syslog' => 0,
			       'others' => 0 );
		&save_module_acl_logged(\%acl, $_[1]->{'name'}, "syslog")
			if (!$hasmods{'syslog'});
		push(@mods, "syslog");
		}
	else {
		# No logs found!
		@mods = grep { $_ ne "syslog" } @mods;
		}
	}
else {
	@mods = grep { $_ ne "syslog" } @mods;
	}

local @pconfs;
if ($extramods{'phpini'}) {
	# Can edit PHP configuration files
	foreach my $sd (@doms) {
		if ($sd->{'web'} && defined(&get_domain_php_mode) &&
		    &get_domain_php_mode($sd) ne "mod_php") {
			foreach my $ini (&list_domain_php_inis($sd)) {
				local @st = stat($ini->[1]);
				if (@st && $st[4] == $sd->{'uid'}) {
					if ($ini->[0]) {
						push(@pconfs, "$ini->[1]=".
						  &text('webmin_phpini2',
						    $sd->{'dom'}, $ini->[0]));
						}
					else {
						push(@pconfs, "$ini->[1]=".
						  &text('webmin_phpini',
						    $sd->{'dom'}));
						}
					}
				}
			}
		}
	}
if (@pconfs) {
	local %acl = ( 'php_inis' => join("\t", @pconfs),
		       'noconfig' => 1,
		       'global' => 0,
		       'anyfile' => 0,
		       'user' => $_[0]->{'user'},
		       'manual' => 1 );
	&save_module_acl_logged(\%acl, $_[1]->{'name'}, "phpini")
		if (!$hasmods{'phpini'});
	push(@mods, "phpini");
	}
else {
	@mods = grep { $_ ne "phpini" } @mods;
	}

if (!$noextras) {
	# Add any extra modules specified for this domain
	push(@mods, split(/\s+/, $_[0]->{'webmin_modules'}));

	# Add any extra modules specified in global config
	local @wmods = split(/\s+/, $config{'webmin_modules'});
	local $m;
	foreach $m (@wmods) {
		local %acl = ( 'noconfig' => 1 );
		&save_module_acl_logged(\%acl, $_[1]->{'name'}, $m)
			if (!$hasmods{$m});
		}
	push(@mods, @wmods);
	}

if (!$nofeatures) {
	# Add plugin-specified modules
	local $p;
	foreach $p (@plugins) {
		local @pmods = &plugin_call($p, "feature_webmin", $_[0],
					    \@doms);
		local $pm;
		foreach $pm (@pmods) {
			push(@mods, $pm->[0]);
			if ($pm->[1]) {
				&save_module_acl_logged(
					$pm->[1], $_[1]->{'name'}, $pm->[0]);
				}
			}
		}
	}

# Finally, override in settings from template Webmin group
local @ownmods = @mods;
if ($tmpl->{'webmin_group'} ne 'none') {
	local ($group) = grep { $_->{'name'} eq $tmpl->{'webmin_group'} }
			      &acl::list_groups();
	if ($group) {
		# Add modules from group to list
		push(@mods, @{$group->{'modules'}});

		# Copy group's ACLs to user
		&acl::copy_group_user_acl_files(
			$group->{'name'}, $wuser->{'name'},
			[ @{$group->{'modules'}}, "" ]);
		}
	}

$wuser->{'ownmods'} = [ &unique(@ownmods) ];
$wuser->{'modules'} = [ &unique(@mods) ];
$wuser->{'readonly'} = $module_name;
&acl::modify_user($wuser->{'name'}, $wuser);
}

# check_webmin_clash(&domain, [field])
# Returns 1 if a user or group with this name already exists
sub check_webmin_clash
{
if (!$_[1] || $_[1] eq 'user') {
	&require_acl();
	return 1 if ($_[0]->{'user'} eq 'webmin');
	return 0 if ($_[0]->{'webmin_overwrite'});
	local $u;
	foreach $u (&acl::list_users()) {
		return 1 if ($u->{'name'} eq $_[0]->{'user'});
		}
	}
return 0;
}

# modify_all_webmin([template-id])
# Updates the Webmin users for all domains (or just those on some template)
sub modify_all_webmin
{
local ($tid) = @_;
&$first_print($text{'check_allwebmin'});
&obtain_lock_webmin($_[0]);
	{
	local ($first_print, $second_print, $indent_print, $outdent_print);
	&set_all_null_print();
	local $d;
	foreach $d (&list_domains()) {
		if ($d->{'webmin'} && $config{'webmin'} &&
		    (!defined($tid) || $d->{'template'} == $tid)) {
			&modify_webmin($d, $d);
			}
		}
	}
&release_lock_webmin($_[0]);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_webmin);
}

# refresh_webmin_user(&domain, [quiet])
# Calls modify_webmin for a domain or the appropriate parent. This will
# update the ACL for the domain's Webmin login, create and update extra
# admins, and possibly update the reseller too.
sub refresh_webmin_user
{
local ($d, $quiet) = @_;
local $wd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
if ($wd->{'webmin'}) {
	&modify_webmin($wd, $wd);
	}
if ($wd->{'reseller'} && $virtualmin_pro) {
	local @resels = &list_resellers();
	local ($r) = grep { $_->{'name'} eq $d->{'reseller'} } @resels;
	if ($r) {
		&modify_reseller($r, $r);
		}
	}
}

# save_module_acl_logged(&acl, user, module)
# Save an ACL file, with locking and tight permissions
sub save_module_acl_logged
{
local $afile = "$config_directory/$_[2]/$_[1].acl";
&lock_file($afile);
&save_module_acl(@_);
&unlock_file($afile);
&set_ownership_permissions(undef, undef, 0600, $afile);
}

# update_extra_webmin(&domain, [force-disable])
# Creates, updates or deletes Webmin users to be the extra admins for a
# virtual server.
sub update_extra_webmin
{
local ($d, $forcedis) = @_;
local @admins = &list_extra_admins($d);
local %admins = map { $_->{'name'}, $_ } @admins;
local %webmins;
local @dis = split(/,/, $d->{'disabled'});
local $dis = !defined($forcedis) ? &indexof("webmin", @dis) >= 0
			         : $forcedis;

# Get current users
&require_acl();
foreach my $u (&acl::list_users()) {
	if (&indexof($module_name, @{$u->{'modules'}}) >= 0) {
		local %acl = &get_reseller_acl($u->{'name'});
		if ($acl{'admin'} && $acl{'admin'} eq $d->{'id'}) {
			# Found an admin for this domain
			if ($admins{$u->{'name'}}) {
				$webmins{$u->{'name'}} = $u;
				}
			else {
				# Who shouldn't exist!
				&acl::delete_user($u->{'name'});
				}
			}
		}
	}

# Create or update users
foreach my $admin (@admins) {
	local $wuser = $webmins{$admin->{'name'}};
	local $pass = $forcedis ? "*LK*" :
			&acl::encrypt_password($admin->{'pass'});
	if ($wuser) {
		# Update password (if changed)
		if ($pass eq "*LK*" ||
		    &acl::encrypt_password($admin->{'pass'}, $wuser->{'pass'})
		     ne $wuser->{'pass'}) {
			$wuser->{'pass'} = $pass;
			&acl::modify_user($wuser->{'name'}, $wuser);
			}
		}
	else {
		# Need to create user
		$wuser = { 'name' => $admin->{'name'},
			   'pass' => $pass,
			   'notabs' => !$config{'show_tabs'},
			   'modules' => [ ],
			   'theme' => $config{'webmin_theme'} eq '*' ? undef :
				      $config{'webmin_theme'} eq '' ? '' :
				       $config{'webmin_theme'}
			};
		&acl::create_user($wuser);
		}
	local %acl;
	foreach my $ed (@edit_limits) {
		if ($d->{'edit_'.$ed}) {
			$acl{'edit_'.$ed} = $admin->{'edit_'.$ed};
			}
		}
	$acl{'edit'} = $acl{'edit_domain'} ? 2 : 0;
	$acl{'create'} = $d->{'domslimit'} && $admin->{'create'} ? 2 : 0;
	$acl{'norename'} = $d->{'norename'} || $admin->{'norename'};
	$acl{'nodbname'} = $d->{'nodbname'} || $admin->{'nodbname'};
	$acl{'forceunder'} = $d->{'forceunder'} || $admin->{'forceunder'};
	&set_user_modules($d, $wuser, \%acl,
			  !$admin->{'features'}, !$admin->{'modules'}, 1,
			  $admin->{'doms'} ? [ split(/\s+/, $admin->{'doms'}) ]
					   : undef);
	}
}

# backup_webmin(&domain, file, &options)
# Create a tar file of all .acl files, for the server owner and extra admins
sub backup_webmin
{
local ($d, $file, $opts) = @_;
&$first_print($text{'backup_webmin'});
local @files;

# Add .acl files for domain owner
if (-r "$config_directory/$d->{'user'}.acl") {
	push(@files, "$d->{'user'}.acl");
	}
local @otheracls = glob("$config_directory/*/$d->{'user'}.acl");
@otheracls = grep { !/\*/ } @otheracls;
if (@otheracls) {
	push(@files, "*/$d->{'user'}.acl");
	}

# Add .acl files for extra admins
foreach my $admin (&list_extra_admins($d)) {
	push(@files, "$admin->{'name'}.acl");
	local @otheracls = glob("$config_directory/*/$admin->{'name'}.acl");
	@otheracls = grep { !/\*/ } @otheracls;
	if (@otheracls) {
		push(@files, "*/$admin->{'name'}.acl");
		}
	}

# Tar them all up
local $out = &backquote_command("cd $config_directory && tar cf ".quotemeta($file)." ".join(" ", @files)." 2>&1");
if ($?) {
	&$second_print(&text('backup_webminfailed', "<pre>$out</pre>"));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# restore_webmin(&domain, file, &options)
# Extract all .acl files from the backup
sub restore_webmin
{
local ($d, $file, $opts) = @_;
&$first_print($text{'restore_webmin'});
&obtain_lock_webmin($_[0]);
local $out = &backquote_logged(
	"cd $config_directory && tar xf ".quotemeta($file)." 2>&1");
local $rv;
if ($?) {
	&$second_print(&text('backup_webminfailed', "<pre>$out</pre>"));
	$rv = 0;
	}
else {
	&$second_print($text{'setup_done'});
	$rv = 1;
	}
&release_lock_webmin($_[0]);
return $rv;
}

# links_webmin(&domain)
# Returns a link to the Webmin Actions Log module
sub links_webmin
{
local ($d) = @_;
return ( { 'mod' => 'webminlog',
	   'desc' => $text{'links_webminlog'},
	   'page' => "search.cgi?uall=0&user=".&urlize($d->{'user'}).
		     "&mall=1&tall=2&fall=1",
	   'cat' => 'logs',
	 } );
return ( );
}

# show_template_webmin(&tmpl)
# Outputs HTML for editing webmin-user-related template options
sub show_template_webmin
{
local ($tmpl) = @_;

# Global ACL on or off
if (!$tmpl->{'default'}) {
	local @gacl_fields = ( "gacl_umode", "gacl_uusers", "gacl_ugroups",
			       "gacl_groups", "gacl_root" );
	local $dis1 = &js_disable_inputs(\@gacl_fields, [ ]);
	local $dis2 = &js_disable_inputs([ ], \@gacl_fields);
	print &ui_table_row(&hlink($text{'tmpl_gacl'}, "template_gacl"),
		&ui_radio("gacl", int($tmpl->{'gacl'}),
		   [ [ 0, $text{'default'}, "onClick='$dis1'" ],
		     [ 1, $text{'tmpl_gaclbelow'}, "onClick='$dis2'" ] ]));
	}

# Global ACL users
print &ui_table_row(&hlink($text{'tmpl_gaclu'}, "template_gacl_umode"),
    &ui_radio("gacl_umode", int($tmpl->{'gacl_umode'}),
	[ [ 0, $text{'tmpl_gacl0'}." ".
	       &ui_textbox("gacl_uusers",
	       $tmpl->{'gacl_umode'} == 0 ? $tmpl->{'gacl_uusers'} : "",
		 40)."<br>\n" ],
	  [ 1, $text{'tmpl_gacl1'}." ".
	       &ui_textbox("gacl_ugroups",
	       $tmpl->{'gacl_umode'} == 1 ? $tmpl->{'gacl_ugroups'} :"",
	       40) ] ]));

# Global ACL groups
print &ui_table_row(&hlink($text{'tmpl_gaclg'}, "template_groups"),
		    &ui_textbox("gacl_groups", $tmpl->{'gacl_groups'}, 40));

# Global ACL root
print &ui_table_row(&hlink($text{'tmpl_gaclr'}, "template_root"),
		    &ui_textbox("gacl_root", $tmpl->{'gacl_root'}, 40));

# Extra admin prefix
print &ui_table_row(
	&hlink($text{'tmpl_extra_prefix'}, "template_extra_prefix"),
	&none_def_input("extra_prefix", $tmpl->{'extra_prefix'},
		    	$text{'tmpl_sel'}, 0, 0, undef, [ "extra_prefix" ])." ".
	&ui_textbox("extra_prefix", $tmpl->{'extra_prefix'} eq "none" ? undef :
				  $tmpl->{'extra_prefix'}, 15));

# Webmin group for domain owner
&require_acl();
local @groups = &acl::list_groups();
if (@groups) {
	print &ui_table_row(
	  &hlink($text{'tmpl_wgroup'}, "template_webmin_group"),
	    &ui_select("webmin_group", $tmpl->{'webmin_group'},
	      [ $tmpl->{'default'} ? ( )
				   : ( [ "", "&lt;$text{'default'}&gt;" ] ),
		[ "none", "&lt;$text{'newtmpl_none'}&gt;" ],
		map { [ $_->{'name'} ] } &acl::list_groups() ]));
	}
}

# parse_template_webmin(&tmpl)
# Updates webmin-user-related template options from %in
sub parse_template_webmin
{
local ($tmpl) = @_;

# Save global ACL
$tmpl->{'gacl'} = $in{'gacl'};
$tmpl->{'gacl_umode'} = $in{'gacl_umode'};
$tmpl->{'gacl_uusers'} = $in{'gacl_uusers'};
$tmpl->{'gacl_ugroups'} = $in{'gacl_ugroups'};
$tmpl->{'gacl_groups'} = $in{'gacl_groups'};
$tmpl->{'gacl_root'} = $in{'gacl_root'};
$tmpl->{'extra_prefix'} = &parse_none_def("extra_prefix");
$tmpl->{'webmin_group'} = $in{'webmin_group'};
}

# get_reseller_acl(username)
# Returns just the ACL for some reseller
sub get_reseller_acl
{
local %acl;
&read_file_cached("$module_config_directory/$_[0].acl", \%acl);
if (defined(&theme_get_module_acl)) {
	%acl = &theme_get_module_acl($_[0], $module_name, \%acl);
	}
return %acl;
}

# obtain_lock_webmin()
# Lock a flag file indicating that Virtualmin is managing Webmin users.
# Real locking is done in acl-lib.pl.
sub obtain_lock_webmin
{
return if (!$config{'webmin'});
&obtain_lock_anything();
if ($main::got_lock_webmin == 0) {
	&lock_file("$module_config_directory/webminlock");
	}
$main::got_lock_webmin++;
}

# release_lock_webmin()
# Release the lock flag file
sub release_lock_webmin
{
return if (!$config{'webmin'});
if ($main::got_lock_webmin == 1) {
	&unlock_file("$module_config_directory/webminlock");
	}
$main::got_lock_webmin-- if ($main::got_lock_webmin);
&release_lock_anything();
}

$done_feature_script{'webmin'} = 1;

1;

