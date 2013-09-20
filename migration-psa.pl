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
#			&ipinfo, pass, [&parent], [prefix], [email])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_psa_migrate
{
local ($file, $dom, $user, $webmin, $template, $ipinfo, $pass, $parent,
       $prefix, $email) = @_;

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
local $users = $domain->{'user'};
$users = !$users ? [ ] :
	 ref($users) eq 'ARRAY' ? $users : [ $users ];
local $uinfo = $users->[0];
$uinfo || $parent || &error("No primary user details found in backup");
if (!$user && $uinfo) {
	$user = $uinfo->{'login'}->{'name'};
	}
local $group = $user;
local $ugroup = $group;

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix") );
push(@got, "webmin") if ($webmin && !$parent);
push(@got, "mail");	# Assume that all domains have mail
if ($domain->{'dns'}) {
	push(@got, "dns");
	}
push(@got, "web");	# Assume has website
if ($uinfo && $uinfo->{'services'}->{'ssl'} eq 'true') {
	push(@got, "ssl");
	}
if ($uinfo && $uinfo->{'services'}->{'webstat'} eq 'true') {
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
foreach my $u (@$users) {
	if ($u->{'spamassassin'}) {
		$has_spam = 1;
		}
	if (!$uinfo || $u->{'login'}->{'name'} ne $uinfo->{'login'}->{'name'}) {
		push(@mailusers, $u);
		}
	}
if (&indexof("mail", @got) >= 0) {
	$has_spam++ if ($has_virus);	# Dependency
	push(@got, "spam") if ($has_spam);
	push(@got, "virus") if ($has_virus);
	}

# Add 'web users'
if ($uinfo) {
	local $webusers = $uinfo->{'user'};
	$webusers = !$webusers ? [ ] :
		    ref($webusers) ne 'ARRAY' ? [ $webusers ] : $webusers;
	push(@mailusers, @$webusers);
	}

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
	$quota = $domain->{'limits'}->{'disk_space'} / $bsize;
	}

# Create the virtual server object
local %dom;
$prefix ||= &compute_prefix($dom, $group, $parent, 1);
local $plan = $parent ? &get_plan($parent->{'plan'}) : &get_default_plan();
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
	 'dns_ip', $ipinfo->{'virt'} || $config{'all_namevirtual'} ? undef :
		   &get_dns_ip($parent ? $parent->{'id'} : undef),
	 $parent ? ( 'pass', $parent->{'pass'} )
		 : ( 'pass', $pass ),
	 'source', 'migrate.cgi',
	 'template', $template,
	 'plan', $plan->{'id'},
	 'parent', $parent ? $parent->{'id'} : undef,
	 'reseller', $parent ? $parent->{'reseller'} : undef,
	 'prefix', $prefix,
	 'no_tmpl_aliases', 1,
	 'no_mysql_db', $got{'mysql'} ? 1 : 0,
	 'nocreationmail', 1,
	 'nocopyskel', 1,
	 'parent', $parent ? $parent->{'id'} : undef,
        );
&merge_ipinfo_domain(\%dom, $ipinfo);
if (!$parent) {
	&set_limits_from_plan(\%dom, $plan);
	$dom{'quota'} = $quota;
	$dom{'uquota'} = $quota;
	&set_capabilities_from_plan(\%dom, $plan);
	}
$dom{'db'} = $db || &database_name(\%dom);
$dom{'emailto'} = $dom{'email'} ||
		  $dom{'user'}.'@'.&get_system_hostname();
foreach my $f (@features, &list_feature_plugins()) {
	$dom{$f} = $got{$f} ? 1 : 0;
	}
&set_featurelimits_from_plan(\%dom, $plan);
$dom{'home'} = &server_home_directory(\%dom, $parent);
$dom{'public_html_dir'} = 'httpdocs';			# Plesk 7 style
$dom{'public_html_path'} = $dom{'home'}.'/httpdocs';
$dom{'cgi_bin_dir'} = 'cgi-bin';
$dom{'cgi_bin_path'} = $dom{'home'}.'/cgi-bin';
if ($domain->{'forwarding'} && $domain->{'forwarding'}->{'redirect'}) {
	$dom{'proxy_pass_mode'} = 2;
	$dom{'proxy_pass'} = $domain->{'forwarding'}->{'redirect'};
	}
&set_provision_features(\%dom);
&generate_domain_password_hashes(\%dom, 1);
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
&$first_print("Creating initial virtual server $dom ..");
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
if ($uinfo) {
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
		&set_home_ownership(\%dom);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}
	# Fix perms tar may have messed up
	&create_standard_directories(\%dom);
	&set_ownership_permissions(undef, undef, oct($uconfig{'homedir_perms'}),
				   $dom{'home'});
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%dom, 0);
		}
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

# Move the domain owner's mailbox (if needed) and cron jobs
if (!$parent) {
	local $srcfolder = { 'file' => $dom{'home'}.'/Maildir', 'type' => 1 };
	local $duser = &get_domain_owner(\%dom);
	if ($duser) {
		# Move inbox
		local ($ofile, $otype) = &user_mail_file($duser);
		local $dstfolder = { 'file' => $ofile, 'type' => $otype };
		if ($srcfolder->{'file'} ne $dstfolder->{'file'}) {
			&$first_print("Copying domain owner's mailbox ..");
			&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
			&set_mailfolder_owner($dstfolder, $duser);
			&$second_print(".. done");
			}
		}

	if ($duser && $uinfo) {
		# Append crontab to user's current jobs
		local $crsrc = $root."/".
			&remove_cid_prefix($uinfo->{'crontab'}->{'src'});
		if ($uinfo->{'crontab'}->{'src'} && -r $crsrc) {
			&$first_print("Copying domain owner's cron jobs ..");
			eval {
				local $main::error_must_die = 1;
				$cron::cron_temp_file = &transname();
				&cron::copy_cron_temp(
					{ 'user' => $duser->{'user'} });
				&execute_command(
					"cat $crsrc >>$cron::cron_temp_file");
				&cron::copy_crontab($duser->{'user'});
				};
			if ($@) {
				&$second_print(".. failed : $@");
				}
			else {
				&$second_print(".. done");
				}
			}
		}
	}

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

# Re-create mail users and copy mail files
if (@mailusers) {
	&$first_print("Re-creating mail users ..");
	}
local $mcount = 0;
&foreign_require("mailboxes", "mailboxes-lib.pl");
foreach my $mailuser (@mailusers) {
	local $muinfo = &create_initial_user(\%dom);
	local $name = $mailuser->{'login'}->{'name'};
	$muinfo->{'user'} = &userdom_name(lc($name), \%dom);
	if ($mailuser->{'login'}->{'PW_TYPE'} eq 'plain') {
		$muinfo->{'plainpass'} = $mailuser->{'login'}->{'password'};
		$muinfo->{'pass'} = &encrypt_user_password(
					$muinfo, $muinfo->{'plainpass'});
		}
	else {
		$muinfo->{'pass'} = $mailuser->{'login'}->{'password'};
		}
	$muinfo->{'uid'} = &allocate_uid(\%taken);
	$muinfo->{'gid'} = $dom{'gid'};
	$muinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($name);
	if ($mailuser->{'type'} eq 'web_users') {
		# Has FTP access
		$muinfo->{'shell'} = $ftp_shell->{'shell'};
		}
	else {
		$muinfo->{'shell'} = $nologin_shell->{'shell'};
		}
	$muinfo->{'to'} = [ ];
	if ($mailuser->{'services'}->{'postbox'} eq 'true') {
		# Add delivery to user's mailbox
		local $escuser = $muinfo->{'user'};
		if ($config{'mail_system'} == 0 && $escuser =~ /\@/) {
			$escuser = &replace_atsign($escuser);
			}
		else {
			$escuser = &escape_user($escuser);
			}
		push(@{$muinfo->{'to'}}, "\\".$escuser);
		}
	if (&has_home_quotas()) {
		local $q = $mailuser->{'login'}->{'quota'};
		$muinfo->{'qquota'} = $q;
		$muinfo->{'quota'} = $q / &quota_bsize("home");
		$muinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	# Add forwarding
	local $forwarding = $mailuser->{'services'}->{'forwarding'};
	if ($forwarding) {
		$forwarding = [ $forwarding ] if (ref($forwarding) ne 'ARRAY');
		foreach my $f (@$forwarding) {
			local $email = $f->{'email'};
			next if (!$email);
			$email = [ $email ] if (!ref($email));
			foreach my $r (@$email) {
				$r .= "@".$dom{'dom'} if ($r !~ /\@/);
				push(@{$muinfo->{'to'}}, $r);
				}
			}
		}
	# Add any autoresponder
	local $auto = $mailuser->{'autoresponder'};
	if (@{$muinfo->{'to'}}) {
		# Only enable mail if there is at least one destination, which
		# would be his own mailbox or offsite
		$muinfo->{'email'} = lc($name)."\@".$dom;
		}
	&create_user_home($muinfo, \%dom, 1);
	&create_user($muinfo, \%dom);
	$taken{$muinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($muinfo, \%dom);

	# Extract mail user's home directory
	local $hmsrc = $root."/".&remove_cid_prefix($mailuser->{'src'});
	if ($mailuser->{'src'} && -r $hmsrc) {
		local $err = &extract_compressed_file($hmsrc,$muinfo->{'home'});
		if ($err) {
			&$first_print("Failed to extract home for $muinfo->{'user'} : $err");
			}
		local $dstfolder = { 'file' => $crfile, 'type' => $crtype };
		local $srcfolder = { 'file' => $muinfo->{'home'}.'/Maildir',
				     'type' => 1 };
		if ($srcfolder->{'file'} ne $dstfolder->{'file'} &&
		    -d $srcfolder->{'file'}) {
			# Need to move mail file too
			&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
			&set_mailfolder_owner($dstfolder, $muinfo);
			}
		}
	elsif ($mailuser->{'type'} ne 'domain_level') {
		&$first_print("No home contents found for $muinfo->{'user'}");
		}

	$mcount++;
	}
if (@mailusers) {
	&set_mailbox_homes_ownership(\%dom);
	&$second_print(".. done (migrated $mcount users)");
	}

# Re-create MySQL databases
if ($got{'mysql'}) {
	&require_mysql();
	local $mcount = 0;
	local $myucount = 0;
	&$first_print("Migrating MySQL databases ..");
	&disable_quotas(\%dom);
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
			local $mname = $dbuser->{'login'}->{'name'};
			$myuinfo->{'user'} = $mname;
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
			&create_user_home($myuinfo, \%dom, 1);
			&create_user($myuinfo, \%dom);
			&create_mail_file($myuinfo, \%dom);
			$taken{$myuinfo->{'uid'}}++;
			$myucount++;
			}

		&$outdent_print();
		$mcount++;
		}
	&enable_quotas(\%dom);
	&$second_print(".. done (migrated $mcount databases, and created $myucount users)");
	}
&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

&sync_alias_virtuals(\%dom);

# Migrate protected directories as .htaccess files
local $pdirs = $uinfo ? $uinfo->{'protected_dir'} : [ ];
if ($pdirs && ref($pdirs) ne 'ARRAY') {
	$pdirs = [ $pdirs ];
	}
if (@$pdirs && &foreign_check("htaccess-htpasswd")) {
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
	local @htdirs = &htaccess_htpasswd::list_directories();
	foreach my $p (@$pdirs) {
		# Make .htaccess file
		local $name = $p->{'path'};
		local $dir = "$hdir/$name";
		local $htaccess = "$dir/$htaccess_htpasswd::config{'htaccess'}";
		$name =~ s/\//-/g;
		local $htpasswd = "$etc/.htpasswd-$name";
		local $realm = $p->{'realm'}->{'desc'} || $name;
		&open_tempfile(HTACCESS, ">$htaccess");
		&print_tempfile(HTACCESS, "AuthName \"$realm\"\n");
		&print_tempfile(HTACCESS, "AuthType Basic\n");
		&print_tempfile(HTACCESS, "AuthUserFile $htpasswd\n");
		&print_tempfile(HTACCESS, "require valid-user\n");
		&close_tempfile(HTACCESS);

		# Add users to .htpasswd file
		&open_tempfile(HTPASSWD, ">$htpasswd");
		&close_tempfile(HTPASSWD);
		local $pdusers = $p->{'user'};
		if ($pdusers && ref($pdusers) ne 'ARRAY') {
			$pdusers = [ $pdusers ];
			}
		if (@$pdusers) {
			foreach my $u (@$pdusers) {
				local $huinfo = {
					'user' => $u->{'login'}->{'name'},
					'enabled' => 1 };
				local $pass = $u->{'login'}->{'password'};
				if ($u->{'login'}->{'PW_TYPE'} eq 'plain') {
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

# Migrate sub-domains (as Virtualmin sub-servers)
local $subdoms = $uinfo ? $uinfo->{'subdomains'} : { };
if (!$subdoms) {
	$subdoms = { };
	}
elsif ($subdoms->{'name'}) {
	# Just one sub-domain
	$subdoms = { $subdoms->{'name'} => $subdoms };
	}
foreach my $sdom (keys %$subdoms) {
	local $subdom = $subdoms->{$sdom};
	local $sname = $sdom.".".$dom{'dom'};
	&$first_print("Creating sub-domain $sname ..");
	if (&domain_name_clash($sname)) {
		&$second_print(".. the domain $sname already exists");
		next;
		}
	&$indent_print();
	local %subd = ( 'id', &domain_id(),
			'dom', $sname,
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
	$subd{'public_html_dir'} = 'httpdocs';			# Plesk 7 style
	$subd{'public_html_path'} = $subd{'home'}.'/httpdocs';
	$subd{'cgi_bin_dir'} = 'cgi-bin';
	$subd{'cgi_bin_path'} = $subd{'home'}.'/cgi-bin';
	&generate_domain_password_hashes(\%subd, 1);
	&complete_domain(\%subd);
	&create_virtual_server(\%subd, $parentdom,
			       $parentdom->{'user'});
	&$outdent_print();
	&$second_print(".. done");
	push(@rvdoms, \%subd);

	# Extract directory for sub-domains
	&$first_print("Copying home directory for sub-domain $subd{'dom'} ..");
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%subd, 1);
		}
	local $htsrc = $root."/".&remove_cid_prefix($subdom->{'src'});
	if ($subdom->{'src'} && -r $htsrc) {
		local $err = &extract_compressed_file($htsrc, $subd{'home'});
		&set_home_ownership(\%subd);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}
	else {
		&$second_print(".. not found in backup");
		}
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%subd, 0);
		}
	}

# Save original Plesk 7 XML file
&save_plesk_xml_files(\%dom, $xfile, $dump);

return (\%dom, @rvdoms);
}

sub remove_cid_prefix
{
local ($cid) = @_;
$cid =~ s/^cid://;
return $cid;
}

1;

