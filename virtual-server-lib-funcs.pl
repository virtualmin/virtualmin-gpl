
# Work out where our extra -lib.pl files are, and load them
$virtual_server_root = $module_root_directory;
if (!$virtual_server_root) {
	foreach my $i (keys %INC) {
		if ($i =~ /^(.*)\/virtual-server-lib-funcs.pl$/) {
			$virtual_server_root = $1;
			}
		}
	}
if (!$virtual_server_root) {
	$0 =~ /^(.*)\//;
	$virtual_server_root = "$1/virtual-server";
	}
foreach my $lib ("scripts", "resellers", "admins", "simple", "s3", "styles",
		 "php", "ruby", "vui", "dynip", "collect", "maillog",
		 "balancer") {
	do "$virtual_server_root/$lib-lib.pl";
	if ($@ && -r "$virtual_server_root/$lib-lib.pl") {
		print STDERR "failed to load $lib-lib.pl : $@\n";
		}
	}

# require_useradmin([no-quotas])
sub require_useradmin
{
if (!$require_useradmin++) {
	&foreign_require("useradmin", "user-lib.pl");
	%uconfig = &foreign_config("useradmin");
	$home_base = &resolve_links($config{'home_base'} || $uconfig{'home_base'});
	if ($config{'ldap'}) {
		&foreign_require("ldap-useradmin", "ldap-useradmin-lib.pl");
		$usermodule = "ldap-useradmin";
		}
	else {
		$usermodule = "useradmin";
		}
	}
if (!&has_quota_commands() && !$_[0] && !$require_useradmin_quota++) {
	&foreign_require("quota", "quota-lib.pl");
	}
}

# Bring in libraries used for migrating from other servers
sub require_migration
{
foreach my $m (@migration_types) {
	do "$module_root_directory/migration-$m.pl";
	}
}

# list_domains()
# Returns a list of structures containing information about hosted domains
sub list_domains
{
local (@rv, $d);
opendir(DIR, $domains_dir);
foreach $d (readdir(DIR)) {
	if ($d !~ /^\./ && $d !~ /\.(lock|bak|rpmsave|sav|swp|webmintmp|~)$/i) {
		push(@rv, &get_domain($d));
		}
	}
closedir(DIR);
return @rv;
}

# get_domain(id, [file])
# Looks up a domain object by ID
sub get_domain
{
return undef if (!$_[0] && !$_[1]);
if ($_[0] && defined($main::get_domain_cache{$_[0]})) {
	return $main::get_domain_cache{$_[0]};
	}
local %dom;
local $file = $_[1] || "$domains_dir/$_[0]";
&read_file($file, \%dom) || return undef;
$dom{'file'} = "$domains_dir/$_[0]";
$dom{'id'} ||= $_[0];
&complete_domain(\%dom);
if (!defined($dom->{'created'})) {
	# compat - creation date can be inferred from ID
        $dom->{'id'} =~ /^(\d{10})/;
        $dom->{'created'} = $1;
        }
delete($dom->{'missing'});	# never set in a saved domain
if ($_[0]) {
	$main::get_domain_cache{$_[0]} = \%dom;
	}
return \%dom;
}

# complete_domain(&domain)
# Fills in any missing fields in a domain object
sub complete_domain
{
local ($dom) = @_;
$dom->{'mail'} = 1 if (!defined($dom->{'mail'}));	# compat - assume mail is on
if (!defined($dom->{'ugid'})) {
	# compat - assume user's group is domain's group
	$dom->{'ugid'} = $dom->{'gid'}
	}
if (!defined($dom->{'ugroup'}) && defined($dom->{'ugid'})) {
	$dom->{'ugroup'} = getgrgid($dom->{'ugid'});
	}
if ($dom->{'disabled'} eq '1') {
	# compat - assume everything was disabled
	$dom->{'disabled'} = "unix,web,dns,mail,mysql,postgres";
	}
elsif ($dom->{'disabled'}) {
	# compat - user disabled has changed to unix
	$dom->{'disabled'} =~ s/user/unix/g;
	}
if ($dom->{'disabled'}) {
	# Manually disabled
	$dom->{'disabled_reason'} ||= 'manual';
	}
if (!defined($dom->{'gid'}) && defined($dom->{'group'})) {
	# compat - get GID from group name
	$dom->{'gid'} = getgrnam($dom->{'group'});
	}
if (!defined($dom->{'unix'}) && !$dom->{'parent'}) {
	# compat - unix is always on for parent domains
	$dom->{'unix'} = 1;
	}
if (!defined($dom->{'dir'})) {
	# if unix is on, so is home
	$dom->{'dir'} = $dom->{'unix'};
	if ($dom->{'parent'}) {
		# if server has a parent, it never has a Unix user
		$dom->{'unix'} = 0;
		}
	}
if (!defined($dom->{'limit_unix'})) {
	# compat - unix is always available for subdomains
	$dom->{'limit_unix'} = 1;
	}
if (!defined($dom->{'limit_dir'})) {
	# compat - home is always available for subdomains
	$dom->{'limit_dir'} = 1;
	}
if (!defined($dom->{'virt'})) {
	# compat - assume virtual IP if interface assigned
	$dom->{'virt'} = $dom->{'iface'} ? 1 : 0;
	}
if (!defined($dom->{'web_port'}) && $dom->{'web'}) {
	# compat - assume web port is current setting
	$dom->{'web_port'} = $default_web_port;
	}
if (!defined($dom->{'web_sslport'}) && $dom->{'ssl'}) {
	# compat - assume SSL port is current setting
	$dom->{'web_sslport'} = $web_sslport;
	}
if (!defined($dom->{'prefix'})) {
	# compat - assume that prefix is same as group
	$dom->{'prefix'} = $dom->{'group'};
	}
if (!defined($dom->{'home'})) {
	local @u = getpwnam($dom->{'user'});
	$dom->{'home'} = $u[7];
	}
if (!defined($dom->{'proxy_pass_mode'}) && $dom->{'proxy_pass'}) {
	# assume that proxy pass mode is proxy-based if not set
	$dom->{'proxy_pass_mode'} = 1;
	}
if (!defined($dom->{'template'})) {
	# assume default parent or sub-server template
	$dom->{'template'} = $dom->{'parent'} ? 1 : 0;
	}
if (!defined($dom->{'db_mysql'}) && $dom->{'mysql'}) {
	# Assume just one MySQL DB
	$dom->{'db_mysql'} = $dom->{'db'};
	}
$dom->{'db_mysql'} = join(" ", &unique(split(/\s+/, $dom->{'db_mysql'})));
if (!defined($dom->{'db_postgres'}) && $dom->{'postgres'}) {
	# Assume just one PostgreSQL DB
	$dom->{'db_postgres'} = $dom->{'db'};
	}
$dom->{'db_postgres'} = join(" ", &unique(split(/\s+/, $dom->{'db_postgres'})));
# This is a computed field
local $parent;
if ($dom->{'email'}) {
	$dom->{'emailto'} = $dom->{'email'};
	}
elsif ($dom->{'parent'} && ($parent = &get_domain($dom->{'parent'}))) {
	$dom->{'emailto'} = $parent->{'emailto'};
	}
elsif ($dom->{'mail'}) {
	$dom->{'emailto'} = $dom->{'user'}.'@'.$dom->{'dom'};
	}
else {
	$dom->{'emailto'} = $dom->{'user'}.'@'.&get_system_hostname();
	}
# Set edit limits based on ability to edit domains
foreach my $ed (@edit_limits) {
	if (!defined($dom->{'edit_'.$ed})) {
		$dom->{'edit_'.$ed} = $ed eq "users" || $ed eq "aliases" ||
				      $ed eq "html" ? 1 :
				      $dom->{'domslimit'} ? 1 : 0;
		}
	}
delete($dom->{'pass_set'});	# Only set by callers for modify_* functions
}

# get_domain_by(field, value, [field, value, ...])
# Looks up a domain by some field(s). For each field, we either use the quick
# map to find relevant domains, or check though all that we have left.
sub get_domain_by
{
local @rv;
for(my $i=0; $i<@_; $i+=2) {
	local $mf = $get_domain_by_maps{$_[$i]};
	local @possible;
	local %map;
	if ($mf && &read_file_cached($mf, \%map)) {
		# The map knows relevant domains
		foreach my $did (split(" ", $map{$_[$i+1]})) {
			local $d = &get_domain($did);
			push(@possible, $d) if ($d);
			}
		}
	else {
		# Need to check manually
		@possible = grep { $_->{$_[$i]} eq $_[$i+1] } &list_domains();
		}
	if ($i == 0) {
		# First field, so matches are the result
		@rv = @possible;
		}
	else {
		# Later field, so winnow down prevent results with new set
		local %possible = map { $_->{'id'}, $_ } @possible;
		@rv = grep { $possible{$_->{'id'}} } @rv;
		}
	}
return wantarray ? @rv : $rv[0];
}

# domain_id()
# Returns a new unique domain ID
sub domain_id
{
return time().$$;
}

# save_domain(&domain)
# Write domain information to disk
sub save_domain
{
&make_dir($domains_dir, 0700);
&lock_file("$domains_dir/$_[0]->{'id'}");
if (!$_[0]->{'created'}) {
	$_[0]->{'created'} = time();
	$_[0]->{'creator'} ||= $remote_user;
	$_[0]->{'creator'} ||= getpwuid($<);
	}
$_[0]->{'id'} ||= &domain_id();
&write_file("$domains_dir/$_[0]->{'id'}", $_[0]);
&unlock_file("$domains_dir/$_[0]->{'id'}");
$main::get_domain_cache{$_[0]->{'id'}} = $_[0];
&build_domain_maps();
return 1;
}

# delete_domain(&domain)
# Delete all of Virtualmin's internal information about a domain
sub delete_domain
{
local $id = $_[0]->{'id'};
&unlink_logged("$domains_dir/$id");

# And the bandwidth and plain-text password files
&unlink_file("$bandwidth_dir/$id");
&unlink_file("$plainpass_dir/$id");

if (defined(&get_autoreply_file_dir)) {
	# Delete any autoreply file links
	local $dir = &get_autoreply_file_dir();
	opendir(AUTODIR, $dir);
	foreach my $f (readdir(AUTODIR)) {
		next if ($f eq "." || $f eq "..");
		if ($f =~ /^\Q$id-\E/) {
			unlink("$dir/$f");
			}
		}
	closedir(AUTODIR);
	}
delete($main::get_domain_cache{$_[0]->{'id'}});
&build_domain_maps();
}

# build_domain_maps()
# Create the files used by get_domain_by to quickly lookup domains by user
# or parent 
sub build_domain_maps
{
local @doms = &list_domains();
foreach my $m (keys %get_domain_by_maps) {
	local %map;
	foreach my $d (@doms) {
		local $v = $d->{$m};
		#next if ($v eq '');
		if (!defined($map{$v})) {
			$map{$v} = $d->{'id'};
			}
		else {
			$map{$v} .= " ".$d->{'id'};
			}
		}
	&write_file($get_domain_by_maps{$m}, \%map);
	}
}

# list_domain_users([&domain], [skipunix], [no-virts], [no-quotas], [no-dbs])
# List all Unix users who are in the domain's primary group.
# If domain is omitted, returns local users.
sub list_domain_users
{
local ($d, $skipunix, $novirts, $noquotas, $nodbs) = @_;

# Get all aliases (and maybe generics) to look for those that match users
local (%aliases, %generics);
if ($config{'mail'} && !$novirts) {
	&require_mail();
	if ($config{'mail_system'} == 1) {
		# Find Sendmail aliases for users
		%aliases = map { $_->{'name'}, $_ } grep { $_->{'enabled'} }
			       &sendmail::list_aliases($sendmail_afiles);
		}
	elsif ($config{'mail_system'} == 0) {
		# Find Postfix aliases for users
		%aliases = map { $_->{'name'}, $_ }
			       &postfix::list_aliases($postfix_afiles);
		}
	elsif ($config{'mail_system'} == 5) {
		# Find VPOPMail aliases to match with users
		%valiases = map { $_->{'from'}, $_ } &list_virtusers();
		}
	if ($config{'generics'}) {
		%generics = &get_generics_hash();
		}
	}

# Get all virtusers to look for those for users
local @virts;
if (!$_[2]) {
	@virts = &list_virtusers();
	}

# Are we setting quotas individually?
local $ind_quota = 0;
if (&has_quota_commands() && $config{'quota_get_user_command'} && $_[0]) {
	$ind_quota = 1;
	}

local @users = &list_all_users_quotas($noquotas || $ind_quota);
if ($_[0]) {
	# Limit to domain users.
	@users = grep { defined($_[0]->{'gid'}) &&
			$_->{'gid'} == $_[0]->{'gid'} ||
			$_->{'user'} eq $_[0]->{'user'} } @users;
	foreach my $u (@users) {
		if ($u->{'user'} eq $_[0]->{'user'} && $u->{'unix'}) {
			# Virtual server owner
			$u->{'domainowner'} = 1;
			}
		elsif ($u->{'uid'} == $_[0]->{'uid'} && $u->{'unix'}) {
			# Web management user
			$u->{'webowner'} = 1;
			$u->{'noquota'} = 1;
			$u->{'noprimary'} = 1;
			$u->{'noextra'} = 1;
			$u->{'noalias'} = 1;
			$u->{'nocreatehome'} = 1;
			$u->{'nomailfile'} = 1;
			delete($u->{'email'});
			}
		if ($ind_quota && !$noquotas) {
			# Call quota getting command for each user
			local $out = &run_quota_command(
					"get_user", $u->{'user'});
			local ($used, $soft, $hard) = split(/\s+/, $out);
			$u->{'softquota'} = $soft;
			$u->{'hardquota'} = $hard;
			$u->{'uquota'} = $used;
			}
		}
	local @subdoms;
	if ($_[0]->{'parent'}) {
		# This is a subdomain - exclude parent domain users
		@users = grep { $_->{'home'} =~ /^$_[0]->{'home'}\// } @users;
		}
	elsif (@subdoms = &get_domain_by("parent", $_[0]->{'id'})) {
		# This domain has subdomains - exclude their users
		@users = grep { $_->{'home'} !~ /^$_[0]->{'home'}\/domains\// } @users;
		}
	@users = grep { !$_->{'domainowner'} } @users
		if ($_[1] || $_[0]->{'parent'});

	# Remove users with @ in their names for whom a user with the @ replace
	# already exists (for Postfix)
	if ($config{'mail_system'} == 0) {
		local %umap = map { &replace_atsign($_->{'user'}), $_ }
				grep { $_->{'user'} =~ /\@/ } @users;
		@users = grep { !$umap{$_->{'user'}} } @users;
		}

	if ($config{'mail_system'} == 4) {
		# Add Qmail LDAP users (who have same GID?)
		local $ldap = &connect_qmail_ldap();
		local $rv = $ldap->search(base => $config{'ldap_base'},
				  filter => "(&(objectClass=qmailUser)(|(qmailGID=$_[0]->{'gid'})(gidNumber=$_[0]->{'gid'})))");
		&error($rv->error) if ($rv->code);
		foreach $u ($rv->all_entries) {
			local %uinfo = &qmail_dn_to_hash($u);
			next if (!$uinfo{'mailstore'});	# alias only
			$uinfo{'ldap'} = $u;
                        if ($_[0]->{'parent'}) {
                                # In sub-domain, exclude parent domain users
                                next if ($_->{'home'} !~ /^$_[0]->{'home'}\//);
                                }
                        elsif (@subdoms) {
                                # In parent domain exclude sub-domain users
                                next if ($_->{'home'} =~ /^$_[0]->{'home'}\/doma
ins\//);
                                }
			@users = grep { $_->{'user'} ne $uinfo{'user'} } @users;
			push(@users, \%uinfo);
			}
		$ldap->unbind();
		}
	elsif ($config{'mail_system'} == 5) {
		# Add VPOPMail users for this domain
		local %attr_map = ( 'name' => 'user',
				    'passwd' => 'pass',
				    'clear passwd' => 'plainpass',
				    'comment/gecos' => 'real',
				    'dir' => 'home',
				    'quota' => 'qquota',
				   );
		local $user;
		local $_;
		open(UINFO, "$vpopbin/vuserinfo -D $_[0]->{'dom'} |");
		while(<UINFO>) {
			s/\r|\n//g;
			if (/^([^:]+):\s+(.*)$/) {
				local ($attr, $value) = ($1, $2);
				if ($attr eq "name") {
					# Start of a new user
					$user = { 'vpopmail' => 1,
						  'mailquota' => 1,
						  'person' => 1,
						  'fixedhome' => 1,
						  'noappend' => 1,
						  'noprimary' => 1,
						  'alwaysplain' => 1 };
					push(@users, $user);
					}
				local $amapped = $attr_map{$attr};
				$user->{$amapped} = $value if ($amapped);
				if ($amapped eq "qquota") {
					if ($value eq "NOQUOTA") {
						$user->{$amapped} = 0;
						}
					else {
						$user->{$amapped} = int($value);
						}
					}
				}
			}
		close(UINFO);
		}

	# Find users with broken home dir
	foreach my $u (@users) {
		if ($u->{'home'} &&
		    $u->{'home'} !~ /^$d->{'home'}\/$config{'homes_dir'}\// &&
		    !&is_under_directory($d->{'home'}, $u->{'home'})) {
			$u->{'brokenhome'} = 1;
			}
		}

	# Merge in plain text passwords
	local (%plain, $need_plainpass_save);
	&read_file("$plainpass_dir/$d->{'id'}", \%plain);
	foreach my $u (@users) {
		if ($u->{'domainowner'}) {
			# The domain owner's password is always known
			$u->{'plainpass'} = $d->{'pass'};
			}
		elsif (!defined($u->{'plainpass'}) &&
		    defined($plain{$u->{'user'}})) {
			# Check if the plain password is valid, in case the
			# crypted password was changed behind our back
			if ($plain{$u->{'user'}." encrypted"} eq $u->{'pass'} ||
			    &encrypt_user_password($u, $plain{$u->{'user'}}) eq
			    $u->{'pass'} ||
			    &unix_crypt($plain{$u->{'user'}}, $u->{'pass'}) eq
			    $u->{'pass'}) {
				# Valid - we can use it
				$u->{'plainpass'} = $plain{$u->{'user'}};
				if (!defined($plain{$u->{'user'}." encrypted"})) {
					# Save the correct crypted version now
					$plain{$u->{'user'}." encrypted"} =
						$u->{'pass'};
					$need_plainpass_save = 1;
					}
				}
			}
		}
	if ($need_plainpass_save) {
		&write_file("$plainpass_dir/$d->{'id'}", \%plain);
		}
	}
else {
	# Limit to local users
	local @lg = getgrnam($config{'localgroup'});
	@users = grep { $_->{'gid'} == $lg[2] } @users;
	}

# Set appropriate quota field
local $tmpl = &get_template($_[0] ? $_[0]->{'template'} : 0);
local $qtype = $tmpl->{'quotatype'};
local $u;
foreach $u (@users) {
	$u->{'quota'} = $u->{$qtype.'quota'} if (!defined($u->{'quota'}));
	$u->{'mquota'} = $u->{$qtype.'mquota'} if (!defined($u->{'mquota'}));
	}

# Detect user who are close to their quota
if (&has_home_quotas()) {
	local $bsize = &quota_bsize("home");
	foreach $u (@users) {
		local $diff = $u->{'quota'}*$bsize - $u->{'uquota'}*$bsize;
		if ($u->{'quota'} && $diff < $quota_spam_margin &&
		    $_[0]->{'spam'}) {
			# Close to quota, which will block spamassassin ..
			$u->{'spam_quota'} = 1;
			$u->{'spam_quota_diff'} = $diff < 0 ? 0 : $diff;
			}
		}
	}

if (!$_[2]) {
	# Add email addresses and forwarding addresses to user structures
	local $u;
	foreach $u (@users) {
		next if ($u->{'qmail'});	# got from LDAP already
		$u->{'email'} = $u->{'virt'} = undef;
		$u->{'alias'} = $u->{'to'} = $u->{'generic'} = undef;
		$u->{'extraemail'} = $u->{'extravirt'} = undef;
		local ($al, $va);
		if ($al = $aliases{&escape_alias($u->{'user'})}) {
			$u->{'alias'} = $al;
			$u->{'to'} = $al->{'values'};
			}
		elsif ($va = $valiases{"$u->{'user'}\@$_[0]->{'dom'}"}) {
			$u->{'valias'} = $va;
			$u->{'to'} = $va->{'to'};
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# Find .qmail file
			local $alias = &get_dotqmail(&dotqmail_file($u));
			if ($alias) {
				$u->{'alias'} = $alias;
				$u->{'to'} = $u->{'alias'}->{'values'};
				}
			}
		$u->{'generic'} = $generics{$u->{'user'}};
		local $pop3 = $_[0] ? &remove_userdom($u->{'user'}, $_[0])
				    : $u->{'user'};
		local $email = $_[0] ? "$pop3\@$_[0]->{'dom'}" : undef;
		local $escuser = &escape_user($u->{'user'});
		local $escalias = &escape_alias($u->{'user'});
		local $v;
		foreach $v (@virts) {
			if (@{$v->{'to'}} == 1 &&
			    ($v->{'to'}->[0] eq $escuser ||
			     $v->{'to'}->[0] eq $escalias ||
			     $v->{'to'}->[0] eq $email ||
			     $v->{'from'} eq $email &&
			      $v->{'to'}->[0] =~ /^BOUNCE/) &&
			    (!$_[0] || $v->{'from'} ne $_[0]->{'dom'})) {
				if ($v->{'from'} eq $email) {
					if ($v->{'to'}->[0] !~ /^BOUNCE/) {
						$u->{'email'} = $email;
						}
					$u->{'virt'} = $v;
					}
				else {
					push(@{$u->{'extraemail'}},
					     $v->{'from'});
					push(@{$u->{'extravirt'}}, $v);
					}
				}
			}
		}
	}

if (!$_[4] && $_[0]) {
	# Add accessible databases
	local @dbs = &domain_databases($_[0]);
	local $db;
	foreach $db (@dbs) {
		local @dbu;
		local $ufunc;
		if (&indexof($db->{'type'}, @database_plugins) < 0) {
			# Core database
			local $dfunc = "list_".$db->{'type'}."_database_users";
			next if (!defined(&$dfunc));
			$ufunc = $db->{'type'}."_username";
			@dbu = &$dfunc($_[0], $db->{'name'});
			}
		else {
			# Plugin database
			next if (!&plugin_defined($db->{'type'},
						  "database_users"));
			@dbu = &plugin_call($db->{'type'}, "database_users",
					    $_[0], $db->{'name'});
			}
		local %dbu = map { $_->[0], $_->[1] } @dbu;
		local $u;
		foreach $u (@users) {
			# Domain owner always gets all databases
			next if ($u->{'user'} eq $_[0]->{'user'} &&
				 $u->{'unix'});
			local $uname = $ufunc ? &$ufunc($u->{'user'}) :
				&plugin_call($db->{'type'}, "database_user",
					     $u->{'user'});
			if (exists($dbu{$uname})) {
				push(@{$u->{'dbs'}}, $db);
				$u->{$db->{'type'}."_user"} = $uname;
				$u->{$db->{'type'}."_pass"} = $dbu{$uname};
				}
			}
		}

	# Add plugin databases
	local @dbs = &domain_databases($_[0]);
	foreach $db (@dbs) {
		next if (&indexof($db->{'type'}, @database_plugins) == -1);
		}
	}

local @sgroups = &allowed_secondary_groups($_[0]);
if (@sgroups) {
	# Add any secondary groups in the template
	local @groups = &list_all_groups();
	foreach my $u (@users) {
		$u->{'secs'} = [ ];
		}
	foreach my $g (@sgroups) {
		local ($group) = grep { $_->{'group'} eq $g } @groups;
		if ($group) {
			local %mems = map { $_, 1 }
					  split(/,/, $group->{'members'});
			foreach my $u (@users) {
				if ($mems{$u->{'user'}}) {
					push(@{$u->{'secs'}}, $g);
					}
				}
			}
		}
	}

return @users;
}

# list_all_users_quotas([no-quotas])
# Returns a list of all Unix users, with quota info
sub list_all_users_quotas
{
# Get quotas for all users
&require_useradmin($_[0]);
if (&has_quota_commands()) {
	# Get from user quota command
	if (!defined(%soft_home_quota) && !$_[0]) {
		local $out = &run_quota_command("list_users");
		foreach my $l (split(/\r?\n/, $out)) {
			local ($user, $used, $soft, $hard) = split(/\s+/, $l);
			$soft_home_quota{$user} = $soft;
			$hard_home_quota{$user} = $hard;
			$used_home_quota{$user} = $used;
			}
		}
	}
else {
	# Get from real quota system
	if (!defined(%soft_home_quota) && &has_home_quotas() && !$_[0]) {
		local $n = &quota::filesystem_users($config{'home_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$soft_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'sblocks'};
			$hard_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'hblocks'};
			$used_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ublocks'};
			}
		}
	if (!defined(%soft_mail_quota) && &has_mail_quotas() && !$_[0]) {
		local $n = &quota::filesystem_users($config{'mail_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$soft_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'sblocks'};
			$hard_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'hblocks'};
			$used_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ublocks'};
			}
		}
	}

# Get user list and add in quota info
local @users = &foreign_call($usermodule, "list_users");
local $u;
foreach $u (@users) {
	$u->{'module'} = $usermodule;
	$u->{'softquota'} = $soft_home_quota{$u->{'user'}};
	$u->{'hardquota'} = $hard_home_quota{$u->{'user'}};
	$u->{'uquota'} = $used_home_quota{$u->{'user'}};
	$u->{'softmquota'} = $soft_mail_quota{$u->{'user'}};
	$u->{'hardmquota'} = $hard_mail_quota{$u->{'user'}};
	$u->{'umquota'} = $used_mail_quota{$u->{'user'}};
	$u->{'unix'} = 1;
	$u->{'person'} = 1;
	}
return @users;
}

# create_user(&user, [&domain])
# Create a mailbox or local user, his virtuser and possibly his alias
sub create_user
{
local $pop3 = &remove_userdom($_[0]->{'user'}, $_[1]);
&require_useradmin();
&require_mail();

if ($_[0]->{'qmail'}) {
	# Create user in Qmail LDAP
	local $ldap = &connect_qmail_ldap();
	local $_[0]->{'dn'} = "uid=$_[0]->{'user'},$config{'ldap_base'}";
	local @oc = ( "qmailUser" );
	push(@oc, "posixAccount") if ($_[0]->{'unix'});
	push(@oc, split(/\s+/, $config{'ldap_classes'}));
	local $attrs = &qmail_user_to_dn($_[0], \@oc, $_[1]);
	push(@$attrs, "objectClass" => \@oc);
	local $rv = $ldap->add($_[0]->{'dn'}, attr => $attrs);
	&error($rv->error) if ($rv->code);
	$ldap->unbind();
	}
elsif ($_[0]->{'vpopmail'}) {
	# Create user in VPOPMail
	local $quser = quotemeta($_[0]->{'user'});
	local $qdom = $_[1]->{'dom'};
	local $qreal = quotemeta($_[0]->{'real'}) || '""';
	local $quota = $_[0]->{'qquota'} ? "-q $_[0]->{'qquota'}" : "-q NOQUOTA";
	local $qpass = quotemeta($_[0]->{'plainpass'});
	local $cmd = "$vpopbin/vadduser $quota -c $qreal $quser\@$qdom $qpass";
	local $out = &backquote_logged("$cmd 2>&1");
	&error("<tt>$cmd</tt> failed: <pre>$out</pre>") if ($?);
	$_[0]->{'home'} = "$config{'vpopmail_dir'}/domains/$_[1]->{'dom'}/$_[0]->{'user'}";
	}
else {
	# Add the Unix user
	if ($config{'ldap_mail'}) {
		if ($_[0]->{'email'}) {
			push(@{$_[0]->{'ldap_attrs'}}, "mail",$_[0]->{'email'});
			}
		push(@{$_[0]->{'ldap_attrs'}},
		     map { ( "mail", $_ ) } @{$_[0]->{'extraemail'}});
		}
	&foreign_call($usermodule, "set_user_envs", $_[0], 'CREATE_USER', $_[0]->{'plainpass'}, [ ]);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "lock_user_files");
	&userdom_substitutions($_[0], $_[1]);
	&foreign_call($usermodule, "create_user", $_[0]);
	&foreign_call($usermodule, "unlock_user_files");
	&foreign_call($usermodule, "made_changes");
	}

# If we are running Postfix and the username has an @ in it, create an extra
# Unix user without the @ but all the other details the same
local $extrauser;
if ($config{'mail_system'} == 0 && $_[0]->{'user'} =~ /\@/ &&
    !$_[0]->{'webowner'}) {
	$extrauser = { %{$_[0]} };
	$extrauser->{'user'} = &replace_atsign($extrauser->{'user'});
	&foreign_call($usermodule, "set_user_envs", $extrauser, 'CREATE_USER', $extrauser->{'plainpass'}, [ ]);
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "lock_user_files");
	&userdom_substitutions($extrauser, $_[1]);
	&foreign_call($usermodule, "create_user", $extrauser);
	&foreign_call($usermodule, "unlock_user_files");
	&foreign_call($usermodule, "made_changes");
	}

local $firstemail;
local @to = @{$_[0]->{'to'}};
if (!$_[0]->{'qmail'}) {
	# Add his virtusers for non Qmail+LDAP users
	local $vto = @to ? &escape_alias($_[0]->{'user'}) :
		     $extrauser ? $extrauser->{'user'} :
				  &escape_user($_[0]->{'user'});
	if ($_[0]->{'email'}) {
		local $virt = { 'from' => $_[0]->{'email'},
				'to' => [ $vto ] };
		&create_virtuser($virt);
		$_[0]->{'virt'} = $virt;
		$firstemail ||= $_[0]->{'email'};
		}
	elsif ($can_alias_types{9} && $_[1] && !$_[0]->{'noprimary'} &&
	       $_[1]->{'mail'}) {
		# Add bouncer if email disabled
		local $virt = { 'from' => "$pop3\@$_[1]->{'dom'}",
				'to' => [ "BOUNCE" ] };
		&create_virtuser($virt);
		$_[0]->{'virt'} = $virt;
		}
	local @extravirt;
	local $e;
	foreach $e (@{$_[0]->{'extraemail'}}) {
		local $virt = { 'from' => $e,
				'to' => [ $vto ] };
		&create_virtuser($virt);
		push(@extravirt, $virt);
		$firstemail ||= $e;
		}
	$_[0]->{'extravirt'} = \@extravirt;
	}

if (!$_[0]->{'qmail'}) {
	# Add his alias, if any, for non Qmail+LDAP users
	if (@to) {
		local $alias = { 'name' => &escape_alias($_[0]->{'user'}),
				 'enabled' => 1,
				 'values' => $_[0]->{'to'} };
		&check_alias_clash($_[0]->{'user'}) &&
			&error(&text('alias_eclash2', $_[0]->{'user'}));
		if ($config{'mail_system'} == 1) {
			&sendmail::lock_alias_files($sendmail_afiles);
			&sendmail::create_alias($alias, $sendmail_afiles);
			&sendmail::unlock_alias_files($sendmail_afiles);
			}
		elsif ($config{'mail_system'} == 0) {
			&postfix::lock_alias_files($postfix_afiles);
			&postfix::create_alias($alias, $postfix_afiles);
			&postfix::unlock_alias_files($postfix_afiles);
			&postfix::regenerate_aliases();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# Set up user's .qmail file
			local $dqm = &dotqmail_file($_[0]);
			&lock_file($dqm);
			&save_dotqmail($alias, $dqm, $pop3);
			&unlock_file($dqm);
			}
		$_[0]->{'alias'} = $alias;
		}

	if ($config{'generics'} && $firstemail) {
		# Add genericstable entry too
		&create_generic($_[0]->{'user'}, $firstemail);
		}
	}

if ($_[0]->{'unix'} && !$_[0]->{'noquota'}) {
	# Set his initial quotas
	&set_user_quotas($_[0]->{'user'}, $_[0]->{'quota'}, $_[0]->{'mquota'},
			 $_[1]);
	}

# Grant access to databases (unless this is the domain owner)
if ($_[1] && !$_[0]->{'domainowner'}) {
	local $dt;
	foreach $dt (&unique(map { $_->{'type'} } &domain_databases($_[1]))) {
		local @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
		if (@dbs && &indexof($dt, @database_plugins) < 0) {
			# Create in core database
			local $crfunc = "create_${dt}_database_user";
			&$crfunc($_[1], \@dbs, $_[0]->{'user'},
				 $_[0]->{'plainpass'}, $_[0]->{$dt.'_pass'});
			}
		elsif (@dbs && &indexof($dt, @database_plugins) >= 0) {
			# Create in plugin database
			&plugin_call($dt, "database_create_user",
				     $_[1], \@dbs, $_[0]->{'user'},
				     $_[0]->{'plainpass'},$_[0]->{$dt.'_pass'});
			}
		}
	}

# Add user to any secondary groups
local @groups;
@groups = &list_all_groups() if (@{$_[0]->{'secs'}});
foreach my $g (@{$_[0]->{'secs'}}) {
	local ($group) = grep { $_->{'group'} eq $g } @groups;
	if ($group) {
		local @mems = split(/,/, $group->{'members'});
		push(@mems, $_[0]->{'user'});
		$group->{'members'} = join(",", @mems);
		&foreign_call($group->{'module'}, "modify_group",
			      $group, $group);
		}
	}

# Update secondary groups for mail/FTP/db users
&update_secondary_groups($_[1]) if ($_[1]);

# Update spamassassin whitelist
if ($virtualmin_pro) {
	&update_spam_whitelist($_[1]) if ($_[1]);
	}

# Save the plain-text password, if known
mkdir($plainpass_dir, 0700);
if (defined($_[0]->{'plainpass'})) {
	local %plain;
	&read_file("$plainpass_dir/$_[1]->{'id'}", \%plain);
	$plain{$_[0]->{'user'}} = $_[0]->{'plainpass'};
	$plain{$_[0]->{'user'}." encrypted"} = $_[0]->{'pass'};
	&write_file("$plainpass_dir/$_[1]->{'id'}", \%plain);
	}

# Set the user's Usermin IMAP password
&set_usermin_imap_password($_[0]);

# Update cache of existing usernames
$unix_user{&escape_alias($_[0]->{'user'})}++;
}

# modify_user(&user, &old, &domain, [noaliases])
# Update a mail / FTP user
sub modify_user
{
# Rename any of his cron jobs
if ($_[0]->{'unix'}) {
	&rename_unix_cron_jobs($_[0]->{'user'}, $_[1]->{'user'});
	}

local $pop3 = &remove_userdom($_[0]->{'user'}, $_[2]);
local $extrauser;
if ($_[1]->{'qmail'}) {
	# Update user in Qmail LDAP
	local $ldap = &connect_qmail_ldap();
	local $_[0]->{'dn'} = "uid=$_[0]->{'user'},$config{'ldap_base'}";
	local ($attrs, $delattrs) = &qmail_user_to_dn($_[0],
		[ $_[1]->{'ldap'}->get_value("objectClass") ], $_[2]);
	@$delattrs = grep { defined($_[1]->{'ldap'}->get_value($_))} @$delattrs;
	local (%attrs, $i);
	for($i=0; $i<@$attrs; $i+=2) {
		$attrs{$attrs->[$i]} = $attrs->[$i+1];
		}
	local $rv = $ldap->modify($_[1]->{'dn'},
				  replace => \%attrs,
				  delete => $delattrs);
	&error($rv->error) if ($rv->code);
	if ($_[0]->{'dn'} ne $_[1]->{'dn'}) {
		# Re-named too!
		$rv = $ldap->moddn($_[1]->{'dn'},
				   newrdn => "uid=$_[0]->{'user'}");
		&error($rv->error) if ($rv->code);
		}
	$ldap->unbind();
	}
elsif ($_[1]->{'vpopmail'}) {
	# Update VPOPMail user
	local $quser = quotemeta($_[1]->{'user'});
	local $qdom = $_[2]->{'dom'};
	local $qreal = quotemeta($_[0]->{'real'}) || '""';
	local $qpass = quotemeta($_[0]->{'plainpass'});
	local $qquota = $_[0]->{'qquota'} ? $_[0]->{'qquota'} : "NOQUOTA";
	local $cmd = "$vpopbin/vmoduser -c $qreal ".
		     ($_[0]->{'passmode'} == 3 ? " -C $qpass" : "").
		     " -q $qquota $quser\@$qdom";
	local $out = &backquote_logged("$cmd 2>&1");
	if ($?) {
		&error("<tt>$cmd</tt> failed: <pre>$out</pre>");
		}
	if ($_[0]->{'user'} ne $_[1]->{'user'}) {
		# Need to rename manually
		local $vdomdir = "$config{'vpopmail_dir'}/domains/$_[2]->{'dom'}";
		&rename_logged("$vdomdir/$_[1]->{'user'}", "$vdomdir/$_[0]->{'user'}");
		&lock_file("$vdomdir/vpasswd");
		local $lref = &read_file_lines("$vdomdir/vpasswd");
		local $l;
		foreach $l (@$lref) {
			local @u = split(/:/, $l);
			if ($u[0] eq $_[1]->{'user'}) {
				$u[0] = $_[0]->{'user'};
				$u[5] =~ s/$_[1]->{'user'}$/$_[0]->{'user'}/;
				$l = join(":", @u);
				}
			}
		&flush_file_lines();
		&unlock_file("$vdomdir/vpasswd");
		&system_logged("$vpopbin/vmkpasswd $qdom");
		}
	}
else {
	# Modifying Unix user
	&require_useradmin();
	&require_mail();

	# Update the unix user
	if ($config{'ldap_mail'}) {
		if ($_[0]->{'email'}) {
			push(@{$_[0]->{'ldap_attrs'}}, "mail",$_[0]->{'email'});
			}
		push(@{$_[0]->{'ldap_attrs'}},
		     map { ( "mail", $_ ) } @{$_[0]->{'extraemail'}});
		}
	&foreign_call($usermodule, "set_user_envs", $_[0], 'MODIFY_USER',
		      $_[0]->{'plainpass'}, undef, $_[1], $_[1]->{'plainpass'});
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "lock_user_files");
	&userdom_substitutions($_[0], $_[2]);
	&foreign_call($usermodule, "modify_user", $_[1], $_[0]);
	&foreign_call($usermodule, "unlock_user_files");
	&foreign_call($usermodule, "made_changes");

	if ($config{'mail_system'} == 0 && $_[1]->{'user'} =~ /\@/) {
		local $esc = &replace_atsign($_[1]->{'user'});
		local @allusers = &list_all_users_quotas(1);
		local ($oldextrauser) = grep { $_->{'user'} eq $esc } @allusers;
		if ($oldextrauser) {
			# Found him .. fix up
			$extrauser = { %{$_[0]} };
			$extrauser->{'user'} = &replace_atsign($_[0]->{'user'});
			&foreign_call($usermodule, "set_user_envs", $extrauser,
					'MODIFY_USER', $_[0]->{'plainpass'},
					undef, $oldextrauser,
					$_[1]->{'plainpass'});
			&foreign_call($usermodule, "making_changes");
			&foreign_call($usermodule, "lock_user_files");
			&userdom_substitutions($extrauser, $_[2]);
			&foreign_call($usermodule, "modify_user",
					$oldextrauser, $extrauser);
			&foreign_call($usermodule, "unlock_user_files");
			&foreign_call($usermodule, "made_changes");
			}
		}

	goto NOALIASES if ($_[3]);	# no need to touch aliases and virtusers
	}

# Check if email has changed
local $echanged;
if (!$_[0]->{'email'} && $_[1]->{'virt'} &&		# disabling
     $_[1]->{'virt'}->{'to'}->[0] !~ /^BOUNCE/ ||
    $_[0]->{'email'} && !$_[1]->{'virt'} ||		# enabling
    $_[0]->{'email'} && $_[1]->{'virt'} &&		# changing
     $_[0]->{'email'} ne $_[1]->{'virt'}->{'from'} ||
    $_[0]->{'email'} && $_[1]->{'virt'} &&		# also enabling
     $_[1]->{'virt'}->{'to'}->[0] =~ /^BOUNCE/
    ) {
	# Primary has changed
	$echanged = 1;
	}
local $oldextra = join(" ", map { $_->{'from'} } @{$_[1]->{'extravirt'}});
local $newextra = join(" ", @{$_[0]->{'extraemail'}});
if ($oldextra ne $newextra) {
	# Extra has changed
	$echanged = 1;
	}
if ($_[0]->{'user'} ne $_[1]->{'user'}) {
	# Always update on a rename
	$echanged = 1;
	}
local $oldto = join(" ", @{$_[1]->{'to'}});
local $newto = join(" ", @{$_[0]->{'to'}});
if ($oldto ne $newto) {
	# Always update if forwarding dest has changed
	$echanged = 1;
	}

local $firstemail;
local @to = @{$_[0]->{'to'}};
local @oldto = @{$_[1]->{'to'}};
if (!$_[0]->{'qmail'} && $echanged) {
	# Take away all virtusers and add new ones, for non Qmail+LDAP users
	&delete_virtuser($_[1]->{'virt'}) if ($_[1]->{'virt'});
	local $e;
	local %oldcmt;
	foreach $e (@{$_[1]->{'extravirt'}}) {
		$oldcmt{$e->{'from'}} = $e->{'cmt'};
		&delete_virtuser($e);
		}
	local $vto = @to ? &escape_alias($_[0]->{'user'}) :
		     $extrauser ? $extrauser->{'user'} :
				  &escape_user($_[0]->{'user'});
	if ($_[0]->{'email'}) {
		local $virt = { 'from' => $_[0]->{'email'},
				'to' => [ $vto ],
				'cmt' => $oldcmt{$_[0]->{'email'}} };
		&create_virtuser($virt);
		$_[0]->{'virt'} = $virt;
		$firstemail ||= $_[0]->{'email'};
		}
	elsif ($can_alias_types{9} && $_[2] && !$_[0]->{'noprimary'} &&
	       $_[2]->{'mail'}) {
		# Add bouncer if email disabled
		local $virt = { 'from' => "$pop3\@$_[2]->{'dom'}",
				'to' => [ "BOUNCE" ],
				'cmt' => $oldcmt{"$pop3\@$_[2]->{'dom'}"} };
		&create_virtuser($virt);
		$_[0]->{'virt'} = $virt;
		}
	local @extravirt;
	foreach $e (@{$_[0]->{'extraemail'}}) {
		local $virt = { 'from' => $e,
				'to' => [ $vto ],
				'cmt' => $oldcmt{$e} };
		&create_virtuser($virt);
		push(@extravirt, $virt);
		$firstemail ||= $e;
		}
	$_[0]->{'extravirt'} = \@extravirt;
	}

if (!$_[0]->{'qmail'}) {
	# Update, create or delete alias, for non Qmail+LDAP users
	if (@to && !@oldto) {
		# Need to add alias
		local $alias = { 'name' => &escape_alias($_[0]->{'user'}),
				 'enabled' => 1,
				 'values' => $_[0]->{'to'} };
		&check_alias_clash($_[0]->{'user'}) &&
			&error(&text('alias_eclash2', $_[0]->{'user'}));
		if ($config{'mail_system'} == 1) {
			# Create Sendmail alias with same name as user
			&sendmail::lock_alias_files($sendmail_afiles);
			&sendmail::create_alias($alias, $sendmail_afiles);
			&sendmail::unlock_alias_files($sendmail_afiles);
			}
		elsif ($config{'mail_system'} == 0) {
			# Create Postfix alias with same name as user
			&postfix::lock_alias_files($postfix_afiles);
			&postfix::create_alias($alias, $postfix_afiles);
			&postfix::unlock_alias_files($postfix_afiles);
			&postfix::regenerate_aliases();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# Set up user's .qmail file
			local $dqm = &dotqmail_file($_[0]);
			&lock_file($dqm);
			&save_dotqmail($alias, $dqm, $pop3);
			&unlock_file($dqm);
			}
		$_[0]->{'alias'} = $alias;
		}
	elsif (!@to && @oldto) {
		# Need to delete alias
		if ($config{'mail_system'} == 1) {
			# Delete Sendmail alias
			&lock_file($_[0]->{'alias'}->{'file'});
			&sendmail::delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			}
		elsif ($config{'mail_system'} == 0) {
			# Delete Postfix alias
			&lock_file($_[0]->{'alias'}->{'file'});
			&postfix::delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			&postfix::regenerate_aliases();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# Remove user's .qmail file
			local $dqm = &dotqmail_file($_[0]);
			&unlink_logged($dqm);
			}
		}
	elsif (@to && @oldto && join(" ", @to) ne join(" ", @oldto)) {
		# Need to update the alias
		local $alias = { 'name' => &escape_alias($_[0]->{'user'}),
				 'enabled' => 1,
				 'values' => $_[0]->{'to'} };
		if ($config{'mail_system'} == 1) {
			# Update Sendmail alias
			&lock_file($_[1]->{'alias'}->{'file'});
			&sendmail::modify_alias($_[1]->{'alias'}, $alias);
			&unlock_file($_[1]->{'alias'}->{'file'});
			}
		elsif ($config{'mail_system'} == 0) {
			# Update Postfix alias
			&lock_file($_[1]->{'alias'}->{'file'});
			&postfix::modify_alias($_[1]->{'alias'}, $alias);
			&unlock_file($_[1]->{'alias'}->{'file'});
			&postfix::regenerate_aliases();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# Set up user's .qmail file
			local $dqm = &dotqmail_file($_[0]);
			&lock_file($dqm);
			&save_dotqmail($alias, $dqm, $pop3);
			&unlock_file($dqm);
			}
		$_[0]->{'alias'} = $alias;
		}

	if ($config{'generics'} && $echanged) {
		# Update genericstable entry too
		if ($_[1]->{'generic'}) {
			&delete_generic($_[1]->{'generic'});
			}
		if ($firstemail) {
			&create_generic($_[0]->{'user'}, $firstemail);
			}
		}
	}
NOALIASES:

# Save his quotas (unless this is the domain owner)
if ($_[0]->{'unix'} && $_[0]->{'user'} ne $_[2]->{'user'} &&
    !$_[0]->{'noquota'}) {
	&set_user_quotas($_[0]->{'user'}, $_[0]->{'quota'}, $_[0]->{'mquota'},
			 $_[2]);
	}

# Update his allowed databases (unless this is the domain owner)
if ($_[2] && !$_[0]->{'domainowner'}) {
	local $dt;
	foreach $dt (&unique(map { $_->{'type'} } &domain_databases($_[2]))) {
		local @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
		local @olddbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[1]->{'dbs'}};
		local $plugin = &indexof($dt, @database_plugins) >= 0;
		if (@dbs && !@olddbs) {
			# Need to add database user
			if (!$plugin) {
				local $crfunc = "create_${dt}_database_user";
				&$crfunc($_[2], \@dbs, $_[0]->{'user'},
					 $_[0]->{'plainpass'});
				}
			else {
				&plugin_call($dt, "database_create_user",
					     $_[2], \@dbs, $_[0]->{'user'},
					     $_[0]->{'plainpass'});
				}
			}
		elsif (@dbs && @olddbs) {
			# Need to update database user
			if (!$plugin) {
				local $mdfunc = "modify_${dt}_database_user";
				&$mdfunc($_[2], \@olddbs, \@dbs,
					 $_[1]->{'user'}, $_[0]->{'user'},
					 $_[0]->{'plainpass'});
				}
			else {
				&plugin_call($dt, "database_modify_user",
					     $_[2], \@olddbs, \@dbs,
					     $_[1]->{'user'}, $_[0]->{'user'},
					     $_[0]->{'plainpass'});
				}
			}
		elsif (!@dbs && @olddbs) {
			# Need to delete database user
			if (!$plugin) {
				local $dlfunc = "delete_${dt}_database_user";
				&$dlfunc($_[2], $_[1]->{'user'});
				}
			else {
				&plugin_call($dt, "database_delete_user",
					     $_[2], $_[1]->{'user'});
				}
			}
		}
	}

# Rename user in secondary groups, and update membership
local @groups = &list_all_groups();
local %secs = map { $_, 1 } @{$_[0]->{'secs'}};
foreach my $group (@groups) {
	local @mems = split(/,/, $group->{'members'});
	local $idx = &indexof($_[1]->{'user'}, @mems);
	local $changed;
	if ($idx >= 0) {
		# User is currently in group
		if ($secs{$group->{'group'}}) {
			# Just rename in group
			if ($_[0]->{'user'} ne $_[1]->{'user'}) {
				$changed = 1;
				$mems[$idx] = $_[0]->{'user'};
				}
			}
		else {
			# Remove from group
			splice(@mems, $idx, 1);
			$changed = 1;
			}
		}
	elsif ($secs{$group->{'group'}}) {
		# User is not in group, but needs to be
		push(@mems, $_[0]->{'user'});
		$changed = 1;
		}
	if ($changed) {
		# Only save group if members were changed
		$group->{'members'} = join(",", @mems);
		&foreign_call($group->{'module'}, "modify_group",
			      $group, $group);
		}
	}

# Update mail/FTP/db groups
&update_secondary_groups($_[2]) if ($_[2]);

# Update spamassassin whitelist
if ($virtualmin_pro) {
	&update_spam_whitelist($_[2]) if ($_[2]);
	}

# Update the plain-text password, except for a domain owner
if (!$_[0]->{'domainowner'}) {
	local %plain;
	mkdir($plainpass_dir, 0700);
	&read_file("$plainpass_dir/$_[2]->{'id'}", \%plain);
	if ($_[0]->{'user'} ne $_[1]->{'user'}) {
		$plain{$_[0]->{'user'}} = $plain{$_[1]->{'user'}};
		delete($plain{$_[1]->{'user'}});
		$plain{$_[0]->{'user'}." encrypted"} =
			$plain{$_[1]->{'user'}." encrypted"};
		delete($plain{$_[1]->{'user'}." encrypted"});
		}
	if (defined($_[0]->{'plainpass'})) {
		$plain{$_[0]->{'user'}} = $_[0]->{'plainpass'};
		$plain{$_[0]->{'user'}." encrypted"} = $_[0]->{'pass'};
		}
	&write_file("$plainpass_dir/$_[2]->{'id'}", \%plain);
	}

# Clear quota cache for this user
if (defined(&clear_lookup_domain_cache)) {
	&clear_lookup_domain_cache($_[2], $_[0]);
	}

# Set the user's Usermin IMAP password
&set_usermin_imap_password($_[0]);

# Update cache of existing usernames
$unix_user{&escape_alias($_[0]->{'user'})}++;
$unix_user{&escape_alias($_[1]->{'user'})} = 0;

if ($_[0]->{'shell'} ne $_[1]->{'shell'}) {
	# Rebuild denied user list, by shell
	&build_denied_ssh_group();
	}

# Rebuild group of domain owners
&update_domain_owners_group();
}

# delete_user(&user, domain)
# Delete a mailbox user and all associated virtusers and aliases
sub delete_user
{
# Zero out his quotas
if ($_[0]->{'unix'} && !$_[0]->{'noquota'}) {
	&set_user_quotas($_[0]->{'user'}, 0, 0, $_[1]);
	}

# Delete any of his cron jobs
if ($_[0]->{'unix'}) {
	&delete_unix_cron_jobs($_[0]->{'user'});
	}

if ($_[0]->{'qmail'}) {
	# Delete user in Qmail LDAP
	local $ldap = &connect_qmail_ldap();
	local $rv = $ldap->delete($_[0]->{'dn'});
	&error($rv->error) if ($rv->code);
	$ldap->unbind();
	}
elsif ($_[0]->{'vpopmail'}) {
	# Call VPOPMail delete user program
	local $quser = quotemeta($_[0]->{'user'});
	local $qdom = $_[1]->{'dom'};
	local $cmd = "$vpopbin/vdeluser $quser\@$qdom";
	local $out = &backquote_logged("$cmd 2>&1");
	if ($?) {
		&error("<tt>$cmd</tt> failed: <pre>$out</pre>");
		}
	}
else {
	# Delete Unix user
	$_[0]->{'user'} eq 'root' && &error("Cannot delete root user!");
	$_[0]->{'uid'} == 0 && &error("Cannot delete UID 0 user!");
	&require_useradmin();
	&require_mail();

	# Delete the user
	&foreign_call($usermodule, "set_user_envs", $_[0], 'DELETE_USER')
	&foreign_call($usermodule, "making_changes");
	&foreign_call($usermodule, "lock_user_files");
	&foreign_call($usermodule, "delete_user",$_[0]);
	&foreign_call($usermodule, "unlock_user_files");
	&foreign_call($usermodule, "made_changes");
	}

if ($config{'mail_system'} == 0 && $_[0]->{'user'} =~ /\@/) {
	# Find the Unix user with the @ escaped and delete it too
	local $esc = &replace_atsign($_[0]->{'user'});
	local @allusers = &list_all_users_quotas(1);
	local ($extrauser) = grep { $_->{'user'} eq $esc } @allusers;
	if ($extrauser) {
		&foreign_call($usermodule, "set_user_envs", $extrauser, 'DELETE_USER')
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "lock_user_files");
		&foreign_call($usermodule, "delete_user", $extrauser);
		&foreign_call($usermodule, "unlock_user_files");
		&foreign_call($usermodule, "made_changes");
		}
	}

if (!$_[0]->{'qmail'}) {
	# Delete any virtusers (extra email addresses for this user)
	&delete_virtuser($_[0]->{'virt'}) if ($_[0]->{'virt'});
	local $e;
	foreach $e (@{$_[0]->{'extravirt'}}) {
		&delete_virtuser($e);
		}
	}

if (!$_[0]->{'qmail'}) {
	# Delete his alias (for forwarding), if any
	if ($_[0]->{'alias'}) {
		if ($config{'mail_system'} == 1) {
			# Delete Sendmail alias with same name as user
			&lock_file($_[0]->{'alias'}->{'file'});
			&sendmail::delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			}
		elsif ($config{'mail_system'} == 0) {
			# Delete Postfix alias with same name as user
			&lock_file($_[0]->{'alias'}->{'file'});
			&postfix::delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			&postfix::regenerate_aliases();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 5) {
			# .qmail will be deleted when user is
			}
		}

	if ($config{'generics'} && $_[0]->{'generic'}) {
		# Delete genericstable entry too
		&delete_generic($_[0]->{'generic'});
		}
	}

# Delete database access (unless this is the domain owner)
if ($_[1] && !$_[0]->{'domainowner'}) {
	local $dt;
	foreach $dt (&unique(map { $_->{'type'} } &domain_databases($_[1]))) {
		local @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
		if (@dbs && &indexof($dt, @database_plugins) < 0) {
			# Delete from core database
			local $dlfunc = "delete_${dt}_database_user";
			&$dlfunc($_[1], $_[0]->{'user'});
			}
		elsif (@dbs && &indexof($dt, @database_plugins) >= 0) {
			# Delete from plugin database
			&plugin_call($dt, "delete_database_user",
				     $_[1], $_[0]->{'user'});
			}
		}
	}

# Take the user out of any secondary groups
local @groups = &list_all_groups();
foreach my $group (@groups) {
	local @mems = split(/,/, $group->{'members'});
	local $idx = &indexof($_[0]->{'user'}, @mems);
	if ($idx >= 0) {
		splice(@mems, $idx, 1);
		$group->{'members'} = join(",", @mems);
		&foreign_call($group->{'module'}, "modify_group",
			      $group, $group);
		}
	}

# Update mail/FTP/db groups to remove user
&update_secondary_groups($_[1]) if ($_[1]);

# Update spamassassin whitelist
if ($virtualmin_pro) {
	&update_spam_whitelist($_[1]) if ($_[1]);
	}

# Remove the plain-text password
local %plain;
mkdir($plainpass_dir, 0700);
&read_file("$plainpass_dir/$_[1]->{'id'}", \%plain);
delete($plain{$_[0]->{'user'}});
delete($plain{$_[0]->{'user'}." encrypted"});
&write_file("$plainpass_dir/$_[1]->{'id'}", \%plain);

# Update cache of existing usernames
$unix_user{&escape_alias($_[0]->{'user'})} = 0;
}

# set_usermin_imap_password(&user)
# If Usermin is setup to use an IMAP inbox on localhost, set this user's
# IMAP password
sub set_usermin_imap_password
{
local ($user) = @_;
return 0 if (!$user->{'unix'} || !$user->{'home'});
return 0 if (!$user->{'plainpass'});
return 0 if (!$user->{'email'});

# Make sure Usermin is installed, and the mailbox module is setup for IMAP
return 0 if (!&foreign_check("usermin"));
&foreign_require("usermin", "usermin-lib.pl");
return 0 if (!&usermin::get_usermin_module_info("mailbox"));
local %mconfig;
&read_file("$usermin::config{'usermin_dir'}/mailbox/config", \%mconfig);
return 0 if ($mconfig{'mail_system'} != 4);
return 0 if ($mconfig{'pop3_server'} ne '' &&
             $mconfig{'pop3_server'} ne 'localhost' &&
	     $mconfig{'pop3_server'} ne '127.0.0.1' &&
	     &to_ipaddress($mconfig{'pop3_server'}) ne &to_ipaddress(&get_system_hostname()));

# Set the password
foreach my $dir ($user->{'home'}, "$user->{'home'}/.usermin", "$user->{'home'}/.usermin/mailbox") {
	next if ($user->{'webowner'} && $dir eq $user->{'home'});
	next if ($user->{'domainowner'} && $dir eq $user->{'home'});
	&make_dir($dir, 0700);
	&set_ownership_permissions($user->{'uid'}, $user->{'gid'}, 0700, $dir);
	}
local %inbox;
&read_file("$user->{'home'}/.usermin/mailbox/inbox.imap", \%inbox);
$inbox{'user'} = $user->{'user'};
$inbox{'pass'} = $user->{'plainpass'};
&write_file("$user->{'home'}/.usermin/mailbox/inbox.imap", \%inbox);
}

# delete_unix_cron_jobs(username)
# Delete all Cron jobs belonging to some Unix user
sub delete_unix_cron_jobs
{
local ($username) = @_;
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
local $cronfile;
foreach my $j (@jobs) {
	if ($j->{'user'} eq $username) {
		$cronfile ||= &cron::cron_file($j);
		&lock_file($cronfile);
		&cron::delete_cron_job($j);
		}
	}
&unlock_file($cronfile) if ($cronfile);
}

# rename_unix_cron_jobs(username, oldusername)
# Change the name of the user who owns any cron jobs
sub rename_unix_cron_jobs
{
local ($username, $oldusername) = @_;
return if ($username eq $oldusername);
&foreign_require("cron", "cron-lib.pl");
if (-r "$cron::config{'cron_dir'}/$oldusername") {
	# Rename user's crontab directory file
	&rename_logged("$cron::config{'cron_dir'}/$oldusername",
		       "$cron::config{'cron_dir'}/$username");
	}
# Rename jobs in other files
local @jobs = &cron::list_cron_jobs();
local $cronfile;
foreach my $j (@jobs) {
	if ($j->{'user'} eq $oldusername) {
		$cronfile ||= &cron::cron_file($j);
		&lock_file($cronfile);
		$j->{'user'} = $username;
		&change_cron_job($j);
		}
	}
&unlock_file($cronfile) if ($cronfile);
}

# validate_user(&domain, &user, [&olduser])
# Called before a user is saved, to validate it. Must return undef on success,
# or an error message on failure
sub validate_user
{
local ($d, $user, $old) = @_;
if ($d && @{$user->{'dbs'}} && (!$old || !@{$old->{'dbs'}})) {
	# Enabling database access .. make sure a password was given
	if (!$user->{'plainpass'}) {
		return $text{'user_edbpass'};
		}
	# Check for username clash
	foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($d))) {
		local $dfunc = "list_all_".$dt."_users";
		next if (!defined(&$dfunc));
		local @dbusers = &$dfunc();
		local $ufunc = $dt."_username";
		if (&indexof(&$ufunc($user->{'user'}), @dbusers) >= 0) {
			# Found a clash!
			return $text{'user_edbclash'};
			}
		}
	}
return undef;
}

# set_user_quotas(username, home-quota, mail-quota, [&domain])
# Sets the quotas for a mailbox user
sub set_user_quotas
{
local $tmpl = &get_template($_[3] ? $_[3]->{'template'} : 0);
if (&has_quota_commands()) {
	# Call the external quota program
	&run_quota_command("set_user", $_[0],
	    $tmpl->{'quotatype'} eq 'hard' ? ( $_[1], $_[1] ) : ( $_[1], 0 ));
	}
else {
	# Call through to quotas module
	if (&has_home_quotas()) {
		&set_quota($_[0], $config{'home_quotas'}, $_[1],
			   $tmpl->{'quotatype'} eq 'hard');
		}
	if (&has_mail_quotas()) {
		&set_quota($_[0], $config{'mail_quotas'}, $_[2],
			   $tmpl->{'quotatype'} eq 'hard');
		}
	}
}

# run_quota_command(config-suffix, arg, ...)
# Run some external quota set/get command. On failure calls error, otherwise
# returns the output.
sub run_quota_command
{
local ($cfg, @args) = @_;
local $cmd = $config{'quota_'.$cfg.'_command'}." ".
	     join(" ", map { quotemeta($_) } @args);
local $out = &backquote_logged("$cmd 2>&1 </dev/null");
if ($?) {
	&error(&text('equotacommand', "<tt>$cmd</tt>",
		     "<pre>".&html_escape($out)."</pre>"));
	}
else {
	return $out;
	}
}

# encrypt_user_password(&user, text)
# Given a plain text password, returns a suitable encrypted form for
# a mailbox user.
sub encrypt_user_password
{
&require_useradmin();
local ($user, $pass) = @_;
if ($user->{'qmail'}) {
	# Force crypt mode for Qmail+LDAP
	local $salt = $user->{'pass'} || substr(time(), -2);
	return &unix_crypt($pass, $salt);
	}
else {
	return &foreign_call($usermodule, "encrypt_password",
					  $pass, $user->{'pass'});
	}
}

# create_user_home(&uinfo, &domain)
# Creates the home directory for a new mail user, and copies skel files into it
sub create_user_home
{
local $home = $_[0]->{'home'};
if ($home) {
	# Create his homedir
	local @st = $_[1] ? stat($_[1]->{'home'}) : ( undef, undef, 0755 );
	&lock_file($home);
	&make_dir($home, $st[2] & 0777);
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'},
				   $st[2] & 0777, $home);
	&unlock_file($home);

	# Copy files into homedir
	&copy_skel_files(
		&substitute_domain_template($config{'mail_skel'}, $_[1]),
		$_[0], $home);
	}
}

# delete_user_home(&user, &domain)
# Deletes the home directory of a user, if valid
sub delete_user_home
{
local ($user, $d) = @_;
if ($user->{'unix'} && -d $user->{'home'} && $user->{'home'} ne "/") {
	&system_logged("rm -rf ".quotemeta($user->{'home'}));
	}
}

# domain_title(&domain)
sub domain_title
{
print "<center><font size=+1>",&domain_in($_[0]),"</font></center>\n";
}

# domain_in(&domain)
sub domain_in
{
return &text('indom', "<tt>$_[0]->{'dom'}</tt>");
}

# copy_skel_files(basedir, &user, home, [group], [&for-domain])
# Copy files to the home directory of some new user
sub copy_skel_files
{
local ($uf, $user, $home, $group, $d) = @_;
return if (!$uf);
&require_useradmin();
local @copied;
if ($user) {
	# We have the domain username
	local $shell = $user->{'shell'};
	$shell =~ s/^(.*)\///g;
	$group = getgrgid($user->{'gid'}) if (!$group);
	$uf =~ s/\$group/$group/g;
	$uf =~ s/\$gid/$user->{'gid'}/g;
	$uf =~ s/\$shell/$shell/g;
	@copied = &useradmin::copy_skel_files($uf, $home,
				    $user->{'uid'}, $user->{'gid'});
	}
else {
	# This domain has no user
	$uf =~ s/\$group/nogroup/g;
	$uf =~ s/\$gid/100/g;
	$uf =~ s/\$shell/\/bin\/false/g;
	@copied = &useradmin::copy_skel_files($uf, $home, 0, 0);
	}

# Perform variable substition on the files, if requested
if ($d) {
	local $tmpl = &get_template($d->{'template'});
	if ($tmpl->{'skel_subs'}) {
		foreach my $c (@copied) {
			if (-r $c && !-d $c && !-l $c) {
				local $data = &read_file_contents($c);
				&open_tempfile(OUT, ">$c");
				&print_tempfile(OUT,
					&substitute_domain_template($data, $d));
				&close_tempfile(OUT);
				}
			}
		}
	}
}

# can_edit_domain(&domain)
# Returns 1 if the current user can edit some domain (ie. change users, aliases
# databases, and so on)
sub can_edit_domain
{
if ($access{'reseller'}) {
	# User is a reseller .. is this one of his domains?
	if ($_[0]->{'parent'}) {
		# Parent domain permissions apply
		return &can_edit_domain(&get_domain($_[0]->{'parent'}));
		}
	else {
		return $_[0]->{'reseller'} eq $base_remote_user;
		}
	}
else {
	return 1 if ($access{'domains'} eq "*");
	return 0 if (!$_[0]->{'id'});
	local $d;
	foreach $d (split(/\s+/, $access{'domains'})) {
		return 1 if ($d eq $_[0]->{'id'});
		}
	return 0;
	}
}

# can_delete_domain(&domain)
sub can_delete_domain
{
local ($d) = @_;
return &can_edit_domain($d) &&
       (&master_admin() || &reseller_admin() ||
	$_[0]->{'parent'} && $access{'edit_delete'});
}

sub can_move_domain
{
local ($d) = @_;
return 0 if (!$virtualmin_pro);
return &can_edit_domain($d) &&
       (&master_admin() || &reseller_admin());
}

# Returns 1 if the current user is the master Virtualmin admin
sub master_admin
{
return !$access{'noconfig'};
}

# Returns 1 if the current user is a reseller
sub reseller_admin
{
return $access{'reseller'};
}

# Returns the domain ID if the current user is an extra admin
sub extra_admin
{
return $access{'admin'};
}

# Returns 1 if the current user can stop and start servers
sub can_stop_servers
{
return $access{'stop'};
}

# Returns 1 if templates, plugins, fields, ips and resellers can be edited
sub can_edit_templates
{
return &master_admin();
}

# Returns 1 if the user can view installed plugins and system status
sub can_view_status
{
return &master_admin();
}

# Returns 1 if the user can view software versions and other info
sub can_view_sysinfo
{
return 0 if (!$virtualmin_pro);
return $config{'show_sysinfo'} == 1 ||
       $config{'show_sysinfo'} == 2 && &master_admin() ||
       $config{'show_sysinfo'} == 3 && (&master_admin() || &reseller_admin());
}

# Returns 1 if the user can re-check the licence status
sub can_recheck_licence
{
return 0 if (!$virtualmin_pro);
return &master_admin();
}

# Returns 1 if the user can edit local users
sub can_edit_local
{
return $access{'local'};
}

# Returns 1 if the user can backup and restore all domains
sub can_backup_domains
{
return &master_admin();
}

# Returns 1 if the user can backup and restore core Virtualmin settings, like
# the config, resellers and so on
sub can_backup_virtualmin
{
return &master_admin();
}

# can_backup_domain([&domain])
# Returns 0 if no backups are allowed, 1 if they are, 2 if only backups to
# remote are allowed
sub can_backup_domain
{
if (!$_[0]) {
	return &master_admin() ? 1 : 0;
	}
elsif ($_[0] && &can_edit_domain($_[0]) &&
       ($access{'edit_backup'} || &master_admin())) {
	return &master_admin() ? 1 : 2;
	}
else {
	return 0;
	}
}

# Returns 1 if the current user can backup to Amazon's S3 service
sub can_use_s3
{
return $virtualmin_pro;
}

# Returns 1 if the user can create new top-level servers or child servers
sub can_create_master_servers
{
return $access{'create'} == 1;
}

# Returns 1 if the user can create new child servers
sub can_create_sub_servers
{
return $access{'create'};
}

sub can_create_sub_domains
{
return 0 if (!&can_create_sub_servers());
if ($config{'allow_subdoms'} eq '1') {
	return 1;
	}
elsif ($config{'allow_subdoms'} eq '0') {
	return 0;
	}
else {
	local @subdoms = grep { $_->{'subdom'} } &list_domains();
	return @subdoms ? 1 : 0;
	}
}

sub can_create_batch
{
return &master_admin() || &reseller_admin() || $config{'batch_create'};
}

# Returns 1 if the user can migrate servers from other control panels
sub can_migrate_servers
{
return $access{'import'};
}

# Returns 1 if the user can import existing servers and databases
sub can_import_servers
{
return $access{'import'};
}

# Returns 1 if an existing group can be chosen for new domain Unix users
sub can_choose_ugroup
{
return $config{'show_ugroup'} && &master_admin();
}

# can_use_feature(feature)
sub can_use_feature
{
return &master_admin() || $config{$f} == 3 || $access{"feature_".$_[0]};
}

# Returns 1 if the current user is allowed to select a private or shared
# IP for a virtual server
sub can_select_ip
{
local @shared = &list_shared_ips();
return $config{'all_namevirtual'} || &can_use_feature("virt") ||
       @shared && &can_edit_sharedips();
}

# can_edit_limits(&domain)
# Returns 1 if owner limits can be edited in some domain
sub can_edit_limits
{
return &master_admin() ||
       &reseller_admin() && &can_edit_domain($_[0]);
}

# can_config_domain(&domain)
# Returns 1 if the current user can change the settings for a domain (like the
# password, real name and so on)
sub can_config_domain
{
return $access{'edit'} && &can_edit_domain($_[0]);
}

# Returns 1 if the current user can change quotas for an owned domain
sub can_edit_quotas
{
return $access{'edit'} == 1;
}

# Returns 1 if the current user can rename domains, 2 if he can rename and
# select a new username
sub can_rename_domains
{
return $access{'norename'} ? 0 :
       &master_admin() || &reseller_admin() ? 2 : 1;
}

# Returns 1 if the current user can change the home directory of a domain,
# 2 if he can change it to anything
sub can_rehome_domains
{
return $access{'norename'} ? 0 :
       &master_admin() ? 2 : 1;
}

sub can_edit_users
{
return &master_admin() || &reseller_admin() || $access{'edit_users'};
}

sub can_edit_aliases
{
return &master_admin() || &reseller_admin() || $access{'edit_aliases'};
}

# Returns 1 if the current user can edit databases
sub can_edit_databases
{
return &master_admin() || &reseller_admin() ||
       $access{'edit_dbs'} && !$access{'nodbname'};
}

sub can_edit_admins
{
return 0 if (!$virtualmin_pro);
return &master_admin() || &reseller_admin() || $access{'edit_admins'};
}

sub can_edit_spam
{
return 0 if (!$virtualmin_pro);
return &master_admin() || &reseller_admin() || $access{'edit_spam'};
}

sub can_edit_phpmode
{
return $virtualmin_pro && &master_admin();
}

sub can_edit_phpver
{
return 0 if (!$virtualmin_pro);
return &master_admin() || &reseller_admin() || $access{'edit_phpver'};
}

sub can_edit_sharedips
{
return &master_admin() || &reseller_admin() || $access{'edit_sharedips'};
}

sub can_edit_catchall
{
return &master_admin() || &reseller_admin() || $access{'edit_catchall'};
}

sub can_edit_html
{
return &master_admin() || &reseller_admin() || $access{'edit_html'};
}

sub can_edit_scripts
{
return 0 if (!$virtualmin_pro);
return &master_admin() || &reseller_admin() || $access{'edit_scripts'};
}

sub can_edit_forward
{
return &master_admin() || &reseller_admin() || $access{'edit_forward'};
}

sub can_edit_ssl
{
return &master_admin() || &reseller_admin() || $access{'edit_ssl'};
}

# Returns 1 if the current user can setup bandwidth limits for a domain
sub can_edit_bandwidth
{
return &master_admin() || &reseller_admin();
}

# Returns 1 if the current user can see historical system data
sub can_show_history
{
return $virtualmin_pro && &master_admin();
}

sub can_edit_exclude
{
return 1;	# For now, anyone can
}

# Returns 1 if the current user can disable and enable the given domain
sub can_disable_domain
{
local ($d) = @_;
return &can_edit_domain($d) &&
       (&master_admin() || &reseller_admin() ||
        $d->{'parent'} && !$d->{'alias'} && $access{'edit_disable'});
}

# Returns 1 if the configuration can be checked
sub can_check_config
{
return &master_admin();
}

# Returns 1 if address, autoreply and filter files can be edited
sub can_edit_afiles
{
return $config{'edit_afiles'} || &master_admin();
}

# can_change_ip(&domain)
# Returns 1 if the current user can change the IP of a domain
sub can_change_ip
{
return 0 if (!$virtualmin_pro);
local $tmpl = &get_template($_[0]->{'template'});
return &master_admin() ||
       $access{'edit_ip'} && &can_use_feature("virt") &&
       $tmpl->{'ranges'} ne "none";
}

# Returns 1 if the current user can choose the home directory of mailboxes
sub can_mailbox_home
{
return &master_admin() || $config{'edit_homes'};
}

# Returns 1 if the current user can create FTP mailboxes
sub can_mailbox_ftp
{
return &master_admin() || $config{'edit_ftp'};
}

# Returns 1 if the current user can set the quota for mailboxes
sub can_mailbox_quota
{
return &master_admin() || $config{'edit_quota'};
}

# can_use_template(&template)
# Returns 1 if some template can be used by the current user, or his reseller
sub can_use_template
{
if (&master_admin() || $_[0]->{'resellers'} eq '*' || !$virtualmin_pro) {
	return 1;
	}
local %resels = map { $_, 1 } split(/\s+/, $_[0]->{'resellers'});
if (&reseller_admin()) {
	# Is current user in the reseller list?
	return $resels{$base_remote_user};
	}
else {
	# Is user's reseller in list?
	local $dom = &get_domain_by("user", $base_remote_user, "parent", undef);
	return $dom && $dom->{'reseller'} && $resels{$dom->{'reseller'}};
	}
}

# Returns 1 if the current user can execute remote commands
sub can_remote
{
return &master_admin();
}

# Returns 1 if the current user can grant extra modules to server owners
sub can_webmin_modules
{
return &master_admin();
}

# Returns 1 if the current user can change a domain's shell
sub can_edit_shell
{
return &master_admin();
}

# Returns 1 if the current user can select the spamassassin client for a domain
sub can_spam_client
{
return &master_admin();
}

# Returns 1 if the current user can select the ClamAV program for a domain
sub can_virus_scanner
{
return &master_admin();
}

# can_switch_user(&domain, [extra-admin])
# Returns 1 if the current user can switch to the Webmin login for some domain
sub can_switch_user
{
local ($d, $admin) = @_;
return $virtualmin_pro &&	# Only Pro supports this
       $main::session_id &&	# When using session auth
       !$access{'admin'} &&	# Not for extra admins
       (&master_admin() ||	# Master can switch, or domain owner to extras
	&reseller_admin() && &can_edit_domain($d) ||
	$admin && &can_edit_domain($d));
}

# Returns 1 if the user can view mail logs for some domain (or all domains if
# none was given)
sub can_view_maillog
{
local ($d) = @_;
if ($d) {
	return &can_edit_domain($d);
	}
else {
	return &master_admin();
	}
}

# domains_table(&domains, [checkboxes])
# Display a list of domains in a table, with links for editing
sub domains_table
{
local ($doms, $checks) = @_;
local @table_features = $config{'show_features'} ?
    (grep { $_ ne 'webmin' && $_ ne 'mail' &&
	    $_ ne 'unix' && $_ ne 'dir' } @features) : ( );
local $showchecks = $checks && &can_config_domain($_[0]->[0]);
local @tds;
local @cols;
if ($showchecks) {
	push(@tds, "width=5");
	push(@cols, "");
	}
push(@cols, $text{'index_domain'}, $text{'index_user'},
	    $text{'index_owner'} );
local $f;
local $qshow = &has_home_quotas() && $config{'show_quotas'};
foreach $f (@table_features) {
	push(@cols, $text{'index_'.$f}) if ($config{$f});
	}
push(@cols, $text{'index_mail'});
if ($config{'mail'}) {
	push(@cols, $text{'index_alias'});
	}
if ($qshow) {
	push(@cols, $text{'index_quota'}, $text{'index_uquota'});
	}
print &ui_columns_start(\@cols, "100", undef, \@tds);
local $d;
local %done;
local $sortfield = $config{'domains_sort'} || "user";
foreach $d (sort { $a->{$sortfield} cmp $b->{$sortfield} ||
		   $a->{'parent'} <=> $b->{'parent'} ||
		   $a->{'created'} <=> $b->{'created'} } @$doms) {
	$done{$d->{'id'}}++;
	local $dn = &shorten_domain_name($d);
	$dn = $d->{'disabled'} ? "<i>$dn</i>" : $dn;
	local $pfx;
	$pfx .= "&nbsp;&nbsp;" if ($d->{'parent'} && $done{$d->{'parent'}} &&
				   $sortfield eq "user");
	$pfx .= "&nbsp;&nbsp;" if ($d->{'alias'} && $done{$d->{'alias'}} &&
				   $sortfield eq "user");
	local @cols;
	local $proxy = $d->{'proxy_pass_mode'} == 1 ?
		 " <a href='frame_form.cgi?dom=$d->{'id'}'>(F)</a>" :
		$d->{'proxy_pass_mode'} == 2 ?
		 " <a href='proxy_form.cgi?dom=$d->{'id'}'>(P)</a>" : "";
	if (&can_config_domain($d)) {
		push(@cols, "$pfx<a href='edit_domain.cgi?dom=$d->{'id'}'>$dn</a>$proxy");
		}
	else {
		push(@cols, "$pfx<a href='view_domain.cgi?dom=$d->{'id'}'>$dn</a>$proxy");
		}
	push(@cols, $d->{'user'});
	if ($d->{'alias'}) {
		local $aliasdom = &get_domain($d->{'alias'});
		local $of = &text('index_aliasof', $aliasdom->{'dom'});
		push(@cols, $d->{'owner'} ? "$d->{'owner'} ($of)" : $of);
		}
	else {
		push(@cols, $d->{'owner'});
		}
	foreach $f (@table_features) {
		push(@cols, $d->{$f} ? $text{'yes'} : $text{'no'})
			if ($config{$f});
		}
	local @users = &list_domain_users($d, 0, 1, $qshow ? 0 : 1, 1);
	local ($duser) = grep { $_->{'user'} eq $d->{'user'} } @users;
	if (&can_domain_have_users($d)) {
		# Link to users
		if (&can_edit_users()) {
			push(@cols, sprintf("%d&nbsp;(<a href='list_users.cgi?dom=$d->{'id'}'>$text{'index_list'}</a>)\n", scalar(@users)));
			}
		else {
			push(@cols, scalar(@users));
			}
		}
	else {
		push(@cols, "");
		}
	if ($config{'mail'}) {
		if ($d->{'mail'}) {
			# Link to aliases
			local @aliases = &list_domain_aliases($d);
			if (&can_edit_aliases()) {
				push(@cols, sprintf("%d&nbsp;(<a href='list_aliases.cgi?dom=$d->{'id'}'>$text{'index_list'}</a>)\n", scalar(@aliases)));
				}
			else {
				push(@cols, scalar(@aliases));
				}
			}
		else {
			push(@cols, $text{'index_nomail'});
			}
		}
	if ($qshow) {
		local $qmax = undef;
		if ($d->{'parent'}) {
			# Domains with parent have no quota
			if ($done{$d->{'parent'}}) {
				push(@cols, "&nbsp;&nbsp;\"");
				}
			else {
				push(@cols, $text{'index_samequ'});
				}
			}
		else {
			# Show quota for server
			push(@cols, $d->{'quota'} ?
			  &quota_show($d->{'quota'}, "home") :
			  $text{'form_unlimit'});
			$qmax = $d->{'quota'} ?
			    $d->{'quota'}*&quota_bsize("home") : undef;
			}
		if ($d->{'alias'}) {
			# Alias domains have no usage
			push(@cols, undef);
			}
		else {
			# Show total usage for domain
			local ($hq, $mq, $dbq) = &get_domain_quota($d, 1);
			local $ut = $hq*&quota_bsize("home") +
				    $mq*&quota_bsize("mail") +
				    $dbq;
			local $txt = &nice_size($ut);
			if ($qmax && $bytes > $qmax) {
				$txt = "<font color=#ff0000>$txt</font>";
				}
			push(@cols, $txt);
			}
		}
	if (&can_config_domain($d) && $showchecks) {
		print &ui_checked_columns_row(\@cols, \@tds, "d", $d->{'id'});
		}
	else {
		print &ui_columns_row(\@cols, \@tds);
		}
	}
print &ui_columns_end();
}

# userdom_name(name, &domain)
# Returns a username with the domain prefix (usually group) appended somehow
sub userdom_name
{
local $tmpl = &get_template($_[1]->{'template'});
if ($tmpl->{'append_style'} == 0) {
	return $_[0].".".$_[1]->{'prefix'};
	}
elsif ($tmpl->{'append_style'} == 1) {
	return $_[0]."-".$_[1]->{'prefix'};
	}
elsif ($tmpl->{'append_style'} == 2) {
	return $_[1]->{'prefix'}.".".$_[0];
	}
elsif ($tmpl->{'append_style'} == 3) {
	return $_[1]->{'prefix'}."-".$_[0];
	}
elsif ($tmpl->{'append_style'} == 4) {
	return $_[0]."_".$_[1]->{'prefix'};
	}
elsif ($tmpl->{'append_style'} == 5) {
	return $_[1]->{'prefix'}."_".$_[0];
	}
elsif ($tmpl->{'append_style'} == 6) {
	return $_[0]."\@".$_[1]->{'dom'};
	}
else {
	&error("Unknown append_style $config{'append_style'}!");
	}
}

# remove_userdom(name, &domain)
# Returns a username with the domain prefix (group) stripped off
sub remove_userdom
{
return $_[0] if (!$_[1]);			# No domain
return $_[0] if ($_[0] eq $_[1]->{'user'});	# Domain owner has no prefix
local $g = $_[1]->{'prefix'};
local $d = $_[1]->{'dom'};
local $rv = $_[0];
($rv =~ s/\@(\Q$d\E)$//) || ($rv =~ s/(\.|\-|_)\Q$g\E$//) || ($rv =~ s/^\Q$g\E(\.|\-|_)//);
return $rv;
}

# too_long(name)
# Returns an error message if a username is too long for this Unix variant
sub too_long
{
local $max = &max_username_length();
if ($max && length($_[0]) > $max) {
	return &text('user_elong', "<tt>$_[0]</tt>", $max);
	}
else {
	return undef;
	}
}

sub max_username_length
{
&require_useradmin();
return $uconfig{'max_length'};
}

# get_default_ip([reseller])
# Returns this system's primary IP address. If a reseller is given and he
# has a custom IP, use that.
sub get_default_ip
{
local ($reselname) = @_;
if ($reselname && defined(&get_reseller)) {
	# Check if the reseller has an IP
	local $resel = &get_reseller($reselname);
	if ($resel && $resel->{'acl'}->{'defip'}) {
		return $resel->{'acl'}->{'defip'};
		}
	}
if ($config{'defip'}) {
	# Explicitly set on module config page
	return $config{'defip'};
	}
elsif (&running_in_zone()) {
	# From zone's interface
	&foreign_require("net", "net-lib.pl");
	local ($iface) = grep { $_->{'up'} &&
				&net::iface_type($_->{'name'}) =~ /ethernet/i }
			      &net::active_interfaces();
	return $iface ? $iface->{'address'} : undef;
	}
else {
	# From interface detected at check time
	&foreign_require("net", "net-lib.pl");
	local $ifacename = $config{'iface'} || &first_ethernet_iface();
	local ($iface) = grep { $_->{'fullname'} eq $ifacename }
			      &net::active_interfaces();
	if ($iface) {
		return $iface->{'address'};
		}
	else {
		return undef;
		}
	}
}

# first_ethernet_iface()
# Returns the name of the first active ethernet interface
sub first_ethernet_iface
{
&foreign_require("net", "net-lib.pl");
foreach my $a (&net::active_interfaces()) {
	if ($a->{'up'} && $a->{'virtual'} eq '' &&
	    (&net::iface_type($a->{'name'}) =~ /ethernet/i ||
	     $a->{'name'} =~ /^bond/)) {
		return $a->{'fullname'};
		}
	}
return undef;
}

# get_address_iface(address)
# Given an IP address, returns the interface name
sub get_address_iface
{
&foreign_require("net", "net-lib.pl");
local ($iface) = grep { $_->{'address'} eq $_[0] } &net::active_interfaces();
return $iface ? $iface->{'fullname'} : undef;
}

# check_apache_directives([directives])
# Returns an error string if the default Apache directives don't look valid
sub check_apache_directives
{
local ($d, $gotname, $gotdom, $gotdoc, $gotproxy);
local @dirs = split(/\t+/, defined($_[0]) ? $_[0] : $config{'apache_config'});
foreach $d (@dirs) {
	$d =~ s/#.*$//;
	if ($d =~ /^\s*ServerName\s+(\S+)$/i) {
		$gotname++;
		$gotdom++ if ($1 =~ /\$DOM|\$\{DOM\}/);
		}
	if ($d =~ /^\s*ServerAlias\s+(.*)$/i) {
		$gotdom++ if ($1 =~ /\$DOM|\$\{DOM\}/);
		}
	$gotdoc++ if ($d =~ /^\s*(DocumentRoot|VirtualDocumentRoot)\s+(.*)$/i);
	$gotproxy++ if ($d =~ /^\s*ProxyPass\s+(.*)$/i);
	}
$gotname || return $text{'acheck_ename'};
$gotdom || return $text{'acheck_edom'};
$gotdoc || $gotproxy || return $text{'acheck_edoc'};
return undef;
}

# Print functions for HTML output
sub first_html_print { print @_,"<br>\n"; }
sub second_html_print { print @_,"<p>\n"; }
sub indent_html_print { print "<ul>\n"; }
sub outdent_html_print { print "</ul>\n"; }

# Print functions for text output
sub first_text_print
{
print $indent_text,
      (map { &html_tags_to_text(&entities_to_ascii($_)) } @_),"\n";
}
sub second_text_print
{
print $indent_text,
      (map { &html_tags_to_text(&entities_to_ascii($_)) } @_),"\n\n";
}
sub indent_text_print { $indent_text .= "    "; }
sub outdent_text_print { $indent_text = substr($indent_text, 4); }
sub html_tags_to_text
{
local ($rv) = @_;
$rv =~ s/<tt>|<\/tt>//g;
$rv =~ s/<b>|<\/b>//g;
$rv =~ s/<i>|<\/i>//g;
$rv =~ s/<u>|<\/u>//g;
$rv =~ s/<pre>|<\/pre>//g;
$rv =~ s/<br>/\n/g;
$rv =~ s/<p>/\n\n/g;
return $rv;
}

sub null_print { }

sub set_all_null_print
{
$first_print = $second_print = $indent_print = $outdent_print = \&null_print;
}
sub set_all_text_print
{
$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;
}
sub set_all_html_print
{
$first_print = \&first_html_print;
$second_print = \&second_html_print;
$indent_print = \&indent_html_print;
$outdent_print = \&outdent_html_print;
}

# These functions store and retrieve the current print commands
sub push_all_print
{
push(@print_function_stack, [ $first_print, $second_print,
			      $indent_print, $outdent_print ]);
&set_all_null_print();
}
sub pop_all_print
{
local $p = pop(@print_function_stack);
($first_print, $second_print, $indent_print, $outdent_print) = @$p;
}

# will_send_domain_email(&domain)
# Returns 1 if email would be sent to this domain at signup time
sub will_send_domain_email
{
local $tmpl = &get_template($_[0]->{'template'});
return $tmpl->{'mail_on'} ne 'none';
}

# send_domain_email(&domain)
# Sends the signup email to a new domain owner. Returns a pair containing a
# number (0=failed, 1=success) and an optional message. Also outputs status
# messages.
sub send_domain_email
{
local $tmpl = &get_template($_[0]->{'template'});
local $mail = $tmpl->{'mail'};
local $subject = $tmpl->{'mail_subject'};
local $cc = $tmpl->{'mail_cc'};
local $bcc = $tmpl->{'mail_bcc'};
if ($tmpl->{'mail_on'} eq 'none') {
	return (1, undef);
	}
&$first_print($text{'setup_email'});

local %hash = &make_domain_substitions($_[0]);
local @erv = &send_template_email($mail, $_[0]->{'emailto'},
			    	  \%hash, $subject, $cc, $bcc);
if ($erv[0]) {
	&$second_print(&text('setup_emailok', $erv[1]));
	}
else {
	&$second_print(&text('setup_emailfailed', $erv[1]));
	}
}

# make_domain_substitions(&domain)
# Returns a hash of substitions for eamil to a virtual server
sub make_domain_substitions
{
local ($d) = @_;
local %hash = %$d;
if ($hash{'quota'}) {
	$hash{'quota'} = &nice_size($d->{'quota'}*&quota_bsize("home"));
	}
if ($hash{'uquota'}) {
	$hash{'uquota'} = &nice_size($d->{'uquota'}*&quota_bsize("home"));
	}
return %hash;
}

# will_send_user_email([&domain])
# Returns 1 if a new mailbox email would be sent to a user in this domain.
# Will return 0 if no template is defined, or if sending mail to the mailbox
# has been deactivated, or if the domain doesn't even have email
sub will_send_user_email
{
local $tmode = $_[0] ? "user" : "local";
if ($config{$tmode.'_template'} eq 'none' ||
    $tmode eq "user" && !$config{'new'.$tmode.'_to_mailbox'}) {
        return 0;
        }
else {
        return 1;
        }
}

# send_user_email([&domain], &user, [mailbox-to|'none'], [update-mode])
# Sends email to a new mailbox user, and possibly the domain owner, reseller
# and master admin. Returns a pair containing a number (0=failed, 1=success)
# and an optional message
sub send_user_email
{
local ($d, $user, $userto, $mode) = @_;
local $tmode = $mode ? "update" : $d ? "user" : "local";
local $subject = $config{'new'.$tmode.'_subject'};

# Work out who we CC to
local @ccs;
push(@ccs, $config{'new'.$tmode.'_cc'}) if ($config{'new'.$tmode.'_cc'});
push(@ccs, $d->{'emailto'}) if ($config{'new'.$tmode.'_to_owner'});
if ($config{'new'.$tmode.'_to_reseller'} && $d->{'reseller'}) {
	local $resel = &get_reseller($d->{'reseller'});
	if ($resel && $resel->{'acl'}->{'email'}) {
		push(@ccs, $resel->{'acl'}->{'email'});
		}
	}
local $cc = join(",", @ccs);
local $bcc = $config{'new'.$tmode.'_bcc'};

&ensure_template($tmode."-template");
return (1, undef) if ($config{$tmode.'_template'} eq 'none');
local $tmpl = $config{$tmode.'_template'} eq 'default' ?
	"$module_config_directory/$tmode-template" :
	$config{$tmode.'_template'};
local %hash = &make_user_substitutions($user, $d);
local $email = $d ? $hash{'mailbox'}.'@'.$hash{'dom'}
		  : $hash{'user'}.'@'.&get_system_hostname();

# Work out who we send to
if ($userto) {
	$email = $userto eq 'none' ? undef : $userto;
	}
if (($tmode eq 'user' || $tmode eq 'update') &&
    !$config{'new'.$tmode.'_to_mailbox'}) {
	# Don't email domain owner if disabled
	$email = undef;
	}
return (1, undef) if (!$email && !$cc && !$bcc);

return &send_template_email(&cat_file($tmpl), $email, \%hash,
			    $subject ||
			    &entities_to_ascii($text{'mail_usubject'}),
			    $cc, $bcc, $d);
}

# make_user_substitutions(&user, &domain)
# Create a hash of email substitions for a user in some domain
sub make_user_substitutions
{
local ($user, $d) = @_;
local %hash;
if ($d) {
	%hash = ( %$d, %$user );
	$hash{'mailbox'} = &remove_userdom($user->{'user'}, $d);
	}
else {
	%hash = ( %$user );
	$hash{'mailbox'} = $hash{'user'};
	}
$hash{'plainpass'} ||= "";
$hash{'extra'} = join(" ", @{$user->{'extraemail'}});
if ($user->{'domainowner'}) {
	# Check SSH and FTP shells
	local ($sh) = grep { $_->[1] eq $user->{'shell'} } &get_unix_shells();
	if ($sh) {
		$hash{'ftp'} = $sh->[0] eq 'nologin' ? 0 : 1;
		}
	else {
		# Assume yes if unknown shell
		$hash{'ftp'} = 1;
		}
	}
else {
	# Compare shell
	$hash{'ftp'} = $user->{'shell'} eq $config{'ftp_shell'} ||
		       $config{'jail_shell'} &&
			$user->{'shell'} eq $config{'jail_shell'} ? 1 : 0;
	}

# Make quotas use nice units
if ($hash{'quota'}) {
	$hash{'quota'} = &nice_size($user->{'quota'}*&quota_bsize("home"));
	}
if ($hash{'uquota'}) {
	$hash{'uquota'} = &nice_size($user->{'uquota'}*&quota_bsize("home"));
	}
if ($hash{'mquota'}) {
	$hash{'mquota'} = &nice_size($user->{'mquota'}*&quota_bsize("mail"));
	}
if ($hash{'umquota'}) {
	$hash{'umquota'} = &nice_size($user->{'umquota'}*&quota_bsize("mail"));
	}
if ($hash{'qquota'}) {
	$hash{'qquota'} = &nice_size($user->{'qquota'});
	}
return %hash;
}

# ensure_template(file)
sub ensure_template
{
&system_logged("cp $module_root_directory/$_[0] $module_config_directory/$_[0]")
	if (!-r "$module_config_directory/$_[0]");
}

# send_template_email(data, address, &substitions, subject, cc, bcc, [&domain])
# Sends the given file to the specified address, with the substitions from
# a hash reference. The actual subs in the file must be like $XXX for entries
# in the hash like xxx - ie. $DOM is replaced by the domain name, and $HOME
# by the home directory
sub send_template_email
{
local ($template, $to, $subs, $subject, $cc, $bcc, $d) = @_;
local %hash = %$subs;

# Add in Webmin info to the hash
if ($ENV{'SERVER_PORT'}) {
	# Running under miniserv
	$hash{'webmin_port'} = $ENV{'SERVER_PORT'};
	$hash{'webmin_proto'} = $ENV{'HTTPS'} eq 'ON' ? 'https' : 'http';
	}
else {
	# Get from miniserv config
	local %miniserv;
	&get_miniserv_config(\%miniserv);
	$hash{'webmin_port'} = $miniserv{'port'};
	$hash{'webmin_proto'} = $miniserv{'ssl'} ? 'https' : 'http';
	}
$template = &substitute_template($template, \%hash);

# Work out the From: address
local $from;
if ($remote_user && !&master_admin() && $d) {
	$from = $d->{'emailto'};
	}

# Actually send using the mailboxes module
local $subject = &substitute_template($subject, \%hash);
local $cc = &substitute_template($cc, \%hash);
if (!$to) {
	# This can happen when a mailbox is not notified about its
	# own update or creation
	$to = $cc;
	$cc = undef;
	}
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mail = { 'headers' => [ [ 'From', $from ||
					 $config{'from_addr'} ||
					 &mailboxes::get_from_address() ],
			       [ 'To', $to ],
			       $cc ? ( [ 'Cc', $cc ] ) : ( ),
			       $bcc ? ( [ 'Bcc', $bcc ] ) : ( ),
			       [ 'Subject', $subject ],
			       [ 'Content-type', 'text/plain' ] ],
		'body' => $template };
&mailboxes::send_mail($mail);
return (1, &text('mail_ok', $to));
}

# send_notify_email(from, &doms|&users, [&dom], subject, body,
#		    [attach, attach-filename, attach-type])
# Sends a single email to multiple recipients. These can be Virtualmin domains
# or users.
# XXX notify mailboxes
sub send_notify_email
{
local ($from, $recips, $d, $subject, $body, $attach, $attachfile, $attachtype)
	= @_;
foreach my $r (@$recips) {
	# Work out recipient type
	local ($email, %hash);
	if ($r->{'id'}) {
		# A domain
		$email = $r->{'emailto'};
		%hash = &make_domain_substitions($r);
		}
	else {
		# A mailbox user
		$email = $r->{'email'} || $r->{'user'};
		%hash = &make_user_substitutions($r, $d);
		}
	local $mail = { 'headers' =>
		[ [ 'From' => $from ],
		  [ 'To' => $email ],
		  [ 'Subject' => &substitute_template($subject, \%hash) ] ],
		  'attach' =>
		[ { 'headers' => [ [ 'Content-type', 'text/plain' ] ],
		    'data' => &entities_to_ascii(
				&substitute_template($body, \%hash)) } ] };
	if ($attach) {
		local $filename = $attachfile;
		$filename =~ s/^.*(\\|\/)//;
		local $type = $attachtype." name=\"$filename\"";
		local $disp = "inline; filename=\"$filename\"";
		push(@{$mail->{'attach'}},
		     { 'data' => $in{'attach'},
		       'headers' => [ [ 'Content-type', $type ],
			      [ 'Content-Disposition', $disp ],
			      [ 'Content-Transfer-Encoding', 'base64' ] ] });
		}
	&mailboxes::send_mail($mail);
	}
}

# userdom_substitutions(&user, &dom)
# Returns a hash reference of substitutions for a user in a domain
sub userdom_substitutions
{
if ($_[1]) {
	$_[0]->{'mailbox'} = &remove_userdom($_[0]->{'user'}, $_[1]);
	$_[0]->{'dom'} = $_[1]->{'dom'};
	$_[0]->{'dom_prefix'} = substr($_[1]->{'dom'}, 0, 1);
	}
return $_[0];
}

# alias_type(string, [alias-name])
# Return the type and destination of some alias string
sub alias_type
{
local @rv;
if ($_[0] =~ /^\|\s*$module_config_directory\/autoreply.pl\s+(\S+)/) {
        @rv = (5, $1);
        }
elsif ($_[0] =~ /^\|\s*$config{'vpopmail_auto'}\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)(\s+(\S+)\s+(\S+))?/) {
        @rv = (12, $3, $1, $2, $4, $6, $7);
        }
elsif ($_[0] =~ /^\|\s*$module_config_directory\/filter.pl\s+(\S+)/) {
        @rv = (6, $1);
        }
elsif ($_[0] =~ /^\|\s*(.*)$/) {
        @rv = (4, $1);
        }
elsif ($_[0] eq "./Maildir/") {
	return (10);
	}
elsif ($_[0] eq "/dev/null") {
	return (11);
	}
elsif ($_[0] =~ /^(\/.*)$/ || $_[0] =~ /^\.\//) {
        @rv = (3, $_[0]);
        }
elsif ($_[0] =~ /^:include:(.*)$/) {
        @rv = (2, $1);
        }
elsif ($_[0] =~ /^\\(\S+)$/) {
	if ($1 eq $_[1] || $1 eq "NEWUSER" || $1 eq &replace_atsign($_[1])) {
		return (10);
		}
	else {
		@rv = (7, $1);
		}
        }
elsif ($_[0] =~ /^\%1\@(\S+)$/) {
        @rv = (8, $1);
        }
elsif ($_[0] =~ /^BOUNCE\s*(.*)$/) {
        @rv = (9, $1);
        }
else {
        @rv = (1, $_[0]);
        }
return wantarray ? @rv : $rv[0];
}

# set_alias_programs()
# Copy the wrapper scripts needed for autoresponders 
sub set_alias_programs
{
&require_mail();

# Copy autoresponder
local $mailmod = &foreign_check("sendmail") ? "sendmail" :
		 $config{'mail_system'} == 1 ? "sendmail" :
		 $config{'mail_system'} == 0 ? "postfix" :
					       "qmailadmin";
&copy_source_dest("$root_directory/$mailmod/autoreply.pl",
		  $module_config_directory);
&system_logged("chmod 755 $module_config_directory/config");
if (-d $sendmail::config{'smrsh_dir'} &&
    !-r "$sendmail::config{'smrsh_dir'}/autoreply.pl") {
	&system_logged("ln -s $module_config_directory/autoreply.pl $sendmail::config{'smrsh_dir'}/autoreply.pl");
	}

# Copy filter program
&system_logged("cp $root_directory/$mailmod/filter.pl $module_config_directory");
&system_logged("chmod 755 $module_config_directory/config");
if (-d $sendmail::config{'smrsh_dir'} &&
    !-r "$sendmail::config{'smrsh_dir'}/filter.pl") {
	&system_logged("ln -s $module_config_directory/filter.pl $sendmail::config{'smrsh_dir'}/filter.pl");
	}
}

# set_domain_envs(&domain, action)
# Sets up VIRTUALSERVER_ environment variables for a domain update or some kind,
# prior to calling making_changes or made_changes. action must be one of
# CREATE_DOMAIN, MODIFY_DOMAIN or DELETE_DOMAIN
sub set_domain_envs
{
local $e;
&reset_domain_envs();
$ENV{'VIRTUALSERVER_ACTION'} = $_[1];
foreach $e (keys %{$_[0]}) {
	$ENV{'VIRTUALSERVER_'.uc($e)} = $_[0]->{$e};
	}
}

# reset_domain_envs(&domain)
# Removes all environment variables set by set_domain_envs
sub reset_domain_envs
{
local $e;
foreach $e (keys %ENVS) {
	delete($ENV{$e}) if ($e =~ /^VIRTUALSERVER_/);
	}
}

# making_changes()
# Called before a domain is created, modified or deleted to run the
# pre-change command
sub making_changes
{
if ($config{'pre_command'} =~ /\S/) {
	&clean_changes_environment();
	local $out = &backquote_logged("($config{'pre_command'}) 2>&1 </dev/null");
	&reset_changes_environment();
	return $? ? $out : undef;
	}
return undef;
}

# made_changes()
# Called after a domain has been created, modified or deleted to run the
# post-change command
sub made_changes
{
if ($config{'post_command'} =~ /\S/) {
	&clean_changes_environment();
	local $out = &backquote_logged("($config{'post_command'}) 2>&1 </dev/null");
	&reset_changes_environment();
	return $? ? $out : undef;
	}
return undef;
}

sub reset_changes_environment
{
foreach my $e (keys %UNCLEAN_ENV) {
	$ENV{$e} = $UNCLEAN_ENV{$e};
        }
}

sub clean_changes_environment
{
local $e;
%UNCLEAN_ENV = %ENV;
foreach $e ('SERVER_ROOT', 'SCRIPT_NAME',
	    'FOREIGN_MODULE_NAME', 'FOREIGN_ROOT_DIRECTORY',
	    'SCRIPT_FILENAME') {
	delete($ENV{$e});
	}
}

# switch_to_domain_user(&domain)
# Changes the current UID and GID to that of the domain's unix user
sub switch_to_domain_user
{
($(, $)) = ( $_[0]->{'ugid'},
	     "$_[0]->{'ugid'} ".join(" ", $_[0]->{'ugid'},
					 &other_groups($_[0]->{'user'})) );
($<, $>) = ( $_[0]->{'uid'}, $_[0]->{'uid'} );
$ENV{'USER'} = $ENV{'LOGNAME'} = $_[0]->{'user'};
$ENV{'HOME'} = $_[0]->{'home'};
}

# run_as_domain_user(&domain, command)
# Runs some command as the owner of a virtual server, and returns the output
sub run_as_domain_user
{
&foreign_require("proc", "proc-lib.pl");
local $temp = &transname();
open(TEMP, ">$temp");
&proc::safe_process_exec_logged($_[1], $_[0]->{'uid'}, $_[0]->{'ugid'}, \*TEMP);
local $ex = $?;
local $out;
close(TEMP);
local $_;
open(TEMP, $temp);
while(<TEMP>) {
	$out .= $_;
	}
close(TEMP);
unlink($temp);
return wantarray ? ($out, $ex) : $out;
}

# print_subs_table(sub, ..)
sub print_subs_table
{
print "<table>\n";
foreach $k (@_) {
	print "<tr> <td><tt><b>\${$k}</b></td>\n";
	print "<td>",$text{"sub_".$k},"</td> </tr>\n";
	}
print "</table>\n";
print "$text{'sub_if'}<p>\n";
}

# alias_form(&to, left, &domain, "user"|"alias", user|alias, [&tds])
# Prints HTML for selecting 0 or more alias destinations
sub alias_form
{
local ($to, $left, $d, $mode, $who, $tds) = @_;
&require_mail();
local @typenames = map { $text{"alias_type$_"} } (0 .. 12);
$typenames[0] = "&lt;$typenames[0]&gt;";

local @values = @$to;
local $i;
for(my $i=0; $i<=@values+2; $i++) {
	local ($type, $val) = $values[$i] ? &alias_type($values[$i], $_[4])
					  : (0, "");

	# Generate drop-down menu for alias type
	local @opts;
	local $j;
	for($j=0; $j<@typenames; $j++) {
		next if ($j == 8 && $_[3] eq "user");	# to domain not valid
							# for users
		next if ($j == 10 && $_[3] ne "user");	# user's mailbox not
							# valid for aliases
		next if ($j == 9 && $_[3] eq "user");	# bounce is not valid
							# for users
		if ($j == 0 || $can_alias_types{$j} || $type == $j) {
			push(@opts, [ $j, $typenames[$j] ]);
			}
		}
	local $f = &ui_select("type_$i", $type, \@opts);
	if ($type == 7) {
		$val = &unescape_user($val);
		}
	$f .= &ui_textbox("val_$i", $val, 30)."\n";
	if (&can_edit_afiles()) {
		local $prog = $type == 2 ? "edit_afile.cgi" :
			      $type == 5 ? "edit_rfile.cgi" :
			      $type == 6 ? "edit_ffile.cgi" :
			      $type == 12 ? "edit_vfile.cgi" : undef;
		if ($prog && $_[2]) {
			local $di = $_[2] ? $_[2]->{'id'} : undef;
			$f .= "<a href='$prog?dom=$di&file=$val&$_[3]=$_[4]&idx=$i'>$text{'alias_afile'}</a>\n";
			}
		}
	print &ui_table_row($left, $f, undef, $tds);
	$left = " ";
	}
}

# parse_alias(catchall, name, &old-values, "user"|"alias", &domain)
# Returns a list of values for an alias, taken from the form generated by
# &alias_form
sub parse_alias
{
local (@values, $i, $t, $anysame, $anybounce);
for($i=0; defined($t = $in{"type_$i"}); $i++) {
	!$t || $can_alias_types{$t} ||
		&error($text{'alias_etype'}." : ".$text{'alias_type'.$t});
	local $v = $in{"val_$i"};
	$v =~ s/^\s+//;
	$v =~ s/\s+$//;
	if ($t == 1 && $v !~ /^(\S+)$/) {
		&error(&text('alias_etype1', $v));
		}
	elsif ($t == 3 && $v !~ /^\/(\S+)$/ && $v !~ /^\.\//) {
		&error(&text('alias_etype3', $v));
		}
	elsif ($t == 4) {
		$v =~ /^(\S+)/ || &error($text{'alias_etype4none'});
		(-x $1) && &check_aliasfile($1, 0) ||
		   $1 eq "if" || $1 eq "export" || &has_command("$1") ||
			&error(&text('alias_etype4', $1));
		}
	elsif ($t == 7 && !defined(getpwnam($v)) &&
	       $config{'mail_system'} != 4 && $config{'mail_system'} != 5) {
		&error(&text('alias_etype7', $v));
		}
	elsif ($t == 8 && $v !~ /^[a-z0-9\.\-\_]+$/) {
		&error(&text('alias_etype8', $v));
		}
	elsif ($t == 8 && !$_[0]) {
		&error(&text('alias_ecatchall', $v));
		}
	if ($t == 1 || $t == 3) { push(@values, $v); }
	elsif ($t == 2) {
		$v = "$d->{'home'}/$v" if ($v !~ /^\//);
		push(@values, ":include:$v");
		}
	elsif ($t == 4) {
		push(@values, "|$v");
		}
	elsif ($t == 5) {
		# Setup autoreply script
		$v = "$d->{'home'}/$v" if ($v !~ /^\//);
		push(@values, "|$module_config_directory/autoreply.pl ".
			      "$v $name");
		&set_alias_programs();
		}
	elsif ($t == 6) {
		# Setup filter script
		$v = "$d->{'home'}/$v" if ($v !~ /^\//);
		push(@values, "|$module_config_directory/filter.pl ".
			      "$v $name");
		&set_alias_programs();
		}
	elsif ($t == 7) {
		push(@values, "\\".&escape_user($v));
		}
	elsif ($t == 8) {
		push(@values, "\%1\@$v");
		$anysame++;
		}
	elsif ($t == 9) {
		push(@values, "BOUNCE".($v ? " $v" : ""));
		$anybounce++;
		}
	elsif ($t == 10) {
		# Alias to self .. may need to used at-escaped name
		if ($config{'mail_system'} == 0 && $_[1] =~ /\@/) {
			push(@values, "\\".&replace_atsign($_[1]));
			}
		else {
			push(@values, "\\".&escape_user($_[1]));
			}
		}
	elsif ($t == 11) {
		push(@values, "/dev/null");
		}
	elsif ($t == 12) {
		# Setup vpopmail autoresponder script
		local @qm = getpwnam($config{'vpopmail_user'});
		if (!$v) {
			# Create an empty responder file
			$v = $_[3] eq "alias" ?
				"$config{'vpopmail_dir'}/domains/$_[4]->{'dom'}/$_[1].respond" :
				"$config{'vpopmail_dir'}/domains/$_[4]->{'dom'}/$_[1]/respond";
			if (!-r $v) {
				&open_tempfile(MSG, ">$v");
				&close_tempfile(MSG);
				&set_ownership_permissions($qm[2], $qm[3],
							   undef, $v);
				}
			}
		elsif (!$v) {
			&error(&text('alias_eautorepond'));
			}
		$v = "$d->{'home'}/$v" if ($v !~ /^\//);
		local @av;
		if ($_[2] && &alias_type($_[2]->[$i]) == 12) {
			# Use old settings for delay/etc
			local @oldav = &alias_type($_[2]->[$i]);
			@av = ( $oldav[2], $oldav[3], $v, $oldav[4] );
			push(@av, $oldav[5]) if ($oldav[5] ne "");
			push(@av, $oldav[6]) if ($oldav[6] ne "");
			}
		else {
			# User default settings for timeouts, and create log
			# directory
			local $vdir = "$v.log";
			if (!-d $vdir) {
				&make_dir($vdir, 0755);
				&set_ownership_permissions($qm[2], $qm[3],
							   0755, $vdir);
				}
			@av = ( 10000, 5, $v, $vdir );
			}
		push(@values, "|$config{'vpopmail_auto'} ".join(" ", @av));
		}
	}
if (@values > 1 && $anysame) {
	&error(&text('alias_ecatchall2', $v));
	}
if (@values > 1 && $anybounce) {
	&error(&text('alias_ebounce'));
	}
return @values;
}

# set_pass_change(&user)
# Set fields indicating that the password has just been changed
sub set_pass_change
{
&require_useradmin();
local $pft = &useradmin::passfiles_type();
if ($pft == 2 || $pft == 5 || $config{'ldap'}) {
	$_[0]->{'change'} = int(time() / (60*60*24));
	}
elsif ($pft == 4) {
	$_[0]->{'change'} = time();
	}
}

# set_pass_disable(&user, disable)
sub set_pass_disable
{
local ($user, $disable) = @_;
if ($disable && $user->{'pass'} !~ /^\!/) {
	$user->{'pass'} = "!".$user->{'pass'};
	}
elsif (!$disable && $user->{'pass'} =~ /^\!/) {
	$user->{'pass'} = substr($user->{'pass'}, 1);
	}
}

sub check_aliasfile
{
return 0 if (!-r $_[0] && !$_[1]);
return 1;
}

# list_all_users()
# Returns all local and LDAP users, including those from Qmail
sub list_all_users
{
&require_useradmin();
local @rv;
foreach my $u (&useradmin::list_users()) {
	$u->{'module'} = 'useradmin';
	push(@rv, $u);
	}
if ($config{'ldap'}) {
	foreach my $u (&ldap_useradmin::list_users()) {
		$u->{'module'} = 'ldap-useradmin';
		push(@rv, $u);
		}
	}
if ($config{'mail_system'} == 4) {
	local $ldap = &connect_qmail_ldap();
	local $rv = $ldap->search(base => $config{'ldap_base'},
				  filter => "(objectClass=qmailUser)");
	local $u;
	foreach $u ($rv->all_entries) {
		local %uinfo = &qmail_dn_to_hash($u);
		push(@rv, \%uinfo);
		}
	$ldap->unbind();
	}
return @rv;
}

# list_all_groups()
# Returns all local and LDAP groups
sub list_all_groups
{
&require_useradmin();
local @rv;
foreach my $g (&useradmin::list_groups()) {
	$g->{'module'} = 'useradmin';
	push(@rv, $g);
	}
if ($config{'ldap'}) {
	foreach my $g (&ldap_useradmin::list_groups()) {
		$g->{'module'} = 'ldap-useradmin';
		push(@rv, $g);
		}
	}
return @rv;
}

# build_taken(&uid-taken, &username-taken, [&users])
# Fills in the the given hashes with used usernames and UIDs
sub build_taken
{
&require_useradmin();

# Add Unix users
local @users = $_[2] ? @{$_[2]} : &list_all_users();
local $u;
foreach $u (@users) {
	$_[0]->{$u->{'uid'}} = 1;
	$_[1]->{$u->{'user'}} = 1;
	}

# Add domain users
local $d;
foreach $d (&list_domains()) {
	$_[0]->{$d->{'uid'}} = 1;
	$_[1]->{$d->{'user'}} = 1;
	}
}

# build_group_taken(&gid-taken, &groupname-taken, [&groups])
# Fills in the the given hashes with used group names and GIDs
sub build_group_taken
{
&require_useradmin();
local @groups = $_[2] ? @{$_[2]} : &list_all_groups();
local $g;
foreach $g (@groups) {
	$_[0]->{$g->{'gid'}} = 1;
	$_[1]->{$g->{'group'}} = 1;
	}
local $d;
foreach $d (&list_domains()) {
	$_[0]->{$d->{'gid'}} = 1;
	$_[1]->{$d->{'group'}} = 1;
	}
}

# allocate_uid(&uid-taken)
sub allocate_uid
{
local $uid = $uconfig{'base_uid'};
while($_[0]->{$uid}) {
	$uid++;
	}
return $uid;
}

# allocate_gid(&gid-taken)
sub allocate_gid
{
local $gid = $uconfig{'base_gid'};
while($_[0]->{$gid}) {
	$gid++;
	}
return $gid;
}

# server_home_directory(&domain, [&parentdomain])
# Returns the home directory for a new virtual server user
sub server_home_directory
{
&require_useradmin();
if ($_[0]->{'parent'}) {
	# Owned by some existing user, so under his home
	return "$_[1]->{'home'}/domains/$_[0]->{'dom'}";
	}
elsif ($config{'home_format'}) {
	# Use the template from the module config
	local $home = "$home_base/$config{'home_format'}";
	return &substitute_domain_template($home, $_[0]);
	}
else {
	# Just use the Users and Groups module settings
	return &useradmin::auto_home_dir($home_base, $_[0]->{'user'},
						     $_[0]->{'ugroup'});
	}
}

# set_quota(user, filesystem, quota, hard)
# Set hard or soft quotas for one user
sub set_quota
{
&require_useradmin();
if ($_[3]) {
	&quota::edit_user_quota($_[0], $_[1],
				int($_[2]), int($_[2]), 0, 0);
	}
else {
	&quota::edit_user_quota($_[0], $_[1],
				int($_[2]), 0, 0, 0);
	}
}

# set_server_quotas(&domain)
# Set the user and possibly group quotas for a domain
sub set_server_quotas
{
local $tmpl = &get_template($_[0]->{'template'});
if (&has_quota_commands()) {
	# User and group quotas are set externally
	&run_quota_command("set_user", $_[0]->{'user'},
		$tmpl->{'quotatype'} eq 'hard' ? ( $_[0]->{'uquota'},
						   $_[0]->{'uquota'} )
					       : ( 0, $_[0]->{'uquota'} ));
	if (&has_group_quotas() && $_[0]->{'group'}) {
		&run_quota_command("set_group", $_[0]->{'group'},
			$tmpl->{'quotatype'} eq 'hard' ? ( $_[0]->{'quota'},
							   $_[0]->{'quota'} )
						     : ( 0, $_[0]->{'quota'} ));
		}
	}
else {
	if (&has_home_quotas()) {
		# Set Unix user quota for home
		&set_quota($_[0]->{'user'}, $config{'home_quotas'},
			   $_[0]->{'uquota'}, $tmpl->{'quotatype'} eq 'hard');
		}
	if (&has_mail_quotas()) {
		# Set Unix user quota for mail
		&set_quota($_[0]->{'user'}, $config{'mail_quotas'},
			   $_[0]->{'uquota'}, $tmpl->{'quotatype'} eq 'hard');
		}
	if (&has_group_quotas() && $_[0]->{'group'}) {
		# Set group quotas for home and possibly mail
		&require_useradmin();
		local @qargs;
		if ($tmpl->{'quotatype'} eq 'hard') {
			@qargs = ( int($_[0]->{'quota'}),
				   int($_[0]->{'quota'}), 0, 0 );
			}
		else {
			@qargs = ( int($_[0]->{'quota'}), 0, 0, 0 );
			}
		&quota::edit_group_quota(
			$_[0]->{'group'}, $config{'home_quotas'}, @qargs);
		if (&has_mail_quotas()) {
			&quota::edit_group_quota(
			    $_[0]->{'group'}, $config{'mail_quotas'}, @qargs);
			}
		}
	}
}

# users_table(&users, &dom, checkboxes?)
# Output a table of mailbox users
sub users_table
{
local $can_quotas = &has_home_quotas() || &has_mail_quotas();
local $can_qquotas = $config{'mail_system'} == 4 || $config{'mail_system'} == 5;

# Work out table header
local @cols;
push(@cols, "") if ($_[2]);
push(@cols, $text{'users_name'}, $text{'users_pop3'}, $text{'users_real'} );
if ($can_quotas) {
	push(@cols, $text{'users_quota'}, $text{'users_uquota'});
	}
if ($can_qquotas) {
	push(@cols, $text{'users_qquota'});
	}
if ($config{'show_mailsize'}) {
	push(@cols, $text{'users_size'});
	}
push(@cols, $text{'users_ftp'});
if ($_[1]->{'mysql'} || $_[1]->{'postgres'}) {
	push(@cols, $text{'users_db'});
	}
local ($f, %plugcol);
foreach $f (@mail_plugins) {
	local $col = &plugin_call($f, "mailbox_header", $_[1]);
	if ($col) {
		$plugcol{$f} = $col;
		push(@cols, $col);
		}
	}
print &ui_columns_start(\@cols, "100", 0);

local $u;
local $did = $_[1] ? $_[1]->{'id'} : 0;
foreach $u (@{$_[0]}) {
	local $pop3 = $_[1] ? &remove_userdom($u->{'user'}, $_[1])
			    : $u->{'user'};
	local @cols;
	push(@cols, "<a href='edit_user.cgi?dom=$did&".
	      "user=$u->{'user'}&unix=$u->{'unix'}'>".
	      ($u->{'domainowner'} ? "<b>$pop3</b>" :
	       $u->{'webowner'} &&
	        $u->{'pass'} =~ /^\!/ ? "<u><i>$pop3</i></u>" :
	       $u->{'webowner'} ? "<u>$pop3</u>" :
	       $u->{'pass'} =~ /^\!/ ? "<i>$pop3</i>" : $pop3)."</a>\n");
	push(@cols, $u->{'user'});
	push(@cols, $u->{'real'});
	local $quota;
	$quota += $u->{'quota'} if (&has_home_quotas());
	$quota += $u->{'mquota'} if (&has_mail_quotas());
	local $uquota;
	$uquota += $u->{'uquota'} if (&has_home_quotas());
	$uquota += $u->{'muquota'} if (&has_mail_quotas());
	if (defined($quota)) {
		push(@cols, $quota ? &quota_show($quota, "home")
				   : $text{'form_unlimit'});
		if ($u->{'spam_quota'}) {
			push(@cols, "<font color=#ff0000>".
				    &quota_show($uquota, "home")."</font>");
			}
		else {
			push(@cols, &quota_show($uquota, "home"));
			}
		}
	if ($u->{'mailquota'}) {
		push(@cols, $u->{'qquota'} ? &nice_size($u->{'qquota'}) :
					     $text{'form_unlimit'});
		}
	elsif ($can_qquotas) {
		push(@cols, "");
		}

	if ($config{'show_mailsize'}) {
		# Mailbox link, if this user has email enabled or is the owner
		if (!$u->{'nomailfile'} &&
		    ($u->{'email'} || @{$u->{'extraemail'}} ||
		     $u->{'domainowner'})) {
			local ($sz) = &mail_file_size($u);
			$sz = $sz ? &nice_size($sz) : $text{'users_empty'};
			local $lnk = &read_mail_link($u, $_[1]);
			if ($lnk) {
				push(@cols, "<a href='$lnk'>$sz</a>");
				}
			else {
				push(@cols, $sz);
				}
			}
		else {
			push(@cols, $text{'users_noemail'});
			}
		}

	push(@cols,
		$u->{'domainowner'} ? $text{'users_main'} :
		!$u->{'unix'} && !$u->{'shell'} ? $text{'users_qmail'} :
		$u->{'shell'} eq $config{'ftp_shell'} ? $text{'yes'} :
		$config{'jail_shell'} &&
		 $u->{'shell'} eq $config{'jail_shell'} ? $text{'users_jail'} :
		$u->{'shell'} eq $config{'shell'} ? $text{'no'} :
			&text('users_shell', "<tt>$u->{'shell'}</tt>"));
	if ($_[1]->{'mysql'} || $_[1]->{'postgres'}) {
		push(@cols, $u->{'domainowner'} ? $text{'users_all'} :
					   @{$u->{'dbs'}} ? $text{'yes'}
					   		  : $text{'no'});
		}
	foreach $f (grep { $plugcol{$_} } @mail_plugins) {
		push(@cols, &plugin_call($f, "mailbox_column", $u, $_[1]));
		}
	if ($_[2]) {
		if ($u->{'domainowner'}) {
			# Domain owner cannot be mass updated/deleted
			print &ui_columns_row([ "", @cols ]);
			}
		else {
			# Other users can be mass changed
			print &ui_checked_columns_row(\@cols, undef, "d",
					int($u->{'unix'})."/".$u->{'user'});
			}
		}
	else {
		# Mass operations disabled
		print &ui_checked_columns_row(\@cols);
		}
	}
print &ui_columns_end();
}

# quota_bsize(filesystem|"home"|"mail", [for-filesys])
sub quota_bsize
{
if (&has_quota_commands()) {
	# When using quota commands, the block size is always 1024
	return 1024;
	}
local $fs = $_[0] eq "home" ? $config{'home_quotas'} :
	    $_[0] eq "mail" ? $config{'mail_quotas'} : $_[0];
local $forfs = int($_[1]);
if ($gconfig{'os_type'} =~ /-linux$/) {
	# On linux, the quota block size is ALWAYS 1024, so we can shortcut
	# any actual filesystem tests
	return $forfs ? 512 : 1024;
	}
&require_useradmin();
if (defined(&quota::block_size)) {
	local $bsize;
	if (!exists($bsize_cache{$fs,$forfs})) {
		$bsize_cache{$fs,$forfs} = &quota::block_size($fs, $forfs);
		}
	return $bsize_cache{$fs,$forfs};
	}
return undef;
}

# quota_show(number, filesystem|"home"|"mail")
# Returns text for the quota on some filesystem, in a human-readable format
sub quota_show
{
if (!$_[0]) {
	return "Unlimited";
	}
else {
	local $bsize = &quota_bsize($_[1]);
	if ($bsize) {
		return &nice_size($_[0]*$bsize);
		}
	return $_[0]." ".$text{'form_b'};
	}
}

# quota_input(name, number, filesystem|"home"|"mail", [disabled])
# Returns HTML for an input for entering a quota, doing block->kb conversion
sub quota_input
{
local ($name, $value, $fs, $dis) = @_;
local $bsize = &quota_bsize($fs);
if ($bsize) {
	# Allow units selection
	local $sz = $value*$bsize;
	local $units = 1;
	if ($value eq "") {
		# Default to MB, since bytes are rarely useful
		$units = 1024*1024;
		}
	elsif ($sz >= 1024*1024*1024) {
		$units = 1024*1024*1024;
		}
	elsif ($sz >= 1024*1024) {
		$units = 1024*1024;
		}
	elsif ($sz >= 1024) {
		$units = 1024;
		}
	else {
		$units = 1;
		}
	$sz = $sz == 0 ? "" : sprintf("%.2f", ($sz*1.0)/$units);
	$sz =~ s/\.00$//;
	return &ui_textbox($name, $sz, 8, $dis)." ".
	       &ui_select($name."_units", $units,
			 [ [ 1, "bytes" ], [ 1024, "kB" ], [ 1024*1024, "MB" ],
			   [ 1024*1024*1024, "GB" ] ], 1, 0, 0, $_[3]);
	}
else {
	# Just show blocks input
	return &ui_textbox($name, $value, 10, $dis)." ".$text{'form_b'};
	}
}

# opt_quota_input(name, value, filesystem|"home"|"mail"|"none",
#                 [third-option], [set-label])
# Returns HTML for a field for selecting a quota or unlimited
sub opt_quota_input
{
local ($name, $value, $fs, $third, $label) = @_;
local $dis1 = &js_disable_inputs([ $name, $name."_units" ], [ ]);
local $dis2 = &js_disable_inputs([ ], [ $name, $name."_units" ]);
local $mode = $value eq "" ? 1 : $value eq "0" ? 1 : $value eq "none" ? 2 : 0;
local $qi = $fs eq "none" ? &ui_textbox($name, $mode ? "" : $value, 10)
			  : &quota_input($name, $mode ? "" : $value, $fs,$mode);
return &ui_radio($name."_def", $mode,
	  [ $third ? ([ 2, $third, "onClick='$dis1'" ]) : ( ),
	    [ 1, $text{'form_unlimit'}, "onClick='$dis1'" ],
	    [ 0, $label." ".$qi, "onClick='$dis2'" ] ]);
}

# quota_parse(name, filesystem|"home"|"mail")
# Converts an entered quota into blocks
sub quota_parse
{
local $bsize = &quota_bsize($_[1]);
if (!$bsize) {
	return $in{$_[0]};
	}
else {
	return int($in{$_[0]}*$in{$_[0]."_units"}/$bsize);
	}
}

# quota_javascript(name, value, filesystem|"none", unlimited-possible)
# Returns Javascript to set some quota field using Javascript
sub quota_javascript
{
local ($name, $value, $fs, $unlimited) = @_;
local $bsize = $fs eq "none" ? 0 : $fs eq "bw" ? 1 : &quota_bsize($fs);
local $rv;
if ($bsize) {
	# Set value and units
	local $val = $value eq "none" ?  "" : $value*$bsize;
	local $index;
	if ($val >= 1024*1024*1024) {
		$val = $val/(1024*1024*1024);
		$index = 3;
		}
	elsif ($val >= 1024*1024) {
		$val = $val/(1024*1024);
		$index = 2;
		}
	elsif ($val >= 1024) {
		$val = $val/(1024);
		$index = 1;
		}
	else {
		$index = 0;
		}
	$val = sprintf("%.2f", $val) if ($val);
	$val =~ s/\.00$//;
	$rv .= "    document.forms[0].${name}.value = \"$val\";\n";
	$rv .= "    document.forms[0].${name}_units.selectedIndex = $index;\n";
	}
else  {
	# Just set blocks value
	local $val = $value eq "none" ?  "" : $value;
	$rv .= "    document.forms[0].${name}.value = \"$val\";\n";
	}
if ($unlimited) {
	if ($value eq "none") {
		$rv .= "    document.forms[0].${name}_def[0].checked = true;\n";
		$rv .= "    document.forms[0].${name}.disabled = true;\n";
		$rv .= "    if (document.forms[0].${name}_units) {\n";
		$rv .= "        document.forms[0].${name}_units.disabled = true;\n";
		$rv .= "    }\n";
		}
	else {
		$rv .= "    document.forms[0].${name}_def[1].checked = true;\n";
		$rv .= "    document.forms[0].${name}.disabled = false;\n";
		$rv .= "    if (document.forms[0].${name}_units) {\n";
		$rv .= "        document.forms[0].${name}_units.disabled = false;\n";
		$rv .= "    }\n";
		}
	}
return $rv;
}

# backup_domains(file, &domains, &features, dir-format, skip-errors, &options,
#		 home-format, &virtualmin-backups, mkdir, onebyone, as-owner)
# Perform a backup of one or more domains into a single tar.gz file. Returns
# an OK flag and the size of the backup file
sub backup_domains
{
local ($desturl, $doms, $features, $dirfmt, $skip, $opts, $homefmt, $vbs,
       $mkdir, $onebyone, $asowner) = @_;
local $backupdir;
local $transferred_sz;

# See if we can actually connect to the remote server
local ($mode, $user, $pass, $server, $path, $port) =
	&parse_backup_url($desturl);
if ($mode == 1) {
	# Try FTP login
	local $ftperr;
	&ftp_onecommand($server, "CWD /", \$ftperr, $user, $pass, $port);
	if ($ftperr) {
		&$first_print(&text('backup_eftptest', $ftperr));
		return (0, 0);
		}
	if ($dirfmt) {
		# Also create the destination directory now (ignoring any error,
		# as it may already exist)
		local $mkdirerr;
		&ftp_onecommand($server, "MKD $path", \$mkdirerr, $user, $pass,
				$port);
		}
	}
elsif ($mode == 2) {
	# Try a dummy SCP
	local $scperr;
	local $r = ($user ? "$user\@" : "").
		   "$server:/tmp/virtualmin-copy-test.$user";
	local $temp = &transname();
	open(TEMP, ">$temp");
	close(TEMP);
	&scp_copy($temp, $r, $pass, \$scperr, $port);
	if ($scperr) {
		&$first_print(&text('backup_escptest', $scperr));
		return (0, 0);
		}
	if ($dirfmt && $path ne "/") {
		# Also create the destination directory now, by scping an
		# empty dir.
		$path =~ /^(.*)\/([^\/]+)\/?$/;
		local ($pathdir, $pathfile) = ($1, $2);
		local $empty = &transname($pathfile);
		local $mkdirerr;
		&make_dir($empty, 0755);
		local $r = ($user ? "$user\@" : "")."$server:$pathdir";
		&scp_copy($empty, $r, $pass, \$mkdirerr, $port);
		}
	}
elsif ($mode == 3) {
	# Connect to S3 service and create bucket
	if ($path && $dirfmt) {
		&$first_print($text{'backup_es3path'});
		return (0, 0);
		}
	elsif (!$path && !$dirfmt) {
		&$first_print($text{'backup_es3nopath'});
		return (0, 0);
		}
	local $cerr = &check_s3();
	if ($cerr) {
		&$first_print($cerr);
		return (0, 0);
		}
	local $err = &init_s3_bucket($user, $pass, $server);
	if ($err) {
		&$first_print($err);
		return (0, 0);
		}
	}
elsif ($mode == 0) {
	# Make sure target is / is not a directory
	if ($dirfmt && !-d $desturl) {
		# Looking for a directory
		if ($mkdir) {
			&make_dir($desturl, 0755);
			}
		else {
			&$first_print(&text('backup_edirtest',
					    "<tt>$desturl</tt>"));
			return (0, 0);
			}
		}
	elsif (!$dirfmt && -d $desturl) {
		&$first_print(&text('backup_enotdirtest', "<tt>$desturl</tt>"));
		return (0, 0);
		}
	if (!$dirfmt && $mkdir) {
		# Create parent directories if requested
		local $dirdest = $desturl;
		$dirdest =~ s/\/[^\/]+$//;
		if ($dirdest && !-d $dirdest) {
			&make_dir($dirdest, 0755);
			}
		}
	}

if (!$homefmt) {
	# Create a temp dir for the backup, to be tarred up later
	$backupdir = &transname();
	&make_dir($backupdir, 0755);
	}
else {
	# A home-format backup can only be used if the home directory is
	# included, and if we are doing one per domain, and if all domains
	# *have* a home directory
	if (!$dirfmt) {
		&$first_print($text{'backup_ehomeformat'});
		return (0, 0);
		}
	if (&indexof("dir", @$features) == -1) {
		&$first_print($text{'backup_ehomeformat2'});
		return (0, 0);
		}
	foreach my $d (@$doms) {
		if (!$d->{'dir'} && !$skip) {
			&$first_print(&text('backup_ehomeformat3',
					    $d->{'dom'}));
			return (0, 0);
			}
		}
	# Skip any that don't have directories
	$doms = [ grep { $_->{'dir'} } @$doms ];
	}

# Work out where to write the final tar files to
local ($dest, @destfiles, %destfiles_map);
if ($mode >= 1) {
	# Write archive to temporary file/dir first, for later upload
	$path =~ /^(.*)\/([^\/]+)\/?$/;
	local ($pathdir, $pathfile) = ($1, $2);
	$dest = &transname($pathfile);
	}
else {
	# Can write direct to destination
	$dest = $path;
	}
if ($dirfmt) {
	&make_dir($dest, 0755);
	}

# For a home-format backup, the home has to be last
local @backupfeatures = @$features;
local $hfsuffix;
if ($homefmt) {
	@backupfeatures = ((grep { $_ ne "dir" } @$features), "dir");
	$hfsuffix = $config{'compression'} == 0 ? "tar.gz" :
		    $config{'compression'} == 1 ? "tar.bz2" : "tar";
	}

# Go through all the domains, and for each feature call the backup function
# to add it to the backup directory
local $d;
local $ok = 1;
local @donedoms;
local ($okcount, $errcount) = (0, 0);
local @errdoms;
local %donefeatures;				# Map from domain name->features
DOMAIN: foreach $d (@$doms) {
	if ($homefmt) {
		# Backup goes to a sub-dir of the home
		$backupdir = "$d->{'home'}/.backup";
		system("rm -rf ".quotemeta($backupdir));
		&make_dir($backupdir, 0777);
		}
	&$first_print(&text('backup_fordomain', $d->{'dom'}));
	&$second_print();
	&$indent_print();
	local $f;
	local $dok = 1;
	local @donefeatures;
	foreach $f (@backupfeatures) {
		local $bfunc = "backup_$f";
		local $fok;
		if (&indexof($f, @backup_plugins) < 0 &&
		    defined(&$bfunc) &&
		    ($d->{$f} || $f eq "virtualmin" ||
		     $f eq "mail" && &can_domain_have_users($d))) {
			# Call core feature backup function
			local $ffile;
			if ($homefmt && $f eq "dir") {
				# For a home format backup, write the home
				# itself to the backup destination
				$ffile = "$dest/$d->{'dom'}.$hfsuffix";
				}
			else {
				$ffile = "$backupdir/$d->{'dom'}_$f";
				}
			$fok = &$bfunc($d, $ffile, $opts->{$f}, $homefmt);
			}
		elsif (&indexof($f, @backup_plugins) >= 0 &&
		       $d->{$f}) {
			# Call plugin backup function
			local $ffile = "$backupdir/$d->{'dom'}_$f";
			local $fok = &plugin_call($f, "feature_backup",
					  $d, $ffile, $opts->{$f}, $homefmt);
			}
		if (defined($fok)) {
			# See if it worked or not
			$dok = 0 if (!$fok);
			if (!$fok && !$skip) {
				$ok = 0;
				$errcount++;
				push(@errdoms, $d->{'dom'});
				last DOMAIN;
				}
			push(@donedoms, $d);
			}
		if ($fok) {
			push(@donefeatures, $f);
			}
		}
	$donefeatures{$d->{'dom'}} = \@donefeatures;
	if ($dok) {
		$okcount++;
		}
	else {
		$errcount++;
		push(@errdoms, $d->{'dom'});
		}

	if ($onebyone && $homefmt && $dok) {
		# Transfer this domain now
		local $err;
		local $df = "$d->{'dom'}.$hfsuffix";
		if ($mode == 2) {
			# Via SCP
			&$first_print($text{'backup_upload2'});
			local $r = ($user ? "$user\@" : "")."$server:$path";
			&scp_copy("$dest/$df", $r, $pass, \$err, $port);
			}
		elsif ($mode == 1) {
			# Via FTP
			&$first_print($text{'backup_upload'});
			&ftp_upload($server, "$path/$df", "$dest/$df", \$err,
				    undef, $user, $pass, $port);
			}
		if ($mode == 3) {
			# Via S3 upload
			&$first_print($text{'backup_upload3'});
			local $binfo = { $d->{'dom'} =>
					 $donefeatures{$d->{'dom'}} };
			$err = &s3_upload($user, $pass, $server,
					  "$dest/$df", $df, $binfo);
			}
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			local @tst = stat("$dest/$df");
			$transferred_sz += $tst[7];
			}

		# Delete .backup directory
		&execute_command("rm -rf ".quotemeta("$d->{'home'}/.backup"));
		&execute_command("rm -rf ".quotemeta("$dest/$df"));
		}

	&$outdent_print();
	}

# Add all requested Virtualmin config information
local $vcount = 0;
if (@$vbs) {
	&$first_print(&text('backup_global',
		      join(", ", map { $text{'backup_v'.$_} } @$vbs)));
	if ($homefmt) {
		# Need to make a backup dir, as we cannot use one of the
		# previous domains' dirs
		$backupdir = &transname();
		&make_dir($backupdir, 0755);
		}
	foreach my $v (@$vbs) {
		local $vfile = "$backupdir/virtualmin_".$v;
		local $vfunc = "virtualmin_backup_".$v;
		local $ok = &$vfunc($vfile, $vbs);
		$vcount++;
		}
	&$second_print($text{'setup_done'});
	}

if ($ok) {
	# Work out command for writing to backup destination (which may use
	# su, so that permissions are correct)
	local $out;
	if ($homefmt) {
		# No final step is needed for home-format backups, because
		# we have already reached it!
		if (!$onebyone) {
			foreach $d (&unique(@donedoms)) {
				push(@destfiles, "$d->{'dom'}.$hfsuffix");
				$destfiles_map{$destfiles[$#destfiles]} = $d;
				}
			}
		}
	elsif ($dirfmt) {
		# Create one tar file in the destination for each domain
		&$first_print($text{'backup_final2'});
		&make_dir($dest, 0755);

		foreach $d (&unique(@donedoms)) {
			# Work out dest file and compression command
			local $destfile = "$d->{'dom'}.tar";
			local $comp = "cat";
			if ($config{'compression'} == 0) {
				$destfile .= ".gz";
				$comp = "gzip -c";
				}
			elsif ($config{'compression'} == 1) {
				$destfile .= ".bz2";
				$comp = "bzip2 -c";
				}
			local $writer = "cat >$dest/$destfile";
			if ($asowner) {
				$writer = &command_as_user(
					$doms[0]->{'user'}, 0, $writer);
				}

			&execute_command("cd $backupdir && (tar cf - $d->{'dom'}_* | $comp) 2>&1 | $writer", undef, \$out);
			push(@destfiles, $destfile);
			$destfiles_map{$destfile} = $d;
			if ($?) {
				&$second_print(&text('backup_finalfailed',
						     "<pre>$out</pre>"));
				$ok = 0;
				last;
				}
			}
		&$second_print($text{'setup_done'}) if ($ok);
		}
	else {
		# Tar up the directory into the final file
		local $comp = "cat";
		if ($dest =~ /\.(gz|tgz)$/i) {
			$comp = "gzip -c";
			}
		elsif ($dest =~ /\.(bz2|tbz2)$/i) {
			$comp = "bzip2 -c";
			}
		local $writer = "cat >$dest";
		if ($asowner) {
			$writer = &command_as_user(
					$doms[0]->{'user'}, 0, $writer);
		 	}
		&$first_print($text{'backup_final'});
		&execute_command("cd $backupdir && (tar cf - . | $comp) 2>&1 | $writer", undef, \$out);
		if ($?) {
			&$second_print(&text('backup_finalfailed', "<pre>$out</pre>"));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	# Create a separate file in the destination directory for Virtualmin
	# config backups
	if (@$vbs && ($homefmt || $dirfmt)) {
		if (&has_command("gzip")) {
			&execute_command("cd $backupdir && (tar cf - virtualmin_* | gzip -c) 2>&1 >$dest/virtualmin.tar.gz", undef, \$out, \$out);
			push(@destfiles, "virtualmin.tar.gz");
			}
		else {
			&execute_command("cd $backupdir && tar cf $dest/virtualmin.tar virtualmin_* 2>&1", undef, \$out, \$out);
			push(@destfiles, "virtualmin.tar");
			}
		$destfiles_map{$destfiles[$#destfiles]} = "virtualmin";
		}
	$donefeatures{"virtualmin"} = $vbs;
	}

if (!$homefmt) {
	# Remove the global backup temp directory
	&execute_command("rm -rf ".quotemeta($backupdir));
	}
elsif (!$onebyone) {
	# For each domain, remove it's .backup directory
	foreach $d (@$doms) {
		&execute_command("rm -rf ".quotemeta("$d->{'home'}/.backup"));
		}
	}

# Work out backup size, including files already transferred and deleted
local $sz = 0;
if ($dirfmt) {
	# Multiple files
	foreach my $f (@destfiles) {
		local @st = stat("$dest/$f");
		$sz += $st[7];
		}
	}
else {
	# One file
	local @st = stat($dest);
	$sz = $st[7];
	}
$sz += $transferred_sz;

if ($ok && $mode == 1 && (@destfiles || !$dirfmt)) {
	# Upload file(s) to FTP server
	&$first_print($text{'backup_upload'});
	local $err;
	if ($dirfmt) {
		# Need to upload entire directory .. which has to be created
		foreach my $df (@destfiles) {
			&ftp_upload($server, "$path/$df", "$dest/$df", \$err,
				    undef, $user, $pass, $port);
			if ($err) {
				&$second_print(
					&text('backup_uploadfailed', $err));
				$ok = 0;
				last;
				}
			}
		}
	else {
		# Just a single file
		&ftp_upload($server, $path, $dest, \$err, undef, $user, $pass,
			    $port);
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}
elsif ($ok && $mode == 2 && (@destfiles || !$dirfmt)) {
	# Upload to SSH server with scp
	&$first_print($text{'backup_upload2'});
	local $err;
	local $r = ($user ? "$user\@" : "")."$server:$path";
	if ($dirfmt) {
		# Need to upload entire directory
		&scp_copy("$dest/*", $r, $pass, \$err, $port);
		if ($err) {
			# Target dir didn't exist, so scp just the directory
			$err = undef;
			&scp_copy($dest, $r, $pass, \$err, $port);
			}
		}
	else {
		# Just a single file
		&scp_copy($dest, $r, $pass, \$err, $port);
		}
	if ($err) {
		&$second_print(&text('backup_uploadfailed', $err));
		$ok = 0;
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}
elsif ($ok && $mode == 3 && (@destfiles || !$dirfmt)) {
	# Upload to S3 server
	local $err;
	&$first_print($text{'backup_upload3'});
	if ($dirfmt) {
		# Upload an entire directory of files
		foreach my $df (@destfiles) {
			local $d = $destfiles_map{$df};
			local $n = $d eq "virtualmin" ? "virtualmin"
						      : $d->{'dom'};
			local $binfo = { $n => $donefeatures{$n} };
			$err = &s3_upload($user, $pass, $server, "$dest/$df",
					  $df, $binfo);
			if ($err) {
				&$second_print(
					&text('backup_uploadfailed', $err));
				$ok = 0;
				last;
				}
			}
		}
	else {
		# Upload one file to the bucket
		local %donebydname;
		$err = &s3_upload($user, $pass, $server, $dest,
				  $path, \%donefeatures);
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}

if ($mode >= 1) {
	# Always delete the temporary destination
	&execute_command("rm -rf ".quotemeta($dest));
	}

# Show some status
if ($ok) {
	&$first_print(
	  ($okcount || $errcount ?
	    &text('backup_finalstatus', $okcount, $errcount) : "")."\n".
	  ($vcount ? &text('backup_finalstatus2', $vcount) : ""));
	if ($errcount) {
		&$first_print(&text('backup_errorsites', join(" ", @errdoms)));
		}
	}

return ($ok, $sz);
}

# backup_virtualmin(&domain, file)
# Adds a domain's configuration file to the backup
sub backup_virtualmin
{
&$first_print($text{'backup_virtualmincp'});
&copy_source_dest($_[0]->{'file'}, $_[1]);
if (-r "$initial_users_dir/$_[0]->{'id'}") {
	# Initial user settings
	&copy_source_dest("$initial_users_dir/$_[0]->{'id'}", $_[1]."_initial");
	}
if (-d "$extra_admins_dir/$_[0]->{'id'}") {
	# Extra admin details
	&execute_command("cd ".quotemeta("$extra_admins_dir/$_[0]->{'id'}")." && tar cf ".quotemeta($_[1]."_admins")." .");
	}
if ($config{'bw_active'}) {
	# Bandwidth logs
	if (-r "$bandwidth_dir/$_[0]->{'id'}") {
		&copy_source_dest("$bandwidth_dir/$_[0]->{'id'}", $_[1]."_bw");
		}
	else {
		# Create an empty file to indicate that we have no data
		&open_tempfile(EMPTY, ">".$_[1]."_bw");
		&close_tempfile(EMPTY);
		}
	}
if ($virtualmin_pro) {
	# Script logs
	if (-d "$script_log_directory/$_[0]->{'id'}") {
		&execute_command("cd ".quotemeta("$script_log_directory/$_[0]->{'id'}")." && tar cf ".quotemeta($_[1]."_scripts")." .");
		}
	else {
		# Create an empty file to indicate that we have no scripts
		&open_tempfile(EMPTY, ">".$_[1]."_scripts");
		&close_tempfile(EMPTY);
		}
	}
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_config(file, &vbs)
# Save the current module config to the specified file
sub virtualmin_backup_config
{
local ($file, $vbs) = @_;
&copy_source_dest($module_config_file, $file);
}

# virtualmin_restore_config(file, &vbs)
# Replace the current config with the given file, *except* for the default
# template settings
sub virtualmin_restore_config
{
local ($file, $vbs) = @_;
local @tmpls = &list_templates();
&copy_source_dest($file, $module_config_file);
&read_file($module_config_file, \%config);
foreach my $t (@tmpls) {
	if ($t->{'standard'}) {
		&save_template($t);
		}
	}
}

# virtualmin_backup_templates(file, &vbs)
# Write a tar file of all templates (including scripts) to the given file
sub virtualmin_backup_templates
{
local ($file, $vbs) = @_;
local $temp = &transname();
mkdir($temp, 0700);
foreach my $tmpl (&list_templates()) {
	my %tmplquoted = %$tmpl;
	foreach my $k (keys %tmplquoted) {
		$tmplquoted{$k} =~ s/\n/\\n/g;
		}
	&write_file("$temp/$tmpl->{'id'}", \%tmplquoted);
	}
&execute_command("cp $template_scripts_dir/* $temp");
&execute_command("cd ".quotemeta($temp)." && tar cf ".quotemeta($file)." .");
&execute_command("rm -rf ".quotemeta($temp));
}

# virtualmin_restore_templates(file, &vbs)
# Extract all templates from a backup. Those that already exist are not deleted.
sub virtualmin_restore_templates
{
local ($file, $vbs) = @_;

# Extract backup file
local $temp = &transname();
mkdir($temp, 0700);
&execute_command("cd ".quotemeta($temp)." && tar xf ".quotemeta($file));

# Copy templates from backup across
opendir(DIR, $temp);
foreach my $t (readdir(DIR)) {
	next if ($t eq "." || $t eq "..");
	if ($t =~ /^(\d+)_(\d+)$/) {
		# A script file
		&copy_source_dest("$temp/$t", "$template_scripts_dir/$t");
		}
	else {
		# A template file
		local %tmpl;
		&read_file("$temp/$t", \%tmpl);
		foreach my $k (keys %tmpl) {
			$tmpl{$k} =~ s/\\n/\n/g;
			}
		&save_template(\%tmpl);
		}
	}
closedir(DIR);

&execute_command("rm -rf ".quotemeta($temp));
}

# virtualmin_backup_resellers(file, &vbs)
# Create a tar file of reseller details. For each we need to store the Webmin
# user information, plus all ACL files
sub virtualmin_backup_resellers
{
local ($file, $vbs) = @_;
local $temp = &transname();
mkdir($temp, 0700);
foreach my $resel (&list_resellers()) {
	&open_tempfile(RESEL, ">$temp/$resel->{'name'}.webmin");
	&print_tempfile(RESEL, &serialise_variable($resel));
	&close_tempfile(RESEL);
	local $acldir = "$temp/$resel->{'name'}.acls";
	mkdir($acldir, 0700);
	foreach my $m (@{$resel->{'modules'}}) {
		local %acl = &get_module_acl($resel->{'name'}, $m, 1, 1);
		&write_file("$acldir/$m", \%acl);
		}
	}
&execute_command("cd ".quotemeta($temp)." && tar cf ".quotemeta($file)." .");
&execute_command("rm -rf ".quotemeta($temp));
}

# virtualmin_restore_resellers(file, &vbs)
# Delete all resellers and re-create them from the backup
sub virtualmin_restore_resellers
{
local ($file, $vbs) = @_;
local $temp = &transname();
mkdir($temp, 0700);
&require_acl();
&execute_command("cd ".quotemeta($temp)." && tar xf ".quotemeta($file));
foreach my $resel (&list_resellers()) {
	&acl::delete_user($resel->{'name'});
	}
&reload_miniserv();
opendir(DIR, $temp);
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(.*)\.webmin$/) {
		local $acldir = "$temp/$1";
		local $ser = &read_file_contents("$temp/$f");
		local $resel = &unserialise_variable($ser);
		&create_reseller($resel);
		opendir(ACL, $acldir);
		foreach my $a (readdir(ACL)) {
			next if ($a eq "." || $a eq "..");
			local %acl;
			&read_file("$acldir/$a", \%acl);
			&save_module_acl(\%acl, $resel->{'name'}, $a);
			}
		closedir(ACL);
		}
	}
&execute_command("rm -rf ".quotemeta($temp));
}

# virtualmin_backup_email(file, &vbs)
# Creates a tar file of all email templates
sub virtualmin_backup_email
{
local ($file, $vbs) = @_;
&execute_command("cd $module_config_directory && tar cf ".quotemeta($file)." ".
		 join(" ", @all_template_files));
}

# virtualmin_restore_email(file, &vbs)
# Extract a tar file of all email templates
sub virtualmin_restore_email
{
local ($file, $vbs) = @_;
&execute_command("cd $module_config_directory && tar xf ".quotemeta($file));
}

# virtualmin_backup_email(file, &vbs)
# Copies the custom fields file
sub virtualmin_backup_custom
{
local ($file, $vbs) = @_;
&copy_source_dest($custom_fields_file, $file);
}

# virtualmin_restore_custom(file, &vbs)
# Restores the custom fields file
sub virtualmin_restore_custom
{
local ($file, $vbs) = @_;
&copy_source_dest($file, $custom_fields_file);
}

# virtualmin_backup_scripts(file, &vbs)
# Create a tar file of the scripts directory, and of the unavailable scripts
sub virtualmin_backup_scripts
{
local ($file, $vbs) = @_;
&execute_command("cd $module_config_directory/scripts && tar cf ".quotemeta($file)." .");
&copy_source_dest($scripts_unavail_file, $file."_unavail");
}

# virtualmin_restore_scripts(file, &vbs)
# Extract a tar file of all third-party scripts
sub virtualmin_restore_scripts
{
local ($file, $vbs) = @_;
mkdir("$module_config_directory/scripts", 0755);
&execute_command("cd $module_config_directory/scripts && tar xf ".quotemeta($file));
if (-r $file."_unavail") {
	&copy_source_dest($file."_unavail", $scripts_unavail_file);
	}
}

# virtualmin_backup_styles(file, &vbs)
# Create a tar file of the styles directory, and of the unavailable styles
sub virtualmin_backup_styles
{
local ($file, $vbs) = @_;
&execute_command("cd $module_config_directory/styles && tar cf ".quotemeta($file)." .");
&copy_source_dest($styles_unavail_file, $file."_unavail");
}

# virtualmin_restore_styles(file, &vbs)
# Extract a tar file of all third-party styles
sub virtualmin_restore_styles
{
local ($file, $vbs) = @_;
mkdir("$module_config_directory/styles", 0755);
&execute_command("cd $module_config_directory/styles && tar xf ".quotemeta($file));
if (-r $file."_unavail") {
	&copy_source_dest($file."_unavail", $styles_unavail_file);
	}
}

# restore_domains(file, &domains, &features, &options, &vbs,
#		  [only-backup-features])
# Restore multiple domains from the given file
sub restore_domains
{
local ($file, $doms, $features, $opts, $vbs, $onlyfeats) = @_;

# Work out where the backup is located
local $ok = 1;
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($file);
if ($mode > 0) {
	# Need to download to temp file/directory first
	&$first_print($mode == 1 ? $text{'restore_download'} :
		      $mode == 3 ? $text{'restore_downloads3'} :
				   $text{'restore_downloadssh'});
	if ($mode == 3) {
		local $cerr = &check_s3();
		if ($cerr) {
			&$second_print($err);
			return 0;
			}
		}
	$backup = &transname();
	local $derr = &download_backup($_[0], $backup,
		[ map { $_->{'dom'} } @$doms ], $vbs);
	if ($derr) {
		&$second_print(&text('restore_downloadfailed', $derr));
		$ok = 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
else {
	$backup = $file;
	}

local $restoredir;
local %homeformat;
if ($ok) {
	# Create a temp dir for the backup archive contents
	$restoredir = &transname();
	&make_dir($restoredir, 0711);

	local @files;
	if (-d $backup) {
		# Extracting a directory of backup files
		&$first_print($text{'restore_first2'});
		opendir(DIR, $backup);
		@files = map { "$backup/$_" }
			     grep { $_ ne "." && $_ ne ".." } readdir(DIR);
		closedir(DIR);
		}
	else {
		# Extracting one backup file
		&$first_print($text{'restore_first'});
		@files = ( $backup );
		}

	# Extract each of the files
	local $f;
	foreach $f (@files) {
		local $out;
		local $q = quotemeta($f);

		# See if this is a home-format backup, by looking for a .backup
		# sub-directory
		local $lout;
		local $cf = &compression_format($f);
		local $comp = $cf == 1 ? "gunzip -c" :
			      $cf == 2 ? "uncompress -c" :
			      $cf == 3 ? "bunzip2 -c" : "cat";
		&execute_command("$comp $q | tar tf -", undef, \$lout, \$lout);
		local @lines = split(/\n/, $lout);
		local $extract;
		if (&indexof("./.backup/", @lines) >= 0 ||
		    &indexof("./.backup", @lines) >= 0) {
			# Home format! Only extract the .backup directory, as it
			# contains the feature files
			$homeformat{$f} = $f;
			$extract = "./.backup";
			}

		&execute_command("cd '$restoredir' && ($comp $q | tar xf - $extract)", undef, \$out, \$out);
		if ($?) {
			&$second_print(&text('restore_firstfailed',
					     "<tt>$f</tt>", "<pre>$out</pre>"));
			$ok = 0;
			last;
			}

		if ($homeformat{$f}) {
			# Move the .backup contents to the restore dir, as
			# expected by later code
			&execute_command("mv ".quotemeta("$restoredir/.backup")."/* ".quotemeta($restoredir));
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}

# Make sure any domains we need to re-create have a Virtualmin info file
foreach $d (@{$_[1]}) {
	if ($d->{'missing'}) {
		if (!-r "$restoredir/$d->{'dom'}_virtualmin") {
			&$second_print(&text('restore_missinginfo', $d->{'dom'}));
			$ok = 0;
			last;
			}
		}
	}

local $vcount = 0;
if ($ok) {
	# Fill in missing domain details
	foreach $d (@{$_[1]}) {
		if ($d->{'missing'}) {
			$d = &get_domain(undef,
				"$restoredir/$d->{'dom'}_virtualmin");
			if ($_[3]->{'fix'}) {
				# We can just use the domains file from the
				# backup and import it
				&save_domain($d);
				}
			else {
				# We will be re-creating the server
				$d->{'missing'} = 1;
				}
			}
		}

	# Now restore each of the domain/feature files
	local $d;
	DOMAIN: foreach $d (sort { $a->{'parent'} <=> $b->{'parent'} } @{$_[1]}) {
		if ($d->{'missing'}) {
			# This domain doesn't exist yet - need to re-create it
			&$first_print(&text('restore_createdomain',
				      $d->{'dom'}));

			# Only features in the backup are enabled
			if ($onlyfeats) {
				foreach my $f (@backup_features,
					       @backup_plugins) {
					if ($d->{$f} &&
					    &indexof($f, @$features) < 0) {
						$d->{$f} = 0;
						}
					}
				}

			local $cerr = &virtual_server_clashes($d);
			if ($cerr) {
				&$second_print(&text('restore_eclash', $cerr));
				$ok = 0;
				last DOMAIN;
				}
			local ($parentdom, $parentuser);
			if ($d->{'parent'}) {
				# Does the parent exist?
				$parentdom = &get_domain($d->{'parent'});
				if (!$parentdom) {
					&$second_print($text{'restore_epar'});
					$ok = 0;
					last DOMAIN;
					}
				$parentuser = $parentdom->{'user'};
				}

			# Does the template exist?
			local $tmpl = &get_template($d->{'template'});
			if (!$tmpl) {
				&$second_print($text{'restore_etemplate'});
				$ok = 0;
				last DOMAIN;
				}

			if ($parentdom) {
				# UID and GID always come from parent
				$d->{'uid'} = $parentdom->{'uid'};
				$d->{'gid'} = $parentdom->{'gid'};
				$d->{'ugid'} = $parentdom->{'ugid'};
				}
			elsif ($_[3]->{'reuid'}) {
				# Re-allocate the UID and GID
				local ($samegid) =($d->{'gid'} == $d->{'ugid'});
				local (%gtaken, %taken);
				&build_group_taken(\%gtaken);
				$d->{'gid'} = &allocate_gid(\%gtaken);
				$d->{'ugid'} = $d->{'gid'};
				&build_taken(\%taken);
				$d->{'uid'} = &allocate_uid(\%taken);
                                if (!$samegid) {
                                        # Old ugid was custom, so set from old
                                        # group name
                                        local @ginfo = getgrnam($d->{'ugroup'});
                                        if (@ginfo) {
                                                $d->{'ugid'} = $ginfo[2];
                                                }
                                        }
				}

			# Set the home directory to match this system's base
			local $oldhome = $d->{'home'};
			$d->{'home'} = &server_home_directory($d, $parentdom);
			if ($d->{'home'} ne $oldhome) {
				# Fix up setings that reference the home
				$d->{'ssl_cert'} =~s/\Q$oldhome\E/$d->{'home'}/;
				$d->{'ssl_key'} =~ s/\Q$oldhome\E/$d->{'home'}/;
				}

			# Create the domain, fixing the IP if needed
			&$indent_print();
			delete($d->{'missing'});
			if ($d->{'alias'}) {
				local $alias = &get_domain($d->{'alias'});
				$d->{'ip'} = $alias->{'ip'};
				}
			elsif (!$d->{'virt'} && !$config{'all_namevirtual'}) {
				$d->{'ip'} = &get_default_ip($d->{'reseller'});
				if (!$d->{'ip'}) {
					&$second_print($text{'restore_edefip'});
					$ok = 0;
					last DOMAIN;
					}
				}
			$d->{'nocreationmail'} = 1;
			$d->{'nocreationscripts'} = 1;
			&create_virtual_server($d, $parentdom,
			       $parentdom ? $parentdom->{'user'} : undef, 1);
			&$outdent_print();
			}

		# Users need to be restored last
		local @rfeatures = @$features;
		if (&indexof("mail", @rfeatures) >= 0) {
			@rfeatures =((grep { $_ ne "mail" } @$features),"mail");
			}

		# Now do the actual restore
		&$first_print(&text('restore_fordomain', $d->{'dom'}));
		&$indent_print();
		local $f;
		local %oldd;
		foreach $f (@rfeatures) {
			# Restore features
			local $rfunc = "restore_$f";
			local $fok;
			if (&indexof($f, @backup_plugins) < 0 &&
			    defined(&$rfunc) &&
			    ($d->{$f} || $f eq "virtualmin" ||
			     $f eq "mail" && &can_domain_have_users($d))) {
				local $ffile;
				local $hft =
				    $homeformat{"$backup/$d->{'dom'}.tar.gz"} ||
				    $homeformat{"$backup/$d->{'dom'}.tar.bz2"}||
				    $homeformat{"$backup/$d->{'dom'}.tar"} ||
				    $homeformat{$backup};
				if ($hft && $f eq "dir") {
					# For a home-format backup, the backup
					# itself is the home
					$ffile = $hft;
					}
				else {
					$ffile = "$restoredir/$d->{'dom'}_$f";
					}
				if ($f eq "virtualmin") {
					# If restoring the virtualmin info, keep
					# the old feature file
					&read_file($ffile, \%oldd);
					}
				if (-r $ffile) {
					# Call the restore function
					$fok = &$rfunc($d, $ffile,
					     $_[3]->{$f}, $_[3], $hft, \%oldd);
					}
				}
			elsif (&indexof($f, @backup_plugins) >= 0 &&
			       $d->{$f}) {
				# Restoring a plugin feature
				local $ffile = "$restoredir/$d->{'dom'}_$f";
				if (-r $ffile) {
					$fok = &plugin_call($f,
					    "feature_restore", $d, $ffile,
					    $_[3]->{$f}, $_[3], $hft, \%oldd);
					}
				}
			if (defined($fok) && !$fok) {
				# Handle feature failure
				$ok = 0;
				&$outdent_print();
				last DOMAIN;
				}
			}
		&save_domain($d);

		# Re-setup Webmin user
		&refresh_webmin_user($d);
		&$outdent_print();
		}

	# Restore any Virtualmin settings
	if (@$vbs) {
		&$first_print(&text('restore_global',
			      join(", ", map { $text{'backup_v'.$_} } @$vbs)));
		foreach my $v (@$vbs) {
			local $vfile = "$restoredir/virtualmin_".$v;
			if (-r $vfile) {
				local $vfunc = "virtualmin_restore_".$v;
				local $ok = &$vfunc($vfile, $vbs);
				$vcount++;
				}
			}
		&$second_print($text{'setup_done'});
		}
	}

&execute_command("rm -rf ".quotemeta($restoredir));
if ($mode > 0) {
	# Clean up downloaded file
	&execute_command("rm -rf ".quotemeta($backup));
	}
return $ok;
}

# backup_contents(file)
# Returns a hash ref of domains and features in a backup file, or an error
# string if it is invalid
sub backup_contents
{
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($_[0]);
if ($mode == 3) {
	# For S3, just download the backup contents files
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	local %rv;
	foreach my $b (keys %$s3b) {
		$rv{$b} = $s3b->{$b}->{'features'};
		}
	return \%rv;
	}
elsif ($mode > 0) {
	# Need to download to temp file first
	$backup = &transname();
	local $derr = &download_backup($_[0], $backup);
	return $derr if ($derr);
	}
else {
	$backup = $_[0];
	}

if (-d $backup) {
	# A directory of backup files, one per domain
	opendir(DIR, $backup);
	local $f;
	local %rv;
	foreach $f (readdir(DIR)) {
		next if ($f eq "." || $f eq "..");
		local $cont = &backup_contents("$backup/$f");
		if (ref($cont)) {
			local $d;
			foreach $d (keys %$cont) {
				if ($rv{$d}) {
					&clean_contents_temp();
					return &text('restore_edup', $d);
					}
				else {
					$rv{$d} = $cont->{$d};
					}
				}
			}
		else {
			&clean_contents_temp();
			return $backup."/".$f." : ".$cont;
			}
		}
	closedir(DIR);
	&clean_contents_temp();
	return \%rv;
	}
else {
	# A single file
	local $err;
	open(BACKUP, $backup);
	local $two;
	read(BACKUP, $two, 2);
	close(BACKUP);
	local $out;
	local $q = quotemeta($backup);
	local $cf = &compression_format($backup);
	local $comp = $cf == 1 ? "gunzip -c" :
		      $cf == 2 ? "uncompress -c" :
		      $cf == 3 ? "bunzip2 -c" : "cat";
	$out = `($comp $q | tar tf -) 2>&1`;
	if ($?) {
		&clean_contents_temp();
		return $text{'restore_etar'};
		}

	# Look for a home-format backup first
	local ($l, %rv, %done, $dotbackup);
	foreach $l (split(/\n/, $out)) {
		if ($l =~ /^(.\/)?.backup\/([^_]+)_([a-z0-9\-]+)$/) {
			# Found a .backup/domain_feature file
			push(@{$rv{$2}}, $3) if (!$done{$2,$3}++);
			push(@{$rv{$2}}, "dir") if (!$done{$2,"dir"}++);
			$dotbackup = 1;
			}
		}
	if (!$dotbackup) {
		# Look for an old-format backup
		foreach $l (split(/\n/, $out)) {
			if ($l =~ /^(.\/)?([^_]+)_([a-z0-9\-]+)$/) {
				# Found a domain_feature file
				push(@{$rv{$2}}, $3) if (!$done{$2,$3}++);
				}
			}
		}
	&clean_contents_temp();
	return \%rv;
	}

	sub clean_contents_temp
	{
	&execute_command("rm -rf ".quotemeta($backup)) if ($mode > 0);
	}
}

# download_backup(url, tempfile, [&domain-names], [&config-features])
# Downloads a backup file or directory to a local temp file or directory.
# Returns undef on success, or an error message.
sub download_backup
{
local ($url, $temp, $domnames, $vbs) = @_;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($url);
if ($mode == 1) {
	# Download from FTP server
	local $cwderr;
	local $isdir = &ftp_onecommand($server, "CWD $path", \$cwderr,
				       $user, $pass, $port);
	local $err;
	if ($isdir) {
		# Need to download entire directory
		&make_dir($temp, 0700);
		local $list = &ftp_listdir($server, $path, \$err, $user, $pass,
					   $port);
		return $err if (!$list);
		foreach $f (@$list) {
			$f =~ s/^$path[\\\/]//;
			next if ($f eq "." || $f eq ".." || $f eq "");
			&ftp_download($server, "$path/$f", "$temp/$f", \$err,
				      undef, $user, $pass, $port);
			return $err if ($err);
			}
		return undef;
		}
	else {
		# Can just download a single file
		&ftp_download($server, $path, $temp, \$err,
			      undef, $user, $pass, $port);
		return $err;
		}
	}
elsif ($mode == 2) {
	# Download from SSH server
	&scp_copy(($user ? "$user\@" : "")."$server:$path",
		  $temp, $pass, \$err, $port);
	return $err;
	}
elsif ($mode == 3) {
	# Download from S3 server
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	local @wantdoms;
	push(@wantdoms, @$domnames) if (@$domnames);
	push(@wantdoms, "virtualmin") if (@$vbs);
	@wantdoms = (keys %$s3b) if (!@wantdoms);
	&make_dir($temp, 0700);
	foreach my $dname (@wantdoms) {
		local $si = $s3b->{$dname};
		if (!$si) {
			return &text('restore_es3info', $dname);
			}
		local $err = &s3_download($user, $pass, $server,
					  $si->{'file'}, "$temp/$si->{'file'}");
		return $err if ($err);
		}
	return undef;
	}
}

# restore_virtualmin(&domain, file, &opts, &allopts)
# Restore the settings for a domain, such as quota, password and so on. Only
# selected settings are copied from the backup, such as limits.
sub restore_virtualmin
{
if (!$_[3]->{'fix'}) {
	# Merge current and backup configs
	&$first_print($text{'restore_virtualmincp'});
	local %oldd;
	&read_file($_[1], \%oldd);
	$_[0]->{'quota'} = $oldd{'quota'};
	$_[0]->{'uquota'} = $oldd{'uquota'};
	$_[0]->{'bw_limit'} = $oldd{'bw_limit'};
	$_[0]->{'pass'} = $oldd{'pass'};
	$_[0]->{'email'} = $oldd{'email'};
	foreach my $l (@limit_types) {
		$_[0]->{$l} = $oldd{$l};
		}
	$_[0]->{'nodbname'} = $oldd{'nodbname'};
	$_[0]->{'norename'} = $oldd{'norename'};
	$_[0]->{'forceunder'} = $oldd{'forceunder'};
	foreach my $f (@opt_features, @feature_plugins, "virt") {
		$_[0]->{'limit_'.$f} = $oldd{'limit_'.$f};
		}
	$_[0]->{'owner'} = $oldd{'owner'};
	$_[0]->{'proxy_pass_mode'} = $oldd{'proxy_pass_mode'};
	$_[0]->{'proxy_pass'} = $oldd{'proxy_pass'};
	foreach my $f (&list_custom_fields()) {
		$_[0]->{$f->{'name'}} = $oldd{$f->{'name'}};
		}
	&save_domain($_[0]);
	if (-r $_[1]."_initial") {
		# Also restore user defaults file
		&copy_source_dest($_[1]."_initial",
				  "$initial_users_dir/$_[0]->{'id'}");
		}
	if (-r $_[1]."_admins") {
		# Also restore extra admins
		&execute_command("rm -rf ".quotemeta("$extra_admins_dir/$_[0]->{'id'}"));
		mkdir("$extra_admins_dir/$_[0]->{'id'}", 0755);
		&execute_command("cd ".quotemeta("$extra_admins_dir/$_[0]->{'id'}")." && tar xf ".quotemeta($_[1]."_admins")." .");
		}
	if ($config{'bw_active'} && -r $_[1]."_bw") {
		# Also restore bandwidth files
		&make_dir($bandwidth_dir, 0700);
		&copy_source_dest($_[1]."_bw", "$bandwidth_dir/$_[0]->{'id'}");
		}
	if ($virtualmin_pro && -r $_[1]."_scripts") {
		# Also restore script logs
		&execute_command("rm -rf ".quotemeta("$script_log_directory/$_[0]->{'id'}"));
		if (-s $_[1]."_scripts") {
			mkdir("$script_log_directory/$_[0]->{'id'}", 0755);
			&execute_command("cd ".quotemeta("$script_log_directory/$_[0]->{'id'}")." && tar xf ".quotemeta($_[1]."_scripts")." .");
			}
		}
	&$second_print($text{'setup_done'});
	}
return 1;
}

# backup_strftime(path)
# Replaces stftime-style % codes in a path with the current time
sub backup_strftime
{
eval "use POSIX";
eval "use posix" if ($@);
local @tm = localtime(time());
return strftime($_[0], @tm);
}

# parse_backup_url(string)
# Converts a URL like ftp:// or a filename into its components. These will be
# protocol (1 for FTP, 2 for SSH, 0 for local, 3 for S3, 4 for download), login,
# password, host, path and port
sub parse_backup_url
{
local @rv;
if ($_[0] =~ /^ftp:\/\/([^:]*):([^\@]*)\@([^\/:]+)(:\d+)?:?(\/.*)$/) {
	@rv = (1, $1, $2, $3, $5, $4 ? substr($4, 1) : 21);
	}
elsif ($_[0] =~ /^ssh:\/\/([^:]*):([^\@]*)\@([^\/:]+)(:\d+)?:?(\/.*)$/ ||
       $_[0] =~ /^ssh:\/\/([^:]*):([^\@]*)\@([^\/:]+)(:\d+)?:(.+)$/) {
	@rv = (2, $1, $2, $3, $5, $4 ? substr($4, 1) : 22);
	}
elsif ($_[0] =~ /^s3:\/\/([^:]*):([^\@]*)\@([^\/]+)(\/(.*))?$/) {
	@rv = (3, $1, $2, $3, $5, undef);
	}
elsif ($_[0] eq "download:") {
	return (4, undef, undef, undef, undef, undef);
	}
elsif (!$_[0] || $_[0] =~ /^\//) {
	# Absolute path
	@rv = (0, undef, undef, undef, $_[0], undef);
	$rv[4] =~ s/\/+$//;	# No need for trailing /
	}
else {
	# Relative to current dir
	local $pwd = &get_current_dir();
	@rv = (0, undef, undef, undef, $pwd."/".$_[0], undef);
	$rv[4] =~ s/\/+$//;
	}
if ($rv[0] && $rv[3] =~ /^(\S+):(\d+)$/) {
	# Convert hostname to host:port
	$rv[3] = $1;
	$rv[5] = $2;
	}
return @rv;
}

# nice_backup_url(string)
# Converts a backup URL to a nice human-readable format
sub nice_backup_url
{
local ($url) = @_;
local ($proto, $user, $pass, $host, $path, $port) = &parse_backup_url($url);
if ($proto == 1) {
	return &text('backup_niceftp', "<tt>$path</tt>", "<tt>$host</tt>");
	}
elsif ($proto == 2) {
	return &text('backup_nicescp', "<tt>$path</tt>", "<tt>$host</tt>");
	}
elsif ($proto == 3) {
	return &text('backup_nices3', "<tt>$host</tt>");
	}
elsif ($proto == 0) {
	return &text('backup_nicefile', "<tt>$path</tt>");
	}
else {
	return $url;
	}
}

# show_backup_destination(name, value, no-local, [&domain], [nodownload])
# Returns HTML for fields for selecting a local or FTP file
sub show_backup_destination
{
local ($name, $value, $nolocal, $d, $nodownload) = @_;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($_[1]);
local $defport = $mode == 1 ? 21 : $mode == 2 ? 22 : undef;
local $serverport = $port && $port != $defport ? "$server:$port" : $server;
local $rv;

local @opts;
if (!$nolocal) {
	# Local file field (can be anywhere)
	push(@opts, [ 0, $text{'backup_mode0'},
	       &ui_textbox($name."_file", $mode == 0 ? $path : "", 50)." ".
	       &file_chooser_button($name."_file")."<br>\n" ]);
	}
elsif ($d && $d->{'dir'}) {
	# Limit local file to under virtualmin-backups
	push(@opts, [ 0, $text{'backup_mode0a'},
	       &ui_textbox($name."_file",
		  $mode == 0 && $path =~ /virtualmin-backup\/(.*)$/ ? $1 : "",
		  50)."<br>\n" ]);
	}

# FTP file fields
local $ft = "<table>\n";
$ft .= "<tr> <td>$text{'backup_ftpserver'}</td> <td>".
       &ui_textbox($name."_server", $mode == 1 ? $serverport : undef, 20).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_path'}</td> <td>".
       &ui_textbox($name."_path", $mode == 1 ? $path : undef, 50).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_login'}</td> <td>".
       &ui_textbox($name."_user", $mode == 1 ? $user : undef, 15).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_pass", $mode == 1 ? $pass : undef, 15).
       "</td> </tr>\n";
$ft .= "</table>\n";
push(@opts, [ 1, $text{'backup_mode1'}, $ft ]);

# SCP file fields
local $st = "<table>\n";
$st .= "<tr> <td>$text{'backup_sshserver'}</td> <td>".
       &ui_textbox($name."_sserver", $mode == 2 ? $serverport : undef, 20).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_path'}</td> <td>".
       &ui_textbox($name."_spath", $mode == 2 ? $path : undef, 50).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_login'}</td> <td>".
       &ui_textbox($name."_suser", $mode == 2 ? $user : undef, 15).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_spass", $mode == 2 ? $pass : undef, 15).
       "</td> </tr>\n";
$st .= "</table>\n";
push(@opts, [ 2, $text{'backup_mode2'}, $st ]);

if (&can_use_s3()) {
	# S3 backup fields (bucket, access key ID, secret key and file)
	local $st = "<table>\n";
	$st .= "<tr> <td>$text{'backup_bucket'}</td> <td>".
	       &ui_textbox($name."_bucket", $mode == 3 ? $server : undef, 20).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_akey'}</td> <td>".
	       &ui_textbox($name."_akey", $mode == 3 ? $user : undef, 40).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_skey'}</td> <td>".
	       &ui_password($name."_skey", $mode == 3 ? $pass : undef, 40).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_s3file'}</td> <td>".
	       &ui_opt_textbox($name."_s3file", $mode == 3 ? $path : undef,
			       30, $text{'backup_nos3file'}).
	       "</td> </tr>\n";
	$st .= "</table>\n";
	push(@opts, [ 3, $text{'backup_mode3'}, $st ]);
	}

if (!$nodownload) {
	# Show mode to download in browser
	push(@opts, [ 4, $text{'backup_mode4'},
		      $text{'backup_mode4desc'}."<p>" ]);
	}

return &ui_radio_selector(\@opts, $name."_mode", $mode);
}

# parse_backup_destination(name, &in, no-local, [&domain])
# Returns a backup destination string, or calls error
sub parse_backup_destination
{
local %in = %{$_[1]};
local $mode = $in{"$_[0]_mode"};
if ($mode == 0 && !$_[2]) {
	# Any local file
	$in{"$_[0]_file"} =~ /^\/\S/ || &error($text{'backup_edest'});
	$in{"$_[0]_file"} =~ s/\/+$//;	# No need for trailing /
	return $in{"$_[0]_file"};
	}
elsif ($mode == 0 && $_[2]) {
	# Local file under virtualmin-backup directory
	$in{"$_[0]_file"} =~ /^\S+$/ || &error($text{'backup_edest2'});
	$in{"$_[0]_file"} =~ /\.\./ && &error($text{'backup_edest3'});
	$in{"$_[0]_file"} =~ s/\/+$//;
	return "$_[3]->{'home'}/virtualmin-backup/".$in{"$_[0]_file"};
	}
elsif ($mode == 1) {
	# FTP server
	local ($server, $port) = split(/:/, $in{"$_[0]_server"});
	gethostbyname($server) || &error($text{'backup_eserver1'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{"$_[0]_path"} =~ /^\/\S/ || &error($text{'backup_epath'});
	$in{"$_[0]_user"} =~ /^[^:\@\/]*$/ || &error($text{'backup_euser'});
	$in{"$_[0]_pass"} =~ /^[^:\@\/]*$/ || &error($text{'backup_epass'});
	$in{"$_[0]_path"} =~ s/\/+$//;
	return "ftp://".$in{"$_[0]_user"}.":".$in{"$_[0]_pass"}."\@".
	       $in{"$_[0]_server"}.$in{"$_[0]_path"};
	}
elsif ($mode == 2) {
	# SSH server
	local ($server, $port) = split(/:/, $in{"$_[0]_sserver"});
	gethostbyname($server) || &error($text{'backup_eserver2'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{"$_[0]_spath"} =~ /\S/ || &error($text{'backup_epath'});
	$in{"$_[0]_suser"} =~ /^[^:\@\/]*$/ || &error($text{'backup_euser2'});
	$in{"$_[0]_spath"} =~ s/\/+$//;
	return "ssh://".$in{"$_[0]_suser"}.":".$in{"$_[0]_spass"}."\@".
	       $in{"$_[0]_sserver"}.":".$in{"$_[0]_spath"};
	}
elsif ($mode == 3 && &can_use_s3()) {
	# Amazon S3 service
	local $cerr = &check_s3();
	$cerr && &error($cerr);
	$in{$_[0].'_bucket'} =~ /^\S+$/ || &error($text{'backup_ebucket'});
	$in{$_[0].'_akey'} =~ /^\S+$/i || &error($text{'backup_eakey'});
	$in{$_[0].'_skey'} =~ /^\S+$/i || &error($text{'backup_eskey'});
	$in{"$_[0]_s3file_def"} ||
		$in{"$_[0]_s3file"} =~ /^[a-z0-9\-\_\.]+$/i ||
		&error($text{'backup_euser'});
	return "s3://".$in{$_[0].'_akey'}.":".$in{$_[0].'_skey'}."\@".
	       $in{$_[0].'_bucket'}.
	       ($in{"$_[0]_s3file_def"} ? "" : "/".$in{"$_[0]_s3file"});
	}
elsif ($mode == 4) {
	# Just download
	return "download:";
	}
else {
	&error($text{'backup_emode'});
	}
}

# ftp_upload(host, file, srcfile, [&error], [&callback], [user, pass], [port])
# Download data from a local file to an FTP site
sub ftp_upload
{
local($buf, @n);
local $cbfunc = $_[4];

$download_timed_out = undef;
local $SIG{ALRM} = "download_timeout";
alarm(60);

# connect to host and login
&open_socket($_[0], $_[7] || 21, "SOCK", $_[3]) || return 0;
alarm(0);
if ($download_timed_out) {
	if ($_[3]) { ${$_[3]} = $download_timed_out; return 0; }
	else { &error($download_timed_out); }
	}
&ftp_command("", 2, $_[3]) || return 0;
if ($_[5]) {
	# Login as supplied user
	local @urv = &ftp_command("USER $_[5]", [ 2, 3 ], $_[3]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS $_[6]", 2, $_[3]) || return 0;
		}
	}
else {
	# Login as anonymous
	local @urv = &ftp_command("USER anonymous", [ 2, 3 ], $_[3]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS root\@".&get_system_hostname(), 2,
			     $_[3]) || return 0;
		}
	}
&$cbfunc(1, 0) if ($cbfunc);

# Switch to binary mode
&ftp_command("TYPE I", 2, $_[3]) || return 0;

# get the file size and tell the callback
local @st = stat($_[2]);
if ($cbfunc) {
	&$cbfunc(2, $st[7]);
	}

# send the file
local $pasv = &ftp_command("PASV", 2, $_[3]);
defined($pasv) || return 0;
$pasv =~ /\(([0-9,]+)\)/;
@n = split(/,/ , $1);
&open_socket("$n[0].$n[1].$n[2].$n[3]", $n[4]*256 + $n[5], "CON", $_[3]) || return 0;
&ftp_command("STOR $_[1]", 1, $_[3]) || return 0;

# transfer data
local $got;
open(PFILE, $_[2]);
while(read(PFILE, $buf, 1024) > 0) {
	print CON $buf;
	$got += length($buf);
	&$cbfunc(3, $got) if ($cbfunc);
	}
close(PFILE);
close(CON);
if ($got != $st[7]) {
	if ($_[3]) { ${$_[3]} = "Upload incomplete"; return 0; }
	else { &error("Upload incomplete"); }
	}
&$cbfunc(4) if ($cbfunc);

# finish off..
&ftp_command("", 2, $_[3]) || return 0;
&ftp_command("QUIT", 2, $_[3]) || return 0;
close(SOCK);

return 1;
}

# ftp_onecommand(host, command, [&error], [user, pass], [port])
# Executes one command on an FTP server, after logging in, and returns its
# exit status.
sub ftp_onecommand
{
local($buf, @n);

$download_timed_out = undef;
local $SIG{ALRM} = "download_timeout";
alarm(60);

# connect to host and login
&open_socket($_[0], $_[5] || 21, "SOCK", $_[2]) || return 0;
alarm(0);
if ($download_timed_out) {
	if ($_[2]) { ${$_[2]} = $download_timed_out; return 0; }
	else { &error($download_timed_out); }
	}
&ftp_command("", 2, $_[2]) || return 0;
if ($_[3]) {
	# Login as supplied user
	local @urv = &ftp_command("USER $_[3]", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS $_[4]", 2, $_[2]) || return 0;
		}
	}
else {
	# Login as anonymous
	local @urv = &ftp_command("USER anonymous", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS root\@".&get_system_hostname(), 2,
			     $_[2]) || return 0;
		}
	}

# make the directory
local @rv = &ftp_command($_[1], 2, $_[2]);
@rv || return 0;

# finish off..
&ftp_command("QUIT", 2, $_[3]) || return 0;
close(SOCK);

return $rv[1];
}

# ftp_listdir(host, dir, [&error], [user, pass], [port])
# Returns a reference to a list of filenames in a directory
sub ftp_listdir
{
local($buf, @n);

$download_timed_out = undef;
local $SIG{ALRM} = "download_timeout";
alarm(60);

# connect to host and login
&open_socket($_[0], $_[5] || 21, "SOCK", $_[2]) || return 0;
alarm(0);
if ($download_timed_out) {
	if ($_[2]) { ${$_[2]} = $download_timed_out; return 0; }
	else { &error($download_timed_out); }
	}
&ftp_command("", 2, $_[2]) || return 0;
if ($_[3]) {
	# Login as supplied user
	local @urv = &ftp_command("USER $_[3]", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS $_[4]", 2, $_[2]) || return 0;
		}
	}
else {
	# Login as anonymous
	local @urv = &ftp_command("USER anonymous", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS root\@".&get_system_hostname(), 2,
			     $_[2]) || return 0;
		}
	}

# request the listing
local $pasv = &ftp_command("PASV", 2, $_[2]);
defined($pasv) || return 0;
$pasv =~ /\(([0-9,]+)\)/;
@n = split(/,/ , $1);
&open_socket("$n[0].$n[1].$n[2].$n[3]", $n[4]*256 + $n[5], "CON", $_[2]) || return 0;
&ftp_command("NLST $_[1]", 1, $_[2]) || return 0;

# transfer listing
local @list;
local $_;
while(<CON>) {
	s/\r|\n//g;
	push(@list, $_);
	}
close(CON);

# finish off..
&ftp_command("", 2, $_[3]) || return 0;
&ftp_command("QUIT", 2, $_[3]) || return 0;
close(SOCK);

return \@list;
}

# scp_copy(source, dest, password, &error, port)
# Copies a file from some source to a destination. One or the other can be
# a server, like user@foo:/path/to/bar/
sub scp_copy
{
&foreign_require("proc", "proc-lib.pl");
local $cmd = "scp -r ".($_[4] ? "-P $_[4] " : "").$_[0]." ".$_[1];
local ($fh, $fpid) = &proc::pty_process_exec($cmd);
local $out;
while(1) {
	local $rv = &wait_for($fh, "password:", "yes\\/no", ".*\n");
	$out .= $wait_for_input;
	if ($rv == 0) {
		syswrite($fh, "$_[2]\n");
		}
	elsif ($rv == 1) {
		syswrite($fh, "yes\n");
		}
	elsif ($rv < 0) {
		last;
		}
	}
close($fh);
local $got = waitpid($fpid, 0);
if ($? || $out =~ /permission\s+denied/i || $out =~ /connection\s+refused/i) {
	${$_[3]} = "scp failed : <pre>$out</pre>";
	}
}

# free_ip_address(&template|&acl)
# Returns an IP address within the allocation range which is not currently used
sub free_ip_address
{
local ($tmpl) = @_;
&foreign_require("net", "net-lib.pl");
local %taken = map { $_->{'address'}, $_ } (&net::boot_interfaces(),
					    &net::active_interfaces());
local @ranges = split(/\s+/, $tmpl->{'ranges'});
local $r;
foreach $r (@ranges) {
	$r =~ /^(\d+\.\d+\.\d+)\.(\d+)\-(\d+)$/ || next;
	local ($base, $s, $e) = ($1, $2, $3);
	local $j;
	for($j=$s; $j<=$e; $j++) {
		local $try = "$base.$j";
		return $try if (!$taken{$try});
		}
	}
return undef;
}

# parse_ip_ranges(ranges)
# Returns a list of all IP allocation ranges, each of which is a 2-element array
sub parse_ip_ranges
{
local @rv;
local @ranges = split(/\s+/, $_[0]);
local $r;
foreach $r (@ranges) {
	$r =~ /^(\d+\.\d+\.\d+)\.(\d+)\-(\d+)$/ || next;
	push(@rv, [ "$1.$2", "$1.$3" ]);
	}
return @rv;
}

# join_ip_ranges(&ranges)
# Converts a list of ranges into a string
sub join_ip_ranges
{
local @ranges;
local $r;
foreach $r (@{$_[0]}) {
	local @start = split(/\./, $r->[0]);
	local @end = split(/\./, $r->[1]);
	push(@ranges, join(".", @start)."-".$end[3]);
	}
return join(" ", @ranges);
}

# setup_for_subdomain(&parent-domain, subdomain-user, &sub-domain)
# Ensures that this virtual server can host sub-servers
sub setup_for_subdomain
{
&system_logged("mkdir '$_[0]->{'home'}/domains' 2>/dev/null");
&system_logged("chmod 755 '$_[0]->{'home'}/domains'");
local $gid = $_[0]->{'gid'} || $_[0]->{'ugid'};
&system_logged("chown $_[0]->{'uid'}:$gid '$_[0]->{'home'}/domains'");
}

# count_domains([type])
# Returns the number of additional domains the current user is allowed to
# create (-1 for infinite), the reason for the limit (2=this reseller,
# 1=reseller, 0=user), the number of domains allowed in total, and a flag
# indicating if this limit should be hidden from the user.
# May exclude alias domains if they don't count towards the max.
sub count_domains
{
local ($type) = @_;
$type ||= "doms";
local ($left, $reason, $max, $hide) = &count_feature($type);
if ($left != 0) {
	# If no limit has been hit, check the licence
	local ($lstatus, $lexpiry, $lerr, $ldoms) = &check_licence_expired();
	if ($ldoms) {
		local @doms = grep { !$_->{'alias'} } &list_domains();
		if (@doms > $ldoms) {
			# Hit the licenced max!
			return (0, 3, $ldoms, 0);
			}
		else {
			# Haven't reached .. check if the licence limit is
			# less than the current limit
			local $dleft = $ldoms - @doms;
			if ($left == -1 || $dleft < $left) {
				# Will hit domains limit
				return ($dleft, 3, $ldoms, 0);
				}
			else {
				# Will hit user or reseller limit
				return ($left, $reason, $max, $hide);
				}
			}
		}
	}
return ($left, $reason, $max, $hide);
}

# count_mailboxes(&parent)
# Returns the number of mailboxes in this domain and all subdomains, and the
# max allowed for the current user
sub count_mailboxes
{
local $count = 0;
local $doms = 0;
local $parent = $_[0]->{'parent'} ? &get_domain($_[0]->{'parent'}) : $_[0];
local $d;
foreach $d ($parent, &get_domain_by("parent", $parent->{'id'})) {
	local @users = &list_domain_users($d, 0, 1, 1, 1);
	$count += @users;
	$doms++;
	}
return ( $count, $parent->{'mailboxlimit'} ? $parent->{'mailboxlimit'} : 0,
	 $doms );
}

# count_feature(feature, [user])
# Returns the number of extra instances of the given feature that the current
# user is allowed to create, the reason for the limit (2=this reseller,
# 1=reseller, 0=user), the total allowed, and a flag indicating if this
# limit should be hidden from the user.
# Feature can be "doms", "aliasdoms", "realdoms", "mailboxes", "aliases",
# "quota", "uquota", "dbs", "bw" or a feature
sub count_feature
{
local ($f) = @_;
local $user = $_[1] || $base_remote_user;
local %access = &get_module_acl($user);

# Master admin has no limit
return (-1, 0) if (&master_admin());

local $userleft = -1;
local $usermax;
if (!$access{'reseller'}) {
	# Count the number that this user has
	local @doms = &get_domain_by("user", $user);
	local ($parent) = grep { !$_->{'parent'} } @doms;
	local $limit = $f eq "doms" ? $parent->{'domslimit'} :
		       $f eq "aliasdoms" ? $parent->{'aliasdomslimit'} :
		       $f eq "realdoms" ? $parent->{'realdomslimit'} :
		       $f eq "mailboxes" ? $parent->{'mailboxlimit'} :
		       $f eq "aliases" ? $parent->{'aliaslimit'} :
		       $f eq "dbs" ? $parent->{'dbslimit'} : undef;
	$limit = undef if ($limit eq "*");
	if ($limit ne "") {
		# A server-owner-level limit is in force .. check it
		local $got = &count_domain_feature($f, @doms);
		if ($got >= $limit) {
			return (0, 0, $limit);
			}
		$userleft = $limit - $got;
		$usermax = $limit;
		}
	if (($f eq "aliasdoms" || $f eq "realdoms") &&
	    $parent->{'domslimit'} && $parent->{'domslimit'} ne '*') {
		# See if the owner is over the limit for all domains types too
		local $got = &count_domain_feature("doms", @doms);
		if ($got >= $parent->{'domslimit'}) {
			return (0, 0, $parent->{'domslimit'});
			}
		else {
			$userleft = $parent->{'domslimit'} - $got;
			$usermax = $parent->{'domslimit'};
			}
		}
	$reseller = $parent->{'reseller'};
	}
else {
	$reseller = $user;
	}

if ($reseller) {
	# Either this user is owned by a reseller, or he is a reseller.
	local @rdoms = &get_domain_by("reseller", $reseller);
	local %racl = &get_reseller_acl($reseller);
	local $reason = $access{'reseller'} ? 2 : 1;
	local $hide = $base_remote_user ne $reseller && $racl{'hide'};
	local $limit = $racl{"max_".$f};
	if ($limit ne "") {
		# Reseller has a limit ..
		local $got = &count_domain_feature($f, @rdoms);
		if ($got > $limit) {
			# Reseller has reached his limit
			return (0, $reason, $limit, $hide);
			}
		else {
			# Check if reseller limit is less than the user limit
			local $reselleft = $limit - $got;
			if ($userleft == -1 || $reselleft < $userleft) {
				# Yes .. reseller limit applies
				return ($reselleft, $reason, $limit, $hide);
				}
			}
		}
	if (($f eq "aliasdoms" || $f eq "realdoms") &&
	    $racl{'max_doms'}) {
		# See if the reseller is over the limit for all domains types
		local $got = &count_domain_feature("doms", @rdoms);
		if ($got >= $racl{'max_doms'}) {
			return (0, $reason, $racl{'max_doms'}, $hide);
			}
		}
	}
return ($userleft, 0, $usermax);
}

# count_domain_feature(feature, &domain, ...)
# Returns the total for some feature in the given domains. May return -1 if
# any are set to unlimited (ie. quotas)
sub count_domain_feature
{
local ($f, @doms) = @_;
local $rv = 0;
local $d;
foreach $d (@doms) {
	if ($f eq "dbs") {
		local @dbs = &domain_databases($d);
		$rv += scalar(@dbs);
		}
	elsif ($f eq "mailboxes") {
		local @users = &list_domain_users($d, 0, 1, 1, 1);
		$rv += scalar(@users);
		}
	elsif ($f eq "aliases") {
		local @aliases = &list_domain_aliases($d, 1);
		$rv += scalar(@aliases);
		}
	elsif ($f eq "quota" || $f eq "uquota") {
		return -1 if ($d->{$f} eq "");
		$rv += $d->{$f};
		}
	elsif ($f eq "bw") {
		return -1 if ($d->{'bw_limit'} eq "");
		$rv += $d->{'bw_limit'};
		}
	elsif ($f eq "doms") {
		$rv++ if (!$d->{'alias'} || !$config{'limitnoalias'});
		}
	elsif ($f eq "aliasdoms") {
		$rv++ if ($d->{'alias'});
		}
	elsif ($f eq "realdoms") {
		$rv++ if (!$d->{'alias'});
		}
	else {
		$rv++ if ($d->{$f});
		}
	}
return $rv;
}

# database_name(&domain)
# Returns a suitable database name for a domain
sub database_name
{
local $tmpl = &get_template($_[0]->{'template'});
local $db = &substitute_domain_template($tmpl->{'mysql'}, $_[0]);
$db = lc($db);
$db ||= $_[0]->{'prefix'};
$db = &fix_database_name($db);
return $db;
}

# fix_database_name(dbname)
# If a database name starts with a number, convert it to a word to support
# PostgreSQL, which doesn't like numeric names. Also converts . and - to _,
# and handles reserved DB names.
sub fix_database_name
{
local ($db) = @_;
$db =~ s/[\.\-]/_/g;	# mysql doesn't like . or _
$db =~ s/^0/zero/g;	# postgresql doesn't like leading numbers
$db =~ s/^1/one/g;
$db =~ s/^2/two/g;
$db =~ s/^3/three/g;
$db =~ s/^4/four/g;
$db =~ s/^5/five/g;
$db =~ s/^6/six/g;
$db =~ s/^7/seven/g;
$db =~ s/^8/eight/g;
$db =~ s/^9/nine/g;
if ($db eq "test" || $db eq "mysql" || $db =~ /^template/) {
	# These names are reserved by MySQL and PostgreSQL
	$db = "db".$db;
	}
return $db;
}

# unixuser_name(domainname)
# Returns a Unix username for some domain, or undef if none can be found
sub unixuser_name
{
$_[0] =~ /^([^\.]+)/;
local ($try1, $user) = ($1, $1);
if (defined(getpwnam($try1)) || $config{'longname'}) {
	$user = $_[0];
	$try2 = $user;
	if (defined(getpwnam($try))) {
		return (undef, $try1, $try2);
		}
	}
return ($user);
}

# unixgroup_name(domainname)
# Returns a Unix group name for some domain, or undef if none can be found
sub unixgroup_name
{
$_[0] =~ /^([^\.]+)/;
local ($try1, $group) = ($1, $1);
if (defined(getgrnam($try1)) || $config{'longname'}) {
	$group = $_[0];
	$try2 = $group;
	if (defined(getpwnam($try))) {
		return (undef, $try1, $try2);
		}
	}
return ($group);
}

# virtual_server_clashes(&dom, [&features-to-check], [field-to-check])
# Returns a clash error message if any were found for some new domain
sub virtual_server_clashes
{
local ($dom, $check, $field) = @_;
my $f;
foreach $f (@features) {
	next if ($dom->{'parent'} && $f eq "webmin");
	next if ($dom->{'parent'} && $f eq "unix");
	if ($dom->{$f} && (!$check || $check->{$f})) {
		local $cfunc = "check_${f}_clash";
		if (&$cfunc($dom, $field)) {
			return &text('setup_e'.$f, $dom->{'dom'}, $dom->{'db'},
				     $dom->{'user'}, $dom->{'group'});
			}
		}
	}
foreach $f (@feature_plugins) {
	if ($dom->{$f} && (!$check || $check->{$f})) {
		local $cerr = &plugin_call($f, "feature_clash", $dom, $field);
		return $cerr if ($cerr);
		}
	}
return undef;
}

# virtual_server_depends(&dom, [feature])
# Returns an error message if any of the features in the domain depend on
# missing features
sub virtual_server_depends
{
local ($d, $feat) = @_;
local $f;

# Check features that are enabled
foreach $f (grep { $d->{$_} } @features) {
	next if ($feat && $f ne $feat);
	local $dfunc = "check_depends_$f";
	if (defined(&$dfunc)) {
		# Call dependecy function
		local $derr = &$dfunc($d);
		return $derr if ($derr);
		}
	# Check fixed dependency list
	local $fd;
	foreach $fd (@{$feature_depends{$f}}) {
		return &text('setup_edep'.$f) if (!$d->{$fd});
		}
	}

# Check plugins that are enabled
foreach $f (grep { $d->{$_} } @feature_plugins) {
	next if ($feat && $f ne $feat);
	local $derr = &plugin_call($f, "feature_depends", $d);
	return $derr if ($derr);
	}

# Check features that are NOT enabled, to ensure that any needed features are
# not missing. ie. mysql missing from parent but on children
foreach $f (grep { !$d->{$_} } @features) {
	next if ($feat && $f ne $feat);
	local $dfunc = "check_anti_depends_$f";
	if (defined(&$dfunc)) {
		# Call dependecy function
		local $derr = &$dfunc($d);
		return $derr if ($derr);
		}
	}

return undef;
}

# virtual_server_limits(&domain, [&old-domain])
# Checks if the addition of a feature would exceed any limit for the user
sub virtual_server_limits
{
local ($d, $oldd) = @_;
local ($left, $reason, $max);

# Check database limit
local $newdbs = 0;
$newdbs++ if ($d->{'mysql'} && (!$oldd || !$oldd->{'mysql'}));
$newdbs++ if ($d->{'postgres'} && (!$oldd || !$oldd->{'postgres'}));
if ($newdbs) {
	($left, $reason, $max) = &count_feature("dbs");
	if ($left == 0 || $newdbs == 2 && $left == 1) {
		return &text('databases_noadd'.$reason, $max);
		}
	}

# Check quota limits
($left, $reason, $max) = &count_feature("quota");
if (!$d->{'parent'} && $d->{'quota'} eq "" && $left != -1) {
	# Unlimited quota chosen, but not allowed!
	return &text('setup_noquotainf'.$reason, &quota_show($max, "home"));
	}
local $newquota = $d->{'quota'} - ($oldd ? $oldd->{'quota'} : 0);
if ($left != -1 && $left-$newquota < 0) {
	return &text('setup_noquotaadd'.$reason,
		     &quota_show($left+($oldd ? $oldd->{'quota'} : 0), "home"));
	}

# Check bandwidth limits
($left, $reason, $max) = &count_feature("bw");
if (!$d->{'parent'} && $d->{'bw_limit'} eq "" && $left != -1) {
	# Unlimited bandwidth chosen, but not allowed!
	return &text('setup_nobwinf'.$reason, &nice_size($max));
	}
local $newquota = $d->{'bw_limit'} - ($oldd ? $oldd->{'bw_limit'} : 0);
if ($left != -1 && $left-$newquota < 0) {
	return &text('setup_nobwadd'.$reason,
		     &nice_size($left+($oldd ? $oldd->{'bw_limit'} : 0)));
	}

# Check domains limit
if (!$oldd) {
	($left, $reason, $max) = &count_domains();
	if ($left == 0) {
		return &text('index_noadd'.$reason, $max);
		}
	}

return undef;
}

# create_virtual_server(&domain, [&parent-domain], [parent-user], [no-scripts])
# Given a complete domain object, setup all it's features
sub create_virtual_server
{
local ($dom, $parentdom, $parentuser, $noscripts) = @_;

# Run the before command
&set_domain_envs($dom, "CREATE_DOMAIN");
local $merr = &making_changes();
&reset_domain_envs($dom);
return &text('setup_emaking', "<tt>$merr</tt>") if (defined($merr));

# Get ready for hosting a subdomain
if ($dom->{'parent'}) {
	&setup_for_subdomain($parentdom, $parentuser, $dom);
	}

# Work out if this server is being created on the primary default IP address
if ($dom->{'ip'} eq &get_default_ip() &&
    !$dom->{'virt'}) {
	$dom->{'defip'} = 1;
	}

# Set up all the selected features (except Webmin login)
my $f;
local %vital = map { $_, 1 } @vital_features;
local @dof = grep { $_ ne "webmin" } @features;
foreach $f (@dof) {
	if ($dom->{$f}) {
		local $sfunc = "setup_$f";
		if ($vital{$f}) {
			# Failure of this feature should halt the entire setup
			&$sfunc($dom);
			}
		else {
			# Failure can be ignored
			if (!&try_function($f, $sfunc, $dom)) {
				$dom->{$f} = 0;
				}
			}
		}
	}

# Set up all the selected plugins
foreach $f (@feature_plugins) {
	if ($dom->{$f}) {
		# Failure can be ignored
		local $main::error_must_die = 1;
		eval { &plugin_call($f, "feature_setup", $dom) };
		if ($@) {
			&$second_print(&text('setup_failure',
				&plugin_call($f, "feature_name"), $@));
			$dom->{$f} = 0;
			}
		}
	}

# Setup Webmin login last, once all plugins are done
if ($dom->{'webmin'}) {
	local $sfunc = "setup_webmin";
	if (!&try_function($f, $sfunc, $dom)) {
		$dom->{$f} = 0;
		}
	}

&run_post_actions();

# Add virtual IP address, if needed
if ($dom->{'virt'}) {
	&setup_virt($dom);
	}

# Add a virtuser for the unix user, if requested
if ($in{'mailbox'}) {
	&$first_print($text{'setup_mailbox'});
	local $virt = { 'from' => $user."\@".$dom->{'dom'},
			'to' => [ $user ] };
	&create_virtuser($virt);
	&$second_print($text{'setup_done'});
	}

# Save domain details
&$first_print($text{'setup_save'});
&save_domain($dom);
&$second_print($text{'setup_done'});

if (!$dom->{'nocreationmail'}) {
	# Notify the owner via email
	&send_domain_email($dom);
	}

# Update the parent domain Webmin user
if ($parentdom) {
	&refresh_webmin_user($parentdom);
	}

if ($remote_user) {
	# Add to this user's list of domains if needed
	local %access = &get_module_acl();
	if (!&can_edit_domain($dom)) {
		$access{'domains'} = join(" ", split(/\s+/, $access{'domains'}),
					       $dom->{'id'});
		&save_module_acl(\%access);
		}
	}

# Create an automatic alias domain, if specified in template
local $tmpl = &get_template($dom->{'template'});
if ($tmpl->{'domalias'} ne 'none' && !$_[0]->{'alias'}) {
	local $aliasname = $_[0]->{'dom'};
	if ($tmpl->{'domalias_type'} == 1) {
		$aliasname =~ s/\..*$//;
		}
	$aliasname .= ".".$tmpl->{'domalias'};
	&$first_print(&text('setup_domalias', $aliasname));
	&$indent_print();
	local %alias = ( 'id', &domain_id(),
			 'dom', $aliasname,
			 'user', $dom->{'user'},
			 'group', $dom->{'group'},
			 'prefix', $dom->{'prefix'},
			 'ugroup', $dom->{'ugroup'},
			 'pass', $dom->{'pass'},
			 'alias', $dom->{'id'},
			 'uid', $dom->{'uid'},
			 'gid', $dom->{'gid'},
			 'ugid', $dom->{'ugid'},
			 'owner', "Automatic alias of $dom->{'dom'}",
			 'email', $dom->{'email'},
			 'nocreationmail', 1,
			 'name', 1,
			 'ip', $dom->{'ip'},
			 'virt', 0,
			 'source', $dom->{'source'},
			 'parent', $dom->{'id'},
			 'template', $dom->{'template'},
			 'reseller', $dom->{'reseller'},
			);
	foreach my $f (@alias_features) {
		$alias{$f} = $dom->{$f};
		}
	local $parentdom = $dom->{'parent'} ? &get_domain($dom->{'parent'})
					    : $dom;
	$alias{'home'} = &server_home_directory(\%alias, $parentdom);
	&complete_domain(\%alias);
	&create_virtual_server(\%alias, $parentdom, $parentdom->{'user'});
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

# Install any scripts specified in the template
local @scripts = &get_template_scripts($tmpl);
if (@scripts && !$dom->{'alias'} && !$noscripts &&
    $dom->{'web'} && $dom->{'dir'} && !$dom->{'nocreationscripts'}) {
	&$first_print($text{'setup_scripts'});
	&$indent_print();
	foreach my $sinfo (@scripts) {
		# Work out install options
		local ($name, $ver) = split(/\s+/, $sinfo->{'name'});
		local $script = &get_script($name);
		if (!$script) {
			&$first_print(&text('setup_scriptgone', $name));
			next;
			}
		&$first_print(&text('setup_scriptinstall',
				    $script->{'name'}, $ver));
		local $opts = { 'path' => $sinfo->{'path'} };
		local $perr = &validate_script_path($opts, $script, $dom);
		if ($perr) {
			&$second_print($perr);
			next;
			}

		# Check dependencies
		local $derr = &{$script->{'depends_func'}}($dom, $ver);
		if ($derr) {
			&$second_print(&text('setup_scriptdeps', $derr));
			next;
			}

		# Check for needed commands
		local @missing = &check_script_required_commands($d, $script,
								 $ver, $opts);
		if (@missing) {
			&$second_print(&text('setup_scriptcommands',
				    join(' ', @missing)));
			next;
			}

		# Check PHP version
		local $phpvfunc = $script->{'php_vers_func'};
		local $phpver;
		if (defined(&$phpvfunc)) {
			local @vers = &$phpvfunc($dom, $ver);
			$phpver = &setup_php_version($dom, \@vers,
						     $opts->{'path'});
			if (!$phpver) {
				&$second_print(&text('setup_scriptphpver',
						     join(" ", @vers)));
				next;
				}
			}

		# Install needed PHP modules
		local $modok = &setup_php_modules($dom, $script, $ver, $phpver,
						  $opts);
		next if (!$modok);
		$modok = &setup_pear_modules($dom, $script, $ver, $phpver,
					     $opts);
		next if (!$modok);
		$modok = &setup_perl_modules($d, $script, $ver, $opts);
		next if (!$modok);
		$modok = &setup_ruby_modules($d, $script, $ver, $opts);
		next if (!$modok);

		# Find the database, if requested
		if ($sinfo->{'db'}) {
			local $dbname = &substitute_domain_template(
						$sinfo->{'db'}, $dom);
			if (!$dom->{$sinfo->{'dbtype'}}) {
				# DB type isn't enabled for this domain
				&$second_print(&text('setup_scriptnodb',
				   $text{'databases_'.$sinfo->{'dbtype'}}));
				next;
				}
			$opts->{'db'} = $sinfo->{'dbtype'}."_".$dbname;
			local @dbs = &domain_databases($dom);
			local ($db) = grep {
				$_->{'type'} eq $sinfo->{'dbtype'} &&
				$_->{'name'} eq $dbname } @dbs;
			if (!$db) {
				# DB doesn't exist yet .. create it
				$cfunc = "check_".$sinfo->{'dbtype'}.
					 "_database_clash";
				if (&$cfunc($dom, $dbname)) {
					&$second_print(
					  &text('setup_scriptclash', $dbname));
					next;
					}
				$crfunc = "create_".$sinfo->{'dbtype'}.
					  "_database";
				&$indent_print();
				&$crfunc($dom, $dbname);
				&$outdent_print();
				}
			}

		# Check options
		if (defined(&{$script->{'check_func'}})) {
			my $oerr = &{$script->{'check_func'}}($dom, $ver,$opts);
			if ($oerr) {
				&$second_print(&text('setup_scriptopts',$oerr));
				next;
				}
			}

		# Fetch needed files
		local %gotfiles;
		local $ferr = &fetch_script_files($dom, $ver, $opts, undef, \%gotfiles, 1);
		if ($derr) {
			&$second_print(&text('setup_scriptfetch', $ferr));
			next;
			}

		# Call the install function
		local ($ok, $msg, $desc, $url, $suser, $spass) =
			&{$script->{'install_func'}}($dom, $ver, $opts, \%gotfiles, undef);

		if ($ok) {
			&$second_print(&text('setup_scriptdone', $msg));

			# Record script install in domain
			&add_domain_script($dom, $name, $ver, $opts,
					   $desc, $url, $suser, $spass);

			# Config web server for PHP
			if (&indexof("php", @{$script->{'uses'}}) >= 0) {
				if (&setup_web_for_php($dom, $script, $phpver)){
					&$first_print($text{'scripts_apache'});
					&$second_print($text{'setup_done'});
					&register_post_action(\&restart_apache);
					}
				}
			}
		else {
			&$second_print(&text('setup_scriptfailed', $msg));
			}
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	&save_domain($dom);
	}

# Run the after creation command
&run_post_actions();
&made_changes();

return undef;
}

# delete_virtual_server(&domain, only-disconnect)
# Deletes a Virtualmin domain and all sub-domains and aliases. Returns undef
# on succes, or an error message on failure.
sub delete_virtual_server
{
local ($d, $only) = @_;

# Get domain details
local @subs = &get_domain_by("parent", $d->{'id'});
local @aliasdoms = &get_domain_by("alias", $d->{'id'});
local @aliasdoms = grep { $_->{'parent'} != $d->{'id'} } @aliasdoms;

# Go ahead and delete this domain and all sub-domains ..
foreach my $dd (@aliasdoms, @subs, $d) {
	if ($dd ne $d) {
		# Show domain name
		&$first_print(&text('delete_dom', $dd->{'dom'}));
		&$indent_print();
		}

	# Run the before command
	&set_domain_envs($dd, "DELETE_DOMAIN");
	local $merr = &making_changes();
	&reset_domain_envs($d);
	return &text('delete_emaking', "<tt>$merr</tt>")
		if (defined($merr));

	if (!$only) {
		local @users = $dd->{'alias'} ? ( )
					      : &list_domain_users($dd, 1);
		local @aliases = &list_domain_aliases($dd);

		# Stop any processes belonging to installed scripts, such
		# as Ruby on Rails mongrels
		local $done_stopscripts;
		if (!$dd->{'alias'} && defined(&list_domain_scripts)) {
			foreach my $sinfo (&list_domain_scripts($dd)) {
				local $script = &get_script($sinfo->{'name'});
				local $sfunc = $script->{'stop_func'};
				if (defined(&$sfunc)) {
					&$first_print(
					    $text{'delete_stopscripts'})
						if (!$done_stopscripts++);
					&$sfunc($dd, $sinfo);
					}
				}
			}
		if ($done_stopscripts) {
			&$second_print($text{'setup_done'});
			}

		if (@users) {
			# Delete mail users and their mail files
			&$first_print($text{'delete_users'});
			foreach my $u (@users) {
				&delete_user($u, $dd);
				if (!$u->{'nomailfile'}) {
					&delete_mail_file($u);
					}
				if (!$u->{'nocreatehome'}) {
					&delete_user_home($u, $d);
					}
				}
			&$second_print($text{'setup_done'});
			}

                # Delete all virtusers
                &$first_print($text{'delete_aliases'});
                foreach my $v (&list_virtusers()) {
                        if ($v->{'from'} =~ /\@(\S+)$/ &&
                            $1 eq $dd->{'dom'}) {
                                &delete_virtuser($v);
                                }
                        }
                &$second_print($text{'setup_done'});

		# Take down IP
		if ($dd->{'iface'}) {
			&delete_virt($dd);
			}
		}

	if (!$dd->{'parent'} && $virtualmin_pro) {
		# Delete any extra admins
		foreach my $admin (&list_extra_admins($dd)) {
			&delete_extra_admin($admin);
			}
		}

	# Delete all features (or just 'webmin' if un-importing). Any
	# failures are ignored!
	my $f;
	$dd->{'deleting'} = 1;		# so that features know about delete
	if (!$only) {
		# Delete all plugins
		foreach $f (@feature_plugins) {
			if ($dd->{$f}) {
				local $main::error_must_die = 1;
				eval { &plugin_call($f,
					"feature_delete",$dd) };
				if ($@) {
					&$second_print(
					    &text('delete_failure',
					    &plugin_call($f,
						"feature_name"), $@));
					}
				}
			}
		}
	foreach $f ($only ? ( "webmin" ) : reverse(@features)) {
		if ($config{$f} && $dd->{$f} || $f eq 'unix') {
			local $dfunc = "delete_$f";
			if (!&try_function($f, $dfunc, $dd)) {
				$dd->{$f} = 1;
				}
			}
		}

	# Delete domain file
	&$first_print(&text('delete_domain', $dd->{'dom'}));
	&delete_domain($dd);
	&$second_print($text{'setup_done'});

	# Update the parent domain Webmin user, so that his ACL
	# is refreshed
	if ($dd->{'parent'} && $dd->{'parent'} != $d->{'id'}) {
		local $parentdom = &get_domain($d->{'parent'});
		&refresh_webmin_user($parentdom);
		}

	if ($dd ne $d) {
		&$outdent_print();
		&$second_print($text{'setup_done'});
		}
	}

# Run the after creation command
&run_post_actions();
&made_changes();

return undef;
}

# register_post_action(&function, args)
sub register_post_action
{
push(@main::post_actions, [ @_ ]);
}

# run_post_actions()
# Run all registered post-modification actions
sub run_post_actions
{
local $a;

# Check if we are restarting Apache, and if so don't reload it
local $restarting;
foreach $a (@main::post_actions) {
	if ($a->[0] eq \&restart_apache && $a->[1] == 1) {
		$restarting = 1;
		}
	}
if ($restarting) {
	@main::post_actions = grep { $_->[0] ne \&restart_apache ||
				     $_->[1] != 0 } @main::post_actions;
	}

# Run unique actions
local %done;
foreach $a (@main::post_actions) {
	next if ($done{join(",", @$a)}++);
	local ($afunc, @aargs) = @$a;
	local $main::error_must_die = 1;
	eval { &$afunc(@aargs) };
	if ($@) {
		&$second_print(&text('setup_postfailure', $@));
		}
	}
@main::post_actions = ( );
}

# find_bandwidth_job()
# Returns the cron job used for bandwidth monitoring
sub find_bandwidth_job
{
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $bw_cron_cmd } @jobs;
return $job;
}

# get_bandwidth(&domain)
# Returns the bandwidth usage object for some domain
sub get_bandwidth
{
if (!defined($get_bandwidth_cache{$_[0]->{'id'}})) {
	local %bwinfo;
	&read_file("$bandwidth_dir/$_[0]->{'id'}", \%bwinfo);
	local $k;
	foreach $k (keys %bwinfo) {
		if ($k =~ /^\d+$/) {
			# Convert old web entries
			$bwinfo{"web_$k"} = $bwinfo{$k};
			delete($bwinfo{$k});
			}
		}
	$get_bandwidth_cache{$_[0]->{'id'}} = \%bwinfo;
	}
return $get_bandwidth_cache{$_[0]->{'id'}};
}

# save_bandwidth(&domain, &info)
sub save_bandwidth
{
&make_dir($bandwidth_dir, 0700);
&write_file("$bandwidth_dir/$_[0]->{'id'}", $_[1]);
$get_bandwidth_cache{$_[0]->{'id'}} ||= $_[1];
}

# bandwidth_input(name, value, [no-unlimited], [dont-change])
# Returns HTML for a bandwidth input field, with an 'unlimited' option
sub bandwidth_input
{
local ($name, $value, $nounlimited, $dontchange) = @_;
local $rv;
local $dis1 = &js_disable_inputs([ $name, $name."_units" ], [ ]);
local $dis2 = &js_disable_inputs([ ], [ $name, $name."_units" ]);
local $dis;
if (!$nounlimited) {
	if ($dontchange) {
		# Show don't change option
		$rv .= &ui_radio($name."_def", 2,
			 [ [ 2, $text{'massdomains_leave'}, "onClick='$dis1'" ],
			   [ 1, $text{'edit_bwnone'}, "onClick='$dis1'" ],
			   [ 0, " ", "onClick='$dis2'" ] ]);
		$dis = 1;
		}
	else {
		# Show unlimited option
		$rv .= &ui_radio($name."_def", $value ? 0 : 1,
			 [ [ 1, $text{'edit_bwnone'}, "onClick='$dis1'" ],
			   [ 0, " ", "onClick='$dis2'" ] ]);
		$dis = 1 if (!$value);
		}
	}
local ($val, $u);
if ($value eq "") {
	# Default to GB, since bytes are rarely useful
	$u = "GB";
	}
elsif ($value && $value%(1024*1024*1024) == 0) {
	$val = $value/(1024*1024*1024);
	$u = "GB";
	}
elsif ($value && $value%(1024*1024) == 0) {
	$val = $value/(1024*1024);
	$u = "MB";
	}
elsif ($value && $value%(1024) == 0) {
	$val = $value/(1024);
	$u = "kB";
	}
else {
	$val = $value;
	$u = "bytes";
	}
local $sel = &ui_select($name."_units", $u,
		[ ["bytes"], ["kB"], ["MB"], ["GB"] ], 1, 0, 0, $dis);
$rv .= &text('edit_bwpast_'.$config{'bw_past'},
	     &ui_textbox($name, $val, 10, $dis)." ".$sel,
	     $config{'bw_period'});
return $rv;
}

# parse_bandwidth(name, error, [no-unlimited])
sub parse_bandwidth
{
if ($in{"$_[0]_def"} && !$_[2]) {
	return undef;
	}
else {
	$in{$_[0]} =~ /^\d+$/ && $in{$_[0]} > 0 || &error($_[1]);
	local $m = $in{"$_[0]_units"} eq "GB" ? 1024*1024*1024 :
		   $in{"$_[0]_units"} eq "MB" ? 1024*1024 :
		   $in{"$_[0]_units"} eq "kB" ? 1024 : 1;
	return $in{$_[0]} * $m;
	}
}

# email_template_input(template-file, subject, other-cc, other-bcc,
#		       [mailbox-cc, owner-cc, reseller-cc], [header],[filemode])
# Returns HTML for fields for editing an email template
sub email_template_input
{
local ($file, $subject, $cc, $bcc, $mailbox, $owner, $reseller, $header,
       $filemode) = @_;
local $rv;
$rv .= &ui_table_start($header, undef, 2);
if ($filemode eq "none" || $filemode eq "default") {
	# Show input for selecting if enabled
	$rv .= &ui_table_row($text{'newdom_sending'},
		&ui_yesno_radio("sending", $filemode eq "default" ? 1 : 0));
	}
$rv .= &ui_table_row($text{'newdom_subject'},
		     &ui_textbox("subject", $subject, 60));
if (@_ >= 5) {
	# Show inputs for selecting destination
	$rv .= &ui_table_row($text{'newdom_to'},
	     &ui_checkbox("mailbox", 1, $text{'newdom_mailbox'}, $mailbox)." ".
	     &ui_checkbox("owner", 1, $text{'newdom_owner'}, $owner)." ".
	     ($virtualmin_pro ? 
		&ui_checkbox("reseller", 1, $text{'newdom_reseller'},
			     $reseller) : ""));
	}
$rv .= &ui_table_row($text{'newdom_cc'},
		     &ui_textbox("cc", $cc, 60));
$rv .= &ui_table_row($text{'newdom_bcc'},
		     &ui_textbox("bcc", $bcc, 60));
if ($file) {
	$rv .= &ui_table_row(undef,
		&ui_textarea("template", &read_file_contents($file), 20, 70),
		2);
	}
$rv .= &ui_table_end();
return $rv;
}

# parse_email_template(file, subject-config, cc-config, bcc-config,
#		       [mailbox-config, owner-config, reseller-config],
#		       [filemode-config])
sub parse_email_template
{
local ($file, $subject_config, $cc_config, $bcc_config,
       $mailbox_config, $owner_config, $reseller_config, $filemode_config) = @_;
$in{'template'} =~ s/\r//g;
&open_lock_tempfile(FILE, ">$file", 1) ||
	&error(&text('efilewrite', $file, $!));
&print_tempfile(FILE, $in{'template'});
&close_tempfile(FILE);

&lock_file($module_config_file);
$config{$subject_config} = $in{'subject'};
$config{$cc_config} = $in{'cc'};
$config{$bcc_config} = $in{'bcc'};
if ($mailbox_config) {
	$config{$mailbox_config} = $in{'mailbox'};
	$config{$owner_config} = $in{'owner'};
	if ($virtualmin_pro) {
		$config{$reseller_config} = $in{'reseller'};
		}
	}
if ($filemode_config && defined($in{'sending'})) {
	$config{$filemode_config} = $in{'sending'} ? "default" : "none";
	}
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
&save_module_config();
&unlock_file($module_config_file);
}

# escape_user(username)
# Returns a Unix username with characters unsuitable for use in a mail
# destination (like @) escaped
sub escape_user
{
local $escuser = $_[0];
$escuser =~ s/\@/\\\@/g;
return $escuser;
}

# unescape_user(username)
# The reverse of escape_user
sub unescape_user
{
local $escuser = $_[0];
$escuser =~ s/\\\@/\@/g;
return $escuser;
}

# escape_alias(username)
# Converts a username into a suitable alias name
sub escape_alias
{
local $escuser = $_[0];
$escuser =~ s/\@/-/g;
return $escuser;
}

sub replace_atsign
{
local $rv = $_[0];
$rv =~ s/\@/-/g;
return $rv;
}

# dotqmail_file(&user)
sub dotqmail_file
{
return "$_[0]->{'home'}/.qmail";
}

# get_dotqmail(file)
sub get_dotqmail
{
$_[0] =~ /\.qmail(-(\S+))?$/;
local $alias = { 'file' => $_[0],
		 'name' => $2 };
local $_;
open(AFILE, $_[0]) || return undef;
while(<AFILE>) {
	s/\r|\n//g;
	s/#.*$//g;
	if (/\S/) {
		push(@{$alias->{'values'}}, $_);
		}
	}
close(AFILE);
return $alias;
}

# save_dotqmail(&alias, file, username|aliasname)
sub save_dotqmail
{
if (@{$_[0]->{'values'}}) {
	&open_lock_tempfile(AFILE, ">$_[1]");
	local $v;
	foreach $v (@{$_[0]->{'values'}}) {
		if ($v eq "\\$_[2]" || $v eq "\\NEWUSER") {
			# Delivery to this user means to his maildir
			&print_tempfile(AFILE, "./Maildir/\n");
			}
		else {
			&print_tempfile(AFILE, $v,"\n");
			}
		}
	&close_tempfile(AFILE);
	}
else {
	&unlink_file($_[1]);
	}
}

# list_templates()
# Returns a list of all virtual server templates, including two defaults for
# top-level and sub-servers
sub list_templates
{
local @rv;
push(@rv, { 'id' => 0,
	    'name' => 'Default Settings',
	    'standard' => 1,
	    'default' => 1,
	    'web' => $config{'apache_config'},
	    'web_suexec' => $config{'suexec'},
	    'web_writelogs' => $config{'web_writelogs'},
	    'web_user' => $config{'web_user'},
	    'web_html_dir' => $config{'html_dir'},
	    'web_html_perms' => $config{'html_perms'} || 750,
	    'web_stats_dir' => $config{'stats_dir'},
	    'web_stats_hdir' => $config{'stats_hdir'},
	    'web_stats_pass' => $config{'stats_pass'},
	    'web_stats_noedit' => $config{'stats_noedit'},
	    'web_port' => $default_web_port,
	    'web_sslport' => $default_web_sslport,
	    'web_alias' => $config{'alias_mode'},
	    'web_webmin_ssl' => $config{'webmin_ssl'},
	    'web_usermin_ssl' => $config{'usermin_ssl'},
	    'php_vars' => $config{'php_vars'} || "none",
	    'web_php_suexec' => int($config{'php_suexec'}),
	    'web_ruby_suexec' => $config{'ruby_suexec'} eq '' ? -1 :
					int($config{'ruby_suexec'}),
	    'web_phpver' => $config{'phpver'},
	    'web_php_noedit' => int($config{'php_noedit'}),
	    'web_phpchildren' => $config{'phpchildren'},
	    'webalizer' => $config{'def_webalizer'} || "none",
	    'disabled_web' => $config{'disabled_web'} || "none",
	    'disabled_url' => $config{'disabled_url'} || "none",
	    'dns' => $config{'bind_config'},
	    'dns_replace' => $config{'bind_replace'},
	    'dns_view' => $config{'dns_view'},
	    'dns_spf' => $config{'bind_spf'} || "none",
	    'dns_spfhosts' => $config{'bind_spfhosts'},
	    'dns_spfall' => $config{'bind_spfall'},
	    'dns_sub' => $config{'bind_sub'} || "none",
	    'dns_master' => $config{'bind_master'} || "none",
	    'namedconf' => $config{'namedconf'} || "none",
	    'ftp' => $config{'proftpd_config'},
	    'ftp_dir' => $config{'ftp_dir'},
	    'logrotate' => $config{'logrotate_config'} || "none",
	    'status' => $config{'statusemail'} || "none",
	    'statusonly' => int($config{'statusonly'}),
	    'statustimeout' => $config{'statustimeout'},
	    'mail_on' => $config{'domain_template'} eq "none" ? "none" : "yes",
	    'mail' => $config{'domain_template'} eq "none" ||
		      $config{'domain_template'} eq "default" ?
				&cat_file("domain-template") :
				&cat_file($config{'domain_template'}),
	    'mail_subject' => $config{'newdom_subject'} ||
			      &entities_to_ascii($text{'mail_dsubject'}),
	    'mail_cc' => $config{'newdom_cc'},
	    'mail_bcc' => $config{'newdom_bcc'},
	    'spam' => $config{'spam_client'},
	    'spam_host' => $config{'spam_host'},
	    'spam_size' => $config{'spam_size'},
	    'spamclear' => $config{'spamclear'} || 'none',
	    'defmquota' => $config{'defmquota'} || "none",
	    'user_aliases' => $config{'newuser_aliases'} || "none",
	    'dom_aliases' => $config{'newdom_aliases'} || "none",
	    'dom_aliases_bounce' => int($config{'newdom_alias_bounce'}),
	    'mysql' => $config{'mysql_db'} || '${PREFIX}',
	    'mysql_wild' => $config{'mysql_wild'},
	    'mysql_suffix' => $config{'mysql_suffix'} || "none",
	    'mysql_hosts' => $config{'mysql_hosts'} || "none",
	    'mysql_mkdb' => $config{'mysql_mkdb'},
	    'mysql_nopass' => $config{'mysql_nopass'},
	    'mysql_chgrp' => $config{'mysql_chgrp'},
	    'skel' => $config{'virtual_skel'} || "none",
	    'skel_subs' => int($config{'virtual_skel_subs'}),
	    'frame' => &cat_file("framefwd-template"),
	    'gacl' => 1,
	    'gacl_umode' => $config{'gacl_umode'},
	    'gacl_uusers' => $config{'gacl_uusers'},
	    'gacl_ugroups' => $config{'gacl_ugroups'},
	    'gacl_groups' => $config{'gacl_groups'},
	    'gacl_root' => $config{'gacl_root'},
	    'webmin_group' => $config{'webmin_group'},
	    'extra_prefix' => $config{'extra_prefix'} || "none",
	    'ugroup' => $config{'defugroup'} || "none",
	    'quota' => $config{'defquota'} || "none",
	    'uquota' => $config{'defuquota'} || "none",
	    'mailboxlimit' => $config{'defmailboxlimit'} eq "" ? "none" :
			      $config{'defmailboxlimit'},
	    'aliaslimit' => $config{'defaliaslimit'} eq "" ? "none" :
			    $config{'defaliaslimit'},
	    'dbslimit' => $config{'defdbslimit'} eq "" ? "none" :
			  $config{'defdbslimit'},
	    'domslimit' => $config{'defdomslimit'} eq "" ? 0 :
			   $config{'defdomslimit'} eq "*" ? "none" :
			   $config{'defdomslimit'},
	    'bwlimit' => $config{'defbwlimit'} eq "" ? "none" :
			 $config{'defbwlimit'},
	    'capabilities' => $config{'defcapabilities'},
	    'featurelimits' => $config{'featurelimits'} || "none",
	    'nodbname' => $config{'defnodbname'},
	    'norename' => $config{'defnorename'},
	    'forceunder' => $config{'defforceunder'},
	    'ranges' => $config{'ip_ranges'} || "none",
	    'mailgroup' => $config{'mailgroup'} || "none",
	    'ftpgroup' => $config{'ftpgroup'} || "none",
	    'dbgroup' => $config{'dbgroup'} || "none",
	    'othergroups' => $config{'othergroups'} || "none",
	    'quotatype' => $config{'hard_quotas'} ? "hard" : "soft",
	    'append_style' => $config{'append_style'},
	    'domalias' => $config{'domalias'} || "none",
	    'domalias_type' => $config{'domalias_type'} || 0,
	    'for_parent' => 1,
	    'for_sub' => 0,
	    'for_alias' => 1,
	    'for_users' => !$config{'deftmpl_nousers'},
	    'resellers' => !defined($config{'tmpl_resellers'}) ? "*" :
				$config{'tmpl_resellers'},
	  } );
foreach my $w (@php_wrapper_templates) {
	$rv[0]->{$w} = $config{$w} || 'none';
	}
foreach my $phpver (@all_possible_php_versions) {
        $rv[0]->{'web_php_ini_'.$phpver} =
		defined($config{'php_ini_'.$phpver}) ?
			$config{'php_ini_'.$phpver} : $config{'php_ini'},
	}
push(@rv, { 'id' => 1,
	    'name' => 'Defaults Settings For Sub-Servers',
	    'standard' => 1,
	    'mail_on' => $config{'subdomain_template'} eq "none" ? "none" :
			 $config{'subdomain_template'} eq "" ? "" : "yes",
	    'mail' => $config{'subdomain_template'} eq "none" ||
		      $config{'subdomain_template'} eq "" ||
		      $config{'subdomain_template'} eq "default" ?
				&cat_file("subdomain-template") :
				&cat_file($config{'subdomain_template'}),
	    'mail_subject' => $config{'newsubdom_subject'} ||
			      &entities_to_ascii($text{'mail_dsubject'}),
	    'mail_cc' => $config{'newsubdom_cc'},
	    'mail_bcc' => $config{'newsubdom_bcc'},
	    'skel' => $config{'sub_skel'} || "none",
	    'for_parent' => 0,
	    'for_sub' => 1,
	    'for_alias' => 0,
	    'for_users' => !$config{'subtmpl_nousers'},
	    'resellers' => '*',
	  } );
local $f;
opendir(DIR, $templates_dir);
while(defined($f = readdir(DIR))) {
	if ($f ne "." && $f ne "..") {
		local %tmpl;
		&read_file("$templates_dir/$f", \%tmpl);
		$tmpl{'mail'} =~ s/\t/\n/g;
		$tmpl{'resellers'} = '*' if (!defined($tmpl{'resellers'}));
		if ($tmpl{'id'} == 1 || $tmpl{'id'} == 0) {
			foreach $k (keys %tmpl) {
				$rv[$tmpl{'id'}]->{$k} = $tmpl{$k}
					if (!defined($rv[$tmpl{'id'}]->{$k}));
				}
			}
		else {
			push(@rv, \%tmpl);
			}
		foreach my $phpver (@all_possible_php_versions) {
			if (!defined($tmpl{'web_php_ini_'.$phpver})) {
				$tmpl{'web_php_ini_'.$phpver} =
					$tmpl{'web_php_ini'};
				}
			}
		}
	}
closedir(DIR);
return @rv;
}

# list_available_templates([&parentdom], [&aliasdom])
# Returns a list of templates for creating a new server, with the given parent
# and alias target domains
sub list_available_templates
{
local ($parentdom, $aliasdom) = @_;
local @rv;
foreach my $t (&list_templates()) {
	next if ($t->{'deleted'});
	next if (($parentdom && !$aliasdom) && !$t->{'for_sub'});
	next if (!$parentdom && !$t->{'for_parent'});
	next if (!&master_admin() && !&reseller_admin() && !$t->{'for_users'});
	next if ($aliasdom && !$t->{'for_alias'});
	next if (!&can_use_template($t));
	push(@rv, $t);
	}
return @rv;
}

# save_template(&template)
# Create or update a template. If saving the standard template, updates the
# appropriate config options instead of the template file.
sub save_template
{
local ($tmpl) = @_;
local $save_config = 0;
if (!defined($tmpl->{'id'})) {
	$tmpl->{'id'} = &domain_id();
	}
if ($tmpl->{'id'} == 0) {
	# Update appropriate config entries
	$config{'deftmpl_nousers'} = !$tmpl->{'for_users'};
	$config{'apache_config'} = $tmpl->{'web'};
	$config{'suexec'} = $tmpl->{'web_suexec'};
	$config{'web_writelogs'} = $tmpl->{'web_writelogs'};
	$config{'web_user'} = $tmpl->{'web_user'};
	$config{'html_dir'} = $tmpl->{'web_html_dir'};
	$config{'html_perms'} = $tmpl->{'web_html_perms'};
	$config{'stats_dir'} = $tmpl->{'web_stats_dir'};
	$config{'stats_hdir'} = $tmpl->{'web_stats_hdir'};
	$config{'stats_pass'} = $tmpl->{'web_stats_pass'};
	$config{'stats_noedit'} = $tmpl->{'web_stats_noedit'};
	$config{'web_port'} = $tmpl->{'web_port'};
	$config{'web_sslport'} = $tmpl->{'web_sslport'};
	$config{'webmin_ssl'} = $tmpl->{'web_webmin_ssl'};
	$config{'usermin_ssl'} = $tmpl->{'web_usermin_ssl'};
	$config{'php_vars'} = $tmpl->{'php_vars'} eq "none" ? "" :
				$tmpl->{'php_vars'};
	$config{'php_suexec'} = $tmpl->{'web_php_suexec'};
	$config{'ruby_suexec'} = $tmpl->{'web_ruby_suexec'};
	$config{'phpver'} = $tmpl->{'web_phpver'};
	$config{'phpchildren'} = $tmpl->{'web_phpchildren'};
	foreach my $phpver (@all_possible_php_versions) {
		$config{'php_ini_'.$phpver} = $tmpl->{'web_php_ini_'.$phpver};
		}
	delete($config{'php_ini'});
	$config{'php_noedit'} = $tmpl->{'web_php_noedit'};
	$config{'def_webalizer'} = $tmpl->{'webalizer'} eq "none" ? "" :
					$tmpl->{'webalizer'};
	$config{'disabled_web'} = $tmpl->{'disabled_web'} eq "none" ? "" :
					$tmpl->{'disabled_web'};
	$config{'disabled_url'} = $tmpl->{'disabled_url'} eq "none" ? "" :
					$tmpl->{'disabled_url'};
	$config{'alias_mode'} = $tmpl->{'web_alias'};
	$config{'bind_config'} = $tmpl->{'dns'};
	$config{'bind_replace'} = $tmpl->{'dns_replace'};
	$config{'bind_spf'} = $tmpl->{'dns_spf'} eq 'none' ? undef
							   : $tmpl->{'dns_spf'};
	$config{'bind_spfhosts'} = $tmpl->{'dns_spfhosts'};
	$config{'bind_spfall'} = $tmpl->{'dns_spfall'};
	$config{'bind_sub'} = $tmpl->{'dns_sub'} eq 'none' ? undef
							   : $tmpl->{'dns_sub'};
	$config{'bind_master'} = $tmpl->{'dns_master'} eq 'none' ? undef
						   : $tmpl->{'dns_master'};
	$config{'dns_view'} = $tmpl->{'dns_view'};
	$config{'namedconf'} = $tmpl->{'namedconf'} eq 'none' ? undef :
							$tmpl->{'namedconf'};
	delete($config{'mx_server'});
	$config{'proftpd_config'} = $tmpl->{'ftp'};
	$config{'ftp_dir'} = $tmpl->{'ftp_dir'};
	$config{'logrotate_config'} = $tmpl->{'logrotate'} eq "none" ?
					"" : $tmpl->{'logrotate'};
	$config{'statusemail'} = $tmpl->{'status'} eq 'none' ?
					'' : $tmpl->{'status'};
	$config{'statusonly'} = $tmpl->{'statusonly'};
	$config{'statustimeout'} = $tmpl->{'statustimeout'};
	if ($tmpl->{'mail_on'} eq 'none') {
		# Don't send
		$config{'domain_template'} = 'none';
		}
	else {
		# Sending, but need to set a valid mail file
		if ($config{'domain_template'} eq 'none') {
			$config{'domain_template'} = 'default';
			}
		}
	# Write message to default template file, or custom if set
	&uncat_file($config{'domain_template'} eq "none" ||
		    $config{'domain_template'} eq "default" ?
			"domain-template" :
			$config{'domain_template'}, $tmpl->{'mail'});
	$config{'newdom_subject'} = $tmpl->{'mail_subject'};
	$config{'newdom_cc'} = $tmpl->{'mail_cc'};
	$config{'newdom_bcc'} = $tmpl->{'mail_bcc'};
	$config{'spam_client'} = $tmpl->{'spam'};
	$config{'spam_host'} = $tmpl->{'spam_host'};
	$config{'spam_size'} = $tmpl->{'spam_size'};
	$config{'spamclear'} = $tmpl->{'spamclear'};
	$config{'defmquota'} = $tmpl->{'defmquota'} eq "none" ?
					"" : $tmpl->{'defmquota'};
	$config{'newuser_aliases'} = $tmpl->{'user_aliases'} eq "none" ?
					"" : $tmpl->{'user_aliases'};
	$config{'newdom_aliases'} = $tmpl->{'dom_aliases'} eq "none" ?
					"" : $tmpl->{'dom_aliases'};
	$config{'newdom_alias_bounce'} = $tmpl->{'dom_aliases_bounce'};
	$config{'mysql_db'} = $tmpl->{'mysql'};
	$config{'mysql_wild'} = $tmpl->{'mysql_wild'};
	$config{'mysql_hosts'} = $tmpl->{'mysql_hosts'} eq "none" ?
					"" : $tmpl->{'mysql_hosts'};
	$config{'mysql_suffix'} = $tmpl->{'mysql_suffix'} eq "none" ?
					"" : $tmpl->{'mysql_suffix'};
	$config{'mysql_mkdb'} = $tmpl->{'mysql_mkdb'};
	$config{'mysql_nopass'} = $tmpl->{'mysql_nopass'};
	$config{'mysql_chgrp'} = $tmpl->{'mysql_chgrp'};
	$config{'virtual_skel'} = $tmpl->{'skel'} eq "none" ? "" :
				  $tmpl->{'skel'};
	$config{'virtual_skel_subs'} = $tmpl->{'skel_subs'};
	$config{'gacl_umode'} = $tmpl->{'gacl_umode'};
	$config{'gacl_ugroups'} = $tmpl->{'gacl_ugroups'};
	$config{'gacl_users'} = $tmpl->{'gacl_users'};
	$config{'gacl_groups'} = $tmpl->{'gacl_groups'};
	$config{'gacl_root'} = $tmpl->{'gacl_root'};
	$config{'webmin_group'} = $tmpl->{'webmin_group'};
	$config{'extra_prefix'} = $tmpl->{'extra_prefix'} eq "none" ? "" :
					$tmpl->{'extra_prefix'};
	$config{'defugroup'} = $tmpl->{'ugroup'};
	$config{'defquota'} = $tmpl->{'quota'};
	$config{'defuquota'} = $tmpl->{'uquota'};
	$config{'defmailboxlimit'} = $tmpl->{'mailboxlimit'} eq 'none' ? undef :
				     $tmpl->{'mailboxlimit'};
	$config{'defaliaslimit'} = $tmpl->{'aliaslimit'} eq 'none' ? undef :
				   $tmpl->{'aliaslimit'};
	$config{'defdbslimit'} = $tmpl->{'dbslimit'} eq 'none' ? undef :
				 $tmpl->{'dbslimit'};
	$config{'defdomslimit'} = $tmpl->{'domslimit'} eq 'none' ? "*" :
				  $tmpl->{'domslimit'} eq '0' ? "" :
				  $tmpl->{'domslimit'};
	$config{'defbwlimit'} = $tmpl->{'bwlimit'} eq 'none' ? undef :
				$tmpl->{'bwlimit'};
	$config{'defcapabilities'} = $tmpl->{'capabilities'};
	$config{'featurelimits'} = $tmpl->{'featurelimits'};
	$config{'defnodbname'} = $tmpl->{'nodbname'};
	$config{'defnorename'} = $tmpl->{'norename'};
	$config{'defforceunder'} = $tmpl->{'forceunder'};
	&uncat_file("framefwd-template", $tmpl->{'frame'});
	$config{'ip_ranges'} = $tmpl->{'ranges'} eq 'none' ? undef :
			       $tmpl->{'ranges'};
	$config{'mailgroup'} = $tmpl->{'mailgroup'} eq 'none' ? undef :
			       $tmpl->{'mailgroup'};
	$config{'ftpgroup'} = $tmpl->{'ftpgroup'} eq 'none' ? undef :
			      $tmpl->{'ftpgroup'};
	$config{'dbgroup'} = $tmpl->{'dbgroup'} eq 'none' ? undef :
			     $tmpl->{'dbgroup'};
	$config{'othergroups'} = $tmpl->{'othergroups'} eq 'none' ? undef :
			     	 $tmpl->{'othergroups'};
	$config{'hard_quotas'} = $tmpl->{'quotatype'} eq "hard" ? 1 : 0;
	$config{'append_style'} = $tmpl->{'append_style'};
	$config{'domalias'} = $tmpl->{'domalias'} eq 'none' ? undef :
			      $tmpl->{'domalias'};
	$config{'domalias_type'} = $tmpl->{'domalias_type'};
	foreach my $w (@php_wrapper_templates) {
		$config{$w} = $tmpl->{$w};
		}
	$save_config = 1;
	}
elsif ($tmpl->{'id'} == 1) {
	# For the default for sub-servers, update mail and skel in config only
	$config{'subtmpl_nousers'} = !$tmpl->{'for_users'};
	if ($tmpl->{'mail_on'} eq 'none') {
		# Don't send
		$config{'subdomain_template'} = 'none';
		}
	elsif ($tmpl->{'mail_on'} eq '') {
		# Use default message (for top-level servers)
		$config{'subdomain_template'} = '';
		}
	else {
		# Sending, but need to set a valid mail file
		if ($config{'subdomain_template'} eq 'none') {
			$config{'subdomain_template'} = 'default';
			}
		}
	&uncat_file($config{'subdomain_template'} eq "none" ||
		    $config{'subdomain_template'} eq "" ||
		    $config{'subdomain_template'} eq "default" ?
			"subdomain-template" :
			$config{'subdomain_template'}, $tmpl->{'mail'});
	$config{'newsubdom_subject'} = $tmpl->{'mail_subject'};
	$config{'newsubdom_cc'} = $tmpl->{'mail_cc'};
	$config{'newsubdom_bcc'} = $tmpl->{'mail_bcc'};
	$config{'sub_skel'} = $tmpl->{'skel'} eq "none" ? "" :
			      $tmpl->{'skel'};
	$save_config = 1;
	}
if ($tmpl->{'id'} != 0) {
	# Just save the entire template to a file
	&make_dir($templates_dir, 0700);
	$tmpl->{'created'} ||= time();
	$tmpl->{'mail'} =~ s/\n/\t/g;
	&lock_file("$templates_dir/$tmpl->{'id'}");
	&write_file("$templates_dir/$tmpl->{'id'}", $tmpl);
	&unlock_file("$templates_dir/$tmpl->{'id'}");
	}
else {
	# Only plugin-specific options go to a file
	&make_dir($templates_dir, 0700);
	&lock_file("$templates_dir/$tmpl->{'id'}");
	&read_file("$templates_dir/$tmpl->{'id'}", \%ptmpl);
	local %ptmpl;
	foreach my $p (@plugins) {
		foreach my $k (keys %$tmpl) {
			if ($k =~ /^\Q$p\E/) {
				$ptmpl{$k} = $tmpl->{$k};
				}
			}
		}
	&write_file("$templates_dir/$tmpl->{'id'}", \%ptmpl);
	&unlock_file("$templates_dir/$tmpl->{'id'}");
	}
if ($save_config) {
	&lock_file($module_config_file);
	$config{'last_check'} = time()+1;
	&write_file($module_config_file, \%config);
	&unlock_file($module_config_file);
	}
}

# get_template(id)
# Returns a template, with any default settings filled in from real default
sub get_template
{
local @tmpls = &list_templates();
local ($tmpl) = grep { $_->{'id'} == $_[0] } @tmpls;
return undef if (!$tmpl);	# not found
if (!$tmpl->{'default'}) {
	local $def = $tmpls[0];
	local $p;
	local %done;
	foreach $p ("dns_spf", "dns_sub", "dns_master",
		    "web", "dns", "ftp", "frame", "user_aliases",
		    "ugroup", "quota", "uquota", "mailboxlimit", "domslimit",
		    "dbslimit", "aliaslimit", "bwlimit", "skel",
		    "mysql_hosts", "mysql_mkdb", "mysql_suffix", "mysql_chgrp",
		    "mysql_nopass", "mysql_wild", "mysql", "webalizer",
		    "dom_aliases", "ranges", "mailgroup", "ftpgroup", "dbgroup",
		    "othergroups", "defmquota", "quotatype", "append_style",
		    "domalias", "logrotate", "disabled_web", "disabled_url",
		    "php", "status", "extra_prefix", "capabilities",
		    "webmin_group", "spam", "spamclear", "namedconf",
		    "nodbname", "norename", "forceunder",
		    @plugins,
		    @php_wrapper_templates,
		    "capabilities",
		    "featurelimits",
		    (map { $_."limit" } @plugins)) {
		if ($tmpl->{$p} eq "") {
			local $k;
			foreach $k (keys %$def) {
				if (!$done{$k} &&
				    ($k =~ /^\Q$p\E_/ || $k eq $p)) {
					$tmpl->{$k} = $def->{$k};
					$done{$k}++;
					}
				}
			}
		}
	# Mail is a special case - it is the mail_on variable that controls
	# inheritance.
	if ($tmpl->{'mail_on'} eq '') {
		local $k;
		foreach $k (keys %$def) {
			if (!$done{$k} &&
			    ($k =~ /^mail_/ || $k eq 'mail')) {
				$tmpl->{$k} = $def->{$k};
				$done{$k}++;
				}
			}
		}
	# The ruby setting needs to default to -1 if the web section is defined
	# in this template, but we are using the GPL release
	$tmpl->{'web_ruby_suexec'} = -1 if ($tmpl->{'web_ruby_suexec'} eq '');
	}
return $tmpl;
}

# delete_template(&template)
# If this template is used by any domains, just mark it as deleted.
# Otherwise, really delete it.
sub delete_template
{
local %tmpl;
&lock_file("$templates_dir/$_[0]->{'id'}");
local @users = &get_domain_by("template", $_[0]->{'id'});
if (@users) {
	&read_file("$templates_dir/$_[0]->{'id'}", \%tmpl);
	$tmpl{'deleted'} = 1;
	&write_file("$templates_dir/$_[0]->{'id'}", \%tmpl);
	}
else {
	&unlink_file("$templates_dir/$_[0]->{'id'}");
	}
&unlock_file("$templates_dir/$_[0]->{'id'}");
}

# list_template_scripts(&template)
# Returns a list of scripts specified for this template. May return "none"
# if there are none.
sub list_template_scripts
{
local ($tmpl) = @_;
return "none" if ($tmpl->{'noscripts'});
local @rv;
opendir(DIR, $template_scripts_dir);
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(\d+)_(\d+)$/ && $1 == $tmpl->{'id'}) {
		local %script;
		&read_file("$template_scripts_dir/$f", \%script);
		$script{'id'} = $2;
		$script{'file'} = "$template_scripts_dir/$f";
		push(@rv, \%script);
		}
	}
closedir(DIR);
return \@rv;
}

# save_template_scripts(&template, &scripts|"none")
# Updates the scripts for some template
sub save_template_scripts
{
local ($tmpl, $scripts) = @_;

# Delete old scripts
opendir(DIR, $template_scripts_dir);
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(\d+)_(\d+)$/ && $1 == $tmpl->{'id'}) {
		unlink("$template_scripts_dir/$f");
		}
	}
closedir(DIR);

if ($scripts eq "none") {
	$tmpl->{'noscripts'} = 1;
	}
else {
	# Save new scripts
	mkdir($template_scripts_dir, 0700);
	foreach my $script (@$scripts) {
		&write_file("$template_scripts_dir/$tmpl->{'id'}_$script->{'id'}", $script);
		}

	$tmpl->{'noscripts'} = 0;
	}
&save_template($tmpl);
}

# get_template_scripts(&template)
# Returns the actual scripts that should be installed when a domain is setup
# using this template, taking defaults into account
sub get_template_scripts
{
local ($tmpl) = @_;
local $scripts = &list_template_scripts($tmpl);
if ($scripts eq "none") {
	return ( );
	}
elsif (@$scripts || $tmpl->{'default'}) {
	return @$scripts;
	}
else {
	# Fall back to default
	local @tmpls = &list_templates();
	local $def = $tmpls[0];
	return &get_template_scripts($def);
	}
}

# cat_file(file)
# Returns the contents of some file
sub cat_file
{
local $path = $_[0] =~ /^\// ? $_[0] : "$module_config_directory/$_[0]";
return &read_file_contents($path);
}

# uncat_file(file, data)
# Writes to some file
sub uncat_file
{
local $path = $_[0] =~ /^\// ? $_[0] : "$module_config_directory/$_[0]";
&open_lock_tempfile(FILE, ">$path");
&print_tempfile(FILE, $_[1]);
&close_tempfile(FILE);
}

# plugin_call(module, function, [arg, ...])
# If some plugin function is defined, call it and return the result,
# otherwise return undef
sub plugin_call
{
local ($mod, $func, @args) = @_;
if (&plugin_defined($mod, $func)) {
	if ($main::module_name ne "virtual_server") {
		# Set up virtual_server package
		&foreign_require("virtual-server", "virtual-server-lib.pl");
		$virtual_server::first_print = $first_print;
		$virtual_server::second_print = $second_print;
		$virtual_server::indent_print = $indent_print;
		$virtual_server::outdent_print = $outdent_print;
		}
	return &foreign_call($mod, $func, @args);
	}
else {
	return wantarray ? ( ) : undef;
	}
}

# plugin_defined(module, function)
# Returns 1 if some function is defined in a plugin
sub plugin_defined
{
local $pkg = $_[0];
$pkg =~ s/[^A-Za-z0-9]/_/g;
local $func = "${pkg}::$_[1]";
return defined(&$func);
}

# database_feature([&domain])
# Returns 1 if any feature that uses a database is enabled (perhaps in a domain)
sub database_feature
{
local $ok = 0;
foreach my $f ('mysql', 'postgres', @database_plugins) {
	$ok = 1 if ($config{$f} &&
		    (!$_[0] || $_[0]->{$f}));
	}
return $ok;
}

# list_custom_fields()
# Returns a list of structures containing custom field details
sub list_custom_fields
{
local @rv;
local $_;
open(FIELDS, $custom_fields_file);
while(<FIELDS>) {
	s/\r|\n//g;
	local @a = split(/:/, $_, 4);
	push(@rv, { 'name' => $a[0],
		    'type' => $a[1],
		    'opts' => $a[2],
		    'desc' => $a[3] });

	}
close(FIELDS);
return @rv;
}

# save_custom_fields(&fields)
sub save_custom_fields
{
&open_lock_tempfile(FIELDS, ">$custom_fields_file");
foreach my $a (@{$_[0]}) {
	&print_tempfile(FIELDS, $a->{'name'},":",$a->{'type'},":",
		     $a->{'opts'},":",$a->{'desc'},"\n");
	}
&close_tempfile(FIELDS);
}

# list_custom_links()
# Returns a list of structures containing custom link details
sub list_custom_links
{
local @rv;
local $_;
open(LINKS, $custom_links_file);
while(<LINKS>) {
	s/\r|\n//g;
	local @a = split(/\t/, $_);
	push(@rv, { 'desc' => $a[0],
		    'url' => $a[1],
		    'who' => { map { $_ => 1 } split(/:/, $a[2]) },
		    'open' => $a[3],
		    'cat' => $a[4],
		  });
	}
close(LINKS);
return @rv;
}

# save_custom_links(&links)
# Write out the given list of custom links to a file
sub save_custom_links
{
&open_lock_tempfile(LINKS, ">$custom_links_file");
foreach my $a (@{$_[0]}) {
	&print_tempfile(LINKS, $a->{'desc'}."\t".$a->{'url'}."\t".
			       join(":", keys %{$a->{'who'}})."\t".
			       int($a->{'open'})."\t".$a->{'cat'}."\n");
	}
&close_tempfile(LINKS);
}

# list_custom_link_categories()
# Returns a list of all custom link category hash refs
sub list_custom_link_categories
{
local @rv;
open(LINKCATS, $custom_link_categories_file);
while(<LINKCATS>) {
	s/\r|\n//g;
	local @a = split(/\t/, $_);
	push(@rv, { 'id' => $a[0], 'desc' => $a[1] });
	}
close(LINKCATS);
return @rv;
}

# save_custom_link_categories(&cats)
# Write out the given list of link categories to a file
sub save_custom_link_categories
{
&open_lock_tempfile(LINKCATS, ">$custom_link_categories_file");
foreach my $a (@{$_[0]}) {
	&print_tempfile(LINKCATS, $a->{'id'}."\t".$a->{'desc'}."\n");
	}
&close_tempfile(LINKCATS);
}

# list_visible_custom_links(&domain)
# Returns a list of descriptions and URLs for custom links in the given domain,
# for the current user type. Category names are also include.
sub list_visible_custom_links
{
local ($d) = @_;
local @rv;
local $me = &master_admin() ? 'master' :
	    &reseller_admin() ? 'reseller' : 'domain';
local %cats = map { $_->{'id'}, $_->{'desc'} } &list_custom_link_categories();
foreach my $l (&list_custom_links()) {
	if ($l->{'who'}->{$me}) {
		local $nl = {
			'desc' => &substitute_domain_template($l->{'desc'}, $d),
			'url' => &substitute_domain_template($l->{'url'}, $d),
			'open' => $l->{'open'},
			'catname' => $cats{$l->{'cat'}},
			'cat' => $l->{'cat'}, 
			};
		if ($nl->{'desc'} && $nl->{'url'}) {
			push(@rv, $nl);
			}
		}
	}
return @rv;
}

# show_custom_fields([&domain], [&tds])
# Returns HTML for custom field inputs, for inclusion in a table
sub show_custom_fields
{
local ($d, $tds) = @_;
local $rv;
local $f;
local $col = 0;
foreach $f (&list_custom_fields()) {
	local $n = "field_".$f->{'name'};
	local $v = $d ? $d->{"field_".$f->{'name'}} : undef;
	local $fv;
	if ($f->{'type'} == 0) {
		local $sz = $f->{'opts'} || 30;
		$fv = &ui_textbox($n, $v, $sz);
		}
	elsif ($f->{'type'} == 1 || $f->{'type'} == 2) {
		$fv = &ui_user_textbox($n, $v);
		}
	elsif ($f->{'type'} == 3 || $f->{'type'} == 4) {
		$fv = &ui_group_textbox($n, $v);
		}
	elsif ($f->{'type'} == 5 || $f->{'type'} == 6) {
		$fv = &ui_textbox($n, $v, 30)." ".
			&file_chooser_button($n, $f->{'type'}-5);
		}
	elsif ($f->{'type'} == 7) {
		$fv = &ui_radio($n, $v ? 1 : 0, [ [ 1, $text{'yes'} ],
						   [ 0, $text{'no'} ] ]);
		}
	elsif ($f->{'type'} == 8) {
		local $sz = $f->{'opts'} || 30;
		$fv = &ui_password($n, $v, $sz);
		}
	elsif ($f->{'type'} == 9) {
		local @opts = &read_opts_file($f->{'opts'});
		local ($found) = grep { $_->[0] eq $v } @opts;
		push(@opts, [ $v, $v ]) if (!$found);
		$fv = &ui_select($n, $v, \@opts);
		}
	elsif ($f->{'type'} == 10) {
		local ($w, $h) = split(/\s+/, $f->{'opts'});
		$h ||= 4;
		$w ||= 30;
		$v =~ s/\t/\n/g;
		$fv = &ui_textarea($n, $v, $h, $w);
		}
	$rv .= &ui_table_row($f->{'desc'}, $fv, 1, $tds);
	}
return $rv;
}

# parse_custom_fields(&domain, &in)
# Updates a domain with custom fields
sub parse_custom_fields
{
local $f;
local %in = %{$_[1]};
foreach $f (&list_custom_fields()) {
	local $n = "field_".$f->{'name'};
	local $rv;
	if ($f->{'type'} == 0 || $f->{'type'} == 5 ||
	    $f->{'type'} == 6 || $f->{'type'} == 8) {
		$rv = $in{$n};
		}
	elsif ($f->{'type'} == 10) {
		$rv = $in{$n};
		$rv =~ s/\r//g;
		$rv =~ s/\n/\t/g;
		}
	elsif ($f->{'type'} == 1 || $f->{'type'} == 2) {
		local @u = getpwnam($in{$n});
		$rv = $f->{'type'} == 1 ? $in{$n} : $u[2];
		}
	elsif ($f->{'type'} == 3 || $f->{'type'} == 4) {
		local @g = getgrnam($in{$n});
		$rv = $f->{'type'} == 3 ? $in{$n} : $g[2];
		}
	elsif ($f->{'type'} == 7) {
		$rv = $in{$n} ? $f->{'opts'} : "";
		}
	elsif ($f->{'type'} == 9) {
		$rv = $in{$n};
		}
	$_[0]->{"field_".$f->{'name'}} = $rv;
	}
}

# read_opts_file(file)
sub read_opts_file
{
local @rv;
local $file = $_[0];
if ($file !~ /^\//) {
	local @uinfo = getpwnam($remote_user);
	if (@uinfo) {
		$file = "$uinfo[7]/$file";
		}
	}
local $_;
open(FILE, $file);
while(<FILE>) {
	s/\r|\n//g;
	if (/^"([^"]*)"\s+"([^"]*)"$/) {
		push(@rv, [ $1, $2 ]);
		}
	elsif (/^"([^"]*)"$/) {
		push(@rv, [ $1, $1 ]);
		}
	elsif (/^(\S+)\s+(\S.*)/) {
		push(@rv, [ $1, $2 ]);
		}
	else {
		push(@rv, [ $_, $_ ]);
		}
	}
close(FILE);
return @rv;
}

# connect_qmail_ldap([return-error])
# Connect to the LDAP server used for Qmail. Returns an LDAP handle on success,
# or an error message on failure.
sub connect_qmail_ldap
{
eval "use Net::LDAP";
if ($@) {
	local $err = &text('ldap_emod', "<tt>Net::LDAP</tt>");
	if ($_[0]) { return $err; }
	else { &error($err); }
	}

# Connect to server
local $port = $config{'ldap_port'} || 389;
local $ldap = Net::LDAP->new($config{'ldap_host'}, port => $port);
if (!$ldap) {
	local $err = &text('ldap_econn',
			   "<tt>$config{'ldap_host'}</tt>","<tt>$port</tt>");
	if ($_[0]) { return $err; }
	else { &error($err); }
	}

# Start TLS if configured
if ($config{'ldap_tls'}) {
	$ldap->start_tls();
	}

# Login
local $mesg;
if ($config{'ldap_login'}) {
	$mesg = $ldap->bind(dn => $config{'ldap_login'},
			    password => $config{'ldap_pass'});
	}
else {
	$mesg = $ldap->bind(anonymous => 1);
	}
if (!$mesg || $mesg->code) {
	local $err = &text('ldap_elogin', "<tt>$config{'ldap_host'}</tt>",
		     $dn, $mesg ? $mesg->error : "Unknown error");
	if ($_[0]) { return $err; }
	else { &error($err); }
	}
return $ldap;
}

# qmail_dn_to_hash(&ldap-object)
# Given a LDAP object containing user details, convert it to a hash
sub qmail_dn_to_hash
{
local $x;
local %oc = map { $_, 1 } $_[0]->get_value("objectClass");
local %user = ( 'dn' => $_[0]->dn(),
		'qmail' => 1,
		'user' => scalar($_[0]->get_value("uid")),
		'plainpass' => scalar($_[0]->get_value("cuserPassword")),
		'uid' => $oc{'posixAccount'} ?
			scalar($_[0]->get_value("uidNumber")) :
			scalar($_[0]->get_value("qmailUID")),
		'gid' => $oc{'posixAccount'} ?
			scalar($_[0]->get_value("gidNumber")) :
			scalar($_[0]->get_value("qmailGID")),
		'real' => scalar($_[0]->get_value("cn")),
		'shell' => scalar($_[0]->get_value("loginShell")),
		'home' => scalar($_[0]->get_value("homeDirectory")),
		'pass' => scalar($_[0]->get_value("userPassword")),
		'mailstore' => scalar($_[0]->get_value("mailMessageStore")),
		'qquota' => scalar($_[0]->get_value("mailQuotaSize")),
		'email' => scalar($_[0]->get_value("mail")),
		'extraemail' => [ $_[0]->get_value("mailAlternateAddress") ],
	      );
local @fwd = $_[0]->get_value("mailForwardingAddress");
if (@fwd) {
	$user{'to'} = \@fwd;
	}
$user{'pass'} =~ s/^{[a-z0-9]+}//i;
$user{'qmail'} = 1;
$user{'unix'} = 1 if ($oc{'posixAccount'});
$user{'person'} = 1 if ($oc{'person'} || $oc{'inetOrgPerson'} ||
			$oc{'posixAccount'});
$user{'mailquota'} = 1;
return %user;
}

# qmail_user_to_dn(&user, &classes, &domain)
# Given a useradmin-style user hash, returns a list of properties to 
# add/update and to delete
sub qmail_user_to_dn
{
local $pfx = $_[0]->{'pass'} =~ /^\{[a-z0-9]+\}/i ? undef : "{crypt}";
local @ee = @{$_[0]->{'extraemail'}};
local @to = @{$_[0]->{'to'}};
local @delrv;
local @rv = (
	 "uid" => $_[0]->{'user'},
	 "qmailUID" => $_[0]->{'uid'},
	 "qmailGID" => $_[0]->{'gid'},
	 "homeDirectory" => $_[0]->{'home'},
	 "userPassword" => $pfx.$_[0]->{'pass'},
	 "mailMessageStore" => $_[0]->{'mailstore'},
	 "mailQuotaSize" => $_[0]->{'qquota'},
	 "mail" => $_[0]->{'email'},
	 "mailHost" => &get_system_hostname(),
	 "accountStatus" => "active",
	);
if (@ee) {
	push(@rv, "mailAlternateAddress" => \@ee );
	}
else {	
	push(@delrv, "mailAlternateAddress");
	}
if (@to) {
	push(@rv, "mailForwardingAddress" => \@to );
	push(@rv, "deliveryMode", "nolocal");
	}
else {	
	push(@delrv, "mailForwardingAddress");
	push(@rv, "deliveryMode", "noforward");
	}
if ($_[0]->{'unix'}) {
	push(@rv, "uidNumber" => $_[0]->{'uid'},
		  "gidNumber" => $_[0]->{'gid'},
		  "loginShell" => $_[0]->{'shell'});
	}
if ($_[0]->{'person'}) {
	push(@rv, "cn" => $_[0]->{'real'});
	}
if (&indexof("person", @{$_[1]}) >= 0 ||
    &indexof("inetOrgPerson", @{$_[1]}) >= 0) {
	# Have to set sn
	push(@rv, "sn" => $_[0]->{'user'});
	}
# Add extra attribs, which can override those set above
local %subs = %{$_[0]};
&userdom_substitutions(\%subs, $_[2]);
local @props = &split_props($config{'ldap_props'}, \%subs);
local @addprops;
local $i;
local %over;
for($i=0; $i<@props; $i+=2) {
	if ($props[$i+1] ne "") {
		push(@addprops, $props[$i], $props[$i+1]);
		}
	else {
		push(@delrv, $props[$i]);
		}
	$over{$props[$i]} = $props[$i+1];
	}
for($i=0; $i<@rv; $i+=2) {
	if (exists($over{$rv[$i]})) {
		splice(@rv, $i, 2);
		$i -= 2;
		}
	}
push(@rv, @addprops);
return wantarray ? ( \@rv, \@delrv ) : \@rv;
}

# split_props(text, &user)
# Splits up LDAP properties
sub split_props
{
local %pmap;
foreach $p (split(/\t+/, &substitute_template($_[0], $_[1]))) {
	if ($p =~ /^(\S+):\s*(.*)/) {
		push(@{$pmap{$1}}, $2);
		}
	}
local @rv;
local $k;
foreach $k (keys %pmap) {
	local $v = $pmap{$k};
	if (@$v == 1) {
		push(@rv, $k, $v->[0]);
		}
	else {
		push(@rv, $k, $v);
		}
	}
return @rv;
}

# create_initial_user(&dom, [no-template], [for-web])
# Returns a structure for a new mailbox user
sub create_initial_user
{
local $user;
if ($config{'mail_system'} == 4) {
	# User is for Qmail+LDAP
	$user = { 'qmail' => 1,
		  'mailquota' => 1,
		  'person' => $config{'ldap_classes'} =~ /person|inetOrgPerson/ || $config{'ldap_unix'} ? 1 : 0,
		  'unix' => $config{'ldap_unix'} };
	}
elsif ($config{'mail_system'} == 5) {
	# VPOPMail user
	$user = { 'vpopmail' => 1,
		  'mailquota' => 1,
		  'person' => 1,
		  'fixedhome' => 1,
		  'noappend' => 1,
		  'noprimary' => 1,
		  'alwaysplain' => 1 };
	}
else {
	# Normal unix user
	$user = { 'unix' => 1,
		  'person' => 1 };
	}
if ($_[0] && !$_[1]) {
	# Initial aliases and quota come from template
	local $tmpl = &get_template($_[0]->{'template'});
	if ($tmpl->{'user_aliases'} ne 'none') {
		$user->{'to'} = [ split(/\t+/, $tmpl->{'user_aliases'}) ];
		}
	$user->{'quota'} = $tmpl->{'defmquota'};
	$user->{'mquota'} = $tmpl->{'defmquota'};
	}
if (!$user->{'noprimary'}) {
	$user->{'email'} = !$_[0] ? "newuser\@".&get_system_hostname() :
			   $_[0]->{'mail'} ? "newuser\@$_[0]->{'dom'}" : undef;
	}
$user->{'secs'} = [ ];
$user->{'shell'} = $config{'shell'};

# Merge in configurable initial user settings
if ($_[0]) {
	local %init;
	&read_file("$initial_users_dir/$_[0]->{'id'}", \%init);
	foreach my $a ("email", "quota", "mquota", "qquota", "shell") {
		$user->{$a} = $init{$a} if (defined($init{$a}));
		}
	foreach my $a ("secs", "to") {
		if (defined($init{$a})) {
			$user->{$a} = [ split(/\t+/, $init{$a}) ];
			}
		}
	if (defined($init{'dbs'})) {
		local ($db, @dbs);
		foreach $db (split(/\t+/, $init{'dbs'})) {
			local ($type, $name) = split(/_/, $db, 2);
			push(@dbs, { 'type' => $type,
				     'name' => $name });
			}
		$user->{'dbs'} = \@dbs;
		}
	}

if ($_[2] && $user->{'unix'}) {
	# This is a website management user
	$user->{'webowner'} = 1;
	$user->{'fixedhome'} = 0;
	$user->{'home'} = &public_html_dir($_[0]);
	$user->{'noquota'} = 1;
	$user->{'mailquota'} = 0;
	$user->{'noprimary'} = 1;
	$user->{'noextra'} = 1;
	$user->{'noalias'} = 1;
	$user->{'nocreatehome'} = 1;
	$user->{'nomailfile'} = 1;
	$user->{'shell'} = $config{'ftp_shell'};
	delete($user->{'email'});
	}

return $user;
}

# save_initial_user(&user, &domain)
# Saves default settings for new users in a virtual server
sub save_initial_user
{
local ($user, $dom) = @_;
if (!-d $initial_users_dir) {
	mkdir($initial_users_dir, 0700);
	}
&lock_file("$initial_users_dir/$dom->{'id'}");
local %init;
foreach my $a ("email", "quota", "mquota", "qquota", "shell") {
	$init{$a} = $user->{$a} if (defined($user->{$a}));
	}
foreach my $a ("secs", "to") {
	if (defined($user->{$a})) {
		$init{$a} = join("\t", @{$user->{$a}});
		}
	}
if (defined($user->{'dbs'})) {
	$init{'dbs'} = join("\t", map { $_->{'type'}."_".$_->{'name'} }
				      @{$user->{'dbs'}});
	}
&write_file("$initial_users_dir/$dom->{'id'}", \%init);
&unlock_file("$initial_users_dir/$dom->{'id'}");
}

# valid_domain_name(&parent, newdomain)
# Returns an error message if some domain name is invalid, or undef if OK.
# Checks domain-owner subdomain and reseller subdomain limits.
sub valid_domain_name
{
if ($_[0] && $access{'forceunder'}) {
	local $pd = $_[0]->{'dom'};
	if ($_[1] !~ /\.\Q$pd\E$/i) {
		return &text('setup_eforceunder', $parentdom->{'dom'});
		}
	}
if ($access{'subdom'}) {
	if ($_[1] !~ /\.\Q$access{'subdom'}\E$/i) {
		return &text('setup_eforceunder', $access{'subdom'});
		}
	}
if (!&master_admin()) {
	foreach my $re (split(/\s+/, $config{'denied_domains'})) {
		if ($_[1] =~ /^$re$/i) {
			return $text{'setup_edenieddomain'};
			}
		}
	}
return undef;
}

# domain_databases(&domain, [&types])
# Returns a list of structures for databases in a domain
sub domain_databases
{
local @dbs;
if ($_[0]->{'mysql'}) {
	local %done;
	local $av = &foreign_available("mysql");
	foreach my $db (split(/\s+/, $_[0]->{'db_mysql'})) {
		next if ($done{$db}++);
		push(@dbs, { 'name' => $db,
			     'type' => 'mysql',
			     'users' => 1,
			     'link' => $av ? "../mysql/edit_dbase.cgi?db=$db"
					   : undef,
			     'desc' => $text{'databases_mysql'} });
		}
	}
if ($_[0]->{'postgres'}) {
	local %done;
	local $av = &foreign_available("postgresql");
	foreach my $db (split(/\s+/, $_[0]->{'db_postgres'})) {
		next if ($done{$db}++);
		push(@dbs, { 'name' => $db,
			     'type' => 'postgres',
			     'link' => $av ? "../postgresql/".
					     "edit_dbase.cgi?db=$db"
					   : undef,
			     'desc' => $text{'databases_postgres'} });
		}
	}
foreach my $f (@database_plugins) {
	push(@dbs, &plugin_call($f, "database_list", $_[0]));
	}
if ($_[1]) {
	# Limit to specified types
	local %types = map { $_, 1 } @{$_[1]};
	@dbs = grep { $types{$_->{'type'}} } @dbs;
	}
return @dbs;
}

# all_databases([&domain])
# Returns a list of all known databases on the system
sub all_databases
{
local @rv;
if ($config{'mysql'}) {
	&require_mysql();
	push(@rv, map { { 'name' => $_,
			  'type' => 'mysql',
			  'desc' => $text{'databases_mysql'},
			  'special' => $_ eq "mysql" } }
		      &mysql::list_databases());
	}
if ($config{'postgres'}) {
	&require_postgres();
	push(@rv, map { { 'name' => $_,
			  'type' => 'postgres',
			  'desc' => $text{'databases_postgres'},
			  'special' => ($_ =~ /^template/i) } }
		      &postgresql::list_databases());
	}
foreach my $f (@database_plugins) {
	push(@rv, &plugin_call($f, "databases_all", $_[0]));
	}
return @rv;
}

# resync_all_databases(&domain, &all-dbs)
# Updates a domain object to remove databases that no longer really exist
sub resync_all_databases
{
local ($d, $all) = @_;
local %all = map { ("$_->{'type'} $_->{'name'}", $_) } @$all;
local $removed = 0;
foreach my $k (keys %$d) {
	if ($k =~ /^db_(\S+)$/) {
		local $t = $1;
		local @names = split(/\s+/, $d->{$k});
		local @newnames = grep { $all{"$t $_"} } @names;
		if (@names != @newnames) {
			$d->{$k} = join(" ", @newnames);
			$removed = 1;
			}
		}
	}
if ($removed) {
	&save_domain($d);
	}
}

# get_database_host(type)
# Returns the remote host that we use for the given database type. If the
# DB is on the same server, returns localhost
sub get_database_host
{
local ($type) = @_;
local $rv;
if (&indexof($type, @features) >= 0) {
	# Built-in DB
	local $hfunc = "get_database_host_".$type;
	$rv = &$hfunc();
	}
elsif (&indexof($type, @database_plugins) >= 0) {
	# From plugin
	$rv = &plugin_call($type, "database_host");
	}
return $rv || "localhost";
}

# count_ftp_bandwidth(logfile, start, &bw-hash, &users, prefix, include-rotated)
# Scans an FTP server log file for downloads by some user, and returns the
# total bytes and time of last log entry.
sub count_ftp_bandwidth
{
require 'timelocal.pl';
local $max_ltime = $_[1];
local $f;
foreach $f ($_[5] ? &all_log_files($_[0], $max_ltime) : ( $_[0] )) {
	local $_;
	if ($f =~ /\.gz$/i) {
		open(LOG, "gunzip -c ".quotemeta($f)." |");
		}
	elsif ($f =~ /\.Z$/i) {
		open(LOG, "uncompress -c ".quotemeta($f)." |");
		}
	else {
		open(LOG, $f);
		}
	while(<LOG>) {
		if (/^(\S+)\s+(\S+)\s+(\S+)\s+\[(\d+)\/(\S+)\/(\d+):(\d+):(\d+):(\d+)\s+(\S+)\]\s+"([^"]*)"\s+(\S+)\s+(\S+)/) {
			# ProFTPD extended log format line
			local $ltime = timelocal($9, $8, $7, $4, $apache_mmap{lc($5)}, $6-1900);
			$max_ltime = $ltime if ($ltime > $max_ltime);
			next if ($_[3] && &indexof($3, @{$_[3]}) < 0);	# user
			next if (substr($11, 0, 4) ne "RETR" &&
				 substr($11, 0, 4) ne "STOR");
			if ($ltime > $_[1]) {
				local $day = int($ltime / (24*60*60));
				$_[2]->{$_[4]."_".$day} += $13;
				}
			}
		elsif (/^\S+\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+\d+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+(\S+)/) {
			# xferlog format line
			local $ltime = timelocal($5, $4, $3, $2, $apache_mmap{lc($1)}, $6-1900);
			$max_ltime = $ltime if ($ltime > $max_ltime);
			next if ($_[3] && &indexof($9, @{$_[3]}) < 0);	# user
			next if ($8 ne "o" && $8 ne "i");
			if ($ltime > $_[1]) {
				local $day = int($ltime / (24*60*60));
				$_[2]->{$_[4]."_".$day} += $7;
				}
			}
		}
	close(LOG);
	}
return $max_ltime;
}

# random_password([len])
# Returns a random password of the specified length, or the configured default
sub random_password
{
&seed_random();
&require_useradmin();
local $random_password;
local $len = $_[0] || $config{'passwd_length'} || 15;
foreach (1 .. $len) {
	$random_password .= $useradmin::random_password_chars[
			rand(scalar(@useradmin::random_password_chars))];
	}
return $random_password;
}

# try_function(feature, function, arg, ...)
# Executes some function, and if it fails prints an error message
sub try_function
{
local ($f, $func, @args) = @_;
local $main::error_must_die = 1;
eval { &$func(@args) };
if ($@) {
	&$second_print(&text('setup_failure',
		$text{'feature_'.$f}, $@));
	return 0;
	}
return 1;
}

# bandwidth_period_start([ago])
# Returns the day number on which the current (or some previous)
# bandwidth period started
sub bandwidth_period_start
{
local ($ago) = @_;
local $now = time();
local $day = int($now / (24*60*60));
local @tm = localtime(time());
local $rv;
if ($config{'bw_past'} eq 'week') {
	# Start on last sunday
	$rv = $day - $tm[6];
	$rv -= $ago*7;
	}
elsif ($config{'bw_past'} eq 'month') {
	# Start at 1st of month
	for(my $i=0; $i<$ago; $i++) {
		$tm[4]--;
		if ($tm[4] < 0) {
			$tm[5]--;
			$tm[4] = 11;
			}
		}
	$rv = int(timelocal(59, 59, 23, 1, $tm[4], $tm[5]) / (24*60*60));
	}
elsif ($config{'bw_past'} eq 'year') {
	# Start at start of year
	$tm[4] -= $ago;
	$rv = int(timelocal(59, 59, 23, 1, 0, $tm[5]) / (24*60*60));
	}
else {
	# Start N days ago
	$rv = $day - $config{'bw_period'};
	$rv -= $ago*$config{'bw_period'};
	}
return $rv;
}

# bandwidth_period_end([ago])
# Returns the day number on which some bandwidth period ends (inclusive)
sub bandwidth_period_end
{
local ($ago) = @_;
local $now = time();
local $day = int($now / (24*60*60));
if ($ago == 0) {
	return $day;
	}
local $sday = &bandwidth_period_start($ago);
if ($config{'bw_past'} eq 'week') {
	# 6 days after start
	return $day + 6;
	}
elsif ($config{'bw_past'} eq 'month') {
	# End of the month
	return &bandwidth_period_start($ago-1)-1;
	}
elsif ($config{'bw_past'} eq 'year') {
	# End of the year
	return &bandwidth_period_start($ago-1)-1;
	}
else {
	return $day + $config{'bw_period'} - 1;
	}
}

# servers_input(name, &ids, &domains)
# Returns HTML for a multi-server selection field
sub servers_input
{
local ($name, $ids, $doms) = @_;
local $sz = scalar(@$doms) > 10 ? 10 : scalar(@$doms) < 5 ? 5 : scalar(@$doms);
return &ui_select($name, $ids,
		  [ map { [ $_->{'id'}, $_->{'dom'} ] }
			sort { $a->{'dom'} cmp $b->{'dom'} } @$doms ],
		  $sz, 1);
}

# can_monitor_bandwidth(&domain)
# Returns 1 if bandwidth monitoring is enabled for some server
sub can_monitor_bandwidth
{
if ($config{'bw_servers'} eq "") {
	return 1;	# always
	}
elsif ($config{'bw_servers'} =~ /^\!(.*)$/) {
	# List of servers not to check
	local @ids = split(/\s+/, $1);
	return &indexof($_[0]->{'id'}, @ids) == -1;
	}
else {
	# List of servers to check
	local @ids = split(/\s+/, $config{'bw_servers'});
	return &indexof($_[0]->{'id'}, @ids) != -1;
	}
}

# Returns 1 if the current user can see mailbox and domain passwords
sub can_show_pass
{
return &master_admin() || &reseller_admin() || $config{'show_pass'};
}

# has_proxy_balancer(&domain)
# Returns 1 if some domain supports proxy balancing
sub has_proxy_balancer
{
local ($d) = @_;
if ($d->{'web'} && $config{'web'} && !$d->{'alias'} && $virtualmin_pro &&
    !$d->{'proxy_pass_mode'}) {
	&require_apache();
	if ($apache::httpd_modules{'mod_proxy'} &&
	    $apache::httpd_modules{'mod_proxy_balancer'}) {
		return 1;
		}
	}
return 0;
}

# require_licence()
# Reads in the file containing the licence_scheduled function. Returns 1 if OK, 0 if not
sub require_licence
{
return 0 if (!$virtualmin_pro);
foreach my $ls ("$module_root_directory/virtualmin-licence.pl",
		$config{'licence_script'}) {
	if ($ls && -r $ls) {
		do $ls;
		if ($@) {
			&error("Licence script failed : $@");
			}
		return 1;
		}
	}
return 0;
}

# setup_licence_cron()
# Checks for and sets up the licence checking cron job (if needed)
sub setup_licence_cron
{
if (&require_licence()) {
	&read_file($licence_status, \%licence);
	return if (time() - $licence{'last'} < 24*60*60); # checked recently, so no worries

	# Hasn't been checked from cron for 3 days .. do it now
	&foreign_require("cron", "cron-lib.pl");
	local ($job) = grep { $_->{'user'} eq 'root' &&
			      $_->{'command'} eq $licence_cmd }
			    &cron::list_cron_jobs();
	if (!$job) {
		# Create
		$job = { 'mins' => int(rand()*60),
			 'hours' => int(rand()*24),
			 'days' => '*',
			 'months' => '*',
			 'weekdays' => '*',
			 'user' => 'root',
			 'active' => 1,
			 'command' => $licence_cmd };
		&cron::create_cron_job($job);
		}
	else {
		# Enforce a proper schedule
		if ($job->{'mins'} !~ /^\d+$/) {
			$job->{'mins'} = int(rand()*60);
			}
		if ($job->{'hours'} !~ /^\d+$/) {
			$job->{'hours'} = int(rand()*24);
			}
		$job->{'days'} = '*';
		$job->{'months'} = '*';
		$job->{'weekdays'} = '*';
		$job->{'active'} = 1;
		$job->{'user'} = 'root';
		$job->{'command'} = $licence_cmd;
		&cron::change_cron_job($job);
		}
	if (!-x $licence_cmd) {
		&cron::create_wrapper($licence_cmd, $module_name, "licence.pl");
		}
	}
}

# check_licence_expired()
# Returns 0 if the licence is valid, 1 if not, or 2 if could not be checked,
# 3 if expired, the expiry date, error message and number of domain.
sub check_licence_expired
{
return 0 if (!&require_licence());
local %licence;
&read_file_cached($licence_status, \%licence);
if (time() - $licence{'last'} > 3*24*60*60) {
	# Hasn't been checked from cron for 3 days .. do it now
	&update_licence_from_site(\%licence);
	&write_file($licence_status, \%licence);
	}
return ($licence{'status'}, $licence{'expiry'},
	$licence{'err'}, $licence{'doms'});
}

# update_licence_from_site(&licence)
sub update_licence_from_site
{
local ($licence) = @_;
local ($status, $expiry, $err, $doms) = &check_licence_site();
$licence->{'status'} = $status;
$licence->{'expiry'} = $expiry;
$licence->{'err'} = $err;
if (defined($doms)) {
	# Only store the max domains if we got something valid back
	$licence->{'doms'} = $doms;
	}
$licence->{'last'} = time();
}

# check_licence_site()
# Calls the function to actually validate the licence, which must return 0 if
# valid, 1 if not, or 2 if could not be checked, 3 if expired, the expiry
# date, any error message, and the max number of domains.
sub check_licence_site
{
return (0) if (!&require_licence());

# First work out a host ID, from the hostid command or MAC address or hostname
local $id;
if (&has_command("hostid")) {
	chop($id = `hostid 2>/dev/null`);
	}
if (!$id) {
	&foreign_require("net", "net-lib.pl");
	local ($iface) = grep { $_->{'fullname'} eq $config{'iface'} }
			      &net::active_interfaces();
	$id = $iface->{'ether'} if ($iface);
	}
if (!$id) {
	$id = &get_system_hostname();
	}

local ($status, $expiry, $err, $doms) = &licence_scheduled($id);
if ($status == 0 && $doms) {
	# A domains limit exists .. check if we have exceeded it
	local @doms = grep { !$_->{'alias'} } &list_domains();
	if (@doms > $doms) {
		$status = 1;
		$err = "Your system is licenced for only $doms servers, but you have ".scalar(@doms).".";
		}
	}
return ($status, $expiry, $err, $doms);
}

# licence_warning_message()
# Returns HTML for an error message about the licence being expired, if it
# is and if the current user is the master admin.
sub licence_warning_message
{
return undef if (!&master_admin());
local ($status, $expiry, $err) = &check_licence_expired();
return undef if ($status == 0);
local $rv = "<table width=100%><tr bgcolor=#ff8888><td align=center>";
$rv .= "<b>".$text{'licence_err'}."</b><br>\n";
$rv .= $err."\n";
if (&can_recheck_licence()) {
	$rv .= &ui_form_start("/$module_name/licence.cgi");
	$rv .= &ui_submit($text{'licence_recheck'});
	$rv .= &ui_form_end();
	}
$rv .= "</td></tr></table>\n";
return $rv;
}

# get_user_domain(user)
# Given a username, returns it's virtual server details
sub get_user_domain
{
local @uinfo = getpwnam($_[0]);
local @doms;
if (@uinfo) {
	# Is a Unix user .. find the domains for his GID (which could include
	# sub-servers), and then check the home for each
	foreach my $d (&get_domain_by("gid", $uinfo[3])) {
		if ($uinfo[7] =~ /^\Q$d->{'home'}\E\/homes\//) {
			return $d;
			}
		}
	}

# Need to check all domains :( This is unlikely to happen though
local @doms = &list_domains();
foreach my $d (@doms) {
	local @users = &list_domain_users($d, 0, 1, 1, 1);
	local $u;
	foreach $u (@users) {
		if ($u->{'user'} eq $_[0] ||
		    &replace_atsign($u->{'user'}) eq $_[0]) {
			return $d;
			}
		}
	}
return undef;
}

# get_domain_user_quotas(&domain, ...)
# For each virtual server, returns the home and mail directory usage for all its
# users (including the server admin), the server admin object, total usage for
# all databases, and database usage that has already been included in the
# home usage.
sub get_domain_user_quotas
{
local ($duserrv);
local $mailquota = 0;
local $homequota = 0;
local $dbquota = 0;
local $dbquota_home = 0;
foreach my $d (@_) {
	local @users = &list_domain_users($d, 0, 1, 0, 1);
	local ($duser) = grep { $_->{'user'} eq $d->{'user'} } @users;
	$duserrv ||= $duser;
	local $u;
	foreach $u (@users) {
		if (!$u->{'domainowner'} && !$u->{'webowner'}) {
			$homequota += $u->{'uquota'};
			$mailquota += $u->{'umquota'};
			}
		}
	local @dbq = &get_database_usage($d);
	$dbquota += $dbq[0];
	$dbquota_home += $dbq[1];
	}
return ($homequota, $mailquota, $duserrv, $dbquota, $dbquota_home);
}

# get_domain_quota(&domain, [db-too])
# For a domain, returns the group quota used on home and mail filesystems.
# If the db flag is set, also returns the sum of all disk space used by
# databases on this and sub-servers. If database usage is already included
# in the group quota for home, it is subtracted.
sub get_domain_quota
{
local ($d, $dbtoo) = @_;
local ($home, $mail, $db, $dbq);
if (&has_group_quotas()) {
	# Query actual group quotas
	if (&has_quota_commands()) {
		# Get from group quota list command
		local $out = &run_quota_command("list_groups");
		foreach my $l (split(/\r?\n/, $out)) {
			local ($group, $used, $soft, $hard) = split(/\s+/, $l);
			if ($group eq $d->{'group'}) {
				$home = $used;
				}
			}
		}
	else {
		# Get from real quotas
		&require_useradmin();
		local $n = &quota::group_filesystems($d->{'group'});
		for(my $i=0; $i<$n; $i++) {
			if ($quota::filesys{$i,'filesys'} eq
			    $config{'home_quotas'}) {
				$home = $quota::filesys{$i,'ublocks'};
				}
			elsif ($config{'mail_quotas'} &&
			       $quota::filesys{$i,'filesys'} eq
			       $config{'mail_quotas'}) {
				$mail = $quota::filesys{$i,'ublocks'};
				}
			}
		}
	if ($dbtoo) {
		$db = 0;
		foreach my $sd ($d, &get_domain_by("parent", $d->{'id'})) {
			local @dbu = &get_database_usage($sd);
			$db += $dbu[0];
			$dbq += $dbu[1];
			}
		}
	$dbq /= &quota_bsize("home");
	}
else {
	# Fake it by summing up user quotas
	local $dummy;
	($home, $mail, $dummy, $db, $dbq) = &get_domain_user_quotas(
				$d, &get_domain_by("parent", $d->{'id'}));
	}
return ($home-$dbq, $mail, $db);
}

# compute_prefix(domain-name, group, [&parent])
# Given a domain name, returns the prefix for usernames
sub compute_prefix
{
local ($name, $group, $parent) = @_;
if ($config{'longname'} == 1) {
	# Prefix is same as domain name
	return $name;
	}
elsif ($group && !$parent && $config{'longname'} == 0) {
	# For top-level domains, prefix is same as group name
	return $group;
	}
else {
	# Otherwise, prefix comes from first part of domain
	$name =~ /^([^\.]+)/;
	return $1;
	}
}

# get_domain_owner(&domain)
# Returns the Unix user object for a server's owner
sub get_domain_owner
{
local @users = &list_domain_users($_[0], 0, 0, 0);
local ($user) = grep { $_->{'user'} eq $_[0]->{'user'} } @users;
return $user;
}

# new_password_input(name)
# Returns HTML for a password selection field
sub new_password_input
{
local ($name) = @_;
if ($config{'passwd_mode'} == 1) {
	# Random but editable password
	return &ui_textbox($name, &random_password(), 40);
	}
elsif ($config{'passwd_mode'} == 0) {
	# One hidden password
	return &ui_password($name, undef, 40);
	}
elsif ($config{'passwd_mode'} == 2) {
	# Two hidden passwords
	return "<table>\n".
	       "<tr><td>$text{'form_passf'}</td> ".
	       "<td>".&ui_password($name, undef, 40)."</td> </tr>\n".
	       "<tr><td>$text{'form_passa'}</td> ".
	       "<td>".&ui_password($name."_again", undef, 40)."</td> </tr>\n".
	       "</table>";
	}
}

# parse_new_password(name, allow-empty)
# Returns the entered or randomly generated password
sub parse_new_password
{
local ($name, $empty) = @_;
$empty || $in{$name} =~ /\S/ || &error($text{'setup_epass'});
if (defined($in{$name."_again"}) && $in{$name} ne $in{$name."_again"}) {
	&error($text{'setup_epassagain'});
	}
return $in{$name};
}

# get_disable_features(&domain)
# Given a domain, returns a list of features that can be disabled for it
sub get_disable_features
{
local ($d) = @_;
local @disable;
@disable = grep { $d->{$_} && $config{$_} } split(/,/, $config{'disable'});
push(@disable, "ssl") if (&indexof("web", @disable) >= 0 && $d->{'ssl'});
push(@disable, "status") if (&indexof("web", @disable) >= 0 && $d->{'status'});
@disable = grep { $_ ne "unix" } @disable if ($d->{'parent'});
push(@disable, grep { $d->{$_} &&
	      &plugin_defined($_, "feature_disable") } @feature_plugins);
return &unique(@disable);
}

# get_enable_features(&domain)
# Given a domain, returns a list of features that should be enabled for it
sub get_enable_features
{
local ($d) = @_;
local @enable;
local @disabled = split(/,/, $d->{'disabled'});
local %disabled = map { $_, 1 } @disabled;
@enable = grep { $d->{$_} && ($config{$_} || $_ eq 'unix') } @disabled;
push(@enable, "ssl") if (&indexof("web", @enable) >= 0 && $d->{'ssl'});
@enable = grep { $_ ne "unix" } @enable if ($d->{'parent'});
push(@enable, grep { $d->{$_} && $disabled{$_} &&
		     &plugin_defined($_, "feature_enable") } @feature_plugins);
return &unique(@enable);
}

# sysinfo_virtualmin()
# Returns the OS info, Perl version and path
sub sysinfo_virtualmin
{
return ( [ $text{'sysinfo_os'}, "$gconfig{'real_os_type'} $gconfig{'real_os_version'}" ],
	 [ $text{'sysinfo_perl'}, $] ],
	 [ $text{'sysinfo_perlpath'}, &get_perl_path() ] );
}

# has_home_quotas()
# Returns 1 if home directory quotas are enabled
sub has_home_quotas
{
return 1 if (&has_quota_commands());
return $config{'home_quotas'} ? 1 : 0;
}

# has_mail_quotas()
# Returns 1 if mail directory quotas are enabled, and needed
sub has_mail_quotas
{
return 0 if (&has_quota_commands());
return $config{'mail_quotas'} &&
       $config{'mail_quotas'} ne $config{'home_quotas'} ? 1 : 0;
}

# has_server_quotas()
# Returns 1 if the system's mail server supports mail quotas
sub has_server_quotas
{
return $config{'mail'} && ($config{'mail_system'} == 4 ||
			   $config{'mail_system'} == 5);
}

# has_group_quotas()
# Returns 1 if group quotas are enabled
sub has_group_quotas
{
return 1 if (&has_quota_commands());
return $config{'group_quotas'} ? 1 : 0;
}

# has_quota_commands()
# Returns 1 if external quota commands are being used
sub has_quota_commands
{
return $config{'quota_commands'} ? 1 : 0;
}

# get_database_usage(&domain)
# Returns the number of bytes used by all this virtual server's databases. If
# called in a array context, database space already counted by the quota system
# is also returned.
sub get_database_usage
{
local ($d) = @_;
local $rv = 0;
local $qrv = 0;
foreach my $db (&domain_databases($d)) {
	local ($size, $qsize) = &get_one_database_usage($d, $db);
	$rv += $size;
	$qrv += $qsize;
	}
return wantarray ? ($rv, $qrv) : $rv;
}

# get_one_database_usage(&domain, &db)
# Returns the disk space used by one database, and the amount of space that
# is already counted by the quota system.
sub get_one_database_usage
{
local ($d, $db) = @_;
if (&indexof($db->{'type'}, @database_plugins) >= 0) {
	# Get size from plugin
	local ($size, $tables, $qsize) = &plugin_call($db->{'type'}, 
		      "database_size", $d, $db->{'name'}, 1);
	return ($size, $qsize);
	}
else {
	# Get size from core database
	local $szfunc = $db->{'type'}."_size";
	local ($size, $tables, $qsize) = &$szfunc($d, $db->{'name'}, 1);
	return ($size, $qsize);
	}
}

# find_quotas_job()
# Returns the Cron job used for regularly checking quotas
sub find_quotas_job
{
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $quotas_cron_cmd } @jobs;
return $job;
}

# need_config_check()
# Compares the current and previous configs, and returns 1 if a re-check is
# needed due to any checked option changing.
sub need_config_check
{
local @cst = stat($module_config_file);
return 0 if ($cst[9] <= $config{'last_check'});
local %lastconfig;
&read_file("$module_config_directory/last-config", \%lastconfig) || return 1;
foreach my $f (@features) {
	# A feature was enabled or disabled
	return 1 if ($config{$f} != $lastconfig{$f});
	}
foreach my $c ("mail_system", "generics", "append_style", "ldap_host",
	       "ldap_base", "ldap_login", "ldap_pass", "ldap_port", "ldap",
	       "vpopmail_dir", "vpopmail_user", "vpopmail_group",
	       "clamscan_cmd", "iface", "localgroup", "home_quotas",
	       "mail_quotas", "group_quotas", "quotas", "shell", "ftp_shell",
	       "all_namevirtual", "dns_ip", "default_procmail",
	       "compression", "suexec", "domains_group",
	       "quota_commands",
	       "quota_set_user_command", "quota_set_group_command",
	       "quota_list_users_command", "quota_list_groups_command",
	       "quota_get_user_command", "quota_get_group_command") {
	# Some important config option was changed
	return 1 if ($config{$c} ne $lastconfig{$c});
	}
foreach my $k (keys %config) {
	if ($k =~ /^avail_/ || $k eq 'leave_acl' || $k eq 'webmin_modules' ||
	    $k eq 'post_check') {
		# An option effecting Webmin users
		return 1 if ($config{$k} ne $lastconfig{$k});
		}
	}
return 0;
}

# update_secondary_groups(&domain, &users)
# After a user is saved, updated or deleted, update the secondary groups
# specified in it's template with the appropriate users.
sub update_secondary_groups
{
local ($dom, $users) = @_;
local $tmpl = &get_template($dom->{'template'});

# See if this feature is actually configured
my $any = 0;
foreach my $g ("mailgroup", "ftpgroup", "dbgroup") {
	local $gn = $tmpl->{$g};
	$any++ if ($gn && $gn ne "none");
	}
return 0 if (!$any);

# Get the current user and group lists
$users ||= [ &list_domain_users($dom) ];
local %indom = map { $_->{'user'}, 1 } @$users;
&require_useradmin();
local @groups = &list_all_groups();
local %gtaken;
&build_group_taken(\%gtaken, undef, \@groups);
local %taken;
&build_taken(undef, \%taken);

foreach my $g ("mailgroup", "ftpgroup", "dbgroup") {
	local $gn = $tmpl->{$g};
	next if (!$gn || $gn eq "none");
	local @inusers;

	# Work out who is in the group
	if ($g eq "mailgroup") {
		@inusers = grep { $_->{'unix'} && $_->{'email'} } @$users;
		}
	elsif ($g eq "ftpgroup") {
		@inusers = grep { $_->{'unix'} &&
				  $_->{'shell'} ne $config{'shell'} } @$users;
		}
	elsif ($g eq "dbgroup") {
		@inusers = grep { $_->{'unix'} && @{$_->{'dbs'}} > 0 } @$users;
		}
	local @innames = map { $_->{'user'} } @inusers;
	local %innames = map { $_, 1 } @innames;

	# Get the group
	local ($group) = grep { $_->{'group'} eq $gn } @groups;
	if ($group) {
		# Update the secondary members, removing any users who don't
		# exist or are in this domain but shouldn't be there.
		local @mems = split(/,/, $group->{'members'});
		@mems = grep { !($indom{$_} && !$innames{$_}) } @mems;
		@mems = &unique(@mems, @innames);
		@mems = grep { $taken{$_} } @mems;
		$group->{'members'} = join(",", @mems);
		&foreign_call($group->{'module'}, "modify_group",
			      $group, $group);
		}
	else {
		# Need to create!
		$group = { 'group' => $gn,
			   'gid' => &allocate_gid(\%gtaken),
			   'members' => join(",", @innames) };
		&foreign_call($usermodule, "create_group", $group);
		$gtaken{$group->{'gid'}} = 1;
		}
	}
}

# allowed_secondary_groups([&domain])
# Returns a list of secondary groups that users in some domain can belong to
sub allowed_secondary_groups
{
if ($_[0] && ($tmpl = &get_template($_[0]->{'template'})) &&
    $tmpl->{'othergroups'} && $tmpl->{'othergroups'} ne 'none') {
	return split(/\s+/, $tmpl->{'othergroups'});
	}
return ( );
}

# compression_format(file)
# Returns 0 if uncompressed, 1 for gzip, 2 for compress, 3 for bzip2 or
# 4 for zip, 5 for tar
sub compression_format
{
open(BACKUP, $_[0]);
local $two;
read(BACKUP, $two, 2);
close(BACKUP);
local $rv = $two eq "\037\213" ? 1 :
	     $two eq "\037\235" ? 2 :
	     $two eq "PK" ? 4 :
	     $two eq "BZ" ? 3 : 0;
if (!$rv) {
	# Fall back to 'file' command for tar
	local $out = &backquote_command("file ".quotemeta($_[0]));
	if ($out =~ /tar\s+archive/i) {
		$rv = 5;
		}
	}
return $rv;
}

# extract_compressed_file(file, destdir)
# Extracts the contents of some compressed file to the given directory. Returns
# undef if OK, or an error message on failure.
sub extract_compressed_file
{
local ($file, $dir) = @_;
local $format = &compression_format($file);
local @needs = ( undef,
		 [ "gunzip", "tar" ],
		 [ "uncompress", "tar" ],
		 [ "bunzip2", "tar" ],
		 [ "unzip" ],
		 [ "tar" ],
		);
foreach my $n (@{$needs[$format]}) {
	&has_command($n) || return &text('addstyle_ecmd', "<tt>$m</tt>");
	}
local ($qfile, $qdir) = ( quotemeta($file), quotemeta($dir) );
local @cmds = ( undef,
		"cd $qdir && gunzip -c $qfile | tar xf -",
		"cd $qdir && uncompress -c $qfile | tar xf -",
		"cd $qdir && bunzip2 -c $qfile | tar xf -",
		"cd $qdir && unzip $qfile",
		"cd $qdir && tar xf $qfile",
	       );
$cmds[$format] || return "Unknown compression format";
local $out = &backquote_command("($cmds[$format]) 2>&1 </dev/null");
return $? ? &text('addstyle_ecmdfailed',
		  "<tt>".&html_escape($out)."</tt>") : undef;
}

# lock_user_db()
# Take out a lock on all mailbox users. Should be called before performing
# any user-related options
sub lock_user_db
{
return &lock_file("$module_config_directory/userdb");
}

# unlock_user_db()
# Releases the lock take out by lock_user_db()
sub unlock_user_db
{
return &unlock_file("$module_config_directory/userdb");
}

# feature_links(&domain)
# Returns a list of links for editing specific features within a domain, such
# as the DNS zone, apache config and so on. Includes plugins.
sub feature_links
{
local ($d) = @_;
local @rv;

# Links provided by features, like editing DNS records
foreach my $f (@features) {
	if ($d->{$f}) {
		local $lfunc = "links_".$f;
		if (defined(&$lfunc)) {
			foreach my $l (&$lfunc($d)) {
				if (&foreign_available($l->{'mod'})) {
					push(@rv, $l);
					}
				}
			}
		}
	}

# Links provided by plugins, like Mailman mailing lists
foreach my $f (@plugins) {
	if ($d->{$f}) {
		foreach my $l (&plugin_call($f, "feature_links", $d)) {
			if (&foreign_available($l->{'mod'})) {
				$l->{'plugin'} = 1;
				push(@rv, $l);
				}
			}
		}
	foreach my $l (&plugin_call($f, "feature_always_links", $d)) {
		if (&foreign_available($l->{'mod'})) {
			$l->{'plugin'} = 2;
			push(@rv, $l);
			}
		}
	}

# Links to other Webmin modules, for domain owners
if (!&master_admin() && !&reseller_admin()) {
	local @ot;
	foreach my $k (keys %config) {
		if ($k =~ /^avail_(\S+)$/ && &indexof($1, @features) < 0 &&
					     &indexof($1, @plugins) < 0) {
			if (&foreign_available($1)) {
				local %minfo = &get_module_info($1);
				push(@ot, { 'mod' => $1,
					    'page' => 'index.cgi',
					    'desc' => $minfo{'desc'},
					    'cat' => 'webmin',
					    'other' => 1 });
				}
			}
		}
	@ot = sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @ot;
	push(@rv, @ot);
	}
return @rv;
}

# show_domain_buttons(&domain)
# Print all the buttons for actions that can be taken on a server
sub show_domain_buttons
{
local ($d) = @_;
local ($anyrow1, $anyrow2, $anyrow3);
print &ui_buttons_start();

# Get the actions and work out categories
local @buts = &get_domain_actions($d);
local @cats = &unique(map { $_->{'cat'} } @buts);

# Show by category
foreach my $c (@cats) {
	local @incat = grep { $_->{'cat'} eq $c } @buts;
	print &ui_buttons_hr($text{'cat_'.$c});
	foreach my $b (@incat) {
		print &ui_buttons_row($b->{'page'},
				      $b->{'title'},
				      $b->{'desc'},
				      &ui_hidden("dom", $d->{'id'})."\n".
				      join("\n", map { &ui_hidden($_->[0], $_->[1]) } @{$b->{'hidden'}}));
		}
	}

print &ui_buttons_end();
}

# get_domain_actions(&domain)
# Returns a list of actions that can be taken for some virtual server
sub get_domain_actions
{
local ($d) = @_;
local @rv;

if (&can_domain_have_users($d) && &can_edit_users()) {
	# Users button
	push(@rv, { 'page' => 'list_users.cgi',
		    'title' => $text{'edit_users2'},
		    'desc' => $text{'edit_usersdesc'},
		    'cat' => 'objects',
		    });
	}

if ($d->{'mail'} && $config{'mail'} && &can_edit_aliases()) {
	# Mail aliases button
	push(@rv, { 'page' => 'list_aliases.cgi',
		    'title' => $text{'edit_aliases'},
		    'desc' => $text{'edit_aliasesdesc'},
		    'cat' => 'objects',
		    });
	}

if (&database_feature($d) && &can_edit_databases()) {
	# MySQL and PostgreSQL DBs button
	push(@rv, { 'page' => 'list_databases.cgi',
		    'title' => $text{'edit_databases'},
		    'desc' => $text{'edit_databasesdesc'},
		    'cat' => 'objects',
		  });
	}

if ($d->{'web'} && $config{'web'} && &can_edit_scripts() &&
    !$d->{'subdom'} && !$d->{'alias'}) {
	# Scripts button
	push(@rv, { 'page' => 'list_scripts.cgi',
		    'title' => $text{'edit_scripts'},
		    'desc' => $text{'edit_scriptsdesc'},
		    'cat' => 'objects',
		  });
	}

if ($d->{'web'} && $config{'web'} && $d->{'dir'} && !$d->{'alias'} &&
    !$d->{'proxy_pass_mode'} &&
    $virtualmin_pro && &can_edit_html()) {
	# Edit web pages button
	push(@rv, { 'page' => 'edit_html.cgi',
		    'title' => $text{'edit_html'},
		    'desc' => $text{'edit_htmldesc'},
		    'cat' => 'objects',
		  });
	}

if (&can_rename_domains()) {
	# Rename domain button
	push(@rv, { 'page' => 'rename_form.cgi',
		    'title' => $text{'edit_rename'},
		    'desc' => $text{'edit_renamedesc'},
		    'cat' => 'server',
		  });
	}

if (&can_move_domain($d) && !$d->{'alias'} && !$d->{'subdom'}) {
	# Move sub-server to different owner, or turn parent into sub
	push(@rv, { 'page' => 'move_form.cgi',
		    'title' => $text{'edit_move'},
		    'desc' => $d->{'parent'} ? $text{'edit_movedesc2'}
					     : $text{'edit_movedesc'},
		    'cat' => 'server',
		  });
	}

if (&can_change_ip($d) && !$d->{'alias'}) {
	# Change IP / port button
	push(@rv, { 'page' => 'newip_form.cgi',
		    'title' => $text{'edit_newip'},
		    'desc' => $text{'edit_newipdesc'},
		    'cat' => 'server',
		  });
	}

local $parentdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
local $unixer = $parentdom || $d;
if (&can_create_sub_servers() && !$d->{'alias'} && $unixer->{'unix'}) {
	# Domain alias and sub-domain buttons
	local ($dleft, $dreason, $dmax) = &count_domains("realdoms");
	local ($aleft, $areason, $amax) = &count_domains("aliasdoms");
	if ($dleft != 0 && &can_create_sub_servers() &&
	    !$d->{'parent'}) {
		# Sub-server
		push(@rv, { 'page' => 'domain_form.cgi',
			    'title' => $text{'edit_subserv'},
			    'desc' => &text('edit_subservesc', $d->{'dom'}),
			    'hidden' => [ [ "parentuser1", $d->{'user'} ],
					  [ "add1", 1 ] ],
			    'cat' => 'create',
			  });
		}
	if ($aleft != 0) {
		# Alias domain 
		push(@rv, { 'page' => 'domain_form.cgi',
			    'title' => $text{'edit_alias'},
			    'desc' => $text{'edit_aliasdesc'},
			    'hidden' => [ [ "to", $d->{'id'} ] ],
			    'cat' => 'create',
			  });
		}
	if (!$d->{'subdom'} && $dleft != 0 && $virtualmin_pro &&
	    &can_create_sub_domains()) {
		# Sub-domain
		push(@rv, { 'page' => 'domain_form.cgi',
			    'title' => $text{'edit_subdom'},
			    'desc' => &text('edit_subdomdesc', $d->{'dom'}),
			    'hidden' => [ [ "parentuser1", $d->{'user'} ],
					  [ "add1", 1 ],
					  [ "subdom", $d->{'id'} ] ],
			    'cat' => 'create',
			  });
		}
	}

if ($d->{'ssl'} && $config{'ssl'} && $d->{'dir'} && &can_edit_ssl()) {
	# SSL options page button
	push(@rv, { 'page' => 'cert_form.cgi',
		    'title' => $text{'edit_cert'},
		    'desc' => $text{'edit_certdesc'},
		    'cat' => 'server',
		  });
	}

if ($d->{'unix'} && &can_edit_limits($d) && !$d->{'alias'}) {
	# Domain limits button
	push(@rv, { 'page' => 'edit_limits.cgi',
		    'title' => $text{'edit_limits'},
		    'desc' => $text{'edit_limitsdesc'},
		    'cat' => 'admin',
		  });
	}

if (!$d->{'parent'} && &can_edit_admins()) {
	# Extra admins buttons
	push(@rv, { 'page' => 'list_admins.cgi',
		    'title' => $text{'edit_admins'},
		    'desc' => $text{'edit_adminsdesc'},
		    'cat' => 'admin',
		  });
	}

if (!$d->{'parent'} && $d->{'webmin'} && &can_switch_user($d)) {
	# Button to switch to the domain's admin
	push(@rv, { 'page' => 'switch_user.cgi',
		    'title' => $text{'edit_switch'},
		    'desc' => $text{'edit_switchdesc'},
		    'cat' => 'admin',
		    'target' => '_top',
		  });
	}

if ($d->{'web'} && $config{'web'} && !$d->{'alias'} && &can_edit_forward()) {
	# Proxying / frame forwward configuration button
	local $mode = $d->{'proxy_pass_mode'} || $config{'proxy_pass'};
	local $psuffix = $mode == 2 ? "frame" : "proxy";
	push(@rv, { 'page' => $psuffix.'_form.cgi',
		    'title' => $text{'edit_'.$psuffix},
		    'desc' => $text{'edit_'.$psuffix.'desc'},
		    'cat' => 'server',
		  });
	}

if (&has_proxy_balancer($d) && &can_edit_forward()) {
	# Proxy balance editor
	push(@rv, { 'page' => 'list_balancers.cgi',
		    'title' => $text{'edit_balancer'},
		    'desc' => $text{'edit_balancerdesc'},
		    'cat' => 'server',
		  });
	}

if (($d->{'spam'} && $config{'spam'} ||
     $d->{'virus'} && $config{'virus'}) && &can_edit_spam()) {
	# Spam/virus delivery button
	push(@rv, { 'page' => 'edit_spam.cgi',
		    'title' => $text{'edit_spamvirus'},
		    'desc' => $text{'edit_spamvirusdesc'},
		    'cat' => 'server',
		  });
	}

if ($d->{'web'} && $config{'web'} && &can_edit_phpmode()) {
	# PHP execution mode button
	push(@rv, { 'page' => 'edit_phpmode.cgi',
		    'title' => $text{'edit_phpmode'},
		    'desc' => $text{'edit_phpmodedesc'},
		    'cat' => 'server',
		  });
	}

if ($d->{'web'} && &can_edit_phpver() &&
    defined(&list_available_php_versions)) {
	# PHP directory versions button
	local @avail = &list_available_php_versions($d);
	if (@avail > 1) {
		push(@rv, { 'page' => 'edit_phpver.cgi',
			    'title' => $text{'edit_phpver'},
			    'desc' => $text{'edit_phpverdesc'},
			    'cat' => 'server',
			  });
		}
	}

if ($d->{'dns'} && !$d->{'dns_submode'} && $config{'dns'}) {
	# SPF settings button
	push(@rv, { 'page' => 'edit_spf.cgi',
		    'title' => $text{'edit_spf'},
		    'desc' => $text{'edit_spfdesc'},
		    'cat' => 'server',
		  });
	}

# Button to show bandwidth graph
if ($config{'bw_active'} && !$d->{'parent'} && &can_monitor_bandwidth($d)) {
	push(@rv, { 'page' => 'bwgraph.cgi',
		    'title' => $text{'edit_bwgraph'},
		    'desc' => $text{'edit_bwgraphdesc'},
		    'cat' => 'logs',
		  });
	}

# Button to show disk usage
if ($d->{'dir'} && !$d->{'parent'} && $virtualmin_pro) {
	push(@rv, { 'page' => 'usage.cgi',
		    'title' => $text{'edit_usage'},
		    'desc' => $text{'edit_usagehdesc'},
		    'cat' => 'admin',
		  });
	}

# Button to re-send signup email
if (!$d->{'alias'} && &can_config_domain($d) && $virtualmin_pro) {
	push(@rv, { 'page' => 'reemail.cgi',
		    'title' => $text{'edit_reemail'},
		    'desc' => &text('edit_reemaildesc',
                                    "<tt>$d->{'emailto'}</tt>"),
		    'cat' => 'admin',
		  });
	}

# Button to show mail logs
if ($virtualmin_pro && $config{'mail'} && $config{'mail_system'} <= 1 &&
    &can_view_maillog($d) && $d->{'mail'}) {
	push(@rv, { 'page' => 'maillog.cgi',
		    'title' => $text{'edit_maillog'},
		    'desc' => $text{'edit_maillogdesc'},
		    'cat' => 'logs',
		  });
	}

# Buttons to backup and restore this server
local $cb = &can_backup_domain($d);
if (!$d->{'alias'} && $cb) {
	# Users can backup their domains
	push(@rv, { 'page' => 'backup_form.cgi',
		    'title' => $text{'edit_backup'},
		    'desc' => $cb == 1 ? $text{'edit_backupdesc'}
				       : $text{'edit_backupdesc2'},
		    'cat' => 'backup',
		  });

	if ($cb == 1) {
		# Restore is only available to the master admin
		push(@rv, { 'page' => 'restore_form.cgi',
			    'title' => $text{'edit_restore'},
			    'desc' => $text{'edit_restoredesc'},
			    'cat' => 'backup',
			  });
		}
	}
if (!$d->{'alias'} && &can_edit_exclude()) {
	# Anyone can edit excludes
	push(@rv, { 'page' => 'edit_exclude.cgi',
		    'title' => $text{'edit_exclude'},
		    'desc' => $text{'edit_excludedesc'},
		    'cat' => 'backup',
		  });
	}

if (&can_disable_domain($d)) {
	# Enabled or disable buttons
	if ($d->{'disabled'}) {
		push(@rv, { 'page' => 'enable_domain.cgi',
			    'title' => $text{'edit_enable'},
			    'desc' => $text{'edit_enabledesc'},
			    'cat' => 'delete',
			  });
		}
	else {
		push(@rv, { 'page' => 'disable_domain.cgi',
			    'title' => $text{'edit_disable'},
			    'desc' => $text{'edit_disabledesc'},
			    'cat' => 'delete',
			  });
		}
	}

if (&can_delete_domain($d)) {
	# Delete domain button
	push(@rv, { 'page' => 'delete_domain.cgi',
		    'title' => $text{'edit_delete'},
		    'desc' => $text{'edit_deletedesc'},
		    'cat' => 'delete',
		  });
	}

if (!&can_config_domain($d)) {
	# Change password button
	push(@rv, { 'page' => 'edit_pass.cgi',
		    'title' => $text{'edit_changepass'},
		    'desc' => $text{'edit_changepassdesc'},
		    'cat' => 'server',
		  });
	}

return @rv;
}

# domain_footer_link(&domain)
# Returns a link and text suitable for the footer function
sub domain_footer_link
{
local $base = "$gconfig{'webprefix'}/$module_name";
return &can_config_domain($_[0]) ?
	( "$base/edit_domain.cgi?dom=$_[0]->{'id'}", $text{'edit_return'} ) :
	( "$base/view_domain.cgi?dom=$_[0]->{'id'}", $text{'view_return'} );
}

# domain_redirect(&domain)
# Calls redirect to edit_domain.cgi or view_domain.cgi
sub domain_redirect
{
&redirect("$gconfig{'webprefix'}/$module_name/postsave.cgi?dom=$_[0]->{'id'}");
#&redirect(&can_config_domain($_[0]) ? "edit_domain.cgi?dom=$_[0]->{'id'}"
#				    : "view_domain.cgi?dom=$_[0]->{'id'}");
}

# get_template_pages()
# Returns three array references, for template/reseller/etc links, titles
# and icons
sub get_template_pages
{
local @tmpls = ( 'tmpl', 'user', 'update',
   $config{'localgroup'} ? ( 'local' ) : ( ),
   'bw', 'plugin',
   $virtualmin_pro ? ( 'fields', 'links', 'ips', 'sharedips', 'dynip', 'resels',
		       'reseller', 'notify', 'scripts', 'styles' )
		   : ( 'sharedips', 'dynip' ),
   &has_home_quotas() && $virtualmin_pro ? ( 'quotas' ) : ( ),
#   &can_show_history() ? ( 'history' ) : ( ),
   $virtualmin_pro ? ( 'mxs', 'validate' ) : ( ),
   &has_home_quotas() && !&has_quota_commands() ? ( 'quotacheck' ) : ( ),
   $virtualmin_pro ? ( ) : ( 'upgrade' ),
   );
local %nonew = ( 'history', 1 );
local @tlinks = map { $nonew{$_} ? "history.cgi"
			         : "edit_new${_}.cgi" } @tmpls;
local @ttitles = map { $nonew{$_} ? $text{"${_}_title"} 
			          : $text{"new${_}_title"} } @tmpls;
local @ticons = map { $nonew{$_} ? "images/${_}.gif"
			         : "images/new${_}.gif" } @tmpls;
return (\@tlinks, \@ttitles, \@ticons);
}

# get_startstop_links([live])
# Returns a list of status objects for relevant features and plugins
sub get_startstop_links
{
local ($live) = @_;
local @rv;
local %typestatus;
#if (&foreign_check("status")) {
#	# Get scheduled monitoring status (Disabled due to inaccuracy)
#	&foreign_require("status", "status-lib.pl");
#	local %oldstatus;
#	if ($status::config{'sched_mode'} &&
#	    &read_file($status::oldstatus_file, \%oldstatus)) {
#		# Can use scheduled status
#		foreach my $s (&status::list_services()) {
#			local $stat = &status::expand_oldstatus(
#					$oldstatus{$s->{'id'}});
#			$typestatus{$s->{'type'}} = $stat->{'*'};
#			}
#		}
#	}
foreach my $f (@startstop_features) {
	if ($config{$f}) {
		local $sfunc = "startstop_".$f;
		foreach my $status (&$sfunc(\%typestatus)) {
			$status->{'feature'} ||= $f;
			push(@rv, $status);
			}
		}
	}
foreach my $f (@startstop_plugins) {
	local $status = &plugin_call($f, "feature_startstop");
	$status->{'feature'} ||= $f;
	$status->{'plugin'} = 1;
	push(@rv, $status);
	}
return @rv;
}

# can_domain_have_users(&domain)
# Returns 1 if the given domain can have mail/FTP/DB users
sub can_domain_have_users
{
local ($d) = @_;
return 0 if ($d->{'alias'} || $d->{'subdom'});	# never allowed for aliases
if (!$d->{'mail'}) {
	# Qmail+LDAP and VPOPMail require mail to be enabled
	return 0 if ($config{'mail_system'}==4 || $config{'mail_system'}==5);
	}
if (!$d->{'dir'}) {
	# Only VPOPMail allows mail without a dir
	return 0 if ($config{'mail_system'} != 5);
	}
return 1;
}

# call_feature_func(feature, &domain, &olddomain)
# Calls the appropriate function to enable or disable a feature for a domain
sub call_feature_func
{
local ($f, $d, $oldd) = @_;
if (&indexof($f, @features) >= 0 && $config{$f}) {
	# A core feature
	local $sfunc = "setup_$f";
	local $dfunc = "delete_$f";
	local $mfunc = "modify_$f";
	if ($d->{$f} && !$oldd->{$f}) {
		# Setup some feature
		if (!&try_function($f, $sfunc, $d)) {
			$d->{$f} = 0;
			}
		}
	elsif (!$d->{$f} && $oldd->{$f}) {
		# Delete some feature
		if (!&try_function($f, $dfunc, $d)) {
			$d->{$f} = 1;
			}
		}
	elsif ($d->{$f}) {
		# Modify some feature
		&try_function($f, $mfunc, $d, $oldd);
		}
	}
elsif (&indexof($f, @feature_plugins) >= 0) {
	# A plugin feature
	if ($d->{$f} && !$oldd->{$f}) {
		&plugin_call($f, "feature_setup", $d);
		}
	elsif (!$d->{$f} && $oldd->{$f}) {
		&plugin_call($f, "feature_delete", $d);
		}
	elsif ($d->{$f}) {
		&plugin_call($f, "feature_modify", $d, $oldd);
		}
	}
}

# domain_features(&dom)
# Returns a list of possible core features for a domain
sub domain_features
{
local ($d) = @_;
return $d->{'alias'} ? @alias_features :
	$d->{'parent'} ? ( grep { $_ ne "webmin" } @features ) :
		         @features;
}

# list_mx_servers()
# Returns the objects for servers used as secondary MXs
sub list_mx_servers
{
if (&foreign_check("servers")) {
	&foreign_require("servers", "servers-lib.pl");
	local %servers = map { $_->{'id'}, $_ } &servers::list_servers();
	local @rv;
	foreach my $idname (split(/\s+/, $config{'mx_servers'})) {
		my ($id, $name) = split(/=/, $idname);
		local $s = $servers{$id};
		if ($s) {
			$s->{'mxname'} = $name;
			push(@rv, $s);
			}
		}
	return @rv;
	}
return ();
}

# save_mx_servers(&servers)
# Update the list of servers to create secondary MXs on
sub save_mx_servers
{
local ($servers) = @_;
$config{'mx_servers'} =
    join(" ", map { $_->{'mxname'} ? $_->{'id'}."=".$_->{'mxname'}
				   : $_->{'id'} } @$servers);
&save_module_config();
}

# shorten_domain_name(&dom)
# Returns a domain name shorten to the display max
sub shorten_domain_name
{
local ($d) = @_;
local $show = $d->{'showdom'} || $d->{'dom'};
local $rv;
if ($config{'name_max'} && length($show) > $config{'name_max'}) {
	# Show first and last max/2 chars, with ... between
	local $s = int($config{'name_max'} / 2);
	$rv = substr($show, 0, $s)."...".substr($show, -$s);
	}
else {
	$rv = $show;
	}
$rv =~ s/ /&nbsp;/g;
return $rv;
}

# change_home_directory(&domain, newhome)
# Updates the home directory and anything that refers to it in a domain object
sub change_home_directory
{
local ($d, $newhome) = @_;
local $oldhome = $d->{'home'};
$d->{'home'} = $newhome;
foreach my $k (keys %$d) {
	if ($k ne "home") {
		$d->{$k} =~ s/$oldhome/$newhome/g;
		}
	}
}

# move_virtual_server(&domain, &parent)
# Moves some virtual server so that it is now owned by the new parent domain
sub move_virtual_server
{
local ($d, $parent) = @_;
local $oldd = { %$d };
local $oldparent;
if ($d->{'parent'}) {
	$oldparent = &get_domain($d->{'parent'});
	}

# Run the before command
&set_domain_envs($oldd, "MODIFY_DOMAIN");
local $merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));
&setup_for_subdomain($parent);

# Update the domain object with new home directory and parent details
local (@doms, @olddoms);
&set_parent_attributes($d, $parent);
&change_home_directory($d, &server_home_directory($d, $parent));
push(@doms, $d);
push(@olddoms, $oldd);

if (!$d->{'parent'}) {
	# If this is a parent domain, all of it's children need to be
	# re-parented too. This will also catch any aliases and sub-domains
	local @subs = &get_domain_by("parent", $d->{'id'});
	foreach my $sd (@subs) {
		local $oldsd = { %$sd };
		&set_parent_attributes($sd, $parent);
		&change_home_directory($sd,
				       &server_home_directory($sd, $parent));
		push(@doms, $sd);
		push(@olddoms, $oldsd);
		}
	}
else {
	# Find any alias domains that also need to be re-parented. Also find
	# any sub-domains
	local @aliases = &get_domain_by("alias", $d->{'id'});
	local @subdoms = &get_domain_by("subdoms", $d->{'id'});
	foreach my $ad (@aliases, @subdoms) {
		local $oldad = { %$ad };
		&set_parent_attributes($ad, $parent);
		&change_home_directory($ad,
				       &server_home_directory($ad, $parent));
		push(@doms, $ad);
		push(@olddoms, $oldad);
		}
	}

# Setup print function to include domain name
sub first_html_withdom_move
{
&$old_first_print(&text('rename_dd', $doing_dom->{'dom'})," : ",@_);
}
local $old_first_print;
local $doing_dom;
if (@doms > 1) {
	$old_first_print = $first_print;
	$first_print = \&first_html_withdom_move;
	}

# Update all features in all domains
my $f;
local %vital = map { $_, 1 } @vital_features;
foreach $f (@features) {
	local $mfunc = "modify_$f";
	for(my $i=0; $i<@doms; $i++) {
		if ($doms[$i]->{$f} && ($config{$f} || $f eq "unix")) {
			$doing_dom = $doms[$i];
			local $main::error_must_die = 1;
			eval {
				if ($doms[$i]->{'alias'}) {
					# Is an alias domain, so pass in old
					# and new target domain objects
					local $aliasdom = &get_domain(
						$doms[$i]->{'alias'});
					local $idx = &indexof($aliasdom, @doms);
					if ($idx >= 0) {
						&$mfunc(
						   $doms[$i], $olddoms[$i],
						   $doms[$idx], $olddoms[$idx]);
						}
					else {
						&$mfunc(
						   $doms[$i], $olddoms[$i],
						   $aliasdom, $aliasdom);
						}
					}
				else {
					# Not an alias domain
					&$mfunc($doms[$i], $olddoms[$i]);
					}

				if (($f eq "unix" || $f eq "webmin") &&
				    $doms[$i]->{'parent'}) {
					# Disable feature, since the user
					# will no longer exist
					$doms[$i]->{$f} = 0;
					}
				};
			if ($@) {
				&$second_print(&text('setup_failure',
					$text{'feature_'.$f}, $@));
				if ($vital{$f}) {
					# A vital feature failed .. give up
					return 0;
					}
				}
			}
		}
	}
foreach $f (@feature_plugins) {
	for(my $i=0; $i<@doms; $i++) {
		if ($doms[$i]->{$f}) {
			$doing_dom = $doms[$i];
			&plugin_call($f, "feature_modify", $doms[$i], $olddoms[$i]);
			}
		}
	}

# Update old and new Webmin users
$first_print = $old_first_print if ($old_first_print);
&modify_webmin($parent, $parent);
if ($oldparent) {
	&modify_webmin($oldparent, $oldparent);
	}

&run_post_actions();

# Save the domain objects
&$first_print($text{'save_domain'});
for(my $i=0; $i<@doms; $i++) {
        &save_domain($doms[$i]);
        }
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN");
&made_changes();
&reset_domain_envs($d);

return 1;
}

# reparent_virtual_server(&domain, newuser, newpass)
# Converts an existing sub-server into a new parent server
sub reparent_virtual_server
{
local ($d, $newuser, $newpass) = @_;
local $oldd = { %$d };
local $oldparent = &get_domain($d->{'parent'});

# Run the before command
&set_domain_envs($oldd, "MODIFY_DOMAIN");
local $merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Update the domain object with a new top-level home directory and it's
# own user and group
local (@doms, @olddoms);
$d->{'parent'} = undef;
$d->{'user'} = $newuser;
$d->{'group'} = $newuser;
$d->{'pass'} = $newpass;
local (%gtaken, %taken);
&build_group_taken(\%gtaken);
&build_taken(\%taken);
$d->{'uid'} = &allocate_uid(\%taken);
$d->{'gid'} = &allocate_gid(\%gtaken);
$d->{'ugid'} = $d->{'gid'};
&change_home_directory($d, &server_home_directory($d));
push(@doms, $d);
push(@olddoms, $oldd);

# Copy all quotas and limits from the old parent
$d->{'quota'} = $oldparent->{'quota'};
$d->{'uquota'} = $oldparent->{'uquota'};
$d->{'bwlimit'} = $oldparent->{'bwlimit'};
foreach my $l (@limit_types) {
	$d->{$l} = $oldparent->{$l};
	}
$d->{'nodbname'} = $oldparent->{'nodbname'};
$d->{'norename'} = $oldparent->{'norename'};
$d->{'forceunder'} = $oldparent->{'forceunder'};
foreach my $ed (@edit_limits) {
	$d->{'edit_'.$ed} = $oldparent->{'edit_'.$ed};
	}
foreach my $f (@opt_features, "virt", @feature_plugins) {
	$d->{'limit_'.$f} = $oldparent->{'limit_'.$f};
	}
$d->{'demo'} = $oldparent->{'demo'};
$d->{'webmin_modules'} = $oldparent->{'webmin_modules'};

# Find any alias domains that also need to be re-parented. Also find
# any sub-domains
local @aliases = &get_domain_by("alias", $d->{'id'});
local @subdoms = &get_domain_by("subdoms", $d->{'id'});
foreach my $ad (@aliases, @subdoms) {
	local $oldad = { %$ad };
	&set_parent_attributes($ad, $d);
	&change_home_directory($ad,
			       &server_home_directory($ad, $d));
	push(@doms, $ad);
	push(@olddoms, $oldad);
	}

# Setup print function to include domain name
sub first_html_withdom_reparent
{
&$old_first_print(&text('rename_dd', $doing_dom->{'dom'})," : ",@_);
}
local $old_first_print;
local $doing_dom;
if (@doms > 1) {
	$old_first_print = $first_print;
	$first_print = \&first_html_withdom_reparent;
	}

# Update all features in all domains
my $f;
local %vital = map { $_, 1 } @vital_features;
foreach $f (@features) {
	local $mfunc = "modify_$f";
	for(my $i=0; $i<@doms; $i++) {
		if ($doms[$i]->{$f} && ($config{$f} || $f eq "unix")) {
			$doing_dom = $doms[$i];
			local $main::error_must_die = 1;
			eval {
				if ($doms[$i]->{'alias'}) {
					# Is an alias domain, so pass in old
					# and new target domain objects
					local $aliasdom = &get_domain(
						$doms[$i]->{'alias'});
					local $idx = &indexof($aliasdom, @doms);
					if ($idx >= 0) {
						&$mfunc(
						   $doms[$i], $olddoms[$i],
						   $doms[$idx], $olddoms[$idx]);
						}
					else {
						&$mfunc(
						   $doms[$i], $olddoms[$i],
						   $aliasdom, $aliasdom);
						}
					}
				else {
					# Not an alias domain
					&$mfunc($doms[$i], $olddoms[$i]);
					}
				};
			if ($@) {
				&$second_print(&text('setup_failure',
					$text{'feature_'.$f}, $@));
				if ($vital{$f}) {
					# A vital feature failed .. give up
					return 0;
					}
				}
			}

		# Turn on the Unix and Webmin features
		if ($doms[$i] eq $d && ($f eq "unix" || $f eq "webmin")) {
			$doms[$i]->{$f} = 1;
			local $sfunc = "setup_$f";
			&try_function($f, $sfunc, $doms[$i]);
			}
		}
	}
foreach $f (@feature_plugins) {
	for(my $i=0; $i<@doms; $i++) {
		if ($doms[$i]->{$f}) {
			$doing_dom = $doms[$i];
			&plugin_call($f, "feature_modify", $doms[$i], $olddoms[$i]);
			}
		}
	}

# Update old Webmin user
$first_print = $old_first_print if ($old_first_print);
&modify_webmin($oldparent, $oldparent);

&run_post_actions();

# Save the domain objects
&$first_print($text{'save_domain'});
for(my $i=0; $i<@doms; $i++) {
        &save_domain($doms[$i]);
        }
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN");
&made_changes();
&reset_domain_envs($d);

return 1;
}

# set_parent_attributes(&domain, &parent)
# Update a domain object with attributes inherited from the parent
sub set_parent_attributes
{
local ($d, $parent) = @_;
$d->{'parent'} = $parent->{'id'};
$d->{'user'} = $parent->{'user'};
$d->{'group'} = $parent->{'group'};
$d->{'uid'} = $parent->{'uid'};
$d->{'gid'} = $parent->{'gid'};
$d->{'ugid'} = $parent->{'ugid'};
$d->{'pass'} = $parent->{'pass'};
$d->{'mysql_user'} = $parent->{'mysql_user'};
$d->{'postgres_user'} = $parent->{'postgres_user'};
$d->{'email'} = $parent->{'email'};
}

# check_virtual_server_config()
# Validates the Virtualmin configuration, printing out messages as it goes.
# Returns undef on success, or an error message on failure.
sub check_virtual_server_config
{
local $clink = "../config.cgi?$module_name";

# Make sure networking is supported
if (!&foreign_check("net")) {
	&foreign_require("net", "net-lib.pl");
	if (!defined(&net::boot_interfaces)) {
		return &text('index_enet');
		}
	&$second_print($text{'check_netok'});
	}

if ($config{'dns'}) {
	# Make sure BIND is installed
	&foreign_installed("bind8", 1) == 2 ||
		return &text('index_ebind', "/bind8/", $clink);

	# Make sure this server is configured to use the local BIND
	if (&foreign_check("net") && $config{'dns_check'}) {
		&foreign_require("net", "net-lib.pl");
		local %ips = map { $_->{'address'}, $_ }
				 &net::active_interfaces();
		local $dns = &net::get_dns_config();
		local $hasdns;
		foreach my $ns (@{$dns->{'nameserver'}}) {
			$hasdns++ if ($ips{&to_ipaddress($ns)} ||
				      $ns eq "127.0.0.1" ||
				      $ns eq "0.0.0.0");
			}
		if (!$hasdns) {
			return &text('check_eresolv', '/net/list_dns.cgi',
						      $clink);
			}
		&$second_print($text{'check_dnsok'});
		}
	else {
		&$second_print($text{'check_dnsok2'});
		}
	}

if ($config{'mail'}) {
	if ($config{'mail_system'} == 3) {
		# Work out which mail server we have
		if (&postfix_installed()) {
			$config{'mail_system'} = 0;
			}
		elsif (&qmail_vpopmail_installed()) {
			$config{'mail_system'} = 5;
			}
		elsif (&qmail_ldap_installed()) {
			$config{'mail_system'} = 4;
			}
		elsif (&qmail_installed()) {
			$config{'mail_system'} = 2;
			}
		elsif (&sendmail_installed()) {
			$config{'mail_system'} = 1;
			}
		else {
			return &text('index_email');
			}
		&$second_print(&text('check_detected', &mail_system_name()));
		&save_module_config();
		}
	local $expected_mailboxes;
	if ($config{'mail_system'} == 1) {
		# Make sure sendmail is installed
		if (!&sendmail_installed()) {
			return &text('index_esendmail', '/sendmail/',
					   "../config.cgi?$module_name");
			}
		# Check that aliases and virtusers are configured
		&require_mail();
		@$sendmail_afiles ||
			return &text('index_esaliases', '/sendmail/');
		$sendmail_vdbm ||
			return &text('index_esvirts', '/sendmail/');
		if ($config{'generics'}) {
			$sendmail_gdbm ||
		    		return &text('index_esgens',
					     '/sendmail/', $clink);
			}
		&$second_print($text{'check_sendmailok'});
		$expected_mailboxes = 1;
		}
	elsif ($config{'mail_system'} == 0) {
		# Make sure postfix is installed
		if (!&postfix_installed()) {
			return &text('index_epostfix', '/postfix/',
					   "../config.cgi?$module_name");
			}
		# Check that aliases and virtusers are configured
		&require_mail();
		@$postfix_afiles ||
			return &text('index_epaliases', '/postfix/');
		$virtual_maps =~ /^[a-z0-9]+:\//i ||
			return &text('index_epvirts', '/postfix/');
		if ($config{'generics'}) {
			$canonical_maps ||
				return &text('index_epgens',
					    '/postfix/', $clink);
			}
		&$second_print($text{'check_postfixok'});
		$expected_mailboxes = 0;
		}
	elsif ($config{'mail_system'} == 2) {
		# Make sure qmail is installed
		if (!&qmail_installed()) {
			return &text('index_eqmail', '/qmailadmin/',
					   "../config.cgi?$module_name");
			}
		if ($config{'generics'}) {
			return &text('index_eqgens', $clink);
			}
		local $tmpl = &get_template(0);
		if ($tmpl->{'append_style'} == 6) {
			&$second_print($text{'check_qmailmode6'});
			}
		else {
			&$second_print($text{'check_qmailok'});
			}
		$expected_mailboxes = 2;
		}
	elsif ($config{'mail_system'} == 4) {
		# Make sure qmail with LDAP is installed
		if (!&qmail_ldap_installed()) {
			return &text('index_eqmailldap', '/qmailadmin/',
					   "../config.cgi?$module_name");
			}
		if ($config{'generics'}) {
			return &text('index_eqgens', $clink);
			}
		if (!gethostbyname($config{'ldap_host'})) {
			return &text('index_eqmailhost', $clink);
			}
		if (!$config{'ldap_base'}) {
			return &text('index_eqmailbase', $clink);
			}
		local $lerr = &connect_qmail_ldap(1);
		if (!ref($lerr)) {
			return &text('index_eqmailconn', $lerr, $clink);
			}
		&$second_print($text{'check_qmailldapok'});
		$expected_mailboxes = 4;
		}
	elsif ($config{'mail_system'} == 5) {
		# Make sure qmail with VPOPMail is installed
		if (!&qmail_vpopmail_installed()) {
			return &text('index_evpopmail', '/qmailadmin/',
					   "../config.cgi?$module_name");
			}
		if ($config{'generics'}) {
			return &text('index_eqgens', $clink);
			}
		&$second_print($text{'check_vpopmailok'});
		$expected_mailboxes = 5;
		}
	# Check that Read User Mail module agrees
	if (&foreign_check("mailboxes") && defined($expected_mailboxes)) {
		local %mconfig = &foreign_config("mailboxes");
		$mconfig{'mail_system'} == 3 ||
		    $mconfig{'mail_system'} == $expected_mailboxes ||
			return &text('index_emailboxessystem',
				     '/mailboxes/',
				     "../config.cgi?$module_name",
				     $text{'mail_system_'.$expected_mailboxes});
		}
	}

if ($config{'web'}) {
	# Make sure Apache is installed
	&foreign_installed("apache", 1) == 2 ||
		return &text('index_eapache', "/apache/", $clink);

	# Make sure needed Apache modules are active
	local $tmpl = &get_template(0);
	if ($tmpl->{'web_suexec'} && $apache::httpd_modules{'core'} >= 2.0 &&
	    !$apache::httpd_modules{'mod_suexec'}) {
		return &text('check_ewebsuexec');
		}
	if (!$apache::httpd_modules{'mod_actions'}) {
		return &text('check_ewebactions');
		}
	if ($tmpl->{'web_php_suexec'} == 2 &&
	    !$apache::httpd_modules{'mod_fcgid'}) {
		return $text{'tmpl_ephpmode2'};
		}

	&$second_print($text{'check_webok'});
	}

if ($config{'webalizer'}) {
	# Make sure Webalizer is installed, and that global directives are OK
	$config{'web'} || return &text('check_edepwebalizer', $clink);
	&foreign_installed("webalizer", 1) == 2 ||
		return &text('index_ewebalizer', "/webalizer/", $clink);
	&foreign_require("webalizer", "webalizer-lib.pl");
	local $conf = &webalizer::get_config();

	# This is not needed
	#$current = &webalizer::find_value("IncrementalName", $conf);
	#$history = &webalizer::find_value("HistoryName", $conf);
	#if ($current =~ /^\//) {
	#	&check_error(&text('check_current', "/webalizer/"));
	#	}
	#elsif ($history =~ /^\//) {
	#	&check_error(&text('check_history', "/webalizer/"));
	#	}

	&$second_print($text{'check_webalizerok'});
	}

if ($config{'ssl'}) {
	# Make sure openssl is installed, that Apache supports mod_ssl,
	# and that port 443 is in use
	$config{'web'} || return &text('check_edepssl', $clink);
	&has_command("openssl") ||
	    return &text('index_eopenssl', "<tt>openssl</tt>", $clink);

	&require_apache();
	local $conf = &apache::get_config();
	local @loads = &apache::find_directive_struct("LoadModule", $conf);
	local ($l, $hasmod);
	foreach $l (@loads) {
		$hasmod++ if ($l->{'words'}->[1] =~ /mod_ssl/);
		}
	local ($aver, $amods) = &apache::httpd_info();
	$hasmod++ if (&indexof("mod_ssl", @$amods) >= 0);
	$hasmod++ if ($apache::httpd_modules{'mod_ssl'});
	$hasmod ||
	    return &text('index_emodssl', "<tt>mod_ssl</tt>", $clink);

	local @listens = &apache::find_directive_struct("Listen", $conf);
	local $haslisten;
	foreach $l (@listens) {
		$haslisten++ if ($l->{'words'}->[0] =~ /^(\S+:)?$default_web_sslport$/);
		}
	local @ports = &apache::find_directive_struct("Port", $conf);
	foreach $l (@ports) {
		$haslisten++ if ($l->{'words'}->[0] == $default_web_sslport);
		}
	$haslisten ||
	    return &text('index_emodssl2', $default_web_sslport, $clink);
	&$second_print($text{'check_sslok'});
	}

if ($config{'mysql'}) {
	# Make sure MySQL is installed
	&foreign_installed("mysql", 1) == 2 ||
		return &text('index_emysql', "/mysql/", $clink);
	&$second_print($text{'check_mysqlok'});
	}

if ($config{'postgres'}) {
	# Make sure PostgreSQL is installed
	&foreign_installed("postgresql", 1) == 2 ||
		return &text('index_epostgres', "/postgresql/", $clink);
	&$second_print($text{'check_postgresok'});
	}

if ($config{'ftp'}) {
	# Make sure ProFTPd is installed, and that the ftp user exists
	&foreign_installed("proftpd", 1) == 2 ||
		return &text('index_eproftpd', "/proftpd/", $clink);
	local $err = &check_proftpd_template();
	$err && return &text('check_proftpd', $err);
	&$second_print($text{'check_ftpok'});
	}

if ($config{'logrotate'}) {
	# Make sure logrotate is installed
	&foreign_installed("logrotate", 1) == 2 ||
		return &text('index_elogrotate', "/logrotate/", $clink);
	&foreign_require("logrotate", "logrotate-lib.pl");
	local $ver = &logrotate::get_logrotate_version();
	$ver >= 3.6 ||
		return &text('index_elogrotatever', "/logrotate/",
				   $clink, $ver, 3.6);
	&$second_print($text{'check_logrotateok'});
	}

if ($config{'spam'}) {
	# Make sure SpamAssassin and procmail are installed
	&foreign_installed("spam", 1) == 2 ||
		return &text('index_espam', "/spam/", $clink);
	&foreign_installed("procmail", 1) == 2 ||
		return &text('index_eprocmail', "/procmail/", $clink);
	if (&mail_system_has_procmail()) {
		&$second_print($text{'check_spamok'});
		}
	else {
		&$second_print($text{'check_noprocmail'});
		}

	# Check for spamassassin call in /etc/procmailrc
	&require_spam();
	local @recipes = &procmail::get_procmailrc();
	foreach my $r (@recipes) {
		if ($r->{'action'} =~ /spamassassin|spamc/) {
			return &text('check_spamglobal',
				     "<tt>$procmail::procmailrc</tt>");
			}
		}
	}

if ($config{'virus'}) {
	# Make sure ClamAV is installed and working
	&full_clamscan_path() ||
		return &text('index_evirus', "<tt>$config{'clamscan_cmd'}</tt>", $clink);
	if ($config{'clamscan_cmd'} eq "clamdscan") {
		# Need clamd to be running
		&find_byname("clamd") || return $text{'check_eclamd'};
		}
	local $out = `$config{'clamscan_cmd'} - </dev/null 2>&1`;
	$? && return &text('index_evirusrun', "<tt>$config{'clamscan_cmd'}</tt>", "<pre>$out</pre>", $clink);
	&$second_print($text{'check_virusok'});
	}

if ($config{'status'}) {
	# Make sure scheduled status monitoring is enabled
	&foreign_check("status") ||
		return &text('index_estatus', "/status/", $clink);
	local %sconfig = &foreign_config("status");
	if ($sconfig{'sched_mode'}) {
		&$second_print($text{'check_statusok'});
		}
	else {
		&$second_print(&text('check_statussched',
			    "../status/edit_sched.cgi"));
		}
	}

# Check all plugins
foreach $p (@plugins) {
	if ($p eq "virtualmin-mysqluser") {
		return &text('check_emysqlplugin');
		}
	local $err = &plugin_call($p, "feature_check");
	if ($err) {
		return $err;
		}
	else {
		$pname = &plugin_call($p, "feature_name");
		&$second_print(&text('check_plugin', $pname));
		}
	}

if (!$config{'iface'}) {
	if (!&running_in_zone()) {
		# Work out the network interface automatically
		$config{'iface'} = &first_ethernet_iface();
		if (!$config{'iface'}) {
			return &text('index_eiface',
				     "/config.cgi?$module_name");
			}
		&save_module_config();
		}
	else {
		# In a zone, it is worked out as needed, as it changes!
		$config{'iface'} = undef;
		}
	}
if (!&running_in_zone()) {
	&$second_print(&text('check_ifaceok', "<tt>$config{'iface'}</tt>"));
	}

local $defip = &get_default_ip();
if (!$defip) {
	return &text('index_edefip', "../config.cgi?$module_name");
	}
else {
	&$second_print(&text('check_defip', $defip));
	}

# Make sure local group exists
if ($config{'localgroup'} && !defined(getgrnam($config{'localgroup'}))) {
	return &text('index_elocal', "<tt>$config{'localgroup'}</tt>",
			   "../config.cgi?$module_name");
	}

$config{'home_quotas'} = '';
$config{'mail_quotas'} = '';
$config{'group_quotas'} = '';
if ($config{'quotas'} && $config{'quota_commands'}) {
	# External commands are being used for quotas - make sure they exist! 
	foreach my $c ("set_user", "set_group", "list_users", "list_groups") {
		local $cmd = $config{"quota_".$c."_command"};
		$cmd && &has_command($cmd) || return $text{'check_e'.$c};
		}
	foreach my $c ("get_user", "get_group") {
		local $cmd = $config{"quota_".$c."_command"};
		!$cmd || &has_command($cmd) || return $text{'check_e'.$c};
		}
	&$second_print($text{'check_quotacommands'});
	}
elsif ($config{'quotas'}) {
	# Make sure quotas are enabled, and work out where they are needed
	local $qerr;
	&require_useradmin();
	if (!$home_base) {
		&$second_print("<b>",&text('index_ehomebase'),"</b>");
		}
	elsif (&running_in_zone()) {
		$qerr = &text('index_ezone');
		}
	else {
		&foreign_require("mount", "mount-lib.pl");
		local $mail_base = &simplify_path(&resolve_links(
				&mail_system_base()));
		local ($home_mtab, $home_fstab) = &mount_point($home_base);
		local ($mail_mtab, $mail_fstab) = &mount_point($mail_base);
		if (!$home_mtab) {
			&$second_print("<b>",&text('index_ehomemtab',
		    		"<tt>$home_base</tt>"),"</b>");
			}
		elsif (!$mail_mtab) {
			&$second_print("<b>",&text('index_emailmtab',
				"<tt>$mail_base</tt>"),"</b>");
			}
		else {
			# Check if quotas are enabled for home filesystem
			local $nohome;
			if (!($home_mtab->[4] = &quota::quota_can(
				$home_mtab, $home_fstab))%2 ||
			    !&quota::quota_now($home_mtab, $home_fstab)) {
				$nohome++;
				}
			else {
				if ($home_mtab->[4] >= 2) {
					# Group quotas are active too
					$config{'group_quotas'} = 1;
					}
				}

			if ($home_mtab->[0] eq $mail_mtab->[0]) {
				# Home and mail are the same filesystem
				if ($nohome) {
					# Neither are enabled
					$qerr = &text('index_equota2',
					    "<tt>$home_mtab->[0]</tt>",
					    "<tt>$home_base</tt>",
					    "<tt>$mail_base</tt>");
					}
				else {
					# Both are enabled
					$config{'home_quotas'} =
						$home_mtab->[0];
					$config{'mail_quotas'} =
						$home_mtab->[0];
					}
				}
			else {
				# Different .. so check mail too
				local $nomail;
				if (!($mail_mtab->[4] = &quota::quota_can(
					$mail_mtab, $mail_fstab)) ||
				    !&quota::quota_now($mail_mtab,
						       $mail_fstab)) {
					$nomail++;
					}
				if ($nohome) {
					$qerr = &text('index_equota3',
					    "<tt>$home_mtab->[0]</tt>",
					    "<tt>$home_base</tt>");
					}
				else {
					$config{'home_quotas'} =
						$home_mtab->[0];
					}
				if ($nomail) {
					$qerr = &text('index_equota4',
					    "<tt>$mail_mtab->[0]</tt>",
					    "<tt>$mail_base</tt>");
					}
				else {
					$config{'mail_quotas'} =
						$mail_mtab->[0];
					}
				}
			}
		}
	if ($qerr) {
		&$second_print($qerr);
		}
	elsif (!$config{'group_quotas'}) {
		&$second_print($text{'check_nogroup'});
		}
	else {
		&$second_print($text{'check_group'});
		}
	}
else {
	&$second_print($text{'check_noquotas'});
	}

# Check for FTP shells in /etc/shells
local $_;
open(SHELLS, "/etc/shells");
while(<SHELLS>) {
	s/\r|\n//g;
	s/#.*$//;
	$shells{$_}++;
	}
close(SHELLS);
if ($shells{$config{'shell'}}) {
	&$second_print(&text('check_eshell', "<tt>$config{'shell'}</tt>",
		    "<tt>/etc/shells</tt>"));
	}
if (!$shells{$config{'ftp_shell'}}) {
	&$second_print(&text('check_eftpshell', "<tt>$config{'ftp_shell'}</tt>",
		    "<tt>/etc/shells</tt>"));
	}

# Check for problem module config settings
if ($config{'all_namevirtual'} && $config{'dns_ip'}) {
	return &text('check_enamevirt', $clink);
	}

# Make sure LDAP module is set up, if selected
if ($config{'ldap'}) {
	&require_useradmin();
	local $ldap = &ldap_useradmin::ldap_connect(1);
	if (!ref($ldap)) {
		return &text('check_eldap', $ldap, $clink,
				   "../ldap-useradmin/");
		}
	else {
		&require_useradmin();
		if (!defined(&ldap_useradmin::list_users)) {
			return &text('check_eldap2', $clink, 1.164);
			}
		else {
			&$second_print(&text('check_ldap'));
			}
		}
	}

# Make sure needed compression programs are installed
if (!&has_command("tar")) {
	return &text('check_ebcmd', "<tt>tar</tt>");
	}
local @bcmds = $config{'compression'} == 0 ? ( "gzip", "gunzip" )
					   : ( "bzip2", "bunzip2" );
foreach my $bcmd (@bcmds) {
	if (!&has_command($bcmd)) {
		return &text('check_ebcmd', "<tt>$bcmd</tt>");
		}
	}
&$second_print(&text('check_bcmdok'));

# All looks OK .. save the config
$config{'last_check'} = time()+1;
$config{'disable'} =~ s/user/unix/g;	# changed since last release
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&write_file("$module_config_directory/last-config", \%config);

return undef;
}

# mount_point(dir)
# Returns both the mtab and fstab details for the parent mount for a directory
sub mount_point
{
local $dir = &resolve_links($_[0]);
local @mounts = &mount::list_mounts();
local @mounted = &mount::list_mounted();
@mounts = @mounted if (!@mounts);
foreach $m (sort { length($b->[0]) <=> length($a->[0]) } @mounted) {
	if ($dir eq $m->[0] || $m->[0] eq "/" ||
	    substr($dir, 0, length($m->[0])+1) eq "$m->[0]/") {
		local ($m2) = grep { $_->[0] eq $m->[0] } @mounts;
		if ($m2) {
			return ($m, $m2);
			}
		}
	}
print STDERR "Failed to find mount point for $dir\n";
return ( );
}

# show_template_basic(&tmpl)
# Outputs HTML for editing basic template options (like the name)
sub show_template_basic
{
local ($tmpl) = @_;

# Name of this template - only editable for custom templates
print &ui_table_row(&hlink($text{'tmpl_name'}, "template_name"),
		    $tmpl->{'standard'} ? $tmpl->{'name'} :
			&ui_textbox("name", $tmpl->{'name'}, 40));

# Who this template is suitable for
local @fors = ( );
foreach my $f ("parent", "sub", "alias", "users") {
	if ($tmpl->{'standard'} && $f ne "users") {
		if ($tmpl->{"for_".$f}) {
			push(@fors, $text{'tmpl_for_'.$f});
			}
		}
	else {
		push(@fors, &ui_checkbox("for_$f", 1,
			&hlink($text{'tmpl_for_'.$f}, "template_for_$f"),
			$tmpl->{"for_".$f}));
		}
	}
print &ui_table_row(&hlink($text{'tmpl_for'}, "template_for"),
		    join(" , ", @fors));

# Which resellers can use this template?
local @resels = $virtualmin_pro ? &list_resellers() : ( );
if (@resels) {
	print &ui_table_row(
		&hlink($text{'tmpl_resellers'}, "template_resellers"),
		&ui_radio("resellers_def", $tmpl->{'resellers'} eq "*" ? 1 :
					 $tmpl->{'resellers'} ? 0 : 2,
			[ [ 1, $text{'tmpl_resellers_all'} ],
			  [ 2, $text{'tmpl_resellers_none'} ],
			  [ 0, $text{'tmpl_resellers_sel'} ] ])."<br>\n".
		&ui_select("resellers", [ split(/\s+/, $tmpl->{'resellers'}) ],
			 [ map { [ $_->{'name'},
				   "$_->{'name'} ($_->{'acl'}->{'desc'})" ] }
			       @resels ], 5, 1));
	}
}

# parse_template_basic(&tmpl)
sub parse_template_basic
{
local ($tmpl) = @_;

if (!$tmpl->{'standard'}) {
	$in{'name'} || &error($text{'tmpl_ename'});
	$tmpl->{'name'} = $in{'name'};
	}

# Save for-use-by list
foreach my $f ($tmpl->{'standard'} ? ( "users" )
				   : ( "parent", "sub", "alias", "users" )) {
	$tmpl->{"for_".$f} = $in{"for_".$f};
	}

local @resels = $virtualmin_pro ? &list_resellers() : ( );
if (@resels) {
	# Save list of allowed resellers
	if ($in{'resellers_def'} == 1) {
		$tmpl->{'resellers'} = '*';
		}
	elsif ($in{'resellers_def'} == 2) {
		$tmpl->{'resellers'} = '';
		}
	else {
		$tmpl->{'resellers'} = join(" ", split(/\0/, $in{'resellers'}));
		}
	}
}

# show_template_plugins(&tmpl)
# Outputs HTML for editing emplate options from plugins
sub show_template_plugins
{
# Show plugin-specific template options
my $plugtmpl = "";
foreach my $f (@plugins) {
	if (&plugin_defined($f, "template_input")) {
		$plugtmpl .= &plugin_call($f, "template_input", $tmpl);
		}
	}
if ($plugtmpl) {
	print $plugtmpl;
	}
else {
	print &ui_table_row(undef, "<b>$text{'tmpl_noplugins'}</b>");
	}
}

# parse_template_plugins(&tmpl)
sub parse_template_plugins
{
local ($tmpl) = @_;

# Parse plugin options
foreach my $f (@plugins) {
        if (&plugin_defined($f, "template_parse")) {
		&plugin_call($f, "template_parse", $tmpl, \%in);
		}
	}
}


# show_template_virtualmin(&tmpl)
# Outputs HTML for editing core Virtualmin template options
sub show_template_virtualmin
{
local ($tmpl) = @_;

if ($virtualmin_pro) {
	# Automatic alias domain
	local @afields = ( "domalias", "domalias_type" );
	print &ui_table_row(&hlink($text{'tmpl_domalias'}, "template_domalias"),
		&none_def_input("domalias", $tmpl->{'domalias'},
				$text{'tmpl_aliasset'},
				undef, undef, $text{'no'}, \@afields)."\n".
		&ui_textbox("domalias", $tmpl->{'domalias'} eq "none" ? undef :
					$tmpl->{'domalias'}, 30));

	print &ui_table_row(&hlink($text{'tmpl_domalias_type'},
				   "template_domalias_type"),
		    &ui_radio("domalias_type", int($tmpl->{'domalias_type'}),
			      [ [ 0, $text{'tmpl_domalias_type0'} ],
				[ 1, $text{'tmpl_domalias_type1'} ] ]));
	}
}

# parse_template_virtualmin(&tmpl)
# Updates core Virtualmin template options from %in
sub parse_template_virtualmin
{
local ($tmpl) = @_;

# Parse automatic alias domain mode
$tmpl->{'domalias'} = &parse_none_def("domalias");
if ($in{'domalias_mode'} == 2) {
	$in{'domalias'} =~ /^[a-z0-9\.\-\_]+$/i ||
		&error($text{'tmpl_edomalias'});
	$tmpl->{'domalias_type'} = $in{'domalias_type'};
	}
}

# list_template_editmodes()
# Returns a list of available template sections for editing
sub list_template_editmodes
{
return grep { $sfunc = "show_template_".$_;
              defined(&$sfunc) &&
               ($config{$_} || !$isfeature{$_} || $_ eq 'mail') }
            @template_features;
}

# substitute_domain_template(string, &domain)
# Does $VAR substitution in a string for a given domain, pulling in
# PARENT_DOMAIN variables too
sub substitute_domain_template
{
local ($str, $d) = @_;
local %hash = %$d;
delete($hash{''});
if ($d->{'parent'}) {
	local $parent = &get_domain($d->{'parent'});
	foreach my $k (keys %$parent) {
		$hash{'parent_domain_'.$k} = $parent->{$k};
		}
	delete($hash{'parent_domain_'});
	}
return &substitute_template($str, \%hash);
}

# set_limits_from_template(&domain, &template)
# Set initial owner limits on a domain from the given template
sub set_limits_from_template
{
local ($d, $tmpl) = @_;
$d->{'quota'} = $tmpl->{'quota'} eq 'none' ? undef : $tmpl->{'quota'};
$d->{'uquota'} = $tmpl->{'uquota'} eq 'none' ? undef : $tmpl->{'uquota'};
$d->{'bw_limit'} = $tmpl->{'bwlimit'} eq 'none' ? undef : $tmpl->{'bwlimit'};
$d->{'mailboxlimit'} = $tmpl->{'mailboxlimit'} eq 'none' ? undef :
			$tmpl->{'mailboxlimit'};
$d->{'aliaslimit'} = $tmpl->{'aliaslimit'} eq 'none' ? undef :
			$tmpl->{'aliaslimit'};
$d->{'dbslimit'} = $tmpl->{'dbslimit'} eq 'none' ? undef :
			$tmpl->{'dbslimit'};
$d->{'domslimit'} = $tmpl->{'domslimit'} eq 'none' ? '*' :
			$tmpl->{'domslimit'};
$d->{'nodbname'} = $tmpl->{'nodbname'};
$d->{'norename'} = $tmpl->{'norename'};
$d->{'forceunder'} = $tmpl->{'forceunder'};
}

# set_featurelimits_from_template(&domain, &template)
# Updates a virtual server's limit_ variables based on either the enabled
# features or limits defined in the template.
sub set_featurelimits_from_template
{
local ($d, $tmpl) = @_;
if ($tmpl->{'featurelimits'} && $tmpl->{'featurelimits'} ne 'none') {
	# From template
	local %flimits = map { $_, 1 } split(/\s+/, $tmpl->{'featurelimits'});
	foreach my $f (@features, @feature_plugins) {
		$d->{'limit_'.$f} = int($flimits{$f});
		}
	}
else {
	# From domain
	foreach my $f (@features, @feature_plugins) {
		$d->{'limit_'.$f} = $f eq "webmin" ? 0 : int($d->{$f});
		}
	}
}

# set_capabilities_from_template(&domain, &template)
# Set initial owner editing capabilities on a domain from the given template
sub set_capabilities_from_template
{
local ($d, $tmpl) = @_;
if ($tmpl->{'capabilities'} ne 'none') {
	local %caps = map { $_, 1 } split(/\s+/, $tmpl->{'capabilities'});
	foreach my $ed (@edit_limits) {
		$d->{'edit_'.$ed} = $caps{$ed} ? 1 : 0;
		}
	}
}

# show_template_limits(&tmpl)
# Outputs HTML for editing limit-related template options
sub show_template_limits
{
local ($tmpl) = @_;

# Show default feature limits
local $ftable;
local %flimits = map { $_, 1 } split(/\s+/, $tmpl->{'featurelimits'});
$ftable .= &none_def_input("featurelimits", $tmpl->{'featurelimits'},
	   $text{'tmpl_below'}, 0, 0, $text{'tmpl_featauto'},
	   [ "featurelimits" ])."<br>\n";
local @grid;
foreach my $f (@opt_features, "virt") {
	push(@grid, &ui_checkbox("featurelimits", $f,
				 $text{'feature_'.$f} || $f,
				 $flimits{$f}));
	}
foreach my $f (@feature_plugins) {
	push(@grid, &ui_checkbox("featurelimits", $f,
			 &plugin_call($f, "feature_name"), $flimits{$f}));
	}
$ftable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'tmpl_featurelimits'},
			   "template_featurelimits"), $ftable);

print &ui_table_hr();

# Show limits on numbers of things
foreach my $l ("mailbox", "alias", "dbs", "doms", "bw") {
	my $limit = $tmpl->{$l.'limit'} eq "none" ? undef : $tmpl->{$l.'limit'};
	print &ui_table_row(&hlink($text{'tmpl_'.$l.'limit'},
				   "template_".$l."limit"),
	    &none_def_input($l.'limit', $tmpl->{$l.'limit'},
			    $text{'tmpl_atmost'}, undef, undef,
			    $text{'form_unlimit'}, [ $l.'limit' ])."\n".
	    ($l eq "bw" ? 
		&bandwidth_input($l.'limit', $limit, 1) :
		&ui_textbox($l.'limit', $limit, 10)));
	}

print &ui_table_hr();

# Show capabilities
local %caps = map { $_, 1 } split(/\s+/, $tmpl->{'capabilities'});
local $etable;
$etable .= &none_def_input("capabilities", $tmpl->{'capabilities'},
	   $text{'tmpl_below'}, 0, 0, $text{'tmpl_capauto'},
	   [ "capabilities" ])."<br>\n";
local @grid;
foreach my $ed (@edit_limits) {
	push(@grid, &ui_checkbox("capabilities", $ed,
				 $text{'limits_edit_'.$ed} || $ed,
				 $caps{$ed}));
	}
$etable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'tmpl_capabilities'},
			   "template_capabilities"), $etable);

print &ui_table_hr();

# Show rename and db name limits
foreach my $n ('nodbname', 'norename', 'forceunder') {
	print &ui_table_row(&hlink($text{'limits_'.$n}, 'limits_'.$n),
		&ui_radio($n, $tmpl->{$n},
			  [ $tmpl->{'default'} ? ( ) :
				( [ "", $text{'default'} ] ),
			    [ 0, $text{'yes'} ],
			    [ 1, $text{'no'} ] ]));
	}
}

# parse_template_limits(&tmpl)
# Updates limit-related template options from %in
sub parse_template_limits
{
local ($tmpl) = @_;

# Save feature limits
if ($in{'featurelimits_mode'} == 0) {
	# Determine automatically
	$tmpl->{'featurelimits'} = 'none';
	}
elsif ($in{'featurelimits_mode'} == 1) {
	# Default
	$tmpl->{'featurelimits'} = undef;
	}
else {
	# Explicitly selected
	$in{'featurelimits'} || &error($text{'tmpl_efeaturelimits'});
	$tmpl->{'featurelimits'} =
		join(" ", split(/\0/, $in{'featurelimits'}));
	}

# Save limits on various objects
foreach my $l ("mailbox", "alias", "dbs", "doms") {
	$tmpl->{$l.'limit'} = &parse_none_def($l.'limit');
	if ($in{$l."limit_mode"} == 2) {
		$in{$l.'limit'} =~ /^\d+$/ ||
			&error($text{'tmpl_e'.$l.'limit'});
		}
	}
if ($in{"bwlimit_mode"} == 0) {
	$tmpl->{'bwlimit'} = "none";
	}
elsif ($in{"bwlimit_mode"} == 1) {
	$tmpl->{'bwlimit'} = undef;
	}
else {
	$tmpl->{'bwlimit'} =
		&parse_bandwidth("bwlimit", $text{'tmpl_e'.$l.'limit'}, 1);
	}

# Save capability limits
if ($in{'capabilities_mode'} == 0) {
	# Determine automatically
	$tmpl->{'capabilities'} = 'none';
	}
elsif ($in{'capabilities_mode'} == 1) {
	# Default
	$tmpl->{'capabilities'} = undef;
	}
else {
	# Explicitly selected
	$tmpl->{'capabilities'} =
		join(" ", split(/\0/, $in{'capabilities'}));
	}

# Save no database name and no rename
$tmpl->{'nodbname'} = $in{'nodbname'};
$tmpl->{'norename'} = $in{'norename'};
$tmpl->{'forceunder'} = $in{'forceunder'};
}

# get_init_template(subdom)
# Returns the ID of the initially selected template
sub get_init_template
{
return $_[0] ? $config{'initsub_template'} : $config{'init_template'};
}

# set_chained_features(&domain)
# Updates a domain object, setting any features that are automatically based
# on another. Called from .cgi scripts to activate hidden features (mode 3).
sub set_chained_features
{
local ($d) = @_;
foreach my $f (@features) {
	if ($config{$f} == 3) {
		local $cfunc = "chained_$f";
		if (defined(&$cfunc)) {
			$d->{$f} = &$cfunc($d);
			}
		}
	}
}

# check_password_restrictions(&user)
# Returns an error if some user's password (from plainpass) is not acceptable
sub check_password_restrictions
{
local ($user) = @_;
&require_useradmin();
return &useradmin::check_password_restrictions(
	$user->{'plainpass'}, $user->{'user'});
}

# lock_domain_name(name)
# Obtain a lock on some domain name, to prevent concurrent creation
sub lock_domain_name
{
local ($name) = @_;
if (!-d $domainnames_dir) {
	&make_dir($domainnames_dir, 0755);
	}
&lock_file("$domainnames_dir/$name");
}

# show_domain_quota_usage(&domain)
# Prints ui_table fields for quota usage in a domain
sub show_domain_quota_usage
{
local ($d) = @_;
local ($tcount, $total) = (0, 0);

# Get usage for mail users and DBs in the domain
local ($homequota, $mailquota, $duser, $dbquota, $dbquota_home) =
	&get_domain_user_quotas($d);

# Get usage for sub-domain mail users
local @subs = &get_domain_by("parent", $d->{'id'});
local ($subhomequota, $submailquota, $dummy, $subdbquota) =
	&get_domain_user_quotas(@subs);

# Get group usage for the domain
local ($totalhomequota, $totalmailquota) = &get_domain_quota($d);
local $bsize = &quota_bsize("home");
$totalhomequota -= $dbquota_home/$bsize;

# Show home directory file usage, for total, unix user and mail users
print &ui_table_row($text{'edit_allquotah'},
   &text('edit_quotaby',
	&nice_size($totalhomequota*$bsize),
	&nice_size($duser->{'uquota'}*$bsize),
	&nice_size(($homequota+$subhomequota)*$bsize)), 3);
$tcount++;
$total += $totalhomequota*$bsize;

# Show mail filesystem usage separately
if (&has_mail_quotas()) {
	local $mbsize = &quota_bsize("home");
	print &ui_table_row($text{'edit_allquotam'},
	  &text('edit_quotaby',
		&nice_size($totalmailquota*$mbsize),
		&nice_size($duser->{'umquota'}*$mbsize),
		&nice_size(($mailquota+$submailquota)*$mbsize)), 3);
	$tcount++;
	$total += $totalmailquota*$mbsize;
	}

# Show DB usage
if ($dbquota+$subdbquota) {
	print &ui_table_row($text{'edit_dbquota'},
	    &text('edit_quotabysubs',
		&nice_size($dbquota+$subdbquota),
		&nice_size($dbquota),
		&nice_size($subdbquota)), 3);
	$tcount++;
	$total += $dbquota+$subdbquota;
	}

# Show overall total, if needed
if ($tcount > 1) {
	print &ui_table_row($text{'edit_totalquota'}, &nice_size($total));
	}
}

# show_domain_bw_usage(&domain)
# Print ui_table rows for bandwidth usage in a domain
sub show_domain_bw_usage
{
local ($d) = @_;
if (defined($d->{'bw_usage'})) {
	local $msg = &text('edit_bwusage',
		strftime("%d/%m/%Y", localtime($d->{'bw_start'}*(24*60*60))));
	if ($d->{'bw_limit'} && $d->{'bw_usage'} > $d->{'bw_limit'}) {
		local $notify = localtime($d->{'bw_notify'});
		print &ui_table_row($msg,
			"<font color=#ff0000>".
			&nice_size($d->{'bw_usage'})."</font>\n".
			($d->{'bw_notify'} ?
			    &text('edit_bwnotify', $notify) : ""), 3);
		}
	else {
		print &ui_table_row($msg, &nice_size($d->{'bw_usage'}), 3);
		}
	}
}

# domains_list_links(&domains, field, what)
# Returns text for a list of domain with links, or a search
sub domains_list_links
{
local ($doms, $field, $what) = @_;
if (@$doms > 5) {
	return scalar(@$doms)." <a href='search.cgi?field=$field&what=$what'>".
			      "$text{'edit_sublist'}</a>";
	}
else {
	# Show actual domain names
	my @alinks;
	foreach my $a (@$doms) {
		my $prog = &can_config_domain($a) ? "edit_domain.cgi"
					          : "view_domain.cgi";
		push(@alinks, "<a href='$prog?dom=$a->{'id'}'>$a->{'dom'}</a>");
		}
	local $lr = &ui_links_row(\@alinks);
	$lr =~ s/<br>$//;
	return $lr;
	}

}

# show_password_popup(&domain)
# Returns HTML for a link that pops up a password display window
sub show_password_popup
{
local ($d) = @_;
if (&can_show_pass()) {
	return "(<a href='showpass.cgi?dom=$d->{'id'}' onClick='window.open(\"showpass.cgi?dom=$d->{'id'}\", \"showpass\", \"toolbar=no,menubar=no,scrollbar=no,width=300,height=70\"); return false'>$text{'edit_showpass'}</a>)";
	}
else {
	return "";
	}
}

# flush_virtualmin_caches()
# Clear all in-memory caches of users, quotas, domains, etc..
sub flush_virtualmin_caches
{
undef(%main::get_domain_cache);
undef(%bsize_cache);
undef(%get_bandwidth_cache);
undef(%soft_home_quota);
undef(%hard_home_quota);
undef(%used_home_quota);
undef(%soft_mail_quota);
undef(%hard_mail_quota);
undef(%used_mail_quota);
undef(@useradmin::list_users_cache);
undef(@useradmin::list_groups_cache);
}

# list_shared_ips()
# Returns a list of extra IP addresses that can be used by virtual servers
sub list_shared_ips
{
return split(/\s+/, $config{'sharedips'});
}

# save_shared_ips(ip, ...)
# Updates the list of extra IP addresses that can be used by virtual servers
sub save_shared_ips
{
$config{'sharedips'} = join(" ", @_);
&save_module_config();
}

# is_shared_ip(ip)
# Returns 1 if some IP address is shared among multiple domains (ie. default,
# shared or reseller shared)
sub is_shared_ip
{
local ($ip) = @_;
return 1 if ($ip eq &get_default_ip());
return 1 if (&indexof($ip, &list_shared_ips()) >= 0);
if (defined(&list_resellers)) {
	foreach my $r (&list_resellers()) {
		return 1 if ($r->{'acl'}->{'defip'} &&
			     $ip eq $r->{'acl'}->{'defip'});
		}
	}
return 0;
}

# get_available_backup_features()
# Returns a list of features for which backups are possible
sub get_available_backup_features
{
local @rv;
foreach my $f (@backup_features) {
	local $bfunc = "backup_$f";
	if (defined(&$bfunc) &&
	    ($config{$f} || $f eq "unix" || $f eq "virtualmin")) {
		push(@rv, $f);
		}
	}
return @rv;
}

# html_extract_head_body(html)
# Given some HTML, extracts the header, body and stuff after the body
sub html_extract_head_body
{
local ($html) = @_;
if ($html =~ /^([\000-\377]*<body[^>]*>)([\000-\377]*)(<\/body[^>]*>[\000-\377]*)/i) {
	return ($1, $2, $3);
	}
else {
	return (undef, $html, undef);
	}
}

# open_uncompress_file(filehandle, filename)
# Open a file, uncompressing if needed
sub open_uncompress_file
{
local ($fh, $f) = @_;
if ($f =~ /\.gz$/i) {
	return open($fh, "gunzip -c ".quotemeta($f)." |");
	}
elsif ($f =~ /\.Z$/i) {
	return open($fh, "uncompress -c ".quotemeta($f)." |");
	}
elsif ($f =~ /\.bz2$/i) {
	return open($fh, "bunzip2 -c ".quotemeta($f)." |");
	}
else {
	return open($fh, $f);
	}
}

# list_available_features([&parentdom], [&aliasdom], [&subdom])
# Returns a list of features available for a virtual server, by the current
# Virtualmin user.
sub list_available_features
{
local ($parentdom, $aliasdom, $subdom) = @_;

# Start with core features
local @core = $aliasdom ? @opt_alias_features :
	    $subdom ? @opt_subdom_features : @opt_features;
@core = grep { &can_use_feature($_) } @core;
if ($parentdom) {
	@core = grep { $_ ne 'webmin' && $_ ne 'unix' } @core;
	}
if ($aliasdom) {
	@core = grep { $aliasdom->{$_} } @core;
	}
local @rv = map { { 'feature' => $_,
		    'desc' => $text{'feature_'.$_},
		    'core' => 1,
		    'auto' => $config{$_} == 3,
		    'default' => $config{$_} == 1 || $config{$_} == 3,
		    'enabled' => $config{$_} || !defined($config{$_}) } } @core;

# Add plugin features
local @plug = grep { &plugin_call($_, "feature_suitable",
			$parentdom, $aliasdom, $subdom) } @feature_plugins;
@plug = grep { &can_use_feature($_) } @plug;
if ($aliasdom) {
	@plug = grep { $aliasdom->{$_} } @plug;
	}
local %inactive = map { $_, 1 } split(/\s+/, $config{'plugins_inactive'});
push(@rv, map { { 'feature' => $_,
		  'desc' => &plugin_call($_, "feature_name", 0),
		  'plugin' => 1,
		  'auto' => 0,
		  'default' => !$inactive{$_},
		  'enabled' => 1 } } @plug);

return @rv;
}

# count_domain_users()
# Returns a hash ref from domain IDs to user counts
sub count_domain_users
{
local %rv;
local %homemap;
foreach my $d (&list_domains()) {
	$homemap{$d->{'home'}} = $d->{'id'};
	}
foreach my $u (&list_all_users_quotas(1)) {
	local $h = $u->{'home'};
	local $did;
	if ($homemap{$h}) {
		# User home is a domain's home .. so this is the domain owner
		$did = $homemap{$h};
		}
	elsif ($h =~ /^(.*)\/homes\/(\S+)$/) {
		# User's home is under a domain's homes dir, so he must
		# belong to it.
		$did = $homemap{$1};
		}
	elsif ($h =~ /^(.*)\/public_html$/) {
		# Home is public_html, so he is a web user
		$did = $homemap{$1};
		}
	else {
		# Fallback to trying each home (longest first)
		foreach my $hd (sort { length($b) cmp length($a) }
				     keys %homemap) {
			if ($h =~ /^\Q$hd\E\//) {
				$did = $homemap{$hd};
				last;
				}
			}
		}
	if ($did) {
		$rv{$did}++;
		}
	}
return \%rv;
}

# add_user_to_domain_group(&domain, user, [text-message])
# Adds some user (like httpd or ftp) to the Unix group for a domain, if missing
sub add_user_to_domain_group
{
local ($d, $user, $msg) = @_;
return 0 if ($d->{'alias'} || !$d->{'group'});
&require_useradmin();
local @groups = &list_all_groups();
local ($group) = grep { $_->{'group'} eq $d->{'group'} } @groups;
if ($group) {
	local @mems = split(/,/, $group->{'members'});
	if (&indexof($user, @mems) < 0) {
		# Need to add him
		&$first_print(&text($msg, $user)) if ($msg);
		local $oldgroup = { %$group };
		$group->{'members'} = join(",", @mems, $user);
		&foreign_call($group->{'module'}, "set_group_envs", $group,
						  'MODIFY_GROUP', $oldgroup);
		&foreign_call($group->{'module'}, "making_changes");
		&foreign_call($group->{'module'}, "modify_group",
						  $oldgroup, $group);
		&foreign_call($group->{'module'}, "made_changes");
		&$second_print($text{'setup_done'}) if ($msg);
		return 1;
		}
	}
return 0;
}

# get_backup_excludes(&domain)
# Returns a list of excluded directories
sub get_backup_excludes
{
local ($d) = @_;
return split(/\t+/, $d->{'backup_excludes'});
}

# save_backup_excludes(&domain, &excludes)
# Updates the list of excluded directories
sub save_backup_excludes
{
local ($d, $excludes) = @_;
$d->{'backup_excludes'} = join("\t", @$excludes);
&save_domain($d);
}

$done_virtual_server_lib_funcs = 1;

1;

