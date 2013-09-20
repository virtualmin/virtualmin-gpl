# Functions for migrating a plesk backup. These appear to be in MIME format,
# with each part (home dir, settings, etc) in a separate 'attachment'

# migration_plesk_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is a Plesk backup, and contains the domain
sub migration_plesk_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_plesk_dir($file, 8);
$ok || return ("Not a Plesk 8 backup file : $root");
local $xfile = "$root/dump.xml";
local $windows = 0;
if (!-r $xfile) {
	$xfile = "$root/info.xml";
	$windows = 1;
	}
-r $xfile || return ("Not a complete Plesk 8 backup file - missing dump.xml or info.xml");

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

return (undef, $dom, $user, $pass);
}

# migration_plesk_migrate(file, domain, username, create-webmin, template-id,
#			  &ipinfo, pass, [&parent], [prefix], [email])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_plesk_migrate
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
local ($ok, $root) = &extract_plesk_dir($file, 8);
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
local @got = ( "dir", $parent ? () : ("unix") );
push(@got, "webmin") if ($webmin && !$parent);
if (exists($domain->{'mailsystem'}->{'status'}->{'enabled'}) ||
    $domain->{'mail'}) {
	push(@got, "mail");
	}
if ($domain->{'dns-zone'} || $domain->{'dns_zone'}) {
	push(@got, "dns");
	}
if ($domain->{'www'} eq 'true' || -d "$root/$dom/httpdocs" ||
    $domain->{'www'} && (-r "$root/$dom.httpdocs" || -r "$root/$dom.htdocs")) {
	push(@got, "web");
	}
if ($domain->{'ip'}->{'ip-type'} eq 'exclusive' && $virt) {
	push(@got, "ssl");
	}
if ($domain->{'phosting'}->{'logrotation'}->{'enabled'} eq 'true' ||
    $windows && &indexof("web", @got) >= 0) {
	push(@got, "logrotate");
	}
if ($domain->{'phosting'}->{'webalizer'} &&
    &indexof("web", @got) >= 0) {
	push(@got, "webalizer");
	}

# Check for MySQL databases
local $sapp = $domain->{'phosting'}->{'sapp-installed'};
local $databases = ref($sapp) eq 'HASH' ? $sapp->{'database'} : undef;
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

# Copy web files
&$first_print("Copying web pages ..");
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 1);
	}
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
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 0);
	}

# Re-create DNS records
local $oldip = $domain->{'ip'}->{'ip-address'};
if ($got{'dns'}) {
	&$first_print("Copying and fixing DNS records ..");
	local $zonexml = $domain->{'dns-zone'};
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
				&bind8::create_record($file,
						      $recname,
						      undef,
						      "IN",
						      $rectype,
						      $recvalue);
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
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mcount = 0;
# Linux mailboxes
foreach my $name (keys %$mailusers) {
	next if ($windows);
	local $mailuser = $mailusers->{$name};
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name(lc($name), \%dom);
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
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($name);
	$uinfo->{'shell'} = $nologin_shell->{'shell'};
	$uinfo->{'to'} = [ ];
	if ($mailuser->{'mailbox'}->{'enabled'} eq 'true') {
		# Add delivery to user's mailbox
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
		local $q = $mailuser->{'mailbox-quota'} < 0 ? undef :
				$mailuser->{'mailbox-quota'}*1024;
		$uinfo->{'qquota'} = $q;
		$uinfo->{'quota'} = $q / &quota_bsize("home");
		$uinfo->{'mquota'} = $q / &quota_bsize("home");
		}
	# Add mail aliases
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
	$uinfo->{'user'} = &userdom_name(lc($name), \%dom);
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
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($name);
	$uinfo->{'shell'} = $nologin_shell->{'shell'};
	$uinfo->{'email'} = lc($name)."\@".$dom;
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
	&create_user_home($uinfo, \%dom, 1);
	&create_user($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);

	# Convert windows-style mail files
	local $mfile = $mailuser->{'dump'}->{'arcname'};
	local $mpath = "$root/$mfile";
	if ($mfile && -d $mpath) {
		# Rename to MH format
		opendir(MAILDIR, $mpath);
		my @mfiles = grep { /\.MAI/i } readdir(MAILDIR);
		closedir(MAILDIR);
		my $i = 1;
		foreach my $f (@mfiles) {
			rename("$mpath/$f", "$mpath/$i");
			$i++;
			}

		# Copy MH format
		local $srcfolder = { 'file' => $mpath, 'type' => 3, };
		local $dstfolder = { 'file' => $crfile, 'type' => $crtype };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
		&set_mailfolder_owner($dstfolder, $uinfo);
		}

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
	&disable_quotas(\%dom);
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
	&generate_domain_password_hashes(\%alias, 1);
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

# Save original Plesk 8 XML file
&save_plesk_xml_files(\%dom, $xfile, $dump);

return (\%dom, @rvdoms);
}

# extract_plesk_dir(file, version)
# Extracts all attachments from a plesk backup in MIME format to a temp
# directory, and returns the path. Version can be one of 7 or 8
sub extract_plesk_dir
{
local ($file, $version) = @_;
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
	# Read the backup file, parsing it into files as we go
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

	# Read base mail headers
	local %baseheaders;
	while(<FILE>) {
		s/\r|\n//g;
		if (/^(\S+):\s+(.*)/) {
			$baseheaders{lc($1)} = $2;
			}
		else {
			last;
			}
		}
	$baseheaders{'content-type'} =~ /boundary\s*=\s*"([^"]+)"/i ||
	    $baseheaders{'content-type'} =~ /boundary\s*=\s*(\S+)/i ||
		return (0, "Missing Content-Type boundary");
	local $bound = $1;
	if ($baseheaders{'dumped-psa-version'} =~ /^7\./ && $version == 8) {
		return (0, "This is a Plesk 7 backup, which uses a different format. You must use the Plesk 7 (psa) migration type");
		}
	elsif ($baseheaders{'dumped-psa-version'} !~ /^7\./ && $version == 7) {
		return (0, "This is a Plesk 8 backup, which uses a different format. You must use the Plesk 8 (plesk) migration type");
		}

	# Skip to start of first section
	local $lnum = 0;
	while(<FILE>) {
		$lnum++;
		s/\r|\n//g;
		last if ($_ eq "--".$bound);
		}

	# Read sections in turn
	local $alldone = 0;
	local $count = 0;
	while(!$alldone) {
		# Headers first
		local %sheaders;
		while(<FILE>) {
			$lnum++;
			s/\r|\n//g;
			if (/^(\S+):\s+(.*)/) {
				$sheaders{lc($1)} = $2;
				}
			else {
				last;
				}
			}
		local $cd = $sheaders{'content-disposition'};
		local $ct = $sheaders{'content-type'};
		local $filename;
		if ($version == 8) {
			# For Plesk 8, each section has a filename that we can
			# use later to refer to them
			if ($cd =~ /filename\s*=\s*"([^"]+)"/i || 
			    $cd =~ /filename\s*=\s*(\S+)/i) {
				$filename = $1;
				}
			elsif ($cd =~ /name\s*=\s*"([^"]+)"/i || 
			       $cd =~ /name\s*=\s*(\S+)/i) {
				$filename = $1;
				}
			if ($sheaders{'content-type'} =~
				/boundary\s*=\s*"([^"]+)"/i ||
			    $sheaders{'content-type'} =~
				/boundary\s*=\s*(\S+)/i) {
				# Start of a new multi-part section, such as
				# when the backup is signed
				$bound = $1;
				while(<FILE>) {
					$lnum++;
					last if (/\S/);
					}
				next;
				}
			$filename ||
				return (0, "Missing filename at line $lnum");
			}
		elsif ($version == 7) {
			# For Plesk 7, sections have a content ID apart from the
			# XML file
			if ($ct =~ /^text\/xml/) {
				$filename = "dump.xml";
				}
			else {
				$filename = $sheaders{'content-id'};
				}
			$filename ||
				return (0, "Missing content ID at line $lnum");
			}
		local $enc = $sheaders{'content-transfer-encoding'} || 'binary';

		# Read body till the boundary end
		&open_tempfile(ATTACH, ">$dir/$filename", 0, 1);
		while(<FILE>) {
			$lnum++;
			if ($_ eq "--".$bound."\n" ||
			    $_ eq "--".$bound."\r\n") {
				# End of this block
				last;
				}
			elsif ($_ eq "--".$bound."--\n" ||
			       $_ eq "--".$bound."--\r\n") {
				# End of the whole mess
				$alldone = 1;
				last;
				}
			if ($enc eq 'binary' || $enc eq '7bit') {
				&print_tempfile(ATTACH, $_);
				}
			elsif ($enc eq 'base64') {
				&print_tempfile(ATTACH,
					&mailboxes::b64decode($_));
				}
			elsif ($enc eq 'quoted-printable') {
				&print_tempfile(ATTACH,
					&mailboxes::quoted_decode($_));
				}
			else {
				return (0,
				  "Unknown encoding $enc at line $lnum");
				}
			}
		&close_tempfile(ATTACH);
		$count++;
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

