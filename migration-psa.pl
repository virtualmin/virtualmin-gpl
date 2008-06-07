# Functions for migrating a plesk 7 backup. These appear to be in MIME format,
# with each part (home dir, settings, etc) in a separate 'attachment'

# migration_psa_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is a Plesk backup, and contains the domain
sub migration_psa_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_plesk_dir($file, 7);
$ok || return ("Not a Plesk 8 backup file : $root");
local $xfile = "$root/dump.xml";
-r $xfile || return ("Not a complete Plesk 7 backup file - missing XML data");

# Check if the domain is in there
local $dump = &read_plesk_xml($xfile);
ref($dump) || return ($dump);
if (!$dom) {
	# Work out domain name
	$dom = $dump->{'sites'}->{'domain'}->{'name'};
	$dom || return ("Could not work out domain name from backup");
	}
local $domain = $dump->{'sites'}->{'domain'}->{$dom};
if (!$domain && $dump->{'sites'}->{'domain'}->{'name'} eq $dom) {
	$domain = $dump->{'sites'}->{'domain'};
	}
$domain || return ("Backup does not contain the domain $dom");

local $uinfo = ref($domain->{'user'}) eq 'ARRAY' ?
		$domain->{'user'}->[0] : $domain->{'user'};
if (!$parent && !$user) {
	# Check if we can work out the user
	local $user = $uinfo->{'login'}->{'name'};
	$user ||
	    return ("Could not work out original username from backup");
	}

if (!$parent && !$pass) {
	# Check if we can work out the password
	if ($uinfo->{'login'}->{'PW_TYPE'} eq 'plain') {
		$pass = $uinfo->{'login'}->{'password'};
		}
	$pass ||
	    return ("Could not work out original password from backup");
	}

return (undef, $dom, $user, $pass);
}

# migration_psa_migrate(file, domain, username, create-webmin, template-id,
#			   ip-address, virtmode, pass, [&parent], [prefix],
#			   virt-already, [email])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_psa_migrate
{
local ($file, $dom, $user, $webmin, $template, $ip, $virt, $pass, $parent,
       $prefix, $virtalready, $email) = @_;

# Check for prefix clash
$prefix ||= &compute_prefix($dom, undef, $parent, 1);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && &error("A virtual server using the prefix $prefix already exists");

# Get shells for users
local ($nologin_shell, $ftp_shell, undef, $def_shell) =
	&get_common_available_shells();
$nologin_shell ||= $def_shell;
$ftp_shell ||= $def_shell;

# Extract backup and read the dump file
local ($ok, $root) = &extract_plesk_dir($file, 7);
local $xfile = "$root/dump.xml";
local $dump = &read_plesk_xml($xfile);

# Get domain object
local $domain = $dump->{'sites'}->{'domain'}->{$dom};
if (!$domain && $dump->{'sites'}->{'domain'}->{'name'} eq $dom) {
	$domain = $dump->{'sites'}->{'domain'};
	}

# Work out user and group
local $uinfo = ref($domain->{'user'}) eq 'ARRAY' ?
		$domain->{'user'}->[0] : $domain->{'user'};
if (!$user) {
	$user = $uinfo->{'login'}->{'name'};
	}
local $group = $user;
local $ugroup = $group;

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix"), "web" );
push(@got, "webmin") if ($webmin && !$parent);
push(@got, "mail");	# Assume that all domains have mail
if ($domain->{'dns'}) {
	push(@got, "dns");
	}
push(@got, "web");	# Assume has website
if ($uinfo->{'services'}->{'ssl'} eq 'true') {
	push(@got, "ssl");
	}
if ($uinfo->{'services'}->{'webstat'} eq 'true') {
	push(@got, "webalizer");
	}
if (&indexof("web", @got) >= 0) {
	push(@got, "logrotate");
	}

# Check for MySQL databases
local $databases = $domain->{'data_bases'};
if (!$databases) {
	$databases = { };
	}
elsif ($databases->{'name'}) {
	# Just one DB
	$databases = { $databases->{'name'} => $databases };
	}
local @mysqldbs = grep { $databases->{$_}->{'type'} eq 'mysql' }
		       (keys %$databases);
if (@mysqldbs) {
	push(@got, "mysql");
	}

# Check for mail users
local @mailusers;
local ($has_spam, $has_virus);
foreach my $u (@{$domain->{'user'}}) {
	if ($u->{'spamassassin'}) {
		$has_spam = 1;
		}
	if ($u ne $uinfo) {
		push(@mailusers, $u);
		}
	}
push(@got, "spam") if ($has_spam);
push(@got, "virus") if ($has_virus);

# Tell the user what we have got
@got = &show_check_migration_features(@got);
local %got = map { $_, 1 } @got;

# Work out user and group IDs
local ($gid, $ugid, $uid, $duser);
if ($parent) {
	# UID and GID come from parent
	$gid = $parent->{'gid'};
	$ugid = $parent->{'ugid'};
	$uid = $parent->{'uid'};
	$duser = $parent->{'user'};
	$group = $parent->{'group'};
	$ugroup = $parent->{'ugroup'};
	}
else {
	# IDs are allocated in setup_unix
	$gid = $ugid = $uid = undef;
	$duser = $user;
	}

# Get the quota and domain password (if not supplied)
local $bsize = &has_home_quotas() ? &quota_bsize("home") : undef;
local $quota;
if (!$parent && &has_home_quotas()) {
	$quota = $domain->{'limits'}->{'mbox_quota'} / $bsize;
	}

# Create the virtual server object
local %dom;
$prefix ||= &compute_prefix($dom, $group, $parent, 1);
%dom = ( 'id', &domain_id(),
	 'dom', $dom,
         'user', $duser,
         'group', $group,
         'ugroup', $ugroup,
         'uid', $uid,
         'gid', $gid,
         'ugid', $ugid,
         'owner', "Migrated Plesk server $dom",
         'email', $email ? $email : $parent ? $parent->{'email'} : undef,
         'name', !$virt,
         'ip', $ip,
	 'dns_ip', $virt || $config{'all_namevirtual'} ? undef :
		$config{'dns_ip'},
         'virt', $virt,
         'virtalready', $virtalready,
	 $parent ? ( 'pass', $parent->{'pass'} )
		 : ( 'pass', $pass ),
	 'source', 'migrate.cgi',
	 'template', $template,
	 'parent', undef,
	 'prefix', $prefix,
	 'no_tmpl_aliases', 1,
	 'no_mysql_db', $got{'mysql'} ? 1 : 0,
	 'nocreationmail', 1,
	 'nocopyskel', 1,
	 'parent', $parent ? $parent->{'id'} : undef,
        );
if (!$parent) {
	&set_limits_from_template(\%dom, $tmpl);
	$dom{'quota'} = $quota;
	$dom{'uquota'} = $quota;
	&set_capabilities_from_template(\%dom, $tmpl);
	}
$dom{'db'} = $db || &database_name(\%dom);
$dom{'emailto'} = $dom{'email'} ||
		  $dom{'user'}.'@'.&get_system_hostname();
foreach my $f (@features, @feature_plugins) {
	$dom{$f} = $got{$f} ? 1 : 0;
	}
&set_featurelimits_from_template(\%dom, $tmpl);
$dom{'home'} = &server_home_directory(\%dom, $parent);
$dom{'public_html_dir'} = 'httpdocs';			# Plesk 7 style
$dom{'public_html_path'} = $dom{'home'}.'/httpdocs';
$dom{'cgi_bin_dir'} = 'cgi-bin';
$dom{'cgi_bin_path'} = $dom{'home'}.'/cgi-bin';
&complete_domain(\%dom);

# Check for various clashes
&$first_print("Checking for clashes and dependencies ..");
$derr = &virtual_server_depends(\%dom);
if ($derr) {
	&$second_print($derr);
	return ( );
	}
$cerr = &virtual_server_clashes(\%dom);
if ($cerr) {
	&$second_print($cerr);
	return ( );
	}
&$second_print(".. all OK");

# Create the initial server
&$first_print("Creating initial virtual server ..");
&$indent_print();
local $err = &create_virtual_server(\%dom, $parent,
				    $parent ? $parent->{'user'} : undef);
&$outdent_print();
if ($err) {
	&$second_print($err);
	return ( );
	}
else {
	&$second_print(".. done");
	}

# Copy web files, which are the main's users home 
&$first_print("Copying home directory ..");
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 1);
	}
local $htsrc = $root."/".&remove_cid_prefix($uinfo->{'src'});
if (!$uinfo->{'src'}) {
	&$second_print(".. not defined in XML");
	}
elsif (!-r $htsrc) {
	&$second_print(".. not found in backup");
	}
else {
	local $err = &extract_compressed_file($htsrc, $dom{'home'});
	if ($err) {
		&$second_print(".. failed : $err");
		}
	else {
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 0);
	}

# Migrate SSL certs
local $certificate =$domain->{'server'}->{'certificates_list'}->{'certificate'};
if ($certificate && $certificate->{'pub_key'}->{'src'} &&
		    $certificate->{'pvt_key'}->{'src'}) {
	&$first_print("Migrating SSL certificate and key ..");
	local $certfile = $root."/".&remove_cid_prefix(
					$certificate->{'pub_key'}->{'src'});
	local $cert = &cleanup_plesk_cert(&read_file_contents($certfile));
	if ($cert) {
		$dom{'ssl_cert'} ||= &default_certificate_file(\%dom, 'cert');
		&open_tempfile(CERT, ">$dom{'ssl_cert'}");
		&print_tempfile(CERT, $cert);
		&close_tempfile(CERT);
		}
	local $keyfile = $root."/".&remove_cid_prefix(
					$certificate->{'pvt_key'}->{'src'});
	local $key = &cleanup_plesk_cert(&read_file_contents($keyfile));
	if ($key) {
		$dom{'ssl_key'} ||= &default_certificate_file(\%dom, 'key');
		&open_tempfile(CERT, ">$dom{'ssl_key'}");
		&print_tempfile(CERT, $key);
		&close_tempfile(CERT);
		}
	&$second_print($cert && $key ? ".. done" :
		       !$cert && $key ? ".. missing certificate" :
		       $cert && !$key ? ".. missing key" :
					".. not found in backup");
	}

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

# Re-create mail users and copy mail files
&$first_print("Re-creating mail users ..");
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mcount = 0;
foreach my $mailuser (@mailusers) {
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name($mailuser->{'login'}->{'name'}, \%dom);
	if ($mailuser->{'login'}->{'PW_TYPE'} eq 'plain') {
		$uinfo->{'plainpass'} = $mailuser->{'login'}->{'password'};
		$uinfo->{'pass'} = &encrypt_user_password(
					$uinfo, $uinfo->{'plainpass'});
		}
	else {
		$uinfo->{'pass'} = $mailuser->{'login'}->{'password'};
		}
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$name";
	$uinfo->{'shell'} = $nologin_shell->{'shell'};
	$uinfo->{'to'} = [ ];
	if ($mailuser->{'mailbox'}->{'enabled'} eq 'true') {
		# Add delivery to user's mailbox
		# XXX
		local $escuser = $uinfo->{'user'};
		if ($config{'mail_system'} == 0 && $escuser =~ /\@/) {
			$escuser = &replace_atsign($escuser);
			}
		else {
			$escuser = &escape_user($escuser);
			}
		push(@{$uinfo->{'to'}}, "\\".$escuser);
		}
	if (&has_home_quotas()) {
		local $q = $mailuser->{'login'}->{'quota'};
		$uinfo->{'qquota'} = $q;
		$uinfo->{'quota'} = $q / &quota_bsize("home");
		$uinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	# Add mail aliases
	# XXX
	local $alias = $mailuser->{'alias'};
	if ($alias) {
		$alias = [ $alias ] if (ref($alias) ne 'ARRAY');
		foreach my $a (@$alias) {
			$a = $a->{'content'} if (ref($a));
			$a .= "@".$dom{'dom'} if ($a !~ /\@/);
			push(@{$uinfo->{'extraemail'}}, $a);
			}
		}
	# Add forwarding
	# XXX
	local $redirect = $mailuser->{'redirect'};
	if ($redirect) {
		$redirect = [ $redirect ] if (ref($redirect) ne 'ARRAY');
		foreach my $r (@$redirect) {
			$r = $r->{'content'} if (ref($r));
			$r .= "@".$dom{'dom'} if ($r !~ /\@/);
			push(@{$uinfo->{'to'}}, $r);
			}
		}
	# Add mail group members (which are really just forwards)
	# XXX
	local $mailgroup = $mailuser->{'mailgroup-member'};
	if ($mailgroup) {
		$mailgroup = [ $mailgroup ] if (ref($mailgroup) ne 'ARRAY');
		foreach my $r (@$mailgroup) {
			$r = $r->{'content'} if (ref($r));
			$r .= "@".$dom{'dom'} if ($r !~ /\@/);
			push(@{$uinfo->{'to'}}, $r);
			}
		}
	if (@{$uinfo->{'to'}}) {
		# Only enable mail if there is at least one destination, which
		# would be his own mailbox or offsite
		$uinfo->{'email'} = $name."\@".$dom;
		}
	&create_user($uinfo, \%dom);
	&create_user_home($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo);

	# Copy mail into user's inbox
	# XXX dir with Maildir sub-directory
	local $mfile = $mailuser->{'mailbox'}->{'cid'};
	local $mpath = "$root/$mfile";
	if ($mfile && -r $mpath) {
		local $fmt = &compression_format($mpath);
		if ($fmt) {
			# Extract the maildir first
			local $temp = &transname();
			&make_dir($temp, 0700);
			&extract_compressed_file($mpath, $temp);
			$mpath = $temp;
			}
		local $srcfolder = {
		  'file' => $mpath,
		  'type' => $mailuser->{'mailbox'}->{'type'} eq 'mdir' ? 1 : 0,
		  };
		local $dstfolder = { 'file' => $crfile, 'type' => $crtype };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
		&set_mailfolder_owner($dstfolder, $uinfo);
		}

	$mcount++;
	}
&$second_print(".. done (migrated $mcount users)");

# Re-create MySQL databases
if ($got{'mysql'}) {
	&require_mysql();
	local $mcount = 0;
	local $myucount = 0;
	&$first_print("Migrating MySQL databases ..");
	foreach my $name (keys %$databases) {
		local $database = $databases->{$name};
		next if ($database->{'type'} ne 'mysql');

		# Create and import the DB
		&$indent_print();
		&create_mysql_database(\%dom, $name);
		&save_domain(\%dom, 1);
		local $mysrc = $root.'/'.&remove_cid_prefix($database->{'src'});
		if (!$database->{'src'} || !-r $mysrc) {
			&$first_print("Data source for $name not found");
			}
		local $myplain = &transname();
		if (&compression_format($mysrc) == 0) {
			# Plain SQL
			$myplain = $mysrc;
			}
		elsif (&compression_format($mysrc) == 1) {
			local $err = &backquote_command(
				"gunzip -c ".quotemeta($mysrc).
				" 2>&1 >".quotemeta($myplain));
			if ($?) {
				&$first_print("Error un-compressing source for $name : $err");
				}
			}
		else {
			&$first_print("Unknown compression format for $name");
			}
		local ($ex, $out) = &mysql::execute_sql_file($name, $myplain);
		if ($ex) {
			&$first_print("Error loading $name : $out");
			}

		# Create any DB users as domain users
		local $dbusers = $database->{'user'};
		if (!$dbusers) {
			$dbusers = [ ];
			}
		elsif (ref($dbusers) ne 'ARRAY') {
			$dbusers = [ $dbusers ];
			}
		foreach my $dbuser (@$dbusers) {
			local $myuinfo = &create_initial_user(\%dom);
			$myuinfo->{'user'} = $dbuser->{'login'}->{'name'};
			$myuinfo->{'plainpass'} =
				$dbuser->{'login'}->{'password'};
			$myuinfo->{'pass'} = &encrypt_user_password($myuinfo,
						$myuinfo->{'plainpass'});
			$myuinfo->{'uid'} = &allocate_uid(\%taken);
			$myuinfo->{'gid'} = $dom{'gid'};
			$myuinfo->{'real'} = "MySQL user";
			$myuinfo->{'home'} =
				"$dom{'home'}/$config{'homes_dir'}/$mname";
			$myuinfo->{'shell'} = $nologin_shell->{'shell'};
			delete($myuinfo->{'email'});
			$myuinfo->{'dbs'} = [ { 'type' => 'mysql',
					        'name' => $name } ];
			&create_user($myuinfo, \%dom);
			&create_user_home($myuinfo, \%dom);
			&create_mail_file($myuinfo);
			$taken{$myuinfo->{'uid'}}++;
			$myucount++;
			}

		&$outdent_print();
		$mcount++;
		}
	&$second_print(".. done (migrated $mcount databases, and created $myucount users)");
	}
&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

&sync_alias_virtuals(\%dom);
goto DONE;

# Migrate protected directories as .htaccess files
local $pdir = $domain->{'phosting'}->{'pdir'};
if ($pdir && &foreign_check("htaccess-htpasswd")) {
	&$first_print("Re-creating protected directories ..");
	&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
	local $hdir = &public_html_dir(\%dom);
	local $etc = "$dom{'home'}/etc";
	if (!-d $etc) {
		# Create ~/etc dir
		&make_dir($etc, 0755);
		&set_ownership_permissions($dom{'uid'}, $dom{'gid'},
					   undef, $etc);
		}

	# Migrate each one, by creating a .htaccess file
	local $pcount = 0;
	if ($pdir->{'name'}) {
		$pdir = { $pdir->{'name'} => $pdir };
		}
	local @htdirs = &htaccess_htpasswd::list_directories();
	foreach my $name (keys %$pdir) {
		# Make .htaccess file
		local $p = $pdir->{$name};
		local $dir = "$hdir/$name";
		local $htaccess = "$dir/$htaccess_htpasswd::config{'htaccess'}";
		$name =~ s/\//-/g;
		local $htpasswd = "$etc/.htpasswd-$name";
		&open_tempfile(HTACCESS, ">$htaccess");
		&print_tempfile(HTACCESS, "AuthName \"$p->{'title'}\"\n");
		&print_tempfile(HTACCESS, "AuthType Basic\n");
		&print_tempfile(HTACCESS, "AuthUserFile $htpasswd\n");
		&print_tempfile(HTACCESS, "require valid-user\n");
		&close_tempfile(HTACCESS);

		# Add users to .htpasswd file
		&open_tempfile(HTPASSWD, ">$htpasswd");
		&close_tempfile(HTPASSWD);
		local $pduser = $p->{'pduser'};
		if ($pduser) {
			$pduser = [ $pduser ] if (ref($pduser) ne 'ARRAY');
			foreach my $u (@$pduser) {
				local $huinfo = { 'user' => $u->{'name'},
						  'enabled' => 1 };
				local $pass = $u->{'password'}->{'content'};
				if ($u->{'password'}->{'type'} eq 'plain') {
					$huinfo->{'pass'} = &htaccess_htpasswd::encrypt_password($pass);
					}
				else {
					$huinfo->{'pass'} = $pass;
					}
				&htaccess_htpasswd::create_user($huinfo,
								$htpasswd);
				}
			}
		&set_ownership_permissions($dom{'uid'}, $dom{'gid'}, 0755,
					   $htaccess, $htpasswd);

		# Add to protected directories module
		push(@htdirs, [ $dir, $htpasswd, 0, 0, undef ]);
		$pcount++;
		}
	&htaccess_htpasswd::save_directories(\@htdirs);
	&$second_print(".. done (migrated $pcount)");
	}

# Migrate alias domains
local $aliasdoms = $domain->{'domain-alias'};
if (!$aliasdoms) {
	$aliasdoms = { };
	}
elsif ($aliasdoms->{'web'}) {
	# Just one alias
	$aliasdoms = { $aliasdoms->{'name'} => $aliasdoms };
	}
local @rvdoms;
foreach my $adom (keys %$aliasdoms) {
	local $aliasdom = $aliasdoms->{$adom};
	&$first_print("Creating alias domain $adom ..");
	&$indent_print();
	local %alias = ( 'id', &domain_id(),
			 'dom', $adom,
			 'user', $dom{'user'},
			 'group', $dom{'group'},
			 'prefix', $dom{'prefix'},
			 'ugroup', $dom{'ugroup'},
			 'pass', $dom{'pass'},
			 'alias', $dom{'id'},
			 'uid', $dom{'uid'},
			 'gid', $dom{'gid'},
			 'ugid', $dom{'ugid'},
			 'owner', "Migrated Plesk alias for $dom{'dom'}",
			 'email', $dom{'email'},
			 'name', 1,
			 'ip', $dom{'ip'},
			 'virt', 0,
			 'source', $dom{'source'},
			 'parent', $dom{'id'},
			 'template', $dom{'template'},
			 'reseller', $dom{'reseller'},
			 'nocreationmail', 1,
			 'nocopyskel', 1,
			);
	$alias{'dom'} =~ s/^www\.//;
	foreach my $f (@alias_features) {
		local $want = $f eq 'web' ? $aliasdom->{'web'} eq 'true' :
			      $f eq 'dns' ? $aliasdom->{'dns'} eq 'true' : 1;
		$alias{$f} = $dom{$f} && $want;
		}
	local $parentdom = $dom{'parent'} ? &get_domain($dom{'parent'})
					  : \%dom;
	$alias{'home'} = &server_home_directory(\%alias, $parentdom);
	&complete_domain(\%alias);
	&create_virtual_server(\%alias, $parentdom,
			       $parentdom->{'user'});
	&$outdent_print();
	&$second_print($text{'setup_done'});
	push(@rvdoms, \%alias);
	}

# Migrate sub-domains (as Virtualmin sub-servers)
local $subdoms = $domain->{'phosting'}->{'subdomain'};
if (!$subdoms) {
	$subdoms = { };
	}
elsif ($subdoms->{'cid_conf'}) {
	# Just one sub-domain
	$subdoms = { $subdoms->{'name'} => $subdoms };
	}
foreach my $sdom (keys %$subdoms) {
	local $subdom = $subdoms->{$sdom};
	&$first_print("Creating sub-domain $sdom.$dom{'dom'} ..");
	&$indent_print();
	local %subd = ( 'id', &domain_id(),
			'dom', $sdom.".".$dom{'dom'},
			'user', $dom{'user'},
			'group', $dom{'group'},
			'prefix', $dom{'prefix'},
			'ugroup', $dom{'ugroup'},
			'pass', $dom{'pass'},
			'parent', $dom{'id'},
			'uid', $dom{'uid'},
			'gid', $dom{'gid'},
			'ugid', $dom{'ugid'},
			'owner', "Migrated Plesk sub-domain for $dom{'dom'}",
			'email', $dom{'email'},
			'name', 1,
			'ip', $dom{'ip'},
			'virt', 0,
			'source', $dom{'source'},
			'parent', $dom{'id'},
			'template', $dom{'template'},
			'reseller', $dom{'reseller'},
			'nocreationmail', 1,
			'nocopyskel', 1,
			);
	foreach my $f (@subdom_features) {
		local $want = $f eq 'ssl' ? 0 : 1;
		$subd{$f} = $dom{$f} && $want;
		}
	local $parentdom = $dom{'parent'} ? &get_domain($dom{'parent'})
					  : \%dom;
	$subd{'home'} = &server_home_directory(\%subd, $parentdom);
	&complete_domain(\%subd);
	&create_virtual_server(\%subd, $parentdom,
			       $parentdom->{'user'});
	&$outdent_print();
	&$second_print($text{'setup_done'});
	push(@rvdoms, \%subd);

	# Extract sub-domain's HTML directory
	local $htdocs = "$root/$subd{'dom'}.httpdocs";
	if (!-r $htdocs) {
		$htdocs = "$root/$subd{'dom'}.htdocs";
		}
	local $hdir = &public_html_dir(\%subd);
	if (-r $htdocs) {
		&$first_print(
			"Copying web pages for sub-domain $subd{'dom'} ..");
		local $err = &extract_compressed_file($htdocs, $hdir);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&set_home_ownership(\%dom);
			&$second_print(".. done");
			}
		}

	# Extract sub-domains CGI directory
	local $cgis = "$root/$subd{'dom'}.cgi-bin";
	if (!-r $cgis) {
		$cgis = "$root/$subd{'dom'}.cgi";
		}
	if (-r $cgis) {
		&$first_print(
			"Copying CGI scripts for sub-domain $subd{'dom'} ..");
		local $cdir = &cgi_bin_dir(\%subd);
		local $err = &extract_compressed_file($cgis, $cdir);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&set_home_ownership(\%dom);
			&$second_print(".. done");
			}
		}

	# Re-create users for sub-domains
	&$first_print("Re-creating sub-domain users ..");
	local $sysusers = $subdom->{'sysuser'};
	if (!$sysusers) {
		$sysusers = { };
		}
	elsif ($sysusers->{'name'}) {
		# Just one user
		$sysusers = { $sysusers->{'name'} => $sysusers };
		}
	local $sucount = 0;
	foreach my $name (keys %$sysusers) {
		local $mailuser = $sysusers->{$name};
		local $uinfo = &create_initial_user(\%dom, 0, 1);
		$uinfo->{'user'} = &userdom_name($name, \%dom);
		if ($mailuser->{'password'}->{'type'} eq 'plain') {
			$uinfo->{'plainpass'} =
				$mailuser->{'password'}->{'content'};
			$uinfo->{'pass'} = &encrypt_user_password(
						$uinfo, $uinfo->{'plainpass'});
			}
		else {
			$uinfo->{'pass'} = $mailuser->{'password'}->{'content'};
			}
		$uinfo->{'uid'} = $dom{'uid'};
		$uinfo->{'gid'} = $dom{'gid'};
		$uinfo->{'home'} = $hdir;
		$uinfo->{'shell'} = $ftp_shell->{'shell'};
		&create_user($uinfo, \%dom);
		$sucount++;
		}
	&$second_print(".. created $sucount");
	}

DONE:
return (\%dom, @rvdoms);
}

sub remove_cid_prefix
{
local ($cid) = @_;
$cid =~ s/^cid://;
return $cid;
}

1;

