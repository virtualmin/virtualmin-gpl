# Functions for migrating an ensim backup

# migration_ensim_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is an ensim backup, and contains the domain
sub migration_ensim_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;

# Validate file
local ($ok, $root) = &extract_ensim_dir($file);
$ok || return ("Not an Ensim tar.gz file : $root");
local $www = "$root/var/www";
-d $www || return ("Not an Ensim backup file");

# Check XML file and domain
local $manifest;
eval { $manifest = &parse_enim_xml($root); };
if ($@) {
	&error("$@");
	}
if (!$dom) {
	# Work out domain name
	$dom = $manifest->{'siteIdent'}->{'sitename'};
	$dom || return ("Could not work out domain name from backup");
	}
else {
	$manifest->{'siteIdent'}->{'sitename'} eq $dom ||
		return ("Backup is for domain $manifest->{'siteIdent'}->{'sitename'}, not $dom");
	}

# Check if we can work out the user
if (!$parent && !$user) {
	local $service = $manifest->{'siteIdent'}->{'service'};
	local ($si) = grep { $_->{'serviceName'} eq 'siteinfo' } @$service;
	$user = $si->{'config'}->{'admin_user'};
	$user || return ("Could not work out original username from backup");
	}

return (undef, $dom, $user, $pass);
}

# migration_ensim_migrate(file, domain, username, create-webmin, template-id,
#			  ip-address, virtmode, pass, [&parent], [prefix],
#			  virt-already, netmask)
# Actually extract the given ensim backup, and return the list of domains
# created.
sub migration_ensim_migrate
{
local ($file, $dom, $user, $webmin, $template, $ip, $virt, $pass, $parent,
       $prefix, $virtalready, $defemail, $netmask) = @_;
local ($ok, $root) = &extract_ensim_dir($file);

# Check for prefix clash
$prefix ||= &compute_prefix($dom, undef, $parent, 1);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && &error("A virtual server using the prefix $prefix already exists");

# Get the manifest and some useful info from it
local $manifest = &parse_enim_xml($root);
local $service = $manifest->{'siteIdent'}->{'service'};
local ($si) = grep { $_->{'serviceName'} eq 'siteinfo' } @$service;
local $origuser = $si->{'config'}->{'admin_user'};
$user ||= $origuser;
local $group;
if ($user eq $si->{'config'}->{'admin_user'}) {
	# If username was automatically detected, stick to group from backup
	$group = $manifest->{'userIdent'}->{'group'};
	}
$group ||= $user;
local $ugroup = $group;

# Get shells for users
local ($nologin_shell, $ftp_shell, undef, $def_shell) =
	&get_common_available_shells();
$nologin_shell ||= $def_shell;
$ftp_shell ||= $def_shell;

# First work out what features we have ..
&$first_print("Checking for Ensim features ..");
local $service = $manifest->{'siteIdent'}->{'service'};
local @got = ( "dir", $parent ? () : ("unix") );
push(@got, "webmin") if ($webmin && !$parent);
foreach my $sm ([ "logrotate", "logrotate" ],
		[ "bind", "dns" ],
		[ "sendmail", "mail" ],
		[ "apache", "web" ],
		[ "anonftp", "ftp" ],
		[ "spam_filter", "spam" ],
		[ "majordomo", "virtualmin-mailman" ],
		[ "mysql", "mysql" ],
		[ "webalizer", "webalizer" ]) {
	local ($cs) = grep { $_->{'serviceName'} eq $sm->[0] } @$service;
	if ($cs && $cs->{'config'}->{'enabled'}) {
		push(@got, $sm->[1]);
		}
	}

# Don't enable logrotate if no Apache
if (&indexof("web", @got) < 0) {
	@got = grep { $_ ne "logrotate" } @got;
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
	# IDs are allocated by setup_unix
	$gid = $ugid = $uid = undef;
	$duser = $user;
	}

# Extract quota
local $quota;
local ($qc) = grep { $_->{'serviceName'} eq 'diskquota' } @$service;
if ($qc) {
	if ($qc->{'config'}->{'enabled'}) {
		$quota = $qc->{'config'}->{'quota'};
		local $qu = uc($qc->{'config'}->{'units'});
		$quota *= ($qu eq "GB" ? 1024*1024*1024 :
			   $qu eq "MB" ? 1024*1024 :
			   $qu eq "KB" ? 1024 : 1);
		$quota /= &quota_bsize("home");
		}
	else {
		$quota = 0;
		}
	}

# Extract bandwidth limit
local ($bw) = grep { $_->{'serviceName'} eq 'bandwidth' } @$service;
local $bw_limit = !$bw ? undef :
		  !$bw->{'config'}->{'enabled'} ? 0 :
		 	$bw->{'config'}->{'threshold'};

# Extract email address
local ($si) = grep { $_->{'serviceName'} eq 'siteinfo' } @$service;
local $email = $si ? $si->{'config'}->{'email'} : undef;

# Extract encrypted password
local $userident = $manifest->{'userIdent'}->{$origuser};
if (!$userident) {
	# There are no extra users .. everything is directly under userIdent
	$userident = $manifest->{'userIdent'};
	}
local $userservice = $userident->{'service'};
local ($uu) = grep { $_->{'serviceName'} eq 'users' } @$userservice;
local $encpass;
if ($uu) {
	$encpass = $uu->{'config'}->{'password'};
	}
$parent || $encpass || $pass ||
	&error("No encrypted password was found in the Ensim backup, ".
	       "and no password was provided");

# Find original IP address
local ($ii) = grep { $_->{'serviceName'} eq 'ipinfo' } @$service;
local $oldip = $ii ? $ii->{'config'}->{'nbaddr'} : undef;

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
         'owner', "Migrated Ensim server $dom",
         'email', $defemail ? $defemail : $parent ? $parent->{'email'} : $email,
         'name', !$virt,
         'ip', $ip,
         'netmask', $netmask,
	 'dns_ip', $virt || $config{'all_namevirtual'} ? undef :
		   &get_dns_ip($parent ? $parent->{'id'} : undef),
         'virt', $virt,
         'virtalready', $virtalready,
	 $parent ? ( 'pass', $parent->{'pass'} )
		 : ( 'pass', $pass,
		     'enc_pass', $encpass,
		     'hashpass', $pass ? 0 : 1 ),
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
if (!$parent) {
	&set_limits_from_plan(\%dom, $plan);
	if (defined($quota)) {
		$dom{'quota'} = $dom{'uquota'} = $quota;
		}
	if (defined($bw_limit)) {
		$dom{'bw_limit'} = $bw_limit;
		}
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

# Set MySQL login and password
local ($mc) = grep { $_->{'serviceName'} eq 'mysql' } @$service;
if ($mc && $mc->{'DbaseAdmin'}->{'DbAdminName'}) {
	$dom{'mysql_user'} = $mc->{'DbaseAdmin'}->{'DbAdminName'};
	$dom{'mysql_enc_pass'} = $mc->{'DbaseAdmin'}->{'DbaseAdminPwd'};
	}

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

# Migrate DNS domain, by re-creating records in the original XML that don't
# exist in the new domain, but with fixed IPs.
if ($got{'dns'} && $si->{'config'}->{'zone'}) {
	&$first_print("Copying and fixing DNS records ..");
	&require_bind();
	local @srcrecs = @{$si->{'config'}->{'zone'}->{'record'}};
	local ($recs, $file) = &get_domain_dns_records_and_file(\%dom);
	local %got = map { $_->{'name'}, $_ } @$recs;
	local $count = 0;
	foreach my $rec (@srcrecs) {
		if (!$got{$rec->{'owner'}}) {
			if ($rec->{'address'} eq $oldip) {
				$rec->{'address'} = $ip;
				}
			&bind8::create_record(
				$file, $rec->{'owner'}, $rec->{'ttl'},
				$rec->{'class'}, $rec->{'type'},
				$rec->{'address'} || 
				  $rec->{'exchange_dname'} ||
				  $rec->{'name_server_dname'} ||
				  $rec->{'alias'});
			$count++;
			}
		}
	&post_records_change(\%dom, $recs, $file);
	&$second_print(".. added $count records");
	&register_post_action(\&restart_bind);
	}

# Migrate web directory contents
local $webdir = &public_html_dir(\%dom);
local $websrc = "$root/var/www/html";
&$first_print("Copying web pages to $webdir ..");
local $qwebdir = quotemeta($webdir);
local $qwebsrc = quotemeta($websrc);
local $out;
&execute_command("cd $qwebsrc && (".
		 &make_tar_command("cvf", "-", ".").
		 " | (cd $qwebdir && ".
		 &make_tar_command("xf", "-")."))",
		 undef, \$out, \$out);
if ($?) {
	&$second_print(".. copy failed : <tt>$out</tt>");
	}
else {
	&$second_print(".. done");
	}

# Migrate cgi-bin contents
local $cgidir = &cgi_bin_dir(\%dom);
local $cgisrc = "$root/var/www/cgi-bin";
&$first_print("Copying CGI programs to $cgidir ..");
if (!-d $cgisrc) {
	&$second_print(".. not found in backup");
	}
else {
	local $qcgidir = quotemeta($cgidir);
	local $qcgisrc = quotemeta($cgisrc);
	local $out;
	&execute_command(
		"cd $qcgisrc && (".
		&make_tar_command("cvf", "-", ".").
		" | (cd $qcgidir && ".
		&make_tar_command("xf", "-")."))",
		undef, \$out, \$out);
	if ($?) {
		&$second_print(".. copy failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Fix up ownership and permissions
&$first_print("Fixing home directory permissions ..");
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 1);
	}
&set_home_ownership(\%dom);
&system_logged("chmod '$uconfig{'homedir_perms'}' ".
	       quotemeta($dom{'home'}));
foreach my $sd (&virtual_server_directories(\%dom)) {
	&system_logged("chmod $sd->[1] ".
		       quotemeta("$dom{'home'}/$sd->[0]"));
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable(\%dom, 0);
	}
&$second_print(".. done");

# Re-create and import MySQL databases. This is done by looking in the backup
# dir specified in the XML for .mysql.dmp files
if ($got{'mysql'}) {
	&$first_print("Re-creating and loading MySQL databases ..");
	&disable_quotas(\%dom);
	local ($mc) = grep { $_->{'serviceName'} eq 'mysql' } @$service;
	local $mydir = "$root/var/lib/mysql/".$mc->{'DbaseAdmin'}->{'TmpPath'};
	local $prefix = $mc->{'DbaseAdmin'}->{'DbasePrefix'};
	local $mycount = 0;
	opendir(MYDIR, $mydir);
	foreach my $myf (readdir(MYDIR)) {
		next if ($myf !~ /^(\Q$prefix\E\S+)\.mysql\.dmp$/);
		local $db = $1;
		&$indent_print();
		&create_mysql_database(\%dom, $db);
		&save_domain(\%dom, 1);
		local ($ex, $out) = &mysql::execute_sql_file($db,"$mydir/$myf");
		if ($ex) {
			&$first_print("Error loading $db : $out");
			}
		&$outdent_print();
		$mycount++;
		}
	&enable_quotas(\%dom);
	&$second_print(".. done (created $mycount)");
	}

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

# Migrate mail users (if there are any)
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $usercount = 0;
local $userident = $manifest->{'userIdent'};
if ($userident->{$origuser}) {
	&$first_print("Copying mail/FTP users ..");
	foreach my $mu (keys %$userident) {
		next if ($mu eq $user);
		local $userservice = $userident->{$mu}->{'service'};
		local ($uu) = grep { $_->{'serviceName'} eq 'users' }
				   @$userservice;
		local ($qu) = grep { $_->{'serviceName'} eq 'diskquota' }
				   @$userservice;
		next if (!$uu);

		# Create the extra user
		local $uinfo = &create_initial_user(\%dom);
		$uinfo->{'user'} = lc($mu).'@'.$dom;
		$uinfo->{'pass'} = $uu->{'config'}->{'password'};
		$uinfo->{'uid'} = &allocate_uid(\%taken);
		$uinfo->{'gid'} = $dom{'gid'};
		$uinfo->{'real'} = $uu->{'config'}->{'fullname'};
		$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($mu);
		$uinfo->{'shell'} = $nologin_shell->{'shell'};
		$uinfo->{'email'} = lc($mu).'@'.$dom;
		if ($qu) {
			$uinfo->{'quota'} = $uinfo->{'mquota'} =
			  $uinfo->{'qquota'} =
			    $qu->{'config'}->{'quota'} / &quota_bsize("home");
			}
		&create_user_home($uinfo, \%dom, 1);
		&create_user($uinfo, \%dom);
		$taken{$uinfo->{'uid'}}++;

		# Move his mail file
		local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);
		local $srcfolder = { 'type' => 0,
				     'file' => "$root/var/spool/mail/$mu" };
		local $dstfolder = { 'type' => $crtype,
				     'file' => $crfile };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);

		# Copy his home directory contents, and set ownership
		local $homesrc = "$root/home/$mu";
		local $qhomesrc = quotemeta($homesrc);
		local $qhomedest = quotemeta($uinfo->{'home'});
		&execute_command(
		    "cd $qhomesrc && (".
		    &make_tar_command("cvf", "-", ".").
		    " | (cd $qhomedest && ".
		    &make_tar_command("xf", "-")."))",
		    undef, \$out, \$out);
		&execute_command(
		  "chown -R $uinfo->{'uid'}:$uinfo->{'gid'} $qhomedest",
		  undef, \$out, \$out);

		# Copy his ~/mail folders, if that isn't already the location
		# for mail folders
		local $mailsrc = "$uinfo->{'home'}/mail";
		local $sfdir = $mailboxes::config{'mail_usermin'};
		local $sftype = $sfdir eq 'Maildir' ? 1 : 0;
		if ($sfdir ne "mail") {
			opendir(DIR, $mailsrc);
			while(my $mf = readdir(DIR)) {
				next if ($mf eq "." || $mf eq "..");
				local $srcfolder = { 'type' => 0,
					'file' => "$maildir/$mf" };
				next if (-d $srcfolder->{'file'});
				local $dstfolder = { 'type' => $sftype,
					'file' => "$uinfo->{'home'}/$sfdir/" };
				if ($sftype == 0) {
					$dstfolder->{'file'} .= $mf;
					}
				else {
					$dstfolder->{'file'} .= ".".$mf;
					}
				&mailboxes::mailbox_move_folder($srcfolder,
								$dstfolder);
				&set_mailfolder_owner($dstfolder, $uinfo);
				}
			closedir(DIR);
			}
		$usercount++;
		}
	&$second_print(".. done (created $usercount)");
	}
&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

# Move server owner's inbox file
local $owner = &get_domain_owner(\%dom);
if (!$parent && -r "$root/var/spool/mail/$origuser") {
	&$first_print("Moving server owner's mailbox ..");
	local ($mfile, $mtype) = &create_mail_file($owner, \%dom);
	if ($mfile) {
		local $srcfolder = { 'type' => 0,
				     'file' => "$root/var/spool/mail/$origuser" };
		local $dstfolder = { 'type' => $mtype,
				     'file' => $mfile };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
		&$second_print(".. done");
		}
	else {
		&$second_print(".. could not work out mail file");
		}
	}

if ($got{'mail'}) {
	# Copy mail aliases
	local $acount = 0;
	&$first_print("Copying email aliases ..");
	&set_alias_programs();
	&foreign_require("sendmail", "sendmail-lib.pl");
	&foreign_require("sendmail", "aliases-lib.pl");
	local @srcaliases = &sendmail::list_aliases([ "$root/etc/aliases" ]);
	local %already = map { $_->{'from'}, $_ } &list_virtusers();
	foreach my $src (@srcaliases) {
		local $n = $src->{'name'};
		$n = "" if ($n eq "catch-all");
		next if ($n eq "majordomo");	# Not used by Virtualmin
		local @to;
		foreach my $t (@{$src->{'values'}}) {
			local ($atype, $adest) = &alias_type($t);
			if ($atype == 1 && $adest !~ /\@/) {
				# Convert unqualified address to this domain
				push(@to, $t.'@'.$dom{'dom'});
				}
			else {
				push(@to, $t);
				}
			}
		local $virt = { 'from' => $n.'@'.$dom{'dom'},
				'to' => \@to,
			      };
		next if ($already{$virt->{'from'}}++);
		&create_virtuser($virt);
		$acount++;
		}
	&$second_print(".. done (migrated $acount aliases)");
	}

if ($parent) {
	# Re-save parent user, to update Webmin ACLs
	&refresh_webmin_user($parent);
	}

&sync_alias_virtuals(\%dom);
return (\%dom);
}

# extract_ensim_dir(file)
# Extracts a tar.gz file, and returns a a status code and the directory under
# which it was extracted or an error message
sub extract_ensim_dir
{
local ($file) = @_;
local $dir;
if (!-e $file) {
	return (0, "File does not exist");
	}
elsif (-d $file) {
	# Extract extracted
	$dir = $file;
	}
else {
	if ($main::ensim_dir_cache{$file} &&
	    -d $main::ensim_dir_cache{$file}) {
		# Use cached extract from this session
		return (1, $main::ensim_dir_cache{$file});
		}
	$dir = &transname();
	mkdir($dir, 0700);
	local $qf = quotemeta($file);
	local $out = &backquote_command(
		"cd $dir && ".&make_tar_command("xzf", $qf)." 2>&1");
	if ($? && $out !~ /decompression\s+OK/i) {
		return (0, $out);
		}
	$main::ensim_dir_cache{$file} = $dir;
	}
return (1, $dir);
}

# parse_enim_xml(dir)
# Read an Ensim XML manifest file and convert it to a hash. Dies if the XML
# file cannot be read.
sub parse_enim_xml
{
local ($dir) = @_;
local ($xfile) = glob("$dir/export.xml*");
-r $xfile || die "Backup does not contain an export.xml file";
eval "use XML::Simple";
$@ && die "Perl module XML::Simple needed to parse the Ensim backup manifest is not installed";
my $xs = XML::Simple->new();
my $ref = $xs->XMLin($xfile);
$ref || die "Failed to read export.xml file";
return $ref;
}

1;

