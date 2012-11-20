#!/usr/local/bin/perl
# import.cgi
# Work out what will be imported, and either tell the user or actually do it

require './virtual-server-lib.pl';
&can_import_servers() || &error($text{'import_ecannot'});
&ReadParse();

&ui_print_header(undef, $text{'import_title'}, "");

# Check for domain clash
$in{'dom'} = lc($in{'dom'});
@doms = &list_domains();
($clash) = grep { $_->{'dom'} eq $in{'dom'} } @doms;
$clash && &error_exit($text{'import_eexists'});

# Get the parent
if (!$in{'parent_def'}) {
	$parent = &get_domain_by("user", $in{'parent'}, "parent", "");
	}

# Validate username and group name
if (!$parent) {
	$in{'user_def'} || $in{'user'} =~ /^[^\t :]+$/ ||
		&error_exit($text{'setup_euser2'});
	$in{'group_def'} || $in{'group'} =~ /^[^\t :]+$/ ||
		&error_exit($text{'import_egroup'});
	$in{'user_def'} || &indexof($in{'user'}, @banned_usernames) < 0 ||
		&error(&text('setup_eroot', join(" ", @banned_usernames)));
	$in{'group_def'} || &indexof($in{'group'}, @banned_usernames) < 0 ||
		&error(&text('setup_eroot2', join(" ", @banned_usernames)));
	}

# Make sure IP is valid
if ($in{'virt'}) {
	&foreign_require("net", "net-lib.pl");
	($iface) = grep { $_->{'address'} eq $in{'ip'} }
				( &net::boot_interfaces(),
				  &net::active_interfaces() );
	$iface || &error_exit($text{'import_enoip'});
	$iface->{'address'} eq &get_default_ip() &&
		&error_exit($text{'import_eipsame'});
	foreach $d (@doms) {
		$d->{'ip'} eq $in{'ip'} &&
			&error_exit(&text('import_eipclash', $d->{'dom'}));
		}
	$iface->{'virtual'} eq '' &&
		&error_exit(&text('import_ereal', $iface->{'fullname'}));
	}

# Validate home directory
if (!$in{'home_def'}) {
	-d $in{'home'} && $in{'home'} =~ /^\/\S/ ||
		&error($text{'import_ehome'});
	}

# Validate prefix
if (!$in{'prefix_def'}) {
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
		&error($text{'setup_eprefix'});
	($in{'prefix'} =~ /^[\.\-]/ || $in{'prefix'} =~ /[\.\-]$/) &&
		&error($text{'setup_eprefix4'});
	$prefix = $in{'prefix'};
	}
else {
	$prefix = &compute_prefix($in{'dom'}, $in{'crgroup'} || $in{'group'},
				  $parent, 1);
	}

# Validate regexp
if (!$in{'regexp_def'}) {
	$in{'regexp'} =~ /\S/ || &error($text{'import_eregexp'});
	}

if ($in{'confirm'}) {
	# Go ahead and do it
	&lock_domain_name($in{'dom'});
	&obtain_lock_unix();
	print "$text{'import_doing'}<p>\n";
	&require_useradmin();

	if (!$parent) {
		# Get existing group and user details
		$crgroup = $in{'crgroup'} || $in{'group'};
		@groups = &foreign_call($usermodule, "list_groups");
		($ginfo) = grep { $_->{'group'} eq $crgroup } @groups;
		&build_group_taken(\%gtaken, \%ggtaken);
		$gid = $ginfo ? $ginfo->{'gid'} : &allocate_gid(\%gtaken);

		$cruser = $in{'cruser'} || $in{'user'};
		@users = &foreign_call($usermodule, "list_users");
		($uinfo) = grep { $_->{'user'} eq $cruser } @users;
		&build_taken(\%taken, \%utaken);
		$uid = $uinfo ? $uinfo->{'uid'} : &allocate_uid(\%taken);
		$ugid = $uinfo ? $uinfo->{'gid'} : $gid;
		$ugroup = $uinfo ? getgrgid($uinfo->{'gid'}) : $crgroup;
		$owner = $uinfo ? $uinfo->{'real'} : "Imported domain $in{'dom'}";
		$plan = &get_plan($in{'plan'});
		}
	else {
		# All details come from parent
		$cruser = $parent->{'user'};
		$crgroup = $parent->{'group'};
		$uid = $parent->{'uid'};
		$gid = $parent->{'gid'};
		$ugid = $parent->{'ugid'};
		$ugroup = $parent->{'ugroup'};
		$owner = "Imported domain $in{'dom'}";
		$plan = &get_plan($parent->{'plan'});
		}

	# Create domain details
	%found = map { $_, 1 } split(/\0/, $in{'found'});
	@dbs = ( split(/\s+/, $in{'db_mysql'}),
		 split(/\s+/, $in{'db_postgres'}) );
	%dom = ( 'id', &domain_id(),
		 'dom', $in{'dom'},
		 'unix', $parent ? 0 : 1,
		 'dir', 1,
		 'user', $cruser,
		 'group', $crgroup,
		 'ugroup', $ugroup,
		 'uid', $uid,
		 'gid', $gid,
		 'ugid', $ugid,
		 'prefix', $prefix,
		 'owner', $owner,
		 'mail', int($found{'mail'}),
		 'web', int($found{'web'}),
		 'web_port', $found{'web'} ? $default_web_port : undef,
		 'ssl', int($found{'ssl'}),
		 'web_sslport', $found{'ssl'} ? $default_web_sslport : undef,
		 'ftp', int($found{'ftp'}),
		 'webalizer', int($found{'webalizer'}),
		 'mysql', int($found{'mysql'}),
		 'postgres', int($found{'postgres'}),
		 'logrotate', int($found{'logrotate'}),
		 'webmin', $parent ? 0 : $in{'webmin'},
		 'name', !$in{'virt'},
		 'ip', $in{'ip'},
		 'iface', $in{'virt'} ? $iface->{'fullname'} : "",
		 'virt', $in{'virt'},
		 'dns', int($found{'dns'}),
		 'pass', $parent ? $parent->{'pass'} : $in{'pass'},
		 'db', $dbs[0],
		 'db_mysql', $in{'found_mysql'},
		 'db_postgres', $in{'found_postgres'},
		 'source', 'import.cgi',
		 'parent', $parent ? $parent->{'id'} : undef,
		 'template', 0,
		 'plan', $plan->{'id'},
		 'reseller', undef,
		);
	foreach $f (&list_feature_plugins()) {
		$dom{$f} = int($found{$f});
		}
	if (!$parent) {
		&set_limits_from_plan(\%dom, $plan);
		&set_capabilities_from_plan(\%dom, $plan);
		&set_featurelimits_from_plan(\%dom, $plan);
		}
	&generate_domain_password_hashes(\%dom, 1);
	$dom{'emailto'} = $dom{'email'} ||
			  $dom{'user'}.'@'.&get_system_hostname();

	# Work out home directory
	$dom{'home'} = !$in{'home_def'} ? $in{'home'} :
		       $uinfo ? $uinfo->{'home'}
			      : &server_home_directory(\%dom, $parent);

	if (!$parent) {
		if (!$ginfo) {
			# Create the unix group
			print &text('setup_group', $crgroup),"<br>\n";
			%ginfo = ( 'group', $crgroup,
				   'gid', $gid );
			&foreign_call($usermodule, "set_group_envs", \%ginfo, 'CREATE_GROUP');
			&foreign_call($usermodule, "making_changes");
			&foreign_call($usermodule, "create_group", \%ginfo);
			&foreign_call($usermodule, "made_changes");
			print $text{'setup_done'},"<p>\n";
			}
		else {
			%ginfo = %$ginfo;
			}

		if (!$uinfo) {
			# Create the Unix user
			# XXX use common function??
			print &text('setup_user', $cruser),"<br>\n";
			%uinfo = ( 'user', $cruser,
				   'uid', $uid,
				   'gid', $gid,
				   'pass', $dom->{'enc_pass'} ||
					&foreign_call($usermodule,
						"encrypt_password", $in{'pass'}),
				   'real', $owner,
				   'home', $dom{'home'},
				   'shell', &default_available_shell('owner'),
				   'mailbox', $cruser,
				   'dom', $in{'dom'},
				 );
			&set_pass_change(\%uinfo);
			&foreign_call($usermodule, "set_user_envs", \%uinfo, 'CREATE_USER', $in{'pass'}, [ ]);
			&foreign_call($usermodule, "making_changes");
			&foreign_call($usermodule, "create_user", \%uinfo);
			&foreign_call($usermodule, "made_changes");
			print $text{'setup_done'},"<p>\n";

			if (!-d $uinfo{'home'}) {
				# Create his home directory, and copy files into it
				print $text{'setup_home'},"<br>\n";
				&system_logged(
				  "mkdir '$uinfo{'home'}'");
				&system_logged(
				  "chmod '$uconfig{'homedir_perms'}' '$uinfo{'home'}'");
				&system_logged("chown $uid:$gid '$uinfo{'home'}'");
				&copy_skel_files($config{'virtual_skel'},
						 \%uinfo, $uinfo{'home'});
				print $text{'setup_done'},"<p>\n";
				}
			}
		else {
			%uinfo = %$uinfo;
			}
		}

	# Setup web directories
	print $text{'import_dirs'},"<br>\n";
	foreach $d (&virtual_server_directories(\%dom)) {
		if (!-d "$uinfo{'home'}/$d->[0]") {
			&system_logged(
				"mkdir '$uinfo{'home'}/$d->[0]' 2>/dev/null");
			&system_logged(
				"chmod $d->[1] '$uinfo{'home'}/$d->[0]'");
			&system_logged(
				"chown $uid:$ugid '$uinfo{'home'}/$d->[0]'");
			}
		}
	print $text{'setup_done'},"<p>\n";

	if ($found{'ssl'}) {
		# Find and record the SSL key files
		&require_apache();
		($svirt, $svconf) = &get_apache_virtual($in{'dom'},
					$default_web_sslport);
		$certfile = &apache::find_directive("SSLCertificateFile",
						    $svconf);
		$keyfile = &apache::find_directive("SSLCertificateKeyFile",
						    $svconf);
		$dom{'ssl_cert'} = $certfile;
		$dom{'ssl_key'} = $keyfile if ($keyfile);
		$dom{'web_sslport'} = $default_web_sslport;
		}

	# Find users matching regexp, and import them
	if (!$in{'regexp_def'}) {
		print &text('import_updating', "<tt>$in{'regexp'}</tt>"),
		      "<br>\n";
		$re = $in{'regexp'};
		foreach $u (&list_all_users()) {
			next if ($u->{'user'} !~ /^$re$/);

			# If this user matches, change his primary group
			$oldu = { %$u };
			$u->{'gid'} = $dom{'gid'};
			&foreign_call($usermodule, "making_changes");
			&foreign_call($usermodule, "modify_user", $oldu, $u);
			&foreign_call($usermodule, "made_changes");

			# Also fix group permissions on his home and mail file
			&useradmin::recursive_change($u->{'home'},
				$u->{'uid'}, $oldu->{'gid'},
				$u->{'uid'}, $u->{'gid'});
			&useradmin::recursive_change(&user_mail_file($u),
				$u->{'uid'}, $oldu->{'gid'},
				$u->{'uid'}, $u->{'gid'});
			}
		print $text{'setup_done'},"<p>\n";
		}

	# Find any slave DNS servers with the domain
	if ($dom{'dns'}) {
		&require_bind();
		@slavehosts = ( );
		foreach my $s (&bind8::list_slave_servers()) {
			if (&exists_on_slave($dom{'dom'}, $s)) {
				push(@slavehosts, $s->{'nsname'} ||
						  $s->{'host'});
				}
			}
		if (@slavehosts) {
			$dom{'dns_slave'} = join(" ", @slavehosts);
			}
		}

	# Create the domain details
	&complete_domain(\%dom);
	&find_html_cgi_dirs(\%dom);
	print $text{'setup_save'},"<br>\n";
	&save_domain(\%dom, 1);
	print $text{'setup_done'},"<p>\n";

	# Create or update webmin user
	if ($in{'webmin'} && !$parent) {
		&require_acl();
		($wuser) = grep { $_->{'name'} eq $cruser } &acl::list_users();
		if ($wuser) {
			&modify_webmin(\%dom, \%dom);
			}
		else {
			&setup_webmin(\%dom);
			}
		}
	elsif ($parent) {
		# Update parent domain's webmin user
		&modify_webmin($parent, $parent);
		}
	&run_post_actions();

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain(\%dom, 'create');
		}

	# Add to this user's list of domains if needed
	if (!&can_edit_domain(\%dom)) {
		$access{'domains'} = join(" ", split(/\s+/, $access{'domains'}),
					       $dom{'id'});
		&save_module_acl(\%access);
		}
	&release_lock_unix();
	&webmin_log("import", "domain", $dom{'dom'});
	}
else {
	# Just work out what can be done
	print "$text{'import_idesc'}<p>\n";

	# Work out the Unix username
	if (!$parent) {
		if ($in{'user_def'}) {
			# Creating a new user with a name taken from the domain
			$in{'dom'} =~ /^([^\.]+)/;
			$try1 = $user = $1;
			if (defined(getpwnam($1)) || $config{'longname'}) {
				$user = $in{'dom'};
				$try2 = $user;
				if (defined(getpwnam($user))) {
					&error_exit(&text('setup_eauto', $try1,$try2));
					}
				}
			print "<b>",&text('import_user1',
					  "<tt>$user</tt>"),"</b><p>\n";
			}
		else {
			# Using a specified name, which may or may not exist
			if (defined(getpwnam($in{'user'}))) {
				print "<b>",&text('import_user2',
						  "<tt>$in{'user'}</tt>"),"</b><p>\n";
				}
			else {
				print "<b>",&text('import_user3',
						  "<tt>$in{'user'}</tt>"),"</b><p>\n";
				}
			}

		if ($in{'group_def'}) {
			# Need to create new group with the same name as user
			$group = $user || $in{'user'};
			print "<b>",&text('import_group1',
					  "<tt>$group</tt>"),"</b><p>\n";
			}
		elsif (scalar(@ginfo = getgrnam($in{'group'}))) {
			# Group already exists
			print "<b>",&text('import_group2',
				  "<tt>$in{'group'}</tt>"),"</b><p>\n";
			$group = $in{'group'};
			}
		else {
			# Group does not exist
			print "<b>",&text('import_group3',
				  "<tt>$in{'group'}</tt>"),"</b><p>\n";
			}

		if (@ginfo) {
			# Find users in the group
			setpwent();
			while(@muinfo = getpwent()) {
				$mcount++ if ($muinfo[3] == $ginfo[2]);
				}
			endpwent();
			if ($mcount) {
				print "<b>",&text('import_mailboxes',
				    $mcount, "<tt>$in{'group'}</tt>"),
				    "</b><p>\n";
				}
			}
		if (!$in{'regexp_def'}) {
			# Find users who match regexp
			$re = $in{'regexp'};
			setpwent();
			while(@muinfo = getpwent()) {
				$rcount++ if ($muinfo[0] =~ /^$re$/);
				}
			endpwent();
			if ($rcount) {
				print "<b>",&text('import_mailboxes2',
				    $rcount, "<tt>$in{'regexp'}</tt>"),
				    "</b><p>\n";
				}
			}
		}
	else {
		print "<b>",&text('import_under',
				  "<tt>$parent->{'dom'}</tt>"),"</b><p>\n";
		}

	# Check for mail domain
	if ($config{'mail'}) {
		&require_mail();
		$found{'mail'}++ if (&is_local_domain($in{'dom'}));
		if ($found{'mail'}) {
			print "<b>",&text('import_mail',
				"<tt>$in{'dom'}</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_nomail',
				"<tt>$in{'dom'}</tt>"),"<p>\n";
			}
		}

	# Check for an Apache virtualhost
	if ($config{'web'}) {
		&require_apache();
		($virt, $vconf) = &get_apache_virtual($in{'dom'},
						      $default_web_port);
		if ($virt) {
			$found{'web'}++;
			$sn = &apache::find_directive(
				"ServerName", $virt->{'members'});
			$dr = &apache::find_directive(
				"DocumentRoot", $virt->{'members'});
			print "<b>",&text('import_web',
				"<tt>$sn</tt>", "<tt>$dr</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_noweb',
				"<tt>$in{'dom'}</tt>"),"<p>\n";
			}
		}

	# Check for an SSL virtualhost
	if ($config{'ssl'}) {
		&require_apache();
		($svirt, $svconf) = &get_apache_virtual($in{'dom'},
					$default_web_sslport);
		if ($svirt) {
			$found{'ssl'}++;
			$sn = &apache::find_directive(
				"ServerName", $svirt->{'members'});
			$dr = &apache::find_directive(
				"DocumentRoot", $svirt->{'members'});
			print "<b>",&text('import_ssl',
				"<tt>$sn</tt>", "<tt>$dr</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_nossl',
				"<tt>$in{'dom'}</tt>"),"<p>\n";
			}
		}

	# Check for Webalizer on the virtual host logs
	if ($config{'webalizer'}) {
		&require_webalizer();
		$log = &get_apache_log($in{'dom'});
		if ($log && -r &webalizer::config_file_name($log)) {
			$found{'webalizer'}++;
			print "<b>",&text('import_webalizer',
				    "<tt>$log</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_nowebalizer',
				    "<tt>$log</tt>"),"<p>\n";
			}
		}

	# Check for a DNS domain
	if ($config{'dns'}) {
		&require_bind();
		$conf = &bind8::get_config();
		@zones = &bind8::find("zone", $conf);
		foreach $v (&bind8::find("view", $conf)) {
			push(@zones, &bind8::find("zone", $v->{'members'}));
			}
		foreach $z (@zones) {
			if ($z->{'value'} eq $in{'dom'}) {
				$found{'dns'}++;
				last;
				}
			}
		if ($found{'dns'}) {
			print "<b>",&text('import_dns',
				"<tt>$in{'dom'}</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_nodns',
				"<tt>$in{'dom'}</tt>"),"<p>\n";
			}
		}

	# Check for databases
	@alldbs = &all_databases();
	foreach $t ('mysql', 'postgres') {
		foreach $db (split(/\s+/, $in{'db_'.$t})) {
			local ($got) = grep { $_->{'type'} eq $t &&
					      $_->{'name'} eq $db } @alldbs;
			if ($got) {
				$found{$t}++;
				print "<b>",&text('import_'.$t,
					"<tt>$db</tt>"),"</b><p>\n";
				}
			else {
				print &text('import_no'.$t,
					"<tt>$db</tt>"),"<p>\n";
				}
			push(@{$dbnames{$t}}, $db);
			}
		}

	# Check for a ProFTPd virtualhost
	if ($config{'ftp'} && $in{'virt'}) {
		&require_proftpd();
		($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($in{'ip'});
		if ($virt && $anon) {
			$found{'ftp'}++;
			print "<b>",&text('import_ftp',
				"<tt>$in{'ip'}</tt>",
				"<tt>$anon->{'value'}</tt>"),"</b><p>\n";
			}
		elsif ($virt) {
			$found{'ftp'}++;
			print "<b>",&text('import_ftpnoanon',
				"<tt>$in{'ip'}</tt>"),"</b><p>\n";
			}
		else {
			print &text('import_noftp',
				"<tt>$in{'ip'}</tt>"),"<p>\n";
			}
		}

	# Check for an existing logrotate configuration
	if ($config{'logrotate'}) {
		$log = &get_apache_log($in{'dom'});
		$lconf = &get_logrotate_section($log);
		if ($log && $lconf) {
			$found{'logrotate'}++;
			print "<b>",&text('import_logrotate',
				    "<tt>$log</tt>"),"</b><p>\n";
			}
		elsif ($log) {
			print &text('import_nologrotate',
				    "<tt>$log</tt>"),"<p>\n";
			}
		else {
			print &text('import_nologrotate2',
				    "<tt>$in{'dom'}</tt>"),"<p>\n";
			}
		}

	# Check for plugin features
	foreach $f (&list_feature_plugins()) {
		$pname = &plugin_call($f, "feature_name");
		if (&plugin_call($f, "feature_import", $in{'dom'},
				 $user || $in{'user'},
				 $in{'db'})) {
			$found{$f}++;
			print "<b>",&text('import_plugin', $pname),"</b><p>\n";
			}
		else {
			print &text('import_noplugin', $pname),"<p>\n";
			}
		}

	if (!$parent) {
		# Tell if a Webmin user will be created
		if ($in{'webmin'}) {
			&require_acl();
			($wuser) = grep { $_->{'name'} eq ($user || $in{'user'}) }
					&acl::list_users();
			if ($wuser) {
				print "<b>",&text('import_webmin1',
					  "<tt>$wuser->{'name'}</tt>"),"</b><p>\n";
				}
			else {
				print "<b>",&text('import_webmin2',
					  "<tt>$wuser->{'name'}</tt>"),"</b><p>\n";
				}
			}
		else {
			print "$text{'import_nowebmin'}<p>\n";
			}
		}

	# Work out if IP would be assigned
	if ($in{'virt'}) {
		print "<b>",&text('import_virt',
				  "<tt>$iface->{'fullname'}</tt>"),"</b><p>\n";
		}
	else {
		print "$text{'import_novirt'}<p>\n";
		}

	# Output form with confirm button
	print &check_clicks_function();
	print "<center><form action=import.cgi method=post>\n";
	foreach $i (keys %in) {
		print "<input type=hidden name=$i value='",
			&html_escape($in{$i}),"'>\n";
		}
	foreach $f (keys %found) {
		print "<input type=hidden name=found value='$f'>\n";
		}
	foreach $t (keys %dbnames) {
		print "<input type=hidden name=found_$t value='",
		      join(" ", @{$dbnames{$t}}),"'>\n";
		}
	print "<input type=hidden name=cruser value='$user'>\n";
	print "<input type=hidden name=crgroup value='$group'>\n";
	print "<b>$text{'import_rusure'}</b><p>\n";
	print "<input type=submit name=confirm value='$text{'import_ok'}' ",
	      "onClick='check_clicks(form)'>\n";
	print "</form></center>\n";
	}

&ui_print_footer("", $text{'index_return'});

sub error_exit
{
print "<b>",$text{'import_err'}," : ",@_,"</b><p>\n";
&ui_print_footer("", $text{'index_return'});
exit;
}

