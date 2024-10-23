# Functions for migrating a DirectAdmin backup

# migration_directadmin_validate(file, domain, [user], [&parent],
# 				 [prefix], [pass])
# Make sure the given file is a DirectAdmin backup, and contains the domain
sub migration_directadmin_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;

# Password is needed for DirectAdmin migrations
if (!$parent && !$pass) {
	return ("A password must be supplied for DirectAdmin migrations");
	}

# Extract the backup and verify it
local ($ok, $root) = &extract_directadmin_dir($file);
$ok || return ("Not a DirectAdmin tar.gz file : $root");
local $domains = "$root/domains";
local $backup = "$root/backup";
if (!-r $domains && $dom && -d "$backup/$dom") {
	$domains = $backup;
	}
-d $domains && -d $backup || return ("Not a DirectAdmin backup file");

if (!$dom) {
	# Try to work out the default domain
	local @domdirs = grep { !/^default$/ && -r "$backup/$_/domain.conf" }
			      split(/\r?\n/, &backquote_command("ls -t $domains"));
	@domdirs || return ("No domains found in backup");
	$dom = $domdirs[0];
	}
else {
	# Validate the domain
	-d "$domains/$dom" && -r "$backup/$dom/domain.conf" ||
		return ("Backup does not contain domain $dom");
	}

# If no username was given, use the default
if (!$user) {
	local %uinfo;
	&read_env_file("$backup/user.conf", \%uinfo) ||
		return ("$backup/user.conf not found!");
	$user = $uinfo{'username'};
	}

return (undef, $dom, $user, $pass);
}

# migration_directadmin_migrate(file, domain, username, create-webmin,
# 				template-id, &ipinfo, pass, [&parent],
# 				[prefix], [email], [&plan])
# Actually extract the given DirectAdmin backup, and return the list of domains
# created.
sub migration_directadmin_migrate
{
local ($file, $dom, $user, $webmin, $template, $ipinfo, $pass, $parent,
       $prefix, $email, $plan) = @_;
local ($ok, $root) = &extract_directadmin_dir($file);
$ok || return ("Not a DirectAdmin tar.gz file : $root");
local $domains = "$root/domains";
local $backup = "$root/backup";
local $imap = "$root/imap";
if (!-r $domains && $dom && -d "$backup/$dom") {
	$domains = $backup;
	}
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
local @got = &directadmin_domain_features($dom, $domains, $backup, $imap);

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
         'owner', "Migrated DirectAdmin server $dom",
         'email', $email ? $email :
		  $parent ? $parent->{'email'} :
			    $uinfo{'email'},
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
	 'migration_type', 'directadmin',
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

# Copy over public_html and private_html dirs
&copy_directadmin_html_dir(\%dom, $domains);

# Copy over webalizer and awstats directories
&copy_directadmin_stats_dir(\%dom, $domains);

# Fix home permissions
&set_home_ownership(\%dom);

# Just adjust cgi-bin directory to match DirectAdmin
&fix_directadmin_cgi_bin(\%dom);

# Migrate DNS domain
&copy_directadmin_dns_records(\%dom, $backup);

# Copy SSL cert
&copy_directadmin_ssl_cert(\%dom, $backup);

# Setup PHP options
&fix_directadmin_php_options(\%dom, \%uinfo, $backup);

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
		$uinfo->{'quota'} = $quota{$muser};
		$uinfo->{'mquota'} = $quota{$muser};
		&create_user_home($uinfo, \%dom, 1);
		&create_user($uinfo, \%dom);
		$taken{$uinfo->{'uid'}}++;
		local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);

		# Move his Maildir directory
		# XXX sub-folders??
		local $mailsrc = "$backup/$dom/email/data/imap/$muser/Maildir";
		if (!-d $mailsrc) {
			$mailsrc = "$imap/$dom/$muser/Maildir";
			}
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

# Migrate email aliases
&copy_directadmin_mail_aliases(\%dom, $backup);

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
				$mypass =~ s/^%2A/\*/;
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
my %sublist;
my $phd = &public_html_dir(\%dom);
foreach my $sdom (@$sublist) {
	next if (!-d $phd."/".$sdom);
	my $sname = $sdom.".".$dom{'dom'};
	$sublist{$sname} = 1;
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
			'owner', "Migrated DirectAdmin sub-domain",
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
			'no_tmpl_aliases', 1,
			'nocreationscripts', 1,
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

# Migrate any additional domains in the backup, as sub-servers
if (!$dom{'parent'}) {
	opendir(DOMS, $domains);
	foreach my $dname (readdir(DOMS)) {
		next if ($dname eq "." || $dname eq ".." ||
			 $dname eq "default" || $dname eq $dom);
		next if ($aliaslist{$dname} || $sublist{$dname});
		&$first_print("Creating sub-server $dname ..");
		if (&domain_name_clash($dname)) {
			&$second_print(".. the domain $dname already exists");
			next;
			}
		&$indent_print();

		local %subd = ( 'id', &domain_id(),
				'dom', $dname,
				'user', $dom{'user'},
				'group', $dom{'group'},
				'prefix', $dom{'prefix'},
				'ugroup', $dom{'ugroup'},
				'pass', $dom{'pass'},
				'parent', $dom{'id'},
				'uid', $dom{'uid'},
				'gid', $dom{'gid'},
				'ugid', $dom{'ugid'},
				'owner', "Migrated DirectAdmin sub-server for $dom{'dom'}",
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
		# Set cgi directories to DirectAdmin standard
		my %got = map { $_, 1 } &directadmin_domain_features($dname, $domains, $backup);
		my $linkssl = &directadmin_linked_ssl($dname, $backup, \%dom);
		$got{&domain_has_ssl()} = 1 if ($linkssl);
		foreach my $f (@features, &list_feature_plugins()) {
			next if ($f eq "unix" || $f eq "webmin");
			$subd{$f} = $got{$f} ? 1 : 0;
			}
		local $parentdom = $dom{'parent'} ? &get_domain($dom{'parent'})
						  : \%dom;
		$subd{'home'} = &server_home_directory(\%subd, $parentdom);
		$subd{'cgi_bin_dir'} = "public_html/cgi-bin";
		$subd{'cgi_bin_path'} = "$subd{'home'}/$subd{'cgi_bin_dir'}";
		$subd{'cgi_bin_correct'} = 1;
		&generate_domain_password_hashes(\%subd, 1);
		&complete_domain(\%subd);
		&create_virtual_server(\%subd, $parentdom,
				       $parentdom->{'user'}, 0, 1);
		push(@rvdoms, \%subd);

		# Copy over public_html dir
		&copy_directadmin_html_dir(\%subd, $domains);

		# Copy over webalizer and awstats directories
		&copy_directadmin_stats_dir(\%subd, $domains);

		# Fix permissions on copied files
		&set_home_ownership(\%subd);

		# Copy custom DNS records
		&copy_directadmin_dns_records(\%subd, $backup);

		# Just adjust cgi-bin directory to match DirectAdmin
		&fix_directadmin_cgi_bin(\%subd);

		# Copy SSL cert
		&copy_directadmin_ssl_cert(\%subd, $backup);

		# Set PHP options
		&fix_directadmin_php_options(\%subd, \%uinfo, $backup);

		# Migrate email aliases
		&copy_directadmin_mail_aliases(\%subd, $backup);

		# Fix home permissions
		&set_home_ownership(\%subd);

		&$outdent_print();
		&$second_print($text{'setup_done'});
		}
	closedir(DOMS);
	&run_post_actions();
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

# copy_directadmin_html_dir(&domain, domains-dir)
# Copy the public HTML and FTP directories
sub copy_directadmin_html_dir
{
my ($d, $domains) = @_;
my $tmpl = &get_template($d->{'template'});

my $phd = &public_html_dir($d);
my $phdsrc = "$domains/$d->{'dom'}/public_html";
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
my $phd = "$d->{'home'}/private_html";
my $phdsrc = "$domains/$d->{'dom'}/private_html";
if (-d $phdsrc && !-l $phdsrc) {
	&$first_print("Copying private_html directory ..");
	&make_dir_as_domain_user($d, $phd, 0700);
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

# Copy over public_ftp directory
my $ftp = $d->{'home'}.'/'.($tmpl->{'ftp_dir'} || 'ftp');
my $ftpsrc = "$domains/$d->{'dom'}/public_ftp";
if (-d $ftpsrc) {
	&$first_print("Copying public_ftp directory ..");
	&make_dir_as_domain_user($d, $ftp, 0755);
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
}

# copy_directadmin_stats_dir(&domain, domains-dir)
# Copy the webalizer and AWstats dirs
sub copy_directadmin_stats_dir
{
my ($d, $domains) = @_;

# Copy over stats directory
my $stats = &webalizer_stats_dir($d);
my $statssrc = "$domains/$d->{'dom'}/stats";
if (-d $statssrc && $d->{'webalizer'}) {
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

# Copy over AWstats files
if ($d->{'virtualmin-awstats'}) {
	&$first_print("Copying AWstats data files ..");
	&execute_command(
		"cp ".quotemeta("$domains/$d->{'dom'}/awstats")."/.data/*.$d->{'dom'}.txt ".
		quotemeta("$d->{'home'}/awstats"));
	&execute_command(
		"chown -R $d->{'uid'}:$d->{'ugid'} ".
		quotemeta("$d->{'home'}/awstats"));
	&$second_print(".. done");
	}
}

# copy_directadmin_dns_records(&domain, backup-dir)
# Copy DNS records from the backup
sub copy_directadmin_dns_records
{
my ($d, $backup) = @_;

my $dnsfile = "$backup/$d->{'dom'}/$d->{'dom'}.db";
if ($d->{'dns'} && -r $dnsfile && !$d->{'dns_submode'}) {
	&$first_print("Copying and fixing DNS records ..");
	&require_bind();
	my $zonefile = &get_domain_dns_file($d);
	&copy_source_dest($dnsfile, &bind8::make_chroot($zonefile));
	my ($recs, $zdstfile) = &get_domain_dns_records_and_file($d, 1);
	my $oldip;
	foreach my $r (@$recs) {
		my $change = 0;
		if ($r->{'type'} eq 'A' &&
		    ($r->{'name'} =~ /^(|www\.|pop\.|smtp\.|cp\.|ftp\.|mail\.)\Q$d->{'dom'}\E\.$/ || $r->{'values'}->[0] eq $oldip)) {
			# Fix IP in domain record
			$oldip ||= $r->{'values'}->[0];
			$r->{'values'} = [ $d->{'ip'} ];
			$change++;
			}
		elsif ($r->{'name'} eq $d->{'dom'}."." &&
		       $r->{'type'} eq 'NS') {
			# Set NS record to this server
			local $master = $bconfig{'default_prins'} ||
					&get_system_hostname();
			$master .= "." if ($master !~ /\.$/);
			$r->{'values'} = [ $master ];
			$change++;
			}
		elsif ($r->{'name'} eq $d->{'dom'}."." &&
		       ($r->{'type'} eq 'SPF' ||
			$r->{'type'} eq 'TXT') &&
		    $r->{'values'}->[0] =~ /ip4:/) {
			# Fix IP in SPF record
			$r->{'values'}->[0] =~ s/ip4:([0-9\.]+)/ip4:$d->{'ip'}/;
			$change++;
			}
		if ($change) {
			&modify_dns_record($recs, $zdstfile, $r);
			}
		}
	&post_records_change($d, $recs, $zdstfile);
	&$second_print(".. done");
	&register_post_action(\&reload_bind_records, $d);
	}
}

# fix_directadmin_cgi_bin(&domain)
# Fix the cgi-bin path to follow the directadmin standard
sub fix_directadmin_cgi_bin
{
my ($d) = @_;
if ($d->{'web'}) {
	my @ports = ( $d->{'web_port'} );
	push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
	foreach my $p (@ports) {
		my ($virt, $vconf, $conf) = &get_apache_virtual(
				$d->{'dom'}, undef);
		next if (!$virt);
		my @sa = &apache::find_directive("ScriptAlias", $vconf);
		next if (!@sa);
		&apache::save_directive("ScriptAlias",
			[ "/cgi-bin $d->{'home'}/public_html/cgi-bin" ],
			$vconf, $conf);
		&flush_file_lines($virt->{'file'});
		&register_post_action(\&restart_apache);
		}
	}
$d->{'cgi_bin_correct'} = 0;	# So that it is computed from now on
}

# copy_directadmin_ssl_cert(&domain, backup-dir)
# Copy the SSL cert and key into place from the backup
sub copy_directadmin_ssl_cert
{
my ($d, $backup) = @_;
my $cfile = "$backup/$d->{'dom'}/domain.cert";
my $kfile = "$backup/$d->{'dom'}/domain.key";
my $cafile = "$backup/$d->{'dom'}/domain.cacert";
if (&domain_has_ssl_cert($d) && -r $cfile && -r $kfile) {
	&$first_print("Copying SSL certificate and key ..");
	my $cdom = &get_website_ssl_file($d, "cert");
	&write_ssl_file_contents($d, $cdom, $cfile);
	my $kdom = &get_website_ssl_file($d, "key");
	&write_ssl_file_contents($d, $kdom, $kfile);
	if ($cafile) {
		my $cadom = &get_website_ssl_file($d, "ca");
		$cadom ||= &default_certificate_file($d, "ca");
		&write_ssl_file_contents($d, $cadom, $cafile);
		&save_website_ssl_file($d, "ca", $cadom);
		}
	else {
		&save_website_ssl_file($d, "ca", undef);
		}
	&sync_combined_ssl_cert($d);
	&$second_print(".. done");
	}

my %dinfo;
&read_env_file("$backup/$d->{'dom'}/domain.conf", \%dinfo);
if ($dinfo{'force_ssl'} =~ /yes/i && &domain_has_ssl($d)) {
	# Add redirect to SSL
	&create_redirect($d, &get_redirect_to_ssl($d));
	}
}

# directadmin_linked_ssl(subdomain-name, backup-dir, &parent-domain)
# Returns 1 if this sub-domain can use the parent domain's SSL cert
sub directadmin_linked_ssl
{
my ($dname, $backup, $parent) = @_;
return 0 if (!&domain_has_ssl($parent));
return &check_domain_certificate($dname, $parent);
}

# copy_directadmin_mail_aliases(&domain, backup-dir)
# Copy email aliases from the backup
sub copy_directadmin_mail_aliases
{
my ($d, $backup) = @_;
my $afile = "$backup/$d->{'dom'}/email/aliases";
if ($d->{'mail'} && -r $afile) {
	local $acount = 0;
	&$first_print("Copying email aliases ..");
	&set_alias_programs();
	local %gotvirt = map { $_->{'from'}, $_ } &list_virtusers();
	my $lref = &read_file_lines($afile, 1);
	foreach my $l (@$lref) {
		my ($name, $values) = split(/:/, $l, 2);
		next if ($name eq $d->{'user'} && $values eq $d->{'user'});
		my @values = split(/,/, $values);
		foreach my $v (@values) {
			if ($v eq ":fail:") {
				$v = "BOUNCE";
				}
			}
		local $virt = { 'from' => $name =~ /^\*/ ?
				  "\@".$d->{'dom'} :
				  $name."\@".$d->{'dom'},
				'to' => \@values };
		my $clash = $gotvirt{$virt->{'from'}};
		&delete_virtuser($clash) if ($clash);
		&create_virtuser($virt);
		$acount++;
		}
	&$second_print(".. done (migrated $acount aliases)");
	}
}

# directadmin_domain_features(domain-name, domains-dir, backup-dir, imap-dir)
# Return a list of features that should be enabled
sub directadmin_domain_features
{
my ($dom, $domains, $backup, $imap) = @_;
my %dinfo;
&read_env_file("$backup/$dom/domain.conf", \%dinfo);
my @got = ( "dir", $parent ? () : ("unix"),
	    &domain_has_website(), "logrotate" );
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
if (-d "$domains/$dom/awstats" &&
    &indexof("virtualmin-awstats", @plugins) >= 0) {
	push(@got, "virtualmin-awstats");
	}
my $lref = &read_file_lines("$backup/$dom/email/aliases", 1);
if (@$lref > 1 ||
    glob("$backup/$dom/email/data/imap/*/Maildir") ||
    glob("$imap/$dom/*/Maildir")) {
	push(@got, "mail");
	}
if (uc($dinfo{'ssl'}) eq 'ON') {
	push(@got, &domain_has_ssl());
	}
return @got;
}

# fix_directadmin_php_options(&domain, user-options)
# Set the PHP version and enabled/disabled state
sub fix_directadmin_php_options
{
my ($d, $uinfo, $backup) = @_;
if ($uinfo->{'php'} =~ /off/i) {
	&$first_print("Disabling PHP ..");
	&save_domain_php_mode($d, "none");
	&$second_print(".. done");
	}
else {
	my %crontab;
	&read_env_file("$backup/crontab.conf", \%crontab);
	my $wantver;
	if ($crontab{'PATH'} =~ /\/php(\d)(\d+)\//) {
		my $ver = $1.".".$2;
		foreach my $v (&list_available_php_versions($d)) {
			if ($v->[0] eq $ver) {
				$wantver = $v->[0];
				}
			}
		}
	if ($wantver) {
		&$first_print("Changing PHP version to $wantver ..");
		my $phd = &public_html_dir($d);
		my $err = &save_domain_php_directory($d, $phd, $wantver);
		&$second_print($err ? "..failed : $err" : ".. done");
		}
	}
if ($uinfo->{'cgi'} =~ /off/i) {
	&$first_print("Disabling CGI scripts ..");
	&save_domain_cgi_mode($d, undef);
	&$second_print(".. done");
	}
}

1;

