# Functions for migrating an LXadmin backup
# XXX how to work out admin username?

# migration_cpanel_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is an LXadmin backup, and contains the domain
sub migration_lxadmin_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_lxadmin_dir($file);
$ok || return ("Not an LXadmin tar file : $root");
local $filename = -r "$root/kloxo.file" ? "$root/kloxo.file"
					: "$root/lxadmin.file";
local $metaname = -r "$root/kloxo.metadata" ? "$root/kloxo.metadata"
					    : "$root/lxadmin.metadata";
-r $filename || return ("Not an LXadmin backup - missing kloxo.file ".
			"or lxadmin.file");
-r $metaname || return ("Not an LXadmin backup - missing kloxo.metadata ".
			"or lxadmin.metadata");

# Parse data files
local $filehash = &parse_lxadmin_file($filename);
ref($filehash) || return "Failed to parse kloxo.file : $filehash";
local $metahash = &parse_lxadmin_file($metaname);
ref($metahash) || return "Failed to parse kloxo.metadata : $metahash";

local @doms = keys %{$filehash->{'bobject'}->{'domain_l'}};
if (!$dom) {
	# Work out the domain
	@doms || return ("No domains were found in this backup!");
	@doms == 1 ||
		return ("This backup contains multiple domains, of which one must be selected. Domains are : ".join(" ", @doms));
	$dom = $doms[0];
	}
else {
	# Validate that the domain is in this backup
	&indexof($dom, @doms) >= 0 ||
		return ("The domain $dom is not in this backup. Possible domains are : ".join(" ", @doms));
	}
local $domhash = $filehash->{'bobject'}->{'domain_l'}->{$dom};

# Work out the username
if (!$user) {
	$user = $metahash->{'_clean_object'}->{'username'};
	$user || return ("No username was found in this backup!");
	}

# Work out the password
if (!$parent && !$pass) {
	$pass = $filehash->{'bobject'}->{'realpass'};
	$pass || return ("Failed to find original password in backup");
	}

return (undef, $dom, $user, $pass);
}

# migration_lxadmin_migrate(file, domain, username, create-webmin, template-id,
#			    &ipinfo, pass, [&parent], [prefix], [email])
# Actually extract the given LXadmin backup, and return the list of domains
# created.
sub migration_lxadmin_migrate
{
local ($file, $dom, $user, $webmin, $template, $ipinfo, $pass, $parent,
       $prefix, $email) = @_;
local @rv;

# Extract the backup
local ($ok, $root) = &extract_lxadmin_dir($file);
$ok || &error("Not an LXadmin tar file : $root");
local $filename = -r "$root/kloxo.file" ? "$root/kloxo.file"
					: "$root/lxadmin.file";
local $metaname = -r "$root/kloxo.metadata" ? "$root/kloxo.metadata"
					    : "$root/lxadmin.metadata";
local $metahash = &parse_lxadmin_file($metaname);
ref($metahash) || &error("Failed to parse kloxo.metadata : $metahash");
local $filehash = &parse_lxadmin_file($filename);
ref($filehash) || &error("Failed to parse kloxo.file : $filehash");
local $domhash = $filehash->{'bobject'}->{'domain_l'}->{$dom};

# Get shells for users
local ($nologin_shell, $ftp_shell, undef, $def_shell) =
	&get_common_available_shells();
$nologin_shell ||= $def_shell;
$ftp_shell ||= $def_shell;

# Work out the original username
local $realuser = $filehash->{'bobject'}->{'username'};
$realuser || &error("No username was found in this backup!");
$user ||= $realuser;
local $group = $user;
local $ugroup = $group;

# Work out the password
$pass ||= $filehash->{'object'}->{'realpass'};

&$first_print("Checking for LXadmin features ..");
local @got = ( "dir", $parent ? () : ("unix"), "mail" );
if ($domhash->{'web_o'}) {
	push(@got, "web", "logrotate");
	}
push(@got, "webmin") if ($webmin && !$parent);
if ($filehash->{'bobject'}->{'used'}->{'mysqldb_num'}) {
	push(@got, "mysql");
	}
if ($domhash->{'dns_o'}) {
	push(@got, "dns");
	}
if ($domhash->{'mmail_o'}->{'spam_o'}) {
	push(@got, "spam", "virus");
	}
my $aw = $filehash->{'bobject'}->{'used'}->{'awstats_flag'};
my @plugins = &list_feature_plugins();
if ($aw && $aw ne '-' && &indexof('virtualmin-awstats', @plugins) >= 0) {
	push(@got, 'virtualmin-awstats');
	}
if ($filehash->{'bobject'}->{'used'}->{'mailinglist_num'} &&
    &indexof('virtualmin-mailman', @plugins) >= 0) {
	push(@got, 'virtualmin-mailman');
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

# Find quota
# XXX set $quota

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
         'owner', "Migrated LXadmin domain $dom",
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
	 'nocreationscripts', 1,
	 'parent', $parent ? $parent->{'id'} : undef,
        );
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
$dom{'home'} = &server_home_directory(\%dom, $parent);

# Set cgi directories to LXadmin standard
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
push(@rv, \%dom);

# Extract the client file containing domain homes
&$first_print("Restoring web directory ..");
local ($homesfile) = glob("$root/$realuser-client-*");
local $ht = &public_html_dir(\%dom);
if (!$homesfile) {
	&$second_print(".. failed to find $realuser-client-* file!");
	}
else {
	local ($ok, $homes) = &extract_lxadmin_dir($homesfile);
	if (!$ok) {
		&$second_print(".. failed to extract web directories file : $homes");
		}
	else {
		# Find a sub-dir for this domain
		local $subdir = "$homes/$dom";
		if (!-d $subdir) {
			local @dp = split(/\./, $dom);
			$subdir = "$homes/$dp[0]";
			}
		if (!-d $subdir) {
			&$second_print(".. failed to find sub-directory for domain");
			}
		else {
			&execute_command("cp -r ".quotemeta($subdir)."/* ".
					 quotemeta($ht));
			&set_home_ownership(\%dom);
			&$second_print(".. done");
			}
		}
	}

if ($got{'web'}) {
	# Just adjust cgi-bin directory to match LXadmin
	local ($virt, $vconf, $conf) = &get_apache_virtual($dom, undef);
	&apache::save_directive("ScriptAlias",
		[ "/cgi-bin $dom{'home'}/public_html/cgi-bin" ], $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	&register_post_action(\&restart_apache);
	&save_domain(\%dom);
	}
$dom{'cgi_bin_correct'} = 0;	# So that it is computed from now on

# Extract mailboxes file
&$first_print("Extracting mailboxes file ..");
local ($mfile) = glob("$root/$dom-mmail-*.tar");
local $mdir;
if (!$mfile) {
	&$second_print(".. no $dom-mmail-* file found");
	}
else {
	($ok, $mdir) = &extract_lxadmin_dir($mfile);
	if (!$ok) {
		&$second_print(".. extraction failed : $mdir");
		}
	else {
		&$second_print(".. done");
		}
	}

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);
&foreign_require("mailboxes");
$mailboxes::no_permanent_index = 1;

# Restore mailboxes
&$first_print("Re-creating mailbox users ..");
local $mcount = 0;
local @emails = keys %{$domhash->{'mmail_o'}->{'mailaccount_l'}};
foreach my $e (@emails) {
	my $u = $domhash->{'mmail_o'}->{'mailaccount_l'}->{$e};
	my ($username) = split(/\@/, $e);
	local $uinfo = &create_initial_user(\%dom);
	$uinfo->{'user'} = &userdom_name(lc($username), \%dom);
	if ($u->{'realpass'}) {
		$uinfo->{'plainpass'} = $u->{'realpass'};
		$uinfo->{'pass'} = &encrypt_user_password(
					$uinfo, $uinfo->{'plainpass'});
		}
	else {
		$uinfo->{'pass'} = $u->{'password'};
		}
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/".lc($username);
	$uinfo->{'shell'} = $nologin_shell->{'shell'};
	$uinfo->{'email'} = lc($e);
	&create_user_home($uinfo, \%dom, 1);
	&create_user($uinfo, \%dom);
	$taken{$uinfo->{'uid'}}++;
	local ($crfile, $crtype) = &create_mail_file($uinfo, \%dom);

	# Find original mail directory
	local $umdir = "$mdir/$username/Maildir";
	next if (!-d $umdir);

	# Move his mail file
	local $srcfolder = { 'file' => $umdir, 'type' => 1 };
	local $dstfolder = { 'file' => $crfile, 'type' => $crtype };
	if ($srcfolder->{'type'} == 1 && $dstfolder->{'type'} == 1) {
		# Same format, so can just copy including sub-folders
		&copy_source_dest($srcfolder->{'file'}, $dstfolder->{'file'});
		}
	else {
		# Move and convert
		&mailboxes::mailbox_copy_folder($srcfolder, $dstfolder);
		}
	&set_mailfolder_owner($dstfolder, $uinfo);

	# Move other mail folders, if not using Maildir
	if ($dstfolder->{'type'} != 1) {
		local $dstdir = $uinfo->{'home'}."/".
				$mailboxes::config{'mail_usermin'};
		opendir(SRCDIR, $umdir);
		foreach my $uf (readdir(SRCDIR)) {
			if ($uf =~ /^\./ && $uf ne "." && $uf ne "..") {
				local $fname = $uf;
				$fname =~ s/^\.//;
				local $srcf = { 'file' => "$umdir/$uf",
						'type' => 1 };
				local $dstf = { 'file' => "$dstdir/$fname",
						'type' => 1 };
				&mailboxes::mailbox_copy_folder($srcf, $dstf);
				&set_mailfolder_owner($dstf, $uinfo);
				}
			}
		closedir(SRCDIR);
		}

	$mcount++;
	}
&$second_print(".. done (migrated $mcount mail users)");

# Restore mail aliases
if ($got{'mail'}) {
	&$first_print("Re-creating mail aliases ..");
	local $acount = 0;
	local @aliases = keys %{$domhash->{'mmail_o'}->{'mailforward_l'}};
	local %gotvirt = map { $_->{'from'}, $_ } &list_virtusers();
	foreach my $e (@aliases) {
		my $a = $domhash->{'mmail_o'}->{'mailforward_l'}->{$e};
		local $virt = { 'from' => $e, 'to' => [ ] };
		if ($a->{'forwardaddress'}) {
			push(@{$virt->{'to'}},
			     split(/[ ,]/, $a->{'forwardaddress'}));
			}
		local $clash = $gotvirt{$virt->{'from'}};
		&delete_virtuser($clash) if ($clash);
		&create_virtuser($virt);
		$acount++;
		}
	&$second_print(".. done (migrated $acount mail aliases)");
	}

# Restore mailing lists
if ($got{'virtualmin-mailman'}) {
	# XXX how to migrate members?
	&$first_print("Re-creating Mailman mailing lists ..");
	&foreign_require('virtualmin-mailman', 'virtualmin-mailman-lib.pl');
	local $lcount = 0;
	local @lists = keys %{$domhash->{'mmail_o'}->{'mailinglist_l'}};
	foreach my $e (@lists) {
		my $l = $domhash->{'mmail_o'}->{'mailinglist_l'}->{$e};
		my $err = &plugin_call("virtualmin-mailman", "create_list",
				       $l->{'listname'}, $dom,
				       "Migrated LXadmin mailing list",
				       undef, $l->{'adminemail'} ||
						$dom{'emailto_addr'},
				       $dom{'pass'});
		if ($err) {
			&$second_print("Failed to create $ml : $err");
			}
		else {
			$lcount++;
			}
		}
	&$second_print(".. done (migrated $lcount lists)");
	}

# Restore MySQL databases
if ($got{'mysql'}) {
	&$first_print("Re-creating MySQL databases ..");
	&disable_quotas(\%dom);
	&require_mysql();
	local @gotmysql = &mysql::list_databases();
	local $dcount = 0;
	local @dbs = keys %{$filehash->{'bobject'}->{'mysqldb_l'}};
	foreach my $db (@dbs) {
		next if (&indexof($db, @gotmysql) >= 0);

		# Create the empty DB
		&$indent_print();
		&create_mysql_database(\%dom, $db);
		&save_domain(\%dom, 1);

		# Extract the tar file
		local ($dbtar) = glob("$root/$db-mysqldb-*");
		if (!$dbtar) {
			&$first_print("No TAR file for contents of $db found");
			&$outdent_print();
			next;
			}
		local $dbdir = &extract_lxadmin_file($dbtar);
		if (!$dbdir || !-r "$dbdir/mysql-$db.dump") {
			&$first_print("TAR file for contents of $db does not ".
				      "contain mysql-$db.dump");
			&$outdent_print();
			next;
			}

		# Load the SQL
		local ($ex, $out) = &mysql::execute_sql_file($db,
					"$dbdir/mysql-$db.dump");
		if ($ex) {
			&$first_print("Error loading $db : $out");
			}
		&$outdent_print();
		$dcount++;
		}
	&enable_quotas(\%dom);
	&$second_print(".. done (migrated $dcount databases)");
	}

&release_lock_unix(\%dom);
&release_lock_mail(\%dom);

# Save original metadata files
&$first_print("Saving LXadmin metadata files ..");
local $etcdir = "$dom{'home'}/etc";
if (!-d $etcdir) {
	&make_dir($etcdir, 0755);
	&set_ownership_permissions($dom{'uid'}, $dom{'gid'}, undef, $etcdir);
	}
&copy_source_dest("$root/kloxo.metadata", "$etcdir/kloxo.metadata");
&copy_source_dest("$root/kloxo.file", "$etcdir/kloxo.file");
eval "use Data::Dumper";
if (!$@) {
	&open_tempfile(DUMP, ">$etcdir/kloxo.metadata.dump");
	&print_tempfile(DUMP, Dumper($metahash));
	&close_tempfile(DUMP);
	&open_tempfile(DUMP, ">$etcdir/kloxo.file.dump");
	&print_tempfile(DUMP, Dumper($filehash));
	&close_tempfile(DUMP);
	}
&set_ownership_permissions($dom{'uid'}, $dom{'gid'}, 0700,
		   "$etcdir/kloxo.metadata", "$etcdir/kloxo.file",
		   "$etcdir/kloxo.metadata.dump", "$etcdir/kloxo.file.dump");
&$second_print(".. done");

return @rv;
}

# extract_lxadmin_dir(file)
# Extracts a tar file, and returns a status code and either the directory
# under which it was extracted, or an error message
sub extract_lxadmin_dir
{
local ($file) = @_;
local $dir;
if (!-e $file) {
	return (0, "$file does not exist");
	}
elsif (-d $file) {
	# Just use directory
	$dir = $file;
	}
else {
	if ($main::lxadmin_dir_cache{$file} &&
	    -d $main::lxadmin_dir_cache{$file}) {
		# Use cached extract from this session
		return (1, $main::lxadmin_dir_cache{$file});
		}
	$dir = &transname();
	mkdir($dir, 0700);
	local $err = &extract_compressed_file($file, $dir);
	if ($err) {
		return (0, $err);
		}
	$main::lxadmin_dir_cache{$file} = $dir;
	}
return (1, $dir);
}

# extract_lxadmin_file(file)
# Extracts a tar file, and returns the filename that is was extracted to
sub extract_lxadmin_file
{
return undef if (!-r $_[0]);
local $temp = &transname();
&make_dir($temp, 0700);
local $qf = quotemeta($_[0]);
&execute_command("cd $temp && ".&make_tar_command("xf", $qf));
return $? ? undef : $temp;
}

# parse_lxadmin_file(file)
# Returns a hash ref for the contents of an LXadmin metadata file, which is
# actually just PHP serialized data. Returns a string on failure.
sub parse_lxadmin_file
{
local ($file) = @_;
local $ser = &read_file_contents($file);
$ser || return "$file is missing or empty";
$ser =~ /O:6:"Remote"/ || return "$file does not appear to contain PHP serialized data : ".substr($ser, 0, 20);
eval "use PHP::Serialization";
$@ && return "Failed to load PHP::Serialization module : $@";
local $rv = eval { PHP::Serialization::unserialize($ser) };
$@ && return "Un-serialization failed : $@";
ref($rv) || return "Un-serialization did not return a hash : $rv";
return $rv;
}

