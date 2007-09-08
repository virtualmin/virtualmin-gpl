# Functions for migrating a plesk backup. These appear to be in MIME format,
# with each part (home dir, settings, etc) in a separate 'attachment'

# XXX how to find regular aliases?
# XXX domain aliases
# XXX SSL cert
# XXX DNS records (new ones, with correct IP)

# migration_plesk_validate(file, domain, username, [&parent], [prefix])
# Make sure the given file is a Plesk backup, and contains the domain
sub migration_plesk_validate
{
local ($file, $dom, $user, $parent, $prefix) = @_;
local $root = &extract_plesk_dir($file);
$root || return "Not a Plesk MIME-format backup file";
-r "$root/dump.xml" || return "Not a Plesk backup file - missing dump.xml";

# Check the domain
local $dump = &read_plesk_xml("$root/dump.xml");
ref($dump) || return $dump;
local $realdom = $dump->{'domain'}->{'name'};
$realdom eq $dom ||
	return "Backup is for domain $realdom, not $dom";

if (!$parent) {
	# Check the user
	local $realuser = $dump->{'domain'}->{'phosting'}->{'sysuser'}->{'name'};
	$realuser eq $user ||
		return "Original username is $realuser, not $user";
	}

# Check for clashes
$prefix ||= &compute_prefix($dom, undef, $parent);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && return "A virtual server using the prefix $prefix already exists";

return undef;
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

# Work out user and group
local $group = $user;
local $ugroup = $group;
local $root = &extract_plesk_dir($file);
local $dump = &read_plesk_xml("$root/dump.xml");
local $domain = $dump->{'domain'};
if (ref($domain) eq 'ARRAY') {
	$domain = $domain->[0];
	}

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix"), "web" );
push(@got, "webmin") if ($webmin && !$parent);
if (exists($domain->{'mailsystem'}->{'status'}->{'enabled'})) {
	push(@got, "mail");
	}
if ($domain->{'dns-zone'}) {
	push(@got, "dns");
	}
if ($domain->{'www'} eq 'true') {
	push(@got, "web");
	}
if ($domain->{'ip'}->{'ip-type'} eq 'exclusive' && $virt) {
	push(@got, "ssl");
	}
if ($domain->{'phosting'}->{'logrotation'}->{'enabled'} eq 'true') {
	push(@got, "logrotate");
	}
if ($domain->{'phosting'}->{'webalizer'}) {
	push(@got, "webalizer");
	}

# Check for MySQL databases
local $databases = $domain->{'phosting'}->{'sapp-installed'}->{'database'};
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
local $mailusers = $domain->{'mailsystem'}->{'mailuser'};
if (!$mailusers) {
	$mailusers = { };
	}
elsif ($mailusers->{'mailbox-quota'}) {
	# Just one user
	$mailusers = { $mailusers->{'name'} => $mailusers };
	}
local ($has_spam, $has_virus);
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
local (%gtaken, %ggtaken, %taken, %utaken);
&build_group_taken(\%gtaken, \%ggtaken);
&build_taken(\%taken, \%utaken);
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
	# Allocate new IDs
	$gid = &allocate_gid(\%gtaken);
	$ugid = $gid;
	$uid = &allocate_uid(\%taken);
	$duser = $user;
	}

# Get the quota and domain password
local $bsize = &has_home_quotas() ? &quota_bsize("home") : undef;
local $quota;
if (!$parent && &has_home_quotas()) {
	$quota = $domain->{'phosting'}->{'sysuser'}->{'quota'} / $bsize;
	}
if (!$parent) {
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
local $htdocs = "$root/$dom.httpdocs";
if (-r $htdocs) {
	local $hdir = &public_html_dir(\%dom);
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

# Re-create DNS records
# XXX

# Re-create mail users and copy mail files
&$first_print("Re-creating mail users ..");
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mcount = 0;
foreach my $name (keys %$mailusers) {
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
	local %taken;
	&build_taken(\%taken);
	$uinfo->{'uid'} = &allocate_uid(\%taken);
	$uinfo->{'gid'} = $dom{'gid'};
	$uinfo->{'home'} = "$dom{'home'}/$config{'homes_dir'}/$name";
	$uinfo->{'shell'} = $config{'shell'};
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
&$second_print(".. done (migrated $mcount)");

# Re-create mail aliases
local $acount = 0;
&$first_print("Re-creating mail aliases ..");
&set_alias_programs();
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
&$second_print(".. done (migrated $acount)");

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
		&save_domain(\%dom);
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
			local %taken;
			&build_taken(\%taken);
			$myuinfo->{'uid'} = &allocate_uid(\%taken);
			$myuinfo->{'gid'} = $dom{'gid'};
			$myuinfo->{'real'} = "MySQL user";
			$myuinfo->{'home'} =
				"$dom{'home'}/$config{'homes_dir'}/$myuser";
			$myuinfo->{'shell'} = $config{'shell'};
			delete($myuinfo->{'email'});
			$myuinfo->{'dbs'} = [ { 'type' => 'mysql',
					        'name' => $name } ];
			&create_user($myuinfo, \%dom);
			&create_user_home($myuinfo, \%dom);
			&create_mail_file($myuinfo);
			$myucount++;
			}

		&$outdent_print();
		$mcount++;
		}
	&$second_print(".. done (migrated $mcount, and created $myucount users)");
	}

return (\%dom);
}

# extract_plesk_dir(file)
# Extracts all attachments from a plesk backup in MIME format to a temp
# directory, and returns the path.
sub extract_plesk_dir
{
local ($file) = @_;
local $dir = &transname();
&make_dir($dir, 0700);

# Is this compressed?
local $cf = &compression_format($file);
if ($cf != 0 && $cf != 1) {
	return undef;
	}

# Read in the backup as a fake mail object
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mail = { };
if ($cf == 0) {
	open(FILE, $file) || return undef;
	}
else {
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
return undef if (!$count);	# No attachments!

return $dir;
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

1;

