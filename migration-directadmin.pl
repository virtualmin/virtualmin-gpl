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
if ($dinfo{'quota'} && $dinfo{'quota'} ne 'unlimited') {
	# Assume in MB
	$quota = $dinfo{'quota'} * 1024;
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

# Copy over stats directory
local $stats = &webalizer_stats_dir(\%dom);
local $statssrc = "$domains/$dom/stats";
if (-d $statssrc) {
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

# XXX public_ftp

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
	# XXX fix SPF record
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

# Lock the user DB and build list of used IDs
&obtain_lock_unix(\%dom);
&obtain_lock_mail(\%dom);
local (%taken, %utaken);
&build_taken(\%taken, \%utaken);

&foreign_require("mailboxes", "mailboxes-lib.pl");
local %usermap;
if ($got{'mail'}) {
	# Migrate mail users
	# XXX
	}

# XXX email aliases?

&release_lock_mail(\%dom);
&release_lock_unix(\%dom);

if ($got{'mysql'}) {
	# Re-create all MySQL databases
	local $mycount = 0;
	&$first_print("Re-creating and loading MySQL databases ..");
	&disable_quotas(\%dom);
	foreach my $myf (glob("$backup/*.sql")) {
		if ($myf =~ /\/([^\/]+)\.sql$/) {
			local $db = $1;
			&$indent_print();
			&create_mysql_database(\%dom, $db);
			&save_domain(\%dom, 1);
			local ($ex, $out) = &mysql::execute_sql_file($db, $myf);
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

