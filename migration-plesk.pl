# Functions for migrating a plesk backup. These appear to be in MIME format,
# with each part (home dir, settings, etc) in a separate 'attachment'

# XXX how to find regular aliases?

# migration_plesk_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is a Plesk backup, and contains the domain
sub migration_plesk_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_plesk_dir($file);
$ok || return ("Not a Plesk 8 backup file : $root");
local $xfile = "$root/dump.xml";
local $windows = 0;
if (!-r $xfile) {
	$xfile = "$root/info.xml";
	$windows = 1;
	}
-r $xfile || return ("Not a complete Plesk 8 backup file - missing dump.xml or info.xml");

# Check Webmin version
&get_webmin_version() >= 1.365 ||
    return ("Webmin version 1.365 or later is needed to migrate Plesk domains");

# Check if the domain is in there
local $dump = &read_plesk_xml($xfile);
ref($dump) || return ($dump);
if (!$windows) {
	# Linux Plesk format
	if (!$dom) {
		# Work out domain name
		$dom = $dump->{'domain'}->{'name'};
		$dom || return ("Could not work out domain name from backup");
		}
	local $domain = $dump->{'domain'}->{$dom};
	if (!$domain && $dump->{'domain'}->{'name'} eq $dom) {
		$domain = $dump->{'domain'};
		}
	$domain || return ("Backup does not contain the domain $dom");

	if (!$parent && !$user) {
		# Check if we can work out the user
		$user = $domain->{'phosting'}->{'sysuser'}->{'name'};
		$user ||
		    return ("Could not work out original username from backup");
		}

	if (!$parent && !$pass) {
		# Check if we can work out the password
		$pass = $domain->{'phosting'}->{'sysuser'}->{'password'}->{'content'} ||
			$domain->{'domainuser'}->{'password'}->{'content'};
		$pass ||
		    return ("Could not work out original password from backup");
		}
	}
else {
	# On Windows, domain details are in a different place in the XML
	if (!$dom) {
		# Work out domain name
		$dom = $dump->{'clients'}->{'client'}->{'domain'}->{'name'};
		$dom || return ("Could not work out domain name from backup");
		}
	local $domain = $dump->{'clients'}->{'client'}->{'domain'};
	$domain->{'name'} eq $dom ||
		return ("Backup does not contain the domain $dom");

	if (!$parent && !$user) {
		# Check if we can work out the user
		$user = $domain->{'hosting'}->{'sys_user'}->{'login'};
		$user ||
		    return ("Could not work out original username from backup");
		}

	if (!$parent && !$pass) {
		# We must have the password
		$pass || return ("A password must be supplied when migrating ".
				 "a Plesk backup");
		}
	}

# Check for clashes
$prefix ||= &compute_prefix($dom, undef, $parent);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && return ("A virtual server using the prefix $prefix already exists");

return (undef, $dom, $user, $pass);
}

# migration_plesk_migrate(file, domain, username, create-webmin, template-id,
#			   ip-address, virtmode, pass, [&parent], [prefix],
#			   virt-already, [email])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_plesk_migrate
{
local ($file, $dom, $user, $webmin, $template, $ip, $virt, $pass, $parent,
       $prefix, $virtalready, $email) = @_;

# Get shells for users
local ($nologin_shell, $ftp_shell, undef, $def_shell) =
	&get_common_available_shells();
$nologin_shell ||= $def_shell;

# Extract backup and read the dump file
local ($ok, $root) = &extract_plesk_dir($file);
local $windows = 0;
local $xfile = "$root/dump.xml";
if (!-r $xfile) {
	$xfile = "$root/info.xml";
	$windows = 1;
	}
local $dump = &read_plesk_xml($xfile);

local $domain;
if (!$windows) {
	# Linux format
	$domain = $dump->{'domain'}->{$dom};
	if (!$domain && $dump->{'domain'}->{'name'} eq $dom) {
		$domain = $dump->{'domain'};
		}

	# Work out user and group
	if (!$user) {
		$user = $domain->{'phosting'}->{'sysuser'}->{'name'};
		}
	}
else {
	# Windows format
	$domain = $dump->{'clients'}->{'client'}->{'domain'};
	if (!$user) {
		$user = $domain->{'hosting'}->{'sys_user'}->{'login'};
		}
	}
local $group = $user;
local $ugroup = $group;

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix"), "web" );
push(@got, "webmin") if ($webmin && !$parent);
if (exists($domain->{'mailsystem'}->{'status'}->{'enabled'}) ||
    $domain->{'mail'}) {
	push(@got, "mail");
	}
if ($domain->{'dns-zone'} || $domain->{'dns_zone'}) {
	push(@got, "dns");
	}
if ($domain->{'www'} eq 'true' || -d "$root/$dom/httpdocs") {
	push(@got, "web");
	}
if ($domain->{'ip'}->{'ip-type'} eq 'exclusive' && $virt) {
	push(@got, "ssl");
	}
if ($domain->{'phosting'}->{'logrotation'}->{'enabled'} eq 'true' ||
    $windows && &indexof("web", @got) >= 0) {
	push(@got, "logrotate");
	}
if ($domain->{'phosting'}->{'webalizer'}) {
	push(@got, "webalizer");
	}

# Check for MySQL databases
local $databases = $domain->{'phosting'}->{'sapp-installed'}->{'database'};
if (!$databases) {
        $databases = $domain->{'database'};
        }
if (!$databases) {
	$databases = { };
	}
elsif ($databases->{'version'}) {
	# Just one database
	$databases = { $databases->{'name'} => $databases };
	}
local @mysqldbs = grep { $databases->{$_}->{'type'} eq 'mysql' }
		       (keys %$databases);
if (@mysqldbs) {
	push(@got, "mysql");
	}

local $mailusers;
local ($has_spam, $has_virus);
if (!$windows) {
	# Check for Linux mail users
	$mailusers = $domain->{'mailsystem'}->{'mailuser'};
	if (!$mailusers) {
		$mailusers = { };
		}
	elsif ($mailusers->{'mailbox-quota'}) {
		# Just one user
		$mailusers = { $mailusers->{'name'} => $mailusers };
		}
	foreach my $name (keys %$mailusers) {
		local $mailuser = $mailusers->{$name};
		if ($mailuser->{'spamassassin'}->{'status'} eq 'on') {
			$has_spam++;
			}
		if ($mailuser->{'virusfilter'}->{'state'} eq 'inout' ||
		    $mailuser->{'virusfilter'}->{'state'} eq 'in') {
			$has_virus++;
			}
		}
	}
else {
	# Check for Windows mail users
	$mailusers = $domain->{'mail'};
	if (!$mailusers) {
		$mailusers = { };
		}
	foreach my $mid (keys %$mailusers) {
		local $mailuser = $mailusers->{$mid};
		if ($mailuser->{'sa_conf'}) {
			$has_spam++;
			}
		}
	}

push(@got, "spam") if ($has_spam);
push(@got, "virus") if ($has_virus);

# Tell the user what we have got
local %pconfig = map { $_, 1 } @feature_plugins;
@got = grep { $config{$_} || $pconfig{$_} } @got;
&$second_print(".. found ".
	       join(", ", map { $text{'feature_'.$_} ||
				&plugin_call($_, "feature_name") } @got).".");
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
	$quota = $domain->{'phosting'}->{'sysuser'}->{'quota'} / $bsize;
	}
if (!$parent && !$pass) {
	$pass = $domain->{'phosting'}->{'sysuser'}->{'password'}->{'content'} ||
		$domain->{'domainuser'}->{'password'}->{'content'};
	}

# Create the virtual server object
local %dom;
$prefix ||= &compute_prefix($dom, $group, $parent);
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

# Copy web files
&$first_print("Copying web pages ..");
local $hdir = &public_html_dir(\%dom);
if (-d "$root/$dom/httpdocs") {
	# Windows format
	&copy_source_dest("$root/$dom/httpdocs", $hdir);
	&set_home_ownership(\%dom);
	&$second_print(".. done");
	}
else {
	# Linux format (a tar file)
	local $htdocs = "$root/$dom.httpdocs";
	if (!-r $htdocs) {
		$htdocs = "$root/$dom.htdocs";
		}
	if (-r $htdocs) {
		local $err = &extract_compressed_file($htdocs, $hdir);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&set_home_ownership(\%dom);
			&$second_print(".. done");
			}
		}
	else {
		&$second_print(".. not found in Plesk backup");
		}
	}

# Copy CGI files
&$first_print("Copying CGI scripts ..");
local $cgis = "$root/$dom.cgi-bin";
if (!-r $cgis) {
	$cgis = "$root/$dom.cgi";
	}
if (-r $cgis) {
	local $cdir = &cgi_bin_dir(\%dom);
	local $err = &extract_compressed_file($cgis, $cdir);
	if ($err) {
		&$second_print(".. failed : $err");
		}
	else {
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	}
else {
	&$second_print(".. not found in Plesk backup");
	}

# Re-create DNS records
local $oldip = $domain->{'ip'}->{'ip-address'};
if ($got{'dns'}) {
	&$first_print("Copying and fixing DNS records ..");
	local $zonexml = $domain->{'dns-zone'};
	local $newzone = &get_bind_zone($dom);
	if (!$newzone) {
		&$second_print(".. could not find new DNS zone!");
		}
	elsif (!$zonexml) {
		&$second_print(".. could not find zone in backup");
		}
	else {
		local $rcount = 0;
		local $zdstfile = &bind8::find_value("file",
						     $newzone->{'members'});
		local @recs = &bind8::read_zone_file($zdstfile, $dom);
		foreach my $rec (@{$zonexml->{'dnsrec'}}) {
			local $recname = $rec->{'src'};
			$recname .= ".".$dom."." if ($recname !~ /\.$/);
			local ($oldrec) = grep { $_->{'name'} eq $recname }
					       @recs;
			if (!$oldrec) {
				# Found one we need to add
				local $recvalue = $rec->{'dst'};
				local $rectype = $rec->{'type'};
				if ($rectype eq "A" && $recvalue eq $oldip) {
					# Use new IP address
					$recvalue = $ip;
					}
				if ($rectype eq "MX") {
					# Include priority in value
					$recvalue = $rec->{'opt'}." ".$recvalue;
					}
				if ($rectype eq "PTR") {
					# Not migratable
					next;
					}
				&bind8::create_record($zdstfile,
						      $recname,
						      undef,
						      "IN",
						      $rectype,
						      $recvalue);
				$rcount++;
				}
			}
		if ($rcount) {
			&bind8::bump_soa_record($zdstfile, \@recs);
			&register_post_action(\&restart_bind);
			}
		&$second_print(".. done (added $rcount records)");
		}
	}

# Migrate SSL certs
local $certificate = $domain->{'certificate'};
if ($certificate) {
	&$first_print("Migrating SSL certificate and key ..");
	local $cert = &cleanup_plesk_cert($certificate->{'certificate-data'});
	if ($cert) {
		$dom{'ssl_cert'} ||= &default_certificate_file(\%dom, 'cert');
		&open_tempfile(CERT, ">$dom{'ssl_cert'}");
		&print_tempfile(CERT, $cert);
		&close_tempfile(CERT);
		}
	local $key = &cleanup_plesk_cert($certificate->{'private-key'});
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
# Linux mailboxes
foreach my $name (keys %$mailusers) {
	next if ($windows);
	local $mailuser = $mailusers->{$name};
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name($name, \%dom);
	if ($mailuser->{'password'}->{'type'} eq 'plain') {
		$uinfo->{'plainpass'} = $mailuser->{'password'}->{'content'};
		$uinfo->{'pass'} = &encrypt_user_password(
					$uinfo, $uinfo->{'plainpass'});
		}
	else {
		$uinfo->{'pass'} = $mailuser->{'password'}->{'content'};
		}
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$name";
	$uinfo->{'shell'} = $nologin_shell;
	if ($mailuser->{'mailbox'}->{'enabled'} eq 'true') {
		$uinfo->{'email'} = $name."\@".$dom;
		}
	if (&has_home_quotas()) {
		local $q = $mailuser->{'mailbox-quota'} < 0 ? undef :
				$mailuser->{'mailbox-quota'}*1024;
		$uinfo->{'qquota'} = $q;
		$uinfo->{'quota'} = $q / &quota_bsize("home");
		$uinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	&create_user($uinfo, \%dom);
	&create_user_home($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo);

	# Copy mail into user's inbox
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
# Windows mail users
foreach my $mid (keys %$mailusers) {
	next if (!$windows);
	local $mailuser = $mailusers->{$mid};
	next if ($mailuser->{'mail_group'} eq 'true');
	local $name = $mailuser->{'mail_name'};
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name($name, \%dom);
	if ($mailuser->{'account'}->{'type'} eq 'plain') {
		$uinfo->{'plainpass'} = $mailuser->{'account'}->{'password'};
		$uinfo->{'pass'} = &encrypt_user_password(
					$uinfo, $uinfo->{'plainpass'});
		}
	else {
		$uinfo->{'pass'} = $mailuser->{'account'}->{'password'};
		}
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$name";
	$uinfo->{'shell'} = $nologin_shell;
	$uinfo->{'email'} = $name."\@".$dom;
	if (&has_home_quotas()) {
		local $q = $mailuser->{'mbox_quota'} < 0 ? undef :
				$mailuser->{'mbox_quota'}*1024;
		$uinfo->{'qquota'} = $q;
		$uinfo->{'quota'} = $q / &quota_bsize("home");
		$uinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	foreach my $r (values %{$mailuser->{'mail_redir'}}) {
		if ($r->{'address'}) {
			push(@{$uinfo->{'to'}}, $r->{'address'});
			}
		}
	&create_user($uinfo, \%dom);
	&create_user_home($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo);
	$mcount++;
	}
&$second_print(".. done (migrated $mcount users)");

# Re-create mail aliases
local $acount = 0;
&$first_print("Re-creating mail aliases ..");
&set_alias_programs();
# Linux catch all
local $ca = $domain->{'mailsystem'}->{'catch-all'};
if ($ca) {
	local @to;
	if ($ca =~ /^bounce:(.*)/) {
		push(@to, "BOUNCE $1");
		}
	else {
		push(@to, $ca);
		}
	local $virt = { 'from' => "\@$dom",
			'to' => \@to };
	&create_virtuser($virt);
	$acount++;
	}
# Windows mail aliases
foreach my $mid (keys %$mailusers) {
	next if (!$windows);
	local $mailuser = $mailusers->{$mid};
	next if ($mailuser->{'mail_group'} eq 'false');
	local $virt = { 'from' => $mailuser->{'mail_name'}.'@'.$dom,
			'to' => [ ] };
	foreach my $r (values %{$mailuser->{'mail_redir'}}) {
		if ($r->{'address'}) {
			push(@{$virt->{'to'}}, $r->{'address'});
			}
		}
	&create_virtuser($virt);
	$acount++;
	}
&$second_print(".. done (migrated $acount aliases)");

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
		local ($ex, $out) = &mysql::execute_sql_file($name,
			"$root/$database->{'cid'}");
		if ($ex) {
			&$first_print("Error loading $db : $out");
			}

		# Create any DB users as domain users
		local $dbusers = $database->{'dbuser'};
		$dbusers = !$dbusers ? { } :
		   $dbusers->{'password'} ? { $dbusers->{'name'} => $dbusers } :
					    $dbusers;
		foreach my $mname (keys %$dbusers) {
			next if ($mname eq $user);	# Domain owner
			local $myuinfo = &create_initial_user(\%dom);
			$myuinfo->{'user'} = $mname;
			$myuinfo->{'plainpass'} =
				$dbusers->{$mname}->{'password'}->{'content'};
			$myuinfo->{'pass'} = &encrypt_user_password($myuinfo,
						$myuinfo->{'plainpass'});
			$myuinfo->{'uid'} = &allocate_uid(\%taken);
			$myuinfo->{'gid'} = $dom{'gid'};
			$myuinfo->{'real'} = "MySQL user";
			$myuinfo->{'home'} =
				"$dom{'home'}/$config{'homes_dir'}/$myuser";
			$myuinfo->{'shell'} = $nologin_shell;
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

return (\%dom, @rvdoms);
}

# extract_plesk_dir(file)
# Extracts all attachments from a plesk backup in MIME format to a temp
# directory, and returns the path.
sub extract_plesk_dir
{
local ($file) = @_;
if ($main::plesk_dir_cache{$file} && -d $main::plesk_dir_cache{$file}) {
	# Use cached extract from this session
	return (1, $main::plesk_dir_cache{$file});
	}
local $dir = &transname();
&make_dir($dir, 0700);

# Is this compressed?
local $cf = &compression_format($file);
if ($cf != 0 && $cf != 1 && $cf != 4) {
	return (0, "Unknown compression format");
	}

if ($cf == 4) {
	# Windows Plesk backup, which is a ZIP file
	&has_command("unzip") || return (0, "The unzip command is needed to ".
					    "extract Plesk Windows backups");
	&execute_command("cd ".quotemeta($dir)." && unzip ".quotemeta($file));
	}
else {
	# Read in the backup as a fake mail object
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	local $mail = { };
	if ($cf == 0) {
		# MIME format file
		open(FILE, $file) || return undef;
		}
	else {
		# Gzipped MIME file
		open(FILE, "gunzip -c ".quotemeta($file)." |") || return undef;
		}
	while(<FILE>) {
		s/\r|\n//g;
		if (/^(\S+):\s+(.*)/) {
			$mail->{'header'}->{lc($1)} = $2;
			push(@{$mail->{'headers'}}, [ $1, $2 ]);
			}
		else {
			last;	# End of 'headers'
			}
		}
	while(read(FILE, $buf, 1024) > 0) {
		$mail->{'body'} .= $buf;
		}
	close(FILE);

	# Parse out the attachments and save each one off
	&mailboxes::parse_mail($mail, undef, undef, 1);
	local $count = 0;
	foreach my $a (@{$mail->{'attach'}}) {
		if ($a->{'filename'}) {
			open(ATTACH, ">$dir/$a->{'filename'}");
			print ATTACH $a->{'data'};
			close(ATTACH);
			$count++;
			}
		}
	return (0, "No attachments found in MIME data") if (!$count);
	}

$main::plesk_dir_cache{$file} = $dir;
return (1, $dir);
}

# read_plesk_xml(file)
# Use XML::Simple to read a Plesk XML file. Returns the object on success, or
# an error message on failure.
sub read_plesk_xml
{
local ($file) = @_;
eval "use XML::Simple";
if ($@) {
	return "XML::Simple Perl module is not installed";
	}
local $ref;
eval {
	local $xs = XML::Simple->new();
	$ref = $xs->XMLin($file);
	};
$ref || return "Failed to read XML file : $@";
return $ref;
}

# cleanup_plesk_cert(data)
# Removes extra spacing from a Plesk cert
sub cleanup_plesk_cert
{
local ($data) = @_;
local @lines = grep { /\S/ } split(/\n/, $data);
foreach my $l (@lines) {
	$l =~ s/^\s+//;
	}
return join("", map { $_."\n" } @lines);
}

1;

