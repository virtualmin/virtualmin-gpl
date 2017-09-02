# Functions for migrating a DirectAdmin backup

# migration_directadmin_validate(file, domain, [user], [&parent],
# 				 [prefix], [pass])
# Make sure the given file is a cPanel backup, and contains the domain
sub migration_directadmin_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_directadmin_dir($file);
$ok || return ("Not a DirectAdmin tar.gz file : $root");
local $domains = "$root/domains";
local $backup = "$root/backup";
-d $domains && -d $backup || return ("Not a DirectAdmin backup file");

if (!$dom) {
	# Try to work out the domain
	local @domdirs = grep { !/\/default$/ } glob("$domains/*");
	@domdirs || return ("No domains found in backup");
	$domdirs[0] =~ /\/([^\/]+)$/;
	$dom = $1;
	}
else {
	# Validate the domain
	-d "$domains/$dom" || return ("Backup does not contain domain $dom");
	}

# If no username was given, use the default
if (!$user) {
	local %uinfo;
	&read_env_file("$backup/user.conf", \%uinfo) ||
		return ("$backup/user.conf not found!");
	$user = $uinfo{'username'};
	}

# Password is needed for DirectAdmin migrations
if (!$parent && !$pass) {
	return ("A password must be supplied for DirectAdmin migrations");
	}

return (undef, $dom, $user, $pass);
}

# migration_directadmin_migrate(file, domain, username, create-webmin,
# 				template-id, &ipinfo, pass, [&parent],
# 				[prefix], [email])
# Actually extract the given cPanel backup, and return the list of domains
# created.
sub migration_directadmin_migrate
{
local ($file, $dom, $user, $webmin, $template, $ipinfo, $pass, $parent,
       $prefix, $email) = @_;
local ($ok, $root) = &extract_directadmin_dir($file);
$ok || return ("Not a DirectAdmin tar.gz file : $root");
local $domains = "$root/domains";
local $backup = "$root/backup";
-d $domains && -d $backup || return ("Not a DirectAdmin backup file");
local $tmpl = &get_template($template);

# Check for prefix clash
$prefix ||= &compute_prefix($dom, undef, $parent, 1);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && &error("A virtual server using the prefix $prefix already exists");

# Get shells for users
local ($nologin_shell, $ftp_shell, undef, $def_shell) =
	&get_common_available_shells();
$nologin_shell ||= $def_shell;
$ftp_shell ||= $def_shell;

# Work out the username again if it wasn't supplied
local %uinfo;
&read_env_file("$backup/user.conf", \%uinfo) ||
	&error("$backup/user.conf not found!");
local $origuser = $uinfo{'username'};
$user ||= $origuser;
$user || &error("Could not work out username automatically");
local $group = $user;
local $ugroup = $group;
local %dinfo;
&read_env_file("$backup/$dom/domain.conf", \%dinfo) ||
	&error("$backup/$dom/domain.conf not found!");

# First work out what features we have ..
&$first_print("Checking for DirectAdmin features ..");
local @got = ( "dir", $parent ? () : ("unix"), "web", "logrotate" );
push(@got, "webmin") if ($webmin && !$parent);
local @sqlfiles = glob("$backup/*.sql");
if (@sqlfiles) {
	push(@got, "mysql");
	}
local $zonefile = "$backup/$dom/$dom.db";
if (-r $zonefile) {
	push(@got, "dns");
	}
if (-r "$domains/$dom/stats/webalizer.current") {
	push(@got, "webalizer");
	}
if (-r "$backup/$dom/email/aliases") {
	push(@got, "mail");
	}
if (uc($dinfo{'ssl'}) eq 'ON') {
	push(@got, "ssl");
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
	$uid = $gid = $ugid = undef;
	$duser = $user;
	}

# Work out quota
local $quota;
local $bsize = &quota_bsize("home");
$bsize ||= 1024;
if ($uinfo{'quota'} && $uinfo{'quota'} ne 'unlimited') {
	# Assume in MB
	$quota = $uinfo{'quota'} * 1024 * 1024 / $bsize;
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
         'owner', "Migrated DirectAdmin server $dom",
         'email', $email ? $email :
		  $parent ? $parent->{'email'} :
			    $uinfo{'email'},
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
	 'nocreationscripts', 1,
	 'parent', $parent ? $parent->{'id'} : undef,
        );
$dom{'home'} = &server_home_directory(\%dom, $parent);
&merge_ipinfo_domain(\%dom, $ipinfo);
if (!$parent) {
	&set_limits_from_plan(\%dom, $plan);
	$dom{'quota'} = $quota;
	$dom{'uquota'} = $quota;
	$dom{'bw_limit'} = $uinfo{'bandwidth'} * 1024 * 1024;
	&set_capabilities_from_plan(\%dom, $plan);
	}
$dom{'db'} = &database_name(\%dom);
foreach my $f (@features, &list_feature_plugins()) {
	$dom{$f} = $got{$f} ? 1 : 0;
	}
&set_featurelimits_from_plan(\%dom, $plan);

# Set cgi directories to DirectAdmin standard
$dom{'cgi_bin_dir'} = "public_html/cgi-bin";
$dom{'cgi_bin_path'} = "$dom{'home'}/$dom{'cgi_bin_dir'}";
$dom{'cgi_bin_correct'} = 1;	# So that setup_web doesn't fix it

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
local @rvdoms = ( \%dom );

# Copy over public_html dir
local $phd = &public_html_dir(\%dom);
local $phdsrc = "$domains/$dom/public_html";
if (-d $phdsrc) {
	&$first_print("Copying public_html directory ..");
	&execute_command("cd ".quotemeta($phdsrc)." && ".
			 &make_tar_command("cf", "-", ".")." | ".
			 "(cd ".quotemeta($phd)." && ".
			   &make_tar_command("xf", "-").")",
			 undef, \$out, \$out);
	if ($?) {
		&$second_print(".. copy failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Copy over private_html dir
local $phd = "$dom{'home'}/private_html";
local $phdsrc = "$domains/$dom/private_html";
if (-d $phdsrc) {
	&$first_print("Copying private_html directory ..");
	&make_dir_as_domain_user(\%dom, $phd, 0700);
	&execute_command("cd ".quotemeta($phdsrc)." && ".
			 &make_tar_command("cf", "-", ".")." | ".
			 "(cd ".quotemeta($phd)." && ".
			   &make_tar_command("xf", "-").")",
			 undef, \$out, \$out);
	if ($?) {
		&$second_print(".. copy failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Copy over stats directory
local $stats = &webalizer_stats_dir(\%dom);
local $statssrc = "$domains/$dom/stats";
if (-d $statssrc && $dom{'webalizer'}) {
	&$first_print("Copying stats directory ..");
	&execute_command("cd ".quotemeta($statssrc)." && ".
			 &make_tar_command("cf", "-", ".")." | ".
			 "(cd ".quotemeta($stats)." && ".
			   &make_tar_command("xf", "-").")",
			 undef, \$out, \$out);
	if ($?) {
		&$second_print(".. copy failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Copy over public_ftp directory
local $ftp = $dom{'home'}.'/'.($tmpl->{'ftp_dir'} || 'ftp');
local $ftpsrc = "$domains/$dom/public_ftp";
if (-d $ftpsrc) {
	&$first_print("Copying public_ftp directory ..");
	if (!-d $ftp) {
		&make_dir($ftp, 0755);
		&set_ownership_permissions($dom{'uid'}, $dom{'ugid'}, 0755, $ftp);
		}
	&execute_command("cd ".quotemeta($ftpsrc)." && ".
			 &make_tar_command("cf", "-", ".")." | ".
			 "(cd ".quotemeta($ftp)." && ".
			   &make_tar_command("xf", "-").")",
			 undef, \$out, \$out);
	if ($?) {
		&$second_print(".. copy failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Fix home permissions
&set_home_ownership(\%dom);

if ($got{'web'}) {
	# Just adjust cgi-bin directory to match DirectAdmin
	local $conf = &apache::get_config();
	local ($virt, $vconf) = &get_apache_virtual($dom, undef);
	if ($virt) {
		&apache::save_directive("ScriptAlias",
			[ "/cgi-bin $dom{'home'}/public_html/cgi-bin" ],
			$vconf, $conf);
		&flush_file_lines($virt->{'file'});
		&register_post_action(\&restart_apache) if (!$got{'ssl'});
		}
	&save_domain(\%dom);
	&add_script_language_directives(\%dom, $tmpl, $dom{'web_port'});
	}
$dom{'cgi_bin_correct'} = 0;	# So that it is computed from now on

# Migrate DNS domain
local $dnsfile = "$backup/$dom/$dom.db";
if ($got{'dns'} && -r $dnsfile) {
	&$first_print("Copying and fixing DNS records ..");
	&require_bind();
	local $zonefile = &get_domain_dns_file(\%dom);
	&copy_source_dest($dnsfile, &bind8::make_chroot($zonefile));
	local ($recs, $zdstfile) =
		&get_domain_dns_records_and_file(\%dom);
	foreach my $r (@$recs) {
		my $change = 0;
		if (($r->{'name'} eq $dom."." ||
		     $r->{'name'} eq "www.".$dom."." ||
		     $r->{'name'} eq "pop.".$dom."." ||
		     $r->{'name'} eq "smtp.".$dom."." ||
		     $r->{'name'} eq "cp.".$dom."." ||
		     $r->{'name'} eq "ftp.".$dom."." ||
		     $r->{'name'} eq "mail.".$dom.".") &&
		    $r->{'type'} eq 'A') {
			# Fix IP in domain record
			$r->{'values'} = [ $dom{'ip'} ];
			$change++;
			}
		elsif ($r->{'name'} eq $dom."." &&
		       $r->{'type'} eq 'NS') {
			# Set NS record to this server
			local $master = $bconfig{'default_prins'} ||
					&get_system_hostname();
			$master .= "." if ($master !~ /\.$/);
			$r->{'values'} = [ $master ];
			$change++;
			}
		elsif ($r->{'name'} eq $dom."." &&
		       ($r->{'type'} eq 'SPF' ||
			$r->{'type'} eq 'TXT') &&
		    $r->{'values'}->[0] =~ /ip4:/) {
			# Fix IP in SPF record
			$r->{'values'}->[0] =~ s/ip4:([0-9\.]+)/ip4:$dom{'ip'}/;
			$change++;
			}
		if ($change) {
			&bind8::modify_record(
				$zdstfile, $r, $r->{'name'},
				$r->{'ttl'}, $r->{'class'},
				$r->{'type'},
				&join_record_values($r),
				$r->{'comment'});
			}
		}
	&post_records_change(\%dom, $recs, $zdstfile);
	&$second_print(".. done");
	&register_post_action(\&restart_bind);
	}

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

&foreign_require("mailboxes");
$mailboxes::no_permanent_index = 1;
local %usermap;
if ($got{'mail'}) {
	# Migrate mail users
	local $mcount = 0;
	&$first_print("Re-creating mail users ..");
	&foreign_require("mailboxes");
	my $lref = &read_file_lines("$backup/$dom/email/quota", 1);
	foreach my $l (@$lref) {
		my ($user, $quota) = split(/:/, $l);
		if ($user && $quota =~ /^\d+$/) {
			$quotamap{$user} = $quota * 1024 * 1024 / $bsize;
			}
		}
	$lref = &read_file_lines("$backup/$dom/email/passwd");
	foreach my $l (@$lref) {
		my ($muser, $crypt) = split(/:/, $l);
		next if (!$muser);
		next if ($muser eq $user);	# Domain owner
		local $uinfo = &create_initial_user(\%dom);
		$uinfo->{'user'} = &userdom_name(lc($muser), \%dom);
		$uinfo->{'pass'} = $crypt;
		$uinfo->{'uid'} = &allocate_uid(\%taken);
		$uinfo->{'gid'} = $dom{'gid'};
		$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".
				   lc($muser);
		$uinfo->{'shell'} = $nologin_shell->{'shell'};
		$uinfo->{'email'} = lc($muser)."\@$dom";
		$uinfo->{'qquota'} = $quota{$muser};
		$uinfo->{'quota'} = $quota{$muser};
		$uinfo->{'mquota'} = $quota{$muser};
		&create_user_home($uinfo, \%dom, 1);
		&create_user($uinfo, \%dom);
		$taken{$uinfo->{'uid'}}++;
		local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);

		# Move his Maildir directory
		local $mailsrc = "$backup/$dom/email/data/imap/$muser/Maildir";
		if (-d $mailsrc) {
			local $srcfolder = { 'type' => 1,
					     'file' => $mailsrc };
			local $dstfolder = { 'file' => $crfile,
					     'type' => $crtype };
			&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
			&set_mailfolder_owner($dstfolder, $uinfo);
			}
		$usermap{$uinfo->{'user'}} = $uinfo;
		$mcount++;
		}
	&$second_print(".. done (migrated $mcount users)");
	}

if ($got{'mail'}) {
	# Migrate mail aliases
	local $acount = 0;
	&$first_print("Copying email aliases ..");
	&set_alias_programs();
	local %gotvirt = map { $_->{'from'}, $_ } &list_virtusers();
	my $lref = &read_file_lines("$backup/$dom/email/aliases", 1);
	foreach my $l (@$lref) {
		my ($name, $values) = split(/:/, $l, 2);
		next if ($name eq $dom{'user'} && $values eq $dom{'user'});
		my @values = split(/,/, $values);
		foreach my $v (@values) {
			if ($v eq ":fail:") {
				$v = "BOUNCE";
				}
			}
		local $virt = { 'from' => $name =~ /^\*/ ?
				  "\@".$dom :
				  $name."\@".$dom,
				'to' => \@values };
		local $clash = $gotvirt{$virt->{'from'}};
		&delete_virtuser($clash) if ($clash);
		&create_virtuser($virt);
		$acount++;
		}
	&$second_print(".. done (migrated $acount aliases)");
	}

# Migrate FTP users
local $fcount = 0;
&$first_print("Copying FTP users ..");
my $lref = &read_file_lines("$backup/$dom/ftp.passwd");
foreach my $l (@$lref) {
	$l =~ /^([^@]+)@[^=]+=passwd=([^=]+)&path=([^=\&]+)/ || next;
	my ($fuser, $crypt, $path) = ($1, $2, $3);
	next if ($fuser eq $user);      # Domain owner
	local $uinfo = &create_initial_user(\%dom, 0, 1);
	$uinfo->{'user'} = &userdom_name(lc($fuser), \%dom);
	$uinfo->{'pass'} = $crypt;
	$uinfo->{'uid'} = $dom{'uid'};
	$uinfo->{'gid'} = $dom{'gid'};
	if ($path =~ /public_html\/?$/) {
		# Same as web dir
		$uinfo->{'home'} = &public_html_dir(\%dom);
		}
	elsif ($path =~ /public_html\/([^\/]+)\/?$/) {
		# Subdir of web dir
		$uinfo->{'home'} = &public_html_dir(\%dom)."/".$1;
		}
	else {
		# Domain home
		$uinfo->{'home'} = $dom{'home'};
		}
	$uinfo->{'shell'} = $ftp_shell->{'shell'};
	&create_user($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	$usermap{$uinfo->{'user'}} = $uinfo;
	$fcount++;
	}
&$second_print(".. done (migrated $fcount users)");

# Migrate cron jobs
# XXX Format?

&release_lock_mail(\%dom);
&release_lock_unix(\%dom);

if ($got{'mysql'}) {
	# Re-create all MySQL databases
	local $mycount = 0;
	local $myucount = 0;
	&$first_print("Re-creating and loading MySQL databases ..");
	&disable_quotas(\%dom);
	foreach my $myf (glob("$backup/*.sql")) {
		if ($myf =~ /\/([^\/]+)\.sql$/) {
			local $db = $1;
			&$indent_print();
			&create_mysql_database(\%dom, $db);
			&save_domain(\%dom, 1);
			local ($ex, $out) = &execute_dom_sql_file(\%dom, $db, $myf);
			if ($ex) {
				&$first_print("Error loading $db : $out");
				}
			&$outdent_print();

			# Create extra DB users
			local %dbusers;
			&read_env_file("$backup/$db.conf", \%dbusers);
			foreach my $myuser (keys %dbusers) {
				next if ($myuser eq $user);
				next if ($dbusers{$myuser} !~ /passwd=([^&]+)/);
				my $mypass = $1;
				local $myuinfo = &create_initial_user(\%dom);
				$myuinfo->{'user'} = $myuser;
				$myuinfo->{'pass'} = "x";	# not needed
				$myuinfo->{'mysql_pass'} = $mypass;
				$myuinfo->{'gid'} = $dom{'gid'};
				$myuinfo->{'real'} = "MySQL user";
				$myuinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$myuser";
				$myuinfo->{'shell'} = $nologin_shell->{'shell'};
				$myuinfo->{'dbs'} = [ { 'type' => 'mysql',
							'name' => $db } ];
				delete($myuinfo->{'email'});
				local $already = $usermap{$myuinfo->{'user'}};
				if ($already) {
					# User already exists, so just give him
					# access to the dbs
					my $olduinfo = { %$already };
					push(@{$already->{'dbs'}},
					     @{$myuinfo->{'dbs'}});
					&modify_user($already, $olduinfo, \%dom);
					}
				else {
					$myuinfo->{'uid'} =
						&allocate_uid(\%taken);
					&create_user_home($myuinfo, \%dom, 1);
					&create_user($myuinfo, \%dom);
					&create_mail_file($myuinfo, \%dom);
					$usermap{$myuinfo->{'user'}} = $myuinfo;
					}
				$myucount++;
				}

			$mycount++;
			}
		}
	closedir(MYDIR);
	&enable_quotas(\%dom);
	&$second_print(".. done (created $mycount databases and $myucount users)");
	}

# Migrate any alias domains
my %aliaslist;
&read_env_file("$backup/$dom/domain.pointers", \%aliaslist);
foreach my $adom (keys %aliaslist) {
	next if ($aliaslist{$adom} ne 'alias');
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
			 'aliasmail', 1,
			 'uid', $dom{'uid'},
			 'gid', $dom{'gid'},
			 'ugid', $dom{'ugid'},
			 'owner', "Migrated DirectAdmin alias for $dom{'dom'}",
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
		$alias{$f} = $dom{$f};
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

# Migrate any sub-domains
my $sublist = &read_file_lines("$backup/$dom/subdomain.list", 1);
foreach my $sdom (@$sublist) {
	my $sname = $sdom.".".$dom{'dom'};
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
			'subdom', $dom{'id'},
			'subprefix', $sdom,
			'uid', $dom{'uid'},
			'gid', $dom{'gid'},
			'ugid', $dom{'ugid'},
			'owner', "Migrated Ensim sub-domain",
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
			'no_tmpl_aliases', 1,
			);
	foreach my $f (@subdom_features) {
		$subd{$f} = $dom{$f};
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
	}

if ($parent) {
	# Re-save parent user, to update Webmin ACLs
	&refresh_webmin_user($parent);
	}

&sync_alias_virtuals(\%dom);
return @rvdoms;
}

# extract_directadmin_dir(file)
# Extracts a tar.gz file, and returns a status code and either the directory
# under which it was extracted, or an error message
sub extract_directadmin_dir
{
local ($file) = @_;
local $dir;
if ($main::directadmin_dir_cache{$file} && -d $main::directadmin_dir_cache{$file}) {
	# Use cached extract from this session
	return (1, $main::directadmin_dir_cache{$file});
	}
if (!-e $file) {
	return (0, "File $file does not exist");
	}
elsif (-d $file) {
	# Already extracted
	$dir = $file;
	}
else {
	$dir = &transname();
	mkdir($dir, 0700);
	local $err = &extract_compressed_file($file, $dir);
	if ($err) {
		return (0, $err);
		}
	}
$main::directadmin_dir_cache{$file} = $dir;
return (1, $dir);
}

1;

