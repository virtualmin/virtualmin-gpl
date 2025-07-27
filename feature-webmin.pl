sub require_acl
{
return if ($require_acl++);
&foreign_require("acl");
}

# setup_webmin(&domain)
# Creates a new user to manage this domain, with access to the appropriate
# modules with the right permissions
sub setup_webmin
{
my ($d) = @_;
&$first_print($text{'setup_webmin'});
&obtain_lock_webmin($d);
&require_acl();
my $tmpl = &get_template($d->{'template'});
my ($wuser) = grep { $_->{'name'} eq $d->{'user'} }
		   &acl::list_users();
if ($wuser) {
	# Update the modules for existing Webmin user
	if (!&remote_webmin()) {
		&set_user_modules($d, $wuser);
		}
	}
else {
	# Create a new user
	my @modules;
	my %wuser = ( 'name' => $d->{'user'},
		      'pass' => $d->{'unix'} ? 'x' : &webmin_password($d),
		      'notabs' => !$config{'show_tabs'},
		      'modules' => [ ],
		      'theme' => $config{'webmin_theme'} eq '*' ? undef :
				 $config{'webmin_theme'} eq '' ? '' :
				     $config{'webmin_theme'},
		      'real' => $d->{'owner'},
		      'email' => $d->{'emailto'},
		    );
	&acl::create_user(\%wuser);
	&set_user_modules($d, \%wuser);

	# Add to Webmin group
	if ($tmpl->{'webmin_group'} ne 'none') {
		my ($group) = grep { $_->{'name'} eq $tmpl->{'webmin_group'} }
				   &acl::list_groups();
		if ($group) {
			push(@{$group->{'members'}}, $wuser{'name'});
			&acl::modify_group($group->{'name'}, $group);
			}
		}
	}
&update_extra_webmin($d);
&release_lock_webmin($d);
&register_post_action(\&restart_webmin);
&$second_print($text{'setup_done'});
return 1;
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
my ($d, $preserve) = @_;
&$first_print($text{'delete_webmin'});
&obtain_lock_webmin($d);
&require_acl();

if (!$preserve || !&remote_webmin($d)) {
	# Delete the user
	&acl::delete_user($d->{'user'});
	&update_extra_webmin($d);

	# Delete from any groups
	foreach my $group (&acl::list_groups()) {
		my $idx = &indexof($d->{'user'}, @{$group->{'members'}});
		if ($idx >= 0) {
			splice(@{$group->{'members'}}, $idx, 1);
			&acl::modify_group($group->{'name'}, $group);
			}
		}
	}

# Clear Webmin sessions
my %miniserv;
&get_miniserv_config(\%miniserv);
&acl::delete_session_user(\%miniserv, $d->{'user'});

&release_lock_webmin($d);
&register_post_action(\&restart_webmin);
&$second_print($text{'setup_done'});
return 1;
}

# modify_webmin(&domain, &olddomain)
sub modify_webmin
{
my ($d, $oldd) = @_;
if ($d->{'home'} ne $oldd->{'home'} && &foreign_check("htaccess-htpasswd")) {
	# If home has changed, update protected web directories that
	# referred to old dir
	&$first_print($text{'save_htaccess'});
	&foreign_require("htaccess-htpasswd");
	my @dirs = &htaccess_htpasswd::list_directories(1);
	foreach my $dir (@dirs) {
		if ($dir->[0] eq $oldd->{'home'}) {
			$dir->[0] = $d->{'home'};
			}
		else {
			$dir->[0] =~ s/^$oldd->{'home'}\//$d->{'home'}\//;
			}
		if ($dir->[1] =~ /^$oldd->{'home'}\/(.*)$/) {
			# Need to update file too!
			$dir->[1] = "$d->{'home'}/$1";
			&require_apache();
			my $f = $dir->[0]."/".
				   $htaccess_htpasswd::config{'htaccess'};
			my $conf = &apache::get_htaccess_config($f);
			&apache::save_directive(
				"AuthUserFile", [ $dir->[1] ], $conf, $conf);
			&write_as_domain_user($d,
				sub { &flush_file_lines($f) });
			}
		}
	&htaccess_htpasswd::save_directories(\@dirs);
	&$second_print($text{'setup_done'});
	}
if (!$d->{'parent'}) {
	# Update the Webmin user
	&obtain_lock_webmin($d);
	&require_acl();
	my ($wuser) = grep { $_->{'name'} eq $oldd->{'user'} }
			      &acl::list_users();
	if ($d->{'unix'} ne $oldd->{'unix'}) {
		# Turn on or off password synchronization
		$wuser->{'pass'} = $d->{'unix'} ? 'x' :
					&webmin_password($d);
		&acl::modify_user($oldd->{'user'}, $wuser);
		}
	if ($d->{'user'} ne $oldd->{'user'}) {
		# Need to re-name user
		&$first_print($text{'save_webminuser'});
		$wuser->{'real'} = $d->{'owner'};
		$wuser->{'email'} = $d->{'emailto'};
		$wuser->{'name'} = $d->{'user'};
		&acl::modify_user($oldd->{'user'}, $wuser);

		# Rename in groups too
		foreach my $group (&acl::list_groups()) {
			my $idx = &indexof($oldd->{'user'},
					      @{$group->{'members'}});
			if ($idx >= 0) {
				$group->{'members'}->[$idx] = $d->{'user'};
				&acl::modify_group($group->{'name'}, $group);
				}
			}
		}
	elsif ($d->{'owner'} ne $oldd->{'owner'} ||
	       $d->{'emailto'} ne $oldd->{'emailto'}) {
		# Need to update owner or email
		&$first_print($text{'save_webminreal'});
		$wuser->{'real'} = $d->{'owner'};
		$wuser->{'email'} = $d->{'emailto'};
		&acl::modify_user($d->{'user'}, $wuser);
		}
	else {
		# Leave name unchanged
		&$first_print($text{'save_webmin'});
		}
	&set_user_modules($d, $wuser) if ($wuser);
	&update_extra_webmin($d);
	&release_lock_webmin($d);
	&register_post_action(\&restart_webmin);
	&$second_print($text{'setup_done'});
	return 1;
	}
elsif ($d->{'parent'} && !$oldd->{'parent'}) {
	# Webmin feature has been turned off .. so delete the user
	&delete_webmin($oldd);
	}
return 0;
}

# clone_webmin(&old-domain, &domain)
# Copy Webmin user settings to the new domain
sub clone_webmin
{
my ($oldd, $d) = @_;
&obtain_lock_webmin($d);
&require_acl();
my ($olduser) = grep { $_->{'name'} eq $oldd->{'user'} } &acl::list_users();
my ($user) = grep { $_->{'name'} eq $d->{'user'} } &acl::list_users();
if ($olduser && $user) {
	$user->{'theme'} = $olduser->{'theme'};
	$user->{'lang'} = $olduser->{'lang'};
	&acl::modify_user($d->{'user'}, $user);
	}
&release_lock_webmin($d);
&register_post_action(\&restart_webmin);
return 1;
}

# validate_webmin(&domain)
# Make sure all Webmin users exist
sub validate_webmin
{
my ($d) = @_;
&require_acl();
my @users = &acl::list_users();
my ($wuser) = grep { $_->{'name'} eq $d->{'user'} } @users;
return &text('validate_ewebmin', $d->{'user'}) if (!$wuser);
foreach my $admin (&list_extra_admins($d)) {
	my ($wuser) = grep { $_->{'name'} eq $admin->{'name'} } @users;
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
my ($wuser) = grep { $_->{'name'} eq $_[0]->{'user'} } &acl::list_users();
if ($wuser) {
	$wuser->{'pass'} = "*LK*";
	&acl::modify_user($wuser->{'name'}, $wuser);
	&register_post_action(\&restart_webmin);
	}
&release_lock_webmin($_[0]);
&$second_print($text{'setup_done'});
return 1;
}

# enable_webmin(&domain)
# Changes the password of the domain's Webmin user back to unix auth
sub enable_webmin
{
&$first_print($text{'enable_webmin'});
&obtain_lock_webmin($_[0]);
&require_acl();
my ($wuser) = grep { $_->{'name'} eq $_[0]->{'user'} } &acl::list_users();
if ($wuser) {
	$wuser->{'pass'} = "x";
	&acl::modify_user($wuser->{'name'}, $wuser);
	&register_post_action(\&restart_webmin);
	}
&release_lock_webmin($_[0]);
&$second_print($text{'setup_done'});
return 1;
}

# restart_webmin()
# Send a signal to Webmin to re-read its config
sub restart_webmin
{
&$first_print($text{'setup_webminpid2'});
eval {
	local $main::error_must_die = 1;
	&reload_miniserv();
	};
if ($@) {
	&$second_print(&text('setup_webmindown2', "$@"));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# restart_webmin_fully()
# Send a signal to Webmin to make it fully restart and re-read its config
sub restart_webmin_fully
{
&$first_print($text{'setup_webminpid'});
eval {
	local $main::error_must_die = 1;
	&restart_miniserv();
	};
if ($@) {
	&$second_print(&text('setup_webmindown2', "$@"));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# restart_usermin()
# Send a signal to Usermin to make it fully restart and re-read it's config
sub restart_usermin
{
&foreign_require("usermin");
&$first_print($text{'setup_userminpid'});
eval {
	local $main::error_must_die = 1;
	&usermin::restart_usermin_miniserv();
	};
if ($@) {
	&$second_print(&text('setup_usermindown2', "$@"));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# set_user_modules(&domain, &webminuser, [&acls-for-this-module], [no-features],
#		   [no-extra], [is-extra-admin], [&only-domain-ids])
sub set_user_modules
{
my ($d, $wuser, $acls, $nofeatures, $noextras, $isextra, $onlydoms) = @_;
my @mods;
my $tmpl = &get_template($d->{'template'});
my $chroot = &get_domain_jailkit($d);

# Work out which module's ACLs to leave alone
my %hasmods = map { $_, 1 } @{$wuser->{'modules'}};
%hasmods = ( ) if (!$config{'leave_acl'});

# Work out which domains and features exist
my @doms = ( $d, &get_domain_by("parent", $d->{'id'}) );
my %doneid;
@doms = grep { !$doneid{$_->{'id'}}++ } @doms;
my (%features, $sd, $f);
if (!$nofeatures) {
	foreach $sd (@doms) {
		foreach $f (@features) {
			$features{$f}++ if ($sd->{$f});
			}
		}
	}
if ($onlydoms) {
	my %onlydoms = map { $_, 1 } @$onlydoms;
	@doms = grep { $onlydoms{$_->{'id'}} } @doms;
	}

# Modules that this user should be granted access to, and exist
# on this system
my %mods;
foreach my $avail (split(/\s+/, $tmpl->{'avail'})) {
	my ($m, $a) = split(/=/, $avail, 2);
	if ($a && &foreign_check($a)) {
		$mods{$m} = $a;
		}
	}

# Grant access to BIND module if needed
if ($features{'dns'} && $mods{'dns'} && !$d->{'provision_dns'} &&
    !$d->{'dns_cloud'}) {
	# Allow user to manage just their domains
	push(@mods, "bind8");
	my %acl = ( 'noconfig' => 1,
		       'zones' => join(" ",
				    map { $_->{'dom'} }
				     grep { $_->{'dns'} &&
				            !$_->{'provision_dns'} &&
					    !$_->{'dns_cloud'} } @doms),
		       'dir' => &resolve_links($d->{'home'}),
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
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "bind8")
		if (!$hasmods{'bind8'});
	}
else {
	@mods = grep { $_ ne "bind8" } @mods;
	}

# Grant access to MySQL module if needed
if ($features{'mysql'} && $mods{'mysql'}) {
	# Allow user to manage just the domain's DB
	my $mymod = &require_dom_mysql($d);
	push(@mods, $mymod);
	my %acl = ( 'noconfig' => 1,
		       'dbs' => join(" ", map { split(/\s+/, $_->{'db_mysql'}) }
					      grep { $_->{'mysql'} } @doms),
		       'create' => 0,
		       'delete' => 0,
		       'stop' => 0,
		       'perms' => 0,
		       'edonly' => 0,
		       'user' => &mysql_user($d),
		       'pass' => &mysql_pass($d),
		       'buser' => $d->{'user'},
		       'bpath' => "/" );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, $mymod)
		if (!$hasmods{$mymod});
	}
else {
	@mods = grep { !/^mysql(-.*)?$/ } @mods;
	}

# Grant access to PostgreSQL module if needed
if ($features{'postgres'} && $mods{'postgres'}) {
	# Allow user to manage just the domain's DB
	push(@mods, "postgresql");
	my %acl = ( 'noconfig' => 1,
		       'dbs' => join(" ",
				   map { split(/\s+/, $_->{'db_postgres'}) }
				       grep { $_->{'postgres'} } @doms),
		       'create' => 0,
		       'delete' => 0,
		       'stop' => 0,
		       'users' => 0,
		       'user' => &postgres_user($d),
		       'pass' => &postgres_pass($d, 1),
		       'sameunix' => 1,
		       'backup' => 0,
		       'restore' => 0 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "postgresql")
		if (!$hasmods{'postgresql'});
	}
else {
	@mods = grep { $_ ne "postgresql" } @mods;
	}

# Grant access to Apache module if needed
if ($features{'web'} && $mods{'web'} && $d->{'edit_phpmode'}) {
	# Allow user to manage just this website
	&require_apache();
	push(@mods, "apache");
	my @webdoms = grep { $_->{'web'} &&
			     (!$_->{'alias'} || !$_->{'alias_mode'}) } @doms;
	my %acl = ( 'noconfig' => 1,
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
		       'dir' => &resolve_links($d->{'home'}),
		       'aliasdir' => &resolve_links($d->{'home'}),
		       'test_always' => 1,
		       'types' => join(" ",
				(0 .. 7, 9 .. 16,
				 18 .. $apache::directive_type_count)),
		       'dirsmode' => 2,
		       'dirs' => 'ServerName ServerAlias SSLEngine SSLCertificateFile '.
				 'SSLCertificateKeyFile SSLCACertificateFile '.
				 'php_value php_flag php_admin_value php_admin_flag',
		      );
	my @ssldoms = grep { $_->{'ssl'} } @webdoms;
	if (@ssldoms) {
		$acl{'virts'} .= " ".join(" ",
			map { $_->{'dom'}, "$_->{'dom'}:$_->{'web_sslport'}" }
			    @ssldoms);
		}
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "apache")
		if (!$hasmods{'apache'});
	}
else {
	@mods = grep { $_ ne "apache" } @mods;
	}

# Grant access to Webalizer module if needed
if ($features{'webalizer'} && $mods{'webalizer'}) {
	push(@mods, "webalizer");
	my @logs;
	my $d;
	foreach $d (grep { $_->{'webalizer'} } @doms) {
		push(@logs, &resolve_links(&get_website_log($d)));
		}
	@logs = &unique(@logs);
	my %acl = ( 'noconfig' => 1,
		       'view' => $tmpl->{'web_stats_noedit'},
		       'global' => 0,
		       'add' => 0,
		       'user' => $d->{'user'},
		       'dir' => join(" ", @logs) );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "webalizer")
		if (!$hasmods{'webalizer'});
	}
else {
	@mods = grep { $_ ne "webalizer" } @mods;
	}

# Grant access to SpamAssassin module if needed, and if per-domain spamassassin
# configs are available
my @spamassassin_doms;
if (defined(&get_domain_spam_client)) {
	@spamassassin_doms = grep { &get_domain_spam_client($_) ne 'spamc' }
				  grep { $_->{'spam'} } @doms;
	}
if ($features{'spam'} && $mods{'spam'} && @spamassassin_doms) {
	push(@mods, "spam");
	my $sd = $spamassassin_doms[0];
	my %acl = ( 'noconfig' => 1,
		       'avail' => 'white,score,report,user,header,awl',
		       'procmailrc' => "$procmail_spam_dir/$sd->{'id'}",
		       'file' => "$spam_config_dir/$sd->{'id'}/virtualmin.cf",
		       'awl_groups' => $d->{'group'},
		     );
	$acl{'files'} = join(' ',
			     map { "$spam_config_dir/$_->{'id'}/virtualmin.cf" }
			         @spamassassin_doms);
	$acl{'procmailrcs'} = join(' ',
			     map { "$procmail_spam_dir/$_->{'id'}" }
			         @spamassassin_doms);
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "spam")
		if (!$hasmods{'spam'});
	}
else {
	@mods = grep { $_ ne "spam" } @mods;
	}

# All users get access to virtualmin at least
my $can_create = $d->{'domslimit'} && !$d->{'no_create'} &&
		    $d->{'unix'};
push(@mods, $module_name);
my %acl = ( 'noconfig' => 1,
	       'edit' => $d->{'edit_domain'} ? 2 : 0,
	       'create' => $can_create ? 2 : 0,
	       'import' => 0,
	       'stop' => 0,
	       'local' => 0,
	       'nodbname' => $d->{'nodbname'},
	       'norename' => $d->{'norename'},
	       'migrate' => $d->{'migrate'},
	       'forceunder' => $d->{'forceunder'},
	       'safeunder' => $d->{'safeunder'},
	       'ipfollow' => $d->{'ipfollow'},
	       'domains' => join(" ", map { $_->{'id'} } @doms),
	       'admin' => $acls ? $d->{'id'} : undef,
	      );
foreach $f (@opt_features, &list_feature_plugins(), 'virt') {
	$acl{"feature_$f"} = $d->{"limit_$f"};
	}
foreach my $ed (@edit_limits) {
	$acl{'edit_'.$ed} = $d->{'edit_'.$ed};
	}
$acl{'allowedscripts'} = $d->{'allowedscripts'};
if ($acls) {
	foreach my $k (keys %$acls) {
		$acl{$k} = $acls->{$k};
		}
	}
&save_module_acl_logged(\%acl, $wuser->{'name'});
%uaccess = %acl;

# Set global ACL options
my %acl = ( 'feedback' => 0,
	       'rpc' => 0,
	       'negative' => 1,
	       'readonly' => $d->{'demo'},
	       'fileunix' => $d->{'user'} );
if ($chroot) {
	$acl{'root'} = $d->{'home'};
	}
else {
	$acl{'root'} = &resolve_links(
		&substitute_domain_template($tmpl->{'gacl_root'}, $d));
	}
if ($tmpl->{'gacl_umode'} == 1) {
	$acl{'uedit_mode'} = 5;
	$acl{'uedit'} = &substitute_domain_template($tmpl->{'gacl_ugroups'}, $d);
	}
else {
	$acl{'uedit_mode'} = 2;
	$acl{'uedit'} = &substitute_domain_template($tmpl->{'gacl_uusers'}, $d);
	}
$acl{'gedit_mode'} = 2;
$acl{'gedit'} = &substitute_domain_template($tmpl->{'gacl_groups'}, $d);
if (!$d->{'domslimit'}) {
	$acl{'desc_'.$module_name} = $text{'index_title2'};
	}
&save_module_acl_logged(\%acl, $wuser->{'name'}, ".");

if ($mods{'filemin'} && !$noextra && $d->{'unix'}) {
	# Limit new HTML file manager to user's directory, as unix user
	my $modname = &foreign_check("file-manager") ?
				"file-manager" : "filemin";
	my $homedir;
	if (@doms == 1) {
		$homedir = $doms[0]->{'home'};
		}
	else {
		$homedir = $d->{'home'};
		}
	my %acl = ( 'noconfig' => 1,
		       'work_as_root' => 0,
		       'work_as_user', $d->{'user'},
		       'allowed_paths' => &resolve_links($homedir),
		     );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, $modname)
		if (!$hasmods{$modname});
	push(@mods, $modname);
	}

if ($d->{'unix'} && !$noextra) {
	if ($mods{'passwd'} == 1 && !$isextra) {
		# Can only change domain owners password
		my %acl = ( 'noconfig' => 1,
			       'mode' => 1,
			       'users' => $d->{'user'},
			       'repeat' => 1,
			       'old' => 1,
			       'expire' => 0,
			       'others' => 1 );
		&save_module_acl_logged(\%acl, $wuser->{'name'}, "passwd")
			if (!$hasmods{'passwd'});
		push(@mods, "passwd");
		}
	elsif ($mods{'passwd'} == 2) {
		# Can change all mailbox passwords (except for the domain
		# owner, if this is an extra admin)
		my %acl = ( 'noconfig' => 1,
			       'mode' => 5,
			       'users' => $d->{'group'},
			       'notusers' => $d->{'user'},
			       'repeat' => 1,
			       'old' => 0,
			       'expire' => 0,
			       'others' => 1 );
		&save_module_acl_logged(\%acl, $wuser->{'name'}, "passwd")
			if (!$hasmods{'passwd'});
		push(@mods, "passwd");
		}
	}

if ($mods{'proc'} && !$noextra && $d->{'unix'} && !$chroot) {
	# Can only manage and see his own processes
	my %acl = ( 'noconfig' => 1,
		       'uid' => $d->{'uid'},
		       'edit' => 1,
		       'run' => 1,
		       'users' => $d->{'user'},
		       'only' => ($mods{'proc'} == 2) );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "proc")
		if (!$hasmods{'proc'});
	push(@mods, "proc");
	}

if ($mods{'cron'} && !$noextra && $d->{'unix'} && !$chroot) {
	# Can only manage his cron jobs
	my %acl = ( 'noconfig' => 1,
		       'mode' => 1,
		       'users' => $d->{'user'},
		       'allow' => 0 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "cron")
		if (!$hasmods{'cron'});
	push(@mods, "cron");
	}

if ($mods{'at'} && !$noextra && $d->{'unix'} && !$chroot) {
	# Can only manage his at jobs
	my %acl = ( 'noconfig' => 1,
		       'mode' => 1,
		       'users' => $d->{'user'},
		       'allow' => 0,
		       'stop' => 0, );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "at")
		if (!$hasmods{'at'});
	push(@mods, "at");
	}

if ($mods{'telnet'} && !$noextra && $d->{'unix'}) {
	# Cannot configure telnet module
	my %acl = ( 'noconfig' => 1 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "telnet")
		if (!$hasmods{'telnet'});
	push(@mods, "telnet");
	}

if ($mods{'xterm'} && !$noextra && $d->{'unix'}) {
	# Cannot configure module xterm module, and shell opens as domain user
	my %acl = ( 'noconfig' => 1,
		       'user' => $d->{'user'} );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "xterm")
		if (!$hasmods{'xterm'});
	push(@mods, "xterm");
	}

if ($mods{'custom'} && !$noextra) {
	# Cannot edit or create commands
	my %acl = ( 'noconfig' => 1,
		       'cmd' => '*',
		       'edit' => 0 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "custom")
		if (!$hasmods{'custom'});
	push(@mods, "custom");
	}

if ($mods{'shell'} && !$noextra && $d->{'unix'}) {
	# Can only run commands as server owner
	my %acl = ( 'noconfig' => 1,
		       'user' => $d->{'user'},
		       'chroot' => $chroot || '/' );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "shell")
		if (!$hasmods{'shell'});
	push(@mods, "shell");
	}

if ($mods{'updown'} && !$noextra && $d->{'unix'}) {
	# Can upload and download to home dir only
	my %acl = ( 'noconfig' => 1,
		       'dirs' => $d->{'home'},
		       'home' => 0,
		       'mode' => 3, );
	if ($mods{'updown'} == 2) {
		# Can only upload
		$acl{'download'} = 0;
		$acl{'fetch'} = 0;
		}
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "updown")
		if (!$hasmods{'updown'});
	push(@mods, "updown");

	# Set defaults for upload and download directories for this user
	my %udconfig;
	my $udfile = "$config_directory/updown/config";
	&lock_file($udfile);
	&read_file($udfile, \%udconfig);
	$udconfig{'dir_'.$wuser->{'name'}} ||= &resolve_links($d->{'home'});
	$udconfig{'ddir_'.$wuser->{'name'}} ||= &resolve_links($d->{'home'});
	&write_file($udfile, \%udconfig);
	&unlock_file($udfile);
	}

if ($mods{'change-user'} && !$noextra) {
	# This module is always safe, so no ACL needs to be set
	push(@mods, "change-user");
	}

if ($mods{'htaccess-htpasswd'} && !$noextra && $d->{'unix'}) {
	# Can create .htaccess files in home dir, as user
        my %acl = ( 'noconfig' => 1,
                       'home' => 0,
                       'dirs' => $d->{'home'},
                       'sync' => 0,
                       'user' => $d->{'user'} );
        &save_module_acl_logged(\%acl, $wuser->{'name'}, "htaccess-htpasswd")
                if (!$hasmods{'htaccess-htpasswd'});
        push(@mods, "htaccess-htpasswd");
        }

my @maildoms = grep { $_->{'mail'} } @doms;
if ($mods{'mailboxes'} && !$noextra && @maildoms) {
	# Can read mailboxes of users
	my %acl = ( 'noconfig' => 1,
		       'fmode' => 1,
		       'from' => join(" ", map { $_->{'dom'} } @maildoms),
		       'canattach' => 0,
		       'candetach' => 0,
		       'dir' => &mail_domain_base($d),
		       'mmode' => 5,
		       'musers' => $d->{'gid'},
		     );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "mailboxes")
		if (!$hasmods{'mailboxes'});
	push(@mods, "mailboxes");
	}
else {
	@mods = grep { $_ ne "mailboxes" } @mods;
	}

if ($mods{'logviewer'} && !$noextra && $d->{'webmin'}) {
	# Can view log files for Apache and ProFTPd
	my @extras;
	my %done;
	foreach my $sd (@doms) {
		# Add Apache logs, for domains with websites and separate logs
		if (&domain_has_website($sd) && !$sd->{'alias_mode'}) {
			my $alog = &get_website_log($sd, 0);
			my $elog = &get_website_log($sd, 1);
			push(@extras, $alog." ".&text('webmin_alog',
						      $sd->{'dom'}))
				if ($alog && !$done{$alog}++);
			push(@extras, $elog." ".&text('webmin_elog',
						      $sd->{'dom'}))
				if ($elog && !$done{$elog}++);
			}
		# Add FTP logs
		if ($sd->{'ftp'}) {
			my $flog = &get_proftpd_log($sd);
			if ($flog && !$done{$flog}++) {
				push(@extras, $flog." ".&text('webmin_flog',
							     $sd->{'dom'}))
				}
			}
		# Add PHP log
		my $phplog = &get_domain_php_error_log($d);
		if ($phplog && !$done{$phplog}++) {
			push(@extras, $phplog." ".&text('webmin_plog',
							$sd->{'dom'}));
			}
		}
	if (@extras) {
		my %acl = ( 'extras' => join("\t", @extras),
			       'any' => 0,
			       'noconfig' => 1,
			       'noedit' => 1,
			       'syslog' => 0,
			       'others' => 0 );
		&save_module_acl_logged(\%acl, $wuser->{'name'}, "logviewer")
			if (!$hasmods{'logviewer'});
		push(@mods, "logviewer");
		@mods = grep { $_ ne "syslog" } @mods;
		}
	else {
		# No logs found!
		@mods = grep { $_ ne "syslog" && $_ ne "logviewer" } @mods;
		}
	}
else {
	@mods = grep { $_ ne "syslog" && $_ ne "logviewer" } @mods;
	}

my @pconfs;
if ($mods{'phpini'} && !$noextra && $d->{'edit_phpmode'}) {
	# Can edit PHP configuration files
	foreach my $sd (grep { $_->{'web'} } @doms) {
		my $mode = &get_domain_php_mode($sd);
		if ($mode ne "mod_php" && $mode ne "fpm" && $mode ne "none") {
			# Allow access to .ini files
			foreach my $ini (&list_domain_php_inis($sd)) {
				my @st = stat($ini->[1]);
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
		elsif ($mode eq "fpm") {
			# Allow access to FPM configs for PHP overrides
			my $conf = &get_php_fpm_config($sd);
			if ($conf) {
				my $file = $conf->{'dir'}."/".
					   $sd->{'id'}.".conf";
				push(@pconfs, $file."=".
					&text('webmin_phpini', $sd->{'dom'}));
				}
			}
		}
	}
if (@pconfs) {
	my %acl = ( 'php_inis' => join("\t", @pconfs),
		       'noconfig' => 1,
		       'global' => 0,
		       'anyfile' => 0,
		       'user' => $d->{'user'},
		       'manual' => 0 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "phpini")
		if (!$hasmods{'phpini'});
	push(@mods, "phpini");
	}
else {
	@mods = grep { $_ ne "phpini" } @mods;
	}

if (!$noextras) {
	# Add any extra modules specified for this domain
	push(@mods, split(/\s+/, $d->{'webmin_modules'}));

	# Add any extra modules specified in global config
	my @wmods = split(/\s+/, $config{'webmin_modules'});
	my $m;
	foreach $m (@wmods) {
		my %acl = ( 'noconfig' => 1 );
		&save_module_acl_logged(\%acl, $wuser->{'name'}, $m)
			if (!$hasmods{$m});
		}
	push(@mods, @wmods);
	}

if (!$nofeatures) {
	# Add plugin-specified modules, except those that have been disabled
	# for domain owners in the template
	my $p;
	foreach $p (@plugins) {
		my @pmods = &plugin_call($p, "feature_webmin", $d,
					    \@doms);
		my $pm;
		foreach $pm (@pmods) {
			next if ($mods{$pm->[0]} ne '' &&
				 !$mods{$pm->[0]});
			push(@mods, $pm->[0]);
			if ($pm->[1]) {
				&save_module_acl_logged(
					$pm->[1], $wuser->{'name'}, $pm->[0]);
				}
			}
		}
	}

if ($mods{'webminlog'} && !$noextra && $d->{'webmin'}) {
	# Can view own actions, and those of extra admins. This has to be
	# done last, to have access to the list of modules.
	my @users = ( $d->{'user'} );
	if ($virtualmin_pro) {
		push(@users, map { $_->{'name'} } &list_extra_admins($d));
		}
	my %acl = ( 'users' => join(" ", @users),
		       'mods' => join(" ", @mods),
		       'notify' => 0,
		       'rollback' => 0 );
	&save_module_acl_logged(\%acl, $wuser->{'name'}, "webminlog")
		if (!$hasmods{'webminlog'});
	push(@mods, "webminlog");
	}
else {
	@mods = grep { $_ ne "webminlog" } @mods;
	}

# Finally, override in settings from template Webmin group
my @ownmods = @mods;
if ($tmpl->{'webmin_group'} ne 'none') {
	my ($group) = grep { $_->{'name'} eq $tmpl->{'webmin_group'} }
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
# Returns 1 if a Webmin user with this name already exists
sub check_webmin_clash
{
my ($d, $field) = @_; 
if (!$field || $field eq 'user') {
	&require_acl();
	return 1 if ($d->{'user'} eq 'webmin');
	return 0 if ($d->{'webmin_overwrite'});
	return 0 if (&remote_webmin() && $d->{'wasmissing'});
	foreach my $u (&acl::list_users()) {
		return 1 if ($u->{'name'} eq $d->{'user'});
		}
	}
return 0;
}

# modify_all_webmin([template-id])
# Updates the Webmin users for all domains (or just those on some template)
sub modify_all_webmin
{
my ($tid) = @_;
&$first_print($text{'check_allwebmin'});
&obtain_lock_webmin();
&push_all_print();
&set_all_null_print();
foreach my $d (&list_domains()) {
	if ($d->{'webmin'} && $config{'webmin'} &&
	    (!defined($tid) || $d->{'template'} == $tid)) {
		&modify_webmin($d, $d);
		}
	}
&pop_all_print();
&release_lock_webmin();
&$second_print($text{'setup_done'});
&register_post_action(\&restart_webmin);
}

# refresh_webmin_user(&domain, [&old-domain])
# Calls modify_webmin for a domain or the appropriate parent. This will
# update the ACL for the domain's Webmin login, create and update extra
# admins, and possibly update the reseller too.
sub refresh_webmin_user
{
my ($d, $oldd) = @_;
my $has_oldd = $oldd ? 1 : 0;
$oldd ||= $d;
my $wd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
my $oldwd = $oldd->{'parent'} ? &get_domain($oldd->{'parent'}) : $oldd;
if ($wd->{'webmin'}) {
	&modify_webmin($wd, $oldwd);
	}
if ($wd->{'reseller'} && $virtualmin_pro) {
	# Update all resellers on the domain
	foreach my $r (split(/\s+/, $wd->{'reseller'})) {
		my $rinfo = &get_reseller($r);
		if ($rinfo) {
			&modify_reseller($rinfo, $rinfo);
			}
		}
	}
if ($oldwd->{'reseller'} && $virtualmin_pro && $has_oldd) {
	# Update resellers who were previously owners of the domain
	foreach my $r (split(/\s+/, $oldwd->{'reseller'})) {
		my $rinfo = &get_reseller($r);
		if ($rinfo) {
			&modify_reseller($rinfo, $rinfo);
			}
		}
	}
}

# save_module_acl_logged(&acl, user, module)
# Save an ACL file, with locking and tight permissions
sub save_module_acl_logged
{
my ($acl, $user, $mod) = @_;
my $afile = "$config_directory/$mod/$user.acl";
&lock_file($afile);
&save_module_acl($acl, $user, $mod);
&unlock_file($afile);
&set_ownership_permissions(undef, undef, 0600, $afile);
}

# update_extra_webmin(&domain, [force-disable])
# Creates, updates or deletes Webmin users to be the extra admins for a
# virtual server.
sub update_extra_webmin
{
my ($d, $forcedis) = @_;
my @admins = &list_extra_admins($d);
my %admins = map { $_->{'name'}, $_ } @admins;
my %webmins;
my @dis = split(/,/, $d->{'disabled'});
my $dis = !defined($forcedis) ? &indexof("webmin", @dis) >= 0
			         : $forcedis;

# Get current users
&require_acl();
foreach my $u (&acl::list_users()) {
	if (&indexof($module_name, @{$u->{'modules'}}) >= 0) {
		my %acl = &get_reseller_acl($u->{'name'});
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
	my $wuser = $webmins{$admin->{'name'}};
	my $pass = $forcedis ? "*LK*" :
			&acl::encrypt_password($admin->{'pass'});
	if ($wuser) {
		# User already exists .. make sure he's an extra admin
		my %aacl = &get_module_acl($admin->{'name'}, $module_name);
		if (!$aacl{'admin'}) {
			next;
			}

		# Update password (if changed)
		my $save = 0;
		if ($pass eq "*LK*" ||
		    &acl::encrypt_password($admin->{'pass'}, $wuser->{'pass'})
		     ne $wuser->{'pass'}) {
			$wuser->{'pass'} = $pass;
			$save = 1;
			}

		# Update email
		if ($wuser->{'email'} ne $admin->{'email'}) {
			$wuser->{'email'} = $admin->{'email'};
			$save = 1;
			}

		# Make sure readonly flag is set
		if (!$wuser->{'readonly'}) {
			$wuser->{'readonly'} = $module_name;
			$save = 1;
			}

		if ($save) {
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
				       $config{'webmin_theme'},
			   'email' => $admin->{'email'},
			   'readonly' => $module_name,
			};
		&acl::create_user($wuser);
		}
	my %acl;
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
my ($d, $file, $opts, $homefmt, $increment, $asd, $allopts, $key) = @_;
my $compression = $allopts->{'dir'}->{'compression'};
my $destfile = $file.".".&compression_to_suffix_inner($compression);
&$first_print($text{'backup_webmin'});
&require_acl();

# Write out .acl files for domain owner and extra admins, if they are in 
# MySQL or LDAP, and if the .acl files don't already exist
my ($wuser) = &acl::get_user($d->{'user'});
my @nonlocal;
push(@nonlocal, $wuser) if ($wuser && $wuser->{'proto'});
foreach my $admin (&list_extra_admins($d)) {
	my ($auser) = &acl::get_user($admin->{'name'});
	push(@nonlocal, $auser) if ($auser && $auser->{'proto'});
	}
my @acltemp;
foreach my $u (@nonlocal) {
	foreach my $m ("", @{$u->{'modules'}}) {
		my %acl = &get_module_acl($u->{'name'}, $m, 0, 1);
		if (%acl) {
			my $acltemp = "$config_directory/$m/$u->{'name'}.acl";
			if (!-r $acltemp) {
				&write_file($acltemp, \%acl);
				push(@acltemp, $acltemp);
				}
			}
		}
	}

# Add .acl files for domain owner
my @files;
if (-r "$config_directory/$d->{'user'}.acl") {
	push(@files, "$d->{'user'}.acl");
	}
my @otheracls = glob("$config_directory/*/$d->{'user'}.acl");
@otheracls = grep { !/\*/ } @otheracls;
if (@otheracls) {
	push(@files, "*/$d->{'user'}.acl");
	}

# Add .acl files for extra admins
foreach my $admin (&list_extra_admins($d)) {
	push(@files, "$admin->{'name'}.acl");
	my @otheracls = glob("$config_directory/*/$admin->{'name'}.acl");
	@otheracls = grep { !/\*/ } @otheracls;
	if (@otheracls) {
		push(@files, "*/$admin->{'name'}.acl");
		}
	}

if (!@files) {
	&$second_print($text{'backup_webminnofiles'});
	return 1;
	}

# Tar them all up
my $temp = &transname();
@files = &expand_glob_to_files($config_directory, @files);
my $out = &backquote_command(&make_archive_command(
		$compression, $config_directory, $temp, @files)." 2>&1");
my $ex = $?;
if (!$ex) {
	&copy_write_as_domain_user($d, $temp, $destfile);
	}
&unlink_file($temp);
&unlink_file(@acltemp) if (@acltemp);
if ($ex) {
	&$second_print(&text('backup_webminfailed', "<pre>$out</pre>"));
	return 0;
	}

# Save the Webmin database URL
my $url = &get_webmin_database_url() || "";
&write_as_domain_user($d, sub { &uncat_file($file."_url", $url."\n") });

&$second_print($text{'setup_done'});
return 1;
}

# restore_webmin(&domain, file, &options)
# Extract all .acl files from the backup
sub restore_webmin
{
my ($d, $file, $opts, $allopts) = @_;
my $srcfile = $file;
if (!-r $srcfile) {
	($srcfile) = glob("$file.*");
	}
&$first_print($text{'restore_webmin'});
&require_acl();

# Check if users are being stored in the same remote storage, if replicating
my $url = &get_webmin_database_url();
my $burl = &read_file_contents($file."_url");
chop($burl);
if ($url && $burl && $url eq $burl && $allopts->{'repl'}) {
	$url =~ s/^\S+:\/\///g;
	&$second_print(&text('restore_webminsame', $url));
	return 1;
	}

&obtain_lock_webmin($_[0]);
my $out = &backquote_command(
	&make_unarchive_command($config_directory, $srcfile)." 2>&1");
my $rv;
if ($?) {
	&$second_print(&text('backup_webminfailed', "<pre>$out</pre>"));
	$rv = 0;
	}
else {
	&$second_print($text{'setup_done'});
	$rv = 1;

	# Re-load .acl files for domain owner and extra admins, if they are in
	# MySQL or LDAP
	my ($wuser) = &acl::get_user($d->{'user'});
	my @nonlocal;
	push(@nonlocal, $wuser) if ($wuser && $wuser->{'proto'});
	foreach my $admin (&list_extra_admins($d)) {
		my ($auser) = &acl::get_user($admin->{'name'});
		push(@nonlocal, $auser) if ($auser && $auser->{'proto'});
		}
	foreach my $u (@nonlocal) {
		foreach my $m ("", @{$u->{'modules'}}) {
			my %acl;
			my $acltemp = "$config_directory/$m/$u->{'name'}.acl";
			&read_file($acltemp, \%acl) || next;
			&unlink_file($acltemp);
			&save_module_acl(\%acl, $u->{'name'}, $m);
			}
		}
	}

&release_lock_webmin($_[0]);
return $rv;
}

# get_webmin_database_url([&domain])
# Returns the URL to the LDAP server in which Webmin users are stored
sub get_webmin_database_url
{
my ($d) = @_;
&require_acl();
&foreign_require("webmin");
my %miniserv;
&get_miniserv_config(\%miniserv);
return undef if (!$miniserv{'userdb'});
my ($proto, $user, $pass, $host, $prefix, $args) =
	&webmin::split_userdb_string($miniserv{'userdb'});
if ($d) {
	my ($wuser) = grep { $_->{'name'} eq $d->{'user'} }
			     &acl::list_users();
	if ($wuser) {
		return undef if (!$wuser->{'proto'});
		$proto = $wuser->{'proto'};
		}
	}
return $proto."://".$host."/".$prefix.($args ? "?".$args : "");
}

# remote_webmin()
# Returns true if Webmin users are stored on a remote system
sub remote_webmin
{
my ($d) = @_;
return &get_webmin_database_url($d) ? 1 : 0;
}

# links_always_webmin(&domain)
# Returns a link to the Webmin Actions Log module
sub links_always_webmin
{
my ($d) = @_;
my %miniserv;
&get_miniserv_config(\%miniserv);
return ( ) if ($miniserv{'log'} eq '0');
# If login name doesn't equal username in search, it's useless,
# this is why we will search on currently selected domain name
# in description, so it works fine for both master/reseller and
# server owner
return ( { 'mod' => 'webminlog',
	   'desc' => $text{'links_webminlog_dom'},
	   'page' => "search.cgi?uall=1&desc=".&urlize($d->{'dom'})."&search_sub_title=".&urlize(&domain_in($d)).
		     "&mall=1&tall=1&fall=1&search_title=$text{'links_webminlog_dom'}&no_return=1",
	   'cat' => 'logs',
	 } );
return ( );
}

# show_template_webmin(&tmpl)
# Outputs HTML for editing webmin-user-related template options
sub show_template_webmin
{
my ($tmpl) = @_;

# Global ACL on or off
if (!$tmpl->{'default'}) {
	my @gacl_fields = ( "gacl_umode", "gacl_uusers", "gacl_ugroups",
			       "gacl_groups", "gacl_root" );
	my $dis1 = &js_disable_inputs(\@gacl_fields, [ ]);
	my $dis2 = &js_disable_inputs([ ], \@gacl_fields);
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
my @groups = &acl::list_groups();
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
my ($tmpl) = @_;

# Save global ACL
$tmpl->{'gacl'} = $in{'gacl'};
$tmpl->{'gacl_umode'} = $in{'gacl_umode'};
$tmpl->{'gacl_uusers'} = $in{'gacl_uusers'};
$tmpl->{'gacl_ugroups'} = $in{'gacl_ugroups'};
$tmpl->{'gacl_groups'} = $in{'gacl_groups'};
$tmpl->{'gacl_root'} = $in{'gacl_root'};
$tmpl->{'extra_prefix'} = &parse_none_def("extra_prefix");
if ($in{'webmin_group'} && $in{'webmin_group'} ne "none") {
	&require_acl();
	my ($group) = grep { $_->{'name'} eq $in{'webmin_group'} }
			      &acl::list_groups();
	&indexof($module_name, @{$group->{'members'}}) < 0 ||
		&error($text{'tmpl_ewgroup'});
	}
$tmpl->{'webmin_group'} = $in{'webmin_group'};
}

# get_reseller_acl(username)
# Returns just the ACL for some Webmin user, in this module
sub get_reseller_acl
{
my ($name) = @_;
return &get_module_acl($name);
}

# add_user_module_acl(user, mod)
# Add a module to the Webmin ACL for a user
sub add_user_module_acl
{
my ($user, $mod) = @_;
my %acl;
my $f = &acl_filename();
&lock_file($f);
&read_acl(undef, \%acl);
&open_lock_tempfile(ACL, ">$f");
foreach $u (keys %acl) {
        my @mods = @{$acl{$u}};
        if ($u eq $user) {
                @mods = &unique(@mods, $mod);
                }
        &print_tempfile(ACL, "$u: ",join(' ', @mods),"\n");
        }
&close_tempfile(ACL);
&unlock_file($f);
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

