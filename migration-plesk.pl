# Functions for migrating a Plesk 9-11 backup. These appear to be a tar.gz file,
# containing XML and more tar.gz files

# migration_plesk_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is a Plesk 9-11 backup, and contains the domain
sub migration_plesk_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_plesk_dir($file, 8);
$ok || return ("Not a Plesk 9, 10 or 11 backup file : $root");
local ($xfile) = glob("$root/*.xml");
$xfile && -r $xfile || return ("Not a complete Plesk 9, 10 or 11 backup file - missing XML file");

# Check if the domain is in there
local $dump = &read_plesk_xml($xfile);
ref($dump) || return ($dump);
local $domain;
local $domains = $dump->{'admin'} ? $dump->{'admin'}->{'domains'}
				  : $dump->{'domains'};
if ($domains) {
	# Plesk 11 format
	if ($domains->{'domain'}->{'name'}) {
		# Just one domain
		$domains->{'domain'} = { $domains->{'domain'}->{'name'} =>
					 $domains->{'domain'} };
		}
	if (!$dom) {
		# Use first domain
		foreach my $n (keys %{$domains->{'domain'}}) {
			my $v = $domains->{'domain'}->{$n};
			if ($v->{'phosting'}->{'preferences'}->{'sysuser'}->{'name'}) {
				$dom = $n;
				}
			}
		$dom || return ("Could not work out default domain");
		}
	$domain = $domains->{'domain'}->{$dom};
	$domain || return ("Backup does not contain the domain $dom");

	if (!$parent && !$user) {
		# Check if we can work out the user
		$user = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'name'};
		$user ||
		  return ("Could not work out original username from backup");
		}

	if (!$parent && !$pass) {
		$pass = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'password'}->{'content'};
		$pass ||
		  return ("Could not work out original password from backup");
		}
	}
else {
	# Plesk 9 / 10 format, or Plesk 11 single-domain
	local $mig = $dump->{'dump-format'} ? $dump :
			$dump->{'Data'}->{'migration-dump'};
	$mig || return ("Missing migration-dump section in XML file");
	if (scalar(keys %{$mig->{'domain'}}) == 0 ||
	    $dom && !$mig->{'domain'}->{$dom} && $mig->{'domain'}->{'name'} ne $dom) {
		# Inside client sub-section
		$mig = $mig->{'client'}->{'domains'};
		}
	if (!$dom) {
		# Work out domain name
		$dom = $mig->{'domain'}->{'name'};
		$dom || return ("Could not work out domain name from backup");
		}
	$domain = $mig->{'domain'}->{$dom};
	if (!$domain && $mig->{'domain'}->{'name'} eq $dom) {
		$domain = $mig->{'domain'};
		}
	$domain || return ("Backup does not contain the domain $dom");

	if (!$parent && !$user) {
		# Check if we can work out the user
		$user = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'name'};
		$user ||
		    return ("Could not work out original username from backup");
		}

	if (!$parent && !$pass) {
		# Check if we can work out the password
		$pass = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'password'}->{'content'} ||
			$domain->{'domainuser'}->{'password'}->{'content'};
		$pass ||
		    return ("Could not work out original password from backup");
		}
	}

return (undef, $dom, $user, $pass);
}

# migration_plesk_migrate(file, domain, username, create-webmin, template-id,
#			   &ipinfo, pass, [&parent], [prefix], [email], [&plan])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_plesk_migrate
{
local ($file, $dom, $user, $webmin, $template, $ipinfo, $pass, $parent,
       $prefix, $email, $plan) = @_;

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
local ($ok, $root) = &extract_plesk_dir($file);
local ($xfile) = glob("$root/*.xml");
local $dump = &read_plesk_xml($xfile);
ref($dump) || &error($dump);
local $domain;
local $domains = $dump->{'admin'} ? $dump->{'admin'}->{'domains'}
				  : $dump->{'domains'};
if ($domains) {
	# Plesk 11 format
	if ($domains->{'domain'}->{'name'}) {
		# Just one domain
		$domains->{'domain'} = { $domains->{'domain'}->{'name'} =>
					 $domains->{'domain'} };
		}

	# Get the domain object and username if not specified
	$domain = $domains->{'domain'}->{$dom};
	if (!$user) {
		$user = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'name'};
		}
	}
else {
	# Plesk 9 / 10 format, or Plesk 11 single domain
	local $mig = $dump->{'dump-format'} ? $dump :
			$dump->{'Data'}->{'migration-dump'};
	if (!$mig->{'domain'}->{$dom} &&
	    $mig->{'domain'}->{'name'} ne $dom) {
		# Inside client sub-section
		$mig = $mig->{'client'}->{'domains'};
		}

	# Get the domain object from the XML
	$domain = $mig->{'domain'}->{$dom};
	if (!$domain && $mig->{'domain'}->{'name'} eq $dom) {
		$domain = $mig->{'domain'};
		}

	# Work out user and group
	if (!$user) {
		$user = $domain->{'phosting'}->{'preferences'}->{'sysuser'}->{'name'};
		}
	}
local $group = $user;
local $ugroup = $group;

# Extract the tar.gz file containing additional content
&$first_print("Finding contents files ..");
local $cids = $domain->{'phosting'}->{'content'}->{'cid'};
if (!$cids) {
	&$second_print(".. no contents data found!");
#	return ( \%dom );
	}
elsif (ref($cids) eq 'HASH') {
	# Just one file (unlikely)
	$cids = [ $cids ];
	}
&$second_print(".. done");

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix") );
push(@got, "webmin") if ($webmin && !$parent);
local $mss = $domain->{'mailsystem'}->{'properties'}->{'status'};
if (exists($mss->{'enabled'}) ||
    $domain->{'mail'}) {
	push(@got, "mail");
	}
elsif (!$mss->{'disabled-by'}->{'admin'} &&
       $mss->{'disabled-by'}->{'name'} ne 'admin') {
	# Handle case where mail is enabled, but XML contains :
	# <disabled-by name="parent"/>
	# but not
	# <disabled-by name="admin"/>
	push(@got, "mail");
	}
if ($domain->{'properties'}->{'dns-zone'}) {
	push(@got, "dns");
	}
local ($wwwcid) = grep { $_->{'type'} eq 'docroot' } @$cids;
if ($domain->{'www'} eq 'true' || $wwwcid) {
	push(@got, &domain_has_website());
	}
my $ip = $domain->{'properties'}->{'ip'};
if (ref($ip) eq 'ARRAY') {
	($ip) = grep { &check_ipaddress($_->{'ip-address'}) } @$ip;
	}
if ($ip->{'ip-type'} eq 'exclusive' && $ipinfo->{'virt'}) {
	push(@got, &domain_has_ssl());
	}
if (($domain->{'phosting'}->{'preferences'}->{'logrotation'}->{'enabled'} eq 'true' || $windows) && &indexof(&domain_has_website(), @got) >= 0) {
	push(@got, "logrotate");
	}
if ($domain->{'phosting'}->{'preferences'}->{'webalizer'} &&
    &indexof(&domain_has_website(), @got) >= 0) {
	push(@got, "webalizer");
	}

# Check for MySQL databases
local $databases = $domain->{'databases'}->{'database'};
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

# Check for mail users
local ($has_spam, $has_virus);
local $mailusers = $domain->{'mailsystem'}->{'mailusers'}->{'mailuser'};
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

if (&indexof("mail", @got) >= 0) {
	$has_spam++ if ($has_virus);	# Dependency
	push(@got, "spam") if ($has_spam);
	push(@got, "virus") if ($has_virus);
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
	$quota = $domain->{'phosting'}->{'sysuser'}->{'quota'} / $bsize;
	}
if (!$parent && !$pass) {
	$pass = $domain->{'phosting'}->{'sysuser'}->{'password'}->{'content'} ||
		$domain->{'domainuser'}->{'password'}->{'content'};
	}

# Create the virtual server object
local %dom;
$prefix ||= &compute_prefix($dom, $group, $parent, 1);
$plan = $parent ? &get_plan($parent->{'plan'}) :
        $plan ? $plan : &get_default_plan();
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
	 'dns_ip', $ipinfo->{'virt'} ? undef :
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
	 'nocreationscripts', 1,
	 'parent', $parent ? $parent->{'id'} : undef,
	 'creation_type', 'migrate',
	 'migration_type', 'plesk',
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
&set_chained_features(\%dom, undef);
&set_featurelimits_from_plan(\%dom, $plan);
$dom{'home'} = &server_home_directory(\%dom, $parent);
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

# Copy home directory files
&$first_print("Copying web pages ..");
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 1);
	}
local $hdir = &public_html_dir(\%dom);
local $phdir = $hdir;
local $user_data_files;
if ($cids) {
	$user_data_files = &extract_plesk_cid($root, $cids, "user-data");
	local $docroot_files = &extract_plesk_cid($root, $cids, "docroot");
	local $httpdocs = $domain->{'phosting'}->{'www-root'} || "httpdocs";
	local $cgidocs = "cgi-bin";
	if ($docroot_files) {
		&copy_source_dest($docroot_files, $hdir);
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	elsif ($user_data_files) {
		&copy_source_dest($user_data_files."/".$httpdocs, $hdir);
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	else {
		&$second_print(".. no docroot data found");
		}

	# Copy CGI files
	&$first_print("Copying CGI scripts ..");
	local $cdir = &cgi_bin_dir(\%dom);
	local $cgi_files =  &extract_plesk_cid($root, $cids, "cgi");
	if ($cgi_files) {
		&copy_source_dest($cgi_files, $cdir);
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	elsif ($user_data_files) {
                &copy_source_dest($user_data_files."/".$cgidocs, $cdir);
                &set_home_ownership(\%dom);
                &$second_print(".. done");
                }
	else {
		&$second_print(".. no cgi data found");
		}
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%dom, 0);
		}
	}

# Re-create DNS records
local $oldip = $ip->{'ip-address'};
if ($got{'dns'}) {
	&$first_print("Copying and fixing DNS records ..");
	local $zonexml = $domain->{'properties'}->{'dns-zone'};
	local ($recs, $file) = &get_domain_dns_records_and_file(\%dom);
	if (!$file) {
		&$second_print(".. could not find new DNS zone!");
		}
	elsif (!$zonexml) {
		&$second_print(".. could not find zone in backup");
		}
	else {
		local $rcount = 0;
		foreach my $rec (@{$zonexml->{'dnsrec'}}) {
			local $recname = $rec->{'src'};
			$recname .= ".".$dom."." if ($recname !~ /\.$/);
			local ($oldrec) = grep { $_->{'name'} eq $recname }
					       @$recs;
			if (!$oldrec) {
				# Found one we need to add
				local $recvalue = $rec->{'dst'};
				local $rectype = $rec->{'type'};
				if ($rectype eq "A" && $recvalue eq $oldip) {
					# Use new IP address
					$recvalue = $dom{'dns_ip'} ||
						    $dom{'ip'};
					}
				if ($rectype eq "MX") {
					# Include priority in value
					$recvalue = $rec->{'opt'}." ".$recvalue;
					}
				if ($rectype eq "PTR") {
					# Not migratable
					next;
					}
				my $nr = { 'name' => $recname,
					   'type' => $rectype,
					   'values' => [ split(/\s+/, $recvalue) ] };
				&create_dns_record($recs, $file, $nr);
				$rcount++;
				}
			}
		if ($rcount) {
			&post_records_change(\%dom, $recs, $file);
			&register_post_action(\&restart_bind);
			}
		&$second_print(".. done (added $rcount records)");
		}
	}

# Migrate SSL certs
local $certificate = $domain->{'certificates'}->{'certificate'};
if ($certificate) {
	&$first_print("Migrating SSL certificate and key ..");
	local $cert = &cleanup_plesk_cert($certificate->{'certificate-data'});
	&create_ssl_certificate_directories(\%dom);
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
	local $ca = &cleanup_plesk_cert($certificate->{'ca-certificate'});
	if ($ca) {
		$dom{'ssl_chain'} ||= &default_certificate_file(\%dom, 'chain');
		&open_tempfile(CERT, ">$dom{'ssl_chain'}");
		&print_tempfile(CERT, $ca);
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
&foreign_require("mailboxes");
$mailboxes::no_permanent_index = 1;
local $mcount = 0;
foreach my $name (keys %$mailusers) {
	next if ($windows);
	local $mailuser = $mailusers->{$name};
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name(lc($name), \%dom);
	local $pinfo = $mailuser->{'properties'}->{'password'};
	if ($pinfo->{'type'} eq 'plain') {
		$uinfo->{'plainpass'} = $pinfo->{'content'};
		$uinfo->{'pass'} = &encrypt_user_password(
					$uinfo, $uinfo->{'plainpass'});
		}
	else {
		$uinfo->{'pass'} = $pinfo->{'content'};
		}
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($name);
	$uinfo->{'shell'} = $nologin_shell->{'shell'};
	$uinfo->{'to'} = [ ];
	if ($mailuser->{'mailbox'}->{'enabled'} eq 'true') {
		# Add delivery to user's mailbox
		local $escuser = $uinfo->{'user'};
		if ($mail_system == 0 && $escuser =~ /\@/) {
			$escuser = &escape_replace_atsign_if_exists($escuser);
			}
		else {
			$escuser = &escape_user($escuser);
			}
		push(@{$uinfo->{'to'}}, "\\".$escuser);
		}
	if (&has_home_quotas()) {
		local $q = $mailuser->{'mailbox-quota'} < 0 ? undef :
				$mailuser->{'mailbox-quota'};
		$uinfo->{'quota'} = $q / &quota_bsize("home");
		$uinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	# Add mail aliases
	local $alias = $mailuser->{'preferences'}->{'alias'};
	if ($alias) {
		$alias = [ $alias ] if (ref($alias) ne 'ARRAY');
		foreach my $a (@$alias) {
			$a = $a->{'content'} if (ref($a));
			$a .= "@".$dom{'dom'} if ($a !~ /\@/);
			push(@{$uinfo->{'extraemail'}}, $a);
			}
		}
	# Add forwarding
	local $redirect = $mailuser->{'preferences'}->{'redirect'};
	if ($redirect) {
		$redirect = [ $redirect ] if (ref($redirect) ne 'ARRAY');
		foreach my $r (@$redirect) {
			$r = $r->{'content'} if (ref($r));
			$r .= "@".$dom{'dom'} if ($r !~ /\@/);
			push(@{$uinfo->{'to'}}, $r);
			}
		}
	# Add mail group members (which are really just forwards)
	local $mailgroup = $mailuser->{'preferences'}->{'mailgroup-member'};
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
		$uinfo->{'email'} = lc($name)."\@".$dom;
		}
	else {
		delete($uinfo->{'email'});
		}
	&create_user_home($uinfo, \%dom, 1);
	&create_user($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);

	# Copy mail into user's inbox
	local $cids = [ $mailuser->{'preferences'}->{'mailbox'}->{'content'}->{'cid'} ];
	if (ref($cids->[0]) eq 'ARRAY') {
		# Sometimes there are multiple mailboxes .. just use the first
		$cids = [ $cids->[0]->[0] ];
		}
	local $srcdir = &extract_plesk_cid($root, $cids, "mailbox");
	if ($srcdir) {
		local $srcfolder = { 'file' => $srcdir, 'type' => 1 };
		local $dstfolder = { 'file' => $crfile, 'type' => $crtype };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
		&set_mailfolder_owner($dstfolder, $uinfo);
		}

	$mcount++;
	}
&$second_print(".. done (migrated $mcount users)");

# Re-create mail aliases / catchall
local $acount = 0;
&$first_print("Re-creating mail aliases ..");
&set_alias_programs();
local $ca = $domain->{'mailsystem'}->{'preferences'}->{'catch-all'};
if ($ca) {
	local @to;
	if ($ca =~ /^bounce:(.*)/) {
		push(@to, "BOUNCE $1");
		}
	elsif ($ca eq "reject") {
		push(@to, "BOUNCE");
		}
	else {
		push(@to, $ca);
		}
	local $virt = { 'from' => "\@$dom",
			'to' => \@to };
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
	&disable_quotas(\%dom);
	foreach my $name (keys %$databases) {
		local $database = $databases->{$name};
		next if ($database->{'type'} ne 'mysql');

		# Create and import the DB
		&$indent_print();
		&create_mysql_database(\%dom, $name);
		&save_domain(\%dom, 1);
		local $cids = [ $database->{'content'}->{'cid'} ];
		local $sqldir = &extract_plesk_cid($root, $cids, "sqldump");
		local ($sqlfile) = glob("$sqldir/*$name*");
		&$first_print("Restoring database $name ..");
		if (!$sqlfile || !-f $sqlfile) {
			($sqlfile) = glob("$sqldir/backup_*");
			}
		if (!$sqldir) {
			&$second_print(".. no database content found");
			}
		elsif (!$sqlfile || !-f $sqlfile) {
			&$second_print(".. database content missing SQL file");
			}
		else {
			local ($ex, $out) = &execute_dom_sql_file(\%dom, $name,
								  $sqlfile);
			if ($ex) {
				&$second_print(".. error loading $db : $out");
				}
			else {
				&$second_print(".. done");
				}
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

	# Create DB users that are outside of databases
	local $dbusers = $domain->{'databases'}->{'dbusers'}->{'dbuser'};
	if (!$dbusers) {
		$dbusers = { };
		}
	elsif ($dbusers->{'name'}) {
		# Just one user
		$dbusers = { $dbusers->{'name'} => $dbusers };
		}
	foreach my $mname (keys %$dbusers) {
		my $dbuser = $dbusers->{$name};
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
			"$dom{'home'}/$config{'homes_dir'}/$mname";
		$myuinfo->{'shell'} = $nologin_shell->{'shell'};
		delete($myuinfo->{'email'});
		$myuinfo->{'dbs'} = [ map { { 'type' => 'mysql',
					      'name' => $_ } }
					  (keys %$databases) ];
		&create_user_home($myuinfo, \%dom, 1);
		&create_user($myuinfo, \%dom);
		&create_mail_file($myuinfo, \%dom);
		$taken{$myuinfo->{'uid'}}++;
		$myucount++;
		}

	&enable_quotas(\%dom);
	&$second_print(".. done (migrated $mcount databases, and created $myucount users)");
	}
&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

&sync_alias_virtuals(\%dom);

# Migrate protected directories as .htaccess files
local $pdir = $domain->{'phosting'}->{'preferences'}->{'pdir'};
if ($pdir && &foreign_check("htaccess-htpasswd")) {
	&$first_print("Re-creating protected directories ..");
	&foreign_require("htaccess-htpasswd");
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
		next if (!-d $dir);	# Protected dir is missing
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
local $aliasdoms = $domain->{'preferences'}->{'domain-alias'};
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
	if (&domain_name_clash($adom)) {
		&$second_print(".. the domain $adom already exists");
		next;
		}
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
			 'dns_ip', $dom{'dns_ip'},
			 'virt', 0,
			 'source', $dom{'source'},
			 'parent', $dom{'id'},
			 'template', $dom{'template'},
			 'reseller', $dom{'reseller'},
			 'nocreationmail', 1,
			 'nocopyskel', 1,
			 'nocreationscripts', 1,
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
	&generate_domain_password_hashes(\%alias, 1);
	&complete_domain(\%alias);
	&create_virtual_server(\%alias, $parentdom,
			       $parentdom->{'user'});
	&$outdent_print();
	&$second_print($text{'setup_done'});
	push(@rvdoms, \%alias);
	}

# Migrate sub-domains (as Virtualmin sub-servers)
local $subdoms;
if ($domain->{'phosting'}->{'sites'}) {
	$subdoms = $domain->{'phosting'}->{'sites'}->{'site'};
	}
else {
	$subdoms = $domain->{'phosting'}->{'subdomains'}->{'subdomain'};
	}
if (!$subdoms) {
	$subdoms = { };
	}
elsif ($subdoms->{'name'}) {
	# Just one sub-domain
	$subdoms = { $subdoms->{'name'} => $subdoms };
	}
foreach my $sdom (keys %$subdoms) {
	local $subdom = $subdoms->{$sdom};
	local $sname = $sdom;
	if ($sname !~ /\.\Q$dom{'dom'}\E$/) {
		$sname .= ".".$dom{'dom'};
		}
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
			'dns_ip', $dom{'dns_ip'},
			'virt', 0,
			'source', $dom{'source'},
			'template', $dom{'template'},
			'reseller', $dom{'reseller'},
			'nocreationmail', 1,
			'nocopyskel', 1,
			'nocreationscripts', 1,
			);
	foreach my $f (@subdom_features) {
		local $want = $f eq 'ssl' ? 0 : 1;
		$subd{$f} = $dom{$f} && $want;
		}
	local $parentdom = $dom{'parent'} ? &get_domain($dom{'parent'})
					  : \%dom;
	$subd{'home'} = &server_home_directory(\%subd, $parentdom);
	&generate_domain_password_hashes(\%subd, 1);
	&complete_domain(\%subd);
	&create_virtual_server(\%subd, $parentdom,
			       $parentdom->{'user'});
	&$outdent_print();
	&$second_print($text{'setup_done'});
	push(@rvdoms, \%subd);

	# Extract sub-domain's HTML directory
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%subd, 1);
		}
	local $hdir = &public_html_dir(\%subd);
	local $cids = $subdom->{'phosting'}->{'content'}->{'cid'} ||
		      $subdom->{'content'}->{'cid'};
	local $docroot_files = &extract_plesk_cid($root, $cids, "docroot");
	local $wwwroot = $subdom->{'phosting'}->{'www-root'};
	$wwwroot =~ s/^.*\///;
	if ($docroot_files) {
		&$first_print(
			"Copying web pages for sub-domain $subd{'dom'} ..");
		&copy_source_dest($docroot_files, $hdir);
		&set_home_ownership(\%subd);
		&$second_print(".. done");
		}
	elsif ($wwwroot && -d "$phdir/$wwwroot") {
		&$first_print(
			"Moving web pages for sub-domain $subd{'dom'} ..");
		&unlink_file_as_domain_user(\%subd, $hdir);
		&rename_as_domain_user(\%subd, "$phdir/$wwwroot", $hdir);
		&set_home_ownership(\%subd);
		&$second_print(".. done");
		}
	elsif (-d $user_data_files."/".$subd{'dom'}) {
		&$first_print(
			"Copying web pages for sub-domain $subd{'dom'} ..");
		&copy_source_dest($user_data_files."/".$subd{'dom'}, $hdir);
		&set_home_ownership(\%subd);
		&$second_print(".. done");
		}

	# Extract sub-domains CGI directory
	local $cdir = &cgi_bin_dir(\%subd);
	local $cgi_files = &extract_plesk_cid($root, $cids, "cgi");
	if ($cgi_files) {
		&$first_print(
			"Copying CGI scripts for sub-domain $subd{'dom'} ..");
		&copy_source_dest($cgi_files, $cdir);
		&set_home_ownership(\%subd);
		&$second_print(".. done");
		}
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable(\%subd, 0);
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
		local $pinfo = $mailuser->{'properties'}->{'password'} ||
			       $mailuser->{'password'};
		if ($pinfo->{'type'} eq 'plain') {
			$uinfo->{'plainpass'} = $pinfo->{'content'};
			$uinfo->{'pass'} = &encrypt_user_password(
						$uinfo, $uinfo->{'plainpass'});
			}
		else {
			$uinfo->{'pass'} = $pinfo->{'content'};
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

# Save original Plesk 8 XML file
&save_plesk_xml_files(\%dom, $xfile, $dump);

return (\%dom, @rvdoms);
}

# extract_plesk_dir(file, version)
# Extracts a Plesk 9 tar.gz file into a temporary directory
sub extract_plesk_dir
{
local ($file, $version) = @_;
local $dir;
if (-d $file) {
	# Already extracted, so just use the directory
	$dir = $file;
	}
else {
	if ($main::plesk_dir_cache{$file} &&
	    -d $main::plesk_dir_cache{$file}) {
		# Use cached extract from this session
		return (1, $main::plesk_dir_cache{$file});
		}
	$dir = &transname();
	&make_dir($dir, 0700);
	local $err = &extract_compressed_file($file, $dir);
	if ($err) {
		return (0, $err);
		}
	}
local ($disc) = glob("$dir/*/.discovered");
if ($disc =~ /\/([^\/]+)\/\.discovered$/) {
	# Plesk 11 appears to use a sub-directory
	$dir = "$dir/$1";
	}
$main::plesk_dir_cache{$file} = $dir;
return (1, $dir);
}

# extract_plesk_cid(basedir, &cids, type)
# Returns a temp dir containing the contents of some extracted Plesk content,
# or undef if not found
sub extract_plesk_cid
{
local ($basedir, $cids, $type) = @_;
local ($cid) = grep { $_->{'type'} eq $type } @$cids;
return undef if (!$cid || ref($cid) ne 'HASH');
my $cf = $cid->{'content-file'};
if (ref($cf) eq 'ARRAY') {
	$cf = $cf->[0];
	}
my $file = $basedir."/".$cid->{'path'}."/".$cf->{'content'};
if (!-r $file) {
	# Try path as seen on Plesk 11
	$file = $basedir."/".$cf->{'content'};
	}
-r $file || return undef;
local $dir = $main::extract_plesk_cid_cache{$file};
if (!$dir) {
	# Need to extract
	$dir = &transname();
	&make_dir($dir, 0700);
	my $err = &extract_compressed_file($file, $dir);
	return undef if ($err);
	$main::extract_plesk_cid_cache{$file} = $dir;
	}
return $cid->{'offset'} ? $dir."/".$cid->{'offset'} : $dir;
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
if ($ref->{'client'}) {
	# Expand <client> sub-object
 	$ref = $ref->{'client'};
	}
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

# save_plesk_xml_files(&domain, xmlfile, &xmldata)
# Called after a Plesk migration to save the original data files
sub save_plesk_xml_files
{
local ($d, $xmlfile, $xmldata) = @_;
local $etcdir = "$d->{'home'}/etc";
if (!-d $etcdir) {
	# Make sure ~/etc exists
 	&make_dir($etcdir, 0750);
	&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, undef, $etcdir);
	}
local $xmldump = "$etcdir/plesk.xml";
&copy_source_dest($xmlfile, $xmldump);
&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, 0700, $xmldump);
eval "use Data::Dumper";
if (!$@) {
	local $perldump = "$etcdir/plesk.perl";
	&open_tempfile(PERLDUMP, ">$perldump");
	&print_tempfile(PERLDUMP, Dumper($xmldata));
	&close_tempfile(PERLDUMP);
	&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, 0700, $perldump);
	}
}

1;

