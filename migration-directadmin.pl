# Functions for migrating a cpanel backup

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
	local @domdirs = glob("$domains/*");
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
	&read_file_env("$backup/user.conf", \%uinfo) ||
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
&read_file_env("$backup/user.conf", \%uinfo) ||
	&error("$backup/user.conf not found!");
local $origuser = $uinfo{'username'};
$user ||= $origuser;
$user || &error("Could not work out username automatically");
local $group = $user;
local $ugroup = $group;

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

# XXX where to get quota from?
local $quota;
if (-r "$userdir/quota") {
	# Get the quota (from home directory backup)
	open(QUOTA, "$userdir/quota");
	$quota = <QUOTA>;
	close(QUOTA);
	$quota = int($quota) * 1024;	# cpanel quotas are in MB
	}
elsif (-r "$datastore/quota_-v") {
	# Get the quota (from v10 backup)
	local $_;
	open(QUOTA, "$datastore/quota_-v");
	while(<QUOTA>) {
		if (/^\s+\S+\s+(\d+)\s+(\d+)\s+(\d+)/) {
			$quota = $2;
			}
		}
	close(QUOTA);
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
$dom{'home'} = &server_home_directory(\%dom, $parent);
&merge_ipinfo_domain(\%dom, $ipinfo);
if (!$parent) {
	&set_limits_from_plan(\%dom, $plan);
	$dom{'quota'} = $quota;
	$dom{'uquota'} = $quota;
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

# Extra homedir.tar if needed
# XXX
local $hometar = "$userdir/homedir.tar";
if (-r $hometar) {
	&$first_print("Extracting home directory TAR file ..");
	local $out;
	if (!-d $homesrc) {
		&make_dir($homesrc, 0755);
		}
	&execute_command("cd ".quotemeta($homesrc)." && ".
			 &make_tar_command("xf", quotemeta($hometar)),
			 undef, \$out, \$out);
	if ($?) {
		&$second_print(".. TAR failed : <tt>$out</tt>");
		}
	else {
		&$second_print(".. done");
		}
	}

# Migrate Apache configuration
# XXX
if ($got{'web'} && -d $daily) {
	&$first_print("Copying Apache directives ..");
	if ($srcvconf) {
		# Copy any directives not set by Virtualmin
		local $conf = &apache::get_config();
		local ($vconf, $virt) = &get_apache_virtual($dom, undef);
		local %dirs;
		foreach my $a (@$virt) {
			next if ($a->{'type'});
			$dirs{$a->{'name'}}++;
			}
		$dirs{'ScriptAlias'} = 0;	# Always copy this
		$dirs{'ServerAlias'} = 0;	# and this
		$dirs{'BytesLog'} = 1;		# Not supported
		$dirs{'User'} = 1;		# Don't copy user-related
		$dirs{'Group'} = 1;		# settings, as Virtualmin will
		$dirs{'SuexecUserGroup'} = 1;	# have already set them
		local %vals;
		foreach my $a (@$srcvirt) {
			next if ($a->{'type'} || $dirs{$a->{'name'}});
			if ($dom{'home'} ne $orighome) {
				$a->{'value'} =~ s/$orighome/$dom{'home'}/g;
				}
			push(@{$vals{$a->{'name'}}}, $a->{'value'});
			}
		foreach my $an (keys %vals) {
			&apache::save_directive($an, $vals{$an}, $virt, $conf);
			}
		&$second_print(".. done");
		&register_post_action(\&restart_apache) if (!$got{'ssl'});
		}
	else {
		&$second_print(".. could not find Apache configuration");
		}
	}
elsif ($got{'web'}) {
	# Just adjust cgi-bin directory to match cPanel
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

if ($got{'ssl'}) {
	# Copy and use the SSL certs that came with the domain
	&$first_print("Copying SSL certificate and key ..");
	&execute_command("cp ".quotemeta("$userdir/sslcerts/www.$dom.crt")." ".
		     quotemeta($dom{'ssl_cert'}));
	&execute_command("cp ".quotemeta("$userdir/sslcerts/www.$dom.key")." ".
		     quotemeta($dom{'ssl_key'}));
	&register_post_action(\&restart_apache, 1);
	&$second_print(".. done");
	}

# Migrate DNS domain
if ($got{'dns'} && -d $daily) {
	&$first_print("Copying and fixing DNS records ..");
	&require_bind();
	local ($ok, $named) = &extract_cpanel_dir(
				"$daily/dirs/_var_named.tar.gz");
	local $zsrcfile = &bind8::find_value("file", $zone->{'members'});
	if (-r "$named/$zsrcfile") {
		&execute_command("cp ".quotemeta("$named/$zsrcfile")." ".
			     quotemeta(&bind8::make_chroot($zdstfile)));
		local ($recs, $zdstfile) =
			&get_domain_dns_records_and_file(\%dom);
		foreach my $r (@$recs) {
			my $change = 0;
			if (($r->{'name'} eq $dom."." ||
			     $r->{'name'} eq "www.".$dom."." ||
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
			if ($change) {
				&bind8::modify_record(
					$zdstfile, $r, $r->{'name'},
					$r->{'ttl'}, $r->{'class'},
					$r->{'type'},
					join(" ", @{$r->{'values'}}),
					$r->{'comment'});
				}
			}
		&post_records_change(\%dom, $zdstfile, $recs);
		&$second_print(".. done");
		&register_post_action(\&restart_bind);
		}
	else {
		&$second_print(".. could not find records file in backup!");
		}
	}

local $out;
local $ht = &public_html_dir(\%dom);
local $qht = quotemeta($ht);
if ($waschild) {
	# Migrate web directory
	local $qhtsrc = "$homesrc/public_html/$wasuser";
	&$first_print("Copying web pages to $ht ..");
	&execute_command("cd $qhtsrc && ".
			 "(".&make_tar_command("cf", "-", ".").
			 " | (cd $qht && ".
			 &make_tar_command("xf", "-")."))",
			 undef, \$out, \$out);
	}
else {
	# Migrate home directory contents (except logs and mail)
	&$first_print("Copying home directory to $dom{'home'} ..");
	local $qhome = quotemeta($dom{'home'});
	local $xtemp = &transname();
	&open_tempfile(XTEMP, ">$xtemp");
	&print_tempfile(XTEMP, "./logs\n");
	&print_tempfile(XTEMP, "./mail\n");
	&close_tempfile(XTEMP);
	&execute_command("cd $homesrc && ".
			 "(".&make_tar_command("cfX", "-", $xtemp, ".").
			 " | (cd $qhome && ".
			 &make_tar_command("xf", "-")."))",
			 undef, \$out, \$out);
	}
if ($?) {
	&$second_print(".. copy failed : <tt>$out</tt>");
	}
else {
	&$second_print(".. done");
	}

# If php.ini is migrated wrong, fix it
if ($dom{'web'}) {
	local $mode = &get_domain_php_mode(\%dom);
	if ($mode eq "cgi" || $mode eq "fcgid") {
		&fix_php_extension_dir(\%dom);
		}
	}

# Fix up home ownership and permissions
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

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

&foreign_require("mailboxes", "mailboxes-lib.pl");
local %usermap;
if ($got{'mail'}) {
	# Migrate mail users
	&cpanel_migrate_mailboxes($dom, \%dom, \%usermap);
	}

# Move server owner's inbox file
local $owner = &get_domain_owner(\%dom);
if ($owner && !$parent) {
	&$first_print("Moving server owner's mailbox ..");
	local ($mfile, $mtype) = &user_mail_file($owner);
	local $srcfolder;
	if (-d "$homesrc/mail/cur") {
		# Maildir format
		$srcfolder = { 'type' => 1, 'file' => "$homesrc/mail" };
		}
	elsif (-r "$homesrc/mail/inbox") {
		# mbox format
		$srcfolder = { 'type' => 0,
			       'file' => "$homesrc/mail/inbox" };
		}
	if ($srcfolder) {
		local $dstfolder = { 'type' => $mtype, 'file' => $mfile };
		&mailboxes::mailbox_move_folder($srcfolder, $dstfolder);
		&set_mailfolder_owner($dstfolder, $owner);
		&$second_print(".. done");
		}
	else {
		&$second_print(".. none exists");
		}
	}

# Build map from email addresses to users
local %useremail;
foreach my $uinfo (&list_domain_users(\%dom)) {
	if ($uinfo->{'email'}) {
		$useremail{$uinfo->{'email'}} = $uinfo;
		}
	}

if ($got{'mail'}) {
	# Copy mail aliases
	local $acount = 0;
	local $domfwd;
	&$first_print("Copying email aliases ..");
	&set_alias_programs();
	local %gotvirt = map { $_->{'from'}, $_ } &list_virtusers();
	local $_;
	open(VAD, "$userdir/vad/$dom");
	while(<VAD>) {
		s/\r|\n//g;
		s/^\s*#.*$//;
		if (/^(\S+):\s*(\S+)$/) {
			# A domain forward exists ..
			local $virt = { 'from' => "\@$dom",
					'to' => [ "%1\@$2" ] };
			local $clash = $gotvirt{$virt->{'from'}};
			&delete_virtuser($clash) if ($clash);
			&create_virtuser($virt);
			$acount++;
			$domfwd++;
			}
		}
	close(VAD);
	open(VA, "$userdir/va/$dom");
	while(<VA>) {
		s/\r|\n//g;
		s/^\s*#.*$//;
		if (/^(\S+):\s*(.*)$/) {
			local ($name, $v) = ($1, $2);
			local @values;
			if ($v !~ /,/ && $v !~ /"/) {
				# A single destination, not quoted!
				@values = ( $v );
				}
			else {
				# Comma-separated alias destinations
				while($v =~ /^\s*,?\s*"(\|)([^"]+)"(.*)$/ ||
				      $v =~ /^\s*,?\s*()"([^"]+)"(.*)$/ ||
				      $v =~ /^\s*,?\s*(\|)"([^"]+)"(.*)$/ ||
				      $v =~ /^\s*,?\s*()([^,\s]+)(.*)$/) {
					push(@values, $1.$2);
					$v = $3;
					}
				}
			local $mailman = 0;
			foreach my $v (@values) {
				if ($v =~ /:fail:\s+(.*)/) {
					# Fix bounce alias
					$v = "BOUNCE $1";
					}
				local ($atype, $aname) = &alias_type($v, $name);
				if ($atype == 4 && $aname =~ /autorespond\s+(\S+)\@(\S+)\s+(\S+)/) {
					# Turn into Virtualmin auto-responder
					$v = "| $module_config_directory/autoreply.pl $3/$name $1";
					&set_ownership_permissions(
						undef, undef, 0755,
						$3, "$3/$name");
					}
				elsif ($atype == 4 && $aname =~ /mailman/) {
					$mailman++;
					}
				}
			# Don't create aliases for mailman lists
			next if ($mailman || $name =~ /^owner-/);

			# Already done a domain forward
			next if ($name =~ /^\*/ && $domfwd);

			if ($useremail{$name}) {
				# This is an alias from a user. Preserve
				# delivery to his mailbox though, as this is
				# what cPanel seems to do.
				local $uinfo = $useremail{$name};
				local $olduinfo = { %$uinfo };
				local $touser = $uinfo->{'user'};
				if ($config{'mail_system'} == 0 &&
				    $escuser =~ /\@/) {
					$touser = &replace_atsign($touser);
					}
				$touser = "\\".$touser;
				$uinfo->{'to'} = [ $touser, @values ];
				&modify_user($uinfo, $olduinfo, \%dom);
				}
			else {
				# Just create an alias
				if ($name !~ /\@/) {
					$name .= "\@".$dom;
					}
				local $virt = { 'from' => $name =~ /^\*/ ?
						  "\@".$dom : $name,
						'to' => \@values };
				local $clash = $gotvirt{$virt->{'from'}};
				&delete_virtuser($clash) if ($clash);
				&create_virtuser($virt);
				$acount++;
				}
			}
		}
	close(VA);
	&$second_print(".. done (migrated $acount aliases)");
	}

# Create mailing lists
if ($got{'virtualmin-mailman'}) {
	local $lcount = 0;
	&$first_print("Re-creating mailing lists ..");
	foreach $ml (@lists) {
		local $err = &plugin_call("virtualmin-mailman", "create_list",
			     $ml, $dom, "Migrated cPanel mailing list",
			     undef, $dom{'emailto_addr'}, $dom{'pass'});
		if ($err) {
			&$second_print("Failed to create $ml : $err");
			}
		else {
			&execute_command("cp ".quotemeta("$userdir/mm/${ml}_${dom}/")."*.pck ".quotemeta("$virtualmin_mailman::mailman_var/lists/$ml"));
			$lcount++;
			}
		}
	&$second_print(".. done (created $lcount lists)");
	}

# Copy cron jobs for user (direct to his cron file)
if (-r "$userdir/cron/$user" && !$waschild) {
	&foreign_require("cron", "cron-lib.pl");
	&$first_print("Copying Cron jobs ..");
	$cron::cron_temp_file = &transname();
	eval {
		local $main::error_must_die = 1;
		if ($parent) {
			# Append migrated cron to parent user's
			&cron::copy_cron_temp({ 'user' => $parent->{'user'} });
			&execute_command(
			  "cat $userdir/cron/$user >>$cron::cron_temp_file");
			&cron::copy_crontab($parent->{'user'});
			}
		else {
			# Just over-write cron
			&execute_command(
			  "cp $userdir/cron/$user $cron::cron_temp_file");
			&cron::copy_crontab($user);
			}
		};
	if ($@) {
		&$second_print(".. failed : $@");
		}
	else {
		&$second_print(".. done");
		}
	}

if ($got{'mysql'}) {
	# Re-create all MySQL databases
	local $mycount = 0;
	&$first_print("Re-creating and loading MySQL databases ..");
	&disable_quotas(\%dom);
	local $mydir = "$userdir/mysql";
	opendir(MYDIR, $mydir);
	while($myf = readdir(MYDIR)) {
		if ($myf =~ /^(\Q$dbuser\E_\S*).sql$/ ||
		    $myf =~ /^(\Q$dbuser\E).sql$/) {
			local $db = $1;
			&$indent_print();
			&create_mysql_database(\%dom, $db);
			&save_domain(\%dom, 1);
			local ($ex, $out) = &mysql::execute_sql_file($db, "$mydir/$myf");
			if ($ex) {
				&$first_print("Error loading $db : $out");
				}
			&$outdent_print();
			$mycount++;
			}
		}
	closedir(MYDIR);
	&enable_quotas(\%dom);
	&$second_print(".. done (created $mycount databases)");

	# Re-create MySQL users
	if ($got{'mysql'}) {
		local $myucount = 0;
		&$first_print("Re-creating MySQL users ..");
		local %myusers;
		local $_;
		local (%donemysqluser, %donemysqlpriv);
		open(MYSQL, "$userdir/mysql.sql");
		while(<MYSQL>) {
			s/\r|\n//g;
			if (/^GRANT USAGE ON \*\.\* TO '(\S+)'\@'(\S+)' IDENTIFIED BY PASSWORD '(\S+)';/) {
				# Creating a MySQL user
				local ($myuser, $mypass) = ($1, $3);
				next if ($myuser eq $user);	# domain owner
				next if ($donemysqluser{$myuser}++);
				local $myuinfo = &create_initial_user(\%dom);
				$myuinfo->{'user'} = $myuser;
				$myuinfo->{'pass'} = "x";	# not needed
				$myuinfo->{'mysql_pass'} = $mypass;
				$myuinfo->{'gid'} = $dom{'gid'};
				$myuinfo->{'real'} = "MySQL user";
				$myuinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$myuser";
				$myuinfo->{'shell'} = $nologin_shell->{'shell'};
				delete($myuinfo->{'email'});
				$myusers{$myuser} = $myuinfo;
				}
			elsif (/GRANT ALL PRIVILEGES ON `(\S+)`\.\* TO '(\S+)'\@'(\S+)';/ || /GRANT SELECT.*\sON `(\S+)`\.\* TO '(\S+)'\@'(\S+)';/) {
				# Granting access to a MySQL database
				local ($mydb, $myuser) = ($1, $2);
				next if ($myuser eq $user);	# domain owner
				next if ($donemysqlpriv{$mydb,$myuser}++);
				$mydb =~ s/\\(.)/$1/g;
				if ($myusers{$myuser}) {
					push(@{$myusers{$myuser}->{'dbs'}},
					     { 'type' => 'mysql', 'name' => $mydb });
					}
				}
			}
		close(MYSQL);
		foreach my $myuinfo (values %myusers) {
			local $already = $usermap{$myuinfo->{'user'}};
			if ($already) {
				# User already exists, so just give him the dbs
				local $olduinfo = { %$already };
				$already->{'dbs'} = $myuinfo->{'dbs'};
				&modify_user($already, $old, \%dom);
				}
			else {
				$myuinfo->{'uid'} = &allocate_uid(\%taken);
				&create_user_home($myuinfo, \%dom, 1);
				&create_user($myuinfo, \%dom);
				&create_mail_file($myuinfo, \%dom);
				$taken{$myuinfo->{'uid'}}++;
				$usermap{$myuinfo->{'user'}} = $myuinfo;
				}
			$myucount++;
			}
		&$second_print(".. done (created $myucount MySQL users)");
		}
	}

# Fix up FTP configuration
if ($got{'ftp'}) {
	&$first_print("Modifying FTP server configuration ..");
	&require_proftpd();
	local $conf = &proftpd::get_config();
	local ($fvirt, $fconf, $anon, $aconf) =
		&get_proftpd_virtual($ipinfo->{'ip'});
	if ($anon) {
		local $lref = &read_file_lines($anon->{'file'});
		$lref->[$anon->{'line'}] = "<Anonymous $dom{'home'}/public_ftp>";
		&flush_file_lines($anon->{'file'});
		&$second_print(".. done");
		&register_post_action(\&restart_proftpd);
		}
	else {
		&$second_print(".. could not find FTP server configuration");
		}
	}

# Migrate or update FTP users
if (-r "$userdir/proftpdpasswd" && !$waschild) {
	local $fcount = 0;
	&$first_print("Re-creating FTP users ..");
	local $_;
	open(FTP, "$userdir/proftpdpasswd");
	while(<FTP>) {
		s/\r|\n//g;
		s/^\s*#.*$//;
		local ($fuser, $fpass, $fuid, $fgid, $fdummy, $fhome, $fshell) = split(/:/, $_);
		next if (!$fuser);
		next if ($fuser eq "ftp" || $fuser eq $user ||
			 $fuser eq $user."_logs");	# skip cpanel users
		local $fullfuser = &userdom_name(lc($fuser), \%dom);
		if ($fhome eq "/dev/null" ||
		    !&is_under_directory($dom{'home'}, $fhome)) {
			$fhome = "$dom{'home'}/$config{'homes_dir'}/$fuser";
			}
		local $already = $usermap{$fuser} ||
				 $usermap{$fullfuser};
		if ($already) {
			# Turn on FTP for existing user
			local $olduinfo = { %$already };
			$already->{'shell'} = $ftp_shell->{'shell'};
			&modify_user($already, $olduinfo, \%dom);
			}
		else {
			# Create new FTP-only user
			local $fuinfo = &create_initial_user(\%dom, 0,
							     $fhome eq $ht);
			$fuinfo->{'user'} = $fullfuser;
			$fuinfo->{'pass'} = $fpass;
			if ($fuinfo->{'webowner'}) {
				$fuinfo->{'uid'} = $dom{'uid'};
				}
			else {
				$fuinfo->{'uid'} = &allocate_uid(\%taken);
				}
			$fuinfo->{'gid'} = $dom{'gid'};
			$fuinfo->{'real'} = "FTP user";
			$fuinfo->{'home'} = $fhome;
			$fuinfo->{'shell'} = $ftp_shell->{'shell'};
			delete($fuinfo->{'email'});
			$usermap{$fuser} = $fuinfo;
			if (!$user->{'nocreatehome'}) {
				&create_user_home($fuinfo, \%dom, 1);
				}
			&create_user($fuinfo, \%dom);
			if (!$user->{'nomailfile'}) {
				&create_mail_file($fuinfo, \%dom);
				}
			$taken{$fuinfo->{'uid'}}++;
			$fcount++;
			}
		}
	close(FTP);
	&$second_print(".. done (created $fcount FTP users)");
	}
&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

# Migrate any parked domains as alias domains
local @parked;
if (!$waschild) {
	local $_;
	open(PARKED, "$userdir/pds");
	while(<PARKED>) {
		s/\r|\n//g;
		local ($pdom) = split(/\s+/, $_);
		push(@parked, $pdom) if ($pdom && $pdom !~ /^\*/);
		}
	close(PARKED);
	}

# Create alias domain for sub-domain
if ($aliasdom && $aliasdom !~ /^\*/) {
	push(@parked, $aliasdom);
	}

# Actually create alias doms
foreach my $pdom (&unique(@parked)) {
	if ($pdom eq $aliasdom) {
		&$first_print("Creating alias domain $pdom ..");
		}
	else {
		&$first_print("Creating parked domain $pdom ..");
		}
	if (&domain_name_clash($pdom)) {
		&$second_print(".. the domain $pdom already exists");
		next;
		}
	&$indent_print();
	local %alias = ( 'id', &domain_id(),
			 'dom', $pdom,
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
			 'owner', $pdom eq $aliasdom ?
					"Migrated cPanel alias for $dom{'dom'}":
					"Parked domain for $dom{'dom'}",
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
	if ($alias{'mail'}) {
		&cpanel_migrate_mailboxes($alias{'dom'}, \%alias, undef);
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	push(@rvdoms, \%alias);
	}

# Read addons domain mapping file
local %addons;
local $lref = &read_file_lines("$userdir/addons");
foreach my $l (@$lref) {
	my ($a, $t) = split(/=/, $l);
	if ($a && $t) {
		$t =~ s/_/\./;
		$addons{$a} = $t;
		}
	}

# Create sub-domains, silently skipping those for which no parent exists yet
&create_sub_domains(1);

# Create addon domains
&create_addon_domains();

# Create sub-domains again, to catch those for which an addon target exists now
&create_sub_domains(0);


if ($got{'webalizer'}) {
	# Copy existing Weblizer stats to ~/public_html/stats
	&$first_print("Copying Weblizer data files ..");
	&execute_command("cp ".
		quotemeta($webalizer)."/*.{png,gif,html,current,hist} ".
		quotemeta(&webalizer_stats_dir(\%dom)));
	&execute_command("chown -R $dom{'uid'}:$dom{'ugid'} ".
			 quotemeta(&webalizer_stats_dir(\%dom)));
        &$second_print($text{'setup_done'});
	}

if ($got{'virtualmin-awstats'}) {
	# Copy AWstats data files to ~/awstats
	&$first_print("Copying AWstats data files ..");
	&execute_command("cp ".quotemeta("$homesrc/tmp/awstats")."/*.$dom.txt ".
			       quotemeta("$dom{'home'}/awstats"));
	&execute_command("chown -R $dom{'uid'}:$dom{'ugid'} ".
			 quotemeta("$dom{'home'}/awstats"));
        &$second_print($text{'setup_done'});
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

