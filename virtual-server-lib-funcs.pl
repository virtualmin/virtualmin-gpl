
use Time::Local;
use POSIX;
use feature 'state';

## Work out where our extra -lib.pl files are, and load them
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
foreach my $lib ("scripts", "resellers", "admins", "users", "simple", "s3",
		 "php", "ruby", "vui", "dynip", "collect", "maillog",
		 "balancer", "newfeatures", "resources", "backups",
		 "domainname", "commands", "connectivity", "plans",
		 "postgrey", "wizard", "security", "json", "redirects", "ftp",
		 "dkim", "provision", "stats", "bkeys", "rs", "cron",
		 "ratelimit", "cloud", "google", "gcs", "dropbox", "copycert",
		 "jailkit", "ports", "bb", "dnscloud", "dnscloudpro",
		 "smtpcloud", "pro-tip", "azure", "remotedns", "drive",
		 "acme", "api-create-domain") {
	my $libfile = "$virtual_server_root/pro/$lib-lib.pl";
	if (!-r $libfile) {
		$libfile = "$virtual_server_root/$lib-lib.pl";
		}
	do $libfile;
	if ($@ && -r $libfile) {
		print STDERR "failed to load $lib-lib.pl : $@\n";
		}
	}

# Wrapper function to get webprefix safely
sub get_webprefix_safe
{
if (defined(&get_webprefix)) {
	return &get_webprefix();
	}
return $gconfig{'webprefix'};
}

# require_useradmin([no-quotas])
sub require_useradmin
{
if (!$require_useradmin++) {
	&foreign_require("useradmin");
	%uconfig = &foreign_config("useradmin");
	$home_base = &resolve_links($config{'home_base'} || $uconfig{'home_base'});
	$cannot_rehash_password = 0;
	if ($config{'ldap'}) {
		&foreign_require("ldap-useradmin");
		%luconfig = &foreign_config("ldap-useradmin");
		$usermodule = "ldap-useradmin";
		if ($ldap_useradmin::config{'md5'} == 3 ||
		    $ldap_useradmin::config{'md5'} == 4) {
			$cannot_rehash_password = 1;
			}
		}
	else {
		$usermodule = "useradmin";
		}
	}
if (!&has_quota_commands() && !$_[0] && !$require_useradmin_quota++) {
	&foreign_require("quota");
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
local @files;
local @st = stat($domains_dir);
if (scalar(@main::list_domains_cache) &&
    $st[9] == $main::list_domains_cache_time) {
	# Use cache of domain IDs in RAM
	@files = @main::list_domains_cache;
	}
else {
	# Re-scan the directory, if un-changed
	opendir(DIR, $domains_dir);
	@files = readdir(DIR);
	closedir(DIR);
	@main::list_domains_cache = @files;
	$main::list_domains_cache_time = $st[9];
	}
foreach $d (@files) {
	if ($d !~ /^\./ && $d !~ /\.(lock|bak|back|backup|rpmsave|sav|swp|~)$/i && $d !~ /\.webmintmp\.\d+/i) {
		push(@rv, &get_domain($d));
		}
	}
return @rv;
}

# list_visible_domains([opts])
# Returns a list of domain structures the current user can see, for use in
# domain menus. Excludes those that he doesn't have access to, and perhaps
# alias domains.
sub list_visible_domains
{
my ($opts) = @_;
my @rv = grep { &can_edit_domain($_) } &list_domains();

# Always exclude default host domain
my $exclude_defaulthostdomain =
	{ 'exclude' => 'defaulthostdomain' };
$opts = {%$opts, %$exclude_defaulthostdomain}
	if ($config{'default_domain_ssl'} != 2);

# Exclude domains based on given field
@rv = grep { ! $_->{$opts->{'exclude'}} } @rv
	if ($opts->{'exclude'});

return @rv;
}

# sort_indent_domains(&domains)
# Returns a list of all domains sorted according to the module config setting.
# Those that should be indented have the 'indent' field set to some number.
sub sort_indent_domains
{
local @doms = @{$_[0]};
local $sortfield = $config{'domains_sort'} || "user";
local %sortkey;
if ($sortfield eq 'dom' || $sortfield eq 'sub') {
	%sortkey = map { $_->{'id'}, &show_domain_name($_) } @doms;
	}
else {
	%sortkey = map { $_->{'id'}, $_->{$sortfield} } @doms;
	}
@doms = sort { $sortkey{$a->{'id'}} cmp $sortkey{$b->{'id'}} ||
               $a->{'created'} <=> $b->{'created'} } @doms;
foreach my $d (@doms) {
	$d->{'indent'} = 0;
	}
if ($sortfield eq 'user' || $sortfield eq 'sub') {
	# Re-categorize by owner, with sub-servers indented one and alias
	# servers indented two under their targets
	local @catdoms;
	foreach my $d (grep { !$_->{'parent'} } @doms) {
		push(@catdoms, $d);
		foreach my $ad (grep { $_->{'alias'} eq $d->{'id'} } @doms) {
			$ad->{'indent'} = 2;
			push(@catdoms, $ad);
			}
		foreach my $sd (grep { $_->{'parent'} eq $d->{'id'} &&
				       !$_->{'alias'} } @doms) {
			$sd->{'indent'} = 1;
			push(@catdoms, $sd);
			foreach my $ad (grep { $_->{'alias'} eq $sd->{'id'} }
					     @doms) {
				$ad->{'indent'} = 3;
				push(@catdoms, $ad);
				}
			}
		}
	# Any domains that we missed due to their parent not being included
	# should appear at the top level
	my %incatdoms = map { $_->{'id'}, $_ } @catdoms;
	foreach my $d (@doms) {
		if (!$incatdoms{$d->{'id'}}) {
			push(@catdoms, $d);
			}
		}
	@doms = @catdoms;
	}
return @doms;
}

# get_domain(id, [file], [force-reread])
# Looks up a domain object by ID
sub get_domain
{
local ($id, $file, $force) = @_;
return undef if (!$id && !$file);
if ($id && defined($main::get_domain_cache{$id}) && !$force) {
	return $main::get_domain_cache{$id};
	}
local %dom;
$file ||= "$domains_dir/$id";
&read_file($file, \%dom) || return undef;
$dom{'file'} = "$domains_dir/$id";
$dom{'id'} ||= $id;
$dom{'lastread_time'} = time();
delete($dom{'deleting'});
&complete_domain(\%dom);
if (!defined($dom->{'created'})) {
	# compat - creation date can be inferred from ID
        $dom->{'id'} =~ /^(\d{10})/;
        $dom->{'created'} = $1;
        }
delete($dom->{'missing'});	# never set in a saved domain
if ($id) {
	if ($main::get_domain_cache{$id} && $force) {
		# In forced re-read mode, update existing object in cache
		local $cache = $main::get_domain_cache{$id};
		%$cache = %dom;
		}
	else {
		# Add to cache
		$main::get_domain_cache{$id} = \%dom;
		}
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
if (!defined($dom->{'template'})) {
	# assume default parent or sub-server template
	$dom->{'template'} = $dom->{'parent'} ? 1 : 0;
	}
if (!$dom->{'web_port'} && $dom->{'web'}) {
	# compat - assume web port is current setting
	my $tmpl = &get_template($dom->{'template'});
	$dom->{'web_port'} = $tmpl->{'web_port'} || $default_web_port;
	}
if (!$dom->{'web_sslport'} && $dom->{'ssl'}) {
	# compat - assume SSL port is current setting
	my $tmpl = &get_template($dom->{'template'});
	$dom->{'web_sslport'} = $tmpl->{'web_sslport'} || $web_sslport;
	}
if (!defined($dom->{'prefix'})) {
	# compat - assume that prefix is same as group
	$dom->{'prefix'} = $dom->{'group'};
	}
if (!defined($dom->{'home'})) {
	local @u = getpwnam($dom->{'user'});
	if (@u && $u[7] ne '/' && $u[7] ne '/root') {
		$dom->{'home'} = $u[7];
		}
	}
if (!defined($dom->{'proxy_pass_mode'}) && $dom->{'proxy_pass'}) {
	# assume that proxy pass mode is proxy-based if not set
	$dom->{'proxy_pass_mode'} = 1;
	}
if (!defined($dom->{'plan'}) && !$main::no_auto_plan) {
	# assume first plan
	local @plans = sort { $a->{'id'} <=> $b->{'id'} } &list_plans();
	$dom->{'plan'} = $plans[0]->{'id'};
	}
if ($dom->{'db'} eq '' && ($dom->{'mysql'} || $dom->{'postgres'})) {
	$dom->{'db'} = &database_name($dom);
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
if ($dom->{'dns'} && $dom->{'dns_submode'} && !$dom->{'dns_subof'}) {
	# Assume parent DNS domain is parent virtual server
	$dom->{'dns_subof'} = $dom->{'subdom'} || $dom->{'parent'};
	}
if (!$dom->{'letsencrypt_id'} && $dom->{'letsencrypt_last'}) {
	# Default ACME provider to Let's Encrypt
	$dom->{'letsencrypt_id'} = 1;
	}

# Emailto is a computed field
&compute_emailto($dom);

# Also compute first actual email address
if (!$dom->{'emailto_addr'} ||
    $dom->{'emailto_src'} ne $dom->{'emailto'}) {
	if ($dom->{'emailto'} =~ /^[a-z0-9\.\_\-\+]+\@[a-z0-9\.\_\-]+$/i) {
		$dom->{'emailto_addr'} = $dom->{'emailto'};
		}
	else {
		($dom->{'emailto_addr'}) =
			&extract_address_parts($dom->{'emailto'});
		}
	$dom->{'emailto_src'} = $dom->{'emailto'};
	}

# Set edit limits based on ability to edit domains
local %acaps = map { $_, 1 } &list_automatic_capabilities($dom->{'domslimit'});
foreach my $ed (@edit_limits) {
	if (!defined($dom->{'edit_'.$ed})) {
		$dom->{'edit_'.$ed} = $acaps{$ed} || 0;
		}
	}
delete($dom->{'pass_set'});	# Only set by callers for modify_* functions
}

# compute_emailto(&domain)
# Populate the emailto field based on the email field
sub compute_emailto
{
local ($dom) = @_;
local $parent;
if ($dom->{'parent'} && ($parent = &get_domain($dom->{'parent'}))) {
	$dom->{'emailto'} = $parent->{'emailto'};
	}
elsif ($dom->{'email'}) {
	$dom->{'emailto'} = $dom->{'email'};
	}
elsif ($dom->{'mail'}) {
	$dom->{'emailto'} = $dom->{'user'}.'@'.$dom->{'dom'};
	}
else {
	$dom->{'emailto'} = $dom->{'user'}.'@'.&get_system_hostname();
	}
}

# list_automatic_capabilities(can-create-domains)
# Returns a list of default capabilities for a domain owner or plan
sub list_automatic_capabilities
{
local ($cancreate) = @_;
if ($cancreate) {
	return @edit_limits;
	}
else {
	return ( 'users', 'aliases', 'html', 'passwd' );
	}
}

# get_domain_by(field, value, [field, value, ...])
# Looks up a domain by some field(s). For each field, we either use the quick
# map to find relevant domains, or check though all that we have left.
# The special value _ANY_ matches any domains where the field is non-empty
sub get_domain_by
{
local @rv;
for(my $i=0; $i<@_; $i+=2) {
	local $mf = $get_domain_by_maps{$_[$i]};
	local @possible;
	local %map;
	if ($mf && &read_file_cached($mf, \%map)) {
		# The map knows relevant domains
		if ($_[$i+1] eq "_ANY_") {
			# Find domains where the field is non-empty
			foreach my $k (keys %map) {
				next if ($k eq '');
				foreach my $did (split(" ", $map{$k})) {
					local $d = &get_domain($did);
					push(@possible, $d) if ($d);
					}
				}
			}
		else {
			# Check for a match
			foreach my $did (split(" ", $map{$_[$i+1]})) {
				local $d = &get_domain($did);
				push(@possible, $d) if ($d);
				}
			}
		}
	else {
		# Need to check manually
		@possible = grep { $_->{$_[$i]} eq $_[$i+1] ||
				   $_->{$_[$i]} ne "" && $_[$i+1] eq "_ANY_" }
				 &list_domains();
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

# get_domains_by_names_users(&dnames, &usernames, &errorfunc, &plans,
# 			     [subservers-too])
# Given a list of domain names, usernames and plans, returns all matching
# domains (unioned). May callback to the error function if one cannot be found.
sub get_domains_by_names_users
{
local ($dnames, $users, $efunc, $plans, $subs) = @_;
foreach my $domain (&unique(@$dnames)) {
	local $d = &get_domain_by("dom", $domain);
	$d || &$efunc("Virtual server $domain does not exist");
	push(@doms, $d);
	}
foreach my $uname (&unique(@$users)) {
	local $dinfo = &get_domain_by("user", $uname, "parent", "");
	if ($dinfo) {
		push(@doms, $dinfo);
		push(@doms, &get_domain_by("parent", $dinfo->{'id'}));
		}
	else {
		&$efunc("No top-level domain owned by $uname exists");
		}
	}
foreach my $plan (&unique(@$plans)) {
	foreach my $dinfo (&get_domain_by("plan", $plan->{'id'})) {
		push(@doms, $dinfo);
		push(@doms, &get_domain_by("parent", $dinfo->{'id'}));
		}
	}
if ($subs) {
	my @add;
	foreach my $d (@doms) {
		push(@add, &get_domain_by("parent", $d->{'id'}))
			if (!$d->{'parent'});
		push(@add, &get_domain_by("alias", $d->{'id'}))
			if (!$d->{'alias'});
		push(@add, &get_domain_by("subdom", $d->{'id'}))
			if (!$d->{'subdom'});
		}
	push(@doms, @add);
	}
local %donedomain;
@doms = grep { !$donedomain{$_->{'id'}}++ } @doms;
return @doms;
}

# get_domain_by_user(username)
# Given a domain owner's Webmin login, return his top-level domain
sub get_domain_by_user
{
local ($user) = @_;
if ($access{'admin'}) {
	# Extra admin
	local $d = &get_domain($access{'admin'});
	if ($d && $d->{'parent'}) {
		$d = &get_domain($d->{'parent'});
		}
	return $d;
	}
else {
	# Domain owner
	local $d = &get_domain_by("user", $user, "parent", "");
	return $d;
	}
}

# get_domains_by_names(name, ...)
# Given a list of domain names, returns the domain objects (where they exist)
sub get_domains_by_names
{
local @rv;
foreach my $dname (@_) {
	my $d = &get_domain_by("dom", $dname);
	push(@rv, $d) if ($d);
	}
return @rv;
}

# expand_dns_subdomains(&domains)
# Given a list of domains, find all their sub-domains as well and return the
# complete list
sub expand_dns_subdomains
{
my ($doms) = @_;
my @rv;
foreach my $d (@doms) {
	push(@rv, $d);
	if ($d->{'dns'}) {
		push(@rv, grep { $_->{'dns'} }
			       &get_domain_by("dns_subof", $d->{'id'}));
		}
	}
my %done;
return grep { !$done{$_->{'id'}}++ } @rv;
}

# domain_id()
# Returns a new unique domain ID
sub domain_id
{
local $rv = time().$$.$main::domain_id_count;
$main::domain_id_count++;
return $rv;
}

# lock_domain(&domain|id)
# Lock the config file for some domain
sub lock_domain
{
my ($id) = @_;
$id = $id->{'id'} if (ref($id));
&lock_file("$domains_dir/$id");
}

# unlock_domain(&domain|id)
# Unlock the config file for some domain
sub unlock_domain
{
my ($id) = @_;
$id = $id->{'id'} if (ref($id));
&unlock_file("$domains_dir/$id");
}

# save_domain(&domain, [creating])
# Write domain information to disk
sub save_domain
{
local ($d, $creating) = @_;
local $file = "$domains_dir/$d->{'id'}";
if (!$creating && $d->{'id'} && !-r $file) {
	# Deleted from under us! Don't save
	print STDERR "Domain $file was deleted before saving!\n";
	&print_call_stack() if ($gconfig{'error_stack'});
	return 0;
	}
if ($d->{'dom'} eq '') {
	# Has no domain name!
	print STDERR "Domain has no name!\n";
	return 0;
	}
&make_dir($domains_dir, 0700);
&lock_file($file);
local $oldd = { };
if (&read_file($file, $oldd)) {
	my @st = stat($file);
	if ($d->{'lastread_time'} && $st[9] > $d->{'lastread_time'}) {
		print STDERR "Domain $file was modified since last read!\n";
		&print_call_stack() if ($gconfig{'error_stack'});
		}
	}
if (!$d->{'created'}) {
	$d->{'created'} = time();
	$d->{'creator'} ||= $remote_user;
	$d->{'creator'} ||= getpwuid($<);
	}
$d->{'id'} ||= &domain_id();
$d->{'lastsave'} = time();
$d->{'lastsave_script'} = $ENV{'SCRIPT_NAME'} || $0;
$d->{'lastsave_user'} = $remote_user;
$d->{'lastsave_type'} = $main::webmin_script_type;
$d->{'lastsave_webmincron'} = $main::webmin_script_webmincron;
$d->{'lastsave_pid'} = $main::initial_process_id;
delete($d->{'lastread_time'});
&write_file($file, $d);
&unlock_file($file);
$d->{'lastread_time'} = time();
$main::get_domain_cache{$d->{'id'}} = $d;
if (scalar(@main::list_domains_cache)) {
	@main::list_domains_cache =
		&unique(@main::list_domains_cache, $d->{'id'});
	}
# Only rebuild maps if something relevant changed
local $mchanged = 0;
foreach my $m (keys %get_domain_by_maps) {
	$mchanged++ if ($d->{$m} ne $oldd->{$m});
	}
if ($mchanged) {
	&build_domain_maps();
	}
&set_ownership_permissions(undef, undef, 0700, $file);
return 1;
}

# delete_domain(&domain)
# Delete all of Virtualmin's internal information about a domain
sub delete_domain
{
my ($d) = @_;
my $id = $d->{'id'};
&unlink_logged("$domains_dir/$id");

# And the bandwidth and plain-text password files
&unlink_file("$bandwidth_dir/$id");
&unlink_file("$plainpass_dir/$id");
&unlink_file("$hashpass_dir/$id");
&unlink_file("$nospam_dir/$id");
&unlink_file("$quota_cache_dir/$id");

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

# Delete scheduled backups owned by the domain owner, or that backup only
# this domain
foreach my $sched (&list_scheduled_backups()) {
	my @dids = split(/\s+/, $sched->{'doms'});
	if ($sched->{'owner'} eq $id) {
		&delete_scheduled_backup($sched);
		}
	elsif (!$sched->{'all'} && !$sched->{'virtualmin'} &&
	       &indexof($id, @dids) >= 0) {
		# If the backup is for specified domains, check if any of
		# them exist and aren't this domain
		my $candelete = 1;
		foreach my $did (@dids) {
			my $bd = &get_domain($did);
			if ($bd && $id ne $bd->{'id'}) {
				$candelete = 0;
				last;
				}
			}
		if ($candelete) {
			&delete_scheduled_backup($sched);
			}
		}
	}

# Delete any script notifications logs
if (-r $script_warnings_file) {
	&read_file($script_warnings_file, \%warnsent);
	foreach my $key (keys %warnsent) {
		my ($keyid) = split(/\//, $key);
		delete($warnsent{$key}) if ($keyid eq $id);
		}
	&write_file($script_warnings_file, \%warnsent);
	}

# Delete script install logs
&unlink_file("$script_log_directory/$id");

# Delete differential backup file
&unlink_file("$incremental_backups_dir/$id");

# Delete cached links for the domain
&clear_links_cache($d);

# Delete any saved aliases
&unlink_file("$saved_aliases_dir/$id");

# Release any lock on the name
&unlock_file("$domainnames_dir/$d->{'dom'}");
&unlink_file("$domainnames_dir/$d->{'dom'}.lock");

# Remove from caches
delete($main::get_domain_cache{$d->{'id'}});
if (scalar(@main::list_domains_cache)) {
	@main::list_domains_cache = grep { $_ ne $d->{'id'} }
					 @main::list_domains_cache;
	}
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

# supports_firstname()
# Returns 1 if users can have a first name and surname
sub supports_firstname
{
&require_useradmin();
if ($usermodule eq "ldap-useradmin") {
	my %luconfig = &foreign_config("ldap-useradmin");
	return $luconfig{'given'} ? 1 : 0;
	}
return 0;
}

# list_domain_users([&domain], [skipunix], [no-virts], [no-quotas], [no-dbs],
# 		    [include-extra])
# List all Unix users who are in the domain's primary group.
# If domain is omitted, returns local users.
sub list_domain_users
{
local ($d, $skipunix, $novirts, $noquotas, $nodbs, $includeextra) = @_;

# Get all aliases (and maybe generics) to look for those that match users
local (%aliases, %generics);
if ($config{'mail'} && !$novirts) {
	&require_mail();
	if ($mail_system == 1) {
		# Find Sendmail aliases for users
		%aliases = map { $_->{'name'}, $_ } grep { $_->{'enabled'} }
			       &sendmail::list_aliases($sendmail_afiles);
		}
	elsif ($mail_system == 0) {
		# Find Postfix aliases for users
		%aliases = map { $_->{'name'}, $_ }
			       &$postfix_list_aliases($postfix_afiles);
		}
	if ($config{'generics'}) {
		%generics = &get_generics_hash();
		}
	}

# Get all virtusers to look for those for users
local @virts;
if (!$novirts) {
	@virts = &list_virtusers();
	}

# Are we setting quotas individually?
local $ind_quota = 0;
if (&has_quota_commands() && $config{'quota_get_user_command'} && $d) {
	$ind_quota = 1;
	}

local @users = &list_all_users_quotas($noquotas || $ind_quota);
if ($d) {
	# Limit to domain users.
	@users = grep { $d->{'gid'} ne '' &&
			$_->{'gid'} == $d->{'gid'} ||
			$_->{'user'} eq $d->{'user'} } @users;
	foreach my $u (@users) {
		if ($u->{'user'} eq $d->{'user'}) {
			# Virtual server owner
			$u->{'domainowner'} = 1;
			if ($d->{'hashpass'}) {
				$u->{'pass_crypt'} = $d->{'crypt_enc_pass'};
				$u->{'pass_md5'} = $d->{'md5_enc_pass'};
				$u->{'pass_mysql'} = $d->{'mysql_enc_pass'};
				$u->{'pass_digest'} = $d->{'digest_enc_pass'};
				}
			}
		elsif ($u->{'uid'} == $d->{'uid'}) {
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
	if ($d->{'parent'}) {
		# This is a subdomain - exclude parent domain users, including
		# jailed users
		@users = grep { $_->{'home'} =~ 
		    /(^|\/.*?\/\d{10,}\/\.)$d->{'home'}(\/|$)/ } @users;
		}
	elsif (@subdoms = &get_domain_by("parent", $d->{'id'})) {
		# This domain has subdomains - exclude their users, including
		# jailed users
		@users = grep { $_->{'home'} !~
		    /(^|\/.*?\/\d{10,}\/\.)$d->{'home'}\/domains(\/|$)/ } @users;
		}
	@users = grep { !$_->{'domainowner'} } @users
		if ($skipunix || $d->{'parent'});

	# Remove users with @ in their names for whom a user with the @ replace
	# already exists (for Postfix)
	if ($mail_system == 0) {
		local %umap = map { &replace_atsign($_->{'user'}), $_ }
				grep { $_->{'user'} =~ /\@/ } @users;
		@users = grep { !$umap{$_->{'user'}} } @users;
		}

	# Find users with broken home dir (not under homes, or
	# domain's home, or public_html (for web ftp users))
	local $phd = &public_html_dir($d);
	foreach my $u (@users) {
		if (!$u->{'webowner'} && $u->{'home'} &&
		    $u->{'home'} !~ /^$d->{'home'}\/$config{'homes_dir'}\// &&
		    !&is_under_directory($d->{'home'}, $u->{'home'})) {
			# Home dir is outside domain's home base somehow
			$u->{'brokenhome'} = 1;
			}
		elsif ($u->{'webowner'} && $u->{'home'} &&
		       !&is_under_directory($phd, $u->{'home'}) &&
		       $u->{'home'} ne $d->{'home'}) {
			# Website FTP user's home dir must be under public_html
			# or domain's home
			$u->{'brokenhome'} = 1;
                        }
		elsif (!$u->{'webowner'} && $u->{'home'} eq $d->{'home'}) {
			# Home dir is equal to domain's dir, which is invalid,
			# unless it is the web owner user (FTP user)
			$u->{'brokenhome'} = 1;
			}
		}

	if ($d->{'hashpass'}) {
		# Merge in encrypted passwords
		&read_file_cached("$hashpass_dir/$d->{'id'}", \%hash);
		foreach my $u (@users) {
			foreach my $s (@hashpass_types) {
				$u->{'pass_'.$s} = $hash{$u->{'user'}.' '.$s};
				}
			}
		}
	else {
		# Merge in plain text passwords
		local (%plain, $need_plainpass_save);
		&read_file_cached("$plainpass_dir/$d->{'id'}", \%plain);
		foreach my $u (@users) {
			if ($u->{'domainowner'}) {
				# The domain owner's password is always known
				$u->{'plainpass'} = $d->{'pass'};
				}
			elsif (!defined($u->{'plainpass'}) &&
			       defined($plain{$u->{'user'}})) {
				# Check if the plain password is valid, in case
				# the crypted password was changed behind
				# our back
				if ($plain{$u->{'user'}." encrypted"} eq
				     $u->{'pass'} ||
				    &encrypt_user_password(
				      $u, $plain{$u->{'user'}}) eq
				      $u->{'pass'} ||
				    &safe_unix_crypt($plain{$u->{'user'}},
						     $u->{'pass'})
				      eq $u->{'pass'}) {
					# Valid - we can use it
					$u->{'plainpass'} =$plain{$u->{'user'}};
					if (!defined($plain{$u->{'user'}.
						            " encrypted"})) {
						# Save the correct crypted
						# version now
						$plain{$u->{'user'}.
						       " encrypted"} =
							$u->{'pass'};
						$need_plainpass_save = 1;
						}
					}
				else {
					# We know it is wrong, so remove from
					# the plain password cache file
					delete($plain{$u->{'user'}});
					delete($plain{$u->{'user'}." encrypted"});
					$need_plainpass_save = 1;
					}
				}
			}
		if ($need_plainpass_save) {
			&write_file("$plainpass_dir/$d->{'id'}", \%plain);
			}
		}
	}
else {
	# Limit to local users
	local @lg = getgrnam($config{'localgroup'});
	@users = grep { $_->{'gid'} == $lg[2] } @users;
	}

# Set appropriate quota field
local $tmpl = &get_template($d ? $d->{'template'} : 0);
local $qtype = $tmpl->{'quotatype'};
local $u;
foreach $u (@users) {
	$u->{'quota'} = $u->{$qtype.'quota'} if (!defined($u->{'quota'}));
	$u->{'mquota'} = $u->{$qtype.'mquota'} if (!defined($u->{'mquota'}));
	}

# Merge in cached quotas
if ($d) {
	my $qfile = $quota_cache_dir."/".$d->{'id'};
	my %qcache;
	&read_file_cached($qfile, \%qcache);
	foreach $u (@users) {
		$u->{'quota_cache'} = $qcache{$u->{'user'}."_quota"};
		$u->{'mquota_cache'} = $qcache{$u->{'user'}."_mquota"};
		}
	}

# Check if spamc is being used
local $spamc;
if ($d && $d->{'spam'}) {
	local $spamclient = &get_domain_spam_client($d);
	$spamc = 1 if ($spamclient =~ /spamc/);
	}

# Detect user who are close to their quota
if (&has_home_quotas()) {
	local $bsize = &quota_bsize("home");
	foreach $u (@users) {
		local $diff = $u->{'quota'}*$bsize - $u->{'uquota'}*$bsize;
		if ($u->{'quota'} && $diff < $quota_spam_margin &&
		    $d->{'spam'} && !$spamc) {
			# Close to quota, which will block spamassassin ..
			$u->{'spam_quota'} = 1;
			$u->{'spam_quota_diff'} = $diff < 0 ? 0 : $diff;
			}
		if ($u->{'quota'} && $u->{'uquota'} >= $u->{'quota'}) {
			# At or over quota
			$u->{'over_quota'} = 1;
			}
		elsif ($u->{'quota'} && $u->{'uquota'} >= $u->{'quota'}*0.95) {
			# Over 95% of quota
			$u->{'warn_quota'} = 1;
			}
		}
	}

# Add user-configured recovery addresses
if (!$novirts) {
	foreach my $u (@users) {
		if (!defined($u->{'recovery'})) {
			my $recovery = &write_as_mailbox_user($u,
			    sub { &read_file_contents(
				"$u->{'home'}/.usermin/changepass/recovery") });
			$recovery =~ s/\r|\n//g;
			$u->{'recovery'} = $recovery;
			}
		}
	}

if (!$novirts) {
	# Add email addresses and forwarding addresses to user structures
	foreach my $u (@users) {
		$u->{'email'} = $u->{'virt'} = undef;
		$u->{'alias'} = $u->{'to'} = $u->{'generic'} = undef;
		$u->{'extraemail'} = $u->{'extravirt'} = undef;
		local ($al, $va);
		if ($al = $aliases{&escape_alias($u->{'user'})}) {
			$u->{'alias'} = $al;
			$u->{'to'} = $al->{'values'};
			}
		elsif ($va = $valiases{"$u->{'user'}\@$d->{'dom'}"}) {
			$u->{'valias'} = $va;
			$u->{'to'} = $va->{'to'};
			}
		elsif ($mail_system == 2) {
			# Find .qmail file
			local $alias = &get_dotqmail(&dotqmail_file($u));
			if ($alias) {
				$u->{'alias'} = $alias;
				$u->{'to'} = $u->{'alias'}->{'values'};
				}
			}
		$u->{'generic'} = $generics{$u->{'user'}};
		local $pop3 = $d ? &remove_userdom($u->{'user'}, $d)
				    : $u->{'user'};
		local $email = $d ? "$pop3\@$d->{'dom'}" : undef;
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
			    (!$d || $v->{'from'} ne $d->{'dom'})) {
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

# Push domain extra database users
push(@users, &list_extra_db_users($d))
	if ($includeextra);

if (!$nodbs && $d) {
	# Add accessible databases
	local @dbs = &domain_databases($d);
	local $db;
	local %dbdone;
	foreach $u (@users) {
		$u->{'dbs'} = [ ];
		}
	foreach $db (@dbs) {
		local @dbu;
		local $ufunc;
		if (&indexof($db->{'type'}, &list_database_plugins()) < 0) {
			# Core database
			local $dfunc = "list_".$db->{'type'}."_database_users";
			next if (!defined(&$dfunc));
			$ufunc = $db->{'type'}."_username";
			@dbu = &$dfunc($d, $db->{'name'});
			}
		else {
			# Plugin database
			next if (!&plugin_defined($db->{'type'},
						  "database_users"));
			@dbu = &plugin_call($db->{'type'}, "database_users",
					    $d, $db->{'name'});
			}
		local %dbu = map { $_->[0], $_->[1] } @dbu;
		local $u;
		local $domufunc = $db->{'type'}.'_user';
		local $domu = defined(&$domufunc) ? &$domufunc($d) : undef;
		foreach $u (@users) {
			# Domain owner always gets all databases
			next if ($u->{'user'} eq $d->{'user'});

			# For each user, add this DB to his list if there
			# is a user for it with the same name. Unless this
			# is the same as the domain owner's DB username.
			local $uname = $ufunc ? &$ufunc($u->{'user'}) :
				&plugin_call($db->{'type'}, "database_user",
					     $u->{'user'});
			if (exists($dbu{$uname}) &&
			    $uname ne $domu &&
			    !$dbdone{$db->{'type'},$db->{'name'},$uname}++) {
				push(@{$u->{'dbs'}}, $db);
				$u->{$db->{'type'}."_user"} = $uname;
				$u->{$db->{'type'}."_pass"} = $dbu{$uname};
				}
			}
		}

	# Add plugin databases
	local @dbs = &domain_databases($d);
	foreach $db (@dbs) {
		next if (&indexof($db->{'type'}, &list_database_plugins()) == -1);
		}
	}

if ($includeextra && &domain_has_website($d) &&
    &indexof('virtualmin-htpasswd', @plugins) >= 0) {
	# Include webserver users
	push(@users, &list_extra_web_users($d));
	}

# Add any secondary groups in the template
local @sgroups = &allowed_secondary_groups($d);
if (@sgroups) {
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

# Add no-spam flags
if ($d) {
	local %nospam;
	&read_file_cached("$nospam_dir/$d->{'id'}", \%nospam);
	foreach my $u (@users) {
		if (!defined($u->{'nospam'})) {
			$u->{'nospam'} = $nospam{$u->{'user'}};
			}
		}
	}

# Add jailed user info for each user
if ($d && &is_domain_jailed($d)) {
	my @jusers = &get_domain_jailed_users_shell($d);
	foreach my $juser (@jusers) {
		my ($user) = grep { $_->{'user'} eq $juser->{'user'} } @users;
		if ($user) {
			$user->{'jailed'} = $juser;
			}
		}
	}

# Return users list
return @users;
}

# create_databases_user(&domain, &user, [type])
# Create a database user for some domain
# Returns an error message on failure, or undef on success
sub create_databases_user
{
my ($d, $user, $type) = @_;
foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($d))) {
	next if ($type && $type ne $dt);
	eval {
		local $main::error_must_die = 1;
		my @dbs = map { $_->{'name'} }
			      grep { $_->{'type'} eq $dt } @{$user->{'dbs'}};
		if (&indexof($dt, &list_database_plugins()) < 0) {
			# Create in core database
			my $crfunc = "create_${dt}_database_user";
			&$crfunc($d, \@dbs, $user->{'user'}, $user->{'pass'});
			}
		elsif (&indexof($dt, &list_database_plugins()) >= 0) {
			# Create in plugin database
			&plugin_call($dt, "database_create_user",
				     $d, \@dbs, $user->{'user'},
				     $user->{'pass'});
			}
		};
	# Show error
	if ($@) {
		return &text('user_eadddbuser', "$user->{'user'} : $@");
		}
	}
return undef;
}

# delete_databases_user(&domain, &user)
# Delete a database user from a domain
# Returns an error message on failure, or undef on success
sub delete_databases_user
{
my ($d, $user) = @_;
my @dts;
foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($d))) {
	push(@dts, $dt);
	eval {
		local $main::error_must_die = 1;
		if (&indexof($dt, &list_database_plugins()) < 0) {
			# Delete from core database
			local $dlfunc = "delete_${dt}_database_user";
			if (defined(&$dlfunc)) {
				&$dlfunc($d, $user);
				}
			}
		elsif (&indexof($dt, &list_database_plugins()) >= 0) {
			# Delete from plugin database
			&plugin_call($dt, "delete_database_user",
				$d, $user);
			}
		};
	# Show error
	if ($@) {
		my $err = &text('user_edeletedbuser', "$user : $@");
		return wantarray ? ($err) : $err;
		}
	}
return wantarray ? (0, \@dts) : undef;
}

# safe_unix_crypt(pass, salt)
# Tries to call unix_crypt, returns undef if it fails
sub safe_unix_crypt
{
local ($pass, $salt) = @_;
local $uc;
eval {
	local $main::error_must_die = 1;
	$uc = &unix_crypt($pass, $salt);
	};
return $uc;
}

# get_user_database_url()
# Returns a string to identify the remote system for storing users
sub get_user_database_url
{
&require_useradmin(1);
if ($usermodule eq "ldap-useradmin") {
	my $ldap = &ldap_useradmin::ldap_connect();
	my $rv;
	eval {
		$rv = "ldap://".$ldap->host();
		};
	if ($@) {
		# Fall back to host from config
		$rv = $ldap_useradmin::config{'ldap_host'} || "localhost";
		}
	$ldap->unbind();
	return $rv;
	}
return undef;	# Local files
}

# list_all_users_quotas([no-quotas])
# Returns a list of all Unix users, with quota info
sub list_all_users_quotas
{
# Get quotas for all users
&require_useradmin($_[0]);
local $hascmds = &has_quota_commands();
if ($hascmds) {
	# Get from user quota command
	if (!%main::soft_home_quota && !$_[0]) {
		local $out = &run_quota_command("list_users");
		foreach my $l (split(/\r?\n/, $out)) {
			local ($user, $used, $soft, $hard) = split(/\s+/, $l);
			$main::soft_home_quota{$user} = $soft;
			$main::hard_home_quota{$user} = $hard;
			$main::used_home_quota{$user} = $used;
			}
		}
	}
else {
	# Get from real quota system
	if (!%main::soft_home_quota && &has_home_quotas() && !$_[0]) {
		local $n = &quota::filesystem_users($config{'home_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$main::soft_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'sblocks'};
			$main::hard_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'hblocks'};
			$main::used_home_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ublocks'};
			$main::used_home_fquota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ufiles'};
			}
		}
	if (!%main::soft_mail_quota && &has_mail_quotas() && !$_[0]) {
		local $n = &quota::filesystem_users($config{'mail_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$main::soft_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'sblocks'};
			$main::hard_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'hblocks'};
			$main::used_mail_quota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ublocks'};
			$main::used_mail_fquota{$quota::user{$i,'user'}} =
				$quota::user{$i,'ufiles'};
			}
		}
	}

# Get user list and add in quota info
local @users = &foreign_call($usermodule, "list_users");
local %uidmap;
foreach my $u (@users) {
	$u->{'module'} = $usermodule;
	local $sameu = $uidmap{$u->{'uid'}};
	if ($sameu && !$hascmds) {
		# Quotas are set on a per-uid basis, so copy from previously
		# seem user with same ID
		$u->{'softquota'} = $sameu->{'softquota'};
		$u->{'hardquota'} = $sameu->{'hardquota'};
		$u->{'uquota'} = $sameu->{'uquota'};
		$u->{'ufquota'} = $sameu->{'ufquota'};
		$u->{'softmquota'} = $sameu->{'softmquota'};
		$u->{'hardmquota'} = $sameu->{'hardmquota'};
		$u->{'umquota'} = $sameu->{'umquota'};
		$u->{'umfquota'} = $sameu->{'umfquota'};
		}
	else {
		# Set quotas based on quota commands
		my $altuser = $u->{'user'} =~ /\@/ ?
				&replace_atsign($u->{'user'}) :
				&add_atsign($u->{'user'});
		$u->{'softquota'} = $main::soft_home_quota{$u->{'user'}} ||
				    $main::soft_home_quota{$altuser};
		$u->{'hardquota'} = $main::hard_home_quota{$u->{'user'}} ||
				    $main::hard_home_quota{$altuser};
		$u->{'uquota'} = $main::used_home_quota{$u->{'user'}} ||
				 $main::used_home_quota{$altuser};
		$u->{'ufquota'} = $main::used_home_fquota{$u->{'user'}} ||
				  $main::used_home_fquota{$altuser};
		$u->{'softmquota'} = $main::soft_mail_quota{$u->{'user'}} ||
				     $main::soft_mail_quota{$altuser};
		$u->{'hardmquota'} = $main::hard_mail_quota{$u->{'user'}} ||
				     $main::hard_mail_quota{$altuser};
		$u->{'umquota'} = $main::used_mail_quota{$u->{'user'}} ||
				  $main::used_mail_quota{$altuser};
		$u->{'umfquota'} = $main::used_mail_fquota{$u->{'user'}} ||
				   $main::used_mail_fquota{$altuser};
		}
	$u->{'unix'} = 1;
	$uidmap{$u->{'uid'}} ||= $u;
	}
return @users;
}

# list_all_groups_quotas([no-quotas])
# Returns a list of all Unix groups, with quota info
sub list_all_groups_quotas
{
# Get quotas for all groups
&require_useradmin($_[0]);
if (&has_quota_commands()) {
	# Get from user quota command
	if (!%main::gsoft_home_quota && !$_[0]) {
		local $out = &run_quota_command("list_groups");
		foreach my $l (split(/\r?\n/, $out)) {
			local ($group, $used, $soft, $hard) = split(/\s+/, $l);
			$main::gsoft_home_quota{$group} = $soft;
			$main::ghard_home_quota{$group} = $hard;
			$main::gused_home_quota{$group} = $used;
			}
		}
	}
else {
	# Get from real quota system
	if (!%main::gsoft_home_quota && &has_home_quotas() && !$_[0]) {
		local $n = &quota::filesystem_groups($config{'home_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$main::gsoft_home_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'sblocks'};
			$main::ghard_home_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'hblocks'};
			$main::gused_home_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'ublocks'};
			$main::gused_home_fquota{$quota::group{$i,'group'}} =
				$quota::group{$i,'ufiles'};
			}
		}
	if (!%main::gsoft_mail_quota && &has_mail_quotas() && !$_[0]) {
		local $n = &quota::filesystem_groups($config{'mail_quotas'});
		local $i;
		for($i=0; $i<$n; $i++) {
			$main::gsoft_mail_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'sblocks'};
			$main::ghard_mail_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'hblocks'};
			$main::gused_mail_quota{$quota::group{$i,'group'}} =
				$quota::group{$i,'ublocks'};
			$main::gused_mail_fquota{$quota::group{$i,'group'}} =
				$quota::group{$i,'ufiles'};
			}
		}
	}

# Get group list and add in quota info
local @groups = &foreign_call($usermodule, "list_groups");
local $u;
foreach $u (@groups) {
	$u->{'module'} = $usermodule;
	$u->{'softquota'} = $main::gsoft_home_quota{$u->{'group'}};
	$u->{'hardquota'} = $main::ghard_home_quota{$u->{'group'}};
	$u->{'uquota'} = $main::gused_home_quota{$u->{'group'}};
	$u->{'ufquota'} = $main::gused_home_fquota{$u->{'group'}};
	$u->{'softmquota'} = $main::gsoft_mail_quota{$u->{'group'}};
	$u->{'hardmquota'} = $main::ghard_mail_quota{$u->{'group'}};
	$u->{'umquota'} = $main::gused_mail_quota{$u->{'group'}};
	$u->{'umfquota'} = $main::gused_mail_fquota{$u->{'group'}};
	}
return @groups;
}

# need_extra_user(&user)
# Checks if an extra Unix user needs
# to be created for Postfix
sub need_extra_user
{
&require_mail();
my $needextra = 0;
if ($mail_system == 0 && $_[0]->{'user'} =~ /\@/ &&
    !$_[0]->{'webowner'}) {
	if ($config{'nopostfix_extra_user'} == 2) {
		# Explicitly enabled by the admin
		$needextra = 1;
		}
	elsif ($config{'nopostfix_extra_user'} == 0) {
		# Check if it's really needed
		my $dq = &postfix::get_real_value("resolve_dequoted_address");
		$needextra = lc($dq) eq "no" ? 0 : 1;
		}
	}
return $needextra;
}

# create_user(&user, [&domain])
# Create a mailbox or local user, his virtuser and possibly his alias
sub create_user
{
local $pop3 = &remove_userdom($_[0]->{'user'}, $_[1]);
&require_useradmin();
&require_mail();

# Add the Unix user
if ($config{'ldap_mail'}) {
	$_[0]->{'ldap_attrs'} = [ ];
	if ($_[0]->{'email'}) {
		push(@{$_[0]->{'ldap_attrs'}}, "mail",$_[0]->{'email'});
		}
	local $ea = $config{'ldap_mail'} == 2 ?
			'mailAlternateAddress' : 'mail';
	push(@{$_[0]->{'ldap_attrs'}},
	     map { ( $ea, $_ ) } @{$_[0]->{'extraemail'}});
	}
&foreign_call($usermodule, "set_user_envs", $_[0], 'CREATE_USER',
	      $_[0]->{'plainpass'}, [ ]);
&set_virtualmin_user_envs($_[0], $_[1]);
&foreign_call($usermodule, "making_changes");
&userdom_substitutions($_[0], $_[1]);
&foreign_call($usermodule, "create_user", $_[0]);
&foreign_call($usermodule, "made_changes");

# If we are running Postfix and the username has an @ in it, create an extra
# Unix user without the @ but all the other details the same
local $extrauser;
if (&need_extra_user($_[0])) {
	$extrauser = { %{$_[0]} };
	$extrauser->{'user'} = &replace_atsign($extrauser->{'user'});
	&foreign_call($usermodule, "set_user_envs", $extrauser, 'CREATE_USER', $extrauser->{'plainpass'}, [ ]);
	&set_virtualmin_user_envs($_[0], $_[1]);
	&foreign_call($usermodule, "making_changes");
	&userdom_substitutions($extrauser, $_[1]);
	&foreign_call($usermodule, "create_user", $extrauser);
	&foreign_call($usermodule, "made_changes");
	}

# Add virtusers
local $firstemail;
local @to = @{$_[0]->{'to'}};
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
foreach $e (&unique(@{$_[0]->{'extraemail'}})) {
	local $virt = { 'from' => $e,
			'to' => [ $vto ] };
	&create_virtuser($virt);
	push(@extravirt, $virt);
	$firstemail ||= $e;
	}
$_[0]->{'extravirt'} = \@extravirt;

# Add his alias, if any
if (@to) {
	local $alias = { 'name' => &escape_alias($_[0]->{'user'}),
			 'enabled' => 1,
			 'values' => $_[0]->{'to'} };
	&check_alias_clash($_[0]->{'user'}) &&
		&error(&text('alias_eclash2', $_[0]->{'user'}));
	if ($mail_system == 1) {
		&sendmail::lock_alias_files($sendmail_afiles);
		&sendmail::create_alias($alias, $sendmail_afiles);
		&sendmail::unlock_alias_files($sendmail_afiles);
		}
	elsif ($mail_system == 0) {
		&postfix::lock_alias_files($postfix_afiles);
		&$postfix_create_alias($alias, $postfix_afiles);
		&postfix::unlock_alias_files($postfix_afiles);
		&postfix::regenerate_aliases();
		}
	elsif ($mail_system == 2) {
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

if (!$_[0]->{'noquota'}) {
	# Set his initial quotas
	&set_user_quotas($_[0]->{'user'}, $_[0]->{'quota'}, $_[0]->{'mquota'},
			 $_[1]);
	&update_user_quota_cache($_[1], $_[0], 0);
	}

# Grant access to databases (unless this is the domain owner)
if ($_[1] && !$_[0]->{'domainowner'}) {
	local $dt;
	foreach $dt (&unique(map { $_->{'type'} } &domain_databases($_[1]))) {
		eval {
			local $main::error_must_die = 1;
			local @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
			next if (!@dbs);
			if (&indexof($dt, &list_database_plugins()) < 0) {
				# Create in core database
				local $crfunc = "create_${dt}_database_user";
				&$crfunc($_[1], \@dbs, $_[0]->{'user'},
					 $_[0]->{'plainpass'},
					 $_[0]->{$dt.'_pass'});
				}
			else {
				# Create in plugin database
				&plugin_call($dt, "database_create_user",
					     $_[1], \@dbs, $_[0]->{'user'},
					     $_[0]->{'plainpass'},
					     $_[0]->{$dt.'_pass'});
				}
			};
		if ($@) {
			$restore_eusersql = $text{'restore_eusersql'};
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
if ($_[1]) {
	&obtain_lock_spam($_[1]);
	&update_spam_whitelist($_[1]);
	&release_lock_spam($_[1]);
	}

if ($_[1]->{'hashpass'}) {
	# Save hashed passwords, if plain is known
	if (!-d $hashpass_dir) {
		mkdir($hashpass_dir, 0700);
		}
	if (defined($_[0]->{'plainpass'})) {
		local %hash;
		&read_file_cached("$hashpass_dir/$_[1]->{'id'}", \%hash);
		local $g = &generate_password_hashes(
				$_[0], $_[0]->{'plainpass'}, $_[1]);
		foreach my $s (@hashpass_types) {
			$hash{$_[0]->{'user'}.' '.$s} = $g->{$s};
			}
		&write_file("$hashpass_dir/$_[1]->{'id'}", \%hash);
		}
	}
else {
	# Save the plain-text password, if known
	if (!-d $plainpass_dir) {
		mkdir($plainpass_dir, 0700);
		}
	if (defined($_[0]->{'plainpass'})) {
		local %plain;
		&read_file_cached("$plainpass_dir/$_[1]->{'id'}", \%plain);
		$plain{$_[0]->{'user'}} = $_[0]->{'plainpass'};
		$plain{$_[0]->{'user'}." encrypted"} = $_[0]->{'pass'};
		&write_file("$plainpass_dir/$_[1]->{'id'}", \%plain);
		}
	}

# Save the no-spam-check flag
if (!-d $nospam_dir) {
	mkdir($nospam_dir, 0700);
	}
if ($_[0]->{'nospam'}) {
	local %nospam;
	&read_file_cached("$nospam_dir/$_[1]->{'id'}", \%nospam);
	$nospam{$_[0]->{'user'}} = 1;
	&write_file("$nospam_dir/$_[1]->{'id'}", \%nospam);
	}

# Set the user's Usermin IMAP password
if ($_[0]->{'email'} || @{$_[0]->{'extraemail'}}) {
	&set_usermin_imap_password($_[0]);
	}

# Save the recovery address
&set_usermin_recovery_address($_[0]);

# Update cache of existing usernames
$unix_user{&escape_alias($_[0]->{'user'})}++;

# Copy virtusers into alias domains
if ($_[1]) {
	&sync_alias_virtuals($_[1]);
	}

# Create everyone file for domain
if ($_[1] && $_[1]->{'mail'}) {
	&create_everyone_file($_[1]);
	}

# Sync up jail password file
if ($_[1]) {
	&create_jailkit_passwd_file($_[1]);
	&modify_jailkit_user($_[1], $_[0]);
	}

# Remove clashing records of extra user
&merge_extra_user($_[0], $_[1]);
}

# modify_user(&user, &old, &domain, [noaliases])
# Update a mail / FTP user
sub modify_user
{
my ($user, $olduser, $d, $noaliases) = @_;

# Rename any of his cron jobs
&rename_unix_cron_jobs($user->{'user'}, $olduser->{'user'});

local $pop3 = &remove_userdom($user->{'user'}, $d);
local $extrauser;
&require_useradmin();
&require_mail();

# Update the unix user
if ($config{'ldap_mail'}) {
	$user->{'ldap_attrs'} = [ ];
	if ($user->{'email'}) {
		push(@{$user->{'ldap_attrs'}}, "mail",$user->{'email'});
		}
	local $ea = $config{'ldap_mail'} == 2 ?
			'mailAlternateAddress' : 'mail';
	push(@{$user->{'ldap_attrs'}},
	     map { ( $ea, $_ ) } @{$user->{'extraemail'}});
	}
&foreign_call($usermodule, "set_user_envs", $user, 'MODIFY_USER',
	      $user->{'plainpass'}, undef, $olduser, $olduser->{'plainpass'});
&set_virtualmin_user_envs($user, $d);
&foreign_call($usermodule, "making_changes");
&userdom_substitutions($user, $d);
&foreign_call($usermodule, "modify_user", $olduser, $user);
&foreign_call($usermodule, "made_changes");

if ($mail_system == 0 && $olduser->{'user'} =~ /\@/) {
	local $esc = &replace_atsign($olduser->{'user'});
	local @allusers = &list_all_users_quotas(1);
	local ($oldextrauser) = grep { $_->{'user'} eq $esc } @allusers;
	if ($oldextrauser) {
		# Found him .. fix up
		$extrauser = { %{$user} };
		$extrauser->{'user'} = &replace_atsign($user->{'user'});
		$extrauser->{'dn'} = $oldextrauser->{'dn'};
		&foreign_call($usermodule, "set_user_envs", $extrauser,
				'MODIFY_USER', $user->{'plainpass'},
				undef, $oldextrauser,
				$olduser->{'plainpass'});
		&set_virtualmin_user_envs($user, $d);
		&foreign_call($usermodule, "making_changes");
		&userdom_substitutions($extrauser, $d);
		&foreign_call($usermodule, "modify_user",
				$oldextrauser, $extrauser);
		&foreign_call($usermodule, "made_changes");
		}
	}
goto NOALIASES if ($noaliases);	# no need to touch aliases and virtusers

# Check if email has changed
local $echanged;
if (!$user->{'email'} && $olduser->{'virt'} &&		# disabling
     $olduser->{'virt'}->{'to'}->[0] !~ /^BOUNCE/ ||
    $user->{'email'} && !$olduser->{'virt'} ||		# enabling
    $user->{'email'} && $olduser->{'virt'} &&		# changing
     $user->{'email'} ne $olduser->{'virt'}->{'from'} ||
    $user->{'email'} && $olduser->{'virt'} &&		# also enabling
     $olduser->{'virt'}->{'to'}->[0] =~ /^BOUNCE/
    ) {
	# Primary has changed
	$echanged = 1;
	}
local $oldextra = join(" ", map { $_->{'from'} } @{$olduser->{'extravirt'}});
local $newextra = join(" ", @{$user->{'extraemail'}});
if ($oldextra ne $newextra) {
	# Extra has changed
	$echanged = 1;
	}
if ($user->{'user'} ne $olduser->{'user'}) {
	# Always update on a rename
	$echanged = 1;
	}
local $oldto = join(" ", @{$olduser->{'to'}});
local $newto = join(" ", @{$user->{'to'}});
if ($oldto ne $newto) {
	# Always update if forwarding dest has changed
	$echanged = 1;
	}

local $firstemail;
local @to = @{$user->{'to'}};
local @oldto = @{$olduser->{'to'}};
if ($echanged) {
	# Take away all virtusers and add new ones, for non Qmail+LDAP users
	&delete_virtuser($olduser->{'virt'}) if ($olduser->{'virt'});
	local %oldcmt;
	foreach my $e (@{$olduser->{'extravirt'}}) {
		$oldcmt{$e->{'from'}} = $e->{'cmt'};
		&delete_virtuser($e);
		}
	local $vto = @to ? &escape_alias($user->{'user'}) :
		     $extrauser ? $extrauser->{'user'} :
				  &escape_user($user->{'user'});
	if ($user->{'email'}) {
		local $virt = { 'from' => $user->{'email'},
				'to' => [ $vto ],
				'cmt' => $oldcmt{$user->{'email'}} };
		&create_virtuser($virt);
		$user->{'virt'} = $virt;
		$firstemail ||= $user->{'email'};
		}
	elsif ($can_alias_types{9} && $d && !$user->{'noprimary'} &&
	       $d->{'mail'}) {
		# Add bouncer if email disabled
		local $virt = { 'from' => "$pop3\@$d->{'dom'}",
				'to' => [ "BOUNCE" ],
				'cmt' => $oldcmt{"$pop3\@$d->{'dom'}"} };
		&create_virtuser($virt);
		$user->{'virt'} = $virt;
		}
	local @extravirt;
	foreach my $e (&unique(@{$user->{'extraemail'}})) {
		local $virt = { 'from' => $e,
				'to' => [ $vto ],
				'cmt' => $oldcmt{$e} };
		&create_virtuser($virt);
		push(@extravirt, $virt);
		$firstemail ||= $e;
		}
	$user->{'extravirt'} = \@extravirt;
	}
else {
	# Just work out primary email address, for use by generics
	if ($user->{'email'}) {
		$firstemail ||= $user->{'email'};
		}
	foreach my $e (@{$user->{'extraemail'}}) {
		$firstemail ||= $e;
		}
	}

# Update, create or delete alias
if (@to && !@oldto) {
	# Need to add alias
	local $alias = { 'name' => &escape_alias($user->{'user'}),
			 'enabled' => 1,
			 'values' => $user->{'to'} };
	&check_alias_clash($user->{'user'}) &&
		&error(&text('alias_eclash2', $user->{'user'}));
	if ($mail_system == 1) {
		# Create Sendmail alias with same name as user
		&sendmail::lock_alias_files($sendmail_afiles);
		&sendmail::create_alias($alias, $sendmail_afiles);
		&sendmail::unlock_alias_files($sendmail_afiles);
		}
	elsif ($mail_system == 0) {
		# Create Postfix alias with same name as user
		&postfix::lock_alias_files($postfix_afiles);
		&$postfix_create_alias($alias, $postfix_afiles);
		&postfix::unlock_alias_files($postfix_afiles);
		&postfix::regenerate_aliases();
		}
	elsif ($mail_system == 2) {
		# Set up user's .qmail file
		local $dqm = &dotqmail_file($user);
		&lock_file($dqm);
		&save_dotqmail($alias, $dqm, $pop3);
		&unlock_file($dqm);
		}
	$user->{'alias'} = $alias;
	}
elsif (!@to && @oldto) {
	# Need to delete alias
	if ($mail_system == 1) {
		# Delete Sendmail alias
		&lock_file($user->{'alias'}->{'file'});
		&sendmail::delete_alias($user->{'alias'});
		&unlock_file($user->{'alias'}->{'file'});
		}
	elsif ($mail_system == 0) {
		# Delete Postfix alias
		&lock_file($user->{'alias'}->{'file'});
		&$postfix_delete_alias($user->{'alias'});
		&unlock_file($user->{'alias'}->{'file'});
		&postfix::regenerate_aliases();
		}
	elsif ($mail_system == 2) {
		# Remove user's .qmail file
		local $dqm = &dotqmail_file($user);
		&unlink_logged($dqm);
		}
	}
elsif (@to && @oldto && join(" ", @to) ne join(" ", @oldto)) {
	# Need to update the alias
	local $alias = { 'name' => &escape_alias($user->{'user'}),
			 'enabled' => 1,
			 'values' => $user->{'to'} };
	if ($mail_system == 1) {
		# Update Sendmail alias
		&lock_file($olduser->{'alias'}->{'file'});
		&sendmail::modify_alias($olduser->{'alias'}, $alias);
		&unlock_file($olduser->{'alias'}->{'file'});
		}
	elsif ($mail_system == 0) {
		# Update Postfix alias
		&lock_file($olduser->{'alias'}->{'file'});
		&$postfix_modify_alias($olduser->{'alias'}, $alias);
		&unlock_file($olduser->{'alias'}->{'file'});
		&postfix::regenerate_aliases();
		}
	elsif ($mail_system == 2) {
		# Set up user's .qmail file
		local $dqm = &dotqmail_file($user);
		&lock_file($dqm);
		&save_dotqmail($alias, $dqm, $pop3);
		&unlock_file($dqm);
		}
	$user->{'alias'} = $alias;
	}

if ($config{'generics'} && $echanged) {
	# Update genericstable entry too
	if ($olduser->{'generic'}) {
		&delete_generic($olduser->{'generic'});
		}
	if ($firstemail) {
		&create_generic($user->{'user'}, $firstemail);
		}
	}
&sync_alias_virtuals($d);
NOALIASES:

# Save his quotas if changed (unless this is the domain owner)
if ($d && $user->{'user'} ne $d->{'user'} &&
    !$user->{'noquota'} &&
    ($user->{'quota'} != $olduser->{'quota'} ||
     $user->{'mquota'} != $olduser->{'mquota'})) {
	&set_user_quotas($user->{'user'}, $user->{'quota'}, $user->{'mquota'},
			 $d);
	if ($user->{'user'} ne $olduser->{'user'}) {
		&update_user_quota_cache($olduser, $user, 1);
		}
	&update_user_quota_cache($d, $user, 0);
	}

# Update the plain-text password file, except for a domain owner
if (!$user->{'domainowner'} && $d && !$d->{'hashpass'}) {
	local %plain;
	mkdir($plainpass_dir, 0700);
	&read_file_cached("$plainpass_dir/$d->{'id'}", \%plain);
	if ($user->{'user'} ne $olduser->{'user'}) {
		$plain{$user->{'user'}} = $plain{$olduser->{'user'}};
		delete($plain{$olduser->{'user'}});
		$plain{$user->{'user'}." encrypted"} =
			$plain{$olduser->{'user'}." encrypted"};
		delete($plain{$olduser->{'user'}." encrypted"});
		}
	if (defined($user->{'plainpass'})) {
		$plain{$user->{'user'}} = $user->{'plainpass'};
		$plain{$user->{'user'}." encrypted"} = $user->{'pass'};
		}
	&write_file("$plainpass_dir/$d->{'id'}", \%plain);
	}

# Update hashed passwords file, except for domain owner
if (!$user->{'domainowner'} && $d && $d->{'hashpass'}) {
	local %hash;
	mkdir($hashpass_dir, 0700);
	&read_file_cached("$hashpass_dir/$d->{'id'}", \%hash);
	if ($user->{'user'} ne $olduser->{'user'}) {
		foreach my $s (@hashpass_types) {
			$hash{$user->{'user'}.' '.$s} =
				$hash{$olduser->{'user'}.' '.$s};
			delete($hash{$olduser->{'user'}.' '.$s});
			}
		}
	if (defined($user->{'plainpass'})) {
		# Re-hash new password
		local $g = &generate_password_hashes(
				$user, $user->{'plainpass'}, $d);
		foreach my $s (@hashpass_types) {
			$hash{$user->{'user'}.' '.$s} = $g->{$s};
			$user->{'pass_'.$s} = $g->{$s};
			}
		}
	&write_file("$hashpass_dir/$d->{'id'}", \%hash);
	}

# Update his allowed databases (unless this is the domain owner), if any
# have been added or removed.
&modify_database_user(@_);

# Rename user in secondary groups, and update membership
local @groups = &list_all_groups();
local %secs = map { $_, 1 } @{$user->{'secs'}};
local @sgroups = &allowed_secondary_groups($d);
foreach my $group (@groups) {
	local @mems = split(/,/, $group->{'members'});
	local $idx = &indexof($olduser->{'user'}, @mems);
	local $changed;
	if ($idx >= 0) {
		# User is currently in group
		if ($user->{'user'} ne $olduser->{'user'}) {
			# Just rename in group, if needed
			$changed = 1;
			$mems[$idx] = $user->{'user'};
			}
		elsif (!$secs{$group->{'group'}}) {
			# Remove from group, if this is a secondary managed
			# by Virtualmin
			if (&indexof($group->{'group'}, @sgroups) >= 0) {
				splice(@mems, $idx, 1);
				$changed = 1;
				}
			}
		}
	elsif ($secs{$group->{'group'}}) {
		# User is not in group, but needs to be
		push(@mems, $user->{'user'});
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
&update_secondary_groups($d) if ($d);

# Update spamassassin whitelist
if ($d) {
	&obtain_lock_spam($d);
	&update_spam_whitelist($d);
	&release_lock_spam($d);
	}

# Update the no-spam-check flag
if ($d) {
	if (!-d $nospam_dir) {
		mkdir($nospam_dir, 0700);
		}
	if (defined($user->{'nospam'})) {
		local %nospam;
		&read_file_cached("$nospam_dir/$d->{'id'}", \%nospam);
		if ($user->{'user'} ne $olduser->{'user'}) {
			delete($nospam{$olduser->{'user'}});
			}
		$nospam{$user->{'user'}} = $user->{'nospam'};
		&write_file("$nospam_dir/$d->{'id'}", \%nospam);
		}
	}

# Update the last logins file
if ($user->{'user'} ne $olduser->{'user'}) {
	&lock_file($mail_login_file);
	my %logins;
	&read_file_cached($mail_login_file, \%logins);
	if ($logins{$olduser->{'user'}}) {
		$logins{$user->{'user'}} = $logins{$olduser->{'user'}};
		delete($logins{$olduser->{'user'}});
		&write_file($mail_login_file, \%logins);
		}
	&unlock_file($mail_login_file);
	}

# Clear quota cache for this user
if (defined(&clear_lookup_domain_cache) && $d) {
	&clear_lookup_domain_cache($d, $user);
	}

# Set the user's Usermin IMAP password
if (($user->{'email'} || @{$user->{'extraemail'}}) &&
    $user->{'plainpass'} && $olduser->{'plainpass'} &&
    $user->{'plainpass'} ne $olduser->{'plainpass'}) {
	&set_usermin_imap_password($user);
	}

# Save the recovery address
&set_usermin_recovery_address($user);

# Update cache of existing usernames
if ($user->{'user'} ne $olduser->{'user'}) {
	$unix_user{&escape_alias($user->{'user'})}++;
	$unix_user{&escape_alias($olduser->{'user'})} = 0;
	}

if ($user->{'shell'} ne $olduser->{'shell'}) {
	# Rebuild denied user list, by shell
	&build_denied_ssh_group();
	}

# Rebuild group of domain owners
if ($user->{'domainowner'}) {
	&update_domain_owners_group();
	}

# Create everyone file for domain
if ($d && $d->{'mail'}) {
	&create_everyone_file($d);
	}

# Sync up jail password file
if ($d) {
	if ($olduser->{'user'} ne $user->{'user'}) {
		&rename_jailkit_passwd_file($d, $olduser->{'user'},
					    $user->{'user'});
		}
	&create_jailkit_passwd_file($d);
	&modify_jailkit_user($d, $user);
	}
}

# delete_user(&user, &domain)
# Delete a mailbox user and all associated virtusers and aliases
sub delete_user
{
# For extra specific user associated
# with domain delete it and return
if ($_[0]->{'extra'}) {
	if ($_[0]->{'type'} eq 'db') {
		# Delete database user
		my ($err, $dts) = &delete_databases_user($_[1], $_[0]->{'user'});
		&error($err) if ($err);
		# Delete user from domain config
		&delete_extra_user($_[1], $_[0]);
		}
	if ($_[0]->{'type'} eq 'web') {
		&delete_webserver_user($_[0], $_[1]);
		}
	return undef;
	}

# Check if deleted user present in other users aliases
&remove_forward_in_other_users($_[0], $_[1]);

# Zero out his quotas
if (!$_[0]->{'noquota'}) {
	&set_user_quotas($_[0]->{'user'}, 0, 0, $_[1]);
	&update_user_quota_cache($_[1], $_[0], 1);
	}

# Delete any of his cron jobs
&delete_unix_cron_jobs($_[0]->{'user'});

# Delete Unix user
$_[0]->{'user'} eq 'root' && &error("Cannot delete root user!");
$_[0]->{'uid'} == 0 && &error("Cannot delete UID 0 user!");
&require_useradmin();
&require_mail();

# Delete the user
&foreign_call($usermodule, "set_user_envs", $_[0], 'DELETE_USER');
&set_virtualmin_user_envs($_[0], $_[1]);
&foreign_call($usermodule, "making_changes");
&foreign_call($usermodule, "delete_user", $_[0]);
&foreign_call($usermodule, "made_changes");

# Record the old UID to prevent re-use
&record_old_uid($_[0]->{'uid'});

if ($mail_system == 0 && $_[0]->{'user'} =~ /\@/) {
	# Find the Unix user with the @ escaped and delete it too
	local $esc = &replace_atsign_if_exists($_[0]->{'user'});
	local @allusers = &list_all_users_quotas(1);
	local ($extrauser) = grep { $_->{'user'} eq $esc } @allusers;
	if ($extrauser) {
		&foreign_call($usermodule, "set_user_envs", $extrauser, 'DELETE_USER');
		&set_virtualmin_user_envs($_[0], $_[1]);
		&foreign_call($usermodule, "making_changes");
		&foreign_call($usermodule, "delete_user", $extrauser);
		&foreign_call($usermodule, "made_changes");
		}
	}

# Delete any virtusers (extra email addresses for this user)
&delete_virtuser($_[0]->{'virt'}) if ($_[0]->{'virt'});
local $e;
foreach $e (@{$_[0]->{'extravirt'}}) {
	&delete_virtuser($e);
	}

# Delete his alias (for forwarding), if any
if ($_[0]->{'alias'}) {
	if ($mail_system == 1) {
		# Delete Sendmail alias with same name as user
		if (!$_[0]->{'alias'}->{'deleted'}) {
			&lock_file($_[0]->{'alias'}->{'file'});
			&sendmail::delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			$_[0]->{'alias'}->{'deleted'} = 1;
			}
		}
	elsif ($mail_system == 0) {
		# Delete Postfix alias with same name as user
		if (!$_[0]->{'alias'}->{'deleted'}) {
			&lock_file($_[0]->{'alias'}->{'file'});
			&$postfix_delete_alias($_[0]->{'alias'});
			&unlock_file($_[0]->{'alias'}->{'file'});
			&postfix::regenerate_aliases();
			$_[0]->{'alias'}->{'deleted'} = 1;
			}
		}
	elsif ($mail_system == 2) {
		# .qmail will be deleted when user is
		}
	}

if ($config{'generics'} && $_[0]->{'generic'}) {
	# Delete genericstable entry too
	&delete_generic($_[0]->{'generic'});
	}

# Delete database access (unless this is the domain owner)
if ($_[1] && !$_[0]->{'domainowner'}) {
	local $dt;
	foreach $dt (&unique(map { $_->{'type'} } &domain_databases($_[1]))) {
		local @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
		if (@dbs && &indexof($dt, &list_database_plugins()) < 0) {
			# Delete from core database
			local $dlfunc = "delete_${dt}_database_user";
			&$dlfunc($_[1], $_[0]->{'user'});
			}
		elsif (@dbs && &indexof($dt, &list_database_plugins()) >= 0) {
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
if ($_[1]) {
	&obtain_lock_spam($_[1]);
	&update_spam_whitelist($_[1]);
	&release_lock_spam($_[1]);
	}

# Remove the plain-text password
local %plain;
if (!-d $plainpass_dir) {
	mkdir($plainpass_dir, 0700);
	}
&read_file_cached("$plainpass_dir/$_[1]->{'id'}", \%plain);
delete($plain{$_[0]->{'user'}});
delete($plain{$_[0]->{'user'}." encrypted"});
&write_file("$plainpass_dir/$_[1]->{'id'}", \%plain);

# Remove the hashed password
local %hash;
if (!-d $hashpass_dir) {
	mkdir($hashpass_dir, 0700);
	}
&read_file_cached("$hashpass_dir/$_[1]->{'id'}", \%hash);
foreach my $s (@hashpass_types) {
	delete($hash{$_[0]->{'user'}.' '.$s});
	}
&write_file("$hashpass_dir/$_[1]->{'id'}", \%hash);

# Clear the no-spam flag
local %spam;
if (!-d $nospam_dir) {
	mkdir($nospam_dir, 0700);
	}
&read_file_cached("$nospam_dir/$_[1]->{'id'}", \%spam);
delete($spam{$_[0]->{'user'}});
&write_file("$nospam_dir/$_[1]->{'id'}", \%spam);

# Update cache of existing usernames
$unix_user{&escape_alias($_[0]->{'user'})} = 0;

# Delete from last logins file
&lock_file($mail_login_file);
my %logins;
&read_file_cached($mail_login_file, \%logins);
if ($logins{$_[0]->{'user'}}) {
	delete($logins{$_[0]->{'user'}});
	&write_file($mail_login_file, \%logins);
	}
&unlock_file($mail_login_file);

# Create everyone file for domain, minus the user
if ($_[1] && $_[1]->{'mail'}) {
	&create_everyone_file($_[1]);
	}

if ($_[1]) {
	&sync_alias_virtuals($_[1]);
	}

# Sync up jail password file
if ($_[1]) {
	&create_jailkit_passwd_file($_[1]);
	}
}

# modify_databse_user(&user, &olduser, &domain)
# Updates the database user, including database
# permissions and password
sub modify_database_user
{
my $newdbstr = join(" ", map { $_->{'type'}."_".$_->{'name'} }
				@{$_[0]->{'dbs'}});
my $olddbstr = join(" ", map { $_->{'type'}."_".$_->{'name'} }
				@{$_[1]->{'dbs'}});
if ($_[2] && !$_[0]->{'domainowner'} &&
    ($newdbstr ne $olddbstr ||
     $_[0]->{'pass'} ne $_[1]->{'pass'} ||
     $_[0]->{'user'} ne $_[1]->{'user'})) {
	foreach my $dt (&unique(map { $_->{'type'} } &domain_databases($_[2]))) {
		my @dbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[0]->{'dbs'}};
		my @olddbs = map { $_->{'name'} }
				 grep { $_->{'type'} eq $dt } @{$_[1]->{'dbs'}};
		my $plugin = &indexof($dt, &list_database_plugins()) >= 0;
		if (@dbs && !@olddbs) {
			# Need to add database user
			if (!$plugin) {
				my $crfunc = "create_${dt}_database_user";
				&$crfunc($_[2], \@dbs, $_[0]->{'user'},
					 $_[0]->{'plainpass'},
					 $_[0]->{'pass_'.$dt});
				}
			else {
				&plugin_call($dt, "database_create_user",
					     $_[2], \@dbs, $_[0]->{'user'},
					     $_[0]->{'plainpass'},
					     $_[0]->{'pass_'.$dt});
				}
			}
		elsif (@dbs && @olddbs) {
			# Need to update database user
			if (!$plugin) {
				my $mdfunc = "modify_${dt}_database_user";
				&$mdfunc($_[2], \@olddbs, \@dbs,
					 $_[1]->{'user'}, $_[0]->{'user'},
					 $_[0]->{'plainpass'},
					 $_[0]->{'pass_'.$dt});
				}
			else {
				&plugin_call($dt, "database_modify_user",
					     $_[2], \@olddbs, \@dbs,
					     $_[1]->{'user'}, $_[0]->{'user'},
					     $_[0]->{'plainpass'},
					     $_[0]->{'pass_'.$dt});
				}
			}
		elsif (!@dbs && @olddbs) {
			# Need to delete database user
			if (!$plugin) {
				my $dlfunc = "delete_${dt}_database_user";
				&$dlfunc($_[2], $_[1]->{'user'});
				}
			else {
				&plugin_call($dt, "database_delete_user",
					     $_[2], $_[1]->{'user'});
				}
			}
		}
	}
}

# set_usermin_imap_password(&user)
# If Usermin is setup to use an IMAP inbox on localhost, set this user's
# IMAP password
sub set_usermin_imap_password
{
local ($user) = @_;
return 0 if (!$user->{'home'});
return 0 if (!$user->{'plainpass'});

# Make sure Usermin is installed, and the mailbox module is setup for IMAP
return 0 if (!&foreign_check("usermin"));
&foreign_require("usermin");
return 0 if (!&usermin::get_usermin_module_info("mailbox"));
local %mconfig;
&read_file("$usermin::config{'usermin_dir'}/mailbox/config", \%mconfig);
return 0 if ($mconfig{'mail_system'} != 4);
return 0 if ($mconfig{'pop3_server'} ne '' &&
             $mconfig{'pop3_server'} ne 'localhost' &&
	     $mconfig{'pop3_server'} ne '127.0.0.1' &&
	     &to_ipaddress($mconfig{'pop3_server'}) ne &to_ipaddress(&get_system_hostname()));

# Set the password
&create_usermin_module_directory($user, "mailbox");
if (-d "$user->{'home'}/.usermin/mailbox") {
	local %inbox;
	local $imapfile = "$user->{'home'}/.usermin/mailbox/inbox.imap";
	&read_file($imapfile, \%inbox);
	if (&usermin::get_usermin_version() >= 1.323) {
		$inbox{'user'} = '*';
		}
	else {
		$inbox{'user'} = $user->{'user'};
		}
	$inbox{'pass'} = $user->{'plainpass'};
	$inbox{'nologout'} = 1;
	eval {
		# Ignore errors here, in case user is over quota
		local $main::error_must_die = 1;
		&write_as_mailbox_user($user,
			sub { &write_file($imapfile, \%inbox);
			      &set_ownership_permissions(undef, undef,
							 $imapfile, 0600) });
		};
	}
}

# create_usermin_module_directory(&user, module)
# Creates the Usermin config directories for a user
sub create_usermin_module_directory
{
my ($user, $mod) = @_;
foreach my $dir ($user->{'home'}, "$user->{'home'}/.usermin", "$user->{'home'}/.usermin/$mod") {
	next if ($user->{'webowner'} && $dir eq $user->{'home'});
	next if ($user->{'domainowner'} && $dir eq $user->{'home'});
	if (!-e $dir) {
		if ($dir eq $user->{'home'}) {
			&make_dir($dir, 0700);
			&set_ownership_permissions(
				$user->{'uid'}, $user->{'gid'}, 0700, $dir);
			}
		else {
			&write_as_mailbox_user($user,
				sub { &make_dir($dir, 0700);
				      &set_ownership_permissions(undef, undef,
								 0700, $dir) });
			}
		}
	}
}

# set_usermin_recovery_address(&user)
# Updates the password recovery file for a user
sub set_usermin_recovery_address
{
my ($user) = @_;
return 0 if (!$user->{'home'});
&create_usermin_module_directory($user, "changepass");
if (-d "$user->{'home'}/.usermin/changepass") {
	my $rfile = "$user->{'home'}/.usermin/changepass/recovery";
	eval {
		# Ignore errors here, in case user is over quota
		local $main::error_must_die = 1;
		&write_as_mailbox_user($user,
			sub { open(RECOVERY, ">$rfile");
			      if ($user->{'recovery'}) {
				print RECOVERY $user->{'recovery'},"\n";
			      }
			      close(RECOVERY);
			      &set_ownership_permissions(undef, undef,
							 $rfile, 0600) });
		};
	return 1;
	}
return 0;
}

# delete_unix_cron_jobs(username)
# Delete all Cron jobs belonging to some Unix user
sub delete_unix_cron_jobs
{
local ($username) = @_;
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
local $cronfile;
foreach my $j (@jobs) {
	if ($j->{'user'} eq $username) {
		$cronfile ||= &cron::cron_file($j);
		&lock_file($cronfile);
		&cron::delete_cron_job($j);
		}
	}
if ($cron::config{'cron_dir'} && $username) {
	# Make sure file is gone
	&unlink_file($cron::config{'cron_dir'}."/".$username);
	}
&unlock_file($cronfile) if ($cronfile);
}

# rename_unix_cron_jobs(username, oldusername)
# Change the name of the user who owns any cron jobs
sub rename_unix_cron_jobs
{
local ($username, $oldusername) = @_;
return if ($username eq $oldusername);
&foreign_require("cron");
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
		&cron::change_cron_job($j);
		}
	}
&unlock_file($cronfile) if ($cronfile);
}

# copy_unix_cron_jobs(username, oldusername)
# Duplicate all cron jobs for some domain user
sub copy_unix_cron_jobs
{
local ($username, $oldusername) = @_;
return if ($username eq $oldusername);
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
foreach my $j (@jobs) {
	if ($j->{'user'} eq $oldusername) {
		local $newj = { %$j };
		$newj->{'user'} = $username;
		&cron::create_cron_job($newj);
		}
	}
}

# disable_unix_cron_jobs(username)
# Disable all Cron jobs belonging to some Unix user
sub disable_unix_cron_jobs
{
local ($username) = @_;
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
local $cronfile;
foreach my $j (@jobs) {
	if ($j->{'user'} eq $username && $j->{'active'} && !$j->{'name'}) {
		$cronfile ||= &cron::cron_file($j);
		&lock_file($cronfile);
		$j->{'active'} = 0;
		if ($j->{'command'} !~ /#\s+VIRTUALMIN\s+DISABLE/) {
			$j->{'command'} .= " # VIRTUALMIN DISABLE";
			}
		&cron::change_cron_job($j);
		}
	}
&unlock_file($cronfile) if ($cronfile);
}

# enable_unix_cron_jobs(username)
# Enable all Cron jobs belonging to some Unix user
sub enable_unix_cron_jobs
{
local ($username) = @_;
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
local $cronfile;
foreach my $j (@jobs) {
	if ($j->{'user'} eq $username && !$j->{'active'} && !$j->{'name'} &&
	    $j->{'command'} =~ /#\s+VIRTUALMIN\s+DISABLE/) {
		$cronfile ||= &cron::cron_file($j);
		&lock_file($cronfile);
		$j->{'active'} = 1;
		$j->{'command'} =~ s/\s+#\s+VIRTUALMIN\s+DISABLE//g;
		&cron::change_cron_job($j);
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
	if (!$user->{'plainpass'} && !$user->{'pass_mysql'}) {
		return $text{'user_edbpass'};
		}
	# Check for username clash
	return &check_any_database_user_clash($d, $user->{'user'})
		if (!$user->{'nocheck'});
	}
if ($d && $user->{'home'} &&
    (!$old || $old->{'home'} ne $user->{'home'}) &&
    !&is_under_directory($d->{'home'}, $user->{'home'})) {
	# Home dir is outside domain's home
	return &text('user_ehomehome', $d->{'home'});
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
	    $tmpl->{'quotatype'} eq 'hard' ? ( int($_[1]), int($_[1]) )
					   : ( int($_[1]), 0 ));
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

# update_user_quota_cache(&domain, &user|&users, [deleting])
# Updates the cache file of mailbox quotas for this virtual server
sub update_user_quota_cache
{
my ($d, $userlist, $deleting) = @_;
my $users = ref($userlist) eq 'ARRAY' ? $userlist : [ $userlist ];
&make_dir($quota_cache_dir, 0755) if (!-d $quota_cache_dir);
my $qfile = $quota_cache_dir."/".$d->{'id'};
my %cache;
&lock_file($qfile);
&read_file_cached($qfile, \%cache);
foreach my $user (@$users) {
	my $u = $user->{'user'};
	if ($deleting) {
		delete($cache{$u."_quota"});
		delete($cache{$u."_mquota"});
		}
	else {
		$cache{$u."_quota"} = $user->{'quota'};
		if (defined($user->{'mquota'})) {
			$cache{$u."_mquota"} = $user->{'mquota'}
			}
		else {
			delete($cache{$u."_mquota"});
			}
		}
	}
&write_file($qfile, \%cache);
&unlock_file($qfile);
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
local $salt = $user->{'pass'};
$salt =~ s/^\!//;
return &foreign_call($usermodule, "encrypt_password", $pass, $salt);
}

# generate_password_hashes(&user, text, &domain)
# Given a password, returns a hash ref of it hashed into different formats.
# Keys returned are :
# md5 - MD5 hash
# crypt - Unix crypt
# unix - Appropriate hash for Unix user
# mysql - MySQL password hash
# digest - Web digest authentication hash
sub generate_password_hashes
{
local ($user, $pass, $d) = @_;
local $tmpl = &get_template($d->{'template'});
if ($tmpl->{'hashtypes'} eq 'none') {
	# Don't return any hash types
	return { };
	}
&require_useradmin();
local %rv;
local $salt = $user->{'pass'} && $user->{'pass'} !~ /\$/ ? $user->{'pass'}
							 : &random_salt();
$salt =~ s/^\!// if ($salt);
$rv{'crypt'} = &unix_crypt($pass, $salt);
if (!&useradmin::check_md5()) {
	local $salt = $user->{'pass'} &&
		      $user->{'pass'} =~ /\$1\$/ ? $user->{'pass'} : undef;
	$salt =~ s/^\!// if ($salt);
	$rv{'md5'} = &useradmin::encrypt_md5($pass);
	}
$rv{'unix'} = &encrypt_user_password($user, $pass);
if ($config{'mysql'}) {
	&require_mysql();
	eval {
		# This can fail if MySQL is down
		local $main::error_must_die = 1;
		local $qpass = &mysql_escape($pass);
		local $pf = &get_mysql_password_func($d);
		local $rv = &execute_dom_sql($d, $mysql::master_db,
					     "select $pf('$qpass')");
		$rv{'mysql'} = $rv->{'data'}->[0]->[0];
		};
	}
if (&foreign_check("htaccess-htpasswd")) {
	&foreign_require("htaccess-htpasswd");
	$rv{'digest'} = &htaccess_htpasswd::digest_password(
				$user->{'user'}, $d->{'dom'}, $pass);
	}
if ($tmpl->{'hashtypes'} ne '' && $tmpl->{'hashtypes'} ne '*') {
	# Remove disabled types
	local %newrv;
	foreach my $t (split(/\s+/, $tmpl->{'hashtypes'})) {
		$newrv{$t} = $rv{$t} if (defined($rv{$t}));
		}
	return \%newrv;
	}
else {
	# Just return all types
	return \%rv;
	}
}

# list_password_hash_types()
# Returns a list of all supported hashing types and their descriptions
sub list_password_hash_types
{
return ( map { [ $_, $text{'hashtype_'.$_} ] } @hashpass_types );
}

# generate_domain_password_hashes(&domain, new-domain?)
# Updates a domain object with the appropriate password hash fields. For use
# when creating a new domain.
sub generate_domain_password_hashes
{
local ($d, $newdom) = @_;
local $parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
if ($newdom) {
	if ($parent) {
		# Inherit from parent
		$d->{'hashpass'} ||= $parent->{'hashpass'};
		}
	else {
		# Inherit from template
		local $tmpl = &get_template($d->{'template'});
		$d->{'hashpass'} ||= $tmpl->{'hashpass'};
		}
	}
return if (!$d->{'hashpass'});	# Hashing disabled
if ($d->{'parent'}) {
	# Just copy from parent
	$parent = &get_domain($d->{'parent'});
	foreach my $k ('enc_pass', 'mysql_enc_pass', 'crypt_enc_pass',
		       'md5_enc_pass', 'digest_enc_pass') {
		$d->{$k} = $parent->{$k};
		}
	}
else {
	# Hash and store
	return if (!$d->{'pass'});	# Plaintext password unknown
	local $fakeuinfo = { 'user' => $d->{'user'} };
	local $hashes = &generate_password_hashes(
				$fakeuinfo, $d->{'pass'}, $d);
	$d->{'enc_pass'} = $hashes->{'unix'};
	if (!$d->{'mysql_pass'}) {
		$d->{'mysql_enc_pass'} = $hashes->{'mysql'};
		}
	$d->{'crypt_enc_pass'} = $hashes->{'crypt'};
	$d->{'md5_enc_pass'} = $hashes->{'md5'};
	$d->{'digest_enc_pass'} = $hashes->{'digest'};
	}
$d->{'hashpass'} = 1;
delete($d->{'pass'});
}

# create_user_home(&uinfo, &domain, always-chown)
# Creates the home directory for a new mail user, and copies skel files into it
sub create_user_home
{
local ($user, $d, $always) = @_;
local $home = $user->{'home'};
if ($home) {
	# Create his homedir
	local @st = $d ? stat($d->{'home'}) : ( undef, undef, 0755 );
	if (!-e $home || $always) {
		&lock_file($home);
		&make_dir($home, $st[2] & 0777);
		&set_ownership_permissions($user->{'uid'}, $user->{'gid'},
					   $st[2] & 0777, $home);
		&system_logged("chown -R $user->{'uid'}:$user->{'gid'} ".
			       quotemeta($home));
		&unlock_file($home);
		}

	# Copy files into homedir. Don't die if this fails for quota issues
	eval {
		local $main::error_must_die = 1;
		&copy_skel_files(
			&substitute_domain_template($config{'mail_skel'}, $d),
			$user, $home);
		};
	}
}

# delete_user_home(&user, &domain)
# Deletes the home directory of a user, if valid
sub delete_user_home
{
local ($user, $d) = @_;
if (-d $user->{'home'} &&
    !&same_file($user->{'home'}, $d->{'home'}) &&
    &safe_delete_dir($d, $user->{'home'})) {
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
return &text('indom', "<tt>".&show_domain_name($_[0])."</tt>");
}

# copy_skel_files(basedir, &user, home, [group], [&for-domain])
# Copy files to the home directory of some new user
sub copy_skel_files
{
local ($uf, $user, $home, $group, $d) = @_;
return if (!$uf);

# Find all files under the skeleton dir
my @files = &find_recursive_files($uf);
my @copied;
foreach my $f (@files) {
	local $src = "$uf/$f";		# Needs to be local, for subs
	local $dst = "$home/$f";
	my $func;

	# Get file info as root before copying
	local @st = stat($src);
	local $data;
	if (-f $src) {
		$data = &read_file_contents($src);
		}
	local $lnk = readlink($src);

	if (-l $src) {
		# Re-create symlink
		$func = sub { &symlink_file($lnk, $dst) };
		}
	elsif (-d $src) {
		# Re-create directory
		$func = sub { $st[2] ||= 0755;
			      &make_dir($dst, $st[2] & 07777) };
		}
	else {
		# Copy file contents
		$func = sub { return if (!defined($data));
			      &open_tempfile(SKEL, ">$dst", 0, 1);
			      &print_tempfile(SKEL, $data);
			      &close_tempfile(SKEL);
			      &set_ownership_permissions(
				undef, undef, $st[2], $dst) };
		}
	if ($user) {
		&write_as_mailbox_user($user, $func);
		}
	else {
		&$func();
		}
	push(@copied, $dst);
	}

# Perform variable substition on the files, if requested
if ($d) {
	local $tmpl = &get_template($d->{'template'});
	if ($tmpl->{'skel_subs'}) {
		foreach my $c (@copied) {
			if (-r $c && !-d $c && !-l $c &&
			    (!$tmpl->{'skel_onlysubs'} ||
			     &match_skel_subs($c, $tmpl->{'skel_onlysubs'})) &&
			    !&match_skel_subs($c, $tmpl->{'skel_nosubs'}) &&
			    &guess_mime_type($c) !~ /^image\//) {
				local $data =
				    &read_file_contents_as_domain_user($d, $c);
				&open_tempfile_as_domain_user($d, OUT, ">$c");
				&print_tempfile(OUT,
					&substitute_domain_template($data, $d));
				&close_tempfile_as_domain_user($d, OUT);
				}
			}
		}
	}
}

# match_skel_subs(path, nosubs-list)
# Returns 1 if some filename matches the space-separated list of patterns given
sub match_skel_subs
{
my ($path, $nosubs_str) = @_;
return 0 if ($nosubs_str !~ /\S/);
my @nosubs = &split_quoted_string($nosubs_str);
foreach my $ns (@nosubs) {
	$path =~ /^(\S+)\/([^\/]+)$/ || next;
	my ($dir, $file) = ($1, $2);
	my @matches = glob("$dir/$ns");
	if (&indexof($path, @matches) >= 0) {
		return 1;
		}
	}
return 0;
}

# find_recursive_files(dir, [name])
# Given a directory, recursively finds all files and directories under it and
# returns their relative paths
sub find_recursive_files
{
my ($dir, $name) = @_;
opendir(SKELDIR, $dir);
my @files = grep { $_ ne '.' && $_ ne '..' } readdir(SKELDIR);
closedir(SKELDIR);
my @rv;
foreach my $f (@files) {
	my $path = "$dir/$f";
	if (-l $path || !-d $path) {
		push(@rv, $f) if (!$name || $f eq $name);
		}
	elsif (-d $path) {
		push(@rv, $f) if (!$name || $f eq $name);
		push(@rv, map { "$f/$_" } &find_recursive_files($path, $name));
		}
	}
return @rv;
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
		return &indexof($base_remote_user,
				split(/\s+/, $_[0]->{'reseller'})) >= 0;
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
return &can_edit_domain($d) && !$d->{'protected'} &&
       (&master_admin() || &reseller_admin() && !$access{'nodelete'} ||
	$_[0]->{'parent'} && $access{'edit_delete'});
}

# can_associate_domain(&domain)
# Only the master admin is allowed to disconnect or connect features
sub can_associate_domain
{
return &master_admin();
}

sub can_move_domain
{
local ($d) = @_;
return &can_edit_domain($d) &&
       (&master_admin() || &reseller_admin());
}

sub can_transfer_domain
{
return &master_admin();
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
if ($config{'show_sysinfo'} == 1) {
	# Show to everyone
	return 1;
	}
elsif ($config{'show_sysinfo'} == 2) {
	# Show to root only
	return &master_admin();
	}
elsif ($config{'show_sysinfo'} == 3) {
	# Show to root and resellers (not used)
	return &master_admin() || &reseller_admin();
	}
else {
	# Show to nobody (not used)
	return 0;
	}
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

# Returns 1 if the user can migrate servers from other control panels with
# no limits, 2 if only remote file migration is allowed, and 3 if only
# remote file migration of sub-servers is allowed.
sub can_migrate_servers
{
if (!$access{'import'} && !$access{'migrate'}) {
	return 0;
	}
elsif (&master_admin()) {
	# Root can import everything
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can import from remote
	return 2;
	}
else {
	# Domain owners can migrate sub-servers from remote, iff they can also
	# restore backups
	return &can_restore_domain() ? 3 : 0;
	}
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
# Returns 1 if the current user can use some feature at domain creation time,
# or enable or disable it for existing domains
sub can_use_feature
{
local ($f) = @_;
if (&master_admin()) {
	# Master admin can use anything
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can use features they have been granted, or features
	# that are forced on
	return $config{$f} == 3 || $access{"feature_".$f};
	}
else {
	# Domain owners can use granted features (but never change the Unix
	# account, which will be always on)
	if ($f eq 'unix') {
		return 0;
		}
	else {
		return $config{$f} == 3 || $access{"feature_".$f};
		}
	}
}

# Returns 1 if the current user is allowed to select a private or shared
# IP for a virtual server
sub can_select_ip
{
local @shared = &list_shared_ips();
return &can_use_feature("virt") ||
       @shared && &can_edit_sharedips();
}

# Returns 1 if the current user is allowed to select a private or shared
# IPv6 address for a virtual server
sub can_select_ip6
{
local @shared = &list_shared_ip6s();
return &can_use_feature("virt6") ||
       @shared && &can_edit_sharedips();
}

# can_edit_limits(&domain)
# Returns 1 if owner limits can be edited in some domain
sub can_edit_limits
{
return &master_admin() ||
       &reseller_admin() && &can_edit_domain($_[0]);
}

# can_edit_res(&domain)
# Returns 1 if memory / process limits can be edited in some domain
sub can_edit_res
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
return &master_admin() || &reseller_admin() || $access{'edit_dbs'};
}

# Returns 1 if the current user can change this name of his default DB
sub can_edit_database_name
{
return &master_admin() || &reseller_admin() || !$access{'nodbname'};
}

sub can_edit_admins
{
local ($d) = @_;
return $d->{'webmin'} &&
       (&master_admin() ||
	&reseller_admin() && !$access{'noadmins'} ||
	$access{'edit_admins'});
}

sub can_edit_spam
{
return &master_admin() || &reseller_admin() || $access{'edit_spam'};
}

# Returns 2 if all website options can be edited, 1 if only non-suexec related
# settings, 0 if nothing
sub can_edit_phpmode
{
return &master_admin() ? 2 :
       &reseller_admin() ? 1 :
       $access{'edit_phpmode'} ? 1 : 0;
}

sub can_edit_phpver
{
return &master_admin() || &reseller_admin() || $access{'edit_phpver'};
}

sub can_edit_sharedips
{
return &master_admin() ||
       &reseller_admin() && !$access{'nosharedips'} ||
       $access{'edit_sharedips'};
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
return &master_admin() || &reseller_admin() || $access{'edit_scripts'};
}

sub can_unsupported_scripts
{
return &master_admin();
}

sub can_edit_forward
{
return &master_admin() ||
       &reseller_admin() && !$access{'noproxy'} ||
       $access{'edit_forward'};
}

sub can_edit_redirect
{
return &master_admin() || &reseller_admin() || $access{'edit_redirect'};
}

sub can_edit_ssl
{
return &master_admin() || &reseller_admin() || $access{'edit_ssl'};
}

sub can_edit_letsencrypt
{
return &master_admin() ||
       &reseller_admin() && $config{'can_letsencrypt'} <= 1 ||
       $config{'can_letsencrypt'} == 0;
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
return !$access{'admin'} && &can_backup_domain();
}

# can_edit_dns(&domain)
# Allow master admin, resellers, domain owners with DNS options permissions
sub can_edit_dns
{
local ($d) = @_;
return &master_admin() || &reseller_admin() || $access{'edit_spf'};
}

# can_edit_dmarc(&domain)
# Allow master admin, resellers, domain owners with DNS options permissions
sub can_edit_dmarc
{
local ($d) = @_;
return &master_admin() || &reseller_admin() || $access{'edit_spf'};
}

# can_edit_records(&domain)
# Allow master admin, resellers, domain owners with DNS records permission
sub can_edit_records
{
local ($d) = @_;
return &master_admin() || &reseller_admin() || $access{'edit_records'};
}

sub can_edit_mail
{
return &master_admin() || &reseller_admin() || $access{'edit_mail'};
}

# Returns 1 if the current user can disable and enable the given domain
sub can_disable_domain
{
local ($d) = @_;
return &can_edit_domain($d) && !$d->{'protected'} &&
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
local $tmpl = &get_template($_[0]->{'template'});
return &master_admin() ||
       $access{'edit_ip'} && &can_use_feature("virt") &&
       $tmpl->{'ranges'} ne "none";
}

# can_mailbox_home(&user)
# Returns 1 if the current Webmin user can choose the home directory of some
# mailbox user
sub can_mailbox_home
{
local ($user) = @_;
return &master_admin() ||
       $config{'edit_homes'} == 1 ||
       $config{'edit_homes'} == 2 && $user->{'webowner'};
}

# Returns 1 if the current user can create FTP mailboxes
sub can_mailbox_ftp
{
return &master_admin() || $config{'edit_ftp'};
}

# Returns 1 if the current user can create SSH-capable mailboxes
sub can_mailbox_ssh
{
if (&master_admin()) {
	return 1;
	}
elsif (&reseller_admin()) {
	return 0;
	}
else {
	my $d = &get_domain_by("user", $base_remote_user);
	return 0 if (!$d);
	my $shellpath = &get_domain_shell($d);
	return 0 if (!$shellpath);
	my @ashells = &list_available_shells($d);
	my ($shell) = grep { $_->{'shell'} eq $shellpath } @ashells;
	return $shell && $shell->{'id'} eq 'ssh';
	}
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
local ($tmpl) = @_;
if (&master_admin()) {
	# Root can use all templates
	return 1;
	}
if ($tmpl->{'resellers'} ne '*') {
	# Template has a reseller restriction, check it
	local %resels = map { $_, 1 } split(/\s+/, $tmpl->{'resellers'});
	if (&reseller_admin()) {
		# Is current user in the reseller list?
		return 0 if (!$resels{$base_remote_user});
		}
	else {
		# Is user's reseller in list?
		local $dom = &get_domain_by("user", $base_remote_user,
					    "parent", undef);
		if (!($dom && $dom->{'reseller'} &&
		      $resels{$dom->{'reseller'}})) {
			return 0;
			}
		}
	}
if ($tmpl->{'owners'} ne '*' && !&reseller_admin()) {
	# Template has owner restrictions, check them
	local %owners = map { $_, 1 } split(/\s+/, $tmpl->{'owners'});
	return 0 if (!$owners{$base_remote_user});
	}
return 1;
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

# can_switch_user(&domain, [extra-admin])
# Returns 1 if the current user can switch to the Webmin login for some domain
sub can_switch_user
{
local ($d, $admin) = @_;
return $main::session_id &&	# When using session auth
       !$access{'admin'} &&	# Not for extra admins
       (&master_admin() ||	# Master can switch, or domain owner to extras
	&reseller_admin() && &can_edit_domain($d) ||
	$admin && &can_edit_domain($d));
}

# can_switch_usermin(&domain, &user)
# Returns 1 if the current user is allowed to switch to Usermin
sub can_switch_usermin
{
local ($d, $user) = @_;
return &can_edit_domain($d) &&
       &master_admin() || $config{'usermin_switch'};
}

# Returns 1 if the user can view mail logs for some domain (or all domains if
# none was given). Also returns 0 if mail logs are not enabled.
sub can_view_maillog
{
local ($d) = @_;
return 0 if ($config{'maillog_hide'} == 2 ||
	     $config{'maillog_hide'} == 1 && !&master_admin());
return 0 if (!&procmail_logging_enabled());
if ($d) {
	return &can_edit_domain($d);
	}
else {
	return &master_admin();
	}
}

# Returns 1 if the current user can see the preview website link
sub can_use_preview
{
return $config{'show_preview'} == 2 ||
       $config{'show_preview'} == 1 && &master_admin();
}

# can_use_validation()
# Returns 1 if the current user can validate virtual servers, 2 if they can
# setup scheduled validaton.
sub can_use_validation
{
if (&master_admin()) {
	return 2;
	}
elsif ($config{'show_validation'} >= 1 && &reseller_admin()) {
	return 1;
	}
elsif ($config{'show_validation'} == 2) {
	return 1;
	}
else {
	return 0;
	}
}

# can_forward_alias(address)
# Returns 1 if forwarding to some remote address is allowed
sub can_forward_alias
{
my ($a) = @_;
return 1 if (&master_admin());
return 1 if ($config{'remote_alias'});
my %allowed = map { $_->{'dom'}, 1 } &list_domains();
$allowed{&get_system_hostname(0)} = 1;
$allowed{&get_system_hostname(1)} = 1;
foreach my $e (&extract_address_parts($a)) {
	my ($mb, $dn) = split(/\@/, $e);
	next if (!$dn);
	$allowed{lc($dn)} || return 0;
	}
return 1;
}

# domains_table(&domains, [checkboxes], [return-html], [exclude-cols])
# Display a list of domains in a table, with links for editing
sub domains_table
{
local ($doms, $checks, $noprint, $exclude) = @_;
$exclude ||= [ ];
local %emap = map { $_, 1 } @$exclude;
local $usercounts = &count_domain_users();
local $aliascounts = &count_domain_aliases(1);
local @table_features = grep { $config{$_} } split(/,/, $config{'index_fcols'});
local $showchecks = $checks && &can_config_domain($_[0]->[0]);

# Generate headers
local @heads;
if ($showchecks) {
	push(@heads, "");
	}
my @colnames = split(/,/, $config{'index_cols'});
if (!@colnames) {
	@colnames = ( 'dom', 'user', 'owner', 'users', 'aliases', 'lastlogin' );
	}
if (!&has_home_quotas()) {
	@colnames = grep { $_ ne 'quota' && $_ ne 'uquota' } @colnames;
	}
@colnames = grep { !$emap{$_} } @colnames;
if (!defined(&list_resellers)) {
	@colnames = grep { $_ ne 'reseller' } @colnames;
	}
push(@heads, map { $text{'index_'.$_} } @colnames);
foreach my $f (&list_custom_fields()) {
	if ($f->{'show'} && ($f->{'visible'} < 2 || &master_admin())) {
		push(@colnames, 'field_'.$f->{'name'});
		my ($desc, $tip) = split(/;/, $f->{'desc'});
		push(@heads, $desc);
		}
	}
push(@heads, map { $text{'index_'.$_} } @table_features);

# Generate the table contents
local @table;
foreach my $d (&sort_indent_domains($doms)) {
	$done{$d->{'id'}}++;
	local $pfx = "&nbsp;" x ($d->{'indent'} * 2);
	local @cols;

	# Add configured columns
	foreach my $c (@colnames) {
		if ($c eq "dom") {
			# Domain name, with link
			my $prog = &can_config_domain($d) ? "edit_domain.cgi"
							  : "view_domain.cgi";
			my $dn = &shorten_domain_name($d);
			$dn = $d->{'disabled'} ? &ui_text_color("<i>$dn</i>", 'danger') : $dn;
			my $proxy = $d->{'proxy_pass_mode'} == 2 ?
			 " <a href='frame_form.cgi?dom=$d->{'id'}'>(F)</a>" :
				    $d->{'proxy_pass_mode'} == 1 ?
			 " <a href='proxy_form.cgi?dom=$d->{'id'}'>(P)</a>" :"";
			push(@cols, "$pfx<a href='$prog?".
				    "dom=$d->{'id'}'>$dn</a>$proxy");
			}
		elsif ($c eq "type") {
			my $dtype = $d->{'alias'} ? "$pfx$text{'form_generic_aliasshort'}" :
				    $d->{'parent'} ? "$pfx$text{'form_generic_subserver'}" :
				    $text{'form_generic_master'};
			push(@cols, $dtype);
			}
		elsif ($c eq "user") {
			# Username
			push(@cols, &html_escape($d->{'user'}));
			}
		elsif ($c eq "owner") {
			# Domain description / owner
			if ($d->{'alias'}) {
				my $aliasdom = &get_domain($d->{'alias'});
				my $of = &text('index_aliasof',
						$aliasdom->{'dom'});
				push(@cols, &html_escape($d->{'owner'} || $of));
				}
			else {
				push(@cols, &html_escape($d->{'owner'}));
				}
			}
		elsif ($c eq "emailto") {
			# Email address
			push(@cols, &html_escape($d->{'emailto'}));
			}
		elsif ($c eq "reseller") {
			# Reseller name
			push(@cols, &html_escape($d->{'reseller'}));
			}
		elsif ($c eq "admins") {
			# Extra admin names
			my @admins = map { $_->{'name'} }
					 &list_extra_admins($d);
			if (&can_edit_admins($d)) {
				@admins = map { "<a href='edit_admin.cgi?".
						"dom=$d->{'id'}&name=".
						&urlize($_)."'>".
						&html_escape($_)."</a>" }
					      @admins;
				}
			push(@cols, join(' ', @admins));
			}
		elsif ($c eq "users") {
			# User count
			if (&can_domain_have_users($d)) {
				# Link to users
				my $uc = int($usercounts->{$d->{'id'}});
				if (&can_edit_users()) {
					push(@cols, $uc."&nbsp;".
					     "(<a href='list_users.cgi?".
					     "dom=$d->{'id'}'>".
					     $text{'index_list'}."</a>)");
					}
				else {
					push(@cols, $uc);
					}
				}
			else {
				push(@cols, "");
				}
			}
		elsif ($c eq "aliases") {
			# Alias count, with link
			if ($d->{'mail'}) {
				my $ac = int($aliascounts->{$d->{'id'}});
				if (&can_edit_aliases() && !$d->{'aliascopy'}) {
					push(@cols, $ac."&nbsp;".
					     "(<a href='list_aliases.cgi?".
					     "dom=$d->{'id'}'>".
					     $text{'index_list'}."</a>)");
					}
				else {
					push(@cols, scalar(@aliases));
					}
				}
			else {
				push(@cols, $text{'index_nomail'});
				}
			}
		elsif ($c eq "quota") {
			# Quota assigned
			my $qd = $d->{'parent'} ? &get_domain($d->{'parent'})
						: $d;
			push(@cols, $qd->{'quota'} ?
			  &quota_show($qd->{'quota'}, "home") :
			  $text{'form_unlimit'});
			}
		elsif ($c eq "uquota") {
			# Quota used
			if ($d->{'alias'} || $d->{'parent'}) {
				# Alias and sub-servers have no usage
				push(@cols, &nice_size(0));
				}
			else {
				# Show total usage for domain
				my $qmax = $d->{'quota'} ?
				    $d->{'quota'}*&quota_bsize("home") : undef;
				my ($hq, $mq, $dbq) = &get_domain_quota($d, 1);
				my $ut = $hq*&quota_bsize("home") +
					 $mq*&quota_bsize("mail") + $dbq;
				local $txt = &nice_size($ut);
				if ($qmax && $bytes > $qmax) {
					$txt ="<font color=#ff0000>$txt</font>";
					}
				push(@cols, $txt);
				}
			}
		elsif ($c eq "created") {
			# Creation date
			push(@cols, &make_date($d->{'created'}, 1));
			}
		elsif ($c eq "plan") {
			# Account plan
			my $p;
			if ($d->{'plan'} ne '' && defined(&get_plan) &&
			    ($p = &get_plan($d->{'plan'}))) {
				push(@cols, $p->{'name'});
				}
			else {
				push(@cols, "");
				}
			}
		elsif ($c eq "phpv") {
			# PHP version
			my $ver;
			if (&domain_has_website($d)) {
				$ver = &get_domain_php_version($d);
				$ver ||= &get_apache_mod_php_version();
				$ver = &get_php_version($ver) || $ver;
				}
			push(@cols, $ver);
			}
		elsif ($c eq "ip") {
			# IP address
			my $ip = $d->{'ip'};
			$ip = "<i>$ip</i>" if ($d->{'virt'});
			push(@cols, $ip);
			}
		elsif ($c eq "ssl_expiry") {
			# SSL cert expiry
			if (!&domain_has_ssl_cert($d)) {
				push(@cols, "");
				}
			elsif ($d->{'ssl_cert_expiry'}) {
				my $exp = $d->{'ssl_cert_expiry'};
				push(@cols, &human_time_delta($exp)." ".
						&ui_help(&make_date($exp)));
				}
			else {
				push(@cols, "<i>$text{'maillog_unknown'}</i>");
				}
			}
		elsif ($c eq "lastlogin") {
			my $last = $d->{'last_login_timestamp'};
			if ($last && $last > 0) {
				$last = &human_time_delta($last)." ".
						&ui_help(&make_date($last));
				}
			else {
				$last = $text{'users_ll_never'};
				}
			push(@cols, $last);
			}
		elsif ($c =~ /^field_/) {
			# Some custom field
			push(@cols, &html_escape($d->{$c}));
			}
		}
	foreach $f (@table_features) {
		push(@cols, $d->{$f} ? $text{'yes'} : $text{'no'});
		}
	if (&can_config_domain($d) && $showchecks) {
		unshift(@cols, { 'type' => 'checkbox',
				 'name' => 'd', 'value' => $d->{'id'} });
		}
	push(@table, \@cols);
	}

# Output the table
local $rv = &ui_columns_table(\@heads, 100, \@table);
if ($noprint) {
	return $rv;
	}
else {
	print $rv;
	}
}

# userdom_name(name, &domain, [force-append-style])
# Returns a username with the domain prefix (usually group) appended somehow
sub userdom_name
{
my ($name, $d, $append_style) = @_;
if (!defined($append_style)) {
	if (defined($d->{'append_style'})) {
		$append_style = $d->{'append_style'};
		}
	else {
		my $tmpl = &get_template($d->{'template'});
		$append_style = $tmpl->{'append_style'};
		}
	}
if ($append_style == 0) {
	return $name.".".$d->{'prefix'};
	}
elsif ($append_style == 1) {
	return $name."-".$d->{'prefix'};
	}
elsif ($append_style == 2) {
	return $d->{'prefix'}.".".$name;
	}
elsif ($append_style == 3) {
	return $d->{'prefix'}."-".$name;
	}
elsif ($append_style == 4) {
	return $name."_".$d->{'prefix'};
	}
elsif ($append_style == 5) {
	return $d->{'prefix'}."_".$name;
	}
elsif ($append_style == 6) {
	return $name."\@".$d->{'dom'};
	}
elsif ($append_style == 7) {
	return $name."\%".$d->{'prefix'};
	}
else {
	&error("Unknown append_style $append_style");
	}
}

# guess_append_style(username, &domain)
# Returns the append_style number used for some username, or undef if unknown
sub guess_append_style
{
local ($name, $d) = @_;
local $p = $d->{'prefix'};
local $dom = $d->{'dom'};
return $name =~ /\.\Q$p\E$/ ? 0 :
       $name =~ /\-\Q$p\E$/ ? 1 :
       $name =~ /^\Q$p\E\./ ? 2 :
       $name =~ /^\Q$p\E\-/ ? 3 :
       $name =~ /_\Q$p\E$/ ? 4 :
       $name =~ /^\Q$p\E_/ ? 5 :
       $name =~ /\@\Q$dom\E$/ ? 6 :
       $name =~ /\%\Q$p\E$/ ? 7 : undef;
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
($rv =~ s/\@(\Q$d\E)$//) || ($rv =~ s/(\.|\-|_|\%)\Q$g\E$//) || ($rv =~ s/^\Q$g\E(\.|\-|_|\%)//);
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

# valid_alias_name(name)
# Returns an error message if an alias name contains bogus characters
sub valid_alias_name
{
local ($name) = @_;
if ($name !~ /^[^ \t:\&\(\)\|\;\<\>\*\?\!\/\\]+$/) {
	return $text{'user_euser'};
	}
return undef;
}

# valid_mailbox_name(name)
# Returns an error message if a mailbox name contains bogus characters, or uses
# a reserved name
sub valid_mailbox_name
{
local ($name) = @_;
&require_useradmin();
local $err = &valid_alias_name($name);
return $err if ($err);
if ($name eq "domains" || $name eq "logs" || $name eq $home_virtualmin_backup) {
	return &text('user_ereserved', $name);
	}
if ($name =~ /^\d+/) {
	return $text{'user_enumeric'};
	}
$err = &useradmin::check_username_restrictions($name);
if ($err) {
	return $err;
	}
return undef;
}

sub max_username_length
{
&require_useradmin();
return $uconfig{'max_length'};
}

# get_default_ip([reseller-list])
# Returns this system's primary IP address. If a reseller is given and he
# has a custom IP, use that.
sub get_default_ip
{
local ($reselname) = @_;
if ($reselname && defined(&get_reseller)) {
	# Check if the reseller has an IP
	foreach my $r (split(/\s+/, $reselname)) {
		local $resel = &get_reseller($r);
		if ($resel && $resel->{'acl'}->{'defip'}) {
			return $resel->{'acl'}->{'defip'};
			}
		}
	}
if ($config{'defip'}) {
	# Explicitly set on module config page
	return $config{'defip'};
	}
elsif (&running_in_zone()) {
	# From zone's interface
	&foreign_require("net");
	local ($iface) = grep { $_->{'up'} &&
				&net::iface_type($_->{'name'}) =~ /ethernet/i }
			      &net::active_interfaces();
	return $iface ? $iface->{'address'} : undef;
	}
else {
	# From interface detected at check time
	&foreign_require("net");
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

# get_default_ip6([reseller-name])
# Returns this system's primary IPv6 address. If a reseller is given and he
# has a custom IP, use that.
sub get_default_ip6
{
local ($reselname) = @_;
if ($reselname && defined(&get_reseller)) {
	# Check if the reseller has an IP
	local $resel = &get_reseller($reselname);
	if ($resel && $resel->{'acl'}->{'defip6'}) {
		return $resel->{'acl'}->{'defip6'};
		}
	}
if ($config{'defip6'}) {
	# Explicitly set on module config page
	return $config{'defip6'};
	}
else {
	# From interface detected at check time
	&foreign_require("net");
	local $ifacename = $config{'iface'} || &first_ethernet_iface();
	local ($iface) = grep { $_->{'fullname'} eq $ifacename }
			      &net::boot_interfaces();
	if ($iface) {
		# Use address on the boot interface if possible, as active
		# IPv6 addresses can get re-ordered
		my $best = &best_ip6_address($iface);
		return $best if ($best);
		}
	# Otherwise, fall back to first active address
	($iface) = grep { $_->{'fullname'} eq $ifacename }
			&net::active_interfaces();
	if ($iface) {
		my $best = &best_ip6_address($iface);
		return $best if ($best);
		}
	return undef;
	}
}

# best_ip6_address(&iface)
# Returns the best IPv6 address (not local) from an interface
sub best_ip6_address
{
local ($iface) = @_;
return undef if (!$iface->{'address6'});
foreach my $a (@{$iface->{'address6'}}) {
	next if ($a eq '::1');		 # localhost
	next if ($a =~ /^fe80::/);	 # Link local
	next if ($a =~ /^2000::/);	 # Global unicast
	next if ($a eq '::');		 # Unknown
	next if ($a =~ /^(fec0|fc00):/); # Site local 
	return $a;
	}
return undef;
}

# first_ethernet_iface()
# Returns the name of the first active ethernet interface
sub first_ethernet_iface
{
&foreign_require("net");
my @active = &net::active_interfaces();

# First try to find a non-virtual Ethernet interface
foreach my $a (@active) {
	if ($a->{'up'} && $a->{'virtual'} eq '' &&
	    $a->{'address'} ne '127.0.0.1' &&
	    (&net::iface_type($a->{'name'}) =~ /ethernet/i ||
	     $a->{'name'} =~ /^bond/)) {
		return $a->{'fullname'};
		}
	}

# Failing that, look for a virtual interface. On some VPS systems, the
# main interface is actually venet0:0
foreach my $a (@active) {
	if ($a->{'up'} &&
	    $a->{'address'} ne '127.0.0.1' &&
	    (&net::iface_type($a->{'name'}) =~ /ethernet/i ||
	     $a->{'name'} =~ /^venet/)) {
		return $a->{'fullname'};
		}
	}

return undef;
}

# get_address_iface(address)
# Given an IPv4 or v6 address, returns the interface name
sub get_address_iface
{
local ($a) = @_;
&foreign_require("net");
local ($iface) = grep {
	$_->{'address'} eq $a ||
	&indexof(&net::canonicalize_ip6($a),
		 (map { &net::canonicalize_ip6($_) } @{$_->{'address6'}})) >= 0
	} &net::active_interfaces();
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

# Return optional javascript to force scroll to the botton
sub bottom_scroll_js
{
if ($main::force_bottom_scroll &&
    $ENV{'HTTP_X_REQUESTED_WITH'} ne "XMLHttpRequest") {
	return "<script>".
	       "window.scrollTo(0, document.body.scrollHeight)".
	       "</script>\n";
	}
else {
	return "";
	}
}

# Print functions for HTML output
sub first_html_print { print_and_capture("<span data-first-print>@_</span>","<br>\n");
		       print bottom_scroll_js(); }
sub second_html_print { print_and_capture("<span data-second-print>@_</span>",
					  "<br>".&vui_brh()."\n");
		        print bottom_scroll_js(); }
sub indent_html_print { print_and_capture("<ul data-indent-print>\n");
		        print bottom_scroll_js(); }
sub outdent_html_print { print_and_capture("</ul>\n");
		         print bottom_scroll_js(); }

# Print functions for text output
sub first_text_print
{
print_and_capture($indent_text,
      (map { &html_tags_to_text(&entities_to_ascii($_)) } @_),"\n");
}

sub second_text_print
{
print_and_capture($indent_text,
      (map { &html_tags_to_text(&entities_to_ascii($_)) } @_),"\n\n");
}

sub indent_text_print { $indent_text .= "    "; }
sub outdent_text_print { $indent_text = substr($indent_text, 4); }
sub html_tags_to_text
{
local ($rv, $disallow_newlines, $allow_links) = @_;
my $newline = "\n";
if ($disallow_newlines) {
	$newline = " " if ($disallow_newlines);
	$rv =~ s/\n/ /g;
	}
$rv =~ s/<tt>|<\/tt>//g;
$rv =~ s/<span.*?>|<\/span>//g;
$rv =~ s/<sup.*?(data-title|aria-label)="([^"]*)".*?<\/sup>//g;
$rv =~ s/<sup.*?>|<\/sup>//g;
$rv =~ s/<b>|<\/b>//g;
$rv =~ s/<i>|<\/i>//g;
$rv =~ s/<u>|<\/u>//g;
$rv =~ s/<a[^>]*>|<\/a>//g if (!$allow_links);
$rv =~ s/<pre>|<\/pre>//g;
$rv =~ s/<br>|<br\s[^>]*>/$newline/g;
$rv =~ s/<p>|<\/p>/$newline$newline/g;
$rv =~ s/<p>|<p\s[^>]*>/$newline$newline/g;
$rv = &entities_to_ascii($rv);
return $rv;
}

# Print functions for caturing output
sub first_capture_print
{
$print_output .= $indent_text.
    join("", (map { &html_tags_to_text(&entities_to_ascii($_)) } @_))."\n";
}
sub second_capture_print
{
$print_output .= $indent_text.
    join("", (map { &html_tags_to_text(&entities_to_ascii($_)) } @_))."\n\n";
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
sub set_all_capture_print
{
$first_print = \&first_capture_print;
$second_print = \&second_capture_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;
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

# Start capturing output
sub start_print_capture
{
$print_capture = 1;
$print_output = undef;
}

# Stop capturing output, and return what we have
sub stop_print_capture
{
$print_capture = 1;
return $print_output;
}

sub print_and_capture
{
print @_;
if ($print_capture) {
	$print_output .= join("", @_);
	}
}

# will_send_domain_email(&domain)
# Returns 1 if email would be sent to this domain at signup time
sub will_send_domain_email
{
local $tmpl = &get_template($_[0]->{'template'});
return $tmpl->{'mail_on'} ne 'none';
}

# send_domain_email(&domain, [force-to], [password])
# Sends the signup email to a new domain owner. Returns a pair containing a
# number (0=failed, 1=success) and an optional message. Also outputs status
# messages.
sub send_domain_email
{
local ($d, $forceto, $pass) = @_;
local $tmpl = &get_template($d->{'template'});
local $mail = $tmpl->{'mail'};
local $subject = $tmpl->{'mail_subject'};
local $cc = $tmpl->{'mail_cc'};
local $bcc = $tmpl->{'mail_bcc'};
if ($tmpl->{'mail_on'} eq 'none') {
	return (1, undef);
	}
&$first_print($text{'setup_email'});

local %hash = &make_domain_substitions($d, 1);
$hash{'pass'} = $pass if ($pass);
local @erv = &send_template_email($mail, $forceto || $d->{'emailto'},
			    	  \%hash, $subject, $cc, $bcc, undef,
				  &get_global_from_address($d));
if ($erv[0]) {
	&$second_print(&text('setup_emailok', $erv[1]));
	}
else {
	&$second_print(&text('setup_emailfailed', $erv[1]));
	}
return @erv;
}

# make_domain_substitions(&domain, [nice-sizes])
# Returns a hash of substitions for email to a virtual server
sub make_domain_substitions
{
local ($d, $nice_sizes) = @_;
local %hash = %$d;
local $tmpl = &get_template($d->{'template'});

delete($hash{''});
$hash{'idndom'} = &show_domain_name($d->{'dom'});	# With unicode

# Convert disabled_time to timestamp
if ($d->{'disabled_time'}) {
	$hash{'disabled_time'} = &make_date($d->{'disabled_time'});
	}

# Add parent domain info
local $parent;
if ($d->{'parent'}) {
	$parent = &get_domain($d->{'parent'});
	foreach my $k (keys %$parent) {
		$hash{'parent_domain_'.$k} = $parent->{$k};
		}
	delete($hash{'parent_domain_'});
	}

# Add alias target domain info
if ($d->{'alias'}) {
	local $alias = &get_domain($d->{'alias'});
	foreach my $k (keys %$alias) {
		$hash{'alias_domain_'.$k} = $alias->{$k};
		}
	delete($hash{'alias_domain_'});
	}

# Add (first) reseller details
if ($d->{'reseller'} && defined(&get_reseller)) {
	my @r = split(/\s+/, $d->{'reseller'});
	local $resel = &get_reseller($r[0]);
	local $acl = $resel->{'acl'};
	$hash{'reseller_name'} = $resel->{'name'};
	$hash{'reseller_theme'} = $resel->{'theme'};
	$hash{'reseller_modules'} = join(" ", @{$resel->{'modules'}});
	foreach my $a (keys %$acl) {
		$hash{'reseller_'.$a} = $acl->{$a};
		}
	}

# Add plan details, if any
local $plan = &get_plan($d->{'plan'});
if ($plan) {
	foreach my $k (keys %$plan) {
		$hash{'plan_'.$k} = $plan->{$k};
		}
	}

# Add DNS serial number, for use in DNS templates
if ($config{'dns'}) {
	&require_bind();
	if ($bind8::config{'soa_style'} == 1) {
		$hash{'dns_serial'} = &bind8::date_serial().
			sprintf("%2.2d", $bind8::config{'soa_start'});
		}
	else {
		# Use Unix time for date and running number serials
		$hash{'dns_serial'} = time();
		}
	}
else {
	# BIND not installed, so default to using unix time for serial
	$hash{'dns_serial'} = time();
	}

# Add DNS master nameserver
if ($config{'dns'}) {
	$hash{'dns_master'} = &get_master_nameserver($tmpl);
	}

# Add webmin and usermin ports
$hash{'virtualmin_url'} = &get_virtualmin_url($d);
local %miniserv;
&get_miniserv_config(\%miniserv);
$hash{'webmin_port'} = $miniserv{'port'};
$hash{'webmin_proto'} = $miniserv{'ssl'} ? 'https' : 'http';
if (&foreign_installed('usermin')) {
	&foreign_require('usermin');
	local %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	$hash{'usermin_port'} = $uminiserv{'port'};
	$hash{'usermin_proto'} = $uminiserv{'ssl'} ? 'https' : 'http';
	}

# Make quotas nicer, if needed
if ($nice_sizes) {
	if ($hash{'quota'}) {
		$hash{'quota'} = &nice_size($d->{'quota'}*&quota_bsize("home"));
		}
	if ($hash{'uquota'}) {
		$hash{'uquota'} = &nice_size($d->{'uquota'}*&quota_bsize("home"));
		}
	if ($hash{'bw_limit'}) {
		$hash{'bw_limit'} = &nice_size($d->{'bw_limit'});
		}
	if ($hash{'bw_usage'}) {
		$hash{'bw_usage'} = &nice_size($d->{'bw_usage'});
		}
	if ($config{'bw_period'}) {
		$hash{'bw_period'} = $config{'bw_period'};
		$hash{'bw_past'} = '';
		}
	else {
		$hash{'bw_past'} = $config{'bw_past'};
		$hash{'bw_period'} = '';
		}
	}

# Set mysql_pass to blank if missing, so that it can be used if $IF
$hash{'mysql_pass'} ||= '';
$hash{'postgres_pass'} ||= '';

# Setup MySQL and PostgreSQL usernames if not set yet
if ($d->{'mysql'} && !$hash{'mysql_user'}) {
	$hash{'mysql_user'} = &mysql_user($d);
	if ($d->{'parent'}) {
		$hash{'mysql_pass'} = $parent->{'mysql_pass'};
		}
	}
if ($d->{'postgres'} && !$hash{'postgres_user'}) {
	$hash{'postgres_user'} = &postgres_user($d);
	if ($d->{'parent'}) {
		$hash{'postgres_pass'} = $parent->{'postgres_pass'};
		}
	}

# Add remote MySQL and PostgreSQL hosts
if ($d->{'mysql'}) {
	$hash{'mysql_host'} = &get_database_host_mysql($d);
	$hash{'mysql_port'} = &get_database_port_mysql($d);
	}
if ($d->{'postgres'}) {
	$hash{'postgres_host'} = &get_database_host_postgres($d);
	$hash{'postgres_port'} = &get_database_port_postgres($d);
	}

# Add random numbers length 1-10
&seed_random();
for(my $i=1; $i<=10; $i++) {
	my $r;
	do {
		$r = int(rand()*(10**$i));
		} while(length($r) != $i);
	$hash{"RANDOM$i"} = $r;
	}

# Add secondary mail servers
local %ids = map { $_, 1 } split(/\s+/, $d->{'mx_servers'});
if (%ids) {
	local @servers = grep { $ids{$_->{'id'}} } &list_mx_servers();
	$hash{'mx_slaves'} = join(" ", map { $_->{'host'} } @servers);
	}
else {
	$hash{'mx_slaves'} = '';
	}

# Add secondary nameservers
if ($config{'dns'}) {
	local %on = map { $_, 1 } split(/\s+/, $d->{'dns_slave'});
	local @servers = grep { $on{$_->{'host'}} || $on{$_->{'nsname'}} }
			      &bind8::list_slave_servers();
	$hash{'dns_server'} = &get_master_nameserver($tmpl);
	$hash{'dns_slave'} = join(" ", map { $_->{'nsname'} || $_->{'host'} }
					   @servers);
	}
else {
	$hash{'dns_slave'} = '';
	}

# If any website feature is enabled (like Nginx), set the web variable
if (&domain_has_website($d)) {
	$hash{'web'} = 1;
	}

# Add domain parts
my @parts = split(/\./, $d->{'dom'});
for(my $i=0; $i<@parts; $i++) {
	$hash{'dompart'.$i} = $parts[$i];
	}

return %hash;
}

# will_send_user_email([&domain], [new-flag])
# Returns 1 if a new mailbox email would be sent to a user in this domain.
# Will return 0 if no template is defined, or if sending mail to the mailbox
# has been deactivated, or if the domain doesn't even have email
sub will_send_user_email
{
local ($d, $isnew) = @_;
return 0 if ($d->{'domainowner'});
local $tmpl = &get_template($d ? $d->{'template'} : 0);
local $tmode = !$d || $isnew ? "newuser" : "updateuser";
if ($tmpl->{$tmode.'_on'} eq 'none' ||
    $tmode eq "newuser" && !$tmpl->{$tmode.'_to_mailbox'}) {
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
local $tmpl = &get_template($d ? $d->{'template'} : 0);
local $tmode = $mode ? "updateuser" : "newuser";
local $subject = $tmpl->{$tmode.'_subject'};
if ($tmpl->{$tmode.'_on'} eq 'none') {
	return (1, undef);
	}

# Work out who we CC to
local @ccs;
push(@ccs, $tmpl->{$tmode.'_cc'}) if ($tmpl->{$tmode.'_cc'});
push(@ccs, $d->{'emailto'}) if ($d && $tmpl->{$tmode.'_to_owner'});
if ($tmpl->{$tmode.'_to_reseller'} && $d && $d->{'reseller'} &&
    defined(&get_reseller)) {
	foreach my $r (split(/\s+/, $d->{'reseller'})) {
		local $resel = &get_reseller($r);
		if ($resel && $resel->{'acl'}->{'email'}) {
			push(@ccs, &extract_address_parts(
				$resel->{'acl'}->{'email'}));
			}
		}
	}
local $cc = join(",", @ccs);
local $bcc = $tmpl->{$tmode.'_bcc'};

local $mail = $tmpl->{$tmode};
return (1, undef) if ($mail eq 'none');
local %hash = &make_user_substitutions($user, $d);
local $email = $d ? $hash{'mailbox'}.'@'.$hash{'dom'}
		  : $hash{'user'}.'@'.&get_system_hostname();

# Work out who we send to
if ($userto) {
	$email = $userto eq 'none' ? undef : $userto;
	}
if ($d && !$tmpl->{$tmode.'_to_mailbox'}) {
	# Don't email domain owner if disabled
	$email = undef;
	}
return (1, undef) if (!$email && !$cc && !$bcc);

return &send_template_email($mail, $email, \%hash,
			    $subject ||
			    &entities_to_ascii($mode ? $text{'mail_upsubject'}
						     : $text{'mail_usubject'}),
			    $cc, $bcc, $d);
}

# make_user_substitutions(&user, [&domain])
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

# Check SSH and FTP shells
local ($shell) = grep { $_->{'shell'} eq $user->{'shell'} }
		      &list_available_shells();
if ($shell) {
	$hash{'ftp'} = $shell->{'id'} eq 'nologin' ? 0 : 1;
	$hash{'ssh'} = $shell->{'id'} eq 'ssh' ? 1 : 0;
	}
else {
	# Assume FTP but no SSH if unknown shell
	$hash{'ftp'} = 1;
	$hash{'ssh'} = 0;
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
return %hash;
}

# ensure_template(file)
sub ensure_template
{
local ($file) = @_;
local $mpath = "$module_root_directory/$file";
local $cpath = "$module_config_directory/$file";
if (!-s $cpath) {
	&copy_source_dest($mpath, $cpath);
	}
}

# get_miniserv_port_proto()
# Returns the port number, protocol (http or https) and hostname for Webmin
sub get_miniserv_port_proto
{
if ($ENV{'SERVER_PORT'}) {
	# Running under miniserv
	return ( $ENV{'SERVER_PORT'},
		 $ENV{'HTTPS'} eq 'ON' ? 'https' : 'http',
	         $ENV{'SERVER_NAME'} );
	}
else {
	# Get from miniserv config
	local %miniserv;
	&get_miniserv_config(\%miniserv);
	return ( $miniserv{'port'},
		 $miniserv{'ssl'} ? 'https' : 'http',
		 &get_system_hostname() );
	}
}

# get_usermin_miniserv_port_proto()
# Returns the port number, protocol (http or https) and hostname for Usermin
sub get_usermin_miniserv_port_proto
{
my ($port, $proto, $host);
if (&foreign_installed("usermin")) {
	&foreign_require("usermin");
	my %miniserv;
	&usermin::get_usermin_miniserv_config(
		\%miniserv);
	$proto = $miniserv{'ssl'} ? 'https' : 'http';
	$port = $miniserv{'port'};
	}
# Fall back to standard defaults
$proto ||= "https";
$port ||= 20000;
$host ||= &get_system_hostname();
return ($port, $proto, $host);
}

# get_miniserv_base_url()
# Returns the base URL for this Virtualmin install, without the trailing /
sub get_miniserv_base_url
{
my ($port, $proto, $host) = &get_miniserv_port_proto();
my $portstr = $proto eq "http" && $port == 80 ? "" :
	      $proto eq "https" && $port == 443 ? "" : ":".$port;
return $proto."://".$host.$portstr;
}

# send_template_email(data, address, &substitions, subject, cc, bcc,
#		      [&domain], [from])
# Sends the given file to the specified address, with the substitions from
# a hash reference. The actual subs in the file must be like $XXX for entries
# in the hash like xxx - ie. $DOM is replaced by the domain name, and $HOME
# by the home directory
sub send_template_email
{
local ($template, $to, $subs, $subject, $cc, $bcc, $d, $from) = @_;
local %hash = %$subs;

# Add in Webmin info to the hash
($hash{'webmin_port'}, $hash{'webmin_proto'}) = &get_miniserv_port_proto();
$template = &substitute_virtualmin_template($template, \%hash);

# Work out the From: address - if a domain is given, use it's email address
# as long as that address is in a local domain with mail
if (!$from && $remote_user && !&master_admin() && $d) {
	local $localdom = 0;
	local ($emailtouser, $emailtodom) = split(/\@/, $d->{'emailto_addr'});
	foreach my $ld (grep { $_->{'mail'} } &list_domains()) {
		if (lc($ld->{'dom'}) eq lc($emailtodom)) {
			$localdom = 1;
			}
		}
	if ($emailtodom eq &get_system_hostname()) {
		$localdom = 1;
		}
	if ($localdom) {
		$from = $d->{'emailto'};
		}
	}

# Actually send using the mailboxes module
local $subject = &substitute_virtualmin_template($subject, \%hash);
local $cc = &substitute_virtualmin_template($cc, \%hash);
if (!$to) {
	# This can happen when a mailbox is not notified about its
	# own update or creation
	$to = $cc;
	$cc = undef;
	}
&foreign_require("mailboxes");

# Set content type and encoding based on whether the email contains HTML
# and/or non-ascii characters
local $ctype = $template =~ /<html[^>]*>|<body[^>]*>/i ? "text/html"
						       : "text/plain";
local $cs = &get_charset();
local $attach =
    { 'headers' => [ [ 'Content-Type', $ctype.'; charset='.$cs ],
                     [ 'Content-Transfer-Encoding', 'quoted-printable' ] ],
      'data' => &mailboxes::quoted_encode($template) };

# Construct and send the email object
local $mail = { 'headers' => [ [ 'From', $from ||
					 $config{'from_addr'} ||
					 &mailboxes::get_from_address() ],
			       [ 'To', $to ],
			       $cc ? ( [ 'Cc', $cc ] ) : ( ),
			       $bcc ? ( [ 'Bcc', $bcc ] ) : ( ),
			       [ 'Subject', &entities_to_ascii($subject) ],
			     ],
		'attach' => [ $attach ] };
eval {
	local $main::error_must_die = 1;
	&mailboxes::send_mail($mail);
	};
if ($@) {
	return (0, $@);
	}
else {
	return (1, &text('mail_ok', $to));
	}
}

# send_notify_email(from, &doms|&users, [&dom], subject, body,
#		    [attach, attach-filename, attach-type], [extra-admins],
#		    [send-many], [charset])
# Sends a single email to multiple recipients. These can be Virtualmin domains
# or users.
sub send_notify_email
{
local ($from, $recips, $d, $subject, $body, $attach, $attachfile, $attachtype,
       $admins, $many, $charset) = @_;
&foreign_require("mailboxes");
local %done;
foreach my $r (@$recips) {
	# Work out recipient type and addresses
	local (@emails, %hash);
	if ($r->{'id'}) {
		# A domain
		push(@emails, $r->{'emailto'});
		%hash = &make_domain_substitions($r, 1);
		if ($admins) {
			# And extra admins
			push(@emails, map { $_->{'email'} }
					grep { $_->{'email'} }
					   &list_extra_admins($r));
			}
		}
	else {
		# A mailbox user
		push(@emails, $r->{'email'} || $r->{'user'});
		%hash = &make_user_substitutions($r, $d);
		}

	# Send to them
	foreach my $email (@emails) {
		next if (!$many && $done{$email}++);
		local $ct = 'text/plain';
		if ($charset) {
			$ct .= "; charset=".$charset;
			}
		local $mail = { 'headers' =>
		    [ [ 'From' => $from ],
		      [ 'To' => $email ],
		      [ 'Subject' => &entities_to_ascii(
		         &substitute_virtualmin_template($subject, \%hash)) ] ],
		      'attach' =>
		    [ { 'headers' => [ [ 'Content-type', $ct ] ],
		        'data' => &entities_to_ascii(
		          &substitute_virtualmin_template($body, \%hash)) } ] };
		if ($attach) {
			local $filename = $attachfile;
			$filename =~ s/^.*(\\|\/)//;
			local $type = $attachtype." name=\"$filename\"";
			local $disp = "inline; filename=\"$filename\"";
			push(@{$mail->{'attach'}},
			     { 'data' => $in{'attach'},
			       'headers' => [
				 [ 'Content-type', $type ],
				 [ 'Content-Disposition', $disp ],
				 [ 'Content-Transfer-Encoding', 'base64' ] ] });
			}
		&mailboxes::send_mail($mail);
		}
	}
}

# get_global_from_address([&domain])
# Returns the from address to use when sending email to some domain. This may
# be the reseller's email (if set), or the system-wide default
sub get_global_from_address
{
local ($d) = @_;
&foreign_require("mailboxes");
local $rv = $config{'from_addr'} || &mailboxes::get_from_address();
if ($d && $d->{'reseller'} && defined(&get_reseller) && $config{'from_reseller'}) {
	# From first reseller
	my @r = split(/\s+/, $d->{'reseller'});
	local $resel = &get_reseller($r[0]);
	if ($resel && $resel->{'acl'}->{'email'}) {
		# Reseller has an email .... but is it valid for this system?
		if ($resel->{'acl'}->{'from'}) {
			# Custom from address set
			$rv = $resel->{'acl'}->{'from'};
			}
		else {
			my ($rs) = &extract_address_parts($resel->{'acl'}->{'email'});
			my ($rsmbox, $rsdom) = split(/\@/, $rs);
			my $rsd = &get_domain_by("dom", $rsdom);
			if ($rsd || $rsdom eq &get_system_hostname() ||
			    $config{'from_reseller'} == 2) {
				# Yes - safe to use
				$rv = $rs;
				}
			}
		}
	}
return $rv;
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
# Return the type and destination of some alias string. Type codes are:
# 1 - Email address
# 2 - Include file of addresses
# 3 - Write to file
# 4 - Pipe to program
# 5 - Virtualmin autoreply
# 6 - Webmin filter
# 7 - Mailbox of user
# 8 - Same address at other domain
# 9 - Bounce, possibly with message
# 10- Current user's mailbox
# 11- Throw away
# 13- Everyone in some domain
sub alias_type
{
local @rv;
if ($_[0] =~ /^\|\s*$module_config_directory\/autoreply.pl\s+(\S+)/) {
        @rv = (5, $1);
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
elsif ($_[0] =~ /^:include:\Q$everyone_alias_dir\E\/(\S+)$/) {
	return (13, $1);
	}
elsif ($_[0] =~ /^:include:(.*)$/) {
        @rv = (2, $1);
        }
elsif ($_[0] =~ /^\\(\S+)$/) {
	if ($1 eq $_[1] || $1 eq "NEWUSER" || $1 eq &replace_atsign($_[1]) ||
	    $1 eq &escape_user($_[1])) {
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
		 $mail_system == 1 ? "sendmail" :
		 $mail_system == 0 ? "postfix" :
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

# set_domain_envs(&domain, action, [&new-domain], [&old-domain], [&other-envs])
# Sets up VIRTUALSERVER_ environment variables for a domain update or some kind,
# prior to calling making_changes or made_changes. action must be one of
# CREATE_DOMAIN, MODIFY_DOMAIN or DELETE_DOMAIN
sub set_domain_envs
{
local ($d, $action, $newd, $oldd, $others) = @_;
&reset_domain_envs();
$ENV{'VIRTUALSERVER_ACTION'} = $action;
foreach my $e (keys %$d) {
	local $env = uc($e);
	$env =~ s/\-/_/g;
	$ENV{'VIRTUALSERVER_'.$env} = $d->{$e};
	}
$ENV{'VIRTUALSERVER_IDNDOM'} = &show_domain_name($d->{'dom'});
if ($newd) {
	# Set details of virtual server being changed to. This is only
	# done in the pre-modify call
	foreach my $e (keys %$newd) {
		local $env = uc($e);
		$env =~ s/\-/_/g;
		$ENV{'VIRTUALSERVER_NEWSERVER_'.$env} = $newd->{$e};
		}
	$ENV{'VIRTUALSERVER_NEWSERVER_IDNDOM'} =
		&show_domain_name($newd->{'dom'});
	}
if ($oldd) {
	# Set details of virtual server being changed from, in post-modify
	foreach my $e (keys %$oldd) {
		local $env = uc($e);
		$env =~ s/\-/_/g;
		$ENV{'VIRTUALSERVER_OLDSERVER_'.$env} = $oldd->{$e};
		}
	$ENV{'VIRTUALSERVER_OLDSERVER_IDNDOM'} =
		&show_domain_name($oldd->{'dom'});
	}
local $parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
local $alias = $d->{'alias'} ? &get_domain($d->{'alias'}) : undef;
if (defined(&get_reseller)) {
	# Set (first) reseller details, if we have one
	local $rd = $d->{'reseller'} ? $d :
		    $parent && $parent->{'reseller'} ? $parent : undef;
	local ($r) = $rd ? split(/\s+/, $rd->{'reseller'}) : undef;
	local $resel = $r ? &get_reseller($r) : undef;
	if ($resel) {
		local $acl = $resel->{'acl'};
		$ENV{'RESELLER_NAME'} = $resel->{'name'};
		$ENV{'RESELLER_THEME'} = $resel->{'theme'};
		$ENV{'RESELLER_MODULES'} = join(" ", @{$resel->{'modules'}});
		foreach my $a (keys %$acl) {
			local $env = uc($a);
			$env =~ s/\-/_/g;
			$ENV{'RESELLER_'.$env} = $acl->{$a};
			}
		}
	}
if ($parent) {
	# Set parent domain variables
	foreach my $e (keys %$parent) {
		local $env = uc($e);
		$env =~ s/\-/_/g;
		$ENV{'PARENT_VIRTUALSERVER_'.$env} = $parent->{$e};
		}
	$ENV{'PARENT_VIRTUALSERVER_IDNDOM'} =
		&show_domain_name($parent->{'dom'});
	}
if ($alias) {
	# Set alias domain variables
	foreach my $e (keys %$alias) {
		local $env = uc($e);
		$env =~ s/\-/_/g;
		$ENV{'ALIAS_VIRTUALSERVER_'.$env} = $alias->{$e};
		}
	$ENV{'ALIAS_VIRTUALSERVER_IDNDOM'} =
		&show_domain_name($alias->{'dom'});
	}
# Set global variables
foreach my $v (&get_global_template_variables()) {
	if ($v->{'enabled'}) {
		$ENV{'GLOBAL_'.uc($v->{'name'})} = $v->{'value'};
		}
	}
# Set other variables
if ($others) {
	foreach my $e (keys %$others) {
		$ENV{uc($e)} = $others->{$e};
		$ENV{"VIRTUALSERVER_".uc($e)} = $others->{$e};
		}
	}
}

# reset_domain_envs(&domain)
# Removes all environment variables set by set_domain_envs
sub reset_domain_envs
{
foreach my $e (keys %ENV) {
	delete($ENV{$e}) if ($e =~ /^(VIRTUALSERVER_|RESELLER_|PARENT_VIRTUALSERVER_|GLOBAL_)/);
	}
}

# making_changes()
# Called before a domain is created, modified or deleted to run the
# pre-change command
sub making_changes
{
my $cmd = $ENV{'VIRTUALMIN_PRE_COMMAND'} || $config{'pre_command'};
my $output = $ENV{'VIRTUALMIN_OUTPUT_COMMAND'} || $config{'output_command'};
if ($cmd =~ /\S/) {
	&clean_changes_environment();
	local $out = &backquote_logged(
		"($cmd) 2>&1 </dev/null");
	if ($output && !$? && $out =~ /\S/) {
		&$second_print($out);
		}
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
my $cmd = $ENV{'VIRTUALMIN_POST_COMMAND'} || $config{'post_command'};
my $output = $ENV{'VIRTUALMIN_OUTPUT_COMMAND'} || $config{'output_command'};
if ($cmd =~ /\S/) {
	&clean_changes_environment();
	local $out = &backquote_logged(
		"($cmd) 2>&1 </dev/null");
	if ($output && !$? && $out =~ /\S/) {
		&$second_print($out);
		}
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
local @typenames = map { $text{"alias_type$_"} } (0 .. 13);
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
		next if ($j == 13 && $_[3] eq "user");	# everyone is not valid
							# for users
		if ($j == 0 || $can_alias_types{$j} || $type == $j) {
			push(@opts, [ $j, $typenames[$j] ]);
			}
		}
	local $f = &ui_select("type_$i", $type, \@opts);
	if ($type == 7) {
		$val = &unescape_user($val);
		}
	elsif ($type == 13) {
		# Everyone in some domain
		local $d = &get_domain($val);
		if ($d) {
			$val = $d->{'dom'};
			}
		}
	$f .= &ui_textbox("val_$i", $val, 30)."\n";
	if (&can_edit_afiles()) {
		local $prog = $type == 2 ? "edit_afile.cgi" :
			      $type == 5 ? "edit_rfile.cgi" :
			      $type == 6 ? "edit_ffile.cgi" : undef;
		if ($prog && $_[2]) {
			local $di = $_[2] ? $_[2]->{'id'} : undef;
			$f .= "<a href='$prog?dom=$di&amp;file=$val&amp;$_[3]=$_[4]&amp;idx=$i'>$text{'alias_afile'}</a>\n";
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
	if ($t == 1 && $v !~ /^([^\|\:\"\' \t\/\\\%]\S*)$/) {
		&error(&text('alias_etype1', $v));
		}
	elsif ($t == 1 && !&can_forward_alias($v)) {
		&error(&text('alias_etype1f', $v));
		}
	elsif ($t == 3 && $v !~ /^\/(\S+)$/ && $v !~ /^\.\//) {
		&error(&text('alias_etype3', $v));
		}
	elsif ($t == 4) {
		$v =~ /^(\S+)/ || &error($text{'alias_etype4none'});
		my $prog = $1;
		(-x $prog) && &check_aliasfile($prog, 0) ||
		   $prog eq "if" || $prog eq "export" || &has_command($prog) ||
			&error(&text('alias_etype4', $prog));
		}
	elsif ($t == 8 && $v !~ /^[a-z0-9\.\-\_]+$/) {
		&error(&text('alias_etype8', $v));
		}
	elsif ($t == 8 && !$_[0]) {
		&error(&text('alias_ecatchall', $v));
		}
	elsif ($t == 13 && !&get_domain_by("dom", $v)) {
		&error(&text('alias_eeveryone', $v));
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
		if ($mail_system == 0 && $_[1] =~ /\@/) {
			push(@values, "\\".&escape_user(&replace_atsign_if_exists($_[1])));
			}
		else {
			push(@values, "\\".&escape_user($_[1]));
			}
		}
	elsif ($t == 11) {
		push(@values, "/dev/null");
		}
	elsif ($t == 13) {
		# Work out ID for everyone file
		local $d = &get_domain_by("dom", $v);
		&create_everyone_file($d);
		push(@values, ":include:$everyone_alias_dir/$d->{'id'}");
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
my ($uidmap, $usermap, $users) = @_;
&obtain_lock_unix();
&require_useradmin();

# Add Unix users
local @users = $users ? @$users : &list_all_users();
local $u;
foreach $u (@users) {
	$uidmap->{$u->{'uid'}} ||= 'user' if ($uidmap);
	$usermap->{$u->{'user'}} ||= 'user' if ($usermap);
	}

# Add system users
setpwent();
while(my @uinfo = getpwent()) {
	$uidmap->{$uinfo[2]} ||= 'user' if ($uidmap);
	$usermap->{$uinfo[0]} ||= 'user' if ($usermap);
	}
endpwent();

# Add domain users
local $d;
foreach $d (&list_domains()) {
	$uidmap->{$d->{'uid'}} ||= 'dom' if ($uidmap);
	$usermap->{$d->{'user'}} ||= 'dom' if ($usermap);
	}

# Add UIDs used in the past
my %uids;
&read_file_cached($old_uids_file, \%uids);
foreach my $uid (keys %uids) {
	$uidmap->{$uid} ||= 'old' if ($uidmap);
	}

&release_lock_unix();
}

# build_group_taken(&gid-taken, &groupname-taken, [&groups])
# Fills in the the given hashes with used group names and GIDs
sub build_group_taken
{
my ($gidmap, $groupmap, $groups) = @_;
&obtain_lock_unix();
&require_useradmin();

# Add Unix groups
local @groups = $groups ? @$groups : &list_all_groups();
local $g;
foreach $g (@groups) {
	$gidmap->{$g->{'gid'}} ||= 'group' if ($gidmap);
	$groupmap->{$g->{'group'}} ||= 'group' if ($groupmap);
	}

# Add system groups
setgrent();
while(my @ginfo = getgrent()) {
	$gidmap->{$ginfo[2]} ||= 'group' if ($gidmap);
	$groupmap->{$ginfo[0]} ||= 'group' if ($groupmap);
	}
endgrent();

# Add domains
local $d;
foreach $d (&list_domains()) {
	$gidmap->{$d->{'gid'}} ||= 'dom' if ($gidmap);
	$groupmap->{$d->{'group'}} ||= 'dom' if ($groupmap);
	}

# Add GIDs used in the past
my %gids;
&read_file_cached($old_gids_file, \%gids);
foreach my $gid (keys %gids) {
	$gidmap->{$gid} ||= 'old' if ($gidmap);
	}

&release_lock_unix();
}

# allocate_uid(&uid-taken)
# Given a hash of used UIDs, return one that is free
sub allocate_uid
{
local $uid;
if ($usermodule eq "ldap-useradmin") {
	$uid = $luconfig{'base_uid'};
	}
$uid ||= $uconfig{'base_uid'};
while($_[0]->{$uid}) {
	$uid++;
	}
return $uid;
}

# allocate_gid(&gid-taken)
# Given a hash of used GIDs, return one that is free
sub allocate_gid
{
local $gid;
if ($usermodule eq "ldap-useradmin") {
	$gid = $luconfig{'base_gid'};
	}
$gid ||= $uconfig{'base_gid'};
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
	local $dname = $_[0]->{'dom'};
	$dname =~ s/^xn(-+)//;
	return "$_[1]->{'home'}/domains/$dname";
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

# set_server_quotas(&domain, [user-quota, group-quota])
# Set the user and possibly group quotas for a domain
sub set_server_quotas
{
my ($d, $uquota, $quota) = @_;
$uquota = $d->{'uquota'} if (!defined($uquota));
$quota = $d->{'quota'} if (!defined($quota));
local $tmpl = &get_template($d->{'template'});
if (&has_quota_commands()) {
	# User and group quotas are set externally
	&run_quota_command("set_user", $d->{'user'},
		$tmpl->{'quotatype'} eq 'hard' ? ( int($uquota), int($uquota) )
					       : ( 0, int($uquota) ));
	if (&has_group_quotas() && $d->{'group'}) {
		&run_quota_command("set_group", $d->{'group'},
			$tmpl->{'quotatype'} eq 'hard' ?
				( int($quota), int($quota) ) : ( 0, $quota ));
		}
	}
else {
	if (&has_home_quotas()) {
		# Set Unix user quota for home
		&set_quota($d->{'user'}, $config{'home_quotas'},
			   $uquota, $tmpl->{'quotatype'} eq 'hard');
		}
	if (&has_mail_quotas()) {
		# Set Unix user quota for mail
		&set_quota($d->{'user'}, $config{'mail_quotas'},
			   $uquota, $tmpl->{'quotatype'} eq 'hard');
		}
	if (&has_group_quotas() && $d->{'group'}) {
		# Set group quotas for home and possibly mail
		&require_useradmin();
		local @qargs;
		if ($tmpl->{'quotatype'} eq 'hard') {
			@qargs = ( int($quota), int($quota), 0, 0 );
			}
		else {
			@qargs = ( int($quota), 0, 0, 0 );
			}
		&quota::edit_group_quota(
			$d->{'group'}, $config{'home_quotas'}, @qargs);
		if (&has_mail_quotas()) {
			&quota::edit_group_quota(
			    $d->{'group'}, $config{'mail_quotas'}, @qargs);
			}
		}
	}
}

# disable_quotas(&domain)
# Temporarily disable quotas for some virtual server, so that file or DB
# operations don't fail
sub disable_quotas
{
local ($d) = @_;
return if (!&has_home_quotas());
if ($d->{'parent'}) {
	local $pd = &get_domain($d->{'parent'});
	&disable_quotas($pd);
	}
elsif ($d->{'unix'} && $d->{'quota'}) {
	local $nqd = { %$d };
	$nqd->{'quota'} = 0;
	$nqd->{'uquota'} = 0;
	&set_server_quotas($nqd);
	if (!@disable_quotas_users) {
		@disable_quotas_users = &list_domain_users($d, 1, 1, 0, 1);
		foreach my $u (@disable_quotas_users) {
			next if ($u->{'noquota'});
			&set_user_quotas($u->{'user'}, 0, 0, $d);
			}
		}
	}
}

# enable_quotas(&domain)
# Must be called after disable_quotas to re-activate quotas for some domain
sub enable_quotas
{
local ($d) = @_;
return if (!&has_home_quotas());
if ($d->{'parent'}) {
        local $pd = &get_domain($d->{'parent'});
        &enable_quotas($pd);
        }
elsif ($d->{'unix'} && $d->{'quota'}) {
	&set_server_quotas($d);
	if (@disable_quotas_users) {
		foreach my $u (@disable_quotas_users) {
			next if ($u->{'noquota'});
			&set_user_quotas($u->{'user'}, $u->{'quota'},
					 $u->{'mquota'}, $d);
			}
		@disable_quotas_users = ( );
		}
	}
}

# users_table(&users, &dom, cgi, &buttons, &links, empty-msg)
# Output a table of mailbox users
sub users_table
{
local ($users, $d, $cgi, $buttons, $links, $empty) = @_;

local $can_quotas = &has_home_quotas() || &has_mail_quotas();
local @ashells = &list_available_shells($d);

# Given a list of services return
# user-friendly login access label
my $login_access_label = sub {
	my @s = @_;
	@s = map { $text{'users_login_access_'.$_} } @s;
	@s = grep { $_ } @s;
	my $n = scalar(@s);
	if ($n == 0) {
		return '';
		}
	elsif ($n == 1) {
		return "$s[0] $text{'users_login_access__only'}";
		}
	else {
		my $l = pop(@s);
		return join(', ', @s) . " $text{'users_login_access__and'} $l";
		}
	};

# Work out table header
local @headers;
push(@headers, "") if ($cgi);
push(@headers, $text{'users_name'},
	       $text{'user_user2'},
	       $text{'users_real'} );
if ($can_quotas) {
	push(@headers, $text{'users_quota'}, $text{'users_uquota'});
	}
if ($config{'show_mailsize'} && $d->{'mail'}) {
	push(@headers, $text{'users_size'});
	}
if ($config{'show_lastlogin'} && $d->{'mail'}) {
	push(@headers, $text{'users_ll'});
	}
push(@headers, $text{'users_ushell'});
# Database column
if (($d->{'mysql'} || $d->{'postgres'}) && $config{'show_dbs'}) {
	push(@headers, $text{'users_db'});
	}
# Other plugins columns
local ($f, %plugcol);
if ($config{'show_plugins'}) {
	foreach $f (&list_mail_plugins()) {
		local $col = &plugin_call($f, "mailbox_header", $d);
		if ($col) {
			$plugcol{$f} = $col;
			push(@headers, $col);
			}
		}
	}

# Build table contents
local $u;
local $did = $d ? $d->{'id'} : 0;
local @table;
local $userdesc;
my @domsdbs = &domain_databases($d);
foreach $u (sort { $b->{'domainowner'} <=> $a->{'domainowner'} ||
		   $a->{'user'} cmp $b->{'user'} } @$users) {
	local $pop3 = $d ? &remove_userdom($u->{'user'}, $d) : $u->{'user'};
	local $pop3_dis =
		&ui_text_color($pop3.&vui_inline_label('users_disabled_label', undef, 'disabled'), 'danger');
	$pop3 = &html_escape($pop3);
	local @cols;
	local $filetype = $u->{'extra'} ? "&type=".&urlize($u->{'type'}) : "";
	my $col_text =
	  ($u->{'domainowner'} ?
	   "<b>$pop3</b>".&vui_inline_label('users_owner_label') :
	    $u->{'webowner'} && $u->{'pass'} =~ /^(\!|\*)/ ? $pop3_dis :
	    $u->{'webowner'} ? $pop3 :
	    $u->{'pass'} =~ /^(\!|\*)/ ? $pop3_dis : $pop3);
	my $col_val = "<a href='edit_user.cgi?dom=$did$filetype&amp;".
		      "user=".&urlize($u->{'user'})."'>$col_text</a>";
	if (!$virtualmin_pro && $u->{'extra'}) {
		$col_val = $col_text;
		}
	push(@cols, "$col_val\n");
	push(@cols, &html_escape($u->{'user'}));
	push(@cols, &html_escape($u->{'real'}));
	$userdesc++ if ($u->{'real'});

	# Add columns for quotas
	local $quota;
	$quota += $u->{'quota'} if (&has_home_quotas());
	$quota += $u->{'mquota'} if (&has_mail_quotas());
	local $uquota;
	$uquota += $u->{'uquota'} if (&has_home_quotas());
	$uquota += $u->{'muquota'} if (&has_mail_quotas());
	if (($u->{'webowner'} || $u->{'extra'}) && defined($quota)) {
		# Website owners, virtual database and web users have no
		# real quota
		push(@cols, $u->{'type'} eq 'web' || $u->{'type'} eq 'db' ?
			$text{'users_na'} : $text{'users_same'}, "");
		}
	elsif (defined($quota)) {
		# Has Unix quotas
		push(@cols, $quota ? &quota_show($quota, "home")
				   : $text{'form_unlimit'});
		my $color = $u->{'over_quota'} ? "#ff0000" :
			    $u->{'warn_quota'} ? "#df7d0e" :
			    $u->{'spam_quota'} ? "#aaaaaa" : undef;
		if ($color) {
			push(@cols, "<font color=$color><i>".
				    &quota_show($uquota, "home")."</i></font>");
			}
		else {
			push(@cols, &quota_show($uquota, "home"));
			}
		}

	if ($config{'show_mailsize'} && $d->{'mail'}) {
		# Mailbox link, if this user has email enabled or is the owner
		local ($szmsg, $sz, $szb);
		if (!$u->{'nomailfile'} &&
		    ($u->{'email'} || @{$u->{'extraemail'}})) {
			($sz) = &mail_file_size($u);
			$szb = $sz;
			$sz = $sz ? &nice_size($sz) : $text{'users_empty'};
			local $lnk = &read_mail_link($u, $d);
			if ($lnk) {
				$szmsg = &ui_link($lnk, $sz);
				}
			else {
				$szmsg = $sz;
				}
			}
		else {
			$szmsg = $text{'users_noemail'};
			$sz = 0;
			$szb = 0;
			}
		push(@cols, { 'type' => 'string',
			      'td' => 'data-sort='.$szb,
			      'value' => $szmsg });
		}

	if ($config{'show_lastlogin'} && $d->{'mail'}) {
		# Last mail login
		my $ll = &get_last_login_time($u->{'user'});
		my $llbest;
		foreach $k (sort { $a cmp $b } keys %$ll) {
			$llbest = $ll->{$k} if ($ll->{$k} > $llbest);
			}
		push(@cols, $llbest ? &human_time_delta($llbest)
				    : $text{'users_ll_never'});
		}

	# Show shell access level
	if ($u->{'domainowner'}) {
		$u->{'shell'} = &get_domain_shell($d, $u);
		}
	local ($shell) = grep { $_->{'shell'} eq &get_user_shell($u) } @ashells;
	my $udbs = scalar(@{$u->{'dbs'}}) || $u->{'domainowner'};
	push(@cols, ($u->{'extra'} && $u->{'type'} eq 'db') ? &$login_access_label('db') :
		    ($u->{'extra'} && $u->{'type'} eq 'web') ? &$login_access_label('web') :
		    !$u->{'shell'} ? &$login_access_label($udbs ? 'db' : undef, 'mail') :
		    !$shell ? &text('users_shell', "<tt>$u->{'shell'}</tt>") :
	            $shell->{'id'} eq 'ftp' && !$u->{'email'} ?
			&$login_access_label($udbs ? 'db' : undef, 'ftp') :
		    	(&$login_access_label(
				($u->{'extra'} && $u->{'type'} eq 'web') ? 'web' :
				$udbs ? 'db' : undef,
				$shell->{'id'} eq 'nologin' ? ($u->{'email'} ? 'mail' : undef) :
				$shell->{'id'} eq 'ftp' ? ($u->{'email'} ? 'mail' : undef, 'ftp') :
				$shell->{'id'} eq 'scp' ? ($u->{'email'} ? 'mail' : undef, 'scp') :
				$shell->{'id'} eq 'ssh' ? ($u->{'email'} ? 'mail' : undef, 'ftp', 'ssh') : undef
			) || ($shell->{'id'} eq 'nologin' ?
				(!$u->{'email'} ? $text{'users_login_access_none'} :
					$shell->{'desc'}) : $shell->{'desc'})));

	# Show number of DBs
	if (($d->{'mysql'} || $d->{'postgres'}) && $config{'show_dbs'}) {
		my $userdbscnt = scalar(@{$u->{'dbs'}});
		push(@cols, $u->{'domainowner'} ? $text{'users_all'} :
			    $userdbscnt ? scalar(@domsdbs) == $userdbscnt
					? $text{'users_all'} : $userdbscnt
					: $text{'no'});
		}

	# Show columns from plugins
	if ($config{'show_plugins'}) {
		foreach $f (grep { $plugcol{$_} } &list_mail_plugins()) {
			push(@cols, &plugin_call($f, "mailbox_column", $u, $d));
			}
		}

	# Insert checkbox, if needed
	if ($cgi) {
		unshift(@cols, { 'type' => 'checkbox',
				 'name' => 'd',
				 'value' => $u->{'user'},
				 'disabled' => $u->{'domainowner'} });
		}
	push(@table, \@cols);
	}

# Drop "Real name" column if no column has any data
if (!$userdesc) {
	my $colnum = $cgi ? 3 : 2;
	map { splice(@$_, $colnum, 1) } @table;
	splice(@headers, $colnum, 1);
	}

# Generate the table, perhaps with a form
if ($cgi) {
	print &ui_form_columns_table($cgi, $buttons, 1, $links,
				     $d ? [ [ "dom", $d->{'id'} ] ] : undef,
				     \@headers,
				     100, \@table, undef, 0, undef, $empty);
	}
else {
	print &ui_columns_table(\@headers, 100, \@table, undef, 0, undef,
				$empty);
	}
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

# quota_show(number, filesystem|"home"|"mail", [zero-means-none])
# Returns text for the quota on some filesystem, in a human-readable format
sub quota_show
{
my ($n, $fs, $zeromode) = @_;
if (!$n) {
	return $zeromode == 1 ? $text{'resel_none'} :
	       $zeromode == 0 ? $text{'resel_unlimit'} : 0;
	}
else {
	local $bsize = &quota_bsize($fs);
	if ($bsize) {
		return &nice_size($n*$bsize);
		}
	return $n." ".$text{'form_b'};
	}
}

# quota_input(name, number, filesystem|"home"|"mail", [disabled])
# Returns HTML for an input for entering a quota, doing block->kb conversion
sub quota_input
{
my ($name, $value, $fs, $dis) = @_;
my $bsize = &quota_bsize($fs);
if ($bsize) {
	return &ui_bytesbox($name, $value*$bsize, 8, $dis, undef, 1024*1024);
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

# feature_check_chained_javascript(feature)
# Return inline JavaScript code to chain disable/enable dependent features
sub feature_check_chained_javascript
{
my ($f) = @_;
my $chained = {
	'mail'                 => ['spam', 'virus'],
	'web'                  => ['ssl', 'status', 'webalizer', 'virtualmin-awstats'],
	'virtualmin-nginx'     => ['virtualmin-nginx-ssl', 'status', 'webalizer', 'virtualmin-awstats'],
};
my $cfeature = $chained->{$f};
if ($cfeature) {
	my $deps = join(', ', map { "form['$_'] && (form['$_'].checked = false)" }
			@{$cfeature});
	return "oninput=\"if (form['$f'] && !form['$f'].checked) { $deps }\"";
	}
for my $c (keys %$chained) {
	next if (!$config{$c} && &indexof($c, @plugins) < 0);
	return "oninput=\"if (form['$f'] && form['$f'].checked) ".
			   "{ form['$c'] && (form['$c'].checked = true) }\""
		if (grep { $_ eq $f } @{$chained->{$c}});
	}
return undef;
}

# quota_javascript(name, value, filesystem|"bw"|"none", unlimited-possible)
# Returns Javascript to set some quota field using Javascript
sub quota_javascript
{
local ($name, $value, $fs, $unlimited) = @_;
local $bsize = $fs eq "none" ? 0 : $fs eq "bw" ? 1 : &quota_bsize($fs);
local $rv;
if ($bsize) {
	# Set value and units
	local $val = $value eq "" ? "" : $value*$bsize;
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
	$rv .= "    !!domain_form_target[0].${name} && (domain_form_target[0].${name}.value = \"$val\");\n";
	$rv .= "    !!domain_form_target[0].${name}_units && (domain_form_target[0].${name}_units.selectedIndex = $index);\n";
	}
else  {
	# Just set blocks value
	$rv .= "    !!domain_form_target[0].${name} && (domain_form_target[0].${name}.value = \"$value\");\n";
	}
if ($unlimited) {
	if ($value eq "") {
		$rv .= "    !!domain_form_target[0].${name}_def && (domain_form_target[0].${name}_def[0].checked = true);\n";
		$rv .= "    !!domain_form_target[0].${name} && (domain_form_target[0].${name}.disabled = true);\n";
		$rv .= "    if (domain_form_target[0].${name}_units) {\n";
		$rv .= "        domain_form_target[0].${name}_units.disabled = true;\n";
		$rv .= "    }\n";
		}
	else {
		$rv .= "    !!domain_form_target[0].${name}_def && (domain_form_target[0].${name}_def[1].checked = true);\n";
		$rv .= "    !!domain_form_target[0].${name} && (domain_form_target[0].${name}.disabled = false);\n";
		$rv .= "    if (domain_form_target[0].${name}_units) {\n";
		$rv .= "        domain_form_target[0].${name}_units.disabled = false;\n";
		$rv .= "    }\n";
		}
	}
return $rv;
}

# quota_field(name, value, used, files-used, filesystem, &user)
sub quota_field
{
my ($name, $value, $used, $fused, $fs, $u) = @_;
my $rv;
my $color = $u->{'over_quota'} ? "#ff0000" :
	    $u->{'warn_quota'} ? "#df7d0e" :
	    $u->{'spam_quota'} ? "#aaaaaa" : undef;
if (&can_mailbox_quota()) {
	# Show inputs for editing quotas
	local $quota = $_[1];
	$quota = undef if ($quota eq "none");
	$rv .= &opt_quota_input($_[0], $quota, $_[3]);
	$rv .= "\n";
	}
else {
	# Just show current settings, or default
	$rv .= ($defmquota[0] ? &quota_show($defmquota[0], $_[3]) : $text{'form_unlimit'})."\n";
	}
return $rv;
}

# backup_virtualmin(&domain, file)
# Adds a domain's configuration file to the backup
sub backup_virtualmin
{
my ($d, $file) = @_;
&$first_print($text{'backup_virtualmincp'});

# Record parent's domain name, which can be used when restoring
if ($d->{'parent'}) {
	local $parent = &get_domain($d->{'parent'});
	$d->{'backup_parent_dom'} = $parent->{'dom'};
	if ($d->{'alias'}) {
		local $alias = &get_domain($d->{'alias'});
		$d->{'backup_alias_dom'} = $alias->{'dom'};
		}
	if ($d->{'subdom'}) {
		local $subdom = &get_domain($d->{'subdom'});
		$d->{'backup_subdom_dom'} = $subdom->{'dom'};
		}
	}

# Record sub-directory for mail folders, used during mail restores
local %mconfig = &foreign_config("mailboxes");
if ($mconfig{'mail_usermin'}) {
	$d->{'backup_mail_folders'} = $mconfig{'mail_usermin'};
	}
else {
	delete($d->{'backup_mail_folders'});
	}

# Record encrypted Unix password
delete($d->{'backup_encpass'});
if ($d->{'unix'} && !$d->{'parent'} && !$d->{'disabled'}) {
	local @users = &list_all_users();
	local ($user) = grep { $_->{'user'} eq $d->{'user'} } @users;
	if ($user) {
		$d->{'backup_encpass'} = $user->{'pass'};
		}
	}

# Record if default for the IP
if (&domain_has_website($d)) {
	$d->{'backup_web_default'} = &is_default_website($d);
	}
else {
	delete($d->{'backup_web_default'});
	}

# Record webserver type
$d->{'backup_web_type'} = &domain_has_website($d);
$d->{'backup_ssl_type'} = &domain_has_ssl($d);
&lock_domain($d);
&save_domain($d);
&unlock_domain($d);

# Save the domain's data file
&copy_source_dest($d->{'file'}, $file);

if (-r "$initial_users_dir/$d->{'id'}") {
	# Initial user settings
	&copy_source_dest("$initial_users_dir/$d->{'id'}", $file."_initial");
	}
if (-d "$extra_admins_dir/$d->{'id'}") {
	# Extra admin details
	&execute_command(
	    "cd ".quotemeta("$extra_admins_dir/$d->{'id'}").
	    " && ".&make_tar_command("cf", $file."_admins", "."));
	}
if (-d "$extra_users_dir/$d->{'id'}") {
	# Extra users details
	&execute_command(
	    "cd ".quotemeta("$extra_users_dir/$d->{'id'}").
	    " && ".&make_tar_command("cf", $file."_users", "."));
	}
if ($config{'bw_active'}) {
	# Bandwidth logs
	if (-r "$bandwidth_dir/$d->{'id'}") {
		&copy_source_dest("$bandwidth_dir/$d->{'id'}", $file."_bw");
		}
	else {
		# Create an empty file to indicate that we have no data
		&open_tempfile(EMPTY, ">".$file."_bw");
		&close_tempfile(EMPTY);
		}
	}

# Script logs
if (-d "$script_log_directory/$d->{'id'}") {
	&execute_command(
	    "cd ".quotemeta("$script_log_directory/$d->{'id'}").
	    " && ".&make_tar_command("cf", $file."_scripts", "."));
	}
else {
	# Create an empty file to indicate that we have no scripts
	&open_tempfile(EMPTY, ">".$file."_scripts");
	&close_tempfile(EMPTY);
	}

# Include template, in case the restore target doesn't have it
local ($tmpl) = grep { $_->{'id'} == $d->{'template'} } &list_templates();
if (!$tmpl->{'standard'}) {
	&copy_source_dest($tmpl->{'file'}, $file."_template");
	}

# Include plan too
local $plan = &get_plan($d->{'plan'});
if ($plan) {
	&copy_source_dest($plan->{'file'}, $file."_plan");
	}

# Save deleted aliases file
&copy_source_dest("$saved_aliases_dir/$d->{'id'}",
		  $file."_saved_aliases");

# Save SSL cert and key, in case Apache isn't enabled
foreach my $ssltype ('cert', 'key', 'ca') {
	my $sslfile = &get_website_ssl_file($d, $ssltype);
	if ($sslfile && -r $sslfile) {
		&copy_write_as_domain_user($d, $sslfile,
					   $file."_ssl_".$ssltype);
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
&$first_print($text{'backup_vconfig_doing'});
&copy_source_dest($module_config_file, $file);
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_config(file, &vbs)
# Replace the current config with the given file, *except* for the default
# template settings
sub virtualmin_restore_config
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vconfig_doing'});
local %oldconfig = %config;
local @tmpls = &list_templates();
&copy_source_dest($file, $module_config_file);
&read_file($module_config_file, \%config);
foreach my $t (@tmpls) {
	if ($t->{'standard'}) {
		&save_template($t);
		}
	}

# Put back site-specific settings, as those in the backup are unlikely to
# be correct.
$config{'iface'} = $oldconfig{'iface'};
$config{'defip'} = $oldconfig{'defip'};
$config{'sharedips'} = $oldconfig{'sharedips'};
$config{'sharedip6s'} = $oldconfig{'sharedip6s'};
$config{'home_quotas'} = $oldconfig{'home_quotas'};
$config{'mail_quotas'} = $oldconfig{'mail_quotas'};
$config{'group_quotas'} = $oldconfig{'group_quotas'};
$config{'old_defip'} = $oldconfig{'old_defip'};
$config{'old_defip6'} = $oldconfig{'old_defip6'};
$config{'last_check'} = $oldconfig{'last_check'};

# Remove plugins that aren't on the new system
&generate_plugins_list($config{'plugins'});
$config{'plugins'} = join(' ', @plugins);
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&$second_print($text{'setup_done'});

# Apply any new config settings
&run_post_config_actions(\%oldconfig);

return 1;
}

# virtualmin_backup_templates(file, &vbs)
# Write a tar file of all templates (including scripts) to the given file
sub virtualmin_backup_templates
{
local ($file, $vbs) = @_;
&$first_print($text{'backup_vtemplates_doing'});
local $temp = &transname();
mkdir($temp, 0700);
foreach my $tmpl (&list_templates()) {
	my %tmplquoted = %$tmpl;
	foreach my $k (keys %tmplquoted) {
		$tmplquoted{$k} =~ s/\n/\\n/g;
		}
	&write_file("$temp/$tmpl->{'id'}", \%tmplquoted);
	}

# Save template scripts
&execute_command("cp $template_scripts_dir/* $temp");
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("cf", $file, "."));
&unlink_file($temp);

# Save global variables file
if (-r $global_template_variables_file) {
	&copy_source_dest($global_template_variables_file, $file."_global");
	}
else {
	# Create empty, as an indicator that it exists
	&open_tempfile(GLOBAL, ">".$file."_global", 0, 1);
	&close_tempfile(GLOBAL);
	}

# Save skeleton directories for all templates
local %done;
foreach my $tmpl (&list_templates()) {
	if ($tmpl->{'skel'} && $tmpl->{'skel'} ne 'none' &&
	    !$done{$tmpl->{'skel'}}++ &&
	    -d $tmpl->{'skel'}) {
		local $skelfile = $file.'_skel_'.$tmpl->{'id'};
		&execute_command(
		    "cd ".quotemeta($tmpl->{'skel'}).
		    " && ".&make_tar_command("cf", $skelfile, "."));
		}
	}

# Save plans
&make_dir($plans_dir, 0700);
&execute_command(
    "cd ".quotemeta($plans_dir).
    " && ".&make_tar_command("cf", $file."_plans", "."));

# Save ACME providers
if (defined(&list_acme_providers)) {
	&make_dir($acme_providers_dir, 0700);
	&execute_command(
	    "cd ".quotemeta($acme_providers_dir).
	    " && ".&make_tar_command("cf", $file."_acmes", "."));
	}

&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_templates(file, &vbs)
# Extract all templates from a backup. Those that already exist are not deleted.
sub virtualmin_restore_templates
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vtemplates_doing'});

# Extract backup file
local $temp = &transname();
mkdir($temp, 0700);
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("xf", $file));

# Copy templates from backup across
opendir(DIR, $temp);
foreach my $t (readdir(DIR)) {
	next if ($t eq "." || $t eq "..");
	if ($t =~ /^(\d+)_(\d+)$/) {
		# A script file
		if (!-d $template_scripts_dir) {
			&make_dir($template_scripts_dir, 0755);
			}
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

# Fix up bad Apache directives in templates
foreach my $tmpl (&list_templates()) {
	&fix_options_template($tmpl);
	}

# Restore global variables
if (-r $file."_global") {
	&copy_source_dest($file."_global", $global_template_variables_file);
	}

# Restore skeleton directories
local %done;
foreach my $tmpl (&list_templates()) {
	if ($tmpl->{'skel'} && $tmpl->{'skel'} ne 'none' &&
	    !$done{$tmpl->{'skel'}}++) {
		local $skelfile = $file.'_skel_'.$tmpl->{'id'};
		if (-r $skelfile) {
			# Delete and re-create skel directory
			&unlink_file($tmpl->{'skel'});
			&make_dir($tmpl->{'skel'}, 0755);
			&execute_command(
			    "cd ".quotemeta($tmpl->{'skel'}).
			    " && ".&make_tar_command("xf",
					quotemeta($skelfile)));
			}
		}
	}

# Restore plans, if included
if (-r $file."_plans") {
	&make_dir($plans_dir, 0700);
	&execute_command(
	    "cd ".quotemeta($plans_dir)." && ".
	    &make_tar_command("xf", $file."_plans"));
	}

# Restore ACME providers if included
if (-r $file."_acmes" && defined(&list_acme_providers)) {
	&make_dir($acme_providers_dir, 0700);
	&execute_command(
	    "cd ".quotemeta($acme_providers_dir)." && ".
	    &make_tar_command("xf", $file."_acmes"));
	}

&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_scheds(file, &vbs)
# Create a tar file of all scheduled backups and keys
sub virtualmin_backup_scheds
{
local ($file, $vbs) = @_;
local $dokeys = defined(&list_backup_keys) && scalar(&list_backup_keys());
&$first_print($dokeys ? $text{'backup_vscheds_doing2'}
		      : $text{'backup_vscheds_doing'});

# Tar up scheduled backups dir
local $temp = &transname();
mkdir($temp, 0700);
foreach my $sched (&list_scheduled_backups()) {
	&write_file("$temp/$sched->{'id'}", $sched);
	}
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("cf", $file, "."));
&unlink_file($temp);

# Also tar up keys dir
if ($dokeys) {
	&execute_command("cd ".quotemeta($backup_keys_dir)." && ".
			 &make_tar_command("cf", $file."_keys", "."));
	}

# Also tar up S3 accounts dir
if (-d $s3_accounts_dir) {
	&execute_command("cd ".quotemeta($s3_accounts_dir)." && ".
			 &make_tar_command("cf", $file."_s3accounts", "."));
	}

&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_scheds(file, vbs)
# Re-create all scheduled backups
sub virtualmin_restore_scheds
{
local ($file, $vbs) = @_;
local $dokeys = -r $file."_keys" && defined(&list_backup_keys);
&$first_print($dokeys ? $text{'restore_vscheds_doing'}
		      : $text{'restore_vscheds_doing2'});

# Extract backup file
local $temp = &transname();
mkdir($temp, 0700);
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("xf", $file));

# Delete all current non-default schedules
foreach my $sched (&list_scheduled_backups()) {
	if ($sched->{'id'} != 1) {
		&delete_scheduled_backup($sched);
		}
	}

# Re-create the restored ones
opendir(BACKUPDIR, $temp);
foreach my $t (readdir(BACKUPDIR)) {
        next if ($t eq "." || $t eq "..");
	local %sched;
	&read_file("$temp/$t", \%sched);
	delete($sched{'file'});
	&save_scheduled_backup(\%sched);
	}
closedir(BACKUPDIR);

# Extract dir of backup keys, then re-save each to re-import to root
if ($dokeys) {
	local %oldkeys = map { $_->{'id'}, 1 } &list_backup_keys();
	&make_dir($backup_keys_dir, 0700) if (!-d $backup_keys_dir);
	&execute_command("cd ".quotemeta($backup_keys_dir)." && ".
			 &make_tar_command("xf", $file."_keys"));
	foreach my $key (&list_backup_keys()) {
		if (!$oldkey{$key->{'id'}}) {
			eval {
				$main::error_must_die = 1;
				&save_backup_key($key, 1);
				};
			}
		}
	}

# Extract dir of S3 accounts
if (-r $file."_s3accounts") {
	&unlink_file($s3_accounts_dir);
	&make_dir($s3_accounts_dir, 0700);
	&execute_command("cd ".quotemeta($s3_accounts_dir)." && ".
                         &make_tar_command("xf", $file."_s3accounts"));
	}

&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_resellers(file, &vbs)
# Create a tar file of reseller details. For each we need to store the Webmin
# user information, plus all ACL files
sub virtualmin_backup_resellers
{
local ($file, $vbs) = @_;
return 0 if (!defined(&list_resellers));
&$first_print($text{'backup_vresellers_doing'});
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
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("cf", $file, "."));
&execute_command("rm -rf ".quotemeta($temp));
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_resellers(file, &vbs)
# Delete all resellers and re-create them from the backup
sub virtualmin_restore_resellers
{
local ($file, $vbs) = @_;
return undef if (!defined(&list_resellers));
&$first_print($text{'restore_vresellers_doing'});
local $temp = &transname();
mkdir($temp, 0700);
&require_acl();
&execute_command("cd ".quotemeta($temp)." && ".
		 &make_tar_command("xf", $file));
foreach my $resel (&list_resellers()) {
	&acl::delete_user($resel->{'name'});
	&delete_reseller_unix_user($resel);
	}
local %miniserv;
&get_miniserv_config(\%miniserv);
if (&check_pid_file($miniserv{'pidfile'})) {
	&reload_miniserv();
	}
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
&unlink_file($temp);
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_email(file, &vbs)
# Creates a tar file of all email templates
sub virtualmin_backup_email
{
local ($file, $vbs) = @_;
&$first_print($text{'backup_vemail_doing'});
&execute_command(
	"cd $module_config_directory && ".
	&make_tar_command("cf", $file, @all_template_files));
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_email(file, &vbs)
# Extract a tar file of all email templates
sub virtualmin_restore_email
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vemail_doing'});
&execute_command("cd $module_config_directory && ".
		 &make_tar_command("xf", $file));
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_custom(file, &vbs)
# Copies the custom fields, links and shells files
sub virtualmin_backup_custom
{
local ($file, $vbs) = @_;
&$first_print($text{'backup_vcustom_doing'});
foreach my $fm ([ $custom_fields_file, $file ],
		[ $custom_links_file, $file."_links" ],
		[ $custom_link_categories_file, $file."_linkcats" ],
		[ $custom_shells_file, $file."_shells" ]) {
	if (-r $fm->[0]) {
		&copy_source_dest($fm->[0], $fm->[1]);
		}
	else {
		&create_empty_file($fm->[1]);
		}
	}
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_custom(file, &vbs)
# Restores the custom fields, links and shells files
sub virtualmin_restore_custom
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vcustom_doing'});
foreach my $fm ([ $custom_fields_file, $file ],
		[ $custom_links_file, $file."_links" ],
		[ $custom_link_categories_file, $file."_linkcats" ]) {
	if (-r $fm->[1]) {
		&copy_source_dest($fm->[1], $fm->[0]);
		}
	}
if (-s $file."_shells") {
	# A non-empty shells file means that the original system defined some
	# custom shells.
	&copy_source_dest($file."_shells", $custom_shells_file);
	}
elsif (-r $file."_shells") {
	# An empty shells file means that the original system was using the
	# default shells, so so should we
	&unlink_file($custom_shells_file);
	}
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_scripts(file, &vbs)
# Create a tar file of the scripts directory, and of the unavailable scripts
sub virtualmin_backup_scripts
{
local ($file, $vbs) = @_;
&$first_print($text{'backup_vscripts_doing'});
&make_dir("$module_config_directory/scripts", 0755);
&execute_command("cd $module_config_directory/scripts && ".
		 &make_tar_command("cf", $file, "."));
&copy_source_dest($scripts_unavail_file, $file."_unavail");
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_scripts(file, &vbs)
# Extract a tar file of all third-party scripts
sub virtualmin_restore_scripts
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vscripts_doing'});
&make_dir("$module_config_directory/scripts", 0755);
&execute_command("cd $module_config_directory/scripts && ".
		 &make_tar_command("xf", $file));
if (-r $file."_unavail") {
	&copy_source_dest($file."_unavail", $scripts_unavail_file);
	}
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_chroot(file, &vbs)
# Create a file of FTP directory restrictions
sub virtualmin_backup_chroot
{
local ($file, $vbs) = @_;
&$first_print($text{'backup_vchroot_doing'});
local @chroots = &list_ftp_chroots();
&open_tempfile(CHROOT, ">$file");
foreach my $c (@chroots) {
	&print_tempfile(CHROOT,
		join(" ", map { $_."=".&urlize($c->{$_}) }
			      grep { $_ ne 'dr' } keys %$c),"\n");
	}
&close_tempfile(CHROOT);
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_restore_chroot(file, &vbs)
# Restore all chroot'd directories from a backup file
sub virtualmin_restore_chroot
{
local ($file, $vbs) = @_;
&$first_print($text{'restore_vchroot_doing'});
&obtain_lock_ftp();
local @chroots;
open(CHROOT, "<".$file);
while(<CHROOT>) {
	s/\r|\n//g;
	local %c = map { my ($n, $v) = split(/=/, $_, 2);
			 ($n, &un_urlize($v)) }
		       split(/\s+/, $_);
	push(@chroots, \%c);
	}
close(CHROOT);
&save_ftp_chroots(\@chroots);
&release_lock_ftp();
&$second_print($text{'setup_done'});
return 1;
}

# virtualmin_backup_mailserver(file, &vbs)
# Save DKIM and Postgrey settings to a file
sub virtualmin_backup_mailserver
{
local ($file, $vbs) = @_;
&require_mail();

# Save DKIM settings
&$first_print($text{'backup_vmailserver_dkim'});
local %dkim;
if (!&check_dkim()) {
	# DKIM can be used .. check if enabled
	$dkim{'support'} = 1;
	local $conf = &get_dkim_config();
	$dkim{'enabled'} = $conf->{'enabled'};
	$dkim{'selector'} = $conf->{'selector'};
	$dkim{'extra'} = join(" ", @{$conf->{'extra'}});
	$dkim{'keyfile'} = $conf->{'keyfile'};
	$dkim{'sign'} = $conf->{'sign'};
	$dkim{'verify'} = $conf->{'verify'};
	if ($conf->{'keyfile'} && -r $conf->{'keyfile'}) {
		&copy_source_dest($conf->{'keyfile'}, $file."_dkimkey");
		}
	&$second_print($text{'setup_done'});
	}
else {
	$dkim{'support'} = 0;
	&$second_print($text{'backup_vmailserver_none'});
	}
&write_file($file."_dkim", \%dkim);

# Save Postgrey settings
&$first_print($text{'backup_vmailserver_postgrey'});
local %grey;
if (!&check_postgrey()) {
	# Postgrey can be used .. check if enabled, and with what opts
	$grey{'support'} = 1;
	$grey{'enabled'} = &is_postgrey_enabled();
	local $cfile = &get_postgrey_data_file("clients");
	if ($cfile) {
		&copy_source_dest($cfile, $file."_greyclients");
		}
	local $rfile = &get_postgrey_data_file("recipients");
	if ($rfile) {
		&copy_source_dest($rfile, $file."_greyrecipients");
		}
	&$second_print($text{'setup_done'});
	}
else {
	$grey{'support'} = 0;
	&$second_print($text{'backup_vmailserver_none'});
	}
&write_file($file."_grey", \%grey);

# Save rate limiting settings
&$first_print($text{'backup_vmailserver_ratelimit'});
local %ratelimit;
if (!&check_ratelimit()) {
	# Rate limiting can be used .. check if enabled, and save config
	$ratelimit{'support'} = 1;
	$ratelimit{'enabled'} = &is_ratelimit_enabled();
	&copy_source_dest(&get_ratelimit_config_file(),
			  $file."_ratelimitconfig");
	&$second_print($text{'setup_done'});
	}
else {
	$ratelimit{'support'} = 0;
	&$second_print($text{'backup_vmailserver_none'});
	}
&write_file($file."_ratelimit", \%ratelimit);

# Save mail server type
&$first_print($text{'backup_vmailserver_doing'});
&open_tempfile(MS, ">$file", 0, 1);
&print_tempfile(MS, $mail_system,"\n");
&close_tempfile(MS);

# Save general mail server settings
if ($mail_system == 0) {
	# Save main.cf and master.cf
	&copy_source_dest($postfix::config{'postfix_config_file'},
			  $file."_maincf");
	&copy_source_dest($postfix::config{'postfix_master'},
			  $file."_mastercf");
	foreach my $o ("smtpd_tls_cert_file", "smtpd_tls_key_file",
		       "smtpd_tls_CAfile") {
		my $v = &postfix::get_current_value($o);
		if ($v) {
			&copy_source_dest($v, $file."_".$o);
			}
		}
	&$second_print($text{'setup_done'});
	}
elsif ($mail_system == 1) {
	# Save sendmail.cf and sendmail.mc
	&copy_source_dest($sendmail::config{'sendmail_cf'},
			  $file."_sendmailcf");
	&copy_source_dest($sendmail::config{'sendmail_mc'},
			  $file."_sendmailmc");
	&$second_print($text{'setup_done'});
	}
elsif ($mail_system == 2) {
	# Save Qmail dir
	&execute_command("cd $qmailadmin::config{'qmail_dir'} && ".
			 &make_tar_command("cf", $file, "."));
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'backup_vmailserver_supp'});
	}
return 1;
}

# virtualmin_restore_mailserver(file, &vbs)
# Apply DKIM and Postgrey settings from the backup
sub virtualmin_restore_mailserver
{
local ($file, $vbs) = @_;
&require_mail();

# Restore DKIM config
&$first_print($text{'restore_vmailserver_dkim'});
&obtain_lock_mail();
if (!&check_dkim()) {
	# DKIM supported .. see what state was in the backup
	local %dkim;
	&read_file($file."_dkim", \%dkim);
	if (!$dkim{'support'}) {
		&$second_print($text{'restore_vmailserver_none'});
		}
	else {
		local $conf = &get_dkim_config();
		if ($dkim{'enabled'}) {
			# Setup on this system, same as source
			&$indent_print();
			$conf->{'enabled'} = $dkim{'enabled'};
			$conf->{'selector'} = $dkim{'selector'};
			$conf->{'extra'} = [ split(/\s+/, $dkim{'extra'}) ];
			$conf->{'sign'} = $dkim{'sign'};
			$conf->{'verify'} = $dkim{'verify'};
			local $copiedkey = 0;
			if ($conf->{'keyfile'} && -r $file."_dkimkey") {
				# Can copy key now
				&copy_source_dest($file."_dkimkey",
						  $conf->{'keyfile'});
				$copiedkey = 1;
				}
			&enable_dkim($conf);
			$conf = &get_dkim_config();
			if ($conf->{'keyfile'} && -r $file."_dkimkey" &&
			    !$copiedkey) {
				# Copy key file and re-enable DKIM
				&copy_source_dest($file."_dkimkey",
						  $conf->{'keyfile'});
				&enable_dkim($conf);
				}
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		elsif ($conf->{'enabled'} && !$dkim{'enabled'}) {
			# Disable on this system
			&$indent_print();
			&disable_dkim($conf);
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		else {
			# Nothing to do
			&$second_print($text{'restore_vmailserver_already'});
			}
		}
	}
else {
	&$second_print($text{'backup_vmailserver_none'});
	}

# Restore Postgrey config
&$first_print($text{'restore_vmailserver_grey'});
local %grey;
&read_file($file."_grey", \%grey);
if (&check_postgrey() ne '' && &can_install_postgrey() && $grey{'enabled'}) {
	# Postgrey is not installed on this system yet, but it was enabled
	# on the old machine - try to install it now
	&install_postgrey_package();
	}
if (&check_postgrey() eq '') {
	if (!$grey{'support'}) {
		&$second_print($text{'restore_vmailserver_none'});
		}
	else {
		local $enabled = &is_postgrey_enabled();
		if ($grey{'enabled'}) {
			# Enable on this system, and copy client files
			&$indent_print();
			&enable_postgrey();
			local $cfile = &get_postgrey_data_file("clients");
			if ($cfile && -r $file."_greyclients") {
				&copy_source_dest($file."_greyclients",
						  $cfile);
				}
			local $rfile = &get_postgrey_data_file("recipients");
			if ($rfile && -r $file."_greyrecipients") {
				&copy_source_dest($file."_greyrecipients",
						  $rfile);
				}
			&apply_postgrey_data();
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		elsif ($enabled && !$grey{'enabled'}) {
			# Disable on this system
			&$indent_print();
			&disable_postgrey();
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		else {
			# Nothing to do
			&$second_print($text{'restore_vmailserver_already'});
			}
		}
	}
else {
	&$second_print($text{'backup_vmailserver_none'});
	}

# Restore rate limiting config
&$first_print($text{'restore_vmailserver_ratelimit'});
local %ratelimit;
&read_file($file."_ratelimit", \%ratelimit);
if (&check_ratelimit() ne '' && &can_install_ratelimit() &&
    $ratelimit{'enabled'}) {
	# Rate limiting is not installed on this system yet, but it was enabled
	# on the old machine - try to install it now
	&install_ratelimit_package();
	}
if (&check_ratelimit() eq '') {
	if (!$ratelimit{'support'}) {
		&$second_print($text{'restore_vmailserver_none'});
		}
	else {
		local $enabled = &is_ratelimit_enabled();
		# XXX put back socket
		if ($ratelimit{'enabled'}) {
			# Enable on this system, and copy config file
			&$indent_print();
			&enable_ratelimit();
			my $conf = &get_ratelimit_config();
			my ($oldsocket) = grep { $_->{'name'} eq 'socket' }
					       @$conf;
			&copy_source_dest($file."_ratelimitconfig",
					  &get_ratelimit_config_file());
			my $conf = &get_ratelimit_config();
			my ($socket) = grep { $_->{'name'} eq 'socket' }
					    @$conf;
			&save_ratelimit_directive($conf, $socket, $oldsocket);
			&$outdent_print();
                        &$second_print($text{'setup_done'});
			}
		elsif ($enabled && !$ratelimit{'enabled'}) {
			# Disable on this system
			&$indent_print();
			&disable_ratelimit();
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		else {
			# Nothing to do
			&$second_print($text{'restore_vmailserver_already'});
			}
		}
	}
else {
	&$second_print($text{'restore_vmailserver_missing'});
	}

&release_lock_mail();

# Get mail server type from the backup
local $bms = &read_file_contents($file);
$bms =~ s/\n//g;

# Restore mail server type, if matching. This is done last because DKIM or
# greylisting might be detected as disabled if done earlier.
&$first_print($text{'restore_vmailserver_doing'});
&obtain_lock_mail();
if ($bms eq $mail_system) {
	if ($mail_system == 0) {
		# Restore main.cf and master.cf
		&lock_file($postfix::config{'postfix_config_file'});
		&lock_file($postfix::config{'postfix_master'});
		&copy_source_dest($file."_maincf",
				  $postfix::config{'postfix_config_file'});
		&copy_source_dest($file."_mastercf",
				  $postfix::config{'postfix_master'});
		&unlock_file($postfix::config{'postfix_master'});
		&unlock_file($postfix::config{'postfix_config_file'});
		undef(@postfix::master_config_cache);
		foreach my $o ("smtpd_tls_cert_file", "smtpd_tls_key_file",
			       "smtpd_tls_CAfile") {
			my $v = &postfix::get_current_value($o);
			if ($v) {
				&copy_source_dest($file."_".$o, $v);
				}
			}
		&$second_print($text{'setup_done'});
		}
	elsif ($mail_system == 1) {
		# Restore sendmail.cf and .mc
		&lock_file($sendmail::config{'sendmail_cf'});
		&lock_file($sendmail::config{'sendmail_mc'});
		&copy_source_dest($file."_sendmailcf",
				  $sendmail::config{'sendmail_cf'});
		&copy_source_dest($file."_sendmailmc",
				  $sendmail::config{'sendmail_mc'});
		&unlock_file($sendmail::config{'sendmail_mc'});
		&unlock_file($sendmail::config{'sendmail_cf'});
		undef(@sendmail::sendmailcf_cache);
		&$second_print($text{'setup_done'});
		}
	elsif ($mail_system == 2) {
		# Un-tar qmail dir
		&execute_command("cd $qmailadmin::config{'qmail_dir'} && ".
				 &make_tar_command("xf", $file));
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'backup_vmailserver_supp'});
		}
	}
else {
	&$second_print(&text('restore_vmailserver_wrong',
			     $text{'mail_system_'.$bms},
			     $text{'mail_system_'.$mail_system}));
	}
&release_lock_mail();

return 1;
}

# restore_virtualmin(&domain, file, &opts, &allopts)
# Restore the settings for a domain, such as quota, password and so on. Only
# selected settings are copied from the backup, such as limits.
sub restore_virtualmin
{
my ($d, $file, $opts, $allopts) = @_;
if (!$allopts->{'fix'}) {
	# Merge current and backup configs
	&$first_print($text{'restore_virtualmincp'});
	local %oldd;
	&read_file($file, \%oldd);
	$d->{'quota'} = $oldd{'quota'};
	$d->{'uquota'} = $oldd{'uquota'};
	$d->{'bw_limit'} = $oldd{'bw_limit'};
	$d->{'pass'} = $oldd{'pass'};
	$d->{'email'} = $oldd{'email'};
	foreach my $l (@limit_types) {
		$d->{$l} = $oldd{$l};
		}
	$d->{'nodbname'} = $oldd{'nodbname'};
	$d->{'norename'} = $oldd{'norename'};
	$d->{'forceunder'} = $oldd{'forceunder'};
	$d->{'safeunder'} = $oldd{'safeunder'};
	$d->{'ipfollow'} = $oldd{'ipfollow'};
	foreach my $f (@opt_features, &list_feature_plugins(), "virt") {
		$d->{'limit_'.$f} = $oldd{'limit_'.$f};
		}
	$d->{'owner'} = $oldd{'owner'};
	$d->{'proxy_pass_mode'} = $oldd{'proxy_pass_mode'};
	$d->{'proxy_pass'} = $oldd{'proxy_pass'};
	foreach my $f (&list_custom_fields()) {
		$d->{$f->{'name'}} = $oldd{$f->{'name'}};
		}
	# Disable any features that are not on this system, as they can't
	# be restored from the backup anyway.
	foreach my $f (@features) {
		next if ($f eq 'dir' || $f eq 'unix');	# Always on
		if ($d->{$f} && !$config{$f}) {
			$d->{$f} = 0;
			}
		}
	&lock_domain($d);
	&save_domain($d);
	&unlock_domain($d);
	if (-r $file."_initial") {
		# Also restore user defaults file
		&copy_source_dest($file."_initial",
				  "$initial_users_dir/$d->{'id'}");
		}
	if (-r $file."_admins") {
		# Also restore extra admins
		if ($d->{'id'}) {
			&execute_command(
				"rm -rf ".quotemeta("$extra_admins_dir/$d->{'id'}"));
			}
		if (!-d $extra_admins_dir) {
			&make_dir($extra_admins_dir, 755);
			}
		&make_dir("$extra_admins_dir/$d->{'id'}", 0755);
		&execute_command(
		    "cd ".quotemeta("$extra_admins_dir/$d->{'id'}")." && ".
		    &make_tar_command("xf", $file."_admins", "."));
		}
	if (-r $file."_users") {
		# Also restore extra users
		if ($d->{'id'}) {
			&execute_command(
				"rm -rf ".quotemeta("$extra_users_dir/$d->{'id'}"));
			}
		if (!-d $extra_users_dir) {
			&make_dir($extra_users_dir, 0700);
			}
		&make_dir("$extra_users_dir/$d->{'id'}", 0700);
		&execute_command(
		    "cd ".quotemeta("$extra_users_dir/$d->{'id'}")." && ".
		    &make_tar_command("xf", $file."_users", "."));
		}
	if ($config{'bw_active'} && -r $file."_bw" &&
	    !-r "$bandwidth_dir/$d->{'id'}") {
		# Also restore bandwidth files for the domain, but only
		# if missing.
		&make_dir($bandwidth_dir, 0700);
		&copy_source_dest($file."_bw", "$bandwidth_dir/$d->{'id'}");
		}
	if (-r $file."_scripts") {
		# Also restore script logs
		&execute_command("rm -rf ".
			quotemeta("$script_log_directory/$d->{'id'}"));
		if (-s $file."_scripts") {
			if (!-d $script_log_directory) {
				&make_dir($script_log_directory, 0755);
				}
			&make_dir("$script_log_directory/$d->{'id'}", 0755);
			&execute_command(
			 "cd ".quotemeta("$script_log_directory/$d->{'id'}").
			 " && ".
			 &make_tar_command("xf",
				$file."_scripts", "."));
			}

		# Fix up home dir on scripts
		if ($_[5]->{'home'} && $_[5]->{'home'} ne $d->{'home'}) {
			local $olddir = $_[5]->{'home'};
			local $newdir = $d->{'home'};
			foreach my $sinfo (&list_domain_scripts($d)) {
				$sinfo->{'opts'}->{'dir'} =~
				       s/^\Q$olddir\E\//$newdir\//;
				&save_domain_script($d, $sinfo);
				}
			}
		}
	
	if (-r $file."_saved_aliases") {
		# Restore saved aliases
		&make_dir($saved_aliases_dir, 0700);
		&copy_source_dest($file."_saved_aliases",
				  "$saved_aliases_dir/$d->{'id'}");
		}

	# Restore SSL cert and key unless the domain has an SSL website, in
	# which case we can assume that feature has covered it
	if (!&domain_has_ssl($d)) {
		my $changed = 0;
		&create_ssl_certificate_directories($d);
		foreach my $ssltype ('cert', 'key', 'ca') {
			my $sslfile = &get_website_ssl_file($d, $ssltype);
			my $bfile = $file."_ssl_".$ssltype;
			if ($sslfile && -r $bfile) {
				&lock_file($sslfile);
				&write_ssl_file_contents($d, $sslfile, $bfile);
				&unlock_file($sslfile);
				$changed++;
				}
			}
		if ($changed) {
			&refresh_ssl_cert_expiry($d);
			&sync_combined_ssl_cert($d);
			}
		}

	&$second_print($text{'setup_done'});
	}
return 1;
}

# scp_copy(source, dest, password, &error, port, [as-user])
# Copies a file from some source to a destination. One or the other can be
# a server, like user@foo:/path/to/bar/
sub scp_copy
{
local ($src, $dest, $pass, $err, $port, $asuser) = @_;
if ($src =~ /\s|\(|\)/) {
	my ($host, $path) = split(/:/, $src, 2);
	if ($path) {
		$src = $host.":".quotemeta($path);
		}
	}
if ($dest =~ /\s|\(|\)/) {
	my ($host, $path) = split(/:/, $dest, 2);
	if ($path) {
		$dest = $host.":".quotemeta($path);
		}
	}
local $cmd = "scp -r ".($port ? "-P $port " : "").
	     $config{'ssh_args'}." ".
	     $config{'scp_args'}." ".
	     quotemeta($src)." ".quotemeta($dest);
&run_ssh_command($cmd, $pass, $err, $asuser);
}

# run_ssh_command(command, pass, &error, [as-user])
# Attempt to run some command that uses ssh or scp, feeding in a password.
# Returns the output, and sets the error variable ref if failed.
sub run_ssh_command
{
my ($cmd, $pass, $err, $asuser) = @_;
if ($pass =~ /^\// && -r $pass) {
	# Using a key file
	my ($bin, $args) = split(/\s+/, $cmd, 2);
	$cmd = $bin." -i ".quotemeta($pass)." ".$args;
	$pass = undef;
	}
&foreign_require("proc");
if ($asuser) {
	$cmd = &command_as_user($asuser, 0, $cmd);
	}
my ($fh, $fpid) = &proc::pty_process_exec($cmd);
my $out;
my $nopass = 0;
while(1) {
	my $rv = &wait_for($fh, "password:", "yes\\/no", ".*\n");
	$out .= $wait_for_input;
	if ($rv == 0) {
		if (!defined($pass) || $pass eq "") {
			$nopass = 1;
			last;
			}
		syswrite($fh, "$pass\n");
		}
	elsif ($rv == 1) {
		syswrite($fh, "yes\n");
		}
	elsif ($rv < 0) {
		last;
		}
	}
close($fh);
my $got = waitpid($fpid, 0);
if ($nopass) {
	$$err = "Password required but not supplied";
	}
elsif ($? || $out =~ /permission\s+denied/i || $out =~ /connection\s+refused/i) {
	$$err = $out;
	}
return $out;
}

# free_ip_address(&template|&acl)
# Returns an IP address within the allocation range which is not currently used.
# Checks this system's configured interfaces, and does pings.
sub free_ip_address
{
local ($tmpl) = @_;
local %taken = &interface_ip_addresses();
%taken = (%taken, &domain_ip_addresses(), &cloudmin_ip_addresses());
foreach my $ip (&get_default_ip(), &list_shared_ips()) {
	$taken{$ip}++;
	}
local @ranges = split(/\s+/, $tmpl->{'ranges'});
foreach my $rn (@ranges) {
	my ($r, $n) = split(/\//, $rn);
	$r =~ /^(\d+\.\d+\.\d+)\.(\d+)\-(\d+)$/ || next;
	local ($base, $s, $e) = ($1, $2, $3);
	for(my $j=$s; $j<=$e; $j++) {
		local $try = "$base.$j";
		if (!$taken{$try} && !&ping_ip_address($try)) {
			return wantarray ? ( $try, $n ) : $try;
			}
		}
	}
return wantarray ? ( ) : undef;
}

# free_ip6_address(&template|&acl)
# Returns an IPv6 address within the allocation range which is not currently
# used. Checks this system's configured interfaces, and does pings.
sub free_ip6_address
{
local ($tmpl) = @_;
local %taken = &interface_ip_addresses();
%taken = (%taken, &domain_ip_addresses());
local @ranges = split(/\s+/, $tmpl->{'ranges6'});
foreach my $rn (@ranges) {
	my ($r, $n) = split(/\//, lc($rn));
	$r =~ /^([0-9a-f:]+):([0-9a-f]+)\-([0-9a-f]+)$/ || next;
	local ($base, $s, $e) = ($1, $2, $3);
	for(my $j=hex($s); $j<=hex($e); $j++) {
		local $try = sprintf "%s:%x", $base, $j;
		if (!$taken{$try} && !&ping_ip_address($try)) {
			return wantarray ? ( $try, $n ) : $try;
			}
		}
	}
return wantarray ? ( ) : undef;
}

# interface_ip_addresses()
# Returns a hash of IP addresses that are in use by network interfaces, both
# active and boot-time
sub interface_ip_addresses
{
local %taken;
foreach my $ip (&active_ip_addresses(), &bootup_ip_addresses()) {
	$taken{$ip} = 1;
	}
return %taken;
}

# domain_ip_addresses()
# Returns a hash of IPs that are assigned to any domains as virtual IPs
sub domain_ip_addresses
{
local %taken;
foreach my $d (&list_domains()) {
	$taken{$d->{'ip'}} = 1 if ($d->{'virt'});
	$taken{$d->{'ip6'}} = 1 if ($d->{'virt6'});
	}
return %taken;
}

# cloudmin_ip_addresses()
# Returns a hash of IPs that are assigned to any Cloudmin servers (if installed)
sub cloudmin_ip_addresses
{
local %taken;
if (&foreign_installed("server-manager")) {
	&foreign_require("server-manager");
	foreach my $s (&server_manager::list_managed_servers()) {
		foreach my $ip (&server_manager::get_server_ip($s)) {
			$taken{$ip} = 1;
			}
		foreach my $ip (&server_manager::get_server_ip6($s)) {
			$taken{$ip} = 1;
			}
		}
	}
return %taken;
}

# active_ip_addresses()
# Returns a list of IP addresses (v4 and v6) that are active on the system
# right now.
sub active_ip_addresses
{
&foreign_require("net");
local @rv;
push(@rv, map { $_->{'address'} } &net::active_interfaces());
if (&supports_ip6()) {
	push(@rv, map { $_->{'address'} } &active_ip6_interfaces());
	}
if (&has_command("ip")) {
	# On Linux, the 'ip' command sometimes includes IPs that are not
	# shown by ifconfig -a
	local $out = &backquote_command("ip addr </dev/null 2>/dev/null");
	foreach my $l (split(/\r?\n/, $out)) {
		if ($l =~ /inet\s+([0-9\.]+)/) {
			push(@rv, $1);
			}
		if ($l =~ /inet6\s+([a-f0-9:]+)/) {
			push(@rv, $1);
			}
		}
	}
return grep { $_ ne '' } &unique(@rv);
}

# bootup_ip_addresses()
# Returns a list of IP addresses (v4 and v6) that are activated at boot time
sub bootup_ip_addresses
{
&foreign_require("net");
local @rv;
foreach my $i (&net::boot_interfaces()) {
	if ($i->{'range'} && $i->{'start'} && $i->{'end'}) {
		local $start = &net::ip_to_integer($i->{'start'});
		local $end = &net::ip_to_integer($i->{'end'});
		for(my $j=$start; $j<=$end; $j++) {
			push(@rv, &net::integer_to_ip($j));
			}
		}
	elsif ($i->{'address'}) {
		push(@rv, $i->{'address'});
		}
	}
if (&supports_ip6()) {
	push(@rv, map { $_->{'address'} } &boot_ip6_interfaces());
	}
return grep { $_ ne '' } &unique(@rv);
}

# ping_ip_address(hostname|ip|ipv6)
# Returns 1 if some host responds to a ping in 1 second
sub ping_ip_address
{
local ($host) = @_;
local $pinger = &check_ip6address($host) ? "ping6" : "ping";
local $pingcmd = $gconfig{'os_type'} =~ /-linux$/ ? "$pinger -c 1 -t 1"
						  : $pinger;
local ($out, $timed_out) = &backquote_with_timeout(
	$pingcmd." ".$host." 2>&1", 1, 1);
return !$timed_out && !$?;
}

# parse_ip_ranges(ranges)
# Returns a list of all IP allocation ranges, each of which is a 3-element
# array of starting IP, ending IP and optional netmask
sub parse_ip_ranges
{
local @rv;
local @ranges = split(/\s+/, $_[0]);
foreach my $rn (@ranges) {
	my ($r, $n) = split(/\//, $rn);
	if ($r =~ /^(\d+\.\d+\.\d+)\.(\d+)\-(\d+)$/) {
		# IPv4 range
		push(@rv, [ "$1.$2", "$1.$3", $n ]);
		}
	elsif ($r =~ /^([0-9a-f:]+):([0-9a-f]+)-([0-9a-f]+)$/i) {
		# IPv6 range
		push(@rv, [ "$1:$2", "$1:$3", $n ]);
		}
	}
return @rv;
}

# join_ip_ranges(&ranges)
# Converts a list of ranges into a string
sub join_ip_ranges
{
local @ranges;
foreach my $r (@{$_[0]}) {
	if (&check_ipaddress($r->[0])) {
		# IPv4 range
		local @start = split(/\./, $r->[0]);
		local @end = split(/\./, $r->[1]);
		push(@ranges, join(".", @start)."-".$end[3].
			      ($r->[2] ? "/".$r->[2] : ""));
		}
	elsif (&check_ip6address($r->[0])) {
		# IPv6 range
		local @end = split(/:/, $r->[1]);
		push(@ranges, $r->[0]."-".$end[$#end].
			      ($r->[2] ? "/".$r->[2] : ""));
		}
	}
return join(" ", @ranges);
}

# ip_within_ranges(ip, ranges-string)
# Returns 1 if some IP falls within a space-separated list of ranges
sub ip_within_ranges
{
my ($ip, $ranges) = @_;
&foreign_require("net");
my $n = &net::ip_to_integer($ip);
foreach my $r (&parse_ip_ranges($ranges)) {
	if (&check_ipaddress($r->[0])) {
		# IPv4 range
		if ($n >= &net::ip_to_integer($r->[0]) &&
		    $n <= &net::ip_to_integer($r->[1])) {
			return 1;
			}
		}
	elsif (&check_ip6address($r->[0])) {
		# IPv6 range
		my ($p, $n) = split(/\//, lc($r));
		$p =~ /^([0-9a-f:]+):([0-9a-f]+)\-([0-9a-f]+)$/ || next;
		local ($base, $s, $e) = ($1, $2, $3);
		$ip =~ /^([0-9a-f:]+):([0-9a-f]+)$/ || next;
		if (lc($1) eq lc($base) &&
		    hex($2) >= hex($s) && hex($2) <= hex($e)) {
			return 1;
			}
		}
	}
return 0;
}

# setup_for_subdomain(&parent-domain, subdomain-user, &sub-domain)
# Ensures that this virtual server can host sub-servers
sub setup_for_subdomain
{
local ($d, $subuser, $subd) = @_;
if (!-d "$d->{'home'}/domains") {
	&make_dir_as_domain_user($d, "$d->{'home'}/domains", 0755);
	}
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
if ($left != 0 && $type ne "aliasdoms") {
	# If no limit has been hit, check the licence
	local ($lstatus, $lexpiry, $lerr, $ldoms) = &check_licence_expired();
	if ($ldoms) {
		local $donedef = 0;
		local @doms = grep { !$_->{'alias'} &&
				     (!$_->{'defaultdomain'} || $donedef++) }
				   &list_domains();
		if (@doms > $ldoms) {
			return (0, 3, $ldoms, 0);
			}
		else {
			# Haven't reached .. check if the licence limit is
			# less than the current limit
			local $dleft = $ldoms - @doms;
			if ($left == -1 || $dleft < $left) {
				# Will hit licensed domains limit
				return ($dleft, 3,
					$max < $ldoms && $max > 0 ? $max : $ldoms, 0);
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
# Feature can be "doms", "aliasdoms", "realdoms", "topdoms", "mailboxes",
# "aliases", "quota", "uquota", "dbs", "bw" or a feature
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
	($reseller) = split(/\s+/, $parent->{'reseller'});
	}
else {
	$reseller = $user;
	}

if ($reseller && defined(&get_reseller_domains)) {
	# Either this user is owned by a reseller, or he is a reseller.
	local @rdoms = &get_reseller_domains($reseller);
	local %racl = &get_reseller_acl($reseller);
	local $reason = $access{'reseller'} ? 2 : 1;
	local $hide = $base_remote_user ne $reseller && $racl{'hide'};
	local $limit = $racl{"max_".$f};
	if ($limit ne "") {
		# Reseller has a limit ..
		local $got = &count_domain_feature($f, @rdoms);
		if ($got > $limit || $got < 0) {
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
	if (($f eq "aliasdoms" || $f eq "realdoms" || $f eq "topdoms") &&
	    $racl{'max_doms'}) {
		# See if the reseller is over the limit for all domains types
		local $got = &count_domain_feature("doms", @rdoms);
		if ($got >= $racl{'max_doms'}) {
			return (0, $reason, $racl{'max_doms'}, $hide);
			}
		}
	if ($f eq "topdoms" && $racl{'max_realdoms'}) {
		# See if the reseller is over the limit for all real domains
		local $got = &count_domain_feature("realdoms", @rdoms);
		if ($got >= $racl{'max_realdoms'}) {
			return (0, $reason, $racl{'max_realdoms'}, $hide);
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
		if (!$d->{'parent'}) {
			return -1 if ($d->{$f} eq "" || $d->{$f} eq "0");
			$rv += $d->{$f};
			}
		}
	elsif ($f eq "bw") {
		if (!$d->{'parent'}) {
			return -1 if ($d->{'bw_limit'} eq "" ||
				      $d->{'bw_limit'} eq "0");
			$rv += $d->{'bw_limit'};
			}
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
	elsif ($f eq "topdoms") {
		$rv++ if (!$d->{'parent'});
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
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local %hash = %$d;
if (!$hash{'uid'}) {
	# Fake UID allocation now, in case the template uses it
	local %taken;
        &build_taken(\%taken);
        $hash{'uid'} = &allocate_uid(\%taken);
	}
if (!$hash{'gid'}) {
	# Fake GID allocation
	local %gtaken;
	&build_group_taken(\%gtaken);
	$hash{'gid'} = &allocate_gid(\%gtaken);
	}
local $db = &substitute_domain_template($tmpl->{'mysql'}, \%hash);
$db = lc($db);
$db ||= $d->{'prefix'};
$db = &fix_database_name($db, $d->{'mysql'} && $d->{'postgres'} ? undef :
			      $d->{'mysql'} ? 'mysql' : 'postgres');
return $db;
}

# fix_database_name(dbname, [dbtype])
# If a database name starts with a number, convert it to a word to support
# PostgreSQL, which doesn't like numeric names. Also converts . and - to _,
# and handles reserved DB names.
sub fix_database_name
{
local ($db, $dbtype) = @_;
if (!$dbtype) {
	# Guess DB type
	my @dbtypes = grep { $config{$_} } @database_features;
	if (scalar(@dbtypes) == 1) {
		$dbtype = $dbtypes[0];
		}
	}
$db = lc($db);
$db =~ s/[\.\-]/_/g;	# mysql doesn't like . or _
if ($db eq "test" || $db eq "mysql" || $db =~ /^template/) {
	# These names are reserved by MySQL and PostgreSQL
	$db = "db".$db;
	}
if (!$dbtype || $dbtype eq "mysql") {
	# MySQL DB names cannot be longer than 64 chars
	if (length($db) > 64) {
		$db = substr($db, 0, 64);
		}
	}
return $db;
}

# remove_numeric_prefix(name)
# If a name starts with a number, convert it to a work
sub remove_numeric_prefix
{
my ($db) = @_;
return $db if ($config{'allow_numbers'} && $db !~ /^\d+$/);
$db =~ s/^0/zero/g;
$db =~ s/^1/one/g;
$db =~ s/^2/two/g;
$db =~ s/^3/three/g;
$db =~ s/^4/four/g;
$db =~ s/^5/five/g;
$db =~ s/^6/six/g;
$db =~ s/^7/seven/g;
$db =~ s/^8/eight/g;
$db =~ s/^9/nine/g;
return $db;
}

# validate_database_name(&domain, type, name)
# Returns an error message if a name is invalid, undef if OK
sub validate_database_name
{
local ($d, $dbtype, $dbname) = @_;
local $vfunc = "validate_database_name_".$dbtype;
if (defined(&$vfunc)) {
	return &$vfunc($d, $dbname);
	}
else {
	# Default rules
	$dbname =~ /^[a-z0-9\_]+$/i && $dbname =~ /^[a-z]/i ||
		return $text{'database_ename'};
	return undef;
	}
}

# generate_random_available_user(pattern)
# Generates free user available to be used as
# Unix user, group, and virtual server user
sub generate_random_available_user
{
my ($pattern) = @_;
$pattern ||= 'u-[0-9]{4}';
state $user;
if (!defined($user)) {
	for (;;) {
		my $rand_name = &substitute_pattern($pattern,
			              {'filter' => '[^A-Za-z0-9\\-_]',
			               'substitute-datetime' => 1});
		my $uname_clash = defined(getpwnam($rand_name)) ||
		                  defined(getgrnam($rand_name)) ||
		                  &get_domain_by("prefix", $rand_name);
		if (!$uname_clash) {
			$user = $rand_name;
			last;
			}
		}
	}
return $user;
}

# unixuser_name(domainname)
# Returns a Unix username for some domain, or undef if none can be found
sub unixuser_name
{
my ($dname) = @_;
my ($dname_, $config_longname, $try1, $user) = ($dname, $config{'longname'});

if ($config_longname && $config_longname !~ /^[0-9]$/) {
	# Extract random username based on the user pattern
	$user = &generate_random_available_user($config_longname);
	}
elsif ($config_longname == 2) {
	$user = &compute_prefix($dname, undef, undef, 1);
	}
else {
	# Use one based on actual domain name
	$dname =~ s/^xn(-+)//;
	$dname = &remove_numeric_prefix($dname);
	$dname =~ /^([^\.]+)/;
	($try1, $user) = ($1, $1);
	if (defined(getpwnam($try1)) || $config_longname) {
		$user = &remove_numeric_prefix($dname_);
		$try2 = $user;
		if (defined(getpwnam($try2))) {
			return (undef, $try1, $try2);
			}
		}
	}
if ($config{'username_length'} && length($user) > $config{'username_length'}) {
	# Admin asked for a short username
	my $short = substr($user, 0, $config{'username_length'});
	if (!defined(getpwnam($short))) {
		$user = $short;
		}
	}
return ($user);
}

# unixgroup_name(domainname, username)
# Returns a Unix group name for some domain, or undef if none can be found
sub unixgroup_name
{
my ($dname, $user) = @_;
my ($dname_, $config_longname, $try1, $group) = ($dname, $config{'longname'});

if ($user && $config{'groupsame'}) {
	# Same as username where possible
	if (!defined(getgrnam($user))) {
		return ($user);
		}
	return (undef, $user, $user);
	}
# Extract random group based on the user pattern
if ($config_longname && $config_longname !~ /^[0-9]$/) {
	$group = &generate_random_available_user($config_longname);
	}
elsif ($config_longname == 2) {
	$group = &compute_prefix($dname, undef, undef, 1);
	}
# Use one based on actual domain name
else {
	$dname =~ s/^xn(-+)//;
	$dname = &remove_numeric_prefix($dname);
	$dname =~ /^([^\.]+)/;
	($try1, $group) = ($1, $1);
	if (defined(getgrnam($try1)) || $config{'longname'}) {
		$group = &remove_numeric_prefix($dname_);
		$try2 = $group;
		if (defined(getpwnam($try))) {
			return (undef, $try1, $try2);
			}
		}
	}
return ($group);
}

# virtual_server_clashes(&dom, [&features-to-check], [field-to-check],
# 			 [replication-mode])
# Returns a clash error message if any were found for some new domain
sub virtual_server_clashes
{
local ($dom, $check, $field, $repl) = @_;
my $f;
foreach $f (@features) {
	next if ($dom->{'parent'} && $f eq "webmin");
	next if ($dom->{'parent'} && $f eq "unix");
	if ($dom->{$f} && (!$check || $check->{$f})) {
		local $cfunc = "check_${f}_clash";
		local $err = defined(&$cfunc) ? &$cfunc($dom, $field, $repl)
					      : undef;
		if ($err) {
			if ($err eq '1') {
				# Use a built-in error
				$err = &text('setup_e'.$f,
					     $dom->{'dom'}, $dom->{'db'},
					     $dom->{'user'}, $dom->{'group'});
				}
			return $err;
			}
		}
	}
foreach $f (&list_feature_plugins()) {
	if ($dom->{$f} && (!$check || $check->{$f})) {
		local $cerr = &plugin_call($f, "feature_clash", $dom, $field);
		return $cerr if ($cerr);
		}
	}
return undef;
}

# virtual_server_depends(&dom, [feature], [&old-dom])
# Returns an error message if any of the features in the domain depend on
# missing features
sub virtual_server_depends
{
local ($d, $feat, $oldd) = @_;
local $f;

# Check features that are enabled
foreach $f (grep { $d->{$_} } @features) {
	next if ($feat && $f ne $feat);
	local $dfunc = "check_depends_$f";
	if (defined(&$dfunc)) {
		# Call dependecy function
		local $derr = &$dfunc($d, $oldd);
		return $derr if ($derr);
		}
	# Check fixed dependency list
	local $fd;
	foreach $fd (@{$feature_depends{$f}}) {
		return &text('setup_edep'.$f) if (!$d->{$fd});
		}
	}

# Check plugins that are enabled
foreach $f (grep { $d->{$_} } &list_feature_plugins()) {
	next if ($feat && $f ne $feat);
	local $derr = &plugin_call($f, "feature_depends", $d, $oldd);
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
local $tmpl = &get_template($d->{'template'});

# Check database limit
local $newdbs = 0;
$newdbs++ if ($d->{'mysql'} && (!$oldd || !$oldd->{'mysql'}) &&
	      $tmpl->{'mysql_mkdb'} && !$d->{'no_mysql_db'});
$newdbs++ if ($d->{'postgres'} && (!$oldd || !$oldd->{'postgres'}) &&
	      $tmpl->{'mysql_mkdb'});
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
		     &quota_show($left+($oldd ? $oldd->{'quota'} : 0),
				 "home", 2));
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
	($left, $reason, $max) = &count_domains(
				$d->{'alias'} ? 'aliasdoms' :
				$d->{'parent'} ? 'realdoms' : 'topdoms');
	if ($left == 0) {
		return &text('index_noadd'.$reason, $max);
		}
	}

return undef;
}

# virtual_server_warnings(&domain, [&old-domain], [replication-mode])
# Returns a list of warning messages related to the creation or modification
# of some virtual server.
sub virtual_server_warnings
{
local ($d, $oldd, $repl) = @_;
local @rv;

# Check core features
foreach my $f (grep { $d->{$_} } @features) {
	local $wfunc = "check_warnings_$f";
	if (defined(&$wfunc)) {
		local $err = &$wfunc($d, $oldd, $repl);
		push(@rv, $err) if ($err);
		}
	}

# Check plugins that are enabled
foreach $f (grep { $d->{$_} } &list_feature_plugins()) {
	local $err = &plugin_call($f, "feature_warnings", $d, $oldd);
	push(@rv, $err) if ($err);
	}
return @rv;
}

# show_virtual_server_warnings(&domain, [&old-domain], &in)
# Checks if there are any warnings for the creation or modification of some
# domain, and if so shows a confirmation form - unless $in{'confirm_warnings'}
# is set. Returns 1 if the warning form was shown, 0 if not.
sub show_virtual_server_warnings
{
local ($d, $oldd, $in) = @_;
return 0 if ($in->{'confirm_warnings'});
local @warns = &virtual_server_warnings($d, $oldd);
return 0 if (!@warns);

my @hids;
foreach my $i (keys %$in) {
	foreach my $v (split(/\0/, $in->{$i})) {
		push(@hids, [ $i, $v ]);
		}
	}
print &ui_confirmation_form(
	$script_name,
	($oldd ? $text{'setup_warnings2'} : $text{'setup_warnings1'})."<p>\n".
	join("<br>\n", @warns)."<p>\n".
	$text{'setup_warnrusure'},
	\@hids,
	[ [ 'confirm_warnings', $oldd ? $text{'setup_warnok2'}
				      : $text{'setup_warnok1'} ] ],
	);
return 1;
}

# domain_name_clash(name)
# Returns 1 if some domain name is already in use
sub domain_name_clash
{
my ($domain) = @_;
foreach my $d (&list_domains()) {
        return $d if (lc($d->{'dom'}) eq lc($domain));
        }
return 0;
}

# create_virtual_server(&domain, [&parent-domain], [parent-user], [no-scripts],
#                       [no-post-actions], [password], [content])
# Given a complete domain object, setup all it's features
sub create_virtual_server
{
local ($dom, $parentdom, $parentuser, $noscripts, $nopost,
       $pass, $content) = @_;

# Sanity checks
$dom->{'ip'} || $dom->{'ip6'} || return $text{'setup_edefip'};

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

# Work out the auto-alias domain name
local $tmpl = &get_template($dom->{'template'});
local $aliasname;
if ($tmpl->{'domalias'} ne 'none' && $tmpl->{'domalias'} && !$dom->{'alias'}) {
	local $aliasprefix = $dom->{'dom'};
	if ($tmpl->{'domalias_type'} eq '1') {
		# Shorten to first part of domain
		$aliasprefix =~ s/\..*$//;
		}
	elsif ($tmpl->{'domalias_type'} ne '0') {
		# Use template
		$aliasprefix = &substitute_domain_template(
				$tmpl->{'domalias_type'}, $dom);
		}
	my $count;
	while(1) {
		$aliasname = $aliasprefix.$count.".".$tmpl->{'domalias'};
		last if (!&get_domain_by("dom", $aliasname));
		$count++;
		}
	$dom->{'autoalias'} = $aliasname;
	}

# Work out auto disable schedule
if ($tmpl->{'domauto_disable'} &&
    $tmpl->{'domauto_disable'} =~ /^(\d+)$/) {
	$dom->{'disabled_auto'} = time() + $tmpl->{'domauto_disable'}*86400;
	}

# Check if only hashed passwords are stored, and if so generate a random
# MySQL password now. This has to be done before any features are setup
# so that mysql_pass is available to all features.
if ($dom->{'hashpass'} && !$dom->{'parent'} && !$dom->{'mysql_pass'}) {
	# Hashed passwords in use
	$dom->{'mysql_pass'} = &random_password();
	delete($dom->{'mysql_enc_pass'});
	}
elsif ($tmpl->{'mysql_nopass'} == 2 && !$dom->{'parent'} &&
       !$dom->{'mysql_pass'}) {
	# Using random password by default
	$dom->{'mysql_pass'} = &random_password();
	delete($dom->{'mysql_enc_pass'});
	}

# Same for PostgreSQL
if ($dom->{'hashpass'} && !$dom->{'parent'} && !$dom->{'postgres_pass'}) {
	# Hashed passwords in use
	$dom->{'postgres_pass'} = &random_password();
	delete($dom->{'postgres_enc_pass'});
	}
elsif ($tmpl->{'postgres_nopass'} == 2 && !$dom->{'parent'} &&
       !$dom->{'postgres_pass'}) {
	# Using random password by default
	$dom->{'postgres_pass'} = &random_password();
	delete($dom->{'postgres_enc_pass'});
	}

# MySQL module comes from parent always
if ($parentdom) {
	$dom->{'mysql_module'} = $parentdom->{'mysql_module'};
	$dom->{'postgres_module'} = $parentdom->{'postgres_module'};
	}

# Was this originally the default domain?
if (!defined($dom->{'defaultdomain'})) {
	$dom->{'defaultdomain'} = 1, $dom->{'defaulthostdomain'} = 1
		if ($dom->{'dom'} eq $config{'defaultdomain_name'});
	}

# Save domain details before enabling features
&$first_print($text{'setup_save'});
&save_domain($dom, 1);
&$second_print($text{'setup_done'});

# Set up all the selected features (except Webmin login)
my $f;
local @dof = grep { $_ ne "webmin" } @features;
local $p = &domain_has_website($dom);
local $s = &domain_has_ssl($dom);
$dom->{'creating'} = 1;	# Tell features that they are being called for creation
foreach $f (@dof) {
	my $err;
	if ($f eq 'web' && $p && $p ne 'web') {
		# Web feature is provided by a plugin .. call it now
		$err = &call_feature_setup($p, $dom);
		}
	elsif ($f eq 'ssl' && $s && $s ne 'ssl') {
		# SSL feature is provided by a plugin .. call it now
		$err = &call_feature_setup($s, $dom);
		}
	elsif ($dom->{$f}) {
		$err = &call_feature_setup($f, $dom);
		}
	return $err if ($err);
	}

# Set up all the selected plugins
foreach $f (&list_feature_plugins()) {
	if ($dom->{$f} && $f ne $p && $f ne $s) {
		my $err = &call_feature_setup($f, $dom);
		return $err if ($err);
		}
	}

# Setup Webmin login last, once all plugins are done
if ($dom->{'webmin'}) {
	local $sfunc = "setup_webmin";
	local ($ok, $fok) = &try_function($f, $sfunc, $dom);
	if (!$ok || !$fok) {
		$dom->{$f} = 0;
		}
	}

# Add virtual IP address, if needed
if ($dom->{'virt'}) {
	local ($ok, $fok) = &try_function("virt", "setup_virt", $dom);
	if (!$ok || !$fok) {
		$dom->{'virt'} = 0;
		}
	}
if ($dom->{'virt6'}) {
	local ($ok, $fok) = &try_function("virt6", "setup_virt6", $dom);
	if (!$ok || !$fok) {
		$dom->{'virt6'} = 0;
		}
	}
delete($dom->{'creating'});

# Save domain details again at the end
&$first_print($text{'setup_save'});
&save_domain($dom);
&$second_print($text{'setup_done'});

# Now we have an ID, lock the domain
&lock_domain($dom);

# If mail client autoconfig is enabled globally, set it up for
# this domain
if ($config{'mail_autoconfig'} && $dom->{'mail'} &&
    &domain_has_website($dom) && !$dom->{'alias'}) {
	&enable_email_autoconfig($dom);
	}

if (!$nopost) {
	&run_post_actions();
	}

if (!$dom->{'nocreationmail'}) {
	# Notify the owner via email
	&send_domain_email($dom, undef, $pass);
	}

# Update the parent domain Webmin user
&refresh_webmin_user($dom);

if ($remote_user) {
	# Add to this user's list of domains if needed
	local %access = &get_module_acl();
	if (!&can_edit_domain($dom)) {
		$access{'domains'} = join(" ", split(/\s+/, $access{'domains'}),
					       $dom->{'id'});
		&save_module_acl(\%access);
		}
	}

# Update any secondary groups that might contain the domain owner
if (!$dom->{'parent'}) {
	&update_secondary_groups($dom);
	}

# Create an automatic alias domain, if specified in template
if ($aliasname && $aliasname ne $dom->{'dom'}) {
	&$first_print(&text('setup_domalias', $aliasname));
	if ($aliasname !~ /^[a-z0-9\.\_\-]+$/i) {
		&$second_print($text{'setup_domaliasbad'});
		}
	else {
		&$indent_print();
		local $parentdom = $dom->{'parent'} ?
			&get_domain($dom->{'parent'}) : $dom;
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
				 'dns_ip', $dom->{'dns_ip'},
				 'virt', 0,
				 'source', $dom->{'source'},
				 'parent', $parentdom->{'id'},
				 'template', $dom->{'template'},
				 'plan', $dom->{'plan'},
				 'reseller', $dom->{'reseller'},
				);
		# Alias gets all features of domain, except for directory
		# if it isn't needed
		foreach my $f (@alias_features) {
			next if ($f eq 'dir' && $config{$f} == 3 &&
				 $tmpl->{'aliascopy'});
			$alias{$f} = $dom->{$f};
			}
		my $web = &domain_has_website($dom);
		if ($web) {
			# Website may use Nginx
			$alias{$web} = 1;
			}
		$alias{'home'} = &server_home_directory(\%alias, $parentdom);
		&generate_domain_password_hashes(\%dom, 1);
		&set_provision_features(\%alias);
		&complete_domain(\%alias);
		&create_virtual_server(\%alias, $parentdom,
				       $parentdom->{'user'});
		&$outdent_print();
		&$second_print($text{'setup_done'});
		}
	}

# Set any PHP variables defined in the template
&setup_web_for_php($dom, undef, undef);

# Install any scripts specified in the template
local @scripts = &get_template_scripts($tmpl);
if (@scripts && !$dom->{'alias'} && !$noscripts &&
    &domain_has_website($dom) && $dom->{'dir'} &&
    !$dom->{'nocreationscripts'}) {
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

		# Work out actual version
		local @allvers = @{$script->{'install_versions'}};
		if ($ver eq "latest") {
			$ver = $allvers[0];
			}

		&$first_print(&text('setup_scriptinstall',
				    $script->{'name'}, $ver));
		local $opts = { 'path' => &substitute_scriptname_template(
						$sinfo->{'path'}, $d) };
		if ($sinfo->{'sopts'}) {
			$opts->{$_->[0]} = $_->[1]
				for map { [split(/=/, $_)] }
					split(/,/, $sinfo->{'sopts'});
			}
		local $perr = &validate_script_path($opts, $script, $dom);
		if ($perr) {
			&$second_print(&text('setup_scriptpath', $perr));
			next;
			}

		# Install needed packages
		&setup_script_packages($script, $d, $ver);

		# Check PHP version
		local ($phpver, $phperr);
		if (&indexof("php", @{$script->{'uses'}}) >= 0) {
			($phpver, $phperr) = &setup_php_version(
				$dom, $script, $ver, $opts->{'path'});
			if (!$phpver) {
				&$second_print(
				    &text('setup_scriptphpverset', $phperr));
				next;
				}
			$opts->{'phpver'} = $phpver;
			}

		# Check Python version
		local ($pyver, $pyerr);
		if (&indexof("python", @{$script->{'uses'}}) >= 0) {
			($pyver, $pyerr) = &setup_python_version(
				$dom, $script, $ver, $opts->{'path'});
			if ($pyerr) {
				&$second_print($pyerr);
				next;
				}
			$opts->{'pyver'} = $pyver;
			}

		# Check dependencies
		local $derr = &check_script_depends($script, $dom, $ver,
						    $sinfo, $phpver);
		if ($derr) {
			&$second_print(&text('setup_scriptdeps', $derr));
			next;
			}

		# Install needed PHP modules
		if (!&setup_script_requirements($d, $script, $ver, $phpver, $opts)) {
			&$second_print($text{'setup_scriptreqs'});
			next;
			}

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
		local $ferr = &fetch_script_files($script, $dom, $ver, $opts,
						  undef, \%gotfiles, 1);
		if ($derr) {
			&$second_print(&text('setup_scriptfetch', $ferr));
			next;
			}

		# Disable PHP timeouts
		local $t = &disable_script_php_timeout($dom);

		# Call the install function
		local $dompass = $dom->{'pass'} || &random_password(8);
		local ($ok, $msg, $desc, $url, $suser, $spass) =
			&{$script->{'install_func'}}(
				$dom, $ver, $opts, \%gotfiles, undef,
				$dom->{'user'}, $dompass);

		if ($ok) {
			&$second_print(&text($ok < 0 ? 'setup_scriptpartial' :
						'setup_scriptdone', $msg));

			# Record script install in domain
			&add_domain_script($dom, $name, $ver, $opts,
					   $desc, $url, $suser, $spass,
					   $ok < 0 ? $msg : undef);
			}
		else {
			&$second_print(&text('setup_scriptfailed', $msg));
			}

		# Re-enable script PHP timeout
		&enable_script_php_timeout($dom, $t);
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	&save_domain($dom);
	}

# Create any redirects or aliases specified in the template
my @redirs = map { [ split(/\s+/, $_, 4) ] }
		 split(/\t+/, $tmpl->{'web_redirects'});
if (@redirs && !$dom->{'alias'} &&  &domain_has_website($dom) &&
    !$noscripts && !$dom->{'nocreationscripts'}) {
	&$first_print($text{'setup_redirects'});
	&$indent_print();
	foreach my $r (@redirs) {
		my %protos = map { $_, 1 } split(/,/, $r->[2]);
		next if ($protos{'https'} && !$protos{'http'} &&
			 !&domain_has_ssl($dom));
		my $path = &substitute_domain_template($r->[0], $dom);
		my $dest = &substitute_domain_template($r->[1], $dom);
		&$first_print(&text('setup_redirecting', $path, $dest));
		if ($dest !~ /^(http|https):/) {
			$dest = &public_html_dir($dom).$dest;
			}
		my $redirect = { 'path' => $path,
				 'dest' => $dest,
				 'alias' => $dest =~ /^(http|https):/ ? 0 : 1,
				 'regexp' => 0,
				 'http' => $protos{'http'},
				 'https' => $protos{'https'},
			       };
		if ($r->[3]) {
			$redirect->{'host'} =
				&substitute_domain_template($r->[3], $dom);
			}
		$redirect = &add_wellknown_redirect($redirect);
		my $err = &create_redirect($dom, $redirect);
		if ($err) {
			&$second_print(&text('setup_redirecterr', $err));
			}
		else {
			&$second_print($text{'setup_redirected'});
			}
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

# If this was an alias domain, notify all features in the original domain. This
# is useful for things like awstats, which need to add the alias domain to those
# supported for the main site.
if ($dom->{'alias'}) {
	local $aliasdom = &get_domain($dom->{'alias'});
	foreach my $f (@features) {
		local $safunc = "setup_alias_$f";
		if ($aliasdom->{$f} && defined(&$safunc)) {
			&try_function($f, $safunc, $aliasdom, $dom);
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($aliasdom->{$f} &&
		    &plugin_defined($f, "feature_setup_alias")) {
			local $main::error_must_die = 1;
			eval { &plugin_call($f, "feature_setup_alias",
					    $aliasdom, $dom) };
			if ($@) {
				&$second_print(&text('setup_aliasfailure',
					&plugin_call($f, "feature_name"),"$@"));
				}
			}
		}
	}

# Refresh Unix group membership for reseller
if ($dom->{'reseller'} && defined(&update_reseller_unix_groups)) {
	local $rinfo = &get_reseller($dom->{'reseller'});
	if ($rinfo) {
		&update_reseller_unix_groups($rinfo, 1);
		}
	}

# Setup MTA-STS if defined in the template
if (&can_mta_sts($dom) && $tmpl->{'mail_mta_sts'}) {
	&$first_print($text{'mail_mta_sts_on'});
	my $err = &enable_mta_sts($dom);
	&$second_print($err ? &text('mail_mta_sts_err', $err)
			    : $text{'setup_done'});
	}

# If an SSL cert wasn't generated because SSL wasn't enabled, do one now
my $always_ssl = defined($dom->{'always_ssl'}) ? $dom->{'always_ssl'}
					       : $tmpl->{'ssl_always_ssl'};
my $generated = 0;
if (!&domain_has_ssl($dom) && $always_ssl && !$dom->{'alias'}) {
	$generated = &generate_default_certificate($dom) ? 1 : 0;
	}

# Attempt to request a let's encrypt cert. This has to be done after the
# initial setup and when Apache has been restarted, so that it can serve the
# new website.
if (!defined($dom->{'auto_letsencrypt'})) {
	$dom->{'auto_letsencrypt'} = $tmpl->{'ssl_auto_letsencrypt'};
	if ($dom->{'dns'}) {
		$dom->{'letsencrypt_dwild'} = $tmpl->{'ssl_letsencrypt_wild'};
		}
	}
if (!defined($dom->{'letsencrypt_subset'})) {
	$dom->{'letsencrypt_subset'} = $tmpl->{'ssl_allow_subset'};
	}
if ($dom->{'auto_letsencrypt'} && &domain_has_website($dom) &&
    !$dom->{'disabled'} && !$dom->{'alias'} && !$dom->{'ssl_same'} &&
    &under_public_dns_suffix($dom->{'dom'})) {
	my $info = &cert_info($dom);
	if ($info->{'self'}) {
		if ($nopost) {
			# Need to run any pending Apache restart
			&run_post_actions(\&restart_apache);
			}
		if (&create_initial_letsencrypt_cert(
			$dom, $dom->{'auto_letsencrypt'} == 2 ? 0 : 1,
			$config{'err_letsencrypt'})) {
			# Let's encrypt cert request worked
			$generated = 2;
			}
		}
	}

# Update service certs and DANE DNS records if a new Let's Encrypt cert
# was generated
if ($generated == 2) {
	&enable_domain_service_ssl_certs($dom);
	&sync_domain_tlsa_records($dom);
	}

# For a new alias domain, if the target has a Let's Encrypt cert for all
# possible hostnames, re-request it to include the alias
if ($dom->{'alias'} && &domain_has_website($dom)) {
	local $target = &get_domain($dom->{'alias'});
	local $tinfo;
	if ($target &&
	    &domain_has_website($target) &&
	    &domain_has_ssl_cert($target) &&
	    ($tinfo = &cert_info($target)) &&
	    &is_acme_cert($tinfo) &&
	    !&check_domain_certificate($dom->{'dom'}, $tinfo)) {
		&$first_print(&text('setup_letsaliases',
				    &show_domain_name($target),
				    &show_domain_name($dom)));
		my $old_dname = $target->{'letsencrypt_dname'};
		if ($target->{'letsencrypt_dname'}) {
			# Add the alias domain's SSL hostnames to the list
			$target->{'letsencrypt_dname'} =
			 join(" ", split(/\s+/, $target->{'letsencrypt_dname'}),
				    &get_hostnames_for_ssl($d));
			}
		my ($ok, $err, $dnames) = &renew_letsencrypt_cert($target);
		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		else {
			$target->{'letsencrypt_dname'} = $old_dname;
			&$second_print(&text('setup_eletsaliases', $err));
			}
		}
	}

&save_domain($dom);

# Put the user in a jail if possible
if (&is_domain_jailed($dom) && !&check_jailkit_support()) {
	&$first_print($text{'setup_jail'});
	my $err = &enable_domain_jailkit($dom);
	if ($err) {
		&$second_print(&text('setup_ejail', $err));
		}
	else {
		&$second_print(&text('setup_jailed',
				     &domain_jailkit_dir($dom)));
		}
	&save_domain($dom);
	}

if (!$dom->{'alias'} && &domain_has_website($dom) && defined($content)) {
	# Just create virtualmin default index.html
	&$first_print($text{'setup_contenting'});
	eval {
		local $main::error_must_die = 1;
		&create_index_content($dom, $content, 0);
		};
	if ($@) {
		&$second_print(&text('setup_econtenting', "$@"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

# Run the after creation command
if (!$nopost) {
	&run_post_actions();
	}
&unlock_domain($dom);
&set_domain_envs($dom, "CREATE_DOMAIN");
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($dom);

return wantarray ? ($dom) : undef;
}

# create_initial_letsencrypt_cert(&domain, [validate-first], [show-errors])
# Create the initial default let's encrypt cert for a domain which has just
# had SSL enabled. May print stuff.
sub create_initial_letsencrypt_cert
{
local ($d, $valid, $showerrors) = @_;
&foreign_require("webmin");
my @dnames;
if ($d->{'letsencrypt_dname'}) {
	@dnames = split(/\s+/, $d->{'letsencrypt_dname'});
	}
else {
	@dnames = &get_hostnames_for_ssl($d);
	}
push(@dnames, "*.".$d->{'dom'}) if ($d->{'letsencrypt_dwild'});
&$first_print($text{'letsencrypt_doing3'});
if ($valid) {
	my $vcheck = ['web'];
	foreach my $dn (@dnames) {
		$vcheck = ['dns'] if ($dn =~ /\*/);
		}
	my @errs = &validate_letsencrypt_config($d, $vcheck);
	if (@errs) {
		# Always store last Certbot error
		my @estr;
		foreach my $e (@errs) {
			push(@estr, $e->{'desc'}." : ".
					&html_strip($e->{'error'}));
			}
		my $err = &html_escape(join(", ", @estr));
		$d->{'letsencrypt_last_failure'} = time();
		$d->{'letsencrypt_last_err'} = $err;
		$d->{'letsencrypt_last_err'} =~ s/\r?\n/\t/g;
		if ($showerrors) {
			&$second_print(&text('letsencrypt_evalid', $err));
			}
		else {
			&$second_print($text{'letsencrypt_doing3failed'});
			}
		return 0;
		}
	if (defined(&check_domain_connectivity)) {
		@errs = &check_domain_connectivity(
			$d, { 'mail' => 1, 'ssl' => 1 });
		if (@errs) {
			# Always store last Certbot error
			my $e = &html_escape(join(", ",
				map { $_->{'desc'} } @errs));
			$d->{'letsencrypt_last_failure'} = time();
			$d->{'letsencrypt_last_err'} = $e;
			$d->{'letsencrypt_last_err'} =~ s/\r?\n/\t/g;
			if ($showerrors) {
				&$second_print(&text('letsencrypt_econnect', $e));
				}
			else {
				&$second_print($text{'letsencrypt_doing3failed'});
				}
			return 0;
			}
		}
	}
my $phd = &public_html_dir($d);
my $before = &before_letsencrypt_website($d);
my @beforecerts = &get_all_domain_service_ssl_certs($d);
my $acme;
if ($tmpl->{'web_acme'} && defined(&list_acme_providers)) {
	($acme) = grep { $_->{'id'} eq $tmpl->{'web_acme'} }
		       &list_acme_providers();
	}
$d->{'letsencrypt_id'} = $acme->{'id'} if ($acme);
my @leargs = ($d, \@dnames, undef, undef, undef, undef, $acme,
	      $d->{'letsencrypt_subset'});
my ($ok, $cert, $key, $chain) =
	&request_domain_letsencrypt_cert(@leargs);
if ($ok) {
	$d->{'letsencrypt_nodnscheck'} = 1;
	}
else {
	# Try again with just externally resolvable hostnames
	my @badnames;
	my $fok = &filter_external_dns(\@dnames, \@badnames);
	if ($fok == 0 && @dnames) {
		$d->{'letsencrypt_nodnscheck'} = 0;
		($ok, $cert, $key, $chain) =
			&request_domain_letsencrypt_cert(@leargs);
		}
	}
&after_letsencrypt_website($d, $before);
if (!$ok) {
	# Always store last Certbot error
	$d->{'letsencrypt_last_failure'} = time();
	$d->{'letsencrypt_last_err'} = $cert;
	$d->{'letsencrypt_last_err'} =~ s/\r?\n/\t/g;
	if ($showerrors) {
		&$second_print(&text('letsencrypt_failed', $cert));
		}
	else {
		&$second_print($text{'letsencrypt_doing3failed'});
		}
	return 0;
	}
else {
	&obtain_lock_ssl($d);
	&install_letsencrypt_cert($d, $cert, $key, $chain);

	$d->{'letsencrypt_dname'} = '';
	$d->{'letsencrypt_dwild'} = 0;
	$d->{'letsencrypt_last'} = time();
	$d->{'letsencrypt_renew'} = 1 if ($d->{'letsencrypt_renew'} eq '');
	$d->{'letsencrypt_last_id'} = $d->{'letsencrypt_id'};

	# Inject initial SSL expiry to avoid wrong "until expiry"
	&refresh_ssl_cert_expiry($d);
	&lock_domain($d);
	&save_domain($d);
	&unlock_domain($d);

	# Update other services using the cert
	&update_all_domain_service_ssl_certs($d, \@beforecerts);

	&break_invalid_ssl_linkages($d);
	&sync_domain_tlsa_records($d);
	&release_lock_ssl($d);
	&$second_print(&text('letsencrypt_doing3ok',
			     join(", ", map { "<tt>$_</tt>" } @dnames)));
	return 1;
	}
}

# call_feature_setup(feature, &domain, [args])
# Calls the setup function for some feature or plugin. May print stuff.
# Returns an error message on a vital feature failure, sets flag to 0 for
# a non-vital failure.
sub call_feature_setup
{
local ($f, $dom, @args) = @_;
local %vital = map { $_, 1 } @vital_features;
if (&indexof($f, @features) >= 0) {
	# Core feature
	local $sfunc = "setup_$f";
	if ($vital{$f}) {
		# Failure of this feature should halt the entire setup
		if (!&$sfunc($dom, @args)) {
			return &text('setup_evital',
				     $text{'feature_'.$f});
			}
		}
	else {
		# Failure can be ignored
		local ($ok, $fok) = &try_function($f, $sfunc, $dom);
		if (!$ok || !$fok) {
			$dom->{$f} = 0;
			}
		}
	}
else {
	# Plugin feature
	local $main::error_must_die = 1;
	eval { &plugin_call($f, "feature_setup", $dom, @args) };
	if ($@) {
		local $err = $@;
		&$second_print(&text('setup_failure',
			&plugin_call($f, "feature_name"), $err));
		$dom->{$f} = 0;
		}
	}
return undef;
}

# delete_virtual_server(&domain, only-disconnect, no-post, preserve-remote)
# Deletes a Virtualmin domain and all sub-domains and aliases. Returns undef
# on succes, or an error message on failure.
sub delete_virtual_server
{
local ($d, $only, $nopost, $preserve) = @_;

# Get domain details
local @subs = &get_domain_by("parent", $d->{'id'});
local @aliasdoms = &get_domain_by("alias", $d->{'id'});
local @aliasdoms = grep { $_->{'parent'} ne $d->{'id'} } @aliasdoms;
local @alldoms = (@aliasdoms, @subs, $d);

# Check for DNS dependencies
foreach my $dd (@alldoms) {
	foreach my $du (&get_domain_by("dns_subof", $dd->{'id'})) {
		if (&indexof($du, @alldoms) < 0) {
			# Domain is being used as a DNS parent, and user isn't
			# being deleted
			return &text('delete_ednssubof', &show_domain_name($dd),
				     &show_domain_name($du));
			}
		}
	}

# Lock before deleting
foreach my $dd (@alldoms) {
	&lock_domain($dd);
	}

# Delete any jail
if (!&check_jailkit_support() && !$d->{'parent'}) {
	&disable_domain_jailkit($d, 1);
	}

# Go ahead and delete this domain and all sub-domains ..
&obtain_lock_mail();
&obtain_lock_unix();
foreach my $dd (@alldoms) {
	if ($dd ne $d) {
		# Show domain name
		&$first_print(&text('delete_dom', &show_domain_name($dd)));
		&$indent_print();
		}

	# What is shared for this domain?
	my %remote;
	if ($preserve) {
		%remote = map { $_, 1 } &list_remote_domain_features($dd);
		}

	# Run the before command
	&set_domain_envs($dd, "DELETE_DOMAIN");
	local $merr = &making_changes();
	&reset_domain_envs($dd);
	return &text('delete_emaking', "<tt>$merr</tt>")
		if (defined($merr));

	if (!$only) {
		local @users = $dd->{'alias'} && !$dd->{'aliasmail'} ||
			       !$dd->{'group'} ? ( )
					       : &list_domain_users($dd, 1, 0, 0, 0, 1);
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
				if (!$u->{'nomailfile'} && !$remote{'dir'}) {
					&delete_mail_file($u);
					}
				$u->{'dbs'} = [ grep { !$remote{$_->{'type'}} }
						     @{$u->{'dbs'}} ];
				&delete_user($u, $dd);
				if (!$u->{'nocreatehome'} && !$remote{'dir'}) {
					&delete_user_home($u, $d);
					}
				}
			&$second_print($text{'setup_done'});
			}

                # Delete all virtusers
		if (!$dd->{'aliascopy'} && !$remote{'mail'}) {
			&$first_print($text{'delete_aliases'});
			foreach my $v (&list_virtusers()) {
				if ($v->{'from'} =~ /\@(\S+)$/ &&
				    $1 eq $dd->{'dom'}) {
					&delete_virtuser($v);
					}
				}
			&sync_alias_virtuals($dd);
			&$second_print($text{'setup_done'});
			}

		# Take down IP
		if ($dd->{'virt'}) {
			&try_function("virt", "delete_virt", $dd);
			}
		if ($dd->{'virt6'}) {
			&try_function("virt6", "delete_virt6", $dd);
			}
		}

	if (!$dd->{'parent'}) {
		# Delete any extra admins
		foreach my $admin (&list_extra_admins($dd)) {
			&delete_extra_admin($admin);
			}
		}

	# If this is an alias domain, notify the target that it is being
	# deleted. This allows things like extra awstats symlinks to be removed
	$dd->{'deleting'} = 1;		# so that features know about delete
	if (!$only && $dd->{'alias'}) {
		local $aliasdom = &get_domain($dd->{'alias'});
		foreach my $f (@features) {
			local $dafunc = "delete_alias_$f";
			if ($aliasdom->{$f} && defined(&$dafunc)) {
				&try_function($f, $dafunc, $aliasdom, $dd);
				}
			}
		foreach $f (&list_feature_plugins()) {
			if ($aliasdom->{$f} &&
			    &plugin_defined($f, "feature_delete_alias")) {
				local $main::error_must_die = 1;
				eval { &plugin_call($f, "feature_delete_alias",
						    $aliasdom, $dd) };
				if ($@) {
					&$second_print(
					  &text('delete_aliasfailure',
					  &plugin_call($f, "feature_name"),
					  "$@"));
					}
				}
			}
		}

	# Remove SSL cert from Dovecot, Postfix, etc
	&disable_domain_service_ssl_certs($dd);

	# If this domain had it's own lets encrypt cert, delete any leftover
	# files for it under /etc/letsencrypt
	&foreign_require("webmin");
	if ($dd->{'letsencrypt_last'} && !$dd->{'ssl_same'} &&
	    defined(&webmin::cleanup_letsencrypt_files)) {
		&webmin::cleanup_letsencrypt_files($dd->{'dom'});
		}

	# Delete all features (or just 'webmin' if un-importing). Any
	# failures are ignored!
	my $f;
	local $p = &domain_has_website($dd);
	local @of;
	if ($only) {
		@of = ( "webmin" );
		}
	else {
		@of = reverse(&list_ordered_features($dd, 1));
		}
	foreach $f (@of) {
		if (($config{$f} || &indexof($f, @plugins) >= 0) &&
		    $dd->{$f} || $f eq 'unix') {
			# Delete core feature
			local @args = ( $preserve );
			if ($f eq "mail") {
				# Don't delete mail aliases, because we have
				# already done so above
				push(@args, 1);
				}
			&call_feature_delete($f, $dd, @args);
			}
		if (&indexof($f, @plugins) >= 0) {
			&plugin_call($f, "feature_always_delete", $dd);
			}
		}

	# Delete any FPM or FCGIwrap servers, just in case they
	# were disassociated
	&delete_php_fpm_pool($d);
	if ($d->{'fcgiwrap_port'}) {
		&delete_fcgiwrap_server($d);
		}

	# Delete SSL key files outside the home dir
	if (!$dd->{'ssl_same'}) {
		foreach my $k ('ssl_cert', 'ssl_key', 'ssl_chain',
			       'ssl_combined', 'ssl_everything') {
			if ($dd->{$k} &&
			    !&is_under_directory($dd->{'home'}, $dd->{$k}) &&
			    -f $dd->{$k}) {
				&unlink_logged($dd->{$k});
				}
			}
		foreach my $dir (&ssl_certificate_directories($dd, 1)) {
			if (!&is_under_directory($dd->{'home'}, $dir) &&
			    -d $dir &&
			    $dir =~ /\/[^\/]*(\Q$dd->{'dom'}\E|\Q$dd->{'id'}\E)[^\/]*$/ &&
			    &is_empty_directory($dir)) {
				&unlink_logged($dir);
				}
			}
		}

	# Delete domain file
	&$first_print(&text('delete_domain', &show_domain_name($dd)));
	&delete_domain($dd);
	&$second_print($text{'setup_done'});

	# Update the parent domain Webmin user, so that his ACL
	# is refreshed (and any resellers)
	&refresh_webmin_user($dd);

	# Call post script
	&set_domain_envs($dd, "DELETE_DOMAIN");
	local $merr = &made_changes();
	&reset_domain_envs($dd);
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));

	if ($dd ne $d) {
		&$outdent_print();
		&$second_print($text{'setup_done'});
		}
	}
&release_lock_mail();
&release_lock_unix();

# If deleted domain was default host name
if ($d->{'dom'} eq $config{'defaultdomain_name'}) {
	&lock_file($module_config_file);
	delete($config{'defaultdomain_name'});
	$config{'default_domain_ssl'} = 0;
	&save_module_config();
	&unlock_file($module_config_file);
	}

# Run the after deletion command
if (!$nopost) {
	&run_post_actions();
	}

# Unlock now we're done
foreach my $dd (reverse(@alldoms)) {
	&unlock_domain($dd);
	}

return undef;
}

# call_feature_delete(feature, &domain, arg, arg, ...)
# Calls the core or plugin-specific function to delete a feature. May print
# stuff.
sub call_feature_delete
{
local ($f, $dom, @args) = @_;
if (&indexof($f, @features) >= 0) {
	# Call core delete function
	local $dfunc = "delete_$f";
	local ($ok, $fok) = &try_function($f, $dfunc, $dom, @args);
	if (!$ok || !$fok) {
		$dom->{$f} = 1;
		}
	}
else {
	# Call plugin delete function
	local $main::error_must_die = 1;
	eval { &plugin_call($f, "feature_delete", $dom, @args) };
	if ($@) {
		local $err = $@;
		&$second_print(&text('delete_failure',
			    &plugin_call($f, "feature_name"), $err));
		}
	}
}

# disable_scheduled_virtual_servers()
# Disables all scheduled virtual servers that are due to be disabled
sub disable_scheduled_virtual_servers
{
my @disdoms = grep {
	!$_->{'protected'} &&                   # if domain is not protected
	!$_->{'disabled'} &&                    # if not already disabled
	&is_timestamp($_->{'disabled_auto'}) && # if actually a timestamp
	$_->{'disabled_auto'} <= time()         # if timestamp is in the past
	} &list_domains();
foreach my $d (@disdoms) {
	&push_all_print();
	&set_all_null_print();
	eval {
		local $main::error_must_die = 1;
		my $disabled_auto = &make_date($d->{'disabled_auto'});
		&disable_virtual_server($d, 'schedule',
			&text('disable_autodisabledone', $disabled_auto));
		};
	&pop_all_print();
	&error_stderr_local("Disabling domain on schedule failed : $@") if ($@);
	}
}

# disable_virtual_server(&domain, [reason-code], [reason-why], [&only-features])
# Disables all features of one virtual server. Returns undef on success, or
# an error message on failure.
sub disable_virtual_server
{
my ($d, $reason, $why, $only) = @_;

# Work out what can be disabled
my @disable = &get_disable_features($d);
if ($only) {
	@disable = grep { &indexof($_, @$only) >= 0 } @disable;
	@disable || return "None of the features to disable exist on this ".
			   "virtual server";
	}

# Disable it
my %disable = map { $_, 1 } @disable;
$d->{'disabled_reason'} = $reason;
$d->{'disabled_why'} = $why;
$d->{'disabled_time'} = time();
delete($d->{'disabled_auto'});

# Run the before command
&set_domain_envs($d, "DISABLE_DOMAIN");
my $merr = &making_changes();
&reset_domain_envs($d);
return &text('disable_emaking', "<tt>".&html_escape($merr)."</tt>")
	if (defined($merr));

# Disable all configured features
my @disabled;
foreach my $f (@features) {
	if ($d->{$f} && $disable{$f}) {
		my $dfunc = "disable_$f";
		local ($ok, $fok) = &try_function($f, $dfunc, $d);
		if ($ok && $fok) {
			push(@disabled, $f);
			}
		}
	}
foreach my $f (&list_feature_plugins()) {
	if ($d->{$f} && $disable{$f}) {
		&plugin_call($f, "feature_disable", $d);
		push(@disabled, $f);
		}
	}

# Disable extra admins
&update_extra_webmin($d, 1);

# Save new domain details
&$first_print($text{'save_domain'});
&lock_domain($d);
$d->{'disabled'} = join(",", @disabled);
&save_domain($d);
&unlock_domain($d);
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "DISABLE_DOMAIN");
my $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
	if (defined($merr));
&reset_domain_envs($d);

return undef;
}

# enable_virtual_server(&domain)
# Enables all disabled features of one virtual server. Returns undef on
# success, or an error message on failure.
sub enable_virtual_server
{
my ($d) = @_;

# Work out what can be enabled
my @enable = &get_enable_features($d);

# Go ahead and do it
my %enable = map { $_, 1 } @enable;
delete($d->{'disabled_reason'});
delete($d->{'disabled_why'});
delete($d->{'disabled_auto'});

# Run the before command
&set_domain_envs($d, "ENABLE_DOMAIN");
my $merr = &making_changes();
&reset_domain_envs($d);
return &text('enable_emaking', "<tt>$merr</tt>") if (defined($merr));

# Enable all disabled features
foreach my $f (@features) {
	if ($d->{$f} && $enable{$f}) {
		my $efunc = "enable_$f";
		&try_function($f, $efunc, $d);
		}
	}
foreach my $f (&list_feature_plugins()) {
	if ($d->{$f} && $enable{$f}) {
		&plugin_call($f, "feature_enable", $d);
		}
	}

# Enable extra admins
&update_extra_webmin($d, 0);

# Save new domain details
&$first_print($text{'save_domain'});
&lock_domain($d);
delete($d->{'disabled'});
&save_domain($d);
&unlock_domain($d);
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "ENABLE_DOMAIN");
my $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>".&html_escape($merr)."</tt>"))
	if (defined($merr));
&reset_domain_envs($d);

return undef;
}

# register_post_action(&function, args)
sub register_post_action
{
push(@main::post_actions, [ @_ ]);
}

# run_post_actions([&only-action])
# Run all registered post-modification actions
sub run_post_actions
{
local @only = @_;
local %only = map { $_, 1 } @only;
local $a;

# Check if we are restarting Apache or Webmin, and if so don't reload it
my ($apache, $webmin);
foreach $a (@main::post_actions) {
	if ($a->[0] eq \&restart_apache) {
		$a->[1] ||= 0;
		$apache = 1 if ($a->[1] == 1);
		}
	if ($a->[0] eq \&restart_webmin_fully) {
		$webmin = 1;
		}
	}
if ($apache) {
	@main::post_actions = grep { $_->[0] ne \&restart_apache ||
				     $_->[1] != 0 } @main::post_actions;
	}
if ($webmin) {
	@main::post_actions = grep { $_->[0] ne \&restart_webmin }
				   @main::post_actions;
	}

# Run unique actions
local %done;
local @newpost;
foreach my $a (@main::post_actions) {
	# Don't run multiple times
	my $key;
	if ($a->[0] eq \&restart_bind && $a->[1]) {
		# Restarts for the same DNS server are equal
		my $p = $a->[1]->{'provision_dns'} || $a->[1]->{'dns_cloud'};
		$key = $a->[0].",".$p;
		}
	elsif ($a->[0] eq \&update_secondary_mx_virtusers) {
		# Restarts in the same domain are considered equal
		$key = $a->[0].($a->[1] ? ",".$a->[1]->{'dom'} : "");
		}
	elsif ($a->[0] eq \&restart_php_fpm_server) {
		# Restarts of the same FPM version are equal
		$key = $a->[0].($a->[1] ? ",".$a->[1]->{'init'} : "");
		}
	else {
		$key = join(",", @$a);
		}
	next if ($done{$key}++);

	# Skip if the caller requested specific actions
	local ($afunc, @aargs) = @$a;
	if (@only && !$only{$afunc}) {
		push(@newpost, $a);
		next;
		}

	# Call the restart function
	local $main::error_must_die = 1;
	eval { &$afunc(@aargs) };
	if ($@) {
		&$second_print(&text('setup_postfailure', "$@"));
		}
	}
@main::post_actions = @newpost;
}

# run_post_actions_silently()
# Just calls run_post_actions while supressing output
sub run_post_actions_silently
{
&push_all_print();
&set_all_null_print();
&run_post_actions();
&pop_all_print();
}

# find_bandwidth_job()
# Returns the cron job used for bandwidth monitoring
sub find_bandwidth_job
{
local $job = &find_cron_script($bw_cron_cmd);
return $job;
}

# get_bandwidth(&domain)
# Returns the bandwidth usage object for some domain
sub get_bandwidth
{
my ($d) = @_;
if (!defined($get_bandwidth_cache{$d->{'id'}})) {
	local %bwinfo;
	&read_file("$bandwidth_dir/$d->{'id'}", \%bwinfo);
	foreach my $k (keys %bwinfo) {
		if ($k =~ /^\d+$/) {
			# Convert old web entries
			$bwinfo{"web_$k"} = $bwinfo{$k};
			delete($bwinfo{$k});
			}
		}
	$get_bandwidth_cache{$d->{'id'}} = \%bwinfo;
	}
return $get_bandwidth_cache{$d->{'id'}};
}

# save_bandwidth(&domain, &info)
# Update the bandwidth usage object for some domain
sub save_bandwidth
{
my ($d, $info) = @_;
&make_dir($bandwidth_dir, 0700);
&write_file("$bandwidth_dir/$d->{'id'}", $info);
$get_bandwidth_cache{$d->{'id'}} ||= $info;
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
my $unit = 1024;
if ($value eq "") {
	# Default to GB, since bytes are rarely useful
	$u = $text{"nice_size_GiB"};
	}
elsif ($value && $value%($unit*$unit*$unit*$unit) == 0) {
	$val = $value/($unit*$unit*$unit*$unit);
	$u = $text{"nice_size_TiB"};
	}
elsif ($value && $value%($unit*$unit*$unit) == 0) {
	$val = $value/($unit*$unit*$unit);
	$u = $text{"nice_size_GiB"};
	}
elsif ($value && $value%($unit*$unit) == 0) {
	$val = $value/($unit*$unit);
	$u = $text{"nice_size_MiB"};
	}
elsif ($value && $value%($unit) == 0) {
	$val = $value/($unit);
	$u = $text{"nice_size_kiB"};
	}
else {
	$val = $value;
	$u = $text{"nice_size_b"};
	}
local $sel = &ui_select($name."_units", $u,
		[ [$text{"nice_size_b"}], [$text{"nice_size_kiB"}], [$text{"nice_size_MiB"}], [$text{"nice_size_GiB"}], [$text{"nice_size_TiB"}] ], 1, 0, 0, $dis);
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
	my $unit = 1024;
	$in{$_[0]} =~ /^\d+$/ && $in{$_[0]} > 0 || &error($_[1]);
	local $m = $in{"$_[0]_units"} eq $text{"nice_size_TiB"} ? $unit*$unit*$unit*$unit :
		   $in{"$_[0]_units"} eq $text{"nice_size_GiB"} ? $unit*$unit*$unit :
		   $in{"$_[0]_units"} eq $text{"nice_size_MiB"} ? $unit*$unit :
		   $in{"$_[0]_units"} eq $text{"nice_size_kiB"} ? $unit : 1;
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
if (defined($mailbox)) {
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
my ($escuser) = @_;
my $origuser = $escuser;
$escuser =~ s/\@/-/g;
if (!getpwnam($escuser)) {
	$escuser = &escape_user($origuser);
	}
return $escuser;
}

# replace_atsign(username)
# Replace an @ in a username with -
sub replace_atsign
{
my ($user) = @_;
$user =~ s/\@/-/g;
return $user;
}

# replace_atsign_if_exists(username)
# Replace an @ in a username with -
# if a user exists in system
sub replace_atsign_if_exists
{
my ($user) = @_;
my $origuser = $user;
$user =~ s/\@/-/g;
$user = $origuser if (!getpwnam($user));
return $user;
}


# escape_replace_atsign_if_exists(username)
# Replace an @ in a username with - if a
# user exists in system and if not return
# escaped @ user
sub escape_replace_atsign_if_exists
{
my ($user) = @_;
my $origuser = $user;
$user =~ s/\@/-/g;
$user = &escape_user($origuser)
	if (!getpwnam($user));
return $user;
}

# add_atsign(username)
# Given a username like foo-bar.com, return foo@bar.com
sub add_atsign
{
local ($rv) = @_;
$rv =~ s/\-/\@/;
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
open(AFILE, "<".$_[0]) || return undef;
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
if (scalar(@list_templates_cache)) {
	# Use cached copy
	return @list_templates_cache;
	}
local @rv;
&ensure_template("domain-template");
&ensure_template("subdomain-template");
&ensure_template("framefwd-template");
&ensure_template("user-template");
push(@rv, { 'id' => 0,
	    'name' => $text{'newtmpl_name0'},
	    'standard' => 1,
	    'default' => 1,
	    'web' => $config{'apache_config'},
	    'web_ssl' => $config{'apache_ssl_config'},
	    'web_user' => $config{'web_user'},
	    'web_fcgiwrap' => $config{'fcgiwrap'},
	    'web_cgimode' => $config{'cgimode'},
	    'web_html_dir' => $config{'html_dir'},
	    'web_html_perms' => $config{'html_perms'} || 750,
	    'web_stats_dir' => $config{'stats_dir'},
	    'web_stats_hdir' => $config{'stats_hdir'},
	    'web_stats_pass' => $config{'stats_pass'},
	    'web_stats_noedit' => $config{'stats_noedit'},
	    'web_port' => $default_web_port,
	    'web_sslport' => $default_web_sslport,
	    'web_urlport' => $config{'web_urlport'},
	    'web_urlsslport' => $config{'web_urlsslport'},
	    'web_sslprotos' => $config{'web_sslprotos'},
	    'web_alias' => $config{'alias_mode'},
	    'web_acme' => $config{'web_acme'},
	    'web_webmin_ssl' => $config{'webmin_ssl'},
	    'web_usermin_ssl' => $config{'usermin_ssl'},
	    'web_webmail' => $config{'web_webmail'},
	    'web_webmaildom' => $config{'web_webmaildom'},
	    'web_admin' => $config{'web_admin'},
	    'web_admindom' => $config{'web_admindom'},
	    'php_vars' => $config{'php_vars'} || "none",
	    'php_fpm' => $config{'php_fpm'} || "none",
	    'php_sock' => $config{'php_sock'} || 0,
	    'php_log' => $config{'php_log'} || 0,
	    'php_log_path' => $config{'php_log_path'},
	    'web_php_suexec' => int($config{'php_suexec'}),
	    'web_ruby_suexec' => $config{'ruby_suexec'} eq '' ? -1 :
					int($config{'ruby_suexec'}),
	    'web_phpver' => $config{'phpver'},
	    'web_php_noedit' => int($config{'php_noedit'}),
	    'web_phpchildren' => $config{'phpchildren'},
	    'web_ssi' => $config{'web_ssi'} eq '' ? 2 : $config{'web_ssi'},
	    'web_ssi_suffix' => $config{'web_ssi_suffix'},
	    'web_dovecot_ssl' => $config{'dovecot_ssl'},
	    'web_postfix_ssl' => $config{'postfix_ssl'},
	    'web_mysql_ssl' => $config{'mysql_ssl'},
	    'web_proftpd_ssl' => $config{'proftpd_ssl'},
	    'web_http2' => $config{'web_http2'},
	    'web_redirects' => $config{'web_redirects'},
	    'web_sslredirect' => $config{'auto_redirect'},
	    'ssl_key_size' => $config{'key_size'},
	    'ssl_cert_type' => $config{'cert_type'},
	    'ssl_auto_letsencrypt' => $config{'auto_letsencrypt'},
	    'ssl_letsencrypt_wild' => $config{'letsencrypt_wild'},
	    'ssl_renew_letsencrypt' => $config{'renew_letsencrypt'},
	    'ssl_always_ssl' => $config{'always_ssl'},
	    'ssl_tlsa_records' => $config{'tlsa_records'},
	    'ssl_combined_cert' => $config{'combined_cert'},
	    'ssl_allow_subset' => $config{'allow_subset'},
	    'webalizer' => $config{'def_webalizer'} || "none",
	    'content_web' => $config{'content_web'} // 2,
	    'content_web_html' => $config{'content_web_html'},
	    'disabled_web' => $config{'disabled_web'} || "none",
	    'disabled_url' => $config{'disabled_url'} || "none",
	    'dns' => $config{'bind_config'} || "none",
	    'dns_replace' => $config{'bind_replace'},
	    'dns_view' => $config{'dns_view'},
	    'dns_spf' => $config{'bind_spf'} || "none",
	    'dns_spfhosts' => $config{'bind_spfhosts'},
	    'dns_spfonly' => $config{'bind_spfonly'},
	    'dns_spfincludes' => $config{'bind_spfincludes'},
	    'dns_spfall' => $config{'bind_spfall'},
	    'dns_dmarc' => $config{'bind_dmarc'} || "none",
	    'dns_dmarcp' => $config{'bind_dmarcp'} || "none",
	    'dns_dmarcpct' => $config{'bind_dmarcpct'} || 100,
	    'dns_dmarcruf' => $config{'bind_dmarcruf'},
	    'dns_dmarcrua' => $config{'bind_dmarcrua'},
	    'dns_dmarcextra' => $config{'bind_dmarcextra'},
	    'dns_sub' => $config{'bind_sub'} || "none",
	    'dns_alias' => $config{'bind_alias'} || "none",
	    'dns_cloud' => $config{'bind_cloud'},
	    'dns_cloud_import' => $config{'bind_cloud_import'},
	    'dns_cloud_proxy' => $config{'bind_cloud_proxy'},
	    'dns_slaves' => $config{'bind_slaves'},
	    'dns_master' => $config{'bind_master'} || "none",
	    'dns_mx' => $config{'bind_mx'} || "none",
	    'dns_ns' => $config{'dns_ns'},
	    'dns_prins' => $config{'dns_prins'},
	    'dns_records' => $config{'dns_records'},
	    'dns_ttl' => $config{'dns_ttl'},
	    'dns_indom' => $config{'bind_indom'},
	    'dnssec' => $config{'dnssec'} || "none",
	    'dnssec_alg' => $config{'dnssec_alg'},
	    'dnssec_single' => $config{'dnssec_single'},
	    'namedconf' => $config{'namedconf'} || "none",
	    'namedconf_no_allow_transfer' =>
		$config{'namedconf_no_allow_transfer'},
	    'namedconf_no_also_notify' =>
		$config{'namedconf_no_also_notify'},
	    'ftp' => $config{'proftpd_config'},
	    'ftp_dir' => $config{'ftp_dir'},
	    'logrotate' => $config{'logrotate_config'} || "none",
	    'logrotate_files' => $config{'logrotate_files'} || "none",
	    'logrotate_shared' => $config{'logrotate_shared'} || "no",
	    'status' => $config{'statusemail'} || "none",
	    'statusonly' => int($config{'statusonly'}),
	    'statustimeout' => $config{'statustimeout'},
	    'statustmpl' => $config{'statustmpl'},
	    'statussslcert' => $config{'statussslcert'},
	    'mail_on' => $config{'domain_template'} eq "none" ? "none" : "yes",
	    'mail' => $config{'domain_template'} eq "none" ||
		      $config{'domain_template'} eq "" ||
		      $config{'domain_template'} eq "default" ?
				&cat_file("domain-template") :
				&cat_file($config{'domain_template'}),
	    'mail_subject' => $config{'newdom_subject'} ||
			      &entities_to_ascii($text{'mail_dsubject'}),
	    'mail_cc' => $config{'newdom_cc'},
	    'mail_bcc' => $config{'newdom_bcc'},
	    'mail_cloud' => $config{'mail_cloud'},
	    'mail_mta_sts' => $config{'mail_mta_sts'},
	    'newuser_on' => $config{'user_template'} eq "none" ? "none" : "yes",
	    'newuser' => $config{'user_template'} eq "none" ||
		         $config{'user_template'} eq "" ||
		         $config{'user_template'} eq "default" ?
				&cat_file("user-template") :
				&cat_file($config{'user_template'}),
	    'newuser_subject' => $config{'newuser_subject'} ||
			         &entities_to_ascii($text{'mail_usubject'}),
	    'newuser_cc' => $config{'newuser_cc'},
	    'newuser_bcc' => $config{'newuser_bcc'},
	    'newuser_to_mailbox' => $config{'newuser_to_mailbox'} || 0,
	    'newuser_to_owner' => $config{'newuser_to_owner'} || 0,
	    'newuser_to_reseller' => $config{'newuser_to_reseller'} || 0,
	    'updateuser_on' => $config{'update_template'} eq "none" ?
				"none" : "yes",
	    'updateuser' => $config{'update_template'} eq "none" ||
			    $config{'update_template'} eq "" ||
			    $config{'update_template'} eq "default" ?
				&cat_file("update-template") :
				&cat_file($config{'update_template'}),
	    'updateuser_subject' => $config{'newupdate_subject'} ||
			         &entities_to_ascii($text{'mail_upsubject'}),
	    'updateuser_cc' => $config{'newupdate_cc'},
	    'updateuser_bcc' => $config{'newupdate_bcc'},
	    'updateuser_to_mailbox' => $config{'newupdate_to_mailbox'} || 0,
	    'updateuser_to_owner' => $config{'newupdate_to_owner'} || 0,
	    'updateuser_to_reseller' => $config{'newupdate_to_reseller'} || 0,
	    'aliascopy' => $config{'aliascopy'} || 0,
	    'bccto' => $config{'bccto'} || 'none',
	    'spamclear' => $config{'spamclear'} || 'none',
	    'trashclear' => $config{'trashclear'} || 'none',
	    'spamtrap' => $config{'spamtrap'} || 'none',
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
	    'mysql_nouser' => $config{'mysql_nouser'},
	    'mysql_chgrp' => $config{'mysql_chgrp'},
	    'mysql_charset' => $config{'mysql_charset'},
	    'mysql_collate' => $config{'mysql_collate'},
	    'mysql_conns' => $config{'mysql_conns'} || "none",
	    'mysql_uconns' => $config{'mysql_uconns'} || "none",
	    'postgres_encoding' => $config{'postgres_encoding'} || "none",
	    'skel' => $config{'virtual_skel'} || "none",
	    'skel_subs' => int($config{'virtual_skel_subs'}),
	    'skel_nosubs' => $config{'virtual_skel_nosubs'},
	    'exclude' => $config{'default_exclude'} || "none",
	    'frame' => &cat_file("framefwd-template", 1),
	    'gacl' => 1,
	    'gacl_umode' => $config{'gacl_umode'},
	    'gacl_uusers' => $config{'gacl_uusers'},
	    'gacl_ugroups' => $config{'gacl_ugroups'},
	    'gacl_groups' => $config{'gacl_groups'},
	    'gacl_root' => $config{'gacl_root'},
	    'webmin_group' => $config{'webmin_group'},
	    'extra_prefix' => $config{'extra_prefix'} || "none",
	    'ugroup' => $config{'defugroup'} || "none",
	    'sgroup' => $config{'domains_group'} || "none",
	    'quota' => $config{'defquota'} || "none",
	    'uquota' => $config{'defuquota'} || "none",
	    'ushell' => $config{'defushell'} || "none",
	    'ujail' => $config{'defujail'},
	    'mailboxlimit' => $config{'defmailboxlimit'} eq "" ? "none" :
			      $config{'defmailboxlimit'},
	    'aliaslimit' => $config{'defaliaslimit'} eq "" ? "none" :
			    $config{'defaliaslimit'},
	    'dbslimit' => $config{'defdbslimit'} eq "" ? "none" :
			  $config{'defdbslimit'},
	    'domslimit' => $config{'defdomslimit'} eq "" ? 0 :
			   $config{'defdomslimit'} eq "*" ? "none" :
			   $config{'defdomslimit'},
	    'aliasdomslimit' => $config{'defaliasdomslimit'} eq "" ||
			        $config{'defaliasdomslimit'} eq "*" ? "none" :
			        $config{'defaliasdomslimit'},
	    'realdomslimit' => $config{'defrealdomslimit'} eq "" ||
			       $config{'defrealdomslimit'} eq "*" ? "none" :
			       $config{'defrealdomslimit'},
	    'bwlimit' => $config{'defbwlimit'} eq "" ? "none" :
			 $config{'defbwlimit'},
	    'mongrelslimit' => $config{'defmongrelslimit'} eq "" ? "none" :
			       $config{'defmongrelslimit'},
	    'capabilities' => $config{'defcapabilities'} || "none",
	    'featurelimits' => $config{'featurelimits'} || "none",
	    'nodbname' => $config{'defnodbname'},
	    'norename' => $config{'defnorename'},
	    'forceunder' => $config{'defforceunder'},
	    'safeunder' => $config{'defsafeunder'},
	    'ipfollow' => $config{'defipfollow'},
	    'resources' => $config{'defresources'} || "none",
	    'ranges' => $config{'ip_ranges'} || "none",
	    'ranges6' => $config{'ip_ranges6'} || "none",
	    'mailgroup' => $config{'mailgroup'} || "none",
	    'ftpgroup' => $config{'ftpgroup'} || "none",
	    'dbgroup' => $config{'dbgroup'} || "none",
	    'othergroups' => $config{'othergroups'} || "none",
	    'quotatype' => $config{'hard_quotas'} ? "hard" : "soft",
	    'hashpass' => $config{'hashpass'} || 0,
	    'hashtypes' => $config{'hashtypes'},
	    'append_style' => $config{'append_style'},
	    'domalias' => $config{'domalias'} || "none",
	    'domalias_type' => $config{'domalias_type'} || 0,
	    'domauto_disable' => $config{'domauto_disable'},
	    'for_parent' => 1,
	    'for_sub' => 0,
	    'for_alias' => 1,
	    'for_users' => !$config{'deftmpl_nousers'},
	    'resellers' => !defined($config{'tmpl_resellers'}) ? "*" :
				$config{'tmpl_resellers'},
	    'owners' => !defined($config{'tmpl_owners'}) ? "*" :
				$config{'tmpl_owners'},
	    'autoconfig' => $config{'tmpl_autoconfig'} || "none",
	    'outlook_autoconfig' => $config{'tmpl_outlook_autoconfig'} || "none",
	    'cert_key_tmpl' => $config{'key_tmpl'},
	    'cert_cert_tmpl' => $config{'cert_tmpl'},
	    'cert_ca_tmpl' => $config{'ca_tmpl'},
	    'cert_combined_tmpl' => $config{'combined_tmpl'},
	    'cert_everything_tmpl' => $config{'everything_tmpl'},
	  } );
foreach my $w (&list_php_wrapper_templates()) {
	$rv[0]->{$w} = $config{$w} || 'none';
	}
foreach my $phpver (@all_possible_php_versions) {
        $rv[0]->{'web_php_ini_'.$phpver} =
		defined($config{'php_ini_'.$phpver}) ?
			$config{'php_ini_'.$phpver} : $config{'php_ini'},
	}
if (!defined(getpwnam($rv[0]->{'web_user'})) &&
    $rv[0]->{'web_user'} ne 'none' &&
    $rv[0]->{'web_user'} ne '') {
	# Apache user is invalid, due to bad Virtualmin install script. Fix it
	$rv[0]->{'web_user'} = &get_apache_user();
	}
my @avail;
foreach my $m (&list_domain_owner_modules()) {
	push(@avail, $m->[0]."=".$config{'avail_'.$m->[0]});
	}
$rv[0]->{'avail'} = join(' ', @avail);
push(@rv, { 'id' => 1,
	    'name' => $text{'newtmpl_name1'},
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
	  } );
local $f;
opendir(DIR, $templates_dir);
while(defined($f = readdir(DIR))) {
	if ($f ne "." && $f ne "..") {
		local %tmpl;
		&read_file("$templates_dir/$f", \%tmpl);
		$tmpl{'file'} = "$templates_dir/$f";
		$tmpl{'mail'} =~ s/\t/\n/g;
		$tmpl{'newuser'} =~ s/\t/\n/g;
		$tmpl{'updateuser'} =~ s/\t/\n/g;
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
foreach my $tmpl (@rv) {
	$tmpl->{'resellers'} = '*' if (!defined($tmpl->{'resellers'}));
	$tmpl->{'owners'} = '*' if (!defined($tmpl->{'owners'}));
	if (!defined($tmpl->{'web_cgimode'})) {
		# Switch from the old CGI mode field to the new one
		my @cgimodes = &has_cgi_support();
		$tmpl->{'web_cgimode'} = $tmpl->{'web_fcgiwrap'} ? 'fcgiwrap' :
					 @cgimodes ? $cgimodes[0] : 'none';
		delete($tmpl->{'web_fcgiwrap'});
		}
	}
closedir(DIR);

my @default_templates = grep { $_->{'default'} } @rv;
my @non_default_templates = grep { !$_->{'default'} } @rv;
my @sorted_templates = sort { $a->{'name'} cmp $b->{'name'} } @non_default_templates;
@list_templates_cache = (@default_templates, @sorted_templates);

return @list_templates_cache;
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
	if ($tmpl->{'resellers'} eq '*') {
		delete($config{'tmpl_resellers'});
		}
	else {
		$config{'tmpl_resellers'} = $tmpl->{'resellers'};
		}
	if ($tmpl->{'owners'} eq '*') {
		delete($config{'tmpl_owners'});
		}
	else {
		$config{'tmpl_owners'} = $tmpl->{'owners'};
		}
	$config{'apache_config'} = $tmpl->{'web'};
	$config{'apache_ssl_config'} = $tmpl->{'web_ssl'};
	$config{'web_user'} = $tmpl->{'web_user'};
	delete($config{'fcgiwrap'});
	$config{'cgimode'} = $tmpl->{'web_cgimode'};
	$config{'html_dir'} = $tmpl->{'web_html_dir'};
	$config{'html_perms'} = $tmpl->{'web_html_perms'};
	$config{'stats_dir'} = $tmpl->{'web_stats_dir'};
	$config{'stats_hdir'} = $tmpl->{'web_stats_hdir'};
	$config{'stats_pass'} = $tmpl->{'web_stats_pass'};
	$config{'stats_noedit'} = $tmpl->{'web_stats_noedit'};
	$config{'web_port'} = $tmpl->{'web_port'};
	$config{'web_sslport'} = $tmpl->{'web_sslport'};
	$config{'web_urlport'} = $tmpl->{'web_urlport'};
	$config{'web_urlsslport'} = $tmpl->{'web_urlsslport'};
	$config{'web_sslprotos'} = $tmpl->{'web_sslprotos'};
	$config{'web_acme'} = $tmpl->{'web_acme'};
	$config{'webmin_ssl'} = $tmpl->{'web_webmin_ssl'};
	$config{'usermin_ssl'} = $tmpl->{'web_usermin_ssl'};
	$config{'web_webmail'} = $tmpl->{'web_webmail'};
	$config{'web_webmaildom'} = $tmpl->{'web_webmaildom'};
	$config{'web_admin'} = $tmpl->{'web_admin'};
	$config{'web_admindom'} = $tmpl->{'web_admindom'};
	$config{'web_http2'} = $tmpl->{'web_http2'};
	$config{'web_redirects'} = $tmpl->{'web_redirects'};
	$config{'auto_redirect'} = $tmpl->{'web_sslredirect'};
	$config{'key_size'} = $tmpl->{'ssl_key_size'};
	$config{'cert_type'} = $tmpl->{'ssl_cert_type'};
	$config{'auto_letsencrypt'} = $tmpl->{'ssl_auto_letsencrypt'};
	$config{'letsencrypt_wild'} = $tmpl->{'ssl_letsencrypt_wild'};
	$config{'renew_letsencrypt'}= $tmpl->{'ssl_renew_letsencrypt'};
	$config{'always_ssl'} = $tmpl->{'ssl_always_ssl'};
	$config{'tlsa_records'} = $tmpl->{'ssl_tlsa_records'};
	$config{'combined_cert'} = $tmpl->{'ssl_combined_cert'};
	$config{'allow_subset'} = $tmpl->{'ssl_allow_subset'};
	$config{'php_vars'} = $tmpl->{'php_vars'} eq "none" ? "" :
				$tmpl->{'php_vars'};
	$config{'php_fpm'} = $tmpl->{'php_fpm'} eq "none" ? "" :
				$tmpl->{'php_fpm'};
	$config{'php_sock'} = $tmpl->{'php_sock'};
	$config{'php_log'} = $tmpl->{'php_log'};
	$config{'php_log_path'} = $tmpl->{'php_log_path'};
	$config{'php_suexec'} = $tmpl->{'web_php_suexec'};
	$config{'ruby_suexec'} = $tmpl->{'web_ruby_suexec'};
	$config{'phpver'} = $tmpl->{'web_phpver'};
	$config{'phpchildren'} = $tmpl->{'web_phpchildren'};
	$config{'web_ssi'} = $tmpl->{'web_ssi'};
	$config{'web_ssi_suffix'} = $tmpl->{'web_ssi_suffix'};
	$config{'dovecot_ssl'} = $tmpl->{'web_dovecot_ssl'};
	$config{'postfix_ssl'} = $tmpl->{'web_postfix_ssl'};
	$config{'mysql_ssl'} = $tmpl->{'web_mysql_ssl'};
	$config{'proftpd_ssl'} = $tmpl->{'web_proftpd_ssl'};
	foreach my $phpver (@all_possible_php_versions) {
		$config{'php_ini_'.$phpver} = $tmpl->{'web_php_ini_'.$phpver};
		}
	delete($config{'php_ini'});
	$config{'php_noedit'} = $tmpl->{'web_php_noedit'};
	$config{'def_webalizer'} = $tmpl->{'webalizer'} eq "none" ? "" :
					$tmpl->{'webalizer'};
	$config{'content_web'} = $tmpl->{'content_web'};
	delete($config{'content_web_html'});
	$config{'content_web_html'} = $tmpl->{'content_web_html'}
		if ($config{'content_web'} eq "0");
	$config{'disabled_web'} = $tmpl->{'disabled_web'} eq "none" ? "" :
					$tmpl->{'disabled_web'};
	$config{'disabled_url'} = $tmpl->{'disabled_url'} eq "none" ? "" :
					$tmpl->{'disabled_url'};
	$config{'alias_mode'} = $tmpl->{'web_alias'};
	$config{'bind_config'} = $tmpl->{'dns'} eq "none" ? ""
							  : $tmpl->{'dns'};
	$config{'bind_replace'} = $tmpl->{'dns_replace'};
	$config{'bind_spf'} = $tmpl->{'dns_spf'} eq 'none' ? undef
							   : $tmpl->{'dns_spf'};
	$config{'bind_spfhosts'} = $tmpl->{'dns_spfhosts'};
	$config{'bind_spfonly'} = $tmpl->{'dns_spfonly'};
	$config{'bind_spfincludes'} = $tmpl->{'dns_spfincludes'};
	$config{'bind_spfall'} = $tmpl->{'dns_spfall'};
	$config{'bind_dmarc'} = $tmpl->{'dns_dmarc'} eq 'none' ?
					undef : $tmpl->{'dns_dmarc'};
	$config{'bind_dmarcp'} = $tmpl->{'dns_dmarcp'};
	$config{'bind_dmarcpct'} = $tmpl->{'dns_dmarcpct'};
	$config{'bind_dmarcruf'} = $tmpl->{'dns_dmarcruf'};
	$config{'bind_dmarcrua'} = $tmpl->{'dns_dmarcrua'};
	$config{'bind_dmarcextra'} = $tmpl->{'dns_dmarcextra'};
	$config{'bind_sub'} = $tmpl->{'dns_sub'} eq 'none' ?
					undef : $tmpl->{'dns_sub'};
	$config{'bind_alias'} = $tmpl->{'dns_alias'} eq 'none' ?
					undef : $tmpl->{'dns_alias'};
	$config{'bind_cloud'} = $tmpl->{'dns_cloud'};
	$config{'bind_slaves'} = $tmpl->{'dns_slaves'};
	$config{'bind_cloud_import'} = $tmpl->{'dns_cloud_import'};
	$config{'bind_cloud_proxy'} = $tmpl->{'dns_cloud_proxy'};
	$config{'bind_master'} = $tmpl->{'dns_master'} eq 'none' ? undef
						   : $tmpl->{'dns_master'};
	$config{'bind_mx'} = $tmpl->{'dns_mx'} eq 'none' ? undef
						   : $tmpl->{'dns_mx'};
	$config{'bind_indom'} = $tmpl->{'dns_indom'};
	$config{'dns_view'} = $tmpl->{'dns_view'};
	$config{'dns_ns'} = $tmpl->{'dns_ns'};
	$config{'dns_prins'} = $tmpl->{'dns_prins'};
	$config{'dns_records'} = $tmpl->{'dns_records'};
	$config{'dns_ttl'} = $tmpl->{'dns_ttl'};
	$config{'namedconf'} = $tmpl->{'namedconf'} eq 'none' ? undef :
							$tmpl->{'namedconf'};
	$config{'namedconf_no_also_notify'} =
		$tmpl->{'namedconf_no_also_notify'};
	$config{'namedconf_no_allow_transfer'} =
		$tmpl->{'namedconf_no_allow_transfer'};
	$config{'dnssec'} = $tmpl->{'dnssec'} eq 'none' ? undef
							: $tmpl->{'dnssec'};
	$config{'dnssec_alg'} = $tmpl->{'dnssec_alg'};
	$config{'dnssec_single'} = $tmpl->{'dnssec_single'};
	delete($config{'mx_server'});
	$config{'proftpd_config'} = $tmpl->{'ftp'};
	$config{'ftp_dir'} = $tmpl->{'ftp_dir'};
	$config{'logrotate_config'} = $tmpl->{'logrotate'} eq "none" ?
					"" : $tmpl->{'logrotate'};
	$config{'logrotate_files'} = $tmpl->{'logrotate_files'} eq "none" ?
					"" : $tmpl->{'logrotate_files'};
	$config{'logrotate_shared'} = $tmpl->{'logrotate_shared'};
	$config{'statusemail'} = $tmpl->{'status'} eq 'none' ?
					'' : $tmpl->{'status'};
	$config{'statusonly'} = $tmpl->{'statusonly'};
	$config{'statustimeout'} = $tmpl->{'statustimeout'};
	$config{'statustmpl'} = $tmpl->{'statustmpl'};
	$config{'statussslcert'} = $tmpl->{'statussslcert'};
	if ($tmpl->{'mail_on'} eq 'none') {
		# Don't send
		$config{'domain_template'} = 'none';
		}
	elsif ($config{'domain_template'} eq 'none') {
		# Sending, but need to set a valid mail file
		$config{'domain_template'} = 'default';
		}
	# Write message to default template file, or custom if set
	&uncat_file($config{'domain_template'} eq "none" ||
		    $config{'domain_template'} eq "" ||
		    $config{'domain_template'} eq "default" ?
			"domain-template" :
			$config{'domain_template'}, $tmpl->{'mail'});
	$config{'newdom_subject'} = $tmpl->{'mail_subject'};
	$config{'newdom_cc'} = $tmpl->{'mail_cc'};
	$config{'newdom_bcc'} = $tmpl->{'mail_bcc'};
	if ($tmpl->{'newuser_on'} eq 'none') {
		$config{'user_template'} = 'none';
		}
	elsif ($config{'user_template'} eq 'none') {
		$config{'user_template'} = 'default';
		}
	&uncat_file($config{'user_template'} eq "none" ||
		    $config{'user_template'} eq "" ||
		    $config{'user_template'} eq "default" ?
			"user-template" :
			$config{'user_template'}, $tmpl->{'newuser'});
	$config{'newuser_subject'} = $tmpl->{'newuser_subject'};
	$config{'newuser_cc'} = $tmpl->{'newuser_cc'};
	$config{'newuser_bcc'} = $tmpl->{'newuser_bcc'};
	$config{'newuser_to_mailbox'} = $tmpl->{'newuser_to_mailbox'};
	$config{'newuser_to_owner'} = $tmpl->{'newuser_to_owner'};
	$config{'newuser_to_reseller'} = $tmpl->{'newuser_to_reseller'};
	if ($tmpl->{'updateuser_on'} eq 'none') {
		$config{'update_template'} = 'none';
		}
	elsif ($config{'user_template'} eq 'none') {
		$config{'update_template'} = 'default';
		}
	&uncat_file($config{'update_template'} eq "none" ||
		    $config{'update_template'} eq "" ||
		    $config{'update_template'} eq "default" ?
			"update-template" :
			$config{'update_template'}, $tmpl->{'updateuser'});
	$config{'newupdate_subject'} = $tmpl->{'updateuser_subject'};
	$config{'newupdate_cc'} = $tmpl->{'updateuser_cc'};
	$config{'newupdate_bcc'} = $tmpl->{'updateuser_bcc'};
	$config{'newupdate_to_mailbox'} = $tmpl->{'updateuser_to_mailbox'};
	$config{'newupdate_to_owner'} = $tmpl->{'updateuser_to_owner'};
	$config{'newupdate_to_reseller'} = $tmpl->{'updateuser_to_reseller'};
	$config{'mail_cloud'} = $tmpl->{'mail_cloud'};
	$config{'mail_mta_sts'} = $tmpl->{'mail_mta_sts'};
	$config{'aliascopy'} = $tmpl->{'aliascopy'};
	$config{'bccto'} = $tmpl->{'bccto'};
	$config{'spamclear'} = $tmpl->{'spamclear'};
	$config{'trashclear'} = $tmpl->{'trashclear'};
	$config{'spamtrap'} = $tmpl->{'spamtrap'};
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
	$config{'mysql_nouser'} = $tmpl->{'mysql_nouser'};
	$config{'mysql_chgrp'} = $tmpl->{'mysql_chgrp'};
	$config{'mysql_charset'} = $tmpl->{'mysql_charset'};
	$config{'mysql_collate'} = $tmpl->{'mysql_collate'};
	$config{'mysql_conns'} = $tmpl->{'mysql_conns'};
	$config{'mysql_uconns'} = $tmpl->{'mysql_uconns'};
	$config{'postgres_encoding'} = $tmpl->{'postgres_encoding'};
	$config{'virtual_skel'} = $tmpl->{'skel'} eq "none" ? "" :
				  $tmpl->{'skel'};
	$config{'default_exclude'} = $tmpl->{'exclude'} eq "none" ? "" :
				     $tmpl->{'exclude'};
	$config{'virtual_skel_subs'} = $tmpl->{'skel_subs'};
	$config{'virtual_skel_nosubs'} = $tmpl->{'skel_nosubs'};
	$config{'gacl_umode'} = $tmpl->{'gacl_umode'};
	$config{'gacl_ugroups'} = $tmpl->{'gacl_ugroups'};
	$config{'gacl_users'} = $tmpl->{'gacl_users'};
	$config{'gacl_groups'} = $tmpl->{'gacl_groups'};
	$config{'gacl_root'} = $tmpl->{'gacl_root'};
	$config{'webmin_group'} = $tmpl->{'webmin_group'};
	$config{'extra_prefix'} = $tmpl->{'extra_prefix'} eq "none" ? "" :
					$tmpl->{'extra_prefix'};
	$config{'defugroup'} = $tmpl->{'ugroup'};
	$config{'domains_group'} = $tmpl->{'sgroup'} eq "none" ? "" :
					$tmpl->{'sgroup'};
	$config{'defquota'} = $tmpl->{'quota'};
	$config{'defuquota'} = $tmpl->{'uquota'};
	$config{'defushell'} = $tmpl->{'ushell'};
	$config{'defujail'} = $tmpl->{'ujail'};
	$config{'defmailboxlimit'} = $tmpl->{'mailboxlimit'} eq 'none' ? undef :
				     $tmpl->{'mailboxlimit'};
	$config{'defaliaslimit'} = $tmpl->{'aliaslimit'} eq 'none' ? undef :
				   $tmpl->{'aliaslimit'};
	$config{'defdbslimit'} = $tmpl->{'dbslimit'} eq 'none' ? undef :
				 $tmpl->{'dbslimit'};
	$config{'defdomslimit'} = $tmpl->{'domslimit'} eq 'none' ? "*" :
				  $tmpl->{'domslimit'} eq '0' ? "" :
				  $tmpl->{'domslimit'};
	$config{'defaliasdomslimit'} = $tmpl->{'aliasdomslimit'} eq 'none' ?
					"*" : $tmpl->{'aliasdomslimit'};
	$config{'defrealdomslimit'} = $tmpl->{'realdomslimit'} eq 'none' ?
					"*" : $tmpl->{'realdomslimit'};
	$config{'defbwlimit'} = $tmpl->{'bwlimit'} eq 'none' ? undef :
				$tmpl->{'bwlimit'};
	$config{'defmongrelslimit'} = $tmpl->{'mongrelslimit'} eq 'none' ?
					undef : $tmpl->{'mongrelslimit'};
	$config{'defcapabilities'} = $tmpl->{'capabilities'};
	$config{'featurelimits'} = $tmpl->{'featurelimits'};
	$config{'defnodbname'} = $tmpl->{'nodbname'};
	$config{'defnorename'} = $tmpl->{'norename'};
	$config{'defforceunder'} = $tmpl->{'forceunder'};
	$config{'defsafeunder'} = $tmpl->{'safeunder'};
	$config{'defipfollow'} = $tmpl->{'ipfollow'};
	$config{'defresources'} = $tmpl->{'resources'};
	&uncat_file("framefwd-template", $tmpl->{'frame'}, 1);
	$config{'ip_ranges'} = $tmpl->{'ranges'} eq 'none' ? undef :
			       $tmpl->{'ranges'};
	$config{'ip_ranges6'} = $tmpl->{'ranges6'} eq 'none' ? undef :
			        $tmpl->{'ranges6'};
	$config{'mailgroup'} = $tmpl->{'mailgroup'} eq 'none' ? undef :
			       $tmpl->{'mailgroup'};
	$config{'ftpgroup'} = $tmpl->{'ftpgroup'} eq 'none' ? undef :
			      $tmpl->{'ftpgroup'};
	$config{'dbgroup'} = $tmpl->{'dbgroup'} eq 'none' ? undef :
			     $tmpl->{'dbgroup'};
	$config{'othergroups'} = $tmpl->{'othergroups'} eq 'none' ? undef :
			     	 $tmpl->{'othergroups'};
	$config{'hard_quotas'} = $tmpl->{'quotatype'} eq "hard" ? 1 : 0;
	$config{'hashpass'} = $tmpl->{'hashpass'};
	$config{'hashtypes'} = $tmpl->{'hashtypes'};
	$config{'append_style'} = $tmpl->{'append_style'};
	$config{'domalias'} = $tmpl->{'domalias'} eq 'none' ? undef :
			      $tmpl->{'domalias'};
	$config{'domalias_type'} = $tmpl->{'domalias_type'};
	$config{'domauto_disable'} = $tmpl->{'domauto_disable'};
	$config{'tmpl_autoconfig'} = $tmpl->{'autoconfig'};
	$config{'tmpl_outlook_autoconfig'} = $tmpl->{'outlook_autoconfig'};
	$config{'key_tmpl'} = $tmpl->{'cert_key_tmpl'};
	$config{'cert_tmpl'} = $tmpl->{'cert_cert_tmpl'};
	$config{'ca_tmpl'} = $tmpl->{'cert_ca_tmpl'};
	$config{'combined_tmpl'} = $tmpl->{'cert_combined_tmpl'};
	$config{'everything_tmpl'} = $tmpl->{'cert_everything_tmpl'};
	foreach my $w (&list_php_wrapper_templates()) {
		$config{$w} = $tmpl->{$w};
		}
	my %avail = map { split(/=/, $_) } split(/\s+/, $tmpl->{'avail'});
	foreach my $m (&list_domain_owner_modules()) {
		$config{'avail_'.$m->[0]} = $avail{$m->[0]} || 0;
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
	$tmpl->{'newuser'} =~ s/\n/\t/g;
	$tmpl->{'updateuser'} =~ s/\n/\t/g;
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
undef(@list_templates_cache);
}

# get_template(id, [template-overrides])
# Returns a template, with any default settings filled in from real default
sub get_template
{
my ($tmplid) = @_;
local @tmpls = &list_templates();
local ($tmpl) = grep { $_->{'id'} == $tmplid } @tmpls;
return undef if (!$tmpl);	# not found
if (!$tmpl->{'default'}) {
	local $def = $tmpls[0];
	local $p;
	local %done;
	foreach $p ("dns_spf", "dns_sub", "dns_master", "dns_mx", "dns_dmarc",
		    "dns_cloud", "dns_slaves", "dns_prins", "dns_alias",
		    "web_acme", "web_webmail", "web_admin", "web_http2",
		    "web_redirects", "web_sslredirect", "web_php",
		    "web", "dns", "ftp", "mail", "frame", "user_aliases",
		    "ugroup", "sgroup", "quota", "uquota", "ushell", "ujail",
		    "mailboxlimit", "domslimit",
		    "dbslimit", "aliaslimit", "bwlimit", "mongrelslimit","skel",
		    "mysql_hosts", "mysql_mkdb", "mysql_suffix", "mysql_chgrp",
		    "mysql_nopass", "mysql_wild", "mysql_charset", "mysql",
		    "mysql_nouser", "postgres_encoding", "webalizer",
		    "dom_aliases", "ranges", "ranges6",
		    "mailgroup", "ftpgroup", "dbgroup",
		    "othergroups", "defmquota", "quotatype", "append_style",
		    "domalias", "logrotate_files", "logrotate_shared",
		    "logrotate", "disabled_web", "disabled_url", "php_sock",
		    "php_fpm", "php_log", "php", "newuser", "updateuser",
		    "status", "extra_prefix", "capabilities",
		    "webmin_group", "spamclear", "trashclear",
		    "spamtrap", "namedconf",
		    "nodbname", "norename", "forceunder", "safeunder",
		    "ipfollow", "exclude", "cert_key_tmpl", "cert_cert_tmpl",
		    "cert_ca_tmpl", "cert_combined_tmpl","cert_everything_tmpl",
		    "ssl_key_size", "ssl_cert_type", "ssl_auto_letsencrypt",
		    "ssl_letsencrypt_wild", "ssl_always_ssl",
		    "ssl_tlsa_records", "ssl_combined_cert",
		    "ssl_renew_letsencrypt", "ssl_allow_subset",
		    "aliascopy", "bccto", "resources", "dnssec", "avail",
		    @plugins,
		    &list_php_wrapper_templates(),
		    "capabilities",
		    "featurelimits",
		    "hashpass", "hashtypes", "autoconfig", "outlook_autoconfig",
		    (map { $_."limit", $_."server", $_."master", $_."view",
			   $_."passwd" } @plugins)) {
		my $psel = $p eq "web_php" ? "web_php_suexec" :
			   $p eq "mail" ? "mail_on" : $p;
		if ($tmpl->{$psel} eq "") {
			local $k;
			foreach $k (keys %$def) {
				next if ($p eq "dns" &&
					 $k =~ /^dns_(spf|cloud|slaves|prins|alias)/);
				next if ($p eq "php" &&
					 $k =~ /^php_(fpm|sock)/);
				next if ($p eq "web" &&
					 $k =~ /^web_(webmail|admin|http2|redirects|sslredirect|php|acme)/);
				next if ($p eq "mysql" &&
					 $k =~ /^mysql_(hosts|mkdb|suffix|chgrp|nopass|wild|charset|nouser)/);
				next if ($done{$k});
				if ($k =~ /^\Q$p\E_/ ||
				    $k eq $psel || $k eq $p) {
					# If the selector is named like 'web',
					# the template inherits default values
					# like 'web' or 'web_foo'
					$tmpl->{$k} = $def->{$k};
					$done{$k}++;
					}
				elsif ($p =~ /^(dns_spf)$/ &&
				       $k =~ /^\Q$p\E/) {
					# If the selector is named like 'dns_spf'
					# the template inherits default values
					# like 'dns_spfall'
					$tmpl->{$k} = $def->{$k};
					$done{$k}++;
					}
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

# cat_file(file, [newlines-to-tabs])
# Returns the contents of some file
sub cat_file
{
local ($file, $tabs) = @_;
local $path = $file =~ /^\// ? $file : "$module_config_directory/$file";
local $rv = &read_file_contents($path);
if ($tabs) {
	$rv =~ s/\r//g;
	$rv =~ s/\n/\t/g;
	}
return $rv;
}

# uncat_file(file, data, [tabs-to-newlines])
# Writes to some file
sub uncat_file
{
local ($file, $data, $tabs) = @_;
if ($tabs) {
	$data =~ s/\t/\n/g;
	}
local $path = $file =~ /^\// ? $file : "$module_config_directory/$file";
&open_lock_tempfile(FILE, ">$path");
&print_tempfile(FILE, $data);
&close_tempfile(FILE);
}

# uncat_transname(data)
# Creates a temp file and writes some data to it
sub uncat_transname
{
local ($data, $tabs) = @_;
local $temp = &transname();
&uncat_file($temp, $data, $tabs);
return $temp;
}

# plugin_call(module, function, [arg, ...])
# If some plugin function is defined, call it and return the result,
# otherwise return undef
sub plugin_call
{
local ($mod, $func, @args) = @_;
&load_plugin_libraries($mod);
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

# try_plugin_call(module, function, [arg, ...])
# Like plugin_call, but catches and prints errors
sub try_plugin_call
{
local ($mod, $func, @args) = @_;
local $main::error_must_die = 1;
eval { &plugin_call($mod, $func, @args) };
if ($@) {
	my $fn = &plugin_call($mod, "feature_name");
	&$second_print(&text('setup_failure', $fn, "$@"));
	return 0;
	}
return 1;
}

# plugin_defined(module, function)
# Returns 1 if some function is defined in a plugin
sub plugin_defined
{
local ($mod, $func) = @_;
&load_plugin_libraries($mod);
$mod =~ s/[^A-Za-z0-9]/_/g;
local $func = "${mod}::$func";
return defined(&$func);
}

# database_feature([&domain])
# Returns 1 if any feature that uses a database is enabled (perhaps in a domain)
sub database_feature
{
local ($d) = @_;
foreach my $f ('mysql', 'postgres') {
	return 1 if ($config{$f} && (!$d || $d->{$f}));
	}
foreach my $f (&list_database_plugins()) {
	return 1 if ($config{$f} && (!$d || $d->{$f}));
	}
return 0;
}

# list_custom_fields()
# Returns a list of structures containing custom field details. Each has keys :
#   name - Unique name for this field
#   type - 0=textbox, 1=unix user, 2=unix UID, 3=unix group, 4=unix GID,
#          5=file chooser, 6=directory chooser, 7=yes/no, 8=password,
#          9=options file, 10=text area
#   opts - Name of options file
#   desc - Human-readable description, with optional ; separated tooltip
#   show - 1=show in list of domains, 0=hide
#   visible - 0=anyone can edit
#   	      1=root can edit, others can view
#   	      2=only root can see
sub list_custom_fields
{
local @rv;
local $_;
open(FIELDS, "<".$custom_fields_file);
while(<FIELDS>) {
	s/\r|\n//g;
	local @a = split(/:/, $_, 6);
	push(@rv, { 'name' => $a[0],
		    'type' => $a[1],
		    'opts' => $a[2],
		    'desc' => $a[3],
		    'show' => $a[4],
		    'visible' => $a[5], });

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
		     $a->{'opts'},":",$a->{'desc'},":",$a->{'show'},":",
		     $a->{'visible'},"\n");
	}
&close_tempfile(FIELDS);
}

# list_custom_links()
# Returns a list of structures containing custom link details
sub list_custom_links
{
local @rv;
local $_;
open(LINKS, "<".$custom_links_file);
while(<LINKS>) {
	s/\r|\n//g;
	local @a = split(/\t/, $_);
	push(@rv, { 'desc' => $a[0],
		    'url' => $a[1],
		    'who' => { map { $_ => 1 } split(/:/, $a[2]) },
		    'open' => $a[3],
		    'cat' => $a[4],
		    'tmpl' => $a[5] eq '-' ? undef : $a[5],
		    'feature' => $a[6] eq '-' ? undef : $a[6],
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
	&print_tempfile(LINKS,
		$a->{'desc'}."\t".$a->{'url'}."\t".
		join(":", keys %{$a->{'who'}})."\t".
		int($a->{'open'})."\t".$a->{'cat'}."\t".
		($a->{'tmpl'} eq "" ? "-" : $a->{'tmpl'})."\t".
		($a->{'feature'} eq "" ? "-" : $a->{'feature'})."\t".
		"\n");
	}
&close_tempfile(LINKS);
}

# list_custom_link_categories()
# Returns a list of all custom link category hash refs
sub list_custom_link_categories
{
local @rv;
open(LINKCATS, "<".$custom_link_categories_file);
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
	if (!$l->{'who'}->{$me}) {
		# Not for you
		next;
		}
	if ($l->{'tmpl'} && $d->{'template'} ne $l->{'tmpl'}) {
		# Not for this domain template
		next;
		}
	if ($l->{'feature'} && !$d->{$l->{'feature'}}) {
		# Not for this domain feature
		next;
		}
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
return @rv;
}

# show_custom_fields([&domain], [&tds])
# Returns HTML for custom field inputs, for inclusion in a table
sub show_custom_fields
{
local ($d, $tds) = @_;
local $rv;
local $col = 0;
foreach my $f (&list_custom_fields()) {
	local ($desc, $tip) = split(/;/, $f->{'desc'}, 2);
	$desc = &html_escape($desc);
	if ($tip) {
		$desc = "<div title='".&quote_escape($tip)."'>$desc</div>";
		}
	if ($f->{'visible'} == 0 || &master_admin()) {
		# Can edit
		local $n = "field_".$f->{'name'};
		local $v = $d ? $d->{"field_".$f->{'name'}} :
			   $f->{'type'} == 7 ? 1 :
			   $f->{'type'} == 11 ? 0 : undef;
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
		elsif ($f->{'type'} == 7 || $f->{'type'} == 11) {
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
			push(@opts, [ $v, $v ]) if (!$found && $v ne '');
			$fv = &ui_select($n, $v, \@opts);
			}
		elsif ($f->{'type'} == 10) {
			local ($w, $h) = split(/\s+/, $f->{'opts'});
			$h ||= 4;
			$w ||= 30;
			$v =~ s/\t/\n/g;
			$fv = &ui_textarea($n, $v, $h, $w);
			}
		$rv .= &ui_table_row($desc, $fv, 1, $tds);
		}
	elsif ($f->{'visible'} == 1 && $d) {
		# Can only see
		local $fv = $d->{"field_".$f->{'name'}};
		$rv .= &ui_table_row($desc, $fv, 1, $tds);
		}
	}
return $rv;
}

# parse_custom_fields(&domain, &in)
# Updates a domain with custom fields
sub parse_custom_fields
{
local %in = %{$_[1]};
foreach my $f (&list_custom_fields()) {
	next if ($f->{'visible'} != 0 && !&master_admin());
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
	elsif ($f->{'type'} == 7 || $f->{'type'} == 11) {
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
open(FILE, "<".$file);
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

# create_initial_user(&dom, [no-template], [for-web])
# Returns a structure for a new mailbox user
sub create_initial_user
{
my ($d, $notmpl, $forweb) = @_;
my $user = { 'unix' => 1 };
if ($d && !$notmpl) {
	# Initial aliases and quota come from template
	local $tmpl = &get_template($d->{'template'});
	if ($tmpl->{'user_aliases'} ne 'none') {
		$user->{'to'} = [ map { &substitute_domain_template($_, $d) }
				      split(/\t+/, $tmpl->{'user_aliases'}) ];
		}
	if (&has_home_quotas()) {
		$user->{'quota'} = $tmpl->{'defmquota'};
		}
	if (&has_mail_quotas()) {
		$user->{'mquota'} = $tmpl->{'defmquota'};
		}
	}
if (!$user->{'noprimary'}) {
	$user->{'email'} = !$d ? "newuser\@".&get_system_hostname() :
			   $d->{'mail'} ? "newuser\@$d->{'dom'}" : undef;
	}
$user->{'secs'} = [ ];
$user->{'shell'} = &default_available_shell('mailbox');

# Merge in configurable initial user settings
if ($d) {
	local %init;
	&read_file("$initial_users_dir/$d->{'id'}", \%init);
	foreach my $a ("email", "quota", "mquota", "shell") {
		$user->{$a} = $init{$a} if (defined($init{$a}) &&
					    $init{$a} eq "none");
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
				     'name' => $name,
				     'desc' => $text{'databases_'.$type} });
			}
		$user->{'dbs'} = \@dbs;
		}
	}

if ($forweb) {
	# This is a website management user
	local (undef, $ftp_shell, undef, $def_shell) =
		&get_common_available_shells();
	$user->{'webowner'} = 1;
	$user->{'fixedhome'} = 0;
	$user->{'home'} = &public_html_dir($d);
	$user->{'noquota'} = 1;
	$user->{'noprimary'} = 1;
	$user->{'noextra'} = 1;
	$user->{'noalias'} = 1;
	$user->{'nocreatehome'} = 1;
	$user->{'nomailfile'} = 1;
	$user->{'shell'} = $ftp_shell ? $ftp_shell->{'shell'}
				      : $def_shell->{'shell'};
	delete($user->{'email'});
	}

# For a unix user, apply default password expiry restrictions
if ($gconfig{'os_type'} =~ /-linux$/) {
	&require_useradmin();
	local %uconfig = &foreign_config("useradmin");
	if ($usermodule eq "ldap-useradmin") {
		local %lconfig = &foreign_config($usermodule);
		foreach my $k (keys %lconfig) {
			if ($lconfig{$k} ne "") {
				$uconfig{$k} = $lconfig{$k};
				}
			}
		}
	$user->{'min'} = $uconfig{'default_min'};
	$user->{'max'} = $uconfig{'default_max'};
	$user->{'warn'} = $uconfig{'default_warn'};
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
foreach my $a ("email", "quota", "mquota", "shell") {
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

# allowed_domain_name(&parent, newdomain)
# Returns an error message if some domain name is invalid, or undef if OK.
# Checks domain-owner subdomain and reseller subdomain limits.
sub allowed_domain_name
{
local ($parent, $newdom) = @_;

# Check if forced to be under one of the domains he already owns
if ($parent && $access{'forceunder'}) {
	local $ok = 0;
	foreach my $pdom ($parent, &get_domain_by("parent", $parent->{'id'})) {
		local $pd = $pdom->{'dom'};
		if ($newdom =~ /\.\Q$pd\E$/i) {
			$ok = 1;
			last;
			}
		}
	$ok || return &text('setup_eforceunder2', $parent->{'dom'});
	}

# Check if under someone else's domain
if ($parent && $access{'safeunder'}) {
	foreach my $d (&list_domains()) {
		local $od = $d->{'dom'};
		if ($d->{'id'} ne $parent->{'id'} &&
		    $d->{'parent'} ne $parent->{'id'} &&
		    $newdom =~ /\.\Q$od\E$/i) {
			return &text('setup_esafeunder', $od);
			}
		}
	}

# Check allowed domain regexp
if ($access{'subdom'}) {
	if ($newdom !~ /\.\Q$access{'subdom'}\E$/i) {
		return &text('setup_eforceunder', $access{'subdom'});
		}
	}

# Check if on denied list
if (!&master_admin()) {
	foreach my $re (split(/\s+/, $config{'denied_domains'})) {
		if ($newdom =~ /^$re$/i) {
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
local ($d, $types) = @_;
local @dbs;
if ($d->{'mysql'} && (!$types || &indexof("mysql", @$types) >= 0)) {
	local %done;
	local $mymod = &require_dom_mysql($d);
	local $av = &foreign_available($mymod);
	local $myhost = &get_database_host_mysql($d);
	$myhost = undef if ($myhost eq 'localhost');
	foreach my $db (split(/\s+/, $d->{'db_mysql'})) {
		next if ($done{$db}++);
		push(@dbs, { 'name' => $db,
			     'type' => 'mysql',
			     'users' => 1,
			     'link' => $av ? "../$mymod/edit_dbase.cgi?db=$db"
					   : undef,
			     'desc' => $text{'databases_mysql'},
			     'host' => $myhost, });
		}
	}
if ($d->{'postgres'} && (!$types || &indexof("postgres", @$types) >= 0)) {
	local %done;
	local $pgmod = &require_dom_postgres($d);
	local $av = &foreign_available("postgresql");
	&require_postgres();
	local $pghost = &get_database_host_postgres($d);
	$pghost = undef if ($pghost eq 'localhost');
	foreach my $db (split(/\s+/, $d->{'db_postgres'})) {
		next if ($done{$db}++);
		push(@dbs, { 'name' => $db,
			     'type' => 'postgres',
			     'link' => $av ? "../$pgmod/".
					     "edit_dbase.cgi?db=$db"
					   : undef,
			     'desc' => $text{'databases_postgres'},
			     'host' => $pghost, });
		}
	}

# Only check plugins if some non-core DB types were requested
local @nctypes = $types ? grep { $_ ne "mysql" && $_ ne "postgres" } @$types
			: ( );
if (!$types || @nctypes) {
	foreach my $f (&list_database_plugins()) {
		if (!$types || &indexof($f, @$types) >= 0) {
			push(@dbs, &plugin_call($f, "database_list", $d));
			}
		}
	}
return @dbs;
}

# all_databases([&domain])
# Returns a list of all known databases on the system, possibly limited to
# those relevant for some domain.
sub all_databases
{
local ($d) = @_;
local @rv;
if ($config{'mysql'} && (!$d || $d->{'mysql'})) {
	&require_mysql();
	push(@rv, map { { 'name' => $_,
			  'type' => 'mysql',
			  'desc' => $text{'databases_mysql'},
			  'special' => $_ =~ /^(mysql|sys|information_schema|performance_schema)$/ } }
		      &list_all_mysql_databases($d));
	}
if ($config{'postgres'} && (!$d || $d->{'postgres'})) {
	&require_postgres();
	push(@rv, map { { 'name' => $_,
			  'type' => 'postgres',
			  'desc' => $text{'databases_postgres'},
			  'special' => ($_ =~ /^template/i) } }
		      &list_all_postgres_databases($d));
	}
foreach my $f (&list_database_plugins()) {
	if (!$d || $d->{$f}) {
		push(@rv, &plugin_call($f, "databases_all", $d));
		}
	}
return @rv;
}

# all_database_types()
# Returns a list of all database types on the system
sub all_database_types
{
return ( $config{'mysql'} ? ("mysql") : ( ),
	 $config{'postgres'} ? ("postgres") : ( ),
	 &list_database_plugins() );
}

# resync_all_databases(&domain, &all-dbs)
# Updates a domain object to remove databases that no longer really exist, and
# perhaps to change the 'db' field to the first actual database
sub resync_all_databases
{
local ($d, $all) = @_;
return if (!@$all);		# If no DBs were found on the system, do nothing
				# to avoid mass dis-association
local %all = map { ("$_->{'type'} $_->{'name'}", $_) } @$all;
local $removed = 0;
&lock_domain($d);
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

# Fix 'db' field if it is currently set to a missing DB
local @domdbs = &domain_databases($d);
local ($defdb) = grep { $_->{'name'} eq $d->{'db'} } @domdbs;
if (!$defdb && @domdbs) {
	$d->{'db'} = $domdbs[0]->{'name'};
	&save_domain($d);
	}
&unlock_domain($d);
}

# get_database_host(type, [&domain])
# Returns the remote host that we use for the given database type. If the
# DB is on the same server, returns localhost
sub get_database_host
{
local ($type, $d) = @_;
local $rv;
if (&indexof($type, @features) >= 0) {
	# Built-in DB
	local $hfunc = "get_database_host_".$type;
	$rv = &$hfunc($d);
	}
elsif (&indexof($type, &list_database_plugins()) >= 0) {
	# From plugin
	$rv = &plugin_call($type, "database_host", $d);
	}
$rv ||= "localhost";
if ($rv eq "localhost" && $type eq "mysql") {
	# Is this domain under a chroot? If so, use 127.0.0.1 to force use
	# of a TCP connection rather than a socket
	my $parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	if (&get_domain_jailkit($parent)) {
		$rv = "127.0.0.1";
		}
	}
return $rv;
}

# check_domain_hashpass(&domain)
# Shows a checkbox to enable hashed passwords
# if domain and template don't have it aligned
sub check_domain_hashpass
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
if (defined($d->{'hashpass'}) && defined($tmpl->{'hashpass'}) &&
    $d->{'hashpass'} != $tmpl->{'hashpass'}) {
	return 1;
	}
return 0;
}

# update_domain_hashpass(&dom, mode)
# Updates domain hashpass option if needed, and
# delete all *_enc_pass if disabling hashing
sub update_domain_hashpass
{
my ($d, $mode) = @_;
if (&check_domain_hashpass($d)) {
	$d->{'hashpass'} = $mode;
	if (!$mode) {
		my @encpass_opts = grep { /enc_pass$/ } keys %{$d};
		foreach my $encpass_opt (@encpass_opts) {
			delete($d->{$encpass_opt});
			}
		}
	return 1;
	}
return 0;
}

# post_update_domain_hashpass(&@doms, mode, pass)
# Apply domain services hashpass clean ups
sub post_update_domain_hashpass
{
my ($d, $mode, $pass) = @_;
if ($mode) {
	# On switching to hashed mode some passwords
	# services need to be reset to plain text	
	my $opt = 'mysql_enc_pass';
	if ($d->{$opt}) {
		my $fn = $opt;
		$fn =~ s/enc_//;
		$d->{$fn} = $pass;
		delete($d->{$opt});
		}
	}
}

# get_password_synced_types(&domain)
# Returns a list of DB types that are enabled for this domain and have their
# passwords synced with the admin login
sub get_password_synced_types
{
local ($d) = @_;
my @rv;
foreach my $t (&all_database_types()) {
	my $sfunc = $t."_password_synced";
	if (defined(&$sfunc) && &$sfunc($d)) {
		# Definitely is synced
		push(@rv, $t);
		}
	elsif (!defined(&$sfunc)) {
		# Assume yes for other DB types
		push(@rv, $t);
		}
	}
return @rv;
}

# count_ftp_bandwidth(logfile, start, &bw-hash, &users, prefix, include-rotated)
# Scans an FTP server log file for downloads by some user, and returns the
# total bytes and time of last log entry.
sub count_ftp_bandwidth
{
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
		open(LOG, "<".$f);
		}
	while(<LOG>) {
		if (/^(\S+)\s+(\S+)\s+(\S+)\s+\[(\d+)\/(\S+)\/(\d+):(\d+):(\d+):(\d+)\s+(\S+)\]\s+"([^"]*)"\s+(\S+)\s+(\S+)/) {
			# ProFTPD extended log format line
			local $ltime = timelocal($9, $8, $7, $4, $apache_mmap{lc($5)}, $6);
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
			local $ltime = timelocal($5, $4, $3, $2, $apache_mmap{lc($1)}, $6);
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
my $random_password;
my $len = $_[0] || $config{'passwd_length'} || 25;
eval "utf8::decode(\$config{'passwd_chars'})"
	if ($config{'passwd_chars'});
my @passwd_chars = split(//, $config{'passwd_chars'});
if (!@passwd_chars) {
	@passwd_chars = @useradmin::random_password_chars;
	}
# Number of characters to operate on
my $passwd_chars = scalar(@passwd_chars);
# Check resulting password and try again
# if it doesn't meet the requirements
for (my $i = 0; $i < $passwd_chars*100; $i++) {
	$random_password = '';
	foreach (1 .. $len) {
		$random_password .= $passwd_chars[rand($passwd_chars)];
		}
	return $random_password
		if (&random_password_validate(
			\@passwd_chars, $len, $random_password) != 0);
	}
return $random_password;
}

sub random_password_validate
{
my ($chars, $len, $pass) = @_;
# Define character type checks in a hash
my %check = (
	uppercase => qr/[A-Z]/,
	lowercase => qr/[a-z]/,
	digit     => qr/[0-9]/,
	special   => qr/[\@\#\$\%\^\&\*\(\)\_\+\!\-\=\[\]\{\}\;\:\'\"\,\<\.\>\/\?\~\`\\]/,
	unicode   => qr/(?![A-Za-z])\p{L}/,
	);
# Determine required character types
my %required;
foreach my $key (keys %check) {
	# If any character in @$chars matches the regex for this
	# key, add the key to %required with a value of 1
	if (grep { $_ =~ $check{$key} } @$chars) {
		$required{$key} = 1;
		}
	}
# Return -1 if the number of required types exceeds the password length
return -1 if scalar(keys %required) > $len;
# Check if password contains one of each required types
my $matches = grep { $pass =~ $check{$_} } keys %required;
return 0 unless $matches == keys %required;
return 1;
}

# random_salt([len])
# Returns a crypt-format salt of the given length (default 2 chars)
sub random_salt
{
local $len = $_[0] || 2;
&seed_random();
local $rv;
local @saltchars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '.', '/' );
for(my $i=0; $i<$len; $i++) {
	$rv .= $saltchars[int(rand()*scalar(@saltchars))];
	}
return $rv;
}

# try_function(feature, function, arg, ...)
# Executes some function, and if it fails prints an error message. In a scalar
# context returns 0 if the function failed, 1 otherwise. In an array context,
# returns this flag plus the function's actual return value.
sub try_function
{
local ($f, $func, @args) = @_;
local $main::error_must_die = 1;
local $rv;
eval { $rv = &$func(@args) };
if ($@) {
	&$second_print(&text('setup_failure',
			     $text{'feature_'.$f}, "$@"));
	return wantarray ? ( 0 ) : 0;
	}
return wantarray ? ( 1, $rv ) : 1;
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
	return $sday + 6;
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
	return $sday + $config{'bw_period'} - 1;
	}
}

# servers_input(name, &ids, &domains, [disabled], [use-multi-select])
# Returns HTML for a multi-server selection field
sub servers_input
{
my ($name, $ids, $doms, $dis, $ms) = @_;
my $sz = scalar(@$doms) > 10 ? 10 : scalar(@$doms) < 5 ? 5 : scalar(@$doms);
my $opts = [ map { [ $_->{'id'}, &show_domain_name($_) ] }
		 sort { $a->{'dom'} cmp $b->{'dom'} } @$doms ];
my $vals = [ ];
foreach my $id (@$ids) {
	my $d = &get_domain($id);
	push(@$vals, [$id, $d ? &show_domain_name($d) : $id]);
	}
if ($ms) {
	return &ui_multi_select($name, $vals, $opts, $sz, 1, $dis);
	}
else {
	return &ui_select($name, $vals, $opts, $sz, 1, 0, $dis);
	}
}

# one_server_input(name, id, &domains, [disabled])
# Returns HTML for a single-server selection field
sub one_server_input
{
local ($name, $id, $doms, $dis) = @_;
return &ui_select($name, $id,
		  [ map { [ $_->{'id'}, &show_domain_name($_) ] }
			sort { $a->{'dom'} cmp $b->{'dom'} } @$doms ],
		  1, 0, 0, $dis);
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

# Returns 1 if the user can change his own password. Not shown for root,
# because this is done outside of Virtualmin.
sub can_passwd
{
return &reseller_admin() || $access{'edit_passwd'};
}

# Returns 1 if the user can enroll for 2fa
sub can_user_2fa
{
my %miniserv;
&get_miniserv_config(\%miniserv);
return $miniserv{'twofactor_provider'} && $access{'edit_passwd'};
}

# Return 1 if the master admin or reseller can enroll for 2fa
sub can_master_reseller_2fa
{
my %miniserv;
&get_miniserv_config(\%miniserv);
return $miniserv{'twofactor_provider'} &&
       (&master_admin() || &reseller_admin());
}

# Returns 1 if the user can change a domain's external IP address
sub can_dnsip
{
return &master_admin() || &reseller_admin() || $access{'edit_dnsip'};
}

# Returns 1 if the current user can set the chained certificate path to
# anywhere.
sub can_chained_cert_path
{
return &master_admin();
}

# Returns 1 if the user can copy a domain's cert to Webmin
sub can_webmin_cert
{
return &master_admin();
}

# Returns 1 if the current user can edit allowed remote DB hosts
sub can_allowed_db_hosts
{
return &master_admin() || &reseller_admin() || $access{'edit_allowedhosts'};
}

# Returns 2 if the current user can manage all plans, 1 if his own only,
# 0 if cannot manage any
sub can_edit_plans
{
return &master_admin() ? 2 :
       &reseller_admin() && !$access{'noplans'} ? 1 : 0;
}

# Returns 1 if the current user can edit log file locations
sub can_log_paths
{
return &master_admin();
}

# Returns 1 if DNS records can be manually edited
sub can_manual_dns
{
return &master_admin();
}

sub can_edit_resellers
{
return &can_edit_templates() || $access{'createresellers'};
}

# has_proxy_balancer(&domain)
# Returns 2 if some domain supports proxy balancing to multiple URLs, 1 for
# proxying to a single URL, 0 if neither.
sub has_proxy_balancer
{
local ($d) = @_;
if ($config{'web'} && !$d->{'alias'} && !$d->{'proxy_pass_mode'}) {
	# From Apache
	&require_apache();
	if ($apache::httpd_modules{'mod_proxy'} &&
	    $apache::httpd_modules{'mod_proxy_balancer'}) {
		return 2;
		}
	elsif ($apache::httpd_modules{'mod_proxy'}) {
		return 1;
		}
	}
else {
	# From plugin, maybe
	local $p = &domain_has_website($d);
	return &plugin_defined($p, "feature_supports_web_balancers") ?
		&plugin_call($p, "feature_supports_web_balancers", $d) : 0;
	}
}

# has_proxy_none([&domain])
# Returns 1 if the system supports disabling proxying for some URL
sub has_proxy_none
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p eq 'web') {
	&require_apache();
	return $apache::httpd_modules{'mod_proxy'} >= 2.0;
	}
else {
	return 1;	# Assume OK for plugins
	}
}

# has_webmail_rewrite(&domain)
# Returns 1 if this system has mod_rewrite, needed for redirecting webmail.$DOM
# to port 20000
sub has_webmail_rewrite
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p eq 'web') {
	# Check Apache modules
	&require_apache();
	return $apache::httpd_modules{'mod_rewrite'};
	}
else {
	# Call plugin
	return &plugin_defined($p, "feature_supports_webmail_redirect") &&
	       &plugin_call($p, "feature_supports_webmail_redirect", $d);
	}
}

# has_sni_support([&domain])
# Returns 1 if the webserver supports SNI for SSL cert selection
sub has_sni_support
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p eq 'web') {
	# Check Apache modules
	&require_apache();
	local @dirs = &list_apache_directives();
	local ($sni) = grep { lc($_->[0]) eq lc("SSLStrictSNIVHostCheck") }
			    @dirs;
	return 1 if ($sni);
	if ($apache::httpd_modules{'mod_ssl'} >= 2.3 ||
	    $apache::httpd_modules{'mod_ssl'} =~ /^2\.2(\d+)/ && $1 >= 12) {
		# Assume SNI works for Apache 2.2.12 or later
		return 1;
		}
	return 0;
	}
else {
	# Call plugin
	return &plugin_defined($p, "feature_supports_sni") &&
	       &plugin_call($p, "feature_supports_sni", $d);
	}
}

# has_cgi_support([&domain])
# Returns a list of supported cgi modes, which can be 'suexec' and 'fcgiwrap'
sub has_cgi_support
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	# Check if Apache supports suexec or fcgiwrap
	my @rv;
	push(@rv, 'suexec') if (&supports_suexec($d));
	push(@rv, 'fcgiwrap') if (&supports_fcgiwrap());
	return @rv;
	}
elsif ($p) {
	# Call plugin function
	my $supp = &plugin_defined($p, "feature_web_supports_cgi") &&
	           &plugin_call($p, "feature_web_supports_cgi", $d);
	return ('fcgiwrap') if ($supp);
	}
return ( );
}

# get_domain_cgi_mode(&domain)
# Returns either 'suexec', 'fcgiwrap' or undef depending on how CGI scripts
# are being run
sub get_domain_cgi_mode
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	# Check Apache suexec or fcgiwrap modes
	if (&get_domain_suexec($d)) {
		return 'suexec';
		}
	elsif ($d->{'fcgiwrap_port'} && &get_domain_fcgiwrap($d)) {
		return 'fcgiwrap';
		}
	return undef;
	}
elsif ($p) {
	# Check plugin supported mode
	return &plugin_call($p, "feature_web_get_domain_cgi_mode", $d);
	}
return undef;
}

# save_domain_cgi_mode(&domain, mode)
# Change the mode for executing CGI scripts to either fcgiwrap, suexec or undef
# to disable them entirely
sub save_domain_cgi_mode
{
my ($d, $mode) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	# Is PHP mode compatible?
	my $phpmode = &get_domain_php_mode($d);
	if (!$mode && ($phpmode eq 'cgi' || $phpmode eq 'fcgid')) {
		return $text{'website_ephpcgi'};
		}
	if ($mode eq 'fcgiwrap' && $phpmode eq 'fcgid') {
		return $text{'website_ephpfcgid'};
		}

	&obtain_lock_web($d);
	if ($mode ne 'fcgiwrap') {
		&disable_apache_fcgiwrap($d);
		}
	if ($mode ne 'suexec') {
		&disable_apache_suexec($d);
		}
	my $err = undef;
	if ($mode eq 'suexec') {
		$err = &enable_apache_suexec($d);
		}
	elsif ($mode eq 'fcgiwrap') {
		$err = &enable_apache_fcgiwrap($d);
		}
	&lock_domain($d);
	if (!$err) {
		$d->{'last_cgimode'} = $mode;
		}
	&save_domain($d);
	&unlock_domain($d);
	&release_lock_web($d);
	return $err;
	}
elsif ($p) {
	my $err = &plugin_call($p, "feature_web_save_domain_cgi_mode",
			       $d, $mode);
	if (!$err) {
		&lock_domain($d);
		$d->{'last_cgimode'} = $mode;
		&save_domain($d);
		&unlock_domain($d);
		}
	return $err;
	}
else {
	return "Virtual server does not have a website!";
	}
}

# require_licence()
# Reads in the file containing the licence_scheduled function.
# Returns 1 if OK, 0 if not
sub require_licence
{
my ($force) = @_;
return 0 if (!$virtualmin_pro && !$force);
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
	local $job = &find_cron_script($licence_cmd);
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
		}
	&setup_cron_script($job);
	}
}

# licence_state()
# Returns license state as hash
sub licence_state
{
my @keys = qw(Y D T Q P H);
my %hash;
for my $i (0 .. $#keys) {
	$hash{$keys[$i]} = $i == 0 ? 0 + ~0 : $i + 1;
	}
return %hash;
}

# licence_status()
# Checks license status
sub licence_status
{
# Licence related checks
if ($virtualmin_pro && -r $licence_status) {
	my %licence_status;
	&read_file($licence_status, \%licence_status);
	my ($bind, $time) = ($licence_status{'bind'}, $licence_status{'time'});
	my $scale = 1;
	$scale = 3 if ($licence_status{'status'} == 3);
	if ($main::webmin_script_type ne 'cron' && !$time && $bind &&
	    int(($bind-time())/86400)+(21/$scale) <= 0) {
		my $title = $text{'licence_expired'};
		my $body = &text('licence_expired_desc',
			&get_webprefix_safe()."/$module_name/pro/licence.cgi");
		if ($main::webmin_script_type eq 'cmd') {
			my $chars = 75;
			my $astrx = "*" x $chars;
			my $attrx = "*" x 2;
			$body = &html_tags_to_text($body);
			$title = "$attrx $title $attrx";
			my $ptitle = ' ' x (int(($chars - length($title)) / 2)).
				$title;
			$title .= ' ' x ($chars - length($ptitle));
			$body =~ s/(.{1,$chars})(?:\s+|$)/$1\n/g;
			$body = "\n$astrx\n$ptitle\n$body$astrx\n";
			print "$body\n";
			exit(99);
			}
		elsif ($main::webmin_script_type eq 'web') {
			&ui_print_header(undef, $text{'error'}, "");
			print &ui_alert_box("$body", 'warn', undef, 1, $title);
			&ui_print_footer("javascript:history.back()",
				$text{'error_previous'});
			exit(99);
			}
		}
	return;
	}
}

# check_licence_expired()
# Returns 0 if the licence is valid, 1 if not, or 2 if could not be checked,
# 3 if expired, the expiry date, error message, number of domain, number
# of servers, and auto-renewal flag
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
	$licence{'err'} || $licence{'warn'}, $licence{'doms'}, $licence{'servers'},
	$licence{'autorenew'}, $licence{'time'}, $licence{'bind'},
	$licence{'subscription'});
}

# update_licence_from_site(&licence)
# Attempts to validate the license, and updates the given hash ref with
# license details.
sub update_licence_from_site
{
my ($licence) = @_;
my $lastpost = $config{'lastpost'};
return if (defined($licence->{'last'}) && $licence->{'status'} == 0 &&
	   $lastpost && time() - $lastpost < 60*60*60);
my ($status, $expiry, $err, $doms, $servers, $max_servers, $autorenew,
    $state, $subscription) = &check_licence_site();
my  %state = &licence_state();
$licence->{'last'} = $licence->{'time'} = time();
delete($licence->{'warn'});
if ($status == 2) {
	# Networking / CGI error. Don't treat this as a failure unless we have
	# seen it for at least 2 days
	$licence->{'lastdown'} ||= time();
	my $diff = time() - $licence->{'lastdown'};
	if ($diff < 2*24*60*60) {
		# A short-term failure - don't change anything
		$licence->{'warn'} = $err;
		return;
		}
	}
else {
	delete($licence->{'lastdown'});
	}
$licence->{'status'} = $status;
$licence->{'bind'} = $licence->{'time'} if (!$licence->{'bind'} && $status >= 1);
delete($licence->{'bind'}) if (defined($status) && $status == 0);
$licence->{'expiry'} = $expiry;
$licence->{'autorenew'} = $autorenew;
delete($licence->{'time'}) unless ($state{$state} && $state{$state} >= $servers);
$licence->{'subscription'} = $subscription;
$licence->{'err'} = $err;
if (defined($doms)) {
	# Only store the max domains if we got something valid back
	$licence->{'doms'} = $doms;
	}
if (defined($servers)) {
	# Same for servers
	$licence->{'used_servers'} = $servers;
	$licence->{'servers'} = $max_servers;
	}
}

# check_licence_site()
# Calls the function to actually validate the licence, which must return 0 if
# valid, 1 if not, or 2 if could not be checked, 3 if expired, the expiry
# date, any error message, the max number of domains, number of servers,
# maximum servers, and the auto-renewal flag
sub check_licence_site
{
return (0) if (!&require_licence());
local $id = &get_licence_hostid();

my %serial;
&read_env_file($virtualmin_license_file, \%serial);

local ($status, $expiry, $err, $doms, $max_servers, $servers, $autorenew,
       $state, $subscription) =
		&licence_scheduled($id, undef, undef, &get_vps_type());
if (defined($status) && $status == 0 && $doms) {
	# A domains limit exists .. check if we have exceeded it
	local @doms = grep { !$_->{'alias'} &&
			     !$_->{'defaultdomain'} } &list_domains();
	if (@doms > $doms) {
		$status = 1;
		$err = &text('licence_maxdoms', $doms, scalar(@doms));
		}
	}
if (defined($status) && $status == 0 && $max_servers && !$err) {
	# A servers limit exists .. check if we have exceeded it
	if ($servers > $max_servers) {
		$status = 1;
		$err = &text('licence_maxservers2', $max_servers,
			"<span data-maxservers='$servers'>$servers</span>",
			"<tt>$serial{'SerialNumber'}</tt>");
		}
	}
return ($status, $expiry, $err, $doms, $servers, $max_servers,
        $autorenew, $state, $subscription);
}

# get_licence_hostid()
# Return a host ID for licence checking, from the hostid command or
# MAC address or hostname
sub get_licence_hostid
{
my $id;
my $product_uuid_file = "/sys/class/dmi/id/product_uuid";
my $product_serial_file = "/sys/class/dmi/id/product_serial";
my $product_file = -f $product_uuid_file ? $product_uuid_file : 
           	  (-f $product_serial_file ? $product_serial_file : undef);
if ($product_file) {
	$id = &read_file_contents($product_file);
	$id =~ /(?<id>([0-9a-fA-F]\s*){8})/;
	$id = $+{id};
	$id =~ s/\s+//g;
	return lc($id) if ($id);
	}
if (&has_command("hostid")) {
	$id = &backquote_command("hostid 2>/dev/null");
	chop($id);
	}
if (!$id || $id =~ /^0+$/ || $id eq '7f0100') {
	&foreign_require("net");
	local ($iface) = grep { $_->{'fullname'} eq $config{'iface'} }
			      &net::active_interfaces();
	$id = $iface->{'ether'} if ($iface);
	}
if (!$id) {
	$id = &get_system_hostname();
	}
return $id;
}

# get_vps_type()
# If running under some kind of VPS, return a type code for it. This can be
# one of 'xen', 'vserver', 'zones' or undef for none.
sub get_vps_type
{
return defined(&running_in_zone) && &running_in_zone() ? 'zones' :
       defined(&running_in_vserver) && &running_in_vserver() ? 'vserver' :
       defined(&running_in_xen) && &running_in_xen() ? 'xen' : undef;
}

# warning_messages()
# Returns HTML for an error messages such as the licence being expired, if it
# is and if the current user is the master admin. Also warns about IP changes,
# need to reboot, etc.
sub warning_messages
{
my $rv;
foreach my $warn (&list_warning_messages()) {
	$rv .= &ui_alert_box($warn, "warn");
	}
return $rv;
}

# list_warning_messages()
# Returns all warning messages for the current user as an array
sub list_warning_messages
{
return () if (!&master_admin());
my @rv;
my $wp = &get_webprefix_safe();
# Get licence expiry date
local ($status, $expiry, $err, undef, undef, $autorenew, $state, $bind) =
	&check_licence_expired();
local $expirytime;
if ($expiry =~ /^(\d+)\-(\d+)\-(\d+)$/) {
	# Make Unix time
	eval {
		$expirytime = timelocal(59, 59, 23, $3, $2-1, $1);
		};
	}
if ($status != 0 && !$state) {
	my $license_expired = $status == 3 ? 'e' : undef;
	my $scale = 1;
	$scale = 3 if ($license_expired);
	my $alert_text;
	# Not valid .. show message
	if ($bind) {
		my $prd = 21/$scale;
		$bind = int(($bind-time())/86400)+$prd;
		$bind = 0 if ($bind < 0 || $bind > $prd);
		}
	$alert_text .= "<b>".$text{'licence_err'}."</b><br>\n";
	$alert_text .= $err;
	$alert_text = "$alert_text. " if ($err && $err !~ /\.$/);
	my $renew_label = "licence_renew4$license_expired";
	if ($bind) {
		my $multi = $bind > 1 ? 'm' : '';
		if ($license_expired) {
			$alert_text .= " ".
			    &text("licence_renew3$license_expired$multi", $bind); 
			}
		else {
			$alert_text .= " $text{'licence_maxwarn'}";
			$alert_text .= " ".&text("licence_renew3$multi", $bind); 
			}
		}
	else {
		$alert_text .= " ".$text{$renew_label} if (defined($bind));
		$alert_text .= " $text{'licence_maxwarn'}" if (!defined($bind));
		}
	if ($alert_text !~ /$virtualmin_renewal_url/) {
		$alert_text .= " ".&text('licence_renew2', 
			$virtualmin_renewal_url, $text{'license_shop_name'});
		}
	if (&can_recheck_licence()) {
		$alert_text .= &ui_form_start("$wp/$module_name/pro/licence.cgi");
		$alert_text .= &ui_submit($text{'licence_manager_goto'});
		$alert_text .= &ui_form_end();
		}
	$alert_text =~ s/\s+/ /g;
	push(@rv, $alert_text);
	}
elsif ($expirytime && $expirytime - time() < 7*24*60*60 && !$autorenew) {
	# One week to expiry .. tell the user
	local $days = int(($expirytime - time()) / (24*60*60));
	local $hours = int(($expirytime - time()) / (60*60));
	if ($days) {
		$alert_text .= "<b>".&text('licence_soon', $days)."</b><br>\n";
		}
	else {
		$alert_text .= "<b>".&text('licence_soon2', $hours)."</b><br>\n";
		}
	$alert_text .= " ".&text('licence_renew', $virtualmin_renewal_url,
			     $text{'license_shop_name'});
	if (&can_recheck_licence()) {
		$alert_text .= &ui_form_start("$wp/$module_name/pro/licence.cgi");
		$alert_text .= &ui_submit($text{'licence_manager_goto'});
		$alert_text .= &ui_form_end();
		}
	$alert_text =~ s/\s+/ /g;
	push(@rv, $alert_text);
	}

# Check if default IP has changed
local $defip = &get_default_ip();
if ($config{'old_defip'} && $defip && $config{'old_defip'} ne $defip) {
	my $alert_text;
	$alert_text .= "<b>".&text('licence_ipchanged',
			   "<tt>$config{'old_defip'}</tt>",
			   "<tt>$defip</tt>")."</b><p>\n";
	$alert_text .= &ui_form_start("$wp/$module_name/edit_newips.cgi");
	$alert_text .= &ui_hidden("old", $config{'old_defip'});
	$alert_text .= &ui_hidden("new", $defip);
	$alert_text .= &ui_hidden("setold", 1);
	$alert_text .= &ui_hidden("also", 1);
	$alert_text .= &ui_submit($text{'licence_changeip'});
	$alert_text .= &ui_form_end();
	push(@rv, $alert_text);
	}

# Check if in SSL mode, and SSL cert is < 2048 bits
local $small;
if ($ENV{'HTTPS'} eq 'ON') {
	local %miniserv;
	&get_miniserv_config(\%miniserv);
	local $certfile = $miniserv{'certfile'} || $miniserv{'keyfile'};
	if ($certfile) {
		local $cert = &cert_file_info($certfile);
		if ($cert->{'algo'} eq 'rsa' && $cert->{'size'} && $cert->{'size'} < 2048) {
			# Too small!
			$small = $cert;
			}
		}
	}
if ($small) {
	my $alert_text;
	local $msg = $small->{'issuer_c'} eq $small->{'c'} &&
		     $small->{'issuer_o'} eq $small->{'o'} ?
			'licence_smallself' : 'licence_smallcert';
	$alert_text .= &text($msg,
			   $small->{'size'},
			   "<tt>$small->{'cn'}</tt>",
			   $small->{'issuer_o'},
			   $small->{'issuer_cn'},
			   )."<p>\n";
	my $formlink = "$wp/webmin/edit_ssl.cgi";
	my $domid = &get_domain_by('dom', $small->{'cn'});
	if ($domid) {
		$formlink = "$wp/$module_name/cert_form.cgi?dom=$domid";
		}
	$alert_text .= &ui_form_start($formlink);
	$alert_text .= &ui_hidden("mode", $msg eq 'licence_smallself' ?
					'create' : &is_acme_cert($small) ?
							'lets' : 'csr');
	$alert_text .= &ui_submit($msg eq 'licence_smallself' ?
				$text{'licence_newcert'} :
				$text{'licence_newcsr'});
	$alert_text .= &ui_form_end();
	push(@rv, $alert_text);
	}

# Check if symlinks need to be fixed. Blank means not checked yet, 0 means
# fixed, 1 means don't fix.
if ($config{'allow_symlinks'} eq '') {
	my $alert_text;
	# Do any domains have unsafe settings?
	local @fixdoms = &fix_symlink_security(undef, 1);
	if (@fixdoms) {
		$alert_text .= "<b>".&text('licence_fixlinks', scalar(@fixdoms))."<p>".
		             $text{'licence_fixlinks2'}."</b><p>\n";
		$alert_text .= &ui_form_start(
			"$wp/$module_name/fix_symlinks.cgi");
		$alert_text .= &ui_submit($text{'licence_fixlinksok'}, undef);
		$alert_text .= &ui_submit($text{'licence_fixlinksignore'}, 'ignore');
		$alert_text .= &ui_form_end();
		push(@rv, $alert_text);
		}
	else {
		# All OK already, don't check again
		$config{'allow_symlinks'} = 0;
		&lock_file($module_config_file);
		&save_module_config();
		&unlock_file($module_config_file);
		}
	}

# Suggest that the user switch themes to authentic
my @themes = &list_themes();
my ($theme) = grep { $_->{'dir'} eq $recommended_theme } @themes;
if ($theme && $current_theme !~ /$recommended_theme/ &&
    !$config{'theme_switch_'.$recommended_theme}) {
	my $switch_text;
	$switch_text .= "<b>".&text('index_themeswitch',
				    $theme->{'desc'})."</b><p>\n";
	$switch_text .= &ui_form_start(
		"$wp/$module_name/switch_theme.cgi");
	$switch_text .= &ui_submit($text{'index_themeswitchok'});
	$switch_text .= &ui_submit($text{'index_themeswitchnot'}, "cancel");
	$switch_text .= &ui_form_end();
	push(@rv, $switch_text);
	}

# Check for expired SSL certs (if enabled)
my (@expired, @nearly);
my $now = time();
foreach my $d (&list_domains()) {
	next if (!$d->{'ssl_cert_expiry'});
	next if ($d->{'disabled'});

	# Check if cached cert file time is valid
	my @st = stat($d->{'ssl_cert'});
	next if (!@st);
	next if ($d->{'ssl_cert_expiry_cache'} != $st[9]);

	# Skip this if the cert isn't being used
	next if (!&domain_has_ssl_cert($d));
	my $anyuse;
	$anyuse++ if (&domain_has_ssl($d));
	if (!$anyuse) {
		my @svcs = &get_all_domain_service_ssl_certs($d);
		$anyuse++ if (@svcs);
		}
	next if (!$anyuse);

	# Check if at or near expiry
	if ($d->{'ssl_cert_expiry'} < $now) {
		push(@expired, $d);
		}
	elsif ($d->{'ssl_cert_expiry'} < $now + 24*60*60) {
		push(@nearly, $d);
		}
	}
if (@expired || @nearly) {
	my $exp;
	my $cert_text = "<b>$text{'index_certwarn'}</b><p>\n";
	if (@expired) {
		$cert_text .= &text('index_certexpired',
				    &domain_ssl_page_links(\@expired));
		$exp++;
		}
	if (@nearly) {
		my $nl = $exp ? "<br>" : "";
		$cert_text .= $nl . &text('index_certnearly',
				    &domain_ssl_page_links(\@nearly));
		}
	push(@rv, $cert_text);
	}

# Check for invalid SSL cert files
my @badcert;
foreach my $d (&list_domains()) {
	next if (!&domain_has_ssl_cert($d));
	my $cerr = &validate_cert_format($d->{'ssl_cert'}, 'cert');
	my $kerr = &validate_cert_format($d->{'ssl_key'}, 'key');
	if ($cerr) {
		push(@rv, &text('index_certinvalid', &show_domain_name($d),
			"<tt>".&html_escape($d->{'ssl_cert'})."</tt>", $cerr));
		}
	elsif ($kerr) {
		push(@rv, &text('index_keyinvalid', &show_domain_name($d),
			"<tt>".&html_escape($d->{'ssl_key'})."</tt>", $kerr));
		}
	}

# Check for impending domain registrar expiry
my (@expired, @nearly);
foreach my $d (&list_domains()) {
	next if (!$d->{'whois_expiry'} || !$d->{'dns'});
	next if ($d->{'disabled'});
	next if ($d->{'whois_ignore'});

	# If status collection is disabled and last
	# config check was done a long time ago or if
	# already expired and next hasn't been updated
	# for the passed half an hour, then skip it
	# considering current records to be stale	
	my $nocoll = $config{'collect_interval'} eq 'none' ? 1 : 0;
	if ($d->{'whois_next'}) {
		if ($nocoll && $now > $d->{'whois_next'} ||
		    $nocoll && $config{'last_check'} > $d->{'whois_next'} ||
		    $config{'whois_expiry'} < $now &&
		      $now > $d->{'whois_next'} + 1800) {
			next;
			}
		}

	# Tell if domain is already expired
	if ($d->{'whois_expiry'} < $now) {
		push(@expired, $d);
		}
	# Warn 7 days before domain expiry
	elsif ($d->{'whois_expiry'} < $now + 7*24*60*60) {
		push(@nearly, $d);
		}
	}
if (@expired || @nearly) {
	my $exp;
	if (@expired) {
		my $gluechar = ", ";
		if (scalar(@expired) == 1) {
			$gluechar = "";
			}
		$expiry_text .= &text('index_expiryexpired',
			join($gluechar, map { "<a href=\"$wp/$module_name/summary_domain.cgi?dom=$_->{'id'}\">@{[&show_domain_name($_)]}</a>" } @expired));
		$exp++;
		}
	if (@nearly) {
		my $gluechar = ", ";
		if (scalar(@nearly) == 1) {
			$gluechar = "";
			}
		my $nl = $exp ? "<br>" : "";
		$expiry_text .= $nl . &text('index_expirynearly',
			join($gluechar, map { "<a href=\"$wp/$module_name/summary_domain.cgi?dom=$_->{'id'}\">@{[&show_domain_name($_)]}</a>" } @nearly));
		}
	if (@expired || @nearly) {
		my @edoms;
		push(@edoms, map { $_->{'dom'} } @expired) if (@expired);
		push(@edoms, map { $_->{'dom'} } @nearly) if (@nearly);
		@edoms = &unique(@edoms);
		my $expiry_form .= &ui_form_start(
			"$wp/$module_name/recollect_whois.cgi");
		$expiry_form .= &ui_hidden("doms", join(" ", @edoms))."\n".
		$expiry_form .= &ui_submit($text{'index_drefresh'});
		$expiry_form .= &ui_submit($text{'index_dignore'}, "ignore");
		$expiry_form .= &ui_form_end();
		$expiry_text .= $expiry_form;
		}
	push(@rv, $expiry_text);
	}

# Check for active but un-used mod_php
if (&master_admin() && !$config{'mod_php_ok'} && $config{'web'} &&
    &get_apache_mod_php_version()) {
	# Available, but is it used?
	my $count = 0;
	foreach my $d (&list_domains()) {
		if ($d->{'php_mode'} && $d->{'php_mode'} eq 'mod_php') {
			$count++;
			}
		}
	if (!$count) {
		my $mod_text = &text('index_disable_mod_php')."<p>\n";
		$mod_text .= &ui_form_start(
			"$wp/$module_name/disable_mod_php.cgi");
		$mod_text .= &ui_submit($text{'index_disable_mod_phpok'});
		$mod_text .= &ui_submit($text{'index_themeswitchnot'}, "cancel");
		$mod_text .= &ui_form_end();
		push(@rv, $mod_text);
		}
	}

# Check for S3 backups when there is no S3 command
if (&master_admin() && !&has_aws_cmd()) {
	my $s3 = 0;
	foreach my $sched (&list_scheduled_backups()) {
		foreach my $dest (&get_scheduled_backup_dests($sched)) {
			my ($proto) = &parse_backup_url($dest);
			$s3++ if ($proto == 3);
			}
		}
	if ($s3) {
		push(@rv, $text{'s3_need_cli2'}."\n".&text('s3_need_cli3', 'install_awscli.cgi'));
		}
	}

# If virus scanning is enabled, make sure clamdscan is being used
if ($config{'virus'} && !$config{'provision_virus_host'} &&
    &get_global_virus_scanner() eq 'clamscan') {
	my $clam_text = $text{'index_warn_clamscan'}."<p>\n";
	$clam_text .= &ui_form_start(
		"$wp/$module_name/edit_newsv.cgi");
	$clam_text .= &ui_submit($text{'index_disable_clamscan'});
	$clam_text .= &ui_form_end();
	push(@rv, $clam_text);
	}

# If Apache is in use, make sure the config is valid
if ($config{'web'}) {
	&require_apache();
	my $err = &apache::test_config();
	if ($err) {
		my @elines = split(/\r?\n/, $err);
		@elines = grep { !/\[warn\]/ } @elines;
		$err = join("\n", @elines);
		}
	if ($err) {
		my $err_text = $text{'index_warn_apacheconf'}."<p>\n";
		$err_text .= "<pre>".&html_escape($err)."</pre>\n";
		push(@rv, $err_text);
		}
	}

# If BIND is in use, make sure the config is valid
if ($config{'dns'}) {
	&require_bind();
	my @errs = &bind8::check_bind_config();
	if (@errs) {
		my $err_text = $text{'index_warn_bindconf'}."<p>\n";
		$err_text .= "<pre>".&html_escape(join("\n", @errs))."</pre>\n";
		push(@rv, $err_text);
		}
	}

return @rv;
}

sub domain_ssl_page_links
{
my ($doms) = @_;
return join(" ", map { &ui_link("@{[&get_webprefix_safe()]}/$module_name/cert_form.cgi?dom=$_->{'id'}",
				&show_domain_name($_)) } @$doms);
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
		if ($uinfo[7] =~ /^\Q$d->{'home'}\E\/homes\// ||
		    ($d->{'user'} eq $uinfo[0] && !$d->{'parent'})) {
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
# in the group quota for home, it is subtracted. All quotas are in blocks.
sub get_domain_quota
{
local ($d, $dbtoo) = @_;
local ($home, $mail, $db, $dbq);
if (&has_group_quotas()) {
	# Query actual group quotas
	my @groups = &list_all_groups_quotas(0);
	my ($group) = grep { $_->{'group'} eq $d->{'group'} } @groups;
	if ($group) {
		$home = $group->{'uquota'};
		if (&has_mail_quotas()) {
			$mail = $group->{'umquota'};
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
return ($home >= $dbq ? $home-$dbq : $home, $mail, $db);
}

# check_domain_over_quota(&domain)
# If a virtual server is over quota, return an error message
sub check_domain_over_quota
{
my ($d) = @_;
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	return &check_domain_over_quota($parent);
	}
if (&has_group_quotas()) {
	# Check server group quota
	my $bsize = &quota_bsize("home");
	my ($homequota, $mailquota) = &get_domain_quota($d);
	if ($d->{'quota'} && $homequota >= $d->{'quota'}) {
		return &text('setup_overgroupquota',
			     &nice_size($d->{'quota'}*$bsize),
			     &show_domain_name($d));
		}
	}
if (&has_home_quotas()) {
	# Check domain owner user
	my $bsize = &quota_bsize("home");
	my ($homequota, $mailquota, $duser, $dbquota, $dbquota_home) =
		&get_domain_user_quotas($d);
	if ($d->{'uquota'} && $duser->{'uquota'} >= $d->{'uquota'}) {
		return &text('setup_overuserquota',
			     &nice_size($d->{'uquota'}*$bsize),
			     $duser->{'user'});
		}
	}
return undef;
}

# compute_prefix(domain-name, group, [&parent], [creating-flag])
# Given a domain name, returns the prefix for usernames
sub compute_prefix
{
local ($name, $group, $parent, $creating) = @_;
my $config_longname = $config{'longname'};
if ($config_longname != 1) {
	$name =~ s/^xn(-+)//;	# Strip IDN part
	}
if ($config_longname == 1) {
	# Prefix is same as domain name
	return $name;
	}
elsif ($group && !$parent && !$config_longname) {
	# For top-level domains, prefix is same as group name (but append a
	# number if there's a clash)
	my $rv = $group;
	if ($creating) {
		my $sfx;
		while(&get_domain_by("prefix", $rv)) {
			$sfx++;
			$rv = $group.$sfx;
			}
		}
	return $rv;
	}
else {
	# Otherwise, prefix comes from first part of domain. If this clashes,
	# use the second part too and so on
	local @p = split(/\./, $name);
	local $prefix;
	if ($creating) {
		# Extract prefix based on the user pattern
		if ($config_longname && $config_longname !~ /^[0-9]$/) {
			$prefix = &generate_random_available_user($config_longname);
			}
		else {
			# First try foo, then foo.com, then foo.com.au
			for(my $i=0; $i<@p; $i++) {
				local $testp = join("-", @p[0..$i]);
				local $pclash = &get_domain_by("prefix", $testp);
				if (!$pclash) {
					$prefix = $testp;
					last;
					}
				}
			# If none of those worked, append a number
			if (!$prefix) {
				my $i = 1;
				while(1) {
					local $testp = $p[0].$i;
					local $pclash = &get_domain_by("prefix",$testp);
					if (!$pclash) {
						$prefix = $testp;
						last;
						}
					$i++;
					}
				}
			}
		}
	return $prefix || $p[0];
	}
}

# get_domain_owner(&domain, [skip-virts, [skip-quotas, skip-dbs]])
# Returns the Unix user object for a server's owner. Quota, DB and virtuser
# details will be omitted if the skip flag is set.
sub get_domain_owner
{
local ($d, $novirts, $noquotas, $nodbs) = @_;
$noquotas = $novirts if (!defined($noquotas));
$nodbs = $novirts if (!defined($nodbs));
if ($d->{'parent'}) {
	local $parent = &get_domain($d->{'parent'});
	if ($parent) {
		return &get_domain_owner($parent, $novirts, $noquotas, $nodbs);
		}
	return undef;
	}
else {
	local @users = &list_domain_users($d, 0, $novirts, $noquotas, $nodbs);
	local ($user) = grep { $_->{'user'} eq $_[0]->{'user'} } @users;
	return $user;
	}
}

# get_domain_shell(&domain, [&user])
# Return the real shell for a domain's unix user
sub get_domain_shell
{
my ($d, $user) = @_;
# Switch to parent domain if this is a sub-server
$d = &get_domain($d->{'parent'}) if ($d->{'parent'});
$user ||= &get_domain_owner($d, 1, 1, 1);
if ($user->{'shell'} =~ /\/jk_chrootsh$/) {
	return $user->{'jailed'}->{'shell'};
	}
else {
	return $user->{'shell'};
	}
}

# change_domain_shell(&domain, shell-path)
# Change the shell for a domain user, taking chroot into account
sub change_domain_shell
{
my ($d, $shell) = @_;
my $user = &get_domain_owner($d);
my $olduser = { %$user };
$user->{'shell'} = $shell;
&modify_user($user, $olduser, $d);
}

# can_domain_shell_login(&domain)
# Can the domain's shell be used to run commands?
sub can_domain_shell_login
{
my ($d) = @_;
my $shellpath = &get_domain_shell($d);
return 0 if (!$shellpath);
my @ashells = &list_available_shells($d);
my ($shell) = grep { $_->{'shell'} eq $shellpath } @ashells;
return $shell && $shell->{'id'} eq 'ssh';
}

# new_password_input(name)
# Returns HTML for a password selection field
sub new_password_input
{
local ($name) = @_;
if ($config{'passwd_mode'} == 1) {
	# Random but editable password
	return &vui_noauto_textbox($name, &random_password(), 21);
	}
elsif ($config{'passwd_mode'} == 0) {
	# One hidden password
	return &vui_noauto_password($name, undef, 21);
	}
elsif ($config{'passwd_mode'} == 2) {
	# Two hidden passwords
	return "<div style='display: inline-grid;'>".
	          &vui_noauto_password($name, undef, undef, 0, undef,
	              " placeholder='$text{'form_passf'}'").
	          &vui_noauto_password($name."_again", undef, undef, 0, undef,
	              " data-password-again placeholder='$text{'form_passa'}'")."</div>\n";
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
	      &plugin_defined($_, "feature_disable") } &list_feature_plugins());
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
		     &plugin_defined($_, "feature_enable") } &list_feature_plugins());
return &unique(@enable);
}

# get_python_version([path])
# Return current Python version, if instaled
sub get_python_version
{
my ($python_pathpath) = @_;
$python_pathpath ||= get_python_path();
my $python_version;
my $out = &backquote_command("$python_pathpath --version 2>&1", 1);
$python_version = $1 if ($out =~ /Python\s+(.*)/i);
return $python_version;
}

# get_usermin_version()
# Return current Usermin version, if instaled
sub get_usermin_version
{
return 0 if (!&foreign_check("usermin"));
&foreign_require("usermin");
return &usermin::get_usermin_version();
}

# sysinfo_virtualmin()
# Returns the OS info, Perl version and path
sub sysinfo_virtualmin
{
my @sysinfo_virtualmin;

# OS and Perl info
if ($main::sysinfo_virtualmin_self) {

	# Add Webmin version; add Usermin version, if installed
	my %systemstatustext = &load_language('system-status');
	push(@sysinfo_virtualmin,
	    [ $systemstatustext{'right_webmin'}, &get_webmin_version() ] );
	my $um_ver = &get_usermin_version();
	if ($um_ver) {
		push(@sysinfo_virtualmin,
	        [ $systemstatustext{'right_usermin'}, $um_ver ] );
		}

	# Add Virtualmin version
	push(@sysinfo_virtualmin,
	    [ $text{'right_virtualmin'}, &get_module_version_and_type() ] );

	# Add Cloudmin version, if installed
	if (&foreign_installed("server-manager")) {
		&foreign_require("server-manager");
		if (defined(&server_manager::get_module_version_and_type)) {
			my $cm_ver = &server_manager::get_module_version_and_type();
			if ($cm_ver) {
				my %cmtext = &load_language('server-manager');
				push(@sysinfo_virtualmin,
				    [ $cmtext{'right_vm2'}, $cm_ver ] );
				}
			}
		}
	}
my @basic_info;
if (!&master_admin() && !$main::sysinfo_virtualmin_self) {
	push(@basic_info,
	    ( [ $text{'sysinfo_os'}, "$gconfig{'real_os_type'} $gconfig{'real_os_version'}" ] ) );
	}

push(@basic_info,
    ( [ $text{'sysinfo_perl'}, $] ],
      [ $text{'sysinfo_perlpath'}, &get_perl_path() ] ) );

push(@sysinfo_virtualmin, @basic_info);

# Python, if exists
my $python_version = &get_python_version();
if ($python_version) {
	push(@sysinfo_virtualmin,
         [ $text{'sysinfo_python'}, $python_version ],
         [ $text{'sysinfo_pythonpath'}, &get_python_path() ]);
	}
return @sysinfo_virtualmin;
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

# has_quotacheck()
# Returns 1 if the home or mail filesystems support quota checking
sub has_quotacheck
{
&foreign_require("mount");
my @mounted = &mount::list_mounted();
my ($hm) = grep { $_->[0] eq $config{'home_quotas'} } @mounted;
return 1 if ($hm && $hm->[2] ne 'xfs');
if ($config{'mail_quotas'}) {
	my ($mm) = grep { $_->[0] eq $config{'mail_quotas'} } @mounted;
	return 1 if ($mm && $mm->[2] ne 'xfs');
	}
return 0;
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
foreach my $db (&domain_databases($d, [ 'mysql', 'postgres' ])) {
	local ($size, undef, $qsize) = &get_one_database_usage($d, $db);
	$rv += $size;
	$qrv += $qsize;
	}
return wantarray ? ($rv, $qrv) : $rv;
}

# get_one_database_usage(&domain, &db)
# Returns the disk space used by one database, the table count, the amount of
# space that is already counted by the quota system, and the file count.
sub get_one_database_usage
{
local ($d, $db) = @_;
if ($db->{'type'} eq 'mysql' || $db->{'type'} eq 'postgres') {
	# Get size from core database
	local $szfunc = $db->{'type'}."_size";
	local ($size, $tables, $qsize, $count) = &$szfunc($d, $db->{'name'}, 0);
	return ($size, $tables, $qsize, $count);
	}
else {
	# Get size from plugin
	local ($size, $tables, $qsize, $count) = &plugin_call($db->{'type'},
		      "database_size", $d, $db->{'name'}, 0);
	return ($size, $tables, $qsize, $count);
	}
}

# need_config_check()
# Compares the current and previous configs, and returns 1 if a re-check is
# needed due to any checked option changing.
sub need_config_check
{
local @cst = stat($module_config_file);
return 0 if ($cst[9] <= $config{'last_check'});
return 1 if ($mail_system == 5 || $mail_system == 6);
local %lastconfig;
&read_file("$module_config_directory/last-config", \%lastconfig) || return 1;
foreach my $f (@features) {
	# A feature was enabled or disabled
	return 1 if ($config{$f} != $lastconfig{$f});
	}
foreach my $c ("mail_system", "generics", "bccs", "append_style", "ldap_host",
	       "ldap_base", "ldap_login", "ldap_pass", "ldap_port", "ldap",
	       "clamscan_cmd", "iface", "netmask6", "localgroup", "home_quotas",
	       "mail_quotas", "group_quotas", "quotas", "shell", "ftp_shell",
	       "dns_ip", "default_procmail", "defaultdomain_name",
	       "compression", "pbzip2", "domains_group",
	       "quota_commands", "home_base",
	       "quota_set_user_command", "quota_set_group_command",
	       "quota_list_users_command", "quota_list_groups_command",
	       "quota_get_user_command", "quota_get_group_command",
	       "preload_mode", "collect_interval", "api_helper",
	       "spam_lock", "spam_white", "mem_low",
	       "lookup_domain_serial", "default_domain_ssl") {
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

# update_secondary_groups(&domain, [&users])
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

# Find FTP-capable shells
local %shellmap = map { $_->{'shell'}, $_->{'id'} } &list_available_shells();

foreach my $g ("mailgroup", "ftpgroup", "dbgroup") {
	local $gn = $tmpl->{$g};
	next if (!$gn || $gn eq "none");
	local @inusers;

	# Work out who is in the group
	if ($g eq "mailgroup") {
		@inusers = grep { $_->{'email'} } @$users;
		}
	elsif ($g eq "ftpgroup") {
		@inusers = grep { $shellmap{$_->{'shell'}} &&
				  $shellmap{$_->{'shell'}} ne 'nologin' }
				@$users;
		}
	elsif ($g eq "dbgroup") {
		@inusers = grep { @{$_->{'dbs'}} > 0 ||
			  $_->{'domainowner'} && $dom->{'mysql'} } @$users;
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

# compression_format(file, [&key])
# Returns 0 if uncompressed, 1 for gzip, 2 for compress, 3 for bzip2 or
# 4 for zip, 5 for tar, 6 for zstd
sub compression_format
{
local ($file, $key) = @_;
if ($key) {
	open(BACKUP, &backup_decryption_command($key)." ".
		     quotemeta($file)." 2>/dev/null |");
	}
else {
	open(BACKUP, "<".$file);
	}
local $two;
read(BACKUP, $two, 2);
close(BACKUP);
local $rv = $two eq "\037\213" ? 1 :
	    $two eq "\037\235" ? 2 :
	    $two eq chr(0x28).chr(0xB5) ? 6 :
	    $two eq "P*" ? 6 :
	    $two eq "PK" ? 4 :
	    $two eq "BZ" ? 3 : 0;
if (!$rv) {
	# Fall back to 'file' command for tar
	local $out = &backquote_command("file ".quotemeta($_[0]));
	if ($out =~ /tar\s+archive/i) {
		$rv = 5;
		}
	elsif ($out =~ /zstandard\s+compressed/i) {
		$rv = 6;
		}
	}
return $rv;
}

# extract_compressed_file(file, [destdir], [&dom])
# Extracts the contents of some compressed file to the given directory. Returns
# undef if OK, or an error message on failure.
# If the directory is not given, a test extraction is done instead.
sub extract_compressed_file
{
my ($file, $dir, $d) = @_;
my $format = &compression_format($file);
my $tar = &get_tar_command();
my $bunzip2 = &get_bunzip2_command();
my $unzstd = &get_unzstd_command();
my @needs = ( undef,
		 [ "gunzip", $tar ],
		 [ "uncompress", $tar ],
		 [ $bunzip2, $tar ],
		 [ "unzip" ],
		 [ "tar" ],
		 [ $unzstd ],
		);
foreach my $n (@{$needs[$format]}) {
	my ($noargs) = split(/\s+/, $n);
	&has_command($noargs) || return &text('addstyle_ecmd', "<tt>$n</tt>");
	}
my ($qfile, $qdir) = ( quotemeta($file), quotemeta($dir) );
my @cmds;
if ($dir) {
	# Actually extract
	@cmds = ( undef,
		  "cd $qdir && gunzip -c $qfile | ".
		    &make_tar_command("xf", "-"),
	  	  "cd $qdir && uncompress -c $qfile | ".
		    &make_tar_command("xf", "-"),
		  "cd $qdir && $bunzip2 -c $qfile | ".
		    &make_tar_command("xf", "-"),
		  "cd $qdir && unzip $qfile",
		  "cd $qdir && ".
		    &make_tar_command("xf", $file),
		  "cd $qdir && $unzstd -d -c $qfile | ".
		    &make_tar_command("xf", "-")
		  );
	}
else {
	# Just do a test listing
	@cmds = ( undef,
		  "gunzip -c $qfile | ".
		    &make_tar_command("tf", "-"),
	  	  "uncompress -c $qfile | ".
		    &make_tar_command("tf", "-"),
		  "$bunzip2 -c $qfile | ".
		    &make_tar_command("tf", "-"),
		  "unzip -l $qfile",
		  &make_tar_command("tf", $file),
		  "$unzstd --test $qfile",
		  );
	}
$cmds[$format] || return "Unknown compression format";
my $out;
if ($d) {
	# Run as domain owner
	$out = &run_as_domain_user($d, "($cmds[$format]) 2>&1 </dev/null");
	}
else {
	# Run as root
	$out = &backquote_command("($cmds[$format]) 2>&1 </dev/null");
	}
return $? ? &text('addstyle_ecmdfailed',
		  "<tt>".&html_escape($out)."</tt>") : undef;
}

# get_compressed_file_size(file, [&key])
# Returns the un-compressed size of a file in bytes, or undef if it cannot
# be determined
sub get_compressed_file_size
{
local ($file, $key) = @_;
return undef if ($key);	# Too expensive to decrypt and check
my $fmt = &compression_format($file, $key);
my @st = stat($file);
if ($fmt == 0) {
	# Not compressed at all
	return $st[7];
	}
elsif ($fmt == 1) {
	# Gzip compressed
	my $out = &backquote_command("gunzip -l ".quotemeta($file));
	return undef if ($?);
	return $out =~ /\d+\s+(\d+)\s+[0-9\.]+%/ ? $1 : undef;
	}
elsif ($fmt == 2) {
	# Classic compress - no idea how to handle
	return undef;
	}
elsif ($fmt == 3) {
	# Bzip2 compressed - no way to estimate
	return undef;
	}
elsif ($fmt == 4) {
	# Zip format - can sum up files
	my $out = &backquote_command("unzip -l ".quotemeta($file));
	return undef if ($?);
	my $rv = 0;
	foreach my $l (split(/\r?\n/, $out)) {
		if ($l =~ /^\s*(\d+)\s+(\d+-\d+-\d+)/) {
			$rv += $1;
			}
		}
	return $rv;
	}
elsif ($fmt == 5) {
	# TAR format doesn't compress
	return $st[7];
	}
return undef;
}

# features_sort(\@features_values, \@features_order)
#
# Sorts the elements in the array referenced by the first argument based on a
# predefined manual order of features. The second argument provides the
# corresponding features for each element in the first array, serving as a
# mapping between elements and their associated features.
#
# Parameters:
# - The first argument ($features_values) is a reference to an array of elements
#   to be sorted. These elements can be any data structures that represent
#   features but may not directly contain the feature identifiers.
# - The second argument ($features_order) is a reference to an array of feature
#   identifiers, where each feature corresponds to the element at the same index
#   in the first array. This array provides the necessary mapping to associate
#   each element with its feature.
#
# Behavior:
# - The function first creates a mapping of features to their corresponding
#   elements from the arrays provided.
# - It then sorts the elements whose features appear in the predefined manual
#   order (@order_manual), placing them first and in the exact order specified.
# - Elements whose features do not appear in @order_manual are considered
#   unordered and are placed after the ordered elements, maintaining their
#   original order.
# - The original array referenced by the first argument ($features_values) is
#   modified in-place to reflect the new sorted order.
#
# Notes:
# - The use of two separate arrays allows the function to sort elements that may
#   not directly contain their feature identifiers or are complex structures, by
#   using the mapping provided by the features array ($features_order).
# - This provides flexibility, as the elements to be sorted can be of any type,
#   as long as there is a corresponding feature for each element.
# - The function assumes that the features in @$features_order correspond
#   one-to-one with the elements in @$features_values.
sub features_sort
{
my ($features_values, $features_order) = @_;
my @order_manual =
   ('unix', 'dir',
    'dns', 'virtualmin-slavedns', 'virtualmin-powerdns',
    'web', 'ssl',
    'virtualmin-nginx', 'virtualmin-nginx-ssl',
    'mysql', 'postgres', 'virtualmin-sqlite', 'virtualmin-oracle',
    'mail', 'spam', 'virus',
    'virtualmin-mailrelay', 'virtualmin-mailman', 'virtualmin-signup',
    'logrotate',
    'status', 'webalizer',
    'webmin',
    'virtualmin-awstats',
    'virtualmin-notes', 'virtualmin-google-analytics',
    'virtualmin-init',
    'virtualmin-dav', 'virtualmin-registrar',
    'virtualmin-disable',
    'virtualmin-git', 'virtualmin-svn',
    'virtualmin-messageoftheday',
    'virtualmin-htpasswd',
    'ftp', 'virtualmin-vsftpd',
    'virtualmin-support',
    );
my @order_initial = @{$features_order};
my %ordered_;
my @ordered;
my @unordered;
foreach my $i (0 .. $#order_initial) {
	# Store all features
	$ordered_{$order_initial[$i]} = $features_values->[$i];

	# Unordered keys
	if (&indexof($order_initial[$i], @order_manual) < 0) {
		push(@unordered, $features_values->[$i]);
		}
	}

# Sort ordered based on manual sorting
foreach my $i (0 .. $#order_manual) {
	my $o = $ordered_{$order_manual[$i]};
	push(@ordered, $o) if ($o);
	}

# Combine both and modify original
my @ordered_combined = (@ordered, @unordered);
@$features_values = @ordered_combined;
}

# feature_links(&domain)
# Returns a list of links for editing specific features within a domain, such
# as the DNS zone, apache config and so on. Includes plugins.
sub feature_links
{
local ($d) = @_;
local @rv;

# Check cache for feature links
local $v = [ 'time' => $d->{'lastsave'},
	     'last_check' => $config{'last_check'},
	     'plugins' => \@plugins,
	     'features' => \@config_features ];
local $ckey = $d->{'id'}."-links-".$base_remote_user;
local $crv = &get_links_cache($ckey, $v);
my $modify_plugin_category = sub {
	my ($l) = @_;
	if ($l->{'mod'} =~ /virtualmin-(init|oracle|svn|git)/ ||
	    ($l->{'cat'} eq 'services' && $l->{'mod'} eq 'virtualmin-awstats')) {
		$l->{'cat'} = 'server';
		}
	elsif ($l->{'mod'} =~ /virtualmin-(mailman|mailrelay)/) {
		$l->{'cat'} = 'mail';
		}
	elsif ($l->{'mod'} =~ /virtualmin-(htpasswd|dav)/ ||
	       ($l->{'cat'} eq 'services' && $l->{'mod'} eq 'phpini') ||
	       ($l->{'cat'} eq 'services' && $l->{'mod'} eq 'virtualmin-nginx')) {
		$l->{'cat'} = 'web';
		}
	elsif ($l->{'mod'} eq 'virtualmin-slavedns') {
		$l->{'cat'} = 'dns';
		}
	elsif ($l->{'mod'} eq 'virtualmin-registrar') {
		$l->{'cat'} = 'dnsreg';
		}
	};
if ($crv) {
	return @$crv;
	}

# Links provided by features, like editing DNS records
foreach my $f (@features) {
	my $lfunc = "links_".$f;
	if ($d->{$f} && defined(&$lfunc)) {
		foreach my $l (&$lfunc($d)) {
			if (&foreign_available($l->{'mod'})) {
				$l->{'title'} ||= $l->{'desc'};
				push(@rv, $l);
				}
			}
		}
	my $lafunc = "links_always_".$f;
	if (defined(&$lafunc)) {
		foreach my $l (&$lafunc($d)) {
			if (&foreign_available($l->{'mod'})) {
				$l->{'title'} ||= $l->{'desc'};
				push(@rv, $l);
				}
			}
		}
	}

# Links provided by plugins, like Mailman mailing lists
foreach my $f (@plugins) {
	if ($d->{$f}) {
		foreach my $l (&plugin_call($f, "feature_links", $d)) {
			if (&foreign_available($l->{'mod'})) {
				$l->{'title'} ||= $l->{'desc'};
				$l->{'plugin'} = 1;
				&$modify_plugin_category($l);
				push(@rv, $l);
				}
			}
		}
	foreach my $l (&plugin_call($f, "feature_always_links", $d)) {
		if (&foreign_available($l->{'mod'})) {
			$l->{'title'} ||= $l->{'desc'};
			$l->{'plugin'} = 2;
			&$modify_plugin_category($l);
			push(@rv, $l);
			}
		}
	}

# Links to other Webmin modules, for domain owners
if (!&master_admin() && !&reseller_admin()) {
	local @ot;
	foreach my $k (keys %config) {
		if ($k =~ /^avail_(\S+)$/ &&
		    &indexof($1, @features) < 0 &&
		    &indexof($1, @plugins) < 0 &&
		    $1 !~ /(phpini|webminlog|filemin)/) {
			my $mod = $1;
			if (&foreign_available($mod)) {
				local %minfo = &get_module_info($mod);
				push(@ot, { 'mod' => $mod,
					    'page' => 'index.cgi',
					    'title' => $minfo{'desc'},
					    'desc' => $minfo{'desc'},
					    'cat' => 'webmin',
					    'other' => 1 });
				}
			}
		}
	@ot = sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @ot;
	push(@rv, @ot);
	}

&save_links_cache($ckey, $v, \@rv);
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

# Check cache for domain actions
local $v = [ 'time' => $d->{'lastsave'},
	     'last_check' => $config{'last_check'},
	     'plugins' => \@plugins,
	     'features' => \@config_features ];
local $ckey = $d->{'id'}."-actions-".$base_remote_user;
local $crv = &get_links_cache($ckey, $v);
if ($crv) {
	return @$crv;
	}

if (&can_domain_have_users($d) && &can_edit_users()) {
	# Users button
	push(@rv, { 'page' => 'list_users.cgi',
		    'title' => $text{'edit_users'},
		    'desc' => $text{'edit_usersdesc'},
		    'cat' => 'objects',
		    'icon' => 'group',
		    });
	}

if ($d->{'mail'} && $config{'mail'} && &can_edit_aliases() &&
    !$d->{'aliascopy'}) {
	# Mail aliases button
	push(@rv, { 'page' => 'list_aliases.cgi',
		    'title' => $text{'edit_aliases'},
		    'desc' => $text{'edit_aliasesdesc'},
		    'cat' => 'mail',
		    });
	}

if (&database_feature($d) && &can_edit_databases()) {
	# MySQL and PostgreSQL DBs button
	push(@rv, { 'page' => 'list_databases.cgi',
		    'title' => $text{'edit_databases'},
		    'desc' => $text{'edit_databasesdesc'},
		    'cat' => 'objects',
		    'icon' => 'database',
		  });
	}

if (&can_domain_have_scripts($d) && &can_edit_scripts()) {
	# Scripts button
	push(@rv, { 'page' => 'list_scripts.cgi',
		    'title' => $text{'edit_scripts'},
		    'desc' => $text{'edit_scriptsdesc'},
		    'cat' => 'objects',
		    'icon' => 'page_code',
		  });
	}

if (&can_rename_domains()) {
	# Rename domain button
	push(@rv, { 'page' => 'rename_form.cgi',
		    'title' => $text{'edit_rename'},
		    'desc' => $text{'edit_renamedesc'},
		    'cat' => 'server',
		    'icon' => 'comment_edit',
		  });
	}

if (&can_move_domain($d) && !$d->{'subdom'}) {
	# Move sub-server to different owner, or turn parent into sub
	push(@rv, { 'page' => 'move_form.cgi',
		    'title' => $text{'edit_move'},
		    'desc' => $d->{'parent'} ? $text{'edit_movedesc2'}
					     : $text{'edit_movedesc'},
		    'cat' => 'server',
		    'icon' => 'arrow_right',
		  });
	}

if (&can_transfer_domain($d)) {
	# Send server to another system
	push(@rv, { 'page' => 'transfer_form.cgi',
		    'title' => $text{'edit_transfer'},
		    'desc' => $text{'edit_transferdesc'},
		    'cat' => 'server',
		    'icon' => 'arrow_right',
		  });
	}

if ($d->{'parent'} && &can_create_sub_servers() ||
    !$d->{'parent'} && &can_create_master_servers()) {
	# Clone server
	push(@rv, { 'page' => 'clone_form.cgi',
		    'title' => $text{'edit_clone'},
		    'desc' => $text{'edit_clonedesc'},
		    'cat' => 'server',
		    'icon' => 'arrow_right',
		  });
	}

if (&can_config_domain($d) && $d->{'subdom'}) {
	# Turn sub-domain into sub-server
	push(@rv, { 'page' => 'unsub.cgi',
		    'title' => $text{'edit_unsub'},
		    'desc' => $text{'edit_unsubdesc'},
		    'cat' => 'server',
		    'icon' => 'arrow_right',
		  });
	}

if (&can_config_domain($d) && $d->{'alias'}) {
	# Turn alias server into sub-server
	push(@rv, { 'page' => 'unalias.cgi',
		    'title' => $text{'edit_unalias'},
		    'desc' => $text{'edit_unaliasdesc'},
		    'cat' => 'server',
		    'icon' => 'arrow_right',
		  });
	}

if (&can_change_ip($d) && !$d->{'alias'}) {
	# Change IP / port button
	push(@rv, { 'page' => 'newip_form.cgi',
		    'title' => $text{'edit_newip'},
		    'desc' => $text{'edit_newipdesc'},
		    'cat' => 'server',
		    'icon' => 'connect',
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

if ($d->{'dir'} && &can_edit_ssl() && !$d->{'alias'}) {
	# SSL options page button
	push(@rv, { 'page' => 'cert_form.cgi',
		    'title' => $text{'edit_catcert'},
		    'desc' => $text{'edit_certdesc'},
		    'cat' => 'server',
		  });
	}

if ($d->{'unix'} && &can_edit_limits($d) && !$d->{'alias'}) {
	# Domain limits button
	push(@rv, { 'page' => 'edit_limits.cgi',
		    'title' => $text{'edit_limits'},
		    'desc' => $text{'edit_limitsdesc'},
		    'cat' => 'server',
		  });
	}

if ($d->{'unix'} && defined(&supports_resource_limits) &&
    &supports_resource_limits() && &can_edit_res($d)) {
	# Resource limits button
	push(@rv, { 'page' => 'pro/edit_res.cgi',
		    'title' => $text{'edit_res'},
		    'desc' => $text{'edit_resdesc'},
		    'cat' => 'server',
		  });
	}

if (!$d->{'parent'} && &can_edit_admins($d)) {
	# Extra admins buttons
	push(@rv, { 'page' => 'list_admins.cgi',
		    'title' => $text{'edit_admins'},
		    'desc' => $text{'edit_adminsdesc'},
		    'cat' => 'server',
		  });
	}

if (!$d->{'parent'} && $d->{'webmin'} && &can_switch_user($d)) {
	# Button to switch to the domain's admin
	push(@rv, { 'page' => 'switch_user.cgi',
		    'title' => $text{'edit_switch'},
		    'desc' => $text{'edit_switchdesc'},
		    'cat' => 'server',
		    'target' => '_top',
		  });
	}

if (&domain_has_website($d) && !$d->{'alias'} && &can_edit_forward()) {
	# Proxying / frame forward configuration button
	local $mode = $d->{'proxy_pass_mode'} || $config{'proxy_pass'};
	local $psuffix = $mode == 2 ? "frame" : "proxy";
	push(@rv, { 'page' => $psuffix.'_form.cgi',
		    'title' => $text{'edit_'.$psuffix},
		    'desc' => $text{'edit_'.$psuffix.'desc'},
		    'cat' => 'web',
		  });
	}

if (&has_proxy_balancer($d) && &can_edit_forward()) {
	# Proxy balance editor
	push(@rv, { 'page' => 'list_balancers.cgi',
		    'title' => $text{'edit_balancer'},
		    'desc' => $text{'edit_balancerdesc'},
		    'cat' => 'web',
		  });
	}

# Alias and redirects editor
if (&has_web_redirects($d) && &can_edit_redirect() && !$d->{'alias'}) {
	push(@rv, { 'page' => 'list_redirects.cgi',
		    'title' => $text{'edit_redirects'},
		    'desc' => $text{'edit_redirectsdesc'},
		    'cat' => 'web',
		  });
	}

if (($d->{'spam'} && $config{'spam'} ||
     $d->{'virus'} && $config{'virus'}) && &can_edit_spam()) {
	# Spam/virus delivery button
	push(@rv, { 'page' => 'edit_spam.cgi',
		    'title' => $text{'edit_spamvirus'},
		    'desc' => $text{'edit_spamvirusdesc'},
		    'cat' => 'mail',
		  });
	}

if (&domain_has_website($d) && !$d->{'alias'}) {
	# Website / PHP options buttons
	if (&can_edit_phpmode()) {
		push(@rv, { 'page' => 'edit_website.cgi',
			    'title' => $text{'edit_website'},
			    'desc' => $text{'edit_websitedesc'},
			    'cat' => 'web',
			  });
		}
	if (&can_edit_phpmode() || &can_edit_phpver()) {
		push(@rv, { 'page' => 'edit_phpmode.cgi',
			    'title' => $text{'edit_php'},
			    'desc' => $text{'edit_phpdesc'},
			    'cat' => 'web',
			  });
		}
	}

if ($d->{'dns'} && !$d->{'dns_submode'} && $config{'dns'} &&
    &can_edit_dns($d)) {
	# DNS settings button
	push(@rv, { 'page' => 'edit_spf.cgi',
		    'title' => $text{'edit_spf'},
		    'desc' => $text{'edit_spfdesc'},
		    'cat' => 'dns',
		  });
	}

if (&can_edit_records($d)) {
	if ($d->{'dns'}) {
		# DNS edit records button
		push(@rv, { 'page' => 'list_records.cgi',
			    'title' => $text{'edit_records'},
			    'desc' => $text{'edit_recordsdesc'},
			    'cat' => 'dns',
			  });
		}
	elsif (!$d->{'subdom'}) {
		# DNS suggested records button
		push(@rv, { 'page' => 'view_records.cgi',
			    'title' => $text{'edit_viewrecords'},
			    'desc' => $text{'edit_viewrecordsdesc'},
			    'cat' => 'dns',
			  });
		}
	}

&require_mail();
if ($d->{'mail'} && $config{'mail'} && &can_edit_mail()) {
	# Email settings button
	push(@rv, { 'page' => 'edit_mail.cgi',
		    'title' => $text{'edit_mailopts'},
		    'desc' => $text{'edit_mailoptsdesc'},
		    'cat' => 'mail',
		  });
	}

if ($d->{'mail'} && !$d->{'alias'} && $config{'dkim_enabled'}) {
	# Per-domain DKIM page
	push(@rv, { 'page' => 'edit_domdkim.cgi',
		    'title' => $text{'edit_domdkim'},
		    'desc' => $text{'edit_domdkimdesc'},
		    'cat' => 'dns',
		  });
	}

# Button to show bandwidth graph
if ($config{'bw_active'} && &can_monitor_bandwidth($d)) {
	push(@rv, { 'page' => 'bwgraph.cgi',
		    'title' => $text{'edit_bwgraph'},
		    'desc' => $text{'edit_bwgraphdesc'},
		    'cat' => 'logs',
		  });
	}

# Button to show disk usage
if ($d->{'dir'} && !$d->{'parent'}) {
	push(@rv, { 'page' => 'usage.cgi',
		    'title' => $text{'edit_usage'},
		    'desc' => $text{'edit_usagehdesc'},
		    'cat' => 'logs',
		  });
	}

# Button to show mail logs
if ($virtualmin_pro && $config{'mail'} && $mail_system <= 1 &&
    &can_view_maillog($d) && $d->{'mail'}) {
	push(@rv, { 'page' => 'pro/maillog.cgi',
		    'title' => $text{'edit_maillog'},
		    'desc' => $text{'edit_maillogdesc'},
		    'cat' => 'logs',
		  });
	}

# Button to validate connectivity
if ($virtualmin_pro) {
	push(@rv, { 'page' => 'pro/connectivity.cgi',
		    'title' => $text{'edit_connect'},
		    'desc' => $text{'edit_connectdesc'},
		    'cat' => 'logs',
		  });
	}

# Link to edit excluded directories
if (!$d->{'alias'} && &can_edit_exclude()) {
	push(@rv, { 'page' => 'edit_exclude.cgi',
		    'title' => $text{'edit_exclude'},
		    'desc' => $text{'edit_excludedesc'},
		    'cat' => 'server',
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

if (&can_associate_domain($d)) {
	# Feature associate / disassociate button
	push(@rv, { 'page' => 'assoc_form.cgi',
		    'title' => $text{'edit_assoc'},
		    'desc' => $text{'edit_assocdesc'},
		    'cat' => 'server',
		  });
	}

if (&can_passwd()) {
	# Change password button
	push(@rv, { 'page' => 'edit_pass.cgi',
		    'title' => $text{'edit_changepass'},
		    'desc' => $text{'edit_changepassdesc'},
		    'cat' => 'server',
		  });
	}

if (&can_user_2fa()) {
	# Twofactor enroll button for the user
	push(@rv, { 'page' => 'edit_2fa.cgi',
		    'title' => $text{'edit_change2fa'},
		    'desc' => $text{'edit_change2fadesc'},
		    'cat' => 'server',
		  });
	}

if (&domain_has_website($d) && $d->{'dir'} && !$d->{'alias'} &&
    !$d->{'proxy_pass_mode'} &&
    $virtualmin_pro && &can_edit_html()) {
	# Edit web pages button
	push(@rv, { 'page' => 'pro/edit_html.cgi',
		    'title' => $text{'edit_html'},
		    'desc' => $text{'edit_htmldesc'},
		    'cat' => 'web',
		  });
	}

if ($d->{'dir'} && !$d->{'alias'} &&
    !$d->{'proxy_pass_mode'} && &foreign_available("filemin")) {
	# Link to file manager for HTML directory
	my $phd = &public_html_dir($d);
	my %faccess = &get_module_acl(undef, 'filemin');
	my @ap = split(/\s+/, $faccess{'allowed_paths'});
	if (@ap == 1) {
		if ($ap[0] eq '$HOME' &&
		    $base_remote_user eq $d->{'user'}) {
			$ap[0] = $d->{'home'};
			}
		$phd =~ s/^\Q$ap[0]\E//;
		}
	push(@rv, { 'page' => 'index.cgi?path='.&urlize($phd),
		    'mod' => 'filemin',
		    'title' => $text{'edit_filemin'},
		    'desc' => $text{'edit_filemindesc'},
		    'cat' => 'objects',
		    'icon' => 'page_edit',
		  });
	}

if (&foreign_available("xterm") &&
    !$d->{'alias'} && $d->{'unix'} && $d->{'user'} &&
    &can_domain_shell_login($d)) {
	# Link to Terminal for master admin
	push(@rv, { 'page' => 'index.cgi?user='.&urlize($d->{'user'}).
			      '&dir='.&urlize($d->{'home'}),
		    'mod' => 'xterm',
		    'title' => $text{'edit_terminal'},
		    'desc' => $text{'edit_terminaldesc'},
		    'cat' => 'objects',
		    'icon' => 'page_edit',
		  });
	}
&menu_link_pro_tips(\@rv, $d) if (!$virtualmin_pro);
&save_links_cache($ckey, $v, \@rv);
return @rv;
}

# get_all_domain_links(&domain)
# Returns a list of all links for a domain, including actions, feature links
# and custom links. Each has the following keys :
#  url - URL to link to
#  title - Short name for link
#  desc - Longer name for link (optional)
#  cat - Category code
#  catname - Category human-readable name
#  target - Frame to open in (right or _new), defaults to right
#  icon - Unique code for this link
sub get_all_domain_links
{
local ($d) = @_;
local @rv;

# Always start with edit/view link
my $canconfig = &can_config_domain($d);
local $vm = "/$module_name";
my $edit_title = $text{'edit_title'};
my $view_title = $text{'view_title'};
if ($d->{'parent'} && !$d->{'alias'}) {
	$edit_title = $text{'edit_title2'};
	$view_title = $text{'view_title2'};
	}
elsif ($d->{'parent'} && $d->{'alias'}) {
	$edit_title = $text{'edit_title3'};
	$view_title = $text{'view_title3'}
	}
push(@rv, { 'url' => $canconfig ? "$vm/edit_domain.cgi?dom=$d->{'id'}"
				: "$vm/view_domain.cgi?dom=$d->{'id'}",
	    'title' => $canconfig ? $edit_title : $view_title,
	    'cat' => 'objects',
	    'icon' => $canconfig ? 'edit' : 'view' });

# Add link to list sub-servers
if (!$d->{'parent'}) {
	push(@rv, { 'url' => $vm.'/search.cgi?field=parent&amp;what='.
			     &urlize($d->{'dom'}),
		    'title' => $text{'edit_psearch'},
		    'cat' => 'server',
		    'catname' => $text{'cat_server'} });
	}

# Add actions and links
foreach my $l (&get_domain_actions($d), &feature_links($d)) {
	if ($l->{'mod'}) {
		$l->{'url'} = "/$l->{'mod'}/$l->{'page'}";
		}
	else {
		$l->{'url'} = $l->{'urlpro'} || "$vm/$l->{'page'}".
			      "?dom=".$d->{'id'}."&amp;".
			      join("&amp;", map { $_->[0]."=".&urlize($_->[1]) }
                                            @{$l->{'hidden'}});
		}
	$l->{'catname'} ||= $text{'cat_'.$l->{'cat'}};
	push(@rv, $l);
	}
my %catmap = map { $_->{'catname'}, $_->{'cat'} } @rv;

# Add preview website link, proxied via Webmin
if (&domain_has_website($d) && &can_use_preview()) {
	local $pt = $d->{'web_port'} == 80 ? "" : ":$d->{'web_port'}";
	push(@rv, { 'url' => "/$module_name/".
		    	     "link.cgi/$d->{'ip'}/http://www.$d->{'dom'}$pt/",
		    'title' => $text{'links_website'},
		    'cat' => 'web',
		    'catname' => $text{'cat_services'},
		    'target' => '_new',
		  });
	}

# Add custom links
if (defined(&list_visible_custom_links)) {
	foreach my $l (&list_visible_custom_links($d)) {
		$l->{'title'} = $l->{'desc'};
		delete($l->{'desc'});
		$l->{'target'} = $l->{'open'} ? "_new" : "right";
		delete($l->{'open'});
		if (!$l->{'icon'}) {
			# Make a unique ID
			$l->{'icon'} = lc($l->{'title'});
			$l->{'icon'} =~ s/\s/_/g;
			}
		push(@rv, $l);
		# Pick a category code, based on a match by name with an
		# existing category or a lower-cased version of the category
		if ($l->{'catname'}) {
			$l->{'cat'} = $catmap{$l->{'catname'}} ||
				      lc($l->{'catname'});
			$l->{'cat'} =~ s/\s/_/g;
			}
		else {
			$l->{'cat'} = 'objects';
			$l->{'catname'} = $text{'cat_objects'};
			}
		$l->{'nosort'} = 1;
		}
	}

return @rv;
}

# domain_footer_link(&domain)
# Returns a link and text suitable for the footer function
sub domain_footer_link
{
local $base = "/".$module_name;
return &can_config_domain($_[0]) ?
	( "$base/edit_domain.cgi?dom=$_[0]->{'id'}", $text{'edit_return'} ) :
	( "$base/view_domain.cgi?dom=$_[0]->{'id'}", $text{'view_return'} );
}

# domain_redirect(&domain, [refresh-menu])
# Calls redirect to edit_domain.cgi or view_domain.cgi
sub domain_redirect
{
local ($d, $refresh) = @_;
&redirect("/$module_name/postsave.cgi?".
	  "dom=$d->{'id'}&refresh=$refresh");
}

# get_template_pages()
# Returns five array references, for template/reseller/etc links, titles,
# categories and codes
sub get_template_pages
{
local @tmpls = ( 'features', 'tmpl', 'plan', 'bw',
   $virtualmin_pro ? ( 'fields', 'links', 'ips', 'sharedips', 'dynip', 'resels',
		       'notify', 'scripts', )
		   : ( 'fields', 'ips', 'sharedips', 'scripts', 'dynip' ),
   'shells',
   $config{'spam'} || $config{'virus'} ? ( 'sv' ) : ( ),
   &has_home_quotas() && $virtualmin_pro ? ( 'quotas' ) : ( ),
   &has_home_quotas() && !&has_quota_commands() && &has_quotacheck() ?
	( 'quotacheck' ) : ( ),
   $virtualmin_pro ? ( 'mxs' ) : ( ),
   'validate', 'chroot', 'global',
   $virtualmin_pro ? ( ) : ( 'upgrade' ),
   $config{'mail'} && $mail_system == 0 ? ( 'postgrey' ) : ( ),
   $config{'mail'} ? ( 'dkim' ) : ( ),
   $config{'mail'} ? ( 'ratelimit' ) : ( ),
   'provision',
   $config{'mail'} ? ( 'autoconfig' ) : ( ),
   $config{'mail'} && $virtualmin_pro ? ( 'retention' ) : ( ),
   $virtualmin_pro ? ( 'smtpclouds' ) : ( ),
   $config{'mysql'} ? ( 'mysqls' ) : ( ),
   'dnsclouds',
   $virtualmin_pro ? ( 'remotedns' ) : ( ),
   $virtualmin_pro ? ( 'acmes' ) : ( ),
   );
local %tmplcat = (
	'features' => 'setting',
	'notify' => 'email',
	'sv' => 'email',
	'ips' => 'ip',
	'sharedips' => 'ip',
	'dynip' => 'ip',
	'mxs' => 'email',
	'quotas' => 'check',
	'validate' => 'check',
	'quotacheck' => 'check',
	'tmpl' => 'setting',
	'plan' => 'setting',
	'bw' => 'setting',
	'plugin' => 'setting',
	'scripts' => 'setting',
	'upgrade' => 'setting',
	'resels' => 'setting',
	'fields' => 'custom',
	'links' => 'custom',
	'shells' => 'custom',
	'chroot' => 'check',
	'global' => 'custom',
	'postgrey' => 'email',
	'dkim' => 'email',
	'ratelimit' => 'email',
	'changelog' => 'setting',
	'provision' => 'setting',
	'autoconfig' => 'email',
	'retention' => 'email',
	'smtpclouds' => 'email',
	'mysqls' => 'setting',
	'dnsclouds' => 'ip',
	'remotedns' => 'ip',
	'acmes' => 'ip',
	);
local %nonew = ( 'history', 1,
		 'postgrey', 1,
		 'dkim', 1,
		 'ratelimit', 1,
		 'provision', 1,
		 'smtpclouds', 1,
		 'dnsclouds', 1,
		 'remotedns', 1,
	       );
local %pro = ( 'resels', 1,
	       'reseller', 1,
	       'smtpclouds', 1,
	       'remotedns', 1,
	       'acmes', 1 );
local @tlinks = map { ($pro{$_} ? "pro/" : "").
		      ($nonew{$_} ? "${_}.cgi" : "edit_new${_}.cgi") } @tmpls;
local @ttitles = map { $nonew{$_} ? $text{"${_}_title"}
			          : $text{"new${_}_title"} } @tmpls;
local @ticons = map { $nonew{$_} ? "images/${_}.gif"
			         : "images/new${_}.gif" } @tmpls;
local @tcats = map { $tmplcat{$_} } @tmpls;

# Get from plugins too
foreach my $p (@plugins) {
	if (&plugin_defined($p, "settings_links")) {
		foreach my $sl (&plugin_call($p, "settings_links")) {
			push(@tlinks, $sl->{'link'});
			push(@ttitles, $sl->{'title'});
			push(@ticons, $sl->{'icon'});
			push(@tcats, $sl->{'cat'});
			}
		}
	}

return (\@tlinks, \@ttitles, \@ticons, \@tcats, \@tmpls);
}

# get_all_global_links()
# Returns a list of links for global actions, including those from 'templates'
# create/migrate, backup/restore and module config. Each element has the same
# keys as get_all_domain_links
sub get_all_global_links
{
my @rv;
my $vm = "/$module_name";

local $v = [ 'plugins' => \@plugins,
	     'spam' => $config{'spam'},
	     'virus' => $config{'virus'},
	     'quotas' => &has_home_quotas(),
	     'mail_system' => $mail_system,
	     'pro' => $virtualmin_pro ];

# Add template pages
if (&can_edit_templates()) {
	local $crv = &get_links_cache("global", $v);
	if ($crv) {
		# Use cache
		@rv = @$crv;
		}
	else {
		# Need to create
		my ($tlinks, $ttitles, undef, $tcats, $tcodes) =
			&get_template_pages();
		$tcats = [ map { "setting" } @$tlinks ] if (!$tcats);
		for(my $i=0; $i<@$tlinks; $i++) {
			local $url;
			if ($tcodes->[$i] eq 'upgrade' &&
			    $config{'upgrade_link'}) {
				# Special link for upgrading GPL to Pro
				$url = $config{'upgrade_link'};
				}
			elsif ($tlinks->[$i] =~ /^\//) {
				# Outside virtualmin module
				$url = $tlinks->[$i];
				}
			else {
				# Inside virtualmin
				$url = $vm."/".$tlinks->[$i];
				}
			push(@rv, { 'url' => $url,
				    'title' => $ttitles->[$i],
				    'cat' => $tcats->[$i],
				    'icon' => $tcodes->[$i],
				  });
			}
		&global_menu_link_pro_tip(\@rv)
			if (!$virtualmin_pro);
		&save_links_cache("global", $v, \@rv);
		}
	}

# Add module config page
if (!$access{'noconfig'}) {
	push(@rv, { 'url' => "/config.cgi?$module_name",
		    'title' => $text{'index_virtualminconfig'},
		    'cat' => 'setting',
		    'icon' => 'config' });
	}

# Add re-check config page
if (&can_edit_templates()) {
	push(@rv, { 'url' => "$vm/check.cgi",
		    'title' => $text{'index_srefresh2'},
		    'cat' => 'setting',
		    'icon' => 'recheck' });
	}

# Add wizard page
if ($config{'wizard_run'} && &can_edit_templates()) {
	push(@rv, { 'url' => "$vm/wizard.cgi",
		    'title' => $text{'index_rewizard'},
		    'cat' => 'setting',
		    'icon' => 'wizard' });
	}

# Twofactor enroll button for master admins and resellers
if (&can_master_reseller_2fa()) {
	push(@rv, { 'url' => "$vm/edit_2fa.cgi",
		    'title' => $text{'edit_change2fa'},
		    'cat' => 'setting' });
	}

# Show lic manager link for master admins
if (&master_admin() && $virtualmin_pro) {
	push(@rv, { 'url' => "$vm/pro/licence.cgi",
		    'title' => $text{'licence_manager_menu'},
		    'cat' => 'setting' });
	}

# Add creation-related links
my ($dleft, $dreason, $dmax, $dhide) = &count_domains("realdoms");
my ($aleft, $areason, $amax, $ahide) = &count_domains("aliasdoms");
my $nobatch = !&can_create_batch();
if ((&can_create_sub_servers() || &can_create_master_servers()) &&
    $dleft && $virtualmin_pro && !$nobatch) {
	# Batch create
	push(@rv, { 'url' => "$vm/mass_create_form.cgi",
		    'title' => $text{'index_batch'},
		    'cat' => 'add',
		    'icon' => 'batch' });
	}
if (&can_import_servers()) {
	# Import domain
	push(@rv, { 'url' => "$vm/import_form.cgi",
		    'title' => $text{'index_import'},
		    'cat' => 'add',
		    'icon' => 'import' });
	}
if (&can_migrate_servers()) {
	# Migrate domain
	push(@rv, { 'url' => "$vm/migrate_form.cgi",
		    'title' => $text{'index_migrate'},
		    'cat' => 'add',
		    'icon' => 'migrate' });
	}

# Add backup/restore links
my ($blinks, $btitles, undef, $bcodes) = &get_backup_actions();
for(my $i=0; $i<@$blinks; $i++) {
	push(@rv, { 'url' => $vm."/".$blinks->[$i],
		    'title' => $btitles->[$i],
		    'cat' => 'backup',
		    'icon' => $bcodes->[$i] });
	}

# Top-level links
push(@rv, { 'url' => $vm.'/index.cgi',
	    'title' => $text{'index_link'},
	    'icon' => 'index' });
if (&reseller_admin()) {
	# Change password for resellers
	push(@rv, { 'url' => $vm."/edit_pass.cgi",
		    'title' => $text{'edit_changeresellerpass'},
		    'icon' => 'pass' });
	}
elsif (&extra_admin()) {
	# Change password for admin
	push(@rv, { 'url' => $vm."/edit_pass.cgi",
		    'title' => $text{'edit_changeadminpass'},
		    'icon' => 'pass' });
	}
if (&reseller_admin() && $config{'bw_active'}) {
	# Bandwidth for resellers
	push(@rv, { 'url' => $vm."/bwgraph.cgi",
		    'title' => $text{'edit_bwgraph'},
		    'icon' => 'bw' });
	}
if (&reseller_admin() && &can_edit_plans()) {
	# Add plans for resellers
	push(@rv, { 'url' => $vm."/edit_newplan.cgi",
		    'title' => $text{'plans_title'},
		    'icon' => 'newplan' });
	}
if (&reseller_admin() && &can_edit_resellers()) {
	# Reseller who can edit other resellers
	push(@rv, { 'url' => $vm."/edit_newresels.cgi",
		    'title' => $text{'newresels_title'},
		    'icon' => 'webmin-small' });
	}
if (&can_show_history()) {
	# History graphs
	push(@rv, { 'url' => $vm."/pro/history.cgi",
		    'title' => $text{'edit_history'},
		    'icon' => 'graph' });
	}
if (&can_use_validation() && !&can_edit_templates()) {
	# Validation page for domain owner
	push(@rv, { 'url' => $vm."/edit_newvalidate.cgi",
		    'title' => $text{'newvalidate_title'},
		    'icon' => 'validate' });
	}
foreach my $f (@plugins) {
	# Add global link from plugins
	if (&plugin_defined($f, "feature_global_links")) {
		my $global_links = &plugin_call($f, "feature_global_links");
		push(@rv, $global_links) if ($global_links);
		}
	}

# Set category names
foreach my $l (@rv) {
	if ($l->{'cat'}) {
		$l->{'catname'} ||= $text{'cat_'.$l->{'cat'}};
		}
	}

return @rv;
}

# get_links_cache(key, &cache-invalidator)
# Checks the cache for some key, and if it exists make sure the stored cache
# validator matches what is given. If so, return the cache contents. If not,
# return undef.
sub get_links_cache
{
local ($cachekey, $validator) = @_;
local $cachedata = &read_file_contents("$links_cache_dir/$cachekey");
return undef if (!$cachedata);
local $cachestr = &unserialise_variable($cachedata);
return undef if (!$cachestr);
return undef if (&serialise_variable($cachestr->{'validator'}) ne
		 &serialise_variable($validator));
return $cachestr->{'data'};
}

# save_links_cache(key, &cache-invalidator, &object)
# Save some cached key based on a key, with an additional validator that can
# be used to check suitability by get_links_cache.
sub save_links_cache
{
local ($cachekey, $validator, $data) = @_;
if (!-d $links_cache_dir) {
	&make_dir($links_cache_dir, 0700);
	}
&open_tempfile(CACHEDATA, ">$links_cache_dir/$cachekey", 0, 1);
&print_tempfile(CACHEDATA, &serialise_variable(
				{ 'validator' => $validator,
				  'data' => $data }));
&close_tempfile(CACHEDATA);
}

# clear_links_cache([&domain|user], ...)
# Delete all cached information for some or all domains
sub clear_links_cache
{
my (@list) = @_;
@list = (undef) if (!@list); 
foreach my $d (@list) {
	opendir(CACHEDIR, $links_cache_dir);
	foreach my $f (readdir(CACHEDIR)) {
		my $del;
		if (ref($d)) {
			# Belongs to domain?
			$del = $f =~ /^\Q$d->{'id'}\E\-/ ? 1 : 0;
			}
		elsif ($d) {
			# Belongs to user?
			$del = $f =~ /\-\Q$d\E$/ ? 1 : 0;
			}
		else {
			# Deleting everything
			$del = 1;
			}
		&unlink_file("$links_cache_dir/$f") if ($del);
		}
	closedir(CACHEDIR);
	}
}

# get_startstop_links([live])
# Returns a list of status objects for relevant features and plugins
sub get_startstop_links
{
local ($live) = @_;
local @rv;
local %typestatus;
foreach my $f (@startstop_features) {
	if ($config{$f}) {
		local $sfunc = "startstop_".$f;
		if (defined(&$sfunc)) {
			foreach my $status (&$sfunc(\%typestatus)) {
				$status->{'feature'} ||= $f;
				push(@rv, $status);
				}
			}
		}
	}
foreach my $f (@startstop_always_features) {
	local $sfunc = "startstop_".$f;
	if (defined(&$sfunc)) {
		foreach my $status (&$sfunc()) {
			$status->{'feature'} ||= $f;
			push(@rv, $status);
			}
		}
	}
foreach my $f (&list_startstop_plugins()) {
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
return 0 if ($d->{'alias'} && !$d->{'aliasmail'} ||
	     $d->{'subdom'});		# never allowed for aliases
if (!$d->{'dir'}) {
	# Users need a home dir
	return 0;
	}
return 1;
}

# Returns 1 if some domain can have scripts installed
sub can_domain_have_scripts
{
local ($d) = @_;
return ($d->{'web'} && $config{'web'} ||
	&domain_has_website($d)) && !$d->{'subdom'} && !$d->{'alias'};
}

# can_chained_feature(feature, [check-chaining-enabled?])
# Returns a list of parent features if some feature or plugin type gets enabled
# when another feature is. If the second param is set, also check if chaining
# is active for this feature right now.
sub can_chained_feature
{
my ($f, $check) = @_;
if (&indexof($f, @plugins) >= 0) {
	if ($check && &indexof($f, @plugins_inactive) >= 0) {
		# Chaining not currently active for this plugin
		return ();
		}
	if (&plugin_defined($f, "feature_can_chained")) {
		return &plugin_call($f, "feature_can_chained");
		}
	return ();
	}
else {
	if ($check && $config{$f} != 3) {
		# Chaining not currently active for this feature
		return ();
		}
	my $cfunc = "can_chained_".$f;
	return defined(&$cfunc) ? &$cfunc() : ();
	}
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
		local ($ok, $fok) = &try_function($f, $sfunc, $d);
		if (!$ok || !$fok) {
			$d->{$f} = 0;
			}
		}
	elsif (!$d->{$f} && $oldd->{$f}) {
		# Delete some feature
		local ($ok, $fok) = &try_function($f, $dfunc, $oldd);
		if (!$ok || !$fok) {
			$d->{$f} = 1;
			}
		$d->{'db_mysql'} = $oldd->{'db_mysql'};
		$d->{'db_postgres'} = $oldd->{'db_postgres'};
		}
	elsif ($d->{$f}) {
		# Modify some feature
		&try_function($f, $mfunc, $d, $oldd);
		}
	}
elsif (&indexof($f, &list_feature_plugins()) >= 0) {
	# A plugin feature
	if ($d->{$f} && !$oldd->{$f}) {
		&try_plugin_call($f, "feature_setup", $d);
		}
	elsif (!$d->{$f} && $oldd->{$f}) {
		&try_plugin_call($f, "feature_delete", $oldd);
		}
	elsif ($d->{$f}) {
		&try_plugin_call($f, "feature_modify", $d, $oldd);
		}
	}
}

# feature_name(name, [&domain])
# Returns a human-readable short feature name, even if it's a plugin
sub feature_name
{
my ($f, $d) = @_;
return $text{'feature_'.$f} || &plugin_call($f, "feature_name") || $f;
}

# domain_features(&dom)
# Returns a list of possible core features for a domain
sub domain_features
{
local ($d) = @_;
return $d->{'alias'} && $d->{'aliasmail'} ? @aliasmail_features :
       $d->{'alias'} ? @alias_features :
       $d->{'subdom'} ? @opt_subdom_features :
       $d->{'parent'} ? ( grep { $_ ne "webmin" && $_ ne "unix" } @features ) :
		         @features;
}

# list_mx_servers()
# Returns the objects for servers used as secondary MXs
sub list_mx_servers
{
if (&foreign_check("servers") && $config{'mx_servers'}) {
	&foreign_require("servers");
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
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
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

# Update the domain object with new home directory and parent details
local (@doms, @olddoms, @remove_feats);
&set_parent_attributes($d, $parent);
&change_home_directory($d, &server_home_directory($d, $parent));
if ($d->{'alias'}) {
	# Set new alias target to new parent
	$d->{'alias'} = $parent->{'id'};

	# Clear any alias features that the new domain doesn't have
	foreach my $f (@alias_features) {
		if ($d->{$f} && !$parent->{$f}) {
			$d->{$f} = 0;
			push(@remove_feats, $f);
			}
		}
	}
push(@doms, $d);
push(@olddoms, $oldd);

if (!$oldd->{'parent'}) {
	# If this is a parent domain, all of it's children need to be
	# re-parented too. This will also catch any aliases and sub-domains.
	# These have to be moved BEFORE their old parent, so that move of the
	# parent doesn't cause the home directory to disappear.
	local @subs = &get_domain_by("parent", $d->{'id'});
	foreach my $sd (@subs) {
		local $oldsd = { %$sd };
		&set_parent_attributes($sd, $parent);
		&change_home_directory($sd,
				       &server_home_directory($sd, $parent));
		unshift(@doms, $sd);
		unshift(@olddoms, $oldsd);
		}

	# The template may no longer be valid if it was for a top-level server
	local $tmpl = &get_template($d->{'template'});
	if (!$tmpl->{'for_sub'}) {
		$d->{'template'} = &get_init_template(1);
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

# Run the before command
&set_domain_envs($oldd, "MODIFY_DOMAIN", $d);
local $merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));
&setup_for_subdomain($parent);

# If this is an alias domain, first delete features that don't exist in
# the target
foreach my $f (@remove_feats) {
	my $dfunc = "delete_".$f;
	local $main::error_must_die = 1;
	eval {
		&$dfunc($oldd);
		};
	if ($@) {
		&$second_print(&text('setup_failure',
			$text{'feature_'.$f}, "$@"));
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
local %vital = map { $_, 1 } @vital_features;
foreach my $f (@features) {
	local $mfunc = "modify_$f";
	for(my $i=0; $i<@doms; $i++) {
		if (($doms[$i]->{$f} || ($f eq 'mail' && !$d->{'alias'})) &&
		    ($config{$f} || $f eq "unix" || $f eq "mail")) {
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
					$text{'feature_'.$f}, "$@"));
				if ($vital{$f}) {
					# A vital feature failed .. give up
					return 0;
					}
				}
			}
		}
	}

# Do move for plugins, with error handling
foreach my $f (&list_feature_plugins(1)) {
	for(my $i=0; $i<@doms; $i++) {
		$doing_dom = $doms[$i];
		local $main::error_must_die = 1;
		if ($doms[$i]->{$f}) {
			eval { &plugin_call($f, "feature_modify",
				     	    $doms[$i], $olddoms[$i]) };
			if ($@) {
				local $err = $@;
				&$second_print(&text('setup_failure',
					&plugin_call($f, "feature_name"),$err));
				}
			}
		eval { &plugin_call($f, "feature_always_modify",
				    $doms[$i], $olddoms[$i]) };
		}
	}

$first_print = $old_first_print if ($old_first_print);

# Fix script installer paths in all domains
if (defined(&list_domain_scripts) && !$d->{'alias'}) {
	&$first_print($text{'rename_scripts'});
	for(my $i=0; $i<@doms; $i++) {
		local ($olddir, $newdir) =
		    ($olddoms[$i]->{'home'}, $doms[$i]->{'home'});
		foreach $sinfo (&list_domain_scripts($doms[$i])) {
			$changed = 0;
			if ($olddir ne $newdir) {
				# Fix directory
				$changed++
				   if ($sinfo->{'opts'}->{'dir'} =~
				       s/^\Q$olddir\E\//$newdir\//);
				}
			&save_domain_script($doms[$i], $sinfo) if ($changed);
			}
		}
	&$second_print($text{'setup_done'});
	}

# Fix backup schedule and key owners
if (!$oldd->{'parent'}) {
	&rename_backup_owner($d, $oldd);
	}

# Clear email field, to force inheritance from new parent
for(my $i=0; $i<@doms; $i++) {
	delete($doms[$i]->{'email'});
        }

# Set plan based on new parent
for(my $i=0; $i<@doms; $i++) {
	&set_plan_on_children($doms[$i]);
	}

# Save the domain objects
&$first_print($text{'save_domain'});
for(my $i=0; $i<@doms; $i++) {
	&lock_domain($doms[$i]);
        &save_domain($doms[$i]);
	&unlock_domain($doms[$i]);
        }
&$second_print($text{'setup_done'});

# Update old and new Webmin users
&modify_webmin($parent, $parent);
if ($oldparent) {
	&modify_webmin($oldparent, $oldparent);
	}

# Re-apply the parent's resource limits, if any
if (defined(&supports_resource_limits) && &supports_resource_limits()) {
	local $rv = &get_domain_resource_limits($parent);
	&save_domain_resource_limits($parent, $rv);
	}

# If the domain was an alias, re-copy any mail aliases
if ($d->{'alias'} && $d->{'mail'} && $parent->{'mail'}) {
	&sync_alias_virtuals($parent);
	}

&run_post_actions();

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
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
$d->{'ugroup'} = $newuser;
$d->{'pass'} = $newpass;
&generate_domain_password_hashes($d, 1);
if (!$d->{'mysql'}) {
	delete($d->{'mysql_user'});
	}
if (!$d->{'postgres'}) {
	delete($d->{'postgres_user'});
	}
local (%gtaken, %taken);
&build_group_taken(\%gtaken);
&build_taken(\%taken);
$d->{'uid'} = &allocate_uid(\%taken);
$d->{'gid'} = &allocate_gid(\%gtaken);
$d->{'ugid'} = $d->{'gid'};
&change_home_directory($d, &server_home_directory($d));
push(@doms, $d);
push(@olddoms, $oldd);

# The template may no longer be valid if it was for a sub-server
local $tmpl = &get_template($d->{'template'});
local $skelchanged;
if (!$tmpl->{'for_parent'}) {
	local $deftmpl = &get_init_template(0);
	if ($d->{'template'} ne $deftmpl) {
		$d->{'template'} = $deftmpl;
		local $newtmpl = &get_template($d->{'template'});
		if ($newtmpl->{'skel'} ne $tmpl->{'skel'}) {
			$skelchanged = $newtmpl->{'skel'};
			}
		}
	}

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
foreach my $f (@opt_features, "virt", &list_feature_plugins()) {
	$d->{'limit_'.$f} = $oldparent->{'limit_'.$f};
	}
$d->{'demo'} = $oldparent->{'demo'};
$d->{'webmin_modules'} = $oldparent->{'webmin_modules'};
$d->{'plan'} = $oldparent->{'plan'};

# Find any alias domains that also need to be re-parented. Also find
# any sub-domains
local @aliases = &get_domain_by("alias", $d->{'id'});
local @subdoms = &get_domain_by("subdom", $d->{'id'});
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
		$doing_dom = $doms[$i];
		if ($doms[$i]->{$f} && ($config{$f} || $f eq "unix")) {
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
					$text{'feature_'.$f}, "$@"));
				if ($vital{$f}) {
					# A vital feature failed .. give up
					return 0;
					}
				}

			# Setup domains dir for aliases/etc
			if ($doms[$i] eq $d && $f eq "dir") {
				&setup_for_subdomain($d);
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
foreach $f (&list_feature_plugins(1)) {
	for(my $i=0; $i<@doms; $i++) {
		$doing_dom = $doms[$i];
		local $main::error_must_die = 1;
		if ($doms[$i]->{$f}) {
			eval { &plugin_call($f, "feature_modify",
					    $doms[$i], $olddoms[$i]) };
			if ($@) {
				local $err = $@;
				&$second_print(&text('setup_failure',
					&plugin_call($f, "feature_name"),$err));
				}
			}
		eval { &plugin_call($f, "feature_always_modify",
				    $doms[$i], $olddoms[$i]) };
		}
	}

$first_print = $old_first_print if ($old_first_print);

# Fix script installer paths in all domains
if (defined(&list_domain_scripts)) {
	&$first_print($text{'rename_scripts'});
	for(my $i=0; $i<@doms; $i++) {
		local ($olddir, $newdir) =
		    ($olddoms[$i]->{'home'}, $doms[$i]->{'home'});
		foreach $sinfo (&list_domain_scripts($doms[$i])) {
			$changed = 0;
			if ($olddir ne $newdir) {
				# Fix directory
				$changed++
				   if ($sinfo->{'opts'}->{'dir'} =~
				       s/^\Q$olddir\E\//$newdir\//);
				}
			&save_domain_script($doms[$i], $sinfo) if ($changed);
			}
		}
	&$second_print($text{'setup_done'});
	}

# Save the domain objects
&$first_print($text{'save_domain'});
for(my $i=0; $i<@doms; $i++) {
	&lock_domain($doms[$i]);
        &save_domain($doms[$i]);
	&unlock_domain($doms[$i]);
        }
&$second_print($text{'setup_done'});

# Update old Webmin user
if ($oldparent->{'webmin'}) {
	&modify_webmin($oldparent, $oldparent);
	}

# Re-save the new Webmin user to grant access to all aliases
if ($d->{'webmin'}) {
	&modify_webmin($d, $d);
	}

# Re-apply resource limits, to update Apache and PHP configs
if (defined(&supports_resource_limits) && &supports_resource_limits()) {
	local $rv = &get_domain_resource_limits($d);
	&save_domain_resource_limits($d, $rv);
	}

# Copy skeleton files for top-level server
if ($skelchanged && $skelchanged ne 'none') {
	local $uinfo = &get_domain_owner($d, 1);
	&copy_skel_files(&substitute_domain_template($skelchanged, $d),
			 $uinfo, $d->{'home'},
			 $d->{'group'} || $d->{'ugroup'}, $d);
	}

&run_post_actions();

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

return 1;
}

# unsub_virtual_server(&domain)
# Convert a virtual server from a sub-domain to a sub-server
sub unsub_virtual_server
{
local ($d) = @_;
local $oldd = { %$d };
local $parent = &get_domain($d->{'parent'});

# Run the before command
&set_domain_envs($oldd, "MODIFY_DOMAIN");
local $merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Update the domain object with a new home directory
delete($d->{'subdom'});
delete($d->{'public_html_dir'});
delete($d->{'public_html_path'});
$d->{'public_html_dir'} = &public_html_dir($d, 1);
$d->{'public_html_path'} = &public_html_dir($d, 0);
delete($d->{'cgi_bin_dir'});
delete($d->{'cgi_bin_path'});
$d->{'cgi_bin_dir'} = &cgi_bin_dir($d, 1);
$d->{'cgi_bin_path'} = &cgi_bin_dir($d, 0);
&change_home_directory($d, &server_home_directory($d, $parent));

# Update all features in the domain
local %vital = map { $_, 1 } @vital_features;
foreach my $f (@features) {
	local $mfunc = "modify_$f";
	if ($d->{$f} && $config{$f}) {
		local $main::error_must_die = 1;
		eval { &$mfunc($d, $oldd); };
		if ($@) {
			&$second_print(&text('setup_failure',
				       $text{'feature_'.$f}, "$@"));
			return 0 if ($vital{$f});
			}
		}
	}

# Update all enabled plugins
foreach my $f (&list_feature_plugins(1)) {
	local $main::error_must_die = 1;
	if ($d->{$f}) {
		eval { &plugin_call($f, "feature_modify", $d, $oldd) };
		if ($@) {
			local $err = $@;
			&$second_print(&text('setup_failure',
				&plugin_call($f, "feature_name"), $err));
			}
		}
	eval { &plugin_call($f, "feature_always_modify", $d, $oldd) };
	}

# Save the domain object
&$first_print($text{'save_domain'});
&lock_domain($d);
&save_domain($d);
&unlock_domain($d);
&$second_print($text{'setup_done'});

# Update parent Webmin user
&modify_webmin($parent, $parent);

&run_post_actions();

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

return 1;
}

# unalias_virtual_server(&domain)
# Convert a virtual server from an alias to a sub-server
sub unalias_virtual_server
{
local ($d) = @_;
local $oldd = { %$d };
local $parent = &get_domain($d->{'parent'});

# Run the before command
&set_domain_envs($oldd, "MODIFY_DOMAIN");
local $merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Update the domain object to set the web directory
delete($d->{'alias'});
delete($d->{'public_html_dir'});
delete($d->{'public_html_path'});
$d->{'public_html_dir'} = &public_html_dir($d, 1);
$d->{'public_html_path'} = &public_html_dir($d, 0);
delete($d->{'cgi_bin_dir'});
delete($d->{'cgi_bin_path'});
$d->{'cgi_bin_dir'} = &cgi_bin_dir($d, 1);
$d->{'cgi_bin_path'} = &cgi_bin_dir($d, 0);

# Create domains dir if missing
&setup_for_subdomain($parent, $parent->{'user'}, $d);

# Create the directory, if missing
if (!$d->{'dir'}) {
	$d->{'dir'} = 1;
	local $main::error_must_die = 1;
	eval { &setup_dir($d); };
	if ($@) {
		&$second_print(&text('setup_failure',
				     $text{'feature_dir'}, "$@"));
		}
	}

# Update all features in the domain
local %vital = map { $_, 1 } @vital_features;
foreach my $f (@features) {
	local $mfunc = "modify_$f";
	if ($d->{$f} && $config{$f}) {
		local $main::error_must_die = 1;
		eval { &$mfunc($d, $oldd); };
		if ($@) {
			&$second_print(&text('setup_failure',
				       $text{'feature_'.$f}, "$@"));
			return 0 if ($vital{$f});
			}
		}
	}

# Update all enabled plugins
foreach my $f (&list_feature_plugins(1)) {
	local $main::error_must_die = 1;
	if ($d->{$f}) {
		eval { &plugin_call($f, "feature_modify", $d, $oldd) };
		if ($@) {
			local $err = $@;
			&$second_print(&text('setup_failure',
				&plugin_call($f, "feature_name"), $err));
			}
		}
	eval { &plugin_call($f, "feature_always_modify", $d, $oldd) };
	}

# Save the domain object
&$first_print($text{'save_domain'});
&lock_domain($d);
&save_domain($d);
&unlock_domain($d);
&$second_print($text{'setup_done'});

# Update parent Webmin user
&modify_webmin($parent, $parent);

&run_post_actions();

# Turn off aliascopy for future
&lock_domain($d);
delete($d->{'aliascopy'});
&save_domain($d);
&unlock_domain($d);

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
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
$d->{'ugroup'} = $parent->{'ugroup'};
$d->{'uid'} = $parent->{'uid'};
$d->{'gid'} = $parent->{'gid'};
$d->{'ugid'} = $parent->{'ugid'};
$d->{'pass'} = $parent->{'pass'};
$d->{'enc_pass'} = $parent->{'enc_pass'};
$d->{'crypt_enc_pass'} = $parent->{'crypt_enc_pass'};
$d->{'md5_enc_pass'} = $parent->{'md5_enc_pass'};
$d->{'mysql_enc_pass'} = $parent->{'mysql_enc_pass'};
$d->{'digest_enc_pass'} = $parent->{'digest_enc_pass'};
$d->{'mysql_user'} = $parent->{'mysql_user'};
$d->{'postgres_user'} = $parent->{'postgres_user'};
$d->{'email'} = $parent->{'email'};
}

# rename_virtual_server(&domain, [new-domain], [new-user], [new-home|"auto"],
# 		        new-prefix)
# Updates a virtual server and possibly sub-servers with a new domain name,
# username and home directory. If any of the parameters are undef, they are
# left un-changed. Prints progress output, and returns undef on success or
# an error message on failure.
sub rename_virtual_server
{
my ($d, $dom, $user, $home, $prefix) = @_;
&lock_domain($d);

$dom = undef if ($dom eq $d->{'dom'});
$home = undef if ($home eq $d->{'home'});
$prefix = undef if ($prefix eq $d->{'prefix'});

my %oldd = %$d;
my $parentdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;

# Validate domain name
if ($dom) {
	my $derr = &allowed_domain_name($parentdom, $dom);
	return $derr if ($derr);
	my $clash = &get_domain_by("dom", $dom);
	$clash && return $text{'rename_eclash'};
	}

# Validate username, home directory and prefix
if ($d->{'parent'}) {
	# Sub-servers don't have a separate user
	$user = undef;
	}
elsif ($user eq 'auto') {
	my ($try1, $try2);
	($user, $try1, $try2) = &unixuser_name($dom || $d->{'dom'});
	$user || return &text('setup_eauto', $try1, $try2);
	}
elsif ($user) {
	&valid_mailbox_name($user) && return $text{'setup_euser2'};
        my ($clash) = grep { $_->{'user'} eq $user } &list_all_users();
        $clash && return $text{'rename_euserclash'};
	}
if ($prefix eq 'auto') {
	$prefix = &compute_prefix($dom || $d->{'dom'}, $user || $d->{'user'},
				  $parentdom);
	}
elsif ($prefix) {
	$prefix =~ /^[a-z0-9\.\-]+$/i || return $text{'setup_eprefix'};
        my $pclash = &get_domain_by("prefix", $prefix);
        $pclash && return &text('setup_eprefix3', $prefix, $pclash->{'dom'});
	}
my $group;
if ($prefix) {
	$group = $user || $d->{'user'};
	}

# If the domain name is being changed and there are any DNS sub-domains
# which share the same zone file, split them out into their own files
if ($dom && $d->{'dns'} && !$d->{'dns_submode'}) {
	my @dnssub = grep { $_->{'dns'} }
			  &get_domain_by("dns_subof", $d->{'id'});
	if (@dnssub) {
		&$first_print($text{'rename_dnssub'});
		&$indent_print();
		foreach my $sd (@dnssub) {
			&save_dns_submode($sd, 0);
			}
		&$outdent_print();
		}
	}

# Update the domain object with the new domain name and username
if ($dom) {
	$d->{'email'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
	$d->{'emailto'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
	$d->{'dom'} = $dom;
	}
if ($user) {
	$d->{'email'} =~ s/^\Q$d->{'user'}\E\@/$user\@/g;
	$d->{'emailto'} =~ s/^\Q$d->{'user'}\E\@/$user\@/g;
	$d->{'user'} = $user;
	}

# Validate and set home directory
if ($home eq 'auto') {
	# Automatic home
	&change_home_directory($d, &server_home_directory($d, $parentdom));
	}
elsif ($home) {
	# User-selected home
	-e $home && return $text{'rename_ehome3'};
	$home =~ /^(.*)\// && -d $1 || return $text{'rename_ehome4'};
	&change_home_directory($d, $home);
	}
if ($group) {
	if ($d->{'ugroup'} eq $d->{'group'}) {
		$d->{'ugroup'} = $group;
		}
	$d->{'group'} = $group;
	$d->{'prefix'} = $prefix;
	}

# Find any sub-server objects and update them
my @subs;
if (!$d->{'parent'}) {
	@subs = &get_domain_by("parent", $d->{'id'});
	foreach my $sd (@subs) {
		my %oldsd = %$sd;
		push(@oldsubs, \%oldsd);
		if ($user) {
			$sd->{'email'} =~ s/^\Q$sd->{'user'}\E\@/$user\@/g;
			$sd->{'emailto'} =~ s/^\Q$sd->{'user'}\E\@/$user\@/g;
			$sd->{'user'} = $user;
			}
		if ($dom) {
			$sd->{'email'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
			$sd->{'emailto'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
			}
		if ($home) {
			&change_home_directory($sd,
					       &server_home_directory($sd, $d));
			}
		if ($group) {
			if ($sd->{'ugroup'} eq $sd->{'group'}) {
				$sd->{'ugroup'} = $group;
				}
			$sd->{'group'} = $group;
			}
		}
	}

# Find any domains aliases to this one, excluding child domains since they
# were covered above
my @aliases = &get_domain_by("alias", $d->{'id'});
my @aliases = grep { $_->{'parent'} != $d->{'id'} } @aliases;
foreach my $ad (@aliases) {
	my %oldad = %$ad;
	push(@oldaliases, \%oldad);
	if ($user) {
		$ad->{'email'} =~ s/^\Q$ad->{'user'}\E\@/$user\@/g;
		$ad->{'emailto'} =~ s/^\Q$ad->{'user'}\E\@/$user\@/g;
		$ad->{'user'} = $user;
		}
	if ($dom) {
		$ad->{'email'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
		$ad->{'emailto'} =~ s/\@$d->{'dom'}$/\@$dom/gi;
		}
	if ($home) {
		&change_home_directory($ad,
				       &server_home_directory($ad, $d));
		}
	if ($group) {
		$ad->{'group'} = $group;
		}
	}

# Check for domain name clash, where the domain, user or group have changed
foreach my $f (@features) {
	my $cfunc = "check_${f}_clash";
	if (defined(&$cfunc) && $dom{$f}) {
		if ($dom && &$cfunc($d, 'dom')) {
			return &text('setup_e'.$f, $dom, $dom{'db'},
				     $user, $d->{'group'} || $group);
			}
		if ($user && &$cfunc($d, 'user')) {
			return &text('setup_e'.$f, $dom, $dom{'db'},
				     $user, $d->{'group'} || $group);
			}
		if ($group && &$cfunc($d, 'group')) {
			return &text('setup_e'.$f, $dom, $dom{'db'},
				     $user, $group);
			}
		}
	}

# Run the before command
&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
my $merr = &making_changes();
&reset_domain_envs(\%oldd);
return &text('rename_emaking', "<tt>$merr</tt>") if (defined($merr));

if ($dom) {
	&$first_print(&text('rename_doingdom', "<tt>$dom</tt>"));
	&$second_print($text{'setup_done'});
	}
if ($user) {
	&$first_print(&text('rename_doinguser', "<tt>$user</tt>"));
	&$second_print($text{'setup_done'});
	}
if ($home eq 'auto') {
	&$first_print(&text('rename_doinghome',
		"<tt>".&server_home_directory($d, $parentdom)."</tt>"));
	&$second_print($text{'setup_done'});
	}
elsif ($home) {
	&$first_print(&text('rename_doinghome', "<tt>$home</tt>"));
	&$second_print($text{'setup_done'});
	}

# Build the list of domains being changed
my @doms = ( $d );
my @olddoms = ( \%oldd );
push(@doms, @subs, @aliases);
push(@olddoms, @oldsubs, @oldaliases);
foreach my $ld (@doms) {
	&lock_domain($ld);
	}

# Update all features in all domains. Include the mail feature always, as this
# covers FTP users
local $doing_dom;	# Has to be local for scoping
foreach my $f (&unique(@features, 'mail')) {
	my $mfunc = "modify_$f";
	for(my $i=0; $i<@doms; $i++) {
		my $p = &domain_has_website($doms[$i]);
		if ($f eq "web" && $p && $p ne "web") {
			# Web feature is provided by a plugin .. call it now
			$doing_dom = $doms[$i];
			&try_plugin_call($p, "feature_modify",
					 $doms[$i], $olddoms[$i]);
			}
		elsif ($doms[$i]->{$f} && $config{$f} ||
	               $f eq "unix" || $f eq "mail") {
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
						&try_function($f, $mfunc,
						   $doms[$i], $olddoms[$i],
						   $doms[$idx], $olddoms[$idx]);
						}
					else {
						&try_function($f, $mfunc,
						   $doms[$i], $olddoms[$i],
						   $aliasdom, $aliasdom);
						}
					}
				else {
					# Not an alias domain
					&try_function($f, $mfunc,
						      $doms[$i], $olddoms[$i]);
					}
				};
			if ($@) {
				&$second_print(&text('setup_failure',
					$text{'feature_'.$f}, "$@"));
				}
			}
		}
	}

# Update plugins in all domains
foreach $f (&list_feature_plugins(1)) {
	for(my $i=0; $i<@doms; $i++) {
		my $p = &domain_has_website($doms[$i]);
		$doing_dom = $doms[$i];
		if ($doms[$i]->{$f} && $f ne $p) {
			&try_plugin_call($f, "feature_modify",
					 $doms[$i], $olddoms[$i]);
			}
		&try_plugin_call($f, "feature_always_modify",
				 $doms[$i], $olddoms[$i]);
		}
	}

# Fix script installer paths in all domains
if (defined(&list_domain_scripts)) {
	&$first_print($text{'rename_scripts'});
	for(my $i=0; $i<@doms; $i++) {
		my ($olddir, $newdir) =
		    ($olddoms[$i]->{'home'}, $doms[$i]->{'home'});
		my ($olddname, $newdname) =
		    ($olddoms[$i]->{'dom'}, $doms[$i]->{'dom'});
		foreach my $sinfo (&list_domain_scripts($doms[$i])) {
			my $changed = 0;
			if ($olddir ne $newdir) {
				# Fix directory
				$changed++ if ($sinfo->{'opts'}->{'dir'} =~
				       	       s/^\Q$olddir\E\//$newdir\//);
				}
			if ($olddname ne $newdname) {
				# Fix domain in URL
				$changed++ if ($sinfo->{'url'} =~
					       s/\Q$olddname\E/$newdname/);
				}
			if (!$info{'opts'}->{'dir'} ||
			    -d $info{'opts'}->{'dir'}) {
				# list_domain_scripts will set deleted flag
				# due to home directory move, so fix it now that
				# script dir has been corrected
				$sinfo->{'deleted'} = 0;
				}
			&save_domain_script($doms[$i], $sinfo) if ($changed);
			}
		}
	&$second_print($text{'setup_done'});
	}

# Fix backup schedule and key owners
if (!$oldd{'parent'}) {
	&rename_backup_owner($d, \%oldd);
	}

&refresh_webmin_user($d);
&run_post_actions();

# Save all new domain details
&$first_print($text{'save_domain'});
for(my $i=0; $i<@doms; $i++) {
	&save_domain($doms[$i]);
	&unlock_domain($doms[$i]);
	}
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
my $merr = &made_changes();
&$second_print(&text('rename_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

# Clear all left-frame links caches, as links to Apache may no longer be valid
&clear_links_cache();
&unlock_domain($d);

return undef;
}

# check_virtual_server_config([&lastconfig])
# Validates the Virtualmin configuration, printing out messages as it goes.
# Returns undef on success, or an error message on failure.
sub check_virtual_server_config
{
local ($lastconfig) = @_;
local $clink = "edit_newfeatures.cgi";
local $mclink = "../config.cgi?$module_name";

# Check for disabled features that were just turned off
if ($lastconfig) {
	my @doms = &list_domains();
	foreach my $f (@features) {
		if (!$config{$f} && $lastconfig->{$f}) {
			my @lost = grep { $_->{$f} } @doms;
			return &text('check_lostfeature',
				$text{'feature_'.$f},
				join(", ", map { &show_domain_name($_) } @lost))
				if (@lost);
			}
		}
	foreach my $f (split(/\s+/, $lastconfig->{'plugins'})) {
		if (&indexof($f, @plugins) < 0) {
			my @lost = grep { $_->{$f} } @doms;
			return &text('check_lostplugin',
				&plugin_call($f, "feature_name"),
				join(", ", map { &show_domain_name($_) } @lost))
				if (@lost);
			}
		}
	}

# Make sure networking is supported
if (!&foreign_check("net")) {
	&foreign_require("net");
	if (!defined(&net::boot_interfaces)) {
		return &text('index_enet');
		}
	&$second_print($text{'check_netok'});
	}

# Check for sensible memory limits
if (&foreign_check("proc")) {
	&foreign_require("proc");
	local $arch = &backquote_command("uname -m");
	local $defmem = 1024;
	$defmem += 512 if ($config{'virus'});	# ClamAV eats RAM
	local $rmem = ($config{'mem_low'} || $defmem)*1024*1024;
	if (defined(&proc::get_memory_info)) {
		local @mem = &proc::get_memory_info();
		local $beans = &get_beancounters();
		if ($mem[0]*1024 < $rmem) {
			# Memory is less than 512 MB (768 on 64-bit)
			&$second_print(&ui_text_color(&text('check_lowmemory',
				&nice_size($mem[0]*1024),
				&nice_size($rmem)), 'warn'));
			}
		elsif ($beans->{'vmguarpages'} &&
		       $beans->{'vmguarpages'}*4096 < $rmem &&
		       $beans->{'vmguarpages'} < $beans->{'privvmpages'}) {
			# OpenVZ guaranteed memory is lower than max memory,
			# and is less than 256 M
			&$second_print(&ui_text_color(&text('check_lowgmemory',
				&nice_size($mem[0]*1024),
				&nice_size($beans->{'vmguarpages'}*4096),
				&nice_size($rmem)), 'warn'));
			}
		elsif ($beans->{'vmguarpages'} &&
		       $beans->{'vmguarpages'} < $beans->{'privvmpages'}) {
			# OpenVZ guaranteed memory is lower than max memory,
			# but is above 256 M
			&$second_print(&text('check_okgmemory',
				&nice_size($mem[0]*1024),
				&nice_size($beans->{'vmguarpages'}*4096),
				&nice_size($rmem)));
			}
		else {
			# Memory is OK
			&$second_print(&text('check_okmemory',
				&nice_size($mem[0]*1024), &nice_size($rmem)));
			}
		}
	}

if ($config{'dns'}) {
	# Make sure BIND is installed
	if (&is_dns_remote()) {
		# Only BIND module is needed
		&foreign_check("bind8") ||
			return $text{'index_ebindmod'};
		&$second_print($text{'check_dnsok3'});
		}
	else {
		# BIND server must be installed and usable
		&foreign_installed("bind8", 1) == 2 ||
			return &text('index_ebind', "../bind8/", $clink);

		# Validate BIND config
		&require_bind();
		if (&bind8::supports_check_conf()) {
			my @errs = &bind8::check_bind_config();
			if (@errs) {
				return &text('index_ebinderrs',
					     join(", ", @errs));
				}
			}

		# Check that primary NS hostname is reasonable
		&require_bind();
		local $tmpl = &get_template(0);
		local $master = $tmpl->{'dns_master'} eq 'none' ? undef :
						$tmpl->{'dns_master'};
		$master ||= $bind8::config{'default_prins'} ||
			    &get_system_hostname();
		local $mastermsg;
		if ($master !~ /\./) {
			$mastermsg = &text('check_dnsmaster',
					   "<tt>$master</tt>");
			}
		if ($master !~ /\$/) {
			my $masterip = &to_ipaddress($master);
			if (!$masterip) {
				$mastermsg ||= &text('check_dnsmaster2',
						     "<tt>$master</tt>");
				}
			elsif ($masterip ne &get_any_external_ip_address(1) &&
			       $masterip ne &get_dns_ip() &&
			       &indexof($masterip, &active_ip_addresses()) < 0) {
				$mastermsg ||= &text('check_dnsmaster3',
					     "<tt>$master</tt>", "<tt>$masterip</tt>");
				}
			}
		$mastermsg = ", $mastermsg" if ($mastermsg);
		&$second_print($text{'check_dnsok2'}.$mastermsg);
		}
	}

if ($config{'mail'}) {
	if ($mail_system == 5) {
		return $text{'check_evpopmail'};
		}
	if ($mail_system == 6) {
		return $text{'check_eexim'};
		}
	if ($mail_system == 4) {
		return $text{'check_eqmailldap'};
		}
	if ($mail_system == 3) {
		# Work out which mail server we have
		if (&postfix_installed()) {
			$config{'mail_system'} = 0;
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
		$mail_system = $config{'mail_system'};
		&lock_file($module_config_file);
		&save_module_config();
		&unlock_file($module_config_file);
		}
	local $expected_mailboxes;
	if ($mail_system == 1) {
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
					     '/sendmail/', $mclink);
			}
		if ($config{'bccs'}) {
			return &text('check_esendmailbccs', $mclink);
			}

		# Check for external interface
		local @addrs;
		local $conf = &sendmail::get_sendmailcf();
		foreach my $dpo (&sendmail::find_options("DaemonPortOptions",
							 $conf)) {
			local $addr = "*";
			if ($dpo->[1] =~ /(Addr|Address|A)=([^ ,]+)/i) {
				$addr = $2;
				}
			local $port = 25;
			if ($dpo->[1] =~ /(Port|P)=([^ ,]+)/i) {
				$port = $2;
				}
			push(@addrs, [ $addr, $port ]);
			}
		if (@addrs) {
			# Need at least one non-localhost port 25
			local @adescs;
			foreach my $a (@addrs) {
				if ($a->[0] eq '*') {
					push(@adescs, "port $a->[1]");
					}
				else {
					push(@adescs, "$a->[0] port $a->[1]");
					}
				}
			@addrs = grep { $_->[0] ne 'localhost' &&
					$_->[0] ne '127.0.0.1' &&
					$_->[0] !~ /:/ &&
					($_->[1] eq '25' || $_->[1] eq 'smtp') }
				      @addrs;
			@addrs || return &text('check_esendmailaddrs',
					join(", ", @adescs), '/sendmail/');
			}

		&$second_print($text{'check_sendmailok'});
		$expected_mailboxes = 1;
		}
	elsif ($mail_system == 0) {
		# Make sure postfix is installed
		if (!&postfix_installed()) {
			return &text('index_epostfix', '/postfix/',
					   "../config.cgi?$module_name");

			}

		# Check that all the need Postfix maps are working
		&require_mail();
		my $err = &check_postfix_map("alias_maps");
		return &text('check_ealias_maps', $err) if ($err);
		$err = &check_postfix_map($virtual_type);
		return &text('check_evirtual_maps', $err) if ($err);
		if ($config{'generics'}) {
			$canonical_maps ||
			  return &text('index_epgens', '/postfix/', $mclink);
			$err = &check_postfix_map($canonical_type);
			return &text('check_ecanonical_maps', $err) if ($err);
			}
		if ($config{'bccs'}) {
			$sender_bcc_maps ||
				return &text('check_epostfixbccs', '/postfix/',
					     $mclink);
			$err = &check_postfix_map("sender_bcc_maps");
			return &text('check_ebcc_maps', $err) if ($err);
			}

		# Make sure virtual_alias_domains is not set, as it overrides
		# virtual_alias_maps
		local $vad = &postfix::get_real_value("virtual_alias_domains");
		local $vam = &postfix::get_real_value($virtual_type);
		if ($vad && $vad ne $vam) {
			return &text('check_evad', $vad);
			}

		# Make sure mydestination contains hostname or origin
		local $myhost = &postfix::get_real_value("myorigin") ||
			        &postfix::get_real_value("myhostname") ||
				&get_system_hostname(0, 1);
		if ($myhost =~ /^\//) {
			$myhost = &read_file_contents($myhost);
			$myhost =~ s/\s//g;
			}
		$myhost =~ s/^\s+//;
		$myhost =~ s/\s+$//;
		local @mydest = split(/[, ]+/,
				   &postfix::get_real_value("mydestination"));
		if ($myhost &&
		    &indexoflc($myhost, @mydest) < 0 &&
		    &indexoflc('$myhostname', @mydest) < 0) {
			if (&postfix::get_real_value("relayhost")) {
				&$second_print($text{'check_postfixok2'});
				}
			else {
				return &text('check_emydest', $myhost,
					     join(", ", @mydest));
				}
			}
		else {
			&$second_print($text{'check_postfixok'});
			}

		$expected_mailboxes = 0;

		# Report on outgoing IP option
		if ($supports_dependent) {
			&$second_print($text{'check_dependentok'});
			}
		elsif (&compare_versions($postfix::postfix_version, 2.7) < 0) {
			&$second_print($text{'check_dependentever'});
			}
		else {
			local $l = '../postfix/dependent.cgi';
			&$second_print(&text('check_dependentesupport', $l));
			}
		}
	elsif ($mail_system == 2) {
		# Make sure qmail is installed
		if (!&qmail_installed()) {
			return &text('index_eqmail', '/qmailadmin/',
					   "../config.cgi?$module_name");
			}
		if ($config{'generics'}) {
			return &text('index_eqgens', $mclink);
			}
		if ($config{'bccs'}) {
			return &text('check_eqmailbccs', $mclink);
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
	if (!$apache::httpd_modules{'mod_actions'}) {
		return &text('check_ewebactions');
		}

	# Check if template PHP mode is supported, and if not change it
	my @supp = &supported_php_modes();
	foreach my $id (0, 1) {
		my $tmpl = &get_template($id);
		my $mode = &template_to_php_mode($tmpl);
		my $modupd;
		if (&indexof($mode, @supp) < 0) {
			my $mmap = &php_mode_numbers_map();
			my ($best) = grep { $_ ne "none" } @supp;
			$best ||= $supp[0];
			$tmpl->{'web_php_suexec'} = $mmap->{$best};
			&$second_print(&text('check_ewebdefphpmode2',
					     $mode, $supp[0]));
			&save_template($tmpl);
			$modupd++
			}
		}

	# Complain if mod_php is the default mode, unless force reset above 
	if ($mode eq "mod_php" && !$modupd) {
		&$second_print(&ui_alert_box(&text('check_ewebmod_php', $mode), 'warn', undef, undef, "", 'fa-spam'));
		}

	# Run Apache config check
	local $err = &apache::test_config();
	if ($err) {
		local @elines = split(/\r?\n/, $err);
		@elines = grep { !/\[warn\]/ } @elines;
		$err = join("\n", @elines) if (@elines);
		return &text('check_ewebconfig',
			     "<pre>".&html_escape($err)."</pre>");
		}

	# Check for sane Apache version
	if (!$apache::httpd_modules{'core'}) {
		return $text{'check_ewebapacheversion'};
		}
	elsif ($apache::httpd_modules{'core'} < 1.3) {
		return &text('check_ewebapacheversion2',
			     $apache::httpd_modules{'core'}, 1.3);
		}

	# Check for Ubuntu PHP setting that breaks fcgi
	my $php5conf = "/etc/apache2/mods-enabled/php5.conf";
	if (-r $php5conf) {
		my $lref = &read_file_lines($php5conf, 1);
                foreach my $l (@$lref) {
                        if ($l =~ /^\s*SetHandler/) {
				return &text('check_ewebphp',
				   "<tt>$php5conf</tt>", "<tt>SetHandler</tt>");
                                }
                        }
		}

	# Check for breaking SetHandler lines
	local $conf = &apache::get_config();
	local $fixed = &recursive_fix_sethandler($conf, $conf);
	if ($fixed) {
		&flush_file_lines();
		}

	&$second_print($text{'check_webok'});

	# Check HTTP2 support
	my ($ok, $err) = &supports_http2();
	if ($ok) {
		&$second_print($text{'check_http2ok'});
		}
	else {
		&$second_print(&text('check_http2err', $err));
		}
	}

if (&domain_has_website()) {
	# Check suEXEC / CGI mode
	my @cgimodes = &has_cgi_support();
	if (@cgimodes) {
		&$second_print(&text('check_cgimodes', join(' ', @cgimodes)));
		}
	else {
		&$second_print($text{'check_nocgiscript'});
		}

	# Report on supported PHP modes
	my @supp = grep { $_ ne 'none' } &supported_php_modes();
	if (@supp) {
		&$second_print(&text('check_webphpmodes',
				     join(" ", @supp)));
		}
	else {
		&$second_print($text{'check_ewebphpmodes'});
		}

	# Report on PHP versions (unless it's just FPM, which we cover later)
	local @vers = &list_available_php_versions();
	my @othersupp = grep { !/fpm|none/ } @supp;
	if (@othersupp) {
		local @msg;
		foreach my $v (@vers) {
			if ($v->[1]) {
				local $realv = &get_php_version($v->[0]);
				push(@msg, ($realv ||$v->[0])." (".$v->[1].")");
				}
			else {
				push(@msg, $v->[0]." (mod_php)");
				}
			}
		if (@msg) {
			&$second_print(&text('check_webphpvers',
					     join(", ", @msg)));
			}
		else {
			&$second_print(&ui_text_color($text{'check_webphpnovers'}, 'warn'));
			}
		}

	# Check for PHP-FPM support
	my @fpms = &list_php_fpm_configs();
	if (!@fpms) {
		&$second_print($text{'check_webphpnofpm2'});
		}
	else {
		my @okfpms = grep { !$_->{'err'} } @fpms;
		my @errfpms = grep { $_->{'err'} } @fpms;
		if (@okfpms) {
			&$second_print(&text('check_webphpfpm2',
			  join(" ", map { $_->{'version'}.
				  " (".($_->{'package'} || $_->{'cmd'}).")" } @okfpms)));
			}
		if (@errfpms) {
			&$second_print(&text('check_ewebphpfpm2',
				join(" ", map { $_->{'version'}." ".
					"(".$_->{'err'}.")" } @errfpms)));
			}

		if (@okfpms > 1) {
			# Fix any port clashes for non-Virtualmin pools
			my %used;
			foreach my $conf (@okfpms) {
				my @pools = &list_php_fpm_pools($conf);
				my $restart = 0;
				foreach my $p (@pools) {
					my $pd = &get_domain($p);
					next if ($pd);
					my $t = get_php_fpm_pool_config_value(
						$conf, $p, "listen");
					# If returned "$t" is "127.0.0.1:9000", 
					# then extract the port number
					if ($t && $t =~ /\S+:(\d+)/) {
						$t = $1;
						}
					if ($t && $t =~ /^\d+$/ && $used{$t}++) {
						# Port is wrong!
						&$second_print(&text('check_webphpfpmport',
							$conf->{'shortversion'}, $t));
						while($used{$t}) {
							$t = &increase_fpm_port($t) || 9001;
							}
						$used{$t}++;
						&save_php_fpm_pool_config_value(
						    $conf, $p, "listen", $t);
						$restart++;
						}
					}
				if ($restart) {
					&restart_php_fpm_server($conf);
					}
				}
			}

		# Fix FPM versions that aren't enabled at boot
		my @bootfpms = grep { $_->{'init'} && !$_->{'enabled'}} @okfpms;
		foreach my $conf (@bootfpms) {
			&foreign_require("init");
			&$second_print(&text('check_webfpmboot', $conf->{'shortversion'}));
			&init::enable_at_boot($conf->{'init'});
			}

		# Check if the custom FPM binary path is a valid
		if ($config{'php_fpm_cmd'} && !-e $config{'php_fpm_cmd'}) {
			&$second_print(&text('check_ewebphpcustomcmd',
				"<tt>$config{'php_fpm_cmd'}</tt>"));
			}
		if ($config{'php_fpm_cmd'} &&
		    $config{'php_fpm_pool'} && !-d $config{'php_fpm_pool'}) {
			&$second_print(&text('check_ewebphpcustompool',
				"<tt>$config{'php_fpm_pool'}</tt>"));
			}

		# Check for invalid FPM versions, in case one has been
		# upgraded to a new release
		my @fpmfixed;
		foreach my $d (grep { &domain_has_website($_) &&
				      !$_->{'alias'} } &list_domains()) {
			# Check if an FPM version is stored in domain config
			my $dv = $d->{'php_fpm_version'};
			my $mode = &get_domain_php_mode($d);
			next if ($mode ne "fpm");
			# Version set in domain config exists in the list of
			# FPMs, so skip it, all good
			my ($f) = grep { $_->{'shortversion'} eq $dv ||
					 $_->{'version'} eq $dv } @fpms;
			next if ($f);

			# Try to detect actually configured version
			$dv = &detect_php_fpm_version($d);
			# If still none exists do nothing
			next if (!$dv);
			
			&lock_domain($d);
			$d->{'php_fpm_version'} = $dv;
			&save_domain($d);
			&unlock_domain($d);
			push(@fpmfixed, $d);
			}
		if (@fpmfixed) {
			&$second_print(&text('check_webphpverfixed',
					     scalar(@fpmfixed)));
			}

		# Fix numeric ports for any Virtualmin domains
		foreach my $conf (@okfpms) {
			my @pools = &list_php_fpm_pools($conf);
			my $changed = 0;
			foreach my $p (@pools) {
				my $t = get_php_fpm_pool_config_value(
					$conf, $p, "listen");
				if ($t =~ /^\d+$/) {
					$t = "localhost:".$t;
					&save_php_fpm_pool_config_value(
					    $conf, $p, "listen", $t);
					$changed++;
					}
				}
			if ($changed) {
				&$second_print(&text('check_webphplocalfixed',
					     $changed, $conf->{'shortversion'}));
				&$second_print(&text('check_fpmrestart', $conf->{'shortversion'}));
				&push_all_print();
				&set_all_null_print();
				&restart_php_fpm_server($conf);
				&pop_all_print();
				}
			}

		}

	# Check for any unsupported mod_php directives
	if (!&get_apache_mod_php_version()) {
		my $changed = 0;
		foreach my $d (grep { $_->{'web'} } &list_domains()) {
			my @ports = ( $d->{'web_port'},
			      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
			foreach my $p (@ports) {
				my ($virt, $vconf, $conf) =
					&get_apache_virtual($d->{'dom'}, $p);
				next if (!$vconf);
				my @admin = &apache::find_directive(
					"php_admin_value", $vconf);
				if (@admin) {
					&apache::save_directive(
					 "php_admin_value", [], $vconf, $conf);
					$changed++;
					}
				}
			}
		if ($changed) {
			&$second_print(&text('check_webadminfixed',
				"<tt>php_admin_value</tt>", $changed));
			&flush_file_lines();
			&register_post_action(\&restart_apache);
			}
		}

	# Check if any new PHP versions have shown up, and re-generate their
	# cgi and fcgid wrappers and INI files
	local @newvernums = sort { $a <=> $b } map { $_->[0] } &unique(@vers);
	local @oldvernums = sort { $a <=> $b } split(/\s+/, $config{'last_check_php_vers'});
	if (join(" ", @newvernums) ne join(" ", @oldvernums)) {
		my $indented_print;
		foreach my $d (grep { &domain_has_website($_) &&
				      !$_->{'alias'} }
				    &list_domains()) {
			eval {
				local $main::error_must_die = 1;
				local $mode = $d->{'php_mode'} ||
					      &get_domain_php_mode($d);
				if ($mode && $mode ne "mod_php" &&
				    $mode ne "fpm" && $mode ne "none") {
					if (!$indented_print++) {
						&$first_print(&text('check_webphpversinis',
							join(", ", @newvernums)));
						&$indent_print();
						}
					&$first_print(&text('check_webphpversd',
						&show_domain_name($d)));
					&obtain_lock_web($d);
					&save_domain_php_mode($d, $mode);
					&clear_links_cache($d);
					&release_lock_web($d);
					&$second_print($text{'setup_done'});
					}
				};
			}
		&$outdent_print(), &$second_print("") if ($indented_print);
		$config{'last_check_php_vers'} = join(" ", @newvernums);
		}
	}

if ($config{'webalizer'}) {
	# Make sure Webalizer is installed
	my $err = &feature_depends_webalizer();
	return $err if ($err);
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
	local ($aver, $amods) = &apache::httpd_info(&apache::find_httpd());
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
	&require_mysql();
	if ($config{'provision_mysql'}) {
		# Only MySQL client is needed
		&foreign_installed("mysql") ||
			return &text('index_emysql2', "/mysql/", $clink);
		&$second_print($text{'check_mysqlok'});
		}
	else {
		# MySQL server is needed
		my $mysql_server_status = &foreign_installed("mysql", 1);
		my ($defmysql) = grep {
			$_->{'config'}->{'virtualmin_default'} &&
			$_->{'dbtype'} eq 'mysql'
			} &list_remote_mysql_modules();
		if ($defmysql && $defmysql->{'host'}) {
			&$second_print($text{'check_mysqlok3'});
			}
		elsif ($mysql_server_status != 2) {
			return &text('index_emysql', "/mysql/", $clink);
			}
		else {
			my ($mysql_ver) = &get_dom_remote_mysql_version();
			if ($mysql::mysql_pass eq '') {
				if (defined(&mysql::mysql_login_type) &&
				    &mysql::mysql_login_type($mysql::mysql_login || 'root')) {
					# Using socket authentication
					&$second_print(&text('check_mysqlnopasssocket', $mysql_ver));
					}
				else {
					&$second_print(&text('check_mysqlnopass',
							'/mysql/root_form.cgi', $mysql_ver));
					}
				}
			else {
				&$second_print(&text('check_mysqlok', $mysql_ver));
				}

			# Update any cached MySQL version
			if (defined(&mysql::save_mysql_version)) {
				&mysql::save_mysql_version();
				}

			# If MYSQL_PWD doesn't work, disable it
			if (defined(&mysql::working_env_pass) &&
			    !&mysql::working_env_pass()) {
				$mysql::config{'nopwd'} = 1;
				&mysql::save_module_config();
				}
			}
		}
	}

if ($config{'postgres'}) {
	# Make sure PostgreSQL is installed
	&require_postgres();
	my ($defpostgres) = grep {
		$_->{'config'}->{'virtualmin_default'} &&
		$_->{'dbtype'} eq 'postgres'
		} &list_remote_mysql_modules();
	if ($defpostgres && $defpostgres->{'host'}) {
		&$second_print($text{'check_postgresok3'});
		}
	else {
		&foreign_installed("postgresql", 1) == 2 ||
			return &text('index_epostgres', "/postgresql/", $clink);
		if (!$postgresql::postgres_sameunix &&
		    $postgresql::postgres_pass eq '') {
			&$second_print(&text('check_postgresnopass',
				     '/postgresql/',
				     $postgresql::postgres_login || 'root'));
			}
		else {
			my $v = &get_dom_remote_postgres_version();
			&$second_print(&text('check_postgresok', $v));
			}
		}
	}

if ($config{'ftp'}) {
	# Make sure ProFTPd is installed, and that the ftp user exists
	my $err = &feature_depends_ftp();
	return $err if ($err);
	&$second_print($text{'check_ftpok'});
	}

if ($config{'logrotate'}) {
	# Make sure logrotate is installed
	&foreign_installed("logrotate", 1) == 2 ||
		return &text('index_elogrotate', "/logrotate/", $clink);
	&foreign_require("logrotate");
	local $ver = &logrotate::get_logrotate_version();
	&compare_versions($ver, 3.6) >= 0 ||
		return &text('index_elogrotatever', "/logrotate/",
				   $clink, $ver, 3.6);

	# Make sure the current config is OK
	local $out = &backquote_with_timeout(
		"$logrotate::config{'logrotate'} -d -f ".
		&quote_path($logrotate::config{'logrotate_conf'})." 2>&1",
		60, 1, 1000);
	if ($? && $out =~ /(.*stat\s+of\s+.*\s+failed:.*)/) {
		return &text('check_elogrotateconf',
			     "<pre>".&html_escape("$1")."</pre>");
		}
	&$second_print($text{'check_logrotateok'});
	}

if ($config{'spam'}) {
	# Make sure SpamAssassin and procmail are installed
	$config{'mail'} ||
		return &text('index_espammail', $clink);
	&foreign_installed("spam", 1) == 2 ||
		return &text('index_espam', "/spam/", $clink);
	&foreign_installed("procmail", 1) == 2 ||
		return &text('index_eprocmail', "/procmail/", $clink);
	local $spamclient = &get_global_spam_client();
	if ($spamclient =~ /^spamassassin/) {
		# Make sure it supports --siteconfigpath
		local $out = &backquote_command("$spamclient -h 2>&1 </dev/null");
		if ($out !~ /\-\-siteconfigpath/) {
			&require_spam();
			local $ver = &spam::get_spamassassin_version();
			return &text('check_espamsiteconfig', $ver);
			}
		}
	local $hasprocmail = &mail_system_has_procmail();
	if ($hasprocmail) {
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

	# Check for spam_white conflict with spamc
	if ($config{'spam_white'}) {
		local ($client, $host, $size) = &get_global_spam_client();
		if ($client eq "spamc") {
			return &text('check_spamwhite', $mclink,
				     "edit_newsv.cgi");
			}
		}

	# If using Postfix, procmail-wrapper must be used and setuid root
	if ($hasprocmail && $mail_system == 0) {
		&require_mail();
		local $mbc = &postfix::get_real_value("mailbox_command");
		local @mbc = &split_quoted_string($mbc);
		$mbc[0] = &has_command($mbc[0]);
		local @st = stat($mbc[0]);
		if (!&has_command($mbc[0])) {
			# Procmail does not exist
			return &text('check_spamwrappercmd', $mbc[0]);
			}
		if ($mbc[0] !~ /\/procmail-wrapper$/) {
			# Command must be the procmail wrapper
			return &text('check_spamwrappercmd2', $mbc[0]);
			}
		if ($st[4] != 0) {
			# User is not root
			local $user = getpwuid($st[4]);
			return &text('check_spamwrapperuser', $mbc[0],
				     $user || "UID $st[4]");
			}
		if ($st[5] != 0) {
			# Group is not root
			local $group = getgrgid($st[5]);
			return &text('check_spamwrappergroup', $mbc[0],
				     $group || "GID $st[5]");
			}
		if (($st[2] & 04000) != 04000) {
			# Not setuid and setgid
			return &text('check_spamwrapperperms', $mbc[0],
				     sprintf("%o", $st[2]));
			}
		# Check for safe flags
		my @safe = ("-o", "-a", "\$DOMAIN", "-d", "\$LOGNAME");
		my $ok = 1;
		for(my $i=0; $i<@safe; $i++) {
			$ok = 0 if ($mbc[$i+1] ne $safe[$i]);
			}
		$ok = 0 if (@mbc != @safe+1);
		if (!$ok) {
			return &text('check_spamwrapperargs',
				$mbc, join(" ", @safe));
			}
		}
	}

if ($config{'virus'}) {
	# Make sure ClamAV is installed and working
	$config{'mail'} ||
		return &text('index_evirusmail', $clink);
	$config{'spam'} || return $text{'check_evirusspam'};
	&full_clamscan_path() ||
		return &text('index_evirus',
			     "<tt>$config{'clamscan_cmd'}</tt>", $clink);
	if ($config{'clamscan_cmd'} eq "clamdscan") {
		# Need clamd to be running
		&find_byname("clamd") || return $text{'check_eclamd'};
		}
	local $err;
	if ($config{'clamscan_cmd_tested'} ne $config{'clamscan_cmd'}) {
		$err = &test_virus_scanner($config{'clamscan_cmd'},
					   $config{'clamscan_host'});
		}
	if ($err) {
		# Failed .. but this can often be due to the ClamAV database
		# being out of date.
		local $freshclam = &has_command("freshclam");
		if (!$freshclam &&
		    $config{'clamscan_cmd'} =~ /^(\/.*\/)[^\/]+$/) {
			$freshclam = $1."freshclam";
			}
		if (-x $freshclam) {
			local $cout = &backquote_with_timeout($freshclam, 180);
			$err = &test_virus_scanner($config{'clamscan_cmd'},
						   $config{'clamscan_host'});
			}
		}
	if ($err) {
		return &text('index_evirusrun2',
			     "<tt>$config{'clamscan_cmd'}</tt>",
			     $err, "edit_newsv.cgi");
		}
	if ($config{'clamscan_cmd_tested'} eq $config{'clamscan_cmd'}) {
		&$second_print($text{'check_virusok2'});
		}
	else {
		$config{'clamscan_cmd_tested'} = $config{'clamscan_cmd'};
		&$second_print($text{'check_virusok'});
		}
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
		return &text('check_eplugin', "<tt>$p</tt>", $err);
		}
	else {
		my $pname = &plugin_call($p, "feature_name");
		&$second_print(&text('check_plugin', $pname));
		}
	}

if (!$config{'iface'}) {
	if (!&running_in_zone()) {
		# Work out the network interface automatically
		$config{'iface'} = &first_ethernet_iface();
		if (!$config{'iface'}) {
			return &text('index_eiface',
				     "../config.cgi?$module_name");
			}
		&lock_file($module_config_file);
		&save_module_config();
		&unlock_file($module_config_file);
		}
	else {
		# In a zone, it is worked out as needed, as it changes!
		$config{'iface'} = undef;
		}
	}
if (!&running_in_zone()) {
	&$second_print(&text('check_ifaceok', "<tt>$config{'iface'}</tt>"));
	}

# Get the default IP address
my $defip = &get_default_ip();
my $defip6;

# Tell user if IPv4 is not enabled
if (!$defip) {
	&$second_print($text{'check_iface4'})
	}

# Tell the user that IPv6 is available
if ($config{'ip6enabled'} && &supports_ip6()) {
	!$config{'netmask6'} || $config{'netmask6'} =~ /^\d+$/ ||
		return &text('check_enetmask6', $config{'netmask6'});
	if (&supports_ip6() == 2) {
		&$second_print(&text('check_iface6',
		    "<tt>".($config{'iface6'} || $config{'iface'})."</tt>"));
		}
	}

# Show the default IPv4 address
if ($config{'ip6enabled'} && &supports_ip6()) {
	$defip6 = &get_default_ip6();
	}
if (!$defip && !$defip6) {
	return &text('index_edefip', "../config.cgi?$module_name");
	}
else {
	&$second_print(&text('check_defip', $defip))
		if (!$defip6);
	}
$config{'old_defip'} ||= $defip;

# Show the default IPv6 address
if ($defip6) {
	&$second_print(&text('check_defip6', $defip6));
	}
$config{'old_defip6'} ||= $defip6;

# Make sure the external IP is set if needed
if ($config{'dns_ip'} ne '*') {
	local $dns_ip = $config{'dns_ip'} || $defip;
	local $ext_ip = &get_any_external_ip_address(1);
	if ($ext_ip && $ext_ip eq $dns_ip) {
		# Looks OK
		&$second_print(&text($config{'dns_ip'} ? 'check_dnsip1' :
				'check_dnsip2', $dns_ip));
		}
	elsif ($ext_ip && $ext_ip ne $dns_ip) {
		# Mis-match .. warn user
		&$second_print(&ui_text_color(&text($config{'dns_ip'} ? 'check_ednsip1' :
				'check_ednsip2', $dns_ip, $ext_ip,
				"../config.cgi?$module_name"), 'warn'));
		}
	}
else {
	my $ext_ip = &get_any_external_ip_address(1);
	if ($ext_ip) {
		my $msg = $ext_ip =~ /:/ ? "check_dnsip3v6" : "check_dnsip3";
		&$second_print(&text($msg, $ext_ip));
		}
	else {
		&$second_print(&ui_text_color($text{'check_ednsip3'}, 'warn'));
		}
	}

# Make sure local group exists
if ($config{'localgroup'} && !defined(getgrnam($config{'localgroup'}))) {
	return &text('index_elocal', "<tt>$config{'localgroup'}</tt>",
			   "../config.cgi?$module_name");
	}

# Validate home directory format
if ($config{'home_base'} && $config{'home_base'} !~ /^\/\S+/) {
	return &text('check_ehomebase', "<tt>$config{'home_base'}</tt>",
		     "../config.cgi?$module_name");
	}
&require_useradmin();
if (!$config{'home_base'} && $uconfig{'home_base'} !~ /^\/\S+/) {
	return &text('check_ehomebase2', "<tt>$uconfig{'home_base'}</tt>",
		     "../config.cgi?useradmin");
	}
if ($config{'home_format'} &&
    $config{'home_format'} !~ /\$\{(USER|UID|DOM|PREFIX)\}/ &&
    $config{'home_format'} !~ /\$(USER|UID|DOM|PREFIX)/) {
	return &text('check_ehomeformat', "<tt>$config{'home_format'}</tt>",
		     "../config.cgi?$module_name");
	}
elsif (!$config{'home_format'} && $uconfig{'home_style'} == 4) {
	return &text('check_ehomestyle', "../config.cgi?useradmin");
	}

$config{'home_quotas'} = '';
$config{'mail_quotas'} = '';
$config{'group_quotas'} = '';
if ($config{'quotas'} && $config{'quota_commands'}) {
	# External commands are being used for quotas - make sure they exist!
	foreach my $c ("set_user", "set_group", "list_users", "list_groups") {
		local ($cmd) = &split_quoted_string(
			$config{"quota_".$c."_command"});
		$cmd && &has_command($cmd) || return $text{'check_e'.$c};
		}
	foreach my $c ("get_user", "get_group") {
		local ($cmd) = &split_quoted_string(
			$config{"quota_".$c."_command"});
		!$cmd || &has_command($cmd) || return $text{'check_e'.$c};
		}
	&$second_print($text{'check_quotacommands'});
	}
elsif ($config{'quotas'}) {
	# Make sure quotas are enabled, and work out where they are needed
	local $qerr;
	&require_useradmin();
	if (!$home_base) {
		$qerr = &text('index_ehomebase');
		}
	elsif (&running_in_zone()) {
		$qerr = &text('index_ezone');
		}
	else {
		local $mail_base = &simplify_path(&resolve_links(
				&mail_system_base()));
		local ($home_mtab, $home_fstab) = &mount_point($home_base);
		local ($mail_mtab, $mail_fstab) = &mount_point($mail_base);
		if (!$home_mtab) {
			$qerr = &text('index_ehomemtab', "<tt>$home_base</tt>");
			}
		elsif (!$mail_mtab) {
			$qerr = &text('index_emailmtab', "<tt>$mail_base</tt>");
			}
		else {
			# Check if quotas are enabled for home filesystem
			local $nohome;
			$home_mtab->[4] = &quota::quota_can($home_mtab,
						            $home_fstab);
			$home_mtab->[4] &&= &quota::quota_now($home_mtab,
                                                              $home_fstab);
			if ($home_mtab->[4] != 3 && $home_mtab->[4] != 7) {
				# User quotas are not active (we need 
				# both user and group quotas being active)
				$nohome++;
				}
			else {
				# User quotas are active
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
						mount_point_bind($home_mtab->[0]);
					$config{'mail_quotas'} =
						mount_point_bind($home_mtab->[0]);
					}
				}
			else {
				# Different .. so check mail too
				local $nomail;
				$mail_mtab->[4] = &quota::quota_can(
                                        $mail_mtab, $mail_fstab);
				$mail_mtab->[4] &&= &quota::quota_now(
					$mail_mtab, $mail_fstab);
				if ($mail_mtab->[4] != 3 && $mail_mtab->[4] != 7) {
					# Mail user quotas are not active (we need 
					# both user and group quotas being active)
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
		# Check if a reboot is needed to enable XFS quotas on /
		if (&needs_xfs_quota_fix() == 1) {
			my $reboot_msg = "\n$text{'licence_xfsreboot'}&nbsp;";
			if (&foreign_available("init")) {
				$reboot_msg .= ui_link("@{[&get_webprefix_safe()]}/init/reboot.cgi", $text{'licence_xfsrebootok'});
				$reboot_msg .= ".";
				}
			&$second_print(&ui_text_color($reboot_msg, 'warn'));
			}
			else {
				&$second_print(&ui_text_color($qerr, 'warn'));
				}
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
open(SHELLS, "</etc/shells");
while(<SHELLS>) {
	s/\r|\n//g;
	s/#.*$//;
	$shells{$_}++;
	}
close(SHELLS);
local ($nologin_shell, $ftp_shell) = &get_common_available_shells();
if ($nologin_shell && $shells{$nologin_shell->{'shell'}}) {
	&$second_print(&text('check_eshell',
		"<tt>$nologin_shell->{'shell'}</tt>", "<tt>/etc/shells</tt>"));
	}
if ($ftp_shell && !$shells{$ftp_shell->{'shell'}}) {
	&$second_print(&text('check_eftpshell',
		"<tt>$ftp_shell->{'shell'}</tt>", "<tt>/etc/shells</tt>"));
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

# Check for conflicting other-modules calls
if ($config{'unix'} && $config{'other_users'}) {
	# MySQL user creation
	local %mconfig = &foreign_config('mysql');
	if ($mconfig{'sync_create'} || $mconfig{'sync_modify'} ||
	    $mconfig{'sync_delete'}) {
		return &text('check_emysqlsync', '../mysql/list_users.cgi');
		}
	# User and group default quotas
	if ($config{'home_quotas'}) {
		local %qconfig = &foreign_config('quota');
		local @syncs = map { /^sync_(\S+)/; $1 }
				   grep { /^sync_/ } (keys %qconfig);
		if (@syncs) {
			return &text('check_equotasync',
				     join(' , ', map { "<tt>$_</tt>" } @syncs),
				     '../quota/');
			}
		local @gsyncs = map { /^gsync_(\S+)/; $1 }
				   grep { /^gsync_/ } (keys %qconfig);
		if (@gsyncs) {
			return &text('check_egquotasync',
				     join(' , ', map { "<tt>$_</tt>" } @gsyncs),
				     '../quota/');
			}
		}
	}

# Make sure needed compression programs are installed
if (!&has_command("tar")) {
	return &text('check_ebcmd', "<tt>tar</tt>");
	}
local @bcmds = $config{'compression'} == 0 ? ( "gzip", "gunzip" ) :
	       $config{'compression'} == 3 ? ( "zip", "unzip" ) :
	       $config{'compression'} == 4 ? ( "zstd", "unzstd" ) :
	       $config{'compression'} == 1 && $config{'pbzip2'} ? ( "pbzip2" ) :
	       $config{'compression'} == 1 ? ( "bzip2", "bunzip2" ) :
					     ( );
foreach my $bcmd (@bcmds) {
	if (!&has_command($bcmd)) {
		return &text('check_ebcmd', "<tt>$bcmd</tt>");
		}
	}

# If pbzip2 is being used, make sure it is a version that supports
# compressing to stdout
if ($config{'compression'} == 1 && $config{'pbzip2'}) {
	local $out = &backquote_command("pbzip2 -V 2>&1");
	if ($out !~ /Parallel\s+BZIP2\s+v([0-9\.]+)/i) {
		return &text('check_epbzip2out',
			     "<tt>".&html_escape($out)."</tt>");
		}
	local $ver = $1;
	if (&compare_versions($ver, "1.0.4") < 0) {
		return &text('check_epbzip2ver', "1.0.4", $ver);
		}
	}

&$second_print(&text('check_bcmdok'));

# Check if resource limits are supported
if (defined(&supports_resource_limits)) {
	local ($rok, $rmsg) = &supports_resource_limits(1);
	&$second_print(!$rok ? &text('check_reserr', $rmsg) :
		       $rmsg ? &text('check_reswarn', $rmsg) :
			       $text{'check_resok'});
	}

# Check if software packages work, for script installs
if (&foreign_check("software")) {
	&foreign_require("software");
	if (defined(&software::check_package_system)) {
		local $err = &software::check_package_system();
		local $uerr = &software::check_update_system();
		if ($err) {
			&$second_print(&text('check_packageerr', $err));
			}
		elsif ($uerr) {
			&$second_print(&text('check_updateerr', $err));
			}
		else {
			&$second_print(&text('check_packageok'));
			}
		}
	}

# Check if jailkit support is available
my $err = &check_jailkit_support();
if ($err) {
	&$second_print(&text('check_jailkiterr', $err))
		if(!$config{'jailkit_disabled'});
	}
else {
	&$second_print(&text('check_jailkitok'));
	}

# If using the Pro version, make sure the repo licence matches
my %vserial;
if ($virtualmin_pro &&
    &read_env_file($virtualmin_license_file, \%vserial) &&
    $vserial{'SerialNumber'} ne 'GPL') {
	if ($gconfig{'os_type'} eq 'redhat-linux') {
		# Check the YUM config file
		if (!-r $virtualmin_yum_repo) {
			&$second_print(&text('check_eyumrepofile',
					     "<tt>$virtualmin_yum_repo</tt>"));
			}
		else {
			# File exists, but does it contain the right repo line?
			my $lref = &read_file_lines($virtualmin_yum_repo, 1);
			my $found = 0;
			foreach my $l (@$lref) {
				if ($l =~ /baseurl=https?:\/\/([^:]+):([^\@]+)\@(?:$upgrade_virtualmin_host_all)/) {
					if ($1 eq $vserial{'SerialNumber'} &&
					    $2 eq $vserial{'LicenseKey'}) {
						$found = 2;
						}
					else {
						$found = 1;
						}
					last;
					}
				}
			if ($found == 2) {
				&$second_print($text{'check_yumrepook'});
				}
			elsif ($found == 1) {
				&$second_print(&text('check_yumrepowrong',
					"<tt>$virtualmin_yum_repo</tt>"));
				}
			else {
				&$second_print(&text('check_yumrepomissing',
					"<tt>$virtualmin_yum_repo</tt>"));
				}
			}
		}
	elsif ($gconfig{'os_type'} eq 'debian-linux') {
		# Check the APT config file
		if (!-r $virtualmin_apt_repo) {
			&$second_print(&text('check_eaptrepofile',
					     "<tt>$virtualmin_apt_repo</tt>"));
			}
		else {
			# File exists, but does it contain the right repo line?
			my $lref = &read_file_lines($virtualmin_apt_repo, 1);
			my $found = 0;
			my $check_vconf = 0;
			foreach my $l (@$lref) {
				# An old Debian format with login/pass inside
				# of the repo file
				if ($l =~ /^deb(.*?)https?:\/\/([^:]+):([^\@]+)\@(?:$upgrade_virtualmin_host_all)/) {
					if ($2 eq $vserial{'SerialNumber'} &&
					    $3 eq $vserial{'LicenseKey'}) {
						$found = 2;
						}
					else {
						$found = 1;
						}
					last;
					}

				# A new Debian format with auth in a
				# separate file
				if ($l =~ /^deb(.*?)(https):(\/)(\/).*(?:$upgrade_virtualmin_host_all).*$/) {
					$check_vconf = 1;
					}
				}
			if ($check_vconf && -r $virtualmin_apt_auth_file) {
				my $lines = &read_file_contents($virtualmin_apt_auth_file);
				if ($lines =~ /machine\s+(?:$upgrade_virtualmin_host_all)\s+login\s+(\S+)\s+password\s+(\S+)/gmi) {
					if ($1 eq $vserial{'SerialNumber'} &&
					    $2 eq $vserial{'LicenseKey'}) {
						$found = 2;
						}
					else {
						$found = 1;
						}
					}
				}
			if ($found == 2) {
				&$second_print($text{'check_aptrepook'});
				}
			elsif ($found == 1) {
				&$second_print(&text('check_aptrepowrong',
					"<tt>$virtualmin_apt_repo</tt>"));
				}
			else {
				&$second_print(&text('check_aptrepomissing',
					"<tt>$virtualmin_apt_repo</tt>"));
				}
			}
		}
	}

# Display a message about deprecated repos
if ($gconfig{'os_type'} =~ /^(redhat-linux|debian-linux)$/) {
	my $repolines;
	if ($gconfig{'os_type'} eq 'redhat-linux') {
		# File exists, but does it contain correct repo links
		$repolines = &read_file_lines($virtualmin_yum_repo, 1)
			if (-r $virtualmin_yum_repo);
		}
	elsif ($gconfig{'os_type'} eq 'debian-linux') {
		# File exists, but does it contain correct repo links
		$repolines = &read_file_lines($virtualmin_apt_repo, 1)
			if (-r $virtualmin_apt_repo);
		}
	# Does repo file has correct links?
	my $repofound;
	if (defined($repolines)) {
		foreach my $repoline (@$repolines) {
			$repofound++
				# If repo references the upgrade host
				if ($repoline =~ /(?:$upgrade_virtualmin_host_all)/);
			}
		if (!$repofound) {
			&$second_print(&text('check_repoeoutdate',
				       "$virtualmin_link/docs/installation/".
				       	"troubleshooting-repositories/"));
			}
		}
	}

# All looks OK .. save the config
$config{'last_check'} = time()+1;
$config{'disable'} =~ s/user/unix/g;	# changed since last release
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&write_file("$module_config_directory/last-config", \%config);

return undef;
}

# recursive_fix_sethandler(&directive, &config)
# Remove any global SetHandler lines that would run PHP in mod_php mode
sub recursive_fix_sethandler
{
my ($dirs, $conf) = @_;
my $rv = 0;
my @sh = &apache::find_directive("SetHandler", $dirs);
my @newsh;
foreach my $sh (@sh) {
	if ($sh !~ /^application\/x-httpd-php/) {
		push(@newsh, @sh);
		}
	}
if (@sh != @newsh) {
	$rv += @sh - @newsh;
	&apache::save_directive("SetHandler", \@newsh, $dirs, $conf);
	}
foreach my $m (@$dirs) {
	if ($m->{'type'} && $m->{'name'} ne 'VirtualHost') {
		$rv += &recursive_fix_sethandler($m->{'members'}, $conf);
		}
	}
return $rv;
}

# need_update_webmin_users_post_config(&oldconfig)
# Check if we need to Webmin users following a config re-check
sub need_update_webmin_users_post_config
{
local ($lastconfig) = @_;
local $webminchanged = 0;
foreach my $k (keys %config) {
	if ($k eq 'leave_acl' || $k eq 'webmin_modules' ||
	    $k eq 'last_check_php_vers' ||
	    &indexof($k, @features) >= 0) {
		$webminchanged++ if ($config{$k} ne $lastconfig->{$k});
		}
	}
return $webminchanged;
}

# get_beancounters()
# Returns the contents of /proc/user_beancounters for this VM
sub get_beancounters
{
local %beans;
local $inctx = 0;
open(BEANS, "</proc/user_beancounters") || return undef;
while(<BEANS>) {
	if (/^\s*(\d+):/) {
		if ($1 != 0) {
			$inctx = 1;
			}
		else {
			$inctx = 0;
			}
		}
	if (/\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/ && $inctx) {
		$beans{$1} = $5;
		}
	}
close(BEANS);
return \%beans;
}

# run_post_config_actions(&lastconfig)
# Make various changes to the system as specified by a new module config.
# May print stuff.
sub run_post_config_actions
{
local %lastconfig = %{$_[0]};

# Update the domain owner's group
&update_domain_owners_group();

# Update preload settings if changed
if ($config{'preload_mode'} != $lastconfig{'preload_mode'}) {
	&$first_print($text{'check_preload'});
	&update_miniserv_preloads($config{'preload_mode'});
	&restart_miniserv();
	&$second_print($text{'setup_done'});
	}

# Update collectinfo.pl run time
if ($config{'collect_interval'} ne $lastconfig{'collect_interval'}) {
	if ($config{'collect_interval'} eq 'none') {
		&$first_print($text{'check_collectoff'});
		}
	else {
		&$first_print($text{'check_collect'});
		}
	&setup_collectinfo_job();
	&$second_print($text{'setup_done'});
	}

# Re-collect system info
local $info = &collect_system_info();
if ($info) {
        &save_collected_info($info);
        }

# Update spamassassin lock files
if ($config{'spam_lock'} != $lastconfig{'spam_lock'}) {
	&$first_print($config{'spam_lock'} ? $text{'check_spamlockon'}
					   : $text{'check_spamlockoff'});
	&save_global_spam_lockfile($config{'spam_lock'});
	&$second_print($text{'setup_done'});
	}

# Fix default procmail delivery if changed
if ($config{'default_procmail'} != $lastconfig{'default_procmail'}) {
	&setup_default_delivery();
	}

# Re-create API helper command
if ($config{'api_helper'} ne $lastconfig{'api_helper'} ||
	!&has_command(&get_api_helper_command())) {
	&$first_print($text{'check_apicmd'});
	local ($ok, $path) = &create_virtualmin_api_helper_command();
	&$second_print(&text($ok ? 'check_apicmdok' : 'check_apicmderr',
			     $path));
	}

# Create Bash startup profile for PHP alias work on sub-server
# basis, so users could use specific to sub-server PHP version
my $profiled = "/etc/profile.d";
my $profiledphpalias = "$profiled/virtualmin-phpalias.sh";
if (-d $profiled && !-r $profiledphpalias) {
	&$first_print($text{'check_bashphpprofile'});
	my $phpalias =
	"php=\$\(which php 2>/dev/null\)\n".
	"if \[ -x \"\$php\" \]; then\n".
		"  alias php='\$\(phpdom=\"bin/php\" ; \(while [ ! -f \"\$phpdom\" ] && [ \"\$PWD\" != \"/\" ]; do cd \"\$\(dirname \"\$PWD\"\)\" || \"\$php\" ; done ; if [ -f \"\$phpdom\" ] ; then echo \"\$PWD/\$phpdom\" ; else echo \"\$php\" ; fi\)\)'\n".
	"fi\n";
	&write_file_contents($profiledphpalias, $phpalias);
	&$second_print($text{'setup_done'});
	}

# Check LE SSL for hostname
&check_virtualmin_default_hostname_ssl();

# Restart lookup-domain daemon, if need
if ($config{'spam'} && !$config{'no_lookup_domain_daemon'}) {
	&setup_lookup_domain_daemon();
	}

# If bandwidth checking was enabled in the backup, re-enable it now
&setup_bandwidth_job($config{'bw_active'}, $config{'bw_step'} || 1);

# Re-setup script warning job, if it was enabled
if (defined(&setup_scriptwarn_job) && defined($config{'scriptwarn_enabled'})) {
	&setup_scriptwarn_job($config{'scriptwarn_enabled'},
			      $config{'scriptwarn_wsched'});
	}

# Re-setup script updates job, if it was enabled
if (defined(&setup_scriptlatest_job) && $config{'scriptlatest_enabled'}) {
	&setup_scriptlatest_job(1);
	}

# Re-setup spam clearing / retention cron job
&setup_spamclear_cron_job();

# Re-setup the validation cron job based on the saved config
local ($oldjob, $job);
$oldjob = $job = &find_cron_script($validate_cron_cmd);
$job ||= { 'user' => 'root',
	   'active' => 1,
	   'command' => $validate_cron_cmd };
if ($oldjob) {
	&delete_cron_script($validate_cron_cmd);
	}
if ($config{'validate_sched'}) {
	# Re-create cron job
	if ($config{'validate_sched'} =~ /^\@(\S+)/) {
		$job->{'special'} = $1;
		}
	else {
		($job->{'mins'}, $job->{'hours'}, $job->{'days'},
		 $job->{'months'}, $job->{'weekdays'}) =
			split(/\s+/, $config{'validate_sched'});
		delete($job->{'special'});
		}
	&setup_cron_script($job);
	}

# Enable or disable mail client auto-config
if ($config{'mail_autoconfig'} ne '') {
	my @doms = grep { $_->{'mail'} && &domain_has_website($_) &&
			  !$_->{'alias'} } &list_domains();
	foreach my $d (@doms) {
		if ($config{'mail_autoconfig'} eq '1') {
			&enable_email_autoconfig($d);
			}
		else {
			&disable_email_autoconfig($d);
			}
		}
	}
}

# mount_point(dir)
# Returns both the mtab and fstab details for the parent mount for a directory
sub mount_point
{
local $dir = &resolve_links($_[0]);
if ($mount_point_cache{$dir}) {
	# Already found, so no need to re-lookup
	return @{$mount_point_cache{$dir}};
	}
&foreign_require("mount");
local @mounts = &mount::list_mounts();
local @mounted = &mount::list_mounted();
# Exclude swap mounts
local @realmounts = grep { $_->[0] ne 'none' &&
			   $_->[0] ne 'proc' &&
			   $_->[0] ne '/proc' &&
			   $_->[0] !~ /^swap/ &&
			   $_->[1] ne 'none' } @mounts;
if (!@realmounts) {
	# If /etc/fstab contains no real mounts (such as in a VPS environment),
	# then fake it to be the same as /etc/mtab
	@mounts = @mounted;
	}
foreach my $m (sort { length($b->[0]) <=> length($a->[0]) } @mounted) {
	if ($dir eq $m->[0] || $m->[0] eq "/" ||
	    substr($dir, 0, length($m->[0])+1) eq "$m->[0]/") {
		# Found currently mounted parent directory
		local ($m2) = grep { $_->[0] eq $m->[0] } @mounts;
		if ($m2) {
			if ($m2->[2] eq "bind" && $m2->[0] eq $m2->[1]) {
				# Skip loopback mount onto same directory,
				# as any quotas will be defined in the real
				# mount.
				next;
				}
			# Found boot-time mount as well
			$mount_point_cache{$dir} = [ $m, $m2 ];
			return ($m, $m2);
			}
		}
	}
print STDERR "Failed to find mount point for $dir\n";
return ( );
}

# mount_point_bind(dir)
# Check the home to be mounted with other device
sub mount_point_bind
{
my ($mount) = @_;
if (!&has_command("findmnt")) {
	return $mount;
	}
my %uconfig = foreign_config("useradmin");
my %bind_mounts = map { $_ => 1 } split( /\n/m, &backquote_command('findmnt -r | grep -oP \'^(\S+)(?=.*\[\/)\'') );
if (exists($bind_mounts{$uconfig{'home_base'}})) {
	my @device = sub_mount_points($uconfig{'home_base'});
	if (@device) {
		$mount = $device[0]->[1];
		}
	}
return $mount;
}

# sub_mount_points(dir)
# Returns the mtab entries for mounts at or under some directory
sub sub_mount_points
{
local $dir = &resolve_links($_[0]);
&foreign_require("mount");
local @mounted = &mount::list_mounted();
local @rv;
foreach my $m (@mounted) {
	if ($dir eq $m->[0] || &is_under_directory($dir, $m->[0])) {
		push(@rv, $m);
		}
	}
return @rv;
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
		    join("&nbsp;&nbsp;&nbsp;", @fors));

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
				   $_->{'name'}.
				    ($_->{'acl'}->{'desc'} ?
					" ($_->{'acl'}->{'desc'})" : "") ] }
			       @resels ], 5, 1));
	}

# Which system owners can use this template
local @owners = &unique(map { $_->{'user'} } &list_domains());
print &ui_table_row(
	&hlink($text{'tmpl_owners'}, "template_owners"),
	&ui_radio("owners_def", $tmpl->{'owners'} eq "*" ? 1 :
				$tmpl->{'owners'} eq "" ? 2 : 0,
		  [ [ 1, $text{'tmpl_owners_all'} ],
		    [ 2, $text{'tmpl_owners_none'} ],
		    [ 0, $text{'tmpl_owners_sel'} ] ])."<br>\n".
		  &ui_select("owners", [ split(/\s+/, $tmpl->{'owners'}) ],
			     \@owners, 5, 1));
}

# parse_template_basic(&tmpl)
sub parse_template_basic
{
local ($tmpl) = @_;

if (!$tmpl->{'standard'}) {
	$in{'name'} || &error($text{'tmpl_ename'});
	if ($tmpl->{'name'} ne $in{'name'}) {
		$in{'name'} =~ /<|>|\&|"|'/ && &error($text{'tmpl_ename2'});
		$tmpl->{'name'} = $in{'name'};
		}
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
		$tmpl->{'resellers'} || &error($text{'tmpl_eresellers'});
		}
	}

# Save system owners
if ($in{'owners_def'} == 1) {
	$tmpl->{'owners'} = '*';
	}
elsif ($in{'owners_def'} == 2) {
	$tmpl->{'owners'} = '';
	}
else {
	$tmpl->{'owners'} = join(" ", split(/\0/, $in{'owners'}));
	$tmpl->{'owners'} || &error($text{'tmpl_eowners'});
	}
}

# show_template_plugins(&tmpl)
# Outputs HTML for editing emplate options from plugins
sub show_template_plugins
{
# Show plugin-specific template options
my $plugtmpl = "";
foreach my $f (@plugins) {
	if (&plugin_defined($f, "template_input") &&
	    !&plugin_defined($f, "template_section")) {
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
# Parse plugin options
sub parse_template_plugins
{
local ($tmpl) = @_;
foreach my $f (@plugins) {
        if (&plugin_defined($f, "template_parse") &&
	    !&plugin_defined($f, "template_section")) {
		&plugin_call($f, "template_parse", $tmpl, \%in);
		}
	}
}

# list_domain_owner_modules()
# Returns a list of modules that can be granted to domain owners, as array refs
# with module name, description and list of options (optional) entries.
sub list_domain_owner_modules
{
&require_mysql();
my $mytype = $mysql::mysql_version =~ /mariadb/i ? "MariaDB" : "MySQL";
local @rv = (
        [ 'dns', 'BIND DNS Server (for DNS domain)' ],
        [ 'mail', 'Virtual Email (for mailboxes and aliases)' ],
        [ 'web', 'Apache Webserver (for virtual host)' ],
        [ 'webalizer', 'Webalizer Logfile Analysis (for website\'s logs)' ],
        [ 'mysql', $mytype.' Database Server (for database)' ],
        [ 'postgres', 'PostgreSQL Database Server (for database)' ],
        [ 'spam', 'SpamAssassin Mail Filter (for domain\'s config file)' ],
        [ 'filemin', 'File Manager (home directory only)' ],
        [ 'passwd', 'Change Password',
	  [ [ 2, 'User and mailbox passwords' ],
	    [ 1, 'User password' ],
	    [ 0, 'No' ] ] ],
        [ 'proc', 'Running Processes (user\'s processes only)',
	  [ [ 2, 'See own processes' ],
	    [ 1, 'See all processes' ],
	    [ 0, 'No' ] ] ],
        [ 'cron', 'Scheduled Cron Jobs (user\'s Cron jobs)' ],
        [ 'at', 'Scheduled Commands (user\'s commands)' ],
        [ 'telnet', 'SSH Login' ],
        [ 'xterm', 'Terminal' ],
        [ 'updown', 'Upload and Download (as user)',
	  [ [ 1, 'Yes' ],
	    [ 0, 'No' ],
	    [ 2, 'Upload only' ] ] ],
        [ 'change-user', 'Change Language and Theme' ],
        [ 'htaccess-htpasswd', 'Protected Web Directories (under home directory)' ],
        [ 'mailboxes', 'Read User Mail (users\' mailboxes)' ],
        [ 'custom', 'Custom Commands' ],
        [ 'shell', 'Command Shell (run commands as admin)' ],
        [ 'webminlog', 'Webmin Actions Log (view own actions)' ],
        [ 'logviewer', 'System Logs (view Apache and FTP logs)' ],
        [ 'phpini', 'PHP Configuration (for domain\'s php.ini files)' ],
	);
&load_plugin_libraries();
foreach my $p (@plugins) {
	if (&plugin_defined($p, "feature_modules")) {
		push(@rv, &plugin_call($p, "feature_modules"));
		}
	}
return @rv;
}

# show_template_avail(&tmpl)
# Output HTML for selecting modules available to domain owners
sub show_template_avail
{
local ($tmpl) = @_;
local $field;
if (!$tmpl->{'default'}) {
	local @inames = map { "avail_".$_->[0] } &list_domain_owner_modules();
	local $dis1 = &js_disable_inputs(\@inames, [ ], 'onClick');
	local $dis2 = &js_disable_inputs([ ], \@inames, 'onClick');
	$field .= &ui_radio("avail_def", $tmpl->{'avail'} ? 0 : 1,
			    [ [ 1, $text{'tmpl_avail1'}, $dis1 ],
			      [ 0, $text{'tmpl_avail0'}, $dis2 ] ])."<br>\n";
	}
$field .= &ui_columns_start(
	[ $text{'tmpl_availmod'}, $text{'tmpl_availyes'} ]);
my $alist;
if ($tmpl->{'default'} || $tmpl->{'avail'}) {
	$alist = $tmpl->{'avail'};
	}
else {
	# Initial selection comes from default template
	my $deftmpl = &get_template(0);
	$alist = $deftmpl->{'avail'};
	}
my %avail = map { split(/=/, $_, 2) } split(/\s+/, $alist);
# If not set yet, assumed enabled for plugins
foreach my $p (@plugins) {
	if ($avail{$p} eq '') {
		$avail{$p} = 1;
		}
	}
foreach my $m (&list_domain_owner_modules()) {
	my $minp;
	if ($m->[2]) {
		$minp = &ui_radio("avail_".$m->[0], int($avail{$m->[0]}),
				  $m->[2]);
		}
	else {
		$minp = &ui_yesno_radio("avail_".$m->[0], int($avail{$m->[0]}));
		}
	my @h = ( $m->[1], "config_avail_".$m->[0] );
	$field .= &ui_columns_row([
		-r &help_file($module_name, $h[1]) ? &hlink(@h) : $m->[1], $minp ]);
	}
$field .= &ui_columns_end();
print &ui_table_row(undef, $field, 2);
}

# parse_template_avail(&tmpl)
# Update the list of modules available to domain owners
sub parse_template_avail
{
local ($tmpl) = @_;
if ($in{'avail_def'}) {
	$tmpl->{'avail'} = undef;
	}
else {
	local @avail;
	foreach my $m (&list_domain_owner_modules()) {
		push(@avail, $m->[0].'='.$in{'avail_'.$m->[0]});
		}
	$tmpl->{'avail'} = join(' ', @avail);
	}
}

# show_template_virtualmin(&tmpl)
# Outputs HTML for editing core Virtualmin template options
sub show_template_virtualmin
{
local ($tmpl) = @_;

# Automatic alias domain
local @afields = ( "domalias", "domalias_type", "domalias_tmpl" );
print &ui_table_row(&hlink($text{'tmpl_domalias'}, "template_domalias"),
	&none_def_input("domalias", $tmpl->{'domalias'},
			$text{'tmpl_aliasset'},
			undef, undef, $text{'no'}, \@afields)."\n".
	&ui_textbox("domalias", $tmpl->{'domalias'} eq "none" ? undef :
				$tmpl->{'domalias'}, 30));

# Suffix for alias domain
my $mode = $tmpl->{'domalias_type'} eq '0' ? 0 :
	   $tmpl->{'domalias_type'} eq '' ? 0 :
	   $tmpl->{'domalias_type'} eq '1' ? 1 : 2;
print &ui_table_row(&hlink($text{'tmpl_domalias_type'},
			   "template_domalias_type"),
	    &ui_radio("domalias_type", $mode,
	      [ [ 0, $text{'tmpl_domalias_type0'} ],
		[ 1, $text{'tmpl_domalias_type1'} ],
		[ 2, $text{'tmpl_domalias_type2'}." ".
		     &ui_textbox("domalias_tmpl",
			$mode == 2 ? $tmpl->{'domalias_type'} : "", 20) ] ]));

# Automatic domain disabling
print &ui_table_row($text{'disable_autodisable'},
	&ui_opt_textbox(
		"domauto_disable", 
		$tmpl->{'domauto_disable'}, 4,
		$text{'no'},
		$text{'disable_autodisable_in'}));
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
	if ($in{'domalias_type'} == 2) {
		$in{'domalias_tmpl'} =~ /^\S+$/ ||
			&error($text{'tmpl_edomaliastmpl'});
		$tmpl->{'domalias_type'} = $in{'domalias_tmpl'};
		}
	else {
		$tmpl->{'domalias_type'} = $in{'domalias_type'};
		}
	}

# Parse automatic domain disabling
my $auto_disable = $in{'autodisable_def'} ? undef : $in{'domauto_disable'};
if (defined($auto_disable)) {
	$auto_disable =~ /^\d+$/ || &error($text{'disable_save_eautodisable'});
	$auto_disable <= 0 && &error($text{'disable_save_eautodisable'});
	$auto_disable > 365*10 && &error($text{'disable_save_eautodisable2'});
	$tmpl->{'domauto_disable'} = $auto_disable;
	}
else {
	$tmpl->{'domauto_disable'} = undef;
	}
}

# show_template_autoconfig(&tmpl)
# Outputs HTML for mail client autoconfig XML
sub show_template_autoconfig
{
local ($tmpl) = @_;

# XML for Thunderbird
local $xml;
if ($tmpl->{'autoconfig'} eq "" || $tmpl->{'autoconfig'} eq "none") {
	$xml = &get_thunderbird_autoconfig_xml();
	}
else {
	$xml = join("\n", split(/\t/, $tmpl->{'autoconfig'}));
	}
print &ui_table_row(
	&hlink($text{'tmpl_autoconfig'}, "template_autoconfig"),
	&none_def_input("autoconfig", $tmpl->{'autoconfig'},
			$text{'tmpl_autoconfigset'}, 0, 0,
			$text{'tmpl_autoconfignone'})."<br>\n".
	&ui_textarea("autoconfig", $xml, 20, 80));

# XML for Outlook
if ($tmpl->{'outlook_autoconfig'} eq "" ||
    $tmpl->{'outlook_autoconfig'} eq "none") {
	$xml = &get_outlook_autoconfig_xml();
	}
else {
	$xml = join("\n", split(/\t/, $tmpl->{'outlook_autoconfig'}));
	}
print &ui_table_row(
	&hlink($text{'tmpl_outlook_autoconfig'}, "template_outlook_autoconfig"),
	&none_def_input("outlook_autoconfig", $tmpl->{'outlook_autoconfig'},
			$text{'tmpl_autoconfigset'}, 0, 0,
			$text{'tmpl_autoconfignone'})."<br>\n".
	&ui_textarea("outlook_autoconfig", $xml, 20, 80));
}

# parse_template_autoconfig(&tmpl)
# Updates core mail client autoconfig template options from %in
sub parse_template_autoconfig
{
local ($tmpl) = @_;

# Parse Thunderbird automatic alias domain mode
$tmpl->{'autoconfig'} = &parse_none_def("autoconfig");
if ($in{'autoconfig_mode'} == 2) {
	$in{'autoconfig'} =~ /<clientConfig.*>/i ||
		&error($text{'tmpl_eautoconfig'});
	}

# Parse Outlook automatic alias domain mode
$tmpl->{'outlook_autoconfig'} = &parse_none_def("outlook_autoconfig");
if ($in{'outlook_autoconfig_mode'} == 2) {
	$in{'outlook_autoconfig'} =~ /<Autodiscover.*>/i ||
		&error($text{'tmpl_outlook_eautoconfig'});
	}
}

# postsave_template_autoconfig(&tmpl)
# If mail autoconfig is active, update the template for all domains
sub postsave_template_autoconfig
{
local ($tmpl) = @_;
if ($config{'mail_autoconfig'}) {
	local @doms = grep { $_->{'mail'} && &domain_has_website($_) &&
			     !$_->{'alias'} } &list_domains();
	foreach my $d (@doms) {
		&enable_email_autoconfig($d);
		}
	}
}

# list_template_editmodes([&template])
# Returns a list of available template sections for editing, as array refs
# containing : code, description, &source-plugins
sub list_template_editmodes
{
local ($tmpl) = @_;
local @rv = grep { $sfunc = "show_template_".$_;
                   defined(&$sfunc) &&
                    ($config{$_} || !$isfeature{$_} || $_ eq 'mail' ||
		     $_ eq 'web' || $_ eq 'ssl') }
                 @template_features;
if ($tmpl && ($tmpl->{'id'} == 1 || !$tmpl->{'for_parent'})) {
	# For sub-servers only
	@rv = grep { $_ ne 'resources' && $_ ne 'unix' && $_ ne 'webmin' &&
		     $_ ne 'avail' } @rv;
	}
my @rvdesc = map { [ $_,
		     $text{'tmpl_editmode_'.$_} || $text{'feature_'.$_},
		     [ ] ] } @rv;
foreach my $f (@plugins) {
	if (&plugin_defined($f, "template_section")) {
		my ($sid, $sdesc) = &plugin_call($f, "template_section", $tmpl);
		next if (!$sid);
		my ($got) = grep { $_->[0] eq $sid } @rvdesc;
		if ($got) {
			push(@{$got->[2]}, $f);
			}
		else {
			push(@rvdesc, [ $sid, $sdesc, [$f] ]);
			}
		}
	}
return @rvdesc;
}

# substitute_domain_template(string, &domain, [&extra-hash], [html-escape])
# Does $VAR substitution in a string for a given domain, pulling in
# PARENT_DOMAIN variables too
sub substitute_domain_template
{
local ($str, $d, $extra, $escape) = @_;
local %hash = &make_domain_substitions($d, 0);
if ($extra) {
	%hash = ( %hash, %$extra );
	}
return &substitute_virtualmin_template($str, \%hash, $escape);
}

# substitute_virtualmin_template(string, &hash, [html-escape])
# Just calls the standard substitute_template function, but with global
# variables added to the hash
sub substitute_virtualmin_template
{
local ($str, $hash, $escape) = @_;
local %ghash = %$hash;
foreach my $v (&get_global_template_variables()) {
	if ($v->{'enabled'} && !defined($ghash{$v->{'name'}})) {
		$ghash{$v->{'name'}} = $v->{'value'};
		}
	}
if ($escape) {
	# Escape XML / HTML special chars, for example when including in
	# mail client autoconfig template
	foreach my $v (keys %ghash) {
		$ghash{$v} = &html_escape($ghash{$v});
		}
	}
$ghash{'MYSQL_TYPE'} = "MySQL";
if ($config{'mysql'}) {
	&require_mysql();
	$ghash{'MYSQL_TYPE'} = "MariaDB"
		if ($mysql::mysql_version =~ /mariadb/i);
	}
return &substitute_template($str, \%ghash);
}

# populate_default_index_page(&dom, hash)
# Populates defaults for index.html for the given domain
sub populate_default_index_page
{
my ($d, %h) = @_;
my $lpref = 'deftmplt_';
my ($wmport, $wmproto, $wmhost) = &get_miniserv_port_proto();
# Domain defaults
my $ddom = $d->{'dom'};
my $dndis = $d->{'disabled_time'} ? 0 : 1;
my $ddomdef = $d->{'defaultdomain'};
my $diswhy = $d->{'disabled_why'} || $text{"${lpref}tmpltpagedommsglogindescnoreason0"};
$diswhy = "$diswhy." if ($diswhy && $diswhy !~ /[.!?]$/);
my $ddompubhtml = $d->{'public_html_dir'} || 'public_html';
my $deftitle = ($ddomdef ?
		$text{"${lpref}tmpltpagedefhost"} :
			$text{"${lpref}tmpltpagedefdom"});
# Template defaults variables
my $lang = uc('tmpltpagelang');
my $title = uc('tmpltpagetitle');
my $container_type = uc('tmpltpagecontainertype');
my $headtitle = uc('tmpltpageheadtitle');
my $dom = uc('tmpltpagedomname');
my $statushead = uc('tmpltpagedommsg');
my $status = uc('tmpltpagedomstatus');
my $statustext = uc('tmpltpagedommsglogin');
my $statusico = uc('tmpltpagedommsgloginico');
my $dommsglogindesc = uc("tmpltpagedommsglogindesc");
my $dommsgloginlink = uc('tmpltpagedommsgloginlink');
my $pagefooteryear = uc('tmpltpagefooteryear');
# Domain template defaults substitutions
$h{$lang} = $current_lang if (!defined($h{$lang}));
$h{$title} = "$ddom \&mdash;  " . $deftitle
				if (!defined($h{$title}));
$h{$container_type} = $ddomdef ? 'no-max' : undef;
$h{$headtitle} = $deftitle if (!defined($h{$headtitle}));
$h{$dom} = $ddom if (!defined($h{$dom}));
$h{$statushead} = $text{$lpref . lc("$statushead$dndis")} if (!defined($h{$statushead}));
$h{$status} = $text{"${lpref}tmpltpagedomstatus$dndis"} if (!defined($h{$status}));
$h{$statustext} = $text{$lpref . lc("$statustext$dndis")} if (!defined($h{$statustext}));
$h{$statusico} = "⊗" if (!defined($h{$statusico}) && !$dndis);
$h{$dommsglogindesc} = &text($lpref . lc("$dommsglogindesc$dndis"), $dndis ? $ddompubhtml : $diswhy)
						if (!defined($h{$dommsglogindesc}));
$h{$dommsgloginlink} = "$wmproto://$wmhost:$wmport" if (!defined($h{$dommsgloginlink}));
$h{$pagefooteryear} = strftime('%Y',localtime) if (!defined($h{$pagefooteryear}));
# Standard template defaults substitutions
my (@deftmpls) = grep { $_ =~ s/^(\Q$lpref\E)// } keys %text;
foreach my $deftmpl (@deftmpls) {
	my $key = &trim(uc($deftmpl));
	my $value = $text{"$lpref$deftmpl"};
	$h{$key} = $value if (!defined($h{$key}) && $key !~ /\d$/);
	}
return %h;
}

# replace_default_index_page(&dom, content)
# Replaces defaults for index.html for the given template in domain
sub replace_default_index_page
{
my ($d, $content) = @_;
my $ddis = $d->{'disabled_time'};
my $type = ($d->{'defaultdomain'} && !$ddis) ? 'domain' : 'host';
$content =~ s/<x-(main|div)\s+data-type=["']\Q$type\E["'](.*?)<\/x-(main|div)>//gs;
if ($ddis) {
	$content =~ s/<a\s+data-login=["']\Qbutton\E["'](.*?)<\/a>//s,
	$content =~ s/<x-div\s+data-postlogin=["']\Qcontainer\E["'](.*?)<\/x-div>//s,
	$content =~ s/(data-(login|domain)=["'].*?["'].*?)(success)/$1warning/gm;
	$content =~ s/domain\s+font-monospace/$1 text-danger/gm;
	}
$content =~ s/(data-login=["']row["'].*)(col-l.*)(".*)/$1col-lg-8 col-xl-7$3/gm;
$content =~ s/x-(main|div)/$1/g;
return $content;
}

# absolute_domain_path(&domain, path)
# Converts some path to be relative to a domain, like foo.txt or bar/foo.txt or
# ~/bar/foo.txt. Absolute paths are not converted.
sub absolute_domain_path
{
local ($d, $path) = @_;
$d->{'home'} || &error("absolute_domain_path called for $path without a home directory!");
if ($path =~ /^\//) {
	# Already absolute
	return $path;
	}
elsif ($path =~ /^~\/(.*)/) {
	# Relative to home
	return $d->{'home'}.'/'.$1;
	}
else {
	# Also relative to home
	return $d->{'home'}.'/'.$path;
	}
}

# get_init_template(for-subdom)
# Returns the ID of the initially selected template
sub get_init_template
{
local $rv = $_[0] ? $config{'initsub_template'} : $config{'init_template'};
if ($rv > 1 && !-r "$templates_dir/$rv") {
	# Template doesn't exist! Return sensible default
	return $_[0] ? 1 : 0;
	}
return $rv;
}

# set_chained_features(&domain, [&old-domain])
# Updates a domain object, setting any features that are automatically based
# on another. Called from .cgi scripts to activate hidden features (mode 3).
sub set_chained_features
{
local ($d, $oldd) = @_;
foreach my $f (@features) {
	local $cfunc = "chained_$f";
	if (defined(&$cfunc)) {
		local $c = &$cfunc($d, $oldd);
		if (defined($c) && $c ne "") {
			$d->{$f} = $c;
			}
		}
	}
foreach my $f (@plugins) {
	if (&plugin_defined($f, "feature_chained")) {
		my $c = &plugin_call($f, "feature_chained", $d, $oldd);
		if (defined($c) && $c ne "") {
			$d->{$f} = $c;
			}
		}
	}
}

# check_password_restrictions(&user, [webmin-too], [&domain])
# Returns an error if some user's password (from plainpass) is not acceptable
sub check_password_restrictions
{
local ($user, $webmin, $d) = @_;
&require_useradmin();
local $err = &useradmin::check_password_restrictions(
	$user->{'plainpass'}, $user->{'user'}, $user);
return $err if ($err);
if ($d) {
	# Check again with short username
	$err = &useradmin::check_password_restrictions(
		$user->{'plainpass'}, &remove_userdom($user->{'user'}, $d),
		$user);
	return $err if ($err);
	}
if ($webmin) {
	# Check ACL module too
	&foreign_require("acl");
	$err = &acl::check_password_restrictions(
			$user->{'user'}, $user->{'plainpass'});
	return $err if ($err);
	}
if ($user->{'plainpass'} =~ /\\/) {
	# MySQL breaks with backslash passwords
	return $text{'setup_eslashpass'};
	}
return undef;
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

# unlock_domain_name(name)
# Release a lock on some domain name, used to prevent concurrent creation
sub unlock_domain_name
{
local ($name) = @_;
&unlock_file("$domainnames_dir/$name");
}

# merge_domain_config(&d, &newhash, [@&deleted])
# Merge domain configs, possibly delete some keys
sub merge_domain_config
{
my ($d, $newhash, $deleted) = @_;
# Merge the hashes
%$d = (%$d, %$newhash);
# Delete specified keys from the merged hash
delete @{$d}{@$deleted} if @$deleted;
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
local ($subhomequota, $submailquota, $dummy, $subdbquota, $subdbquota_home) =
	&get_domain_user_quotas(@subs);

# Get group usage for the domain
local ($totalhomequota, $totalmailquota) = &get_domain_quota($d);
local $bsize = &quota_bsize("home");
$totalhomequota -= $dbquota_home/$bsize;

# Show home directory file usage, for total, unix user and mail users
local $tmsg = &nice_size($totalhomequota*$bsize);
if ($d->{'quota'} && $totalhomequota > $d->{'quota'}) {
	$tmsg = "<font color=#ff0000><b>$tmsg</b></font>";
	}
local $umsg = &nice_size($duser->{'uquota'}*$bsize);
if ($d->{'uquota'} && $duser->{'uquota'} > $d->{'uquota'}) {
	$umsg = "<font color=#ff0000><b>$umsg</b></font>";
	}
local $mmsg = &nice_size(($homequota+$subhomequota)*$bsize);
print &ui_table_row($text{'edit_allquotah'},
		    &text('edit_quotaby', $tmsg, $umsg, $mmsg), 3);
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
	$total += $dbquota + $subdbquota;
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
		push(@alinks, "<a href='$prog?dom=$a->{'id'}'>".
			      &show_domain_name($a)."</a>");
		}
	local $lr = &ui_links_row(\@alinks);
	$lr =~ s/<br>$//;
	return $lr;
	}

}

# show_password_popup(&domain, [&user], [mode])
# Returns HTML for a link that pops up a password display window
sub show_password_popup
{
local ($d, $user, $mode) = @_;
local $pass = $mode ? $d->{$mode."_pass"} :
	      $user ? $user->{'plainpass'} : $d->{'pass'};
if (&can_show_pass() && $pass) {
	local $link = "showpass.cgi?dom=$d->{'id'}&mode=".&urlize($mode);
	if ($user) {
		$link .= "&amp;user=".&urlize($user->{'user'});
		}
	if (defined(&popup_window_link)) {
		return &popup_window_link($link, $text{'edit_showpass'},
					  500, 70, "no");
		}
	else {
		return "(<a href='$link' onClick='window.open(\"$link\", \"showpass\", \"toolbar=no,menubar=no,scrollbar=no,width=500,height=70,resizable=yes\"); return false'>$text{'edit_showpass'}</a>)";
		}
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
undef(@main::list_domains_cache);
undef(%bsize_cache);
undef(%get_bandwidth_cache);
undef(%main::soft_home_quota);
undef(%main::hard_home_quota);
undef(%main::used_home_quota);
undef(%main::used_home_fquota);
undef(%main::soft_mail_quota);
undef(%main::hard_mail_quota);
undef(%main::used_mail_quota);
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
&lock_file($module_config_file);
$config{'sharedips'} = join(" ", @_);
&save_module_config();
&unlock_file($module_config_file);
}

# list_shared_ip6s()
# Returns a list of extra IPv6 addresses that can be used by virtual servers
sub list_shared_ip6s
{
return split(/\s+/, $config{'sharedip6s'});
}

# save_shared_ip6s(ip6, ...)
# Updates the list of extra IPv6 addresses that can be used by virtual servers
sub save_shared_ip6s
{
&lock_file($module_config_file);
$config{'sharedip6s'} = join(" ", @_);
&save_module_config();
&unlock_file($module_config_file);
}

# is_shared_ip(ip)
# Returns 1 if some IP address is shared among multiple domains (ie. default,
# shared or reseller shared)
sub is_shared_ip
{
local ($ip) = @_;
return 1 if ($ip eq &get_default_ip());
return 1 if (&indexof($ip, &list_shared_ips()) >= 0);
return 1 if ($ip eq &get_default_ip6());
return 1 if (&indexof($ip, &list_shared_ip6s()) >= 0);
if (defined(&list_resellers)) {
	foreach my $r (&list_resellers()) {
		return 1 if ($r->{'acl'}->{'defip'} &&
			     $ip eq $r->{'acl'}->{'defip'});
		return 1 if ($r->{'acl'}->{'defip6'} &&
			     $ip eq $r->{'acl'}->{'defip6'});
		}
	}
return 0;
}

# activate_shared_ip(address, [netmask])
# Create a new virtual interface using some IP address. Returns undef on success
# or an error message on failure.
sub activate_shared_ip
{
local ($ip, $netmask) = @_;
&foreign_require("net");
local @boot = &net::active_interfaces();
local ($iface) = grep { $_->{'fullname'} eq $config{'iface'} } @boot;
if (!$iface) {
	return &text('sharedips_missing', $config{'iface'});
	}
local $vmax = $config{'iface_base'} || int($net::min_virtual_number);
foreach my $b (@boot) {
	$vmax = $b->{'virtual'} if ($b->{'name'} eq $iface->{'name'} &&
				    $b->{'virtual'} > $vmax);
	}
$netmask ||= $net::virtual_netmask || $iface->{'netmask'};
local $virt = { 'address' => $ip,
		'netmask' => $netmask,
		'broadcast' => &net::compute_broadcast($ip, $netmask),
		'name' => $iface->{'name'},
		'virtual' => $vmax+1,
		'up' => 1,
		'desc' => "Virtualmin shared address",
	      };
$virt->{'fullname'} = $virt->{'name'}.":".$virt->{'virtual'};
&net::save_interface($virt);
if (&auto_apply_interface()) {
	&net::apply_network();
	}
else {
	&net::activate_interface($virt);
	}
return undef;
}

# deactivate_shared_ip(address)
# Removes the virtual interface using some IP address. Returns undef on success
# or an error message on failure.
sub deactivate_shared_ip
{
local ($ip) = @_;
&foreign_require("net");
local @boot = &net::boot_interfaces();
local @active = &net::active_interfaces();
local ($b) = grep { $_->{'address'} eq $ip } @boot;
$b || return $text{'sharedips_eboot'};
$b->{'virtual'} eq '' && return $text{'sharedips_ebootreal'};
local ($a) = grep { $_->{'address'} eq $ip } @active;
$a || return $text{'sharedips_eactives'};
$a->{'virtual'} eq '' && return $text{'sharedips_ebootreal'};
&net::delete_interface($b);
&net::deactivate_interface($a);
return undef;
}

# get_available_backup_features([safe-only])
# Returns a list of features for which backups are possible
sub get_available_backup_features
{
local ($safe) = @_;
local @rv;
foreach my $f ($safe ? @safe_backup_features : @backup_features) {
	local $bfunc = "backup_$f";
	if (defined(&$bfunc) &&
	    ($config{$f} ||
	     $f eq "unix" || $f eq "virtualmin" || $f eq "mail")) {
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
if ($f =~ /\|$/) {
	return open($fh, $f);
	}
elsif ($f =~ /\.gz$/i) {
	return open($fh, "gunzip -c ".quotemeta($f)." |");
	}
elsif ($f =~ /\.Z$/i) {
	return open($fh, "uncompress -c ".quotemeta($f)." |");
	}
elsif ($f =~ /\.bz2$/i) {
	return open($fh, &get_bunzip2_command()." -c ".quotemeta($f)." |");
	}
else {
	return open($fh, "<".$f);
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
			$parentdom, $aliasdom, $subdom) } &list_feature_plugins();
@plug = grep { &can_use_feature($_) } @plug;
if ($aliasdom) {
	@plug = grep { $aliasdom->{$_} } @plug;
	}
local %inactive = map { $_, 1 } @plugins_inactive;
push(@rv, map { { 'feature' => $_,
		  'desc' => &plugin_call($_, "feature_name", 0),
		  'plugin' => 1,
		  'auto' => 0,
		  'default' => !$inactive{$_},
		  'enabled' => 1 } } @plug);

return @rv;
}

# list_allowable_features()
# Returns a list of feature and plugin codes that resellers and domain owners
# can be allowed access to
sub list_allowable_features
{
return ( @opt_features, "virt", "virt6", &list_feature_plugins() );
}

# count_domain_users()
# Returns a hash ref from domain IDs to user counts
sub count_domain_users
{
local %rv;
local (%homemap, %doneuser, %gidmap);
foreach my $d (&list_visible_domains()) {
	$homemap{$d->{'home'}} = $d->{'id'};
	$gidmap{$d->{'gid'}} = $d->{'id'} if (!$d->{'parent'});
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
	elsif ($h =~ /^(.*)\/public_html(\/\S+)?$/) {
		# Home is in or under public_html, so he is a web user
		$did = $homemap{$1};
		}
	else {
		# Fallback to trying each domain's home (longest first)
		foreach my $hd (sort { length($b) cmp length($a) }
				     keys %homemap) {
			if ($h =~ /^\Q$hd\E\//) {
				$did = $homemap{$hd};
				last;
				}
			}
		# If THAT still doesn't work, look by GID
		$did = $gidmap{$u->{'gid'}};
		}
	if ($mail_system == 0) {
		# Don't double-count Postfix @ and - users
		local $noat = &replace_atsign($u->{'user'});
		next if ($doneuser{$noat}++);
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
&obtain_lock_unix($d);
local @groups = &list_all_groups();
local ($group) = grep { $_->{'group'} eq $d->{'group'} } @groups;
local $rv;
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
		$rv = 1;
		}
	}
&release_lock_unix($d);
return $rv;
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
&lock_domain($d);
$d->{'backup_excludes'} = join("\t", @$excludes);
&save_domain($d);
&unlock_domain($d);
}

# get_backup_db_excludes(&domain)
# Returns a list of excluded DB or DB.table names
sub get_backup_db_excludes
{
local ($d) = @_;
return split(/\t+/, $d->{'backup_db_excludes'});
}

# save_backup_db_excludes(&domain, &excludes)
# Updates the list of excluded DB or DB.table names
sub save_backup_db_excludes
{
local ($d, $excludes) = @_;
&lock_domain($d);
$d->{'backup_db_excludes'} = join("\t", @$excludes);
&save_domain($d);
&unlock_domain($d);
}

# list_plugin_sections(level)
# Returns a list of right-frame sections defined by Virtualmin plugins.
# Level 0 = master admin, 1 = domain owner, 2 = reseller
sub list_plugin_sections
{
local ($level) = @_;
local $want = $level == 0 ? "for_master" :
	      $level == 1 ? "for_owner" : "for_reseller";
local @rv;
foreach my $p (@plugins) {
		if (&plugin_defined($p, "theme_sections")) {
		foreach my $s (&plugin_call($p, "theme_sections")) {
			if ($s->{$want}) {
				$s->{'plugin'} = $p;
				push(@rv, $s);
				}
			}
		}
	}
return @rv;
}

# get_provider_link()
# Returns HTML for the logo that should be displayed in the theme for the
# Virtualmin hosting provider. In an array context, also returns the image
# URL and link URL, if set.
sub get_provider_link
{
# Does this user's domain's reseller have a logo?
local ($logo, $link, $alt);
local $d = &get_domain_by("user", $remote_user, "parent", "");
if (!$d) {
	# No domain found by user .. but is this user an extra admin?
	if ($access{'admin'}) {
		$d = &get_domain($access{'admin'});
		}
	}
if ($d && $d->{'reseller'} && defined(&get_reseller)) {
	# Domain has a reseller .. check for his logo
	foreach my $r (split(/\s+/, $d->{'reseller'})) {
		local $resel = &get_reseller($r);
		if ($resel->{'acl'}->{'logo'}) {
			$logo = $resel->{'acl'}->{'logo'};
			$link = $resel->{'acl'}->{'link'};
			$alt = $resel->{'acl'}->{'alt'};
			last;
			}
		}
	}
if (!$d && &reseller_admin()) {
	# This user is a reseller .. use his logo
	local $resel = &get_reseller($remote_user);
	if ($resel->{'acl'}->{'logo'}) {
		$logo = $resel->{'acl'}->{'logo'};
		$link = $resel->{'acl'}->{'link'};
		$alt = $resel->{'acl'}->{'alt'};
		}
	}
if (!$logo) {
	# Call back to global config
	$logo = $config{'theme_image'} || $gconfig{'virtualmin_theme_image'};
	$link = $config{'theme_link'} || $gconfig{'virtualmin_theme_link'};
	$alt = $config{'theme_alt'} || $gconfig{'virtualmin_theme_alt'};
	}
if ($logo && $logo ne "none") {
	local $html;
	$html .= "<a href='".&html_escape($link)."' target=_blank>" if ($link);
	$html .= "<img src='".&html_escape($image)."' ".
		 "alt='".&html_escape($alt)."' border=0>";
	$html .= "</a>" if ($link);
	return wantarray ? ( $html, $logo, $link, $alt ) : $html;
	}
else {
	return wantarray ? ( ) : undef;
	}
}

# nice_domains_list(&doms)
# Returns a string listing multiple domains
sub nice_domains_list
{
local ($doms) = @_;
local @ttdoms = map { "<tt>".&show_domain_name($_)."</tt>" } @$doms;
if (@ttdoms > 10) {
	@ttdoms = ( @ttdoms[0..9], &text('index_dmore', @ttdoms-10) );
	}
return join(", ", @ttdoms);
}

# list_available_shells([&domain], [mail])
# Returns a list of shells assignable to domain owners and/or mailboxes.
# Each is a hash ref with keys :
# shell - Path to the shell command
# desc - Human readable description of what this shell grants
# id - One of the classes 'nologin', 'ftp', 'scp' or 'ssh'
# mailbox - Set to 1 if this shell can be used by mailbox users
# owner - Set to 1 if this shell can be used by domain admins
# default - Set to 1 if this is the default shell for the user type,
# avail - Set to 1 if it is available for use
sub list_available_shells
{
local ($d, $mail) = @_;
if (!defined($mail)) {
	$mail = !$d || $d->{'mail'};
	}
local @rv;
if ($list_available_shells_cache{$mail}) {
	return @{$list_available_shells_cache{$mail}};
	}
if (-r $custom_shells_file) {
	# Read shells data file
	open(SHELLS, "<".$custom_shells_file);
	while(<SHELLS>) {
		s/\r|\n//g;
		local %shell = map { split(/=/, $_, 2) } split(/\t+/, $_);
		push(@rv, \%shell);
		}
	close(SHELLS);
	}
if (!@rv) {
	# Fake up from config file and known shells, if there is no custom
	# file or if it is somehow empty.
	push(@rv, { 'shell' => $config{'shell'},
		    'desc' => $mail ? $text{'shells_mailbox'}
				    : $text{'shells_mailbox2'},
		    'mailbox' => 1,
		    'default' => 1,
		    'avail' => 1,
		    'id' => 'nologin' });
	push(@rv, { 'shell' => $config{'ftp_shell'},
		    'desc' => $mail ? $text{'shells_mailboxftp'}
				    : $text{'shells_mailboxftp2'},
		    'mailbox' => 1,
		    'avail' => 1,
		    'id' => 'ftp' });
	if (&has_command("scponly")) {
		push(@rv, { 'shell' => &has_command("scponly"),
			    'desc' => $mail ? $text{'shells_mailboxscp'}
					    : $text{'shells_mailboxscp2'},
			    'mailbox' => 1,
			    'avail' => 1,
			    'id' => 'scp' });
		}
	local (%done, %classes, $defclass);
	local $best_unix_shell;
	foreach my $s (split(/\s+/, $config{'unix_shell'})) {
		if (&has_command($s)) {
			$best_unix_shell = &has_command($s);
			last;
			}
		}
	$best_unix_shell ||= "/bin/sh";
	foreach my $us (&get_unix_shells()) {
		next if (!-r $us->[1]);
		next if ($done{$us->[1]}++);
		local %shell = ( 'shell' => $us->[1],
				 'desc' => $mail ? $text{'shells_'.$us->[0]}
						: $text{'shells_'.$us->[0].'2'},
				 'id' => $us->[0],
				 'owner' => 1,
				 'reseller' => 1 );
		if ($us->[1] eq $best_unix_shell) {
			$shell{'default'} = 1;
			$shell{'avail'} = 1;
			$shell{'mailbox'} = 0;
			$defclass = $us->[0];
			}
		push(@rv, \%shell);
		$classes{$us->[0]}++;
		}
	if (!$defclass) {
		# Default for owners was not found .. use config
		local %shell = ( 'shell' => $best_unix_shell,
				 'desc' => $text{'shells_ssh'},
				 'id' => 'ssh',
				 'owner' => 1,
				 'reseller' => 1,
				 'default' => 1,
				 'avail' => 1 );
		push(@rv, \%shell);
		$classes{'ssh'}++;
		$defclass = 'ssh';
		}
	# Only the default or first of each class are available for each user
	foreach my $c (grep { $_ ne $defclass } keys %classes) {
		foreach my $u ('owner', 'mailbox') {
			my ($firstclass) = grep { $_->{'id'} eq $c &&
						  $_->{$u} } @rv;
			if ($firstclass) {
				$firstclass->{'avail'} = 1;
				}
			}
		}
	}
# Sort based on both description and shell
# name to avoid random ordering
@rv = sort { $a->{'desc'} cmp $b->{'desc'} ||
	     $a->{'shell'} cmp $b->{'shell'} } @rv;

$list_available_shells_cache{$mail} = \@rv;
return @rv;
}

# list_available_shells_by_type('owner'|'mailbox',
# 	['ssh'|'scp'|'ftp'|'nologin'], [include-current-shell])
# Returns a list of shells by given type. If current shell is given
# it will be added to a list of available shells
sub list_available_shells_by_type
{
my ($type, $id, $current_shell) = @_;
my @rv = &available_shells($type, $current_shell);
@rv = grep { $_->{'id'} eq $id } @rv if ($id);
return @rv;
}

# save_available_shells(&shells|undef)
# Updates the list of custom shells available, or resets to the built-in
# defaults if undef is given
sub save_available_shells
{
local ($shells) = @_;
if ($shells) {
	&open_lock_tempfile(SHELLS, ">$custom_shells_file");
	foreach my $s (@$shells) {
		&print_tempfile(SHELLS,
			join("\t", map { $_."=".$s->{$_} } keys %$s),"\n");
		}
	&close_tempfile(SHELLS);
	@list_available_shells_cache = @$shells;
	}
else {
	&unlink_logged($custom_shells_file);
	undef(@list_available_shells_cache);
	}
}

# available_shells('owner'|'mailbox'|'reseller', [value],
#		   ['ssh'|'scp'|'ftp'|'nologin'])
# Returns available shells for a mailbox or domain owner
sub available_shells
{
my ($type, $value, $id) = @_;
$type = [ $type ] if (!ref($type));
my @aashells = &list_available_shells(undef, $mustftp ? 0 : undef);
my @tshells;
foreach my $t (@$type) {
	push(@tshells, grep { $_->{$t} } @aashells);
	}
my %done;
my @ashells = grep { $_->{'avail'} && !$done{$_->{'shell'}}++ } @tshells;
if ($id) {
	# Only return shells with the given IDs
	my @ids = ref($id) ? @$id : ($id);
	@ashells = grep { &indexof($_->{'id'}, @ids) >= 0 } @ashells;
	}
if (defined($value)) {
	# Is current shell on the list?
	my ($got) = grep { $_->{'shell'} eq $value } @ashells;
	if (!$got) {
		($got) = grep { $_->{'shell'} eq $value } @tshells;
		if ($got) {
			# Current exists but is not available .. make it visible
			push(@ashells, $got);
			}
		else {
			# Add unknown shell description if available
			my ($value_desc) = 
				grep { $_->{'shell'} eq $value }
					@aashells;
			# Totally unknown
			if ($value) {
				push(@ashells,
					{ 'id'    => $value_desc->{'id'} ||
					             'unknown',
					  'shell' => $value,
					  'desc'  => $value_desc->{'desc'} ||
					             $value });
				}
			else {
				push(@ashells, { 'shell' => '',
					 'desc' => $text{'shells_none'} });
				}
			}
		}
	}
return @ashells;
}

# available_shells_menu(name, [value], 'owner'|'mailbox'|'reseller',
# 			['ssh'|'scp'|'ftp'|'nologin'])
# Returns HTML for selecting a shell for a mailbox or domain owner
sub available_shells_menu
{
my ($name, $value, $type, $id) = @_;
return &ui_select($name, $value,
	  [ map { [ $_->{'shell'}, $_->{'desc'} ] }
		&available_shells($type, $value, $id) ]);
}

# default_available_shell('owner'|'mailbox'|'reseller')
# Returns the default shell for a mailbox user or domain owner
sub default_available_shell
{
local ($type) = @_;
local @ashells = grep { $_->{$type} && $_->{'avail'} } &list_available_shells();
local ($def) = grep { $_->{'default'} } @ashells;
return $def ? $def->{'shell'} : undef;
}

# check_available_shell(shell, type, [old])
# Returns 1 if some shell is on the available list for this type for the current
# user. Root can use any kind of shell for any user.
sub check_available_shell
{
my ($shell, $type, $old) = @_;
my $ssh = &can_mailbox_ssh();
my @ashells = grep { $ssh || ($_->{$type} && $_->{'avail'}) }
		   &list_available_shells();
my ($got) = grep { $_->{'shell'} eq $shell } @ashells;
return $got || $old && $shell eq $old;
}

# get_common_available_shells()
# Returns the nologin, FTP and jailed FTP shells for mailbox users, some of
# which may be undef. Mainly for legacy use.
sub get_common_available_shells
{
my @ashells = grep { $_->{'mailbox'} && $_->{'avail'} }
		   &list_available_shells();
my ($nologin_shell) = grep { $_->{'id'} eq 'nologin' } @ashells;
my ($ftp_shell) = grep { $_->{'id'} eq 'ftp' } @ashells;
my ($jailed_shell) = grep { $_->{'id'} eq 'ftp' && $_ ne $ftp_shell } @ashells;
my ($def_shell) = grep { $_->{'default'} } @ashells;
return ($nologin_shell, $ftp_shell, $jailed_shell, $def_shell);
}

# create_empty_file(path)
# Creates a new root-owned empty file
sub create_empty_file
{
local ($file) = @_;
&open_tempfile(EMPTY, ">$file", 0, 1);
&close_tempfile(EMPTY);
}

# is_empty_directory(path)
# Returns 1 if a directory contains no files
sub is_empty_directory
{
my ($dir) = @_;
opendir(EMPTYDIR, $dir) || return 0;
my @files = grep { $_ ne "." && $_ ne ".." } readdir(EMPTYDIR);
closedir(EMPTYDIR);
return @files ? 0 : 1;
}

# is_timestamp(unix-timestamp)
# Returns 1 if a given number is a timestamp
sub is_timestamp
{
my ($t) = @_;
return $t =~ /^\d{10}(?:\.\d+)?$/ ? 1 : 0;
}

# is_epochish(value)
# Accept signed epoch seconds with optional fractional part.
# Returns normalized numeric value on success, undef on failure.
sub is_epochish
{
my ($t) = @_;
return undef unless(defined($t) && $t =~ /^-?\d+(?:\.\d+)?$/);
return 0 + $t; # numericize
}

# update_miniserv_preloads(mode)
# Changes the Perl libraries preloaded by miniserv, based on the mode flag.
# This can be 0 for none, 1 for Virtualmin only, or 2 for Virtualmin and
# plugins.
sub update_miniserv_preloads
{
local ($mode) = @_;

local $msc = $ENV{'MINISERV_CONFIG'} || "$config_directory/miniserv.conf";
&lock_file($msc);
local %miniserv;
&get_miniserv_config(\%miniserv);
local @preload;
local $oldpreload = $miniserv{'preload'};
delete($miniserv{'premodules'});
if ($mode == 0) {
	# Nothing to load
	@preload = ( );
	}
else {
	# Do core library and features
	local $vslf = "virtual-server/virtual-server-lib-funcs.pl";
	push(@preload, "virtual-server=$vslf");
	foreach my $f (@features, "virt", "virt6") {
		local $file = "virtual-server/feature-$f.pl";
		push(@preload, "virtual-server=$file");
		}

	# Do new perl module version of Webmin API
	$miniserv{'premodules'} = "WebminCore";
	}
$miniserv{'preload'} = join(" ", &unique(@preload));
&put_miniserv_config(\%miniserv);
&unlock_file($msc);
return $oldpreload ne $miniserv{'preload'};
}

# nice_hour_mins_secs(unixtime, [no-pad], [show-seconds])
# Convert a number of seconds into an HH hours, MM minutes, SS seconds format
sub nice_hour_mins_secs
{
local ($time, $nopad, $showsecs) = @_;
local $days = int($time / (24*60*60));
local $hours = int($time / (60*60)) % 24;
local $mins = sprintf($nopad ? "%d" : "%2.2d", int($time / 60) % 60);
local $secs = sprintf($nopad ? "%d" : "%2.2d", int($time) % 60);
if ($days) {
	return &text('nicetime_days', $days, $hours, $mins, $secs);
	}
elsif ($hours) {
	return &text('nicetime_hours', $hours, $mins, $secs);
	}
elsif ($mins || !$showsecs) {
	return &text('nicetime_mins', $mins, $secs);
	}
else {
	return &text('nicetime_secs', $secs);
	}
}

# short_nice_hour_mins_secs(unixtime)
# Convert a number of seconds into an HH:MM:SS format
sub short_nice_hour_mins_secs
{
local ($time) = @_;
local $days = int($time / (24*60*60));
local $hours = int($time / (60*60)) % 24;
local $mins = sprintf("%2.2d", int($time / 60) % 60);
local $secs = sprintf("%2.2d", int($time) % 60);
return $days ? $days." days, ".$hours.":".$mins.":".$secs :
       $hours ? $hours.":".$mins.":".$secs :
	        $mins.":".$secs;
}

# show_check_migration_features(feature, ...)
# Shows a message about features found in a migration, plus any that are
# not supported. Returns only those that are supported.
sub show_check_migration_features
{
local @got = @_;
local %pconfig = map { $_, 1 } &list_feature_plugins();
local @notgot = grep { !$config{$_} && !$pconfig{$_} } @got;
@got = grep { $config{$_} || $pconfig{$_} } @got;
local @gotmsg = map { &feature_name($_) } @got;
local @notgotmsg = map { &feature_name($_) } @notgot;
&$second_print(".. found ",join(", ", @gotmsg),".");
if (@notgot) {
	&$second_print("<b>However, the follow features are not supported or enabled on your system : ",join(", ", @notgotmsg).". Some functions of the migrated virtual server may not work.</b>");
	}
return @got;
}

# obtain_lock_everything(&domain)
# Obtain locks on everything lockable that this domain has enabled
sub obtain_lock_everything
{
local ($d) = @_;
foreach my $f (@features) {
	local $lfunc = "obtain_lock_".$f;
	if (defined(&$lfunc) && $d->{$d}) {
		&$lfunc($d);
		}
	}
}

# release_lock_everything(&domain)
# Reverses obtain_lock_everything
sub release_lock_everything
{
local ($d) = @_;
foreach my $f (@features) {
	local $lfunc = "release_lock_".$f;
	if (defined(&$lfunc) && $d->{$d}) {
		&$lfunc($d);
		}
	}
}

# obtain_lock_anything(&domain)
# Called by the various obtain_lock_* functions
sub obtain_lock_anything
{
local ($d) = @_;
&lock_domain($d) if ($d && $d->{'id'});
# Assume that we are about to do something important, and so don't want to be
# killed by a SIGPIPE triggered by a browser cancel.
$SIG{'PIPE'} = 'ignore';
$SIG{'TERM'} = 'ignore';
}

# release_lock_anything(&domain)
# Called by the various release_lock_* functions
sub release_lock_anything
{
local ($d) = @_;
&unlock_domain($d) if ($d && $d->{'id'});
}

# virtualmin_api_log(&argv, [&domain], [&suppress-flags])
# Log an action taken by a Virtualmin command-line API call
sub virtualmin_api_log
{
local ($argv, $d, $hide) = @_;

# Parse into flags hash
local (%flags, $lastflag);
local @argv = @$argv;
while(@argv) {
	local $a = shift(@argv);
	if ($a =~ /^\-+(\S+)$/) {
		# A new flag
		$lastflag = $1;
		$flags{$lastflag} = "";
		}
	elsif ($lastflag) {
		# A flag value
		if ($flags{$lastflag} ne "") {
			$flags{$lastflag} .= " ";
			}
		$flags{$lastflag} .= $a;
		}
	if ($a =~ /^[^"' ]+$/) {
		push(@qargv, $a);
		}
	elsif ($a !~ /"/) {
		push(@qargv, "\"$a\"");
		}
	elsif ($a !~ /'/) {
		push(@qargv, "'$a'");
		}
	else {
		push(@qargv, quotemeta($a));
		}
	}
if ($hide) {
	# Hide sensitive fields, like the password
	foreach my $h (@$hide) {
		if ($flags{$h}) {
			$flags{$h} = ("X" x length($flags{$h}));
			}
		my $idx = &indexoflc("--".$h, @qargv);
		if ($idx >= 0) {
			$qargv[$idx+1] = $flags{$h};
			}
		}
	}
$flags{'argv'} = &urlize(join(" ", @qargv));

# Log it
local $script = $0;
$script =~ s/^.*\///;
local $remote_user = "root";
local $WebminCore::remote_user = "root";
local $rh = $ENV{'REMOTE_HOST'};
local $ENV{'REMOTE_HOST'} = $rh || "127.0.0.1";
&webmin_log($main::virtualmin_remote_api ||
	    $ENV{'VIRTUALMIN_REMOTE_API'} ? "remote" : "cmd",
	    $script, $d ? $d->{'dom'} : undef, \%flags);
}

# get_global_template_variables()
# Returns an array of hash refs containing global variable names and values
sub get_global_template_variables
{
if (!scalar(@global_template_variables_cache)) {
	local @rv = ( );
	&open_readfile(GLOBAL, $global_template_variables_file);
	while(<GLOBAL>) {
		s/\r|\n//g;
		local $dis;
		$dis = 1 if (s/^\#+\s*//);
		local ($n, $v) = split(/\s+/, $_, 2);
		push(@rv, { 'name' => $n,
			    'value' => $v,
			    'enabled' => !$dis });
		}
	close(GLOBAL);
	@global_template_variables_cache = @rv;
	}
return @global_template_variables_cache;
}

# save_global_template_variables(&variables)
# Write out the array ref of hash refs of global variables to a file
sub save_global_template_variables
{
local ($vars) = @_;
&open_tempfile(GLOBAL, ">$global_template_variables_file");
foreach my $v (@$vars) {
	&print_tempfile(GLOBAL,
		($v->{'enabled'} ? "" : "#").
		$v->{'name'}." ".$v->{'value'}."\n");
	}
&close_tempfile(GLOBAL);
@global_template_variables_cache = @$vars;
}

# home_relative_path(&domain, path)
# Returns a path relative to a domain's home, if possible
sub home_relative_path
{
local ($d, $file) = @_;
local $l = length($d->{'home'});
if (substr($file, 0, $l+1) eq $d->{'home'}."/") {
	return substr($file, $l+1);
	}
return $file;
}

# update_alias_domain_ips(&domain, &old-domain)
# Called when a domain's IP is changed by adding or removing a virtual IP, to
# update the IPs of an alias domains too. May print stuff.
sub update_alias_domain_ips
{
local ($d, $oldd) = @_;
local @aliases = &get_domain_by("alias", $d->{'id'});
return 0 if (!@aliases);
foreach my $ad (@aliases) {
	next if ($ad->{'ip'} ne $oldd->{'ip'} &&
		 $ad->{'ip6'} ne $oldd->{'ip6'});
	my $oldad = { %$ad };
	if ($ad->{'ip'} eq $oldd->{'ip'}) {
		$ad->{'ip'} = $d->{'ip'};
		}
	if ($oldd->{'ip6'} && $ad->{'ip6'} eq $oldd->{'ip6'}) {
		$ad->{'ip6'} = $d->{'ip6'};
		}
	&$first_print(&text('save_aliasip', $ad->{'dom'}, $d->{'ip'}));
	&$indent_print();
	foreach my $f (@features) {
		local $mfunc = "modify_$f";
		if ($config{$f} && $ad->{$f}) {
			&try_function($f, $mfunc, $ad, $oldad);
			}
		}
	foreach my $f (&list_feature_plugins(1)) {
		if ($ad->{$f}) {
			&plugin_call($f, "feature_modify", $ad, $oldad);
			}
		&plugin_call($f, "feature_always_modify", $ad, $oldad);
		}
	&$outdent_print();
	&lock_domain($ad);
	&save_domain($ad);
	&unlock_domain($ad);
	&$second_print($text{'setup_done'});
	}
}

# get_dns_ip([reseller-name-list])
# Returns the IP address for use in DNS records, or undef to use the domain's IP
sub get_dns_ip
{
local ($reselname) = @_;
if (defined(&get_reseller)) {
	# Check if the reseller has an external IP
	foreach my $r (split(/\s+/, $reselname)) {
		local $resel = &get_reseller($r);
		if ($resel && $resel->{'acl'}->{'defdnsip'}) {
			return $resel->{'acl'}->{'defdnsip'};
			}
		}
	}
if ($config{'dns_ip'} eq '*') {
	local $rv = &get_any_external_ip_address();
	$rv || &error($text{'newdynip_eext'});
	return $rv;
	}
elsif ($config{'dns_ip'}) {
	return $config{'dns_ip'};
	}
return undef;
}

# setup_bandwidth_job(enabled, [hour-step])
# Create or delete the bandwidth monitoring cron job
sub setup_bandwidth_job
{
local ($active, $step) = @_;
$step ||= 1;
&foreign_require("cron");
local $job = &find_bandwidth_job();
if ($job) {
	&delete_cron_script($job);
	}
if ($active) {
	my @hours;
	if ($step == 1) {
		@hours = ( "*" );
		}
	else {
		for(my $h=0; $h<24; $h+=$step) {
			push(@hours, $h);
			}
		}
	$job = { 'user' => 'root',
		 'command' => $bw_cron_cmd,
		 'active' => 1,
		 'mins' => '0',
		 'hours' => join(',', @hours),
		 'days' => '*',
		 'weekdays' => '*',
		 'months' => '*' };
	&setup_cron_script($job);
	}
}

# get_virtualmin_url([&domain])
# Returns a URL for accessing Virtualmin. Never has a trailing /
sub get_virtualmin_url
{
local ($d) = @_;
$d ||= { 'dom' => &get_system_hostname() };
local $rv;
if ($config{'scriptwarn_url'} && !$main::calling_get_virtualmin_url) {
	# From module config
	$main::calling_get_virtualmin_url = 1;
	$rv = &substitute_domain_template($config{'scriptwarn_url'}, $d);
	$rv =~ s/\/$//;
	$main::calling_get_virtualmin_url = 0;
	return $rv;
	}
else {
	# Use new standard function
	return &get_webmin_email_url(undef, undef, 0, $d->{'dom'});
	}
}

# get_domain_url(&domain, [ssl-if-enabled])
# Returns the URL for a domain (with no trailing /)
sub get_domain_url
{
my ($d, $ssl) = @_;
my $linkd;
if ($d->{'linkdom'}) {
	$linkd = &get_domain($d->{'linkdom'});
	}
$linkd ||= $d;
my $ptn = $linkd->{'web_urlport'} || $linkd->{'web_port'};
my $pt = $ptn == 80 || !$ptn ?  "" : ":".$ptn;
return ($ssl && &domain_has_ssl($d) ? "https" : "http").
       "://".$linkd->{'dom'}.$pt;
}

# get_quotas_message()
# Returns the template for email to users who are over quota
sub get_quotas_message
{
local $msg = &read_file_contents($user_quota_msg_file);
if (!$msg) {
	$msg = "You have reached or are approaching your disk quota limit:\n".
	       "\n".
	       "Username:   \${USER}\n".
	       "Domain:     \${DOM}\n".
	       "Email:      \${EMAIL}\n".
	       "Disk quota: \${QUOTA_LIMIT}\n".
	       "Disk usage: \${QUOTA_USED}\n".
	       "Status:     \${IF-QUOTA_PERCENT}Reached \${QUOTA_PERCENT}%\${ELSE-QUOTA_PERCENT}Over quota\${ENDIF-QUOTA_PERCENT}\n".
	       "\n".
	       "Sent by Virtualmin at: \${VIRTUALMIN_URL}\n";
	}
return $msg;
}

# save_quotas_message(message)
# Updates the template for over-quota email message
sub save_quotas_message
{
local ($msg) = @_;
&open_tempfile(QUOTAMSG, ">$user_quota_msg_file");
&print_tempfile(QUOTAMSG, $msg);
&close_tempfile(QUOTAMSG);
}

# get_domain_http_hostname(&domain)
# Returns the best hostname for making HTTP requests
# to some domain, like www.$DOM or just $DOM
sub get_domain_http_hostname
{
my ($d) = @_;
my $host = $d->{'dom'};
foreach my $h ("www.$d->{'dom'}", $d->{'dom'}) {
	my $ip = &to_ipaddress($h);
	my $ip6 = &to_ip6address($h);
	# IPv4
	if ($ip && $ip eq $d->{'ip'}) {
		$host = $h;
		last;
		}
	# IPv6
	elsif ($ip6 && $ip6 eq $d->{'ip6'}) {
		$host = $h;
		last;
		}
	}
if (defined(&get_http_redirect)) {
	my $http_redirect =
	    &get_http_redirect(
	        (&domain_has_ssl($d) ?
	            "https" : "http")."://$host");
	if ($http_redirect->{'host'} =~ /\Q$host\E/) {
		$host = $http_redirect->{'host'};
		}
	}
return $host;
}

# date_to_time(date-string, [gmt], [end-of-day])
# Convert a date string like YYYY-MM-DD or -5 to a Unix time
sub date_to_time
{
local ($date, $gmt, $eod) = @_;
local $rv;
if ($date =~ /^(\d{4})-(\d+)-(\d+)$/) {
	# Date only
	if ($gmt) {
		$rv = timegm(0, 0, 0, $3, $2-1, $1);
		}
	else {
		$rv = timelocal(0, 0, 0, $3, $2-1, $1);
		}
	$rv += 24*60*60-1 if ($eod);
	}
elsif ($date =~ /^\-(\d+)$/) {
	# Some days ago
	$rv = time()-($1*24*60*60);
	}
elsif ($date =~ /^\+(\d+)$/) {
	# Some days in the future
	$rv = time()+($1*24*60*60);
	}
$rv || &usage("Date spec must be like 2007-01-20 or -5 (days ago)");
return $rv;
}

# time_to_date(unix-time)
# Convert a Unix time to a date formatted in YYYY-MM-DD
sub time_to_date
{
local ($secs) = @_;
local @tm = localtime($secs);
return sprintf "%4.4d-%2.2d-%2.2d", $tm[5]+1900, $tm[4]+1, $tm[3];
}

# get_prefix_msg(&domain)
# Returns either "prefix" or "suffix", depending on the mailbox name mode
# set in the template.
sub get_prefix_msg
{
my ($d) = @_;
my $a = $d->{'append_style'};
if (!defined($a)) {
	my $tmpl = &get_template($d->{'template'});
	$a = $tmpl->{'append_style'};
	}
return $a == 0 || $a == 1 || $a == 4 || $a == 7 ? 'suffix' : 'prefix';
}

# compare_versions(ver1, ver2, [&script])
# Returns -1 if ver1 is older than ver2, 1 if newer, 0 if same
sub compare_versions
{
local ($ver1, $ver2, $script) = @_;
if ($script && $script->{'numeric_version'}) {
	# Strict numeric compare
	return $ver1 <=> $ver2;
	}
if ($script && $script->{'release_version'}) {
	# Compare release and version separately
	local ($rel1, $rel2);
	($ver1, $rel1) = split(/-/, $ver1, 2);
	($ver2, $rel2) = split(/-/, $ver2, 2);
	return &compare_versions($ver1, $ver2) ||
               &compare_versions($rel1, $rel2);
	}
return &compare_version_numbers($ver1, $ver2);
}

# clone_virtual_server(&domain, new-domain, [new-user, [new-password]],
# 		       [ip], [ip-already])
# Creates a copy of a virtual server, with a new domain name and perhaps
# username (if top-level). Prints stuff as it progresses. Returns 0 on failure
# or 1 on success.
sub clone_virtual_server
{
local ($oldd, $newdom, $newuser, $newpass, $ip, $virtalready) = @_;

# Create the new domain object, with changes
&$first_print($text{'clone_object'});
local $d = { %$oldd };
local $parent;
local $tmpl = &get_template($d->{'template'});
$d->{'id'} = &domain_id();
$d->{'clone'} = $oldd->{'id'};
$d->{'dom'} = $newdom;
$d->{'owner'} = "Clone of ".($d->{'owner'} || $d->{'dom'});
if (!$d->{'parent'}) {
	# Allocate new UID, GID, prefix, username and group name
	delete($d->{'uid'});
	delete($d->{'gid'});
	delete($d->{'ugid'});
	$d->{'user'} = $newuser;
	$d->{'group'} = $newuser;
	$d->{'ugroup'} = $newuser;
	delete($d->{'mysql_user'});	# Force re-creation of DB name
	delete($d->{'postgres_user'});
	if ($newpass) {
		$d->{'pass'} = $newpass;
		delete($d->{'enc_pass'}); # Any stored encrypted
					  # password is not valid
		}

	# Re-compute email address
	$d->{'emailto'} = $d->{'mail'} ? $d->{'user'}.'@'.$d->{'dom'}
				      : $d->{'user'}.'@'.&get_system_hostname();
	}
else {
	$parent = &get_domain($d->{'parent'});
	}

# Pick a new home directory and prefix
$d->{'home'} = &server_home_directory($d, $parent);
$d->{'prefix'} = &compute_prefix($d->{'dom'}, $d->{'group'}, $parent, 1);
local $pclash = &get_domain_by("prefix", $d->{'prefix'});
if ($pclash) {
	&$second_print(&text('clone_prefixclash',
			     $d->{'prefix'}, $pclash->{'dom'}));
	return 0;
	}
$d->{'db'} = &database_name($d);
$d->{'no_mysql_db'} = 1;	# Don't create DB automatically
$d->{'no_tmpl_aliases'} = 1;	# Don't create any aliases
$d->{'nocreationmail'} = 1;	# Don't re-send post-creation email

# Fix creator
$d->{'created'} = time();
$d->{'creator'} = $remote_user ||  getpwuid($<);

# Fix any paths that refer to old home or ID, like SSL certs
foreach my $k (keys %$d) {
	next if ($k eq "home");	# already fixed
	$d->{$k} =~ s/\Q$oldd->{'home'}\E\//$d->{'home'}\//g;
	$d->{$k} =~ s/\Q$oldd->{'id'}\E/$d->{'id'}/g if ($k =~ /^ssl_/);
	}
&$second_print($text{'setup_done'});

# Pick a new IPv4 address if needed
if ($d->{'virt'} && $ip) {
	# IP specific by caller
	&$first_print(&text('clone_virt2', $ip));
	$d->{'ip'} = $ip;
	$d->{'virtalready'} = $virtalready;
	delete($d->{'dns_ip'});
	&$second_print($text{'setup_done'});
	}
elsif ($d->{'virt'}) {
	# Allocating IP
	&$first_print($text{'clone_virt'});
	if ($tmpl->{'ranges'} eq 'none') {
		&$second_print($text{'clone_virtrange'});
		return 0;
		}
	local ($ip, $netmask) = &free_ip_address($tmpl);
	if (!$ip) {
		&$second_print($text{'clone_virtalloc'});
		return 0;
		}
	$d->{'ip'} = $ip;
	$d->{'netmask'} = $netmask;
	$d->{'virtalready'} = 0;
	delete($d->{'dns_ip'});
	&$second_print(&text('clone_virtdone', $ip));
	}

# Allocate a new IPv6 address if needed
if ($d->{'virt6'}) {
	&$first_print($text{'clone_virt6'});
	if ($tmpl->{'ranges6'} eq 'none') {
		&$second_print($text{'clone_virt6range'});
		return 0;
		}
	local ($ip6, $netmask6) = &free_ip6_address($tmpl);
	if (!$ip6) {
		&$second_print($text{'clone_virt6alloc'});
		return 0;
		}
	$d->{'ip6'} = $ip6;
	$d->{'netmask6'} = $netmask6;
	$d->{'virt6already'} = 0;
	&$second_print(&text('clone_virt6done', $ip6));
	}

# Disable and features that don't support cloning
&$first_print($text{'clone_clash'});
foreach my $f (@features) {
	local $cfunc = "clone_".$f;
	if ($d->{$f} && !defined(&$cfunc)) {
		$d->{$f} = 0;
		}
	}
foreach my $f (@plugins) {
	if ($d->{$f} && !&plugin_defined($f, "feature_clone")) {
		$d->{$f} = 0;
		}
	}

# Check for clashes / depends
local $derr = &virtual_server_depends($d);
if ($derr) {
	&$second_print(&text('clone_dependfound', $derr));
	return 0;
	}
local $cerr = &virtual_server_clashes($d);
if ($cerr) {
	&$second_print(&text('clone_clashfound', $cerr));
	return 0;
	}
&$second_print($text{'setup_done'});

# By default the old chained cert doesn't need to be used by the clone,
# because it won't get copied over and the SSL cert is being re-generated
# anyway.
delete($d->{'ssl_chain'});

# Create it
&$first_print($text{'clone_create'});
&$indent_print();
local $err = &create_virtual_server($d, $parent,
				    $parent ? $parent->{'user'} : undef, 1);
&$outdent_print();
if ($err) {
	&$second_print(&text('clone_createfailed', $err));
	return 0;
	}
&$second_print($text{'setup_done'});

# Run the before clone command
&set_domain_envs($d, "CLONE_DOMAIN", undef, $oldd);
local $merr = &making_changes();
&reset_domain_envs($d);
return &text('setup_emaking', "<tt>$merr</tt>") if (defined($merr));

# Copy across features, mail last so that user DB association works
my @clonefeatures = @features;
if (&indexof("mail", @clonefeatures) >= 0) {
	@clonefeatures = ( ( grep { $_ ne "mail" } @clonefeatures ), "mail" );
	}
foreach my $f (@clonefeatures) {
	if ($d->{$f}) {
		local $cfunc = "clone_".$f;
		&try_function($f, $cfunc, $d, $oldd);
		}
	}
foreach my $f (@plugins) {
	if ($d->{$f}) {
		&try_plugin_call($f, "feature_clone", $d, $oldd);
		}
	}
&lock_domain($d);
&save_domain($d);
&unlock_domain($d);

# Copy across script logs, and then fix paths
# Fix script installer paths in all domains
local $scriptsrc = "$script_log_directory/$oldd->{'id'}";
local $scriptdest = "$script_log_directory/$d->{'id'}";
if (defined(&list_domain_scripts) && -d $scriptsrc) {
	&$first_print($text{'clone_scripts'});
	&copy_source_dest($scriptsrc, $scriptdest);
	local ($olddir, $newdir) = ($oldd->{'home'}, $d->{'home'});
	foreach $sinfo (&list_domain_scripts($d)) {
		my $changed = 0;
		$changed++ if ($sinfo->{'opts'}->{'dir'} =~
		       		s/^\Q$olddir\E\//$newdir\//);
		$changed++ if ($sinfo->{'url'} =~
				s/\/$oldd->{'dom'}/\/$d->{'dom'}/);
		&save_domain_script($d, $sinfo) if ($changed);
		}
	&$second_print($text{'setup_done'});
	}

&run_post_actions();

&set_domain_envs($d, "CLONE_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

return 1;
}

# record_old_uid(uid, [gid])
# Record usage of some UID and perhaps GID to prevent re-use
sub record_old_uid
{
my ($uid, $gid) = @_;
&lock_file($old_uids_file);
my %uids;
&read_file_cached($old_uids_file, \%uids);
$uids{$uid} = 1;
&write_file($old_uids_file, \%uids);
&unlock_file($old_uids_file);
if ($gid) {
	&lock_file($old_gids_file);
	my %gids;
	&read_file_cached($old_gids_file, \%gids);
	$gids{$gid} = 1;
	&write_file($old_gids_file, \%gids);
	&unlock_file($old_gids_file);
	}
}

# check_resolvability(name)
# Returns 1 and the IP if a name can be resolved, or 0 and an error message
sub check_resolvability
{
my ($name) = @_;
local $page = $resolve_check_page."?host=".&urlize($name);
local ($out, $error);
&http_download($resolve_check_host,
	       $resolve_check_port,
	       $page, \$out, \$error, undef, 0, undef, undef, 60, 0, 1);
if ($error) {
	return (0, $error);
	}
elsif ($out =~ /^ok\s+([0-9\.]+)/) {
	return (1, $1);
	}
elsif ($out =~ /^(error|param)\s+(.*)/) {
	return (0, $2);
	}
else {
	return (0, "Unknown response : $out");
	}
}

# domain_has_website([&domain])
# Returns the feature name if a domain has a website, either via apache or a
# plugin. If called without a domain parameter, just return the plugin or
# feature that provides a website.
sub domain_has_website
{
my ($d) = @_;
return 'web' if ((!$d || $d->{'web'}) && $config{'web'});
foreach my $p (&list_feature_plugins()) {
	if ((!$d || $d->{$p}) && &plugin_call($p, "feature_provides_web")) {
		return $p;
		}
	}
return undef;
}

# domain_has_ssl([&domain])
# Returns the feature name if a domain has a website with SSL, either via
# apache or a plugin. If called without a domain parameter, just return the
# plugin or feature that provides an SSL website.
sub domain_has_ssl
{
my ($d) = @_;
return 'ssl' if ((!$d || $d->{'ssl'}) && $config{'ssl'});
foreach my $p (&list_feature_plugins()) {
	if ((!$d || $d->{$p}) && &plugin_call($p, "feature_provides_ssl")) {
		return $p;
		}
	}
return undef;
}

# domain_has_ssl_cert(&domain)
# Returns 1 if a domain has an SSL cert file, even if not used
sub domain_has_ssl_cert
{
my ($d) = @_;
return $d->{'ssl_cert'} && -r $d->{'ssl_cert'} ? 1 : 0;
}

# get_website_log(&domain, [error-log])
# Returns the access or error log for a domain's website. May come from a plugin
sub get_website_log
{
local ($d, $errorlog) = @_;
local $p = &domain_has_website($d);
if ($p eq 'web') {
	return &get_apache_log($d->{'dom'}, $d->{'web_port'}, $errorlog);
	}
elsif ($p) {
	return &plugin_call($p, "feature_get_web_log", $d, $errorlog);
	}
return undef;
}

# get_old_website_log(log, &domain, &old-domain)
# Returns the log path that would have been used in the old domain
sub get_old_website_log
{
local ($alog, $d, $oldd) = @_;
if ($d->{'home'} ne $oldd->{'home'}) {
        $alog =~ s/\Q$d->{'home'}\E/$oldd->{'home'}/;
        }
if ($d->{'dom'} ne $oldd->{'dom'} &&
    !&is_under_directory($d->{'home'}, $alog)) {
        $alog =~ s/\Q$d->{'dom'}\E/$oldd->{'dom'}/;
        }
return $alog;
}

# restart_website_server(&domain, [args])
# Calls the restart function for the webserver for a domain
sub restart_website_server
{
local ($d, @args) = @_;
local $p = &domain_has_website($d);
if ($p eq "web") {
	&restart_apache(@args);
	}
elsif ($p) {
	&plugin_call($p, "feature_restart_web", @args);
	}
}

# save_website_ssl_file(&domain, "cert"|"key"|"ca", file)
# Configure the webserver for some domain to use a file as the SSL cert or key
sub save_website_ssl_file
{
my ($d, $type, $file) = @_;
my $p = &domain_has_website($d);
my $s = &domain_has_ssl($d);
if ($s && $p ne "web") {
	# Update the actual Nginx config
	my $err = &plugin_call($p, "feature_save_web_ssl_file",
			       $d, $type, $file);
	return $err if ($err);
	}
elsif ($s && $p eq "web") {
	# Update the actual Apache config
	&obtain_lock_ssl($d);
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
							$d->{'web_sslport'});
	if (!$virt) {
		&release_lock_ssl($d);
		return "No virtual host found for ".
		       "$d->{'dom'}:$d->{'web_sslport'}";
		}
	my $dir = $type eq 'cert' ? "SSLCertificateFile" :
		     $type eq 'key' ? "SSLCertificateKeyFile" :
		     $type eq 'ca' ? "SSLCACertificateFile" : undef;
	if ($dir eq "SSLCACertificateFile") {
		# Check for the alternate directive
		my ($oldfile) = &apache::find_directive(
			"SSLCertificateChainFile", $vconf);
		if ($oldfile) {
			$dir = "SSLCertificateChainFile";
			}
		}
	if ($dir) {
		&apache::save_directive($dir, $file ? [ $file ] : [ ],
					$vconf, $conf);
		}
	&release_lock_ssl($d);
	if ($dir) {
		&flush_file_lines($virt->{'file'}, undef, 1);
		&register_post_action(\&restart_apache,
				      &ssl_needs_apache_restart());
		}
	}

# Update the domain object
my $k = $type eq 'ca' ? 'ssl_chain' : 'ssl_'.$type;
$d->{$k} = $file;
return undef;
}

# get_website_ssl_file(&domain, "cert"|"key"|"ca")
# Looks up the SSL cert, key or chained CA file for some domain
sub get_website_ssl_file
{
my ($d, $type) = @_;
if ($type eq "combined" || $type eq "everything") {
	# These exist only in the domain's config
	return $d->{"ssl_".$type};
	}
if (&domain_has_ssl($d)) {
	# Get from the actual Apache config
	my $p = &domain_has_website($d);
	if ($p ne "web") {
		return &plugin_call($p, "feature_get_web_ssl_file", $d, $type);
		}
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_sslport'});
	return undef if (!$virt);
	my $dir = $type eq 'cert' ? "SSLCertificateFile" :
		     $type eq 'key' ? "SSLCertificateKeyFile" :
		     $type eq 'ca' || $type eq 'chain' ? "SSLCACertificateFile"
						       : undef;
	return undef if (!$dir);
	my ($file) = &apache::find_directive($dir, $vconf);
	if (!$file && $dir eq "SSLCACertificateFile") {
		# Check for the alternate directive
		$dir = "SSLCertificateChainFile";
		($file) = &apache::find_directive($dir, $vconf);
		}
	if ($type eq "cert" && $file eq $d->{'ssl_combined'} &&
	    $d->{'ssl_cert'}) {
		# The Apache directive points to the combined file, but the
		# cert-only file is what we really want to return
		$file = $d->{'ssl_cert'};
		}
	return $file;
	}
else {
	# Use the domain object
	my $k = $type eq 'ca' ? 'ssl_chain' : 'ssl_'.$type;
	return $d->{$k};
	}
}

# get_website_hostnames(&domain)
# Returns a list of the hostnames this domain's webserver is serving
sub get_website_hostnames
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq "web") {
	my ($virt, $vconf, $conf) =
		&get_apache_virtual($d->{'dom'}, $d->{'web_port'});
	my @rv;
	my $sn = &apache::find_directive("ServerName", $vconf);
	push(@rv, $sn) if ($sn);
	foreach my $sa (&apache::find_directive_struct("ServerAlias", $vconf)) {
		push(@rv, @{$sa->{'words'}});
		}
	return &unique(@rv);
	}
elsif ($p) {
	if (&plugin_defined($p, "feature_get_web_server_names")) {
		my $hn = &plugin_call($p, "feature_get_web_server_names", $d);
		return @$hn if (ref($hn));
		}
	}
return ();
}

# list_ordered_features(&domain, [include-always-features])
# Returns a list of features or plugins possibly relevant to some domain,
# in dependency order for creation.
sub list_ordered_features
{
my ($d, $always) = @_;
my @dom_features = &domain_features($d);
my $p = &domain_has_website($d);
my $s = &domain_has_ssl($d);
my @rv;
foreach my $f (@dom_features, &list_feature_plugins($always)) {
	if ($f eq "web" && $p && $p ne "web") {
		# Replace website feature in ordering with website plugin
		push(@rv, $p, "web");
		}
	elsif ($f eq "ssl" && $s && $s ne "ssl") {
		# Replace SSL feature in ordering with SSL plugin
		push(@rv, $s, "ssl");
		}
	elsif ($f eq $p && $p ne "web" ||
               $f eq $s && $s ne "ssl") {
		# Skip website or SSL plugin feature, as it was inserted above
		}
	else {
		# Some other feature
		push(@rv, $f);
		}
	}
return @rv;
}

# set_virtualmin_user_envs(&user, &domain)
# Set environment variables containing Virtualmin user-specific info
sub set_virtualmin_user_envs
{
local ($user, $d) = @_;
if ($d) {
	$ENV{'USERADMIN_DOM'} = $d->{'dom'};
	}
$ENV{'USERADMIN_EMAIL'} = $d->{'email'};
if ($u->{'extraemail'}) {
	$ENV{'USERADMIN_EXTRAEMAIL'} = join(" ", @{$u->{'extraemail'}});
	}
}

# extract_address_parts(string)
# Given a string that may contain multiple email addresses with real names,
# return a list of just the address parts. Excludes un-qualified addresses
sub extract_address_parts
{
local ($str) = @_;
&foreign_require("mailboxes");
return grep { /^[^@ ]+\@[^@ ]+$/ }
	    map { $_->[0] } &mailboxes::split_addresses($str);
}

# execute_command_via_ssh(host:port, user, pass, command)
# Run some command on a remote system, and return either 1 and the output, or
# 0 and an error message
sub execute_command_via_ssh
{
my ($host, $user, $pass, $cmd) = @_;
my $port;
if ($host =~ s/:(\d+)$//) {
	$port = $1;
	}
my $sshcmd = "ssh".($port ? " -p $port" : "")." ".
	     $config{'ssh_args'}." ".
	     $user."\@".$host." ".
	     $cmd;
my $err;
my $out = &run_ssh_command($sshcmd, $pass, \$err);
if ($err) {
	return (0, $err);
	}
else {
	$out =~ s/^\S+\s+password:.*\n//;	# Strip password prompt
	return (1, $out);
	}
}

# execute_virtualmin_api_command(host, user, pass, proto, command)
# Runs a Virtualmin API command on some system via SSH. Returns
# 0 and the output structure on success, 1 and an error message
# on remote API failure, or 2 and an error message on SSH failure.
sub execute_virtualmin_api_command
{
my ($host, $user, $pass, $proto, $cmd) = @_;
$proto ||= "ssh";
$user ||= "root";
my $out;
if ($proto eq "ssh") {
	# Run the virtualmin command via SSH
	my $sshok;
	($sshok, $out) = &execute_command_via_ssh($host, $user, $pass,
						  "virtualmin ".$cmd);
	if (!$sshok) {
		return (2, $out);
		}
	}
elsif ($proto eq "webmin") {
	# Run via a Webmin API call
	my $webmin = &dest_to_webmin("webmin://$user:$pass\@$host:/tmp");
	eval {
		local $main::error_must_die = 1;
		&remote_foreign_require($webmin, "webmin");
		my @out = &remote_foreign_call($webmin, "webmin",
			"backquote_command", "virtualmin ".$cmd);
		$out = join("", @out);
		};
	if ($@) {
		return (2, "Webmin failed : $@");
		}
	}
my $args = { };
if ($cmd =~ /--(multiline|name-only|id-only)/) {
	$args->{$1} = '';
	}
my $data = &convert_remote_format($out, 0, $cmd, $args, undef);
if ($data->{'error'}) {
	return (1, $data->{'error'});
	}
else {
	return (0, $data->{'data'}, $out);
	}
}

# validate_transfer_host(&domain, destuser, desthost, destpass, proto,
# 			 ignore-clash)
# Checks if a transfer to a remote Virtualmin system is possible
sub validate_transfer_host
{
my ($d, $desthost, $destuser, $destpass, $proto, $overwrite) = @_;

# Cannot transfer a disabled domain
if ($d->{'disabled'}) {
	return $text{'transfer_edisabled'};
	}

my ($status, $out) = &execute_virtualmin_api_command(
	$desthost, $destuser, $destpass, $proto, "list-domains --name-only");
if ($status) {
	# Couldn't connect or run the command
	return &text('transfer_econnect', $out);
	}

# Check for domains clash
if (!$overwrite) {
	my @poss = ( $d );
	push(@poss, &get_domain_by("parent", $d->{'id'}));
	push(@poss, &get_domain_by("alias", $d->{'id'}));
	foreach my $p (@poss) {
		if (&indexoflc($p->{'dom'}, @$out) >= 0) {
			return &text('transfer_already', $p->{'dom'});
			}
		}
	}

# Make sure parent and alias target exists on target
if ($d->{'parent'}) {
	my $parent = &get_domain($d->{'parent'});
	if (&indexoflc($parent->{'dom'}, @$out) < 0) {
		return &text('transfer_noparent', &show_domain_name($parent));
		}
	}
if ($d->{'alias'}) {
	my $alias = &get_domain($d->{'alias'});
	if (&indexoflc($alias->{'dom'}, @$out) < 0) {
		return &text('transfer_noalias', &show_domain_name($alias));
		}
	}

return undef;
}

# transfer_virtual_server(&domain, desthost, destpass, protocol, delete-mode,
# 			  delete-missing-files, replication-mode, show-output,
# 			  reallocate-ip)
# Transfers a domain (and sub-servers) to a destination system, possibly while
# deleting it from the source. Will print stuff while transferring, and returns
# an OK flag.
sub transfer_virtual_server
{
my ($d, $desthost, $destuser, $destpass, $proto, $deletemode, $deletemissing,
    $replication, $showoutput, $reallocate) = @_;

# Get all domains to include
$proto ||= "ssh";
$destuser ||= "root";
my @doms = ( $d );
push(@doms, &get_domain_by("parent", $d->{'id'}));
push(@doms, &get_domain_by("alias", $d->{'id'}));
my @vdoms = grep { $_->{'virt'} } @doms;
$reallocate = 0 if (!@vdoms);

# Get all feature names
my @feats = grep { $config{$_} || $_ eq 'virtualmin' }
	          @backup_features;
push(@feats, &list_backup_plugins());
my $homefmt;
if ($replication) {
	my %remotes = map { $_, 1 } &list_remote_domain_features($d);
	@feats = grep { !$remotes{$_} } @feats;
	$homefmt = &indexof("dir", @feats) >= 0 ? 1 : 0;
	}
else {
	$homefmt = 1;
	}

# Attempt to get the preferred temp dir on the remote system
my $remotetempdir = "/tmp";
my $desturl;
my $webmin;
if ($proto eq "ssh") {
	# Get the temp dir from the webmin config
	$desturl = "ssh://$destuser:$destpass\@$desthost";
	my ($tok, $tout) = &execute_command_via_ssh(
		$desthost, $destuser, $destpass,
		"grep tempdir= /etc/webmin/config");
	if ($tok && $tout =~ /tempdir=(\/\S+)/) {
		$remotetempdir = $1;
		}
	}
elsif ($proto eq "webmin") {
	# Get the temp dir via Webmin call
	$desturl = "webmin://$destuser:$destpass\@$desthost";
	$webmin = &dest_to_webmin($desturl.':/tmp');
	eval {
		local $main::error_must_die = 1;
                &remote_foreign_require($webmin, "webmin");
		$remotetempdir = &remote_foreign_call(
			$webmin, "webmin", "tempname_dir");
		$remotetempdir =~ s/\/\.webmin$//;
		};
	if ($@) {
		return (0, "Webmin call failed : $@");
		}
	}
else {
	return (0, "Unknown protocol $proto");
	}

# Backup all the domains to a temp dir on the remote system
my $remotetemp = "$remotetempdir/virtualmin-transfer-$$";
local $config{'compression'} = 0;
local $config{'zip_args'} = undef;
&$first_print($text{'transfer_backing'});
if (!$showoutput) {
	$print_output = "";
	&push_all_print();
	&set_all_capture_print();
	}
my ($ok, $size, $errdoms) = &backup_domains(
	$desturl.":".$remotetemp,
	\@doms,
	\@feats,
	1,
	0,
	{ },
	$homefmt,
	[ ],
	1,
	1,
	0);
if (!$showoutput) {
	&pop_all_print();
	}
if (!$ok) {
	my @lines = grep { /\S/ } split(/\r?\n/, $print_output);
	my $ll = pop(@lines);
	my $sl = pop(@lines);
	&$second_print($sl);
	&$second_print($ll);
	&$second_print($text{'transfer_ebackup'});
	return 0;
	}
&$second_print($text{'transfer_backingdone'});

my $cleanup_remotetemp = sub {
	if ($proto eq "ssh") {
		&execute_command_via_ssh($desthost, $destuser, $destpass,
					 "rm -rf ".quotemeta($remotetemp));
		}
	elsif ($proto eq "webmin") {
		&remote_foreign_call(
			$webmin, "webmin", "unlink_file", $remotetemp);
		}
	};

# Verify that the destination directory was actually created and contains
# all the expected files
&$first_print($text{'transfer_validating'});
my @lsfiles;
if ($proto eq "ssh") {
	# Run the SSH command
	my ($lsok, $lsout) = &execute_command_via_ssh(
		$desthost, $destuser, $destpass, "ls ".$remotetemp);
	if (!$lsok) {
		&$second_print(&text('transfer_eremotetemp',
				     $remotetemp, $desthost));
		return 0;
		}
	@lsfiles = split(/\r?\n/, $lsout);
	}
elsif ($proto eq "webmin") {
	# Glob the directory
	my $files = &remote_eval($webmin, "webmin",
			'[ glob("'.quotemeta($remotetemp."/*").'") ]');
	@lsfiles = map { /^\Q$remotetemp\E\/(.*)/; $1 } @$files;
	}
my @missing;
foreach my $lsd (@doms) {
	if (&indexof($lsd->{'dom'}.".tar.gz", @lsfiles) < 0) {
		push(@missing, $lsd);
		}
	}
if (@missing) {
	&$cleanup_remotetemp();
	if (@missing == @doms) {
		&$second_print(&text('transfer_empty', $remotetemp));
		}
	else {
		&$second_print(&text('transfer_missing', $remotetemp,
			    join(" ", map { &show_domain_name($_) } @missing)));
		}
	return 0;
	}
&$second_print($text{'transfer_validated'});

# Delete or disable locally, if requested
if ($deletemode == 2) {
	# Delete from this system
	&$first_print(&text('transfer_deleting', &show_domain_name($d)));
	if (!$showoutput) {
		&push_all_print();
		&set_all_null_print();
		}
	my $err = &delete_virtual_server($d);
	if (!$showoutput) {
		&pop_all_print();
		}
	if ($err) {
		&$second_print(&text('transfer_edelete', $err));
		return 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
elsif ($deletemode == 1) {
	# Disable on this system
	&$first_print(&text('transfer_disabling', &show_domain_name($d)));
	if (!$showoutput) {
		&push_all_print();
		&set_all_null_print();
		}
	foreach my $dd (@doms) {
		&disable_virtual_server($dd, 'transfer',
				'Transferred to '.$desthost);
		}
	if (!$showoutput) {
		&pop_all_print();
		}
	&$second_print($text{'setup_done'});
	}

# Restore via an API call to the remote system
&$first_print($text{'transfer_restoring'});
my ($rok, $rerr, $rout) = &execute_virtualmin_api_command(
	$desthost, $destuser, $destpass, $proto,
	"restore-domain --source $remotetemp --all-domains --all-features ".
	"--skip-warnings --continue-on-error ".
	($deletemissing ? "--option dir delete 1 " : "").
	($replication ? "--replication --no-reuid " : "").
	($reallocate ? "--allocate-ip " : "")
	);
if ($showoutput) {
	&$first_print("<pre>".$rout."</pre>");
	}
if ($rok != 0) {
	if ($deletemode == 2) {
		&$second_print(&text('transfer_erestoring3',
				     "<pre>".$rerr."</pre>",
				     $remotetemp, $desthost));
		}
	elsif ($deletemode == 1) {
		&$second_print(&text('transfer_erestoring2',
				     "<pre>".$rerr."</pre>"));
		}
	else {
		&$second_print(&text('transfer_erestoring',
				     "<pre>".$rerr."</pre>"));
		}
	if ($deletemode != 2) {
		&$cleanup_remotetemp();
		}
	return 0;
	}
&$second_print($text{'transfer_restoringdone'});

# Remove temp file from remote system
&$cleanup_remotetemp();

return 1;
}

# get_transfer_hosts()
# Returns previous hosts that transfers have been made to. Each is a tuple
# of hostname and password
sub get_transfer_hosts
{
my $hfile = "$module_config_directory/transfer-hosts";
my %hosts;
&read_file($hfile, \%hosts);
return map { [ $_, split(/\s+/, $hosts{$_}) ] } keys %hosts;
}

# save_transfer_hosts(&host, ...)
# Writes out tuples in the same format as returned by get_transfer_hosts
sub save_transfer_hosts
{
my $hfile = "$module_config_directory/transfer-hosts";
my %hosts = map { $_->[0], $_->[1]." ".($_->[2] || "ssh")." ".
			   ($_->[3] || "root") } @_;
&write_file($hfile, \%hosts);
&set_ownership_permissions(undef, undef, 0600, $hfile);
}

# list_possible_domain_features(&domain)
# Given a domain, returns a list of core features that can possibly be enabled
# or disabled for it
sub list_possible_domain_features
{
my ($d) = @_;
my @rv;
my $aliasdom = $d->{'alias'} ? &get_domain($d->{'alias'}) : undef;
my $subdom = $d->{'subdom'} ? &get_domain($d->{'subdom'}) : undef;
foreach my $f (&domain_features($d)) {
	# Cannot enable features not in alias
	next if ($aliasdom && !$aliasdom->{$f});

	# Don't show features that are globally disabled
	next if (!$config{$f} && defined($config{$f}));

	push(@rv, $f);
	}
return @rv;
}

# forbidden_domain_features(&domain, [creating])
# Returns a list of features that cannot be enabled for some domain
sub forbidden_domain_features
{
my ($d, $new) = @_;
my @rv;
return @rv if ($config{'nocheck_forbidden_domain_features'});
# Not allowed features for a domain matching hostname
if ($d->{'dom'} eq &get_system_hostname()) {
	my @forbidden = ('mail', 'spam', 'virus');
	foreach $ff (@forbidden) {
		# If not already forced-enabled using CLI
		push(@rv, $ff) if (!$d->{$ff} || $new);
		}
	}
return @rv;
}

# filter_possible_domain_features(&features, &domain, [creating])
# Given a list of features, returns only those that aren't forbidden for domain
sub filter_possible_domain_features
{
my ($features, $d, $new) = @_;
my @forbidden = &forbidden_domain_features($d, $new);
@$features = grep {
	my $feature = $_;
        !grep { $feature eq $_ } @forbidden; } @$features;
}

# list_possible_domain_plugins(&domain)
# Given a domain, returns a list of plugin features that can possibly be enabled
# or disabled for it
sub list_possible_domain_plugins
{
my ($d) = @_;
my @rv;
my $aliasdom = $d->{'alias'} ? &get_domain($d->{'alias'}) : undef;
my $subdom = $d->{'subdom'} ? &get_domain($d->{'subdom'}) : undef;
foreach my $f (&list_feature_plugins()) {
	next if (!&plugin_call($f, "feature_suitable",
				$parentdom, $aliasdom, $subdom));
	push(@rv, $f);
	}
return @rv;
}

# list_remote_domain_features(&domain)
# Returns a list of all features for a domain that are on shared storage
sub list_remote_domain_features
{
my ($d) = @_;
my @rv;
foreach my $f (grep { $d->{$_} } &domain_features($d)) {
	my $rfunc = "remote_".$f;
	if (defined(&$rfunc) && &$rfunc($d)) {
		push(@rv, $f);
		}
	}
return @rv;
}

# transname_owned(user|&domain)
# Create a temporary sub-directory owned by some user, and return a filename
# inside it
sub transname_owned
{
my ($user) = @_;
$user = $user->{'user'} if (ref($user));
my $temp = &transname();
if (!$user || $user eq "root") {
	return $temp;
	}
&make_dir($temp, 0755);
&set_ownership_permissions($user, undef, undef, $temp);
my $rv = $temp."/".($$."_".($transname_owned_counter++));
unshift(@main::temporary_files, $rv);
return $rv;
}

# create_virtualmin_api_helper_command()
# Create the API helper for virtualmin core and all plugins
sub create_virtualmin_api_helper_command
{
local @plugindirs = map { &module_root_directory($_) } @plugins;
return &create_api_helper_command([ "$module_root_directory/pro",
				    @plugindirs ]);
}

# load_plugin_libraries([plugin, ...])
# Call foreign_require on some or all plugins, just once
sub load_plugin_libraries
{
local @load = @_;
@load = @plugins if (!@load);
local $loaded = 0;
foreach my $pname (@load) {
	if (!$main::done_load_plugin_libraries{$pname}++) {
		if (&foreign_check($pname)) {
			eval {
				local $main::error_must_die = 1;
				&foreign_require($pname, "virtual_feature.pl");
				};
			if (!$@) {
				$loaded++;
				}
			else {
				my $err = $@;
				$err = &html_strip($err);
				$err =~ s/[\n\r]+/ /g;
				&error_stderr_local($err);
				}
			}
		}
	}
return $loaded;
}

# needs_xfs_quota_fix()
# Checks if quotas are enabled on the /home filesystem in /etc/fstab but
# not for real in /etc/mtab. Returns 0 if all is OK, 1 if just a reboot is
# needed, 2 if GRUB needs to be configured, or 3 if we don't know how to
# fix GRUB.
sub needs_xfs_quota_fix
{
return 0 if ($gconfig{'os_type'} !~ /-linux$/);     # Some other OS
return 0 if (!$config{'quotas'});                   # Quotas not even in use
return 0 if ($config{'quota_commands'});            # Using external commands
&require_useradmin();
return 0 if (!$home_base);                          # Don't know base dir
return 0 if (&running_in_zone());                   # Zones have no quotas
my ($home_mtab, $home_fstab) = &mount_point($home_base);
return 0 if (!$home_mtab || !$home_fstab);          # No mount found?
return 0 if ($home_mtab->[2] ne "xfs");             # Other FS type
return 0 if ($home_mtab->[0] ne "/");               # /home is not on the / FS
return 0 if (!&quota::quota_can($home_mtab,         # Not enabled in fstab
				$home_fstab));
my $now = &quota::quota_now($home_mtab, $home_fstab);
$now -= 4 if ($now >= 4);                           # Ignore XFS always bit
return 0 if ($now);                                 # Already enabled in mtab

# At this point, we are definite in a bad state
my $grubfile = "/etc/default/grub";
return 3 if (!-r $grubfile);

# Check if grub default config was edited after reboot
if (&foreign_check("webmin")) {
	&foreign_require("webmin");
	my $uptime     = webmin::get_system_uptime();
	my $lastreboot = $uptime ? time() - $uptime : undef;
	if ($lastreboot) {
		my @grubfile_stat = stat($grubfile);
		return 0 if ($lastreboot > $grubfile_stat[9]);
		}
	}

my %grub;
&read_env_file($grubfile, \%grub);
return 3 if (!$grub{'GRUB_CMDLINE_LINUX'});

# Enabled already, so just need to reboot
return 1 if ($grub{'GRUB_CMDLINE_LINUX'} =~ /rootflags=\S*uquota,gquota/ ||
	     $grub{'GRUB_CMDLINE_LINUX'} =~ /rootflags=\S*gquota,uquota/);

# Otherwise, flags need adding
return 2;
}

# create_domain_ssh_key(&domain)
# Creates an SSH public and private key for a domain, and returns the public 
# key and an error message.
sub create_domain_ssh_key
{
my ($d) = @_;
return (undef, $text{'setup_esshkeydir'}) if (!$d->{'dir'} || !$d->{'unix'});
return (undef, $text{'setup_esshsshd'}) if (!&foreign_installed("sshd"));
my $sshdir = $d->{'home'}."/.ssh";
my %oldpubs = map { $_, 1 } glob("$sshdir/*.pub");
&foreign_require("sshd");
my $cmd = $sshd::config{'keygen_path'}." -P \"\"";
$cmd = &command_as_user($d->{'user'}, 0, $cmd);
my $out;
my $inp = "\n";
&execute_command($cmd, \$inp, \$out, \$out);
if ($?) {
	return (undef, $out);
	}
my @newpubs = grep { !$oldpubs{$_} } glob("$sshdir/*.pub");
return (undef, $text{'setup_esshnopub'}) if (!@newpubs);
return (&read_file_contents($newpubs[0]), undef);
}

# save_domain_ssh_pubkey(&domain, pubkey)
# Adds an SSH public key to the authorized keys file
sub save_domain_ssh_pubkey
{
my ($d, $pubkey) = @_;
return $text{'setup_esshkeydir'} if (!$d->{'dir'});
my $sshdir = $d->{'home'}."/.ssh";
if (!-d $sshdir) {
	&make_dir_as_domain_user($d, $sshdir, 0700);
	}
my $sshfile = $sshdir."/authorized_keys";
my $ex = -e $sshfile;
&open_tempfile_as_domain_user($d, SSHFILE, ">>$sshfile");
&print_tempfile(SSHFILE, $pubkey."\n");
&close_tempfile_as_domain_user($d, SSHFILE);
&set_permissions_as_domain_user($d, 0600, $sshfile) if (!$ex);
return undef;
}

# get_ssh_key_identifier(&user)
# Returns a string that uniquely identifies a user's SSH public key
sub get_ssh_key_identifier
{
my ($user, $d) = @_;
my $username = &remove_userdom($user->{'user'}, $d);
return "[$d->{'id'}:$username]"; # [1234567890123456:ilia]
}

# add_domain_user_ssh_pubkey(&domain, &user, pubkey)
# Adds an SSH public key to the authorized keys file
sub add_domain_user_ssh_pubkey
{
my ($d, $user, $pubkey) = @_;
return if (!$d->{'dir'});
my $sshdir = $user->{'home'}."/.ssh";
&make_dir_as_domain_user($user, $sshdir, 0700);
my $sshfile = "$sshdir/authorized_keys";
my $identifier = &get_ssh_key_identifier($user, $d);
eval { &write_as_domain_user($user,
	sub { &write_file_contents($sshfile, "$pubkey $identifier") }); };
return $@ if ($@);
return 0;
}

# get_domain_user_ssh_pubkey(&domain, &user)
# Returns the SSH public key for some user
# in a domain, or undef if none
sub get_domain_user_ssh_pubkey
{
my ($d, $user) = @_;
return if (!$d->{'dir'});
my $sshdir = $user->{'home'}."/.ssh";
return if (!-d $sshdir);
my $sshfile = "$sshdir/authorized_keys";
return if (!-f $sshfile);
my $identifier = &get_ssh_key_identifier($user, $d);
my $pubkey;
my $authorized_keys = &read_file_lines_as_domain_user($user, $sshfile, 1);
foreach my $authorized_key (@$authorized_keys) {
	if ($authorized_key =~ /\Q$identifier\E/) {
		$pubkey = $authorized_key;
		$pubkey =~ s/\s+\Q$identifier\E//;
		last;
		}
	}
return $pubkey;
}

# delete_domain_user_ssh_pubkey(&domain, &user)
# Removes an SSH public key from the authorized keys file
# if it is used by the domain and key can be identified
sub delete_domain_user_ssh_pubkey
{
my ($d, $user) = @_;
return if (!$d->{'dir'});
my $sshdir = $user->{'home'}."/.ssh";
return if (!-d $sshdir);
my $sshfile = "$sshdir/authorized_keys";
return if (!-f $sshfile);
my $identifier = &get_ssh_key_identifier($user, $d);
my $authorized_keys = &read_file_lines_as_domain_user($user, $sshfile);
for (my $i = 0; $i < @$authorized_keys; $i++) {
	if ($authorized_keys->[$i] =~ /\Q$identifier\E/) {
        	splice(@$authorized_keys, $i, 1);
        	last;
		}
	}
&flush_file_lines_as_domain_user($user, $sshfile);
return undef;
}

# update_domain_user_ssh_pubkey(&domain, &user, &olduser, [pubkey])
# Updates an SSH public key or key identifier in the authorized
# keys file if it is used by the domain and the old key can be 
# identified
sub update_domain_user_ssh_pubkey
{
my ($d, $user, $olduser, $pubkey) = @_;
return if (!$d->{'dir'});
my $sshdir = $user->{'home'}."/.ssh";
return if (!-d $sshdir);
my $sshfile = "$sshdir/authorized_keys";
return if (!-f $sshfile);
my $identifier = &get_ssh_key_identifier($user, $d);
my $identifier_old = &get_ssh_key_identifier($olduser, $d);
my $authorized_keys = &read_file_lines_as_domain_user($user, $sshfile);
foreach my $authorized_key (@$authorized_keys) {
	if ($authorized_key =~ /\Q$identifier_old\E/) {
		# Replace old key with new key if set
		if ($pubkey) {
			$authorized_key = "$pubkey $identifier";
			}
		# Just update identifier and keep same key
		else {
			$authorized_key =~ s/\Q$identifier_old\E/$identifier/;
			}
		}
	}
&flush_file_lines_as_domain_user($user, $sshfile);
return undef;
}

# get_ssh_pubkey_from_file(file, [match])
# Returns the SSH public key from some file,
# alternatively matching by some string. If
# match parameter is not set, returns the first
# line of the file.
sub get_ssh_pubkey_from_file
{
my ($sshpubkeyfile, $sshpubkeyid) = @_;
my $pubkey;
my $sshpubkeyfilelines = &read_file_lines($sshpubkeyfile, 1);
foreach my $sshpubkeyfileline (@$sshpubkeyfilelines) {
	$sshpubkeyfileline = &trim($sshpubkeyfileline);
	if ($sshpubkeyid) {
		if ($sshpubkeyfileline =~ /\Q$sshpubkeyid\E/) {
			$pubkey = $sshpubkeyfileline;
			last;
			}
		}
	else {
		$pubkey = $sshpubkeyfileline;
		last;
		}
	}
return $pubkey;
}

# validate_ssh_pubkey(pubkey, [no-ssh-keygen])
# Returns an error message if some SSH public key is invalid
sub validate_ssh_pubkey
{
my ($pubkey, $no_ssh_keygen) = @_;
my ($ssh_keytest_out, $ssh_keytest_err);
($ssh_keytest_err = $text{'validate_esshpubkeyempty'}) if (!$pubkey);
if (!$ssh_keytest_err) {
	my $ssh_keygen = !$no_ssh_keygen && &has_command('ssh-keygen');
	if ($ssh_keygen) {
		my $pubkeyfile = &transname('id_rsa.pub');
		&write_file_contents($pubkeyfile, $pubkey);
		&execute_command("$ssh_keygen -l -f $pubkeyfile",
			undef, \$ssh_keytest_out, \$ssh_keytest_err);
		if ($ssh_keytest_err) {
			$ssh_keytest_err =~ s/\s*\Q$pubkeyfile\E\s*|^\s+|\s+$//g;
			$ssh_keytest_err =~ s/\.$//;
			$ssh_keytest_err = &text('validate_esshpubkeyinvalid', 
				&html_escape(ucfirst($ssh_keytest_err)));
			}
		}
	elsif ($pubkey && $pubkey !~
		/^(ssh-rsa|ssh-dss|ssh-dsa|ecdsa-sha2-nistp256|rsa-sha2-512|
		   rsa-sha2-256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|
		   ssh-ed25519|sk-ecdsa-sha2-nistp256|sk-ssh-ed25519)/x) {
		$ssh_keytest_err =
			&text('validate_esshpubkeyinvalid',
			$text{'validate_esshpubkeyinvalidformat'});
		}
	}
return wantarray ? ($ssh_keytest_err, $ssh_keytest_out) : $ssh_keytest_err;
}

sub get_module_version_and_type
{
my ($list, $gpl, $ver) = @_;
my $mver = $ver || $module_info{'version'};
my ($v_major, $v_minor, $v_build, $v_type);
if ($mver =~ /(?<major>\d+)\.(?<minor>\d+)\.(?<build>\d+).*?(?<type>[a-z]+)/i) {
	($v_major, $v_minor, $v_build, $v_type) = ($+{major}, $+{minor}, $+{build}, $+{type});
	}
elsif ($mver =~ /(?<major>\d+)\.(?<minor>\d+).*?(?<type>[a-z]+)/i) {
	($v_major, $v_minor, $v_build, $v_type) = ($+{major}, $+{minor}, undef, $+{type});
	}
elsif ($mver =~ /(?<major>\d+)\.(?<minor>\d+)\.(?<build>\d+)/) {
	($v_major, $v_minor, $v_build) = ($+{major}, $+{minor}, $+{build});
	}
elsif ($mver =~ /(?<major>\d+)\.(?<minor>\d+)/) {
	($v_major, $v_minor) = ($+{major}, $+{minor});
	}
else {
	return $mver;
	}
if ($v_type =~ /pro/i) {
	$v_type = " Pro";
	} 
else {
	if ($gpl) {
		$v_type = " GPL";
		}
	else {
		$v_type = "";
		}
	}
return $list ? ($v_major, $v_minor, $v_build, &trim($v_type)) : 
	  "$v_major.$v_minor".(defined($v_build) ? ".$v_build" : "")."$v_type";
}

# set_provision_features(&domain)
# Set the provision_* and cloud_* fields in a domain based on what
# provisioning features are currently configured globally and in the template,
# to indicate that they should be created remotely.
sub set_provision_features
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
foreach my $f (&list_provision_features()) {
	if ($f eq "dns") {
		# Template has an option to control where DNS is hosted
		my $alias = $d->{'alias'} ? &get_domain($d->{'alias'}) : undef;
		my $cloud = $alias && $alias->{'dns_cloud'} ? $alias->{'dns_cloud'} :
			    $d->{'dns_cloud'} ? $d->{'dns_cloud'} :
			    $d->{'dns_remote'} ? 'remote_'.$d->{'dns_remote'}
					       : $tmpl->{'dns_cloud'};
		if ($cloud eq 'services') {
			# Cloudmin services
			$d->{'provision_dns'} = 1;
			delete($d->{'dns_cloud'});
			}
		elsif ($cloud eq 'local') {
			# Local system
			$d->{'provision_dns'} = 0;
			delete($d->{'dns_cloud'});
			}
		elsif ($cloud =~ /^remote_(\S+)$/) {
			# Remote Webmin server
			delete($d->{'dns_cloud'});
			$d->{'dns_remote'} = $1;
			}
		elsif ($cloud eq '') {
			# Global default
			$d->{'provision_dns'} = 1 if ($config{'provision_dns'});
			delete($d->{'dns_cloud'});
			}
		else {
			# Cloud provider
			$d->{'dns_cloud'} = $cloud;
			$d->{'dns_cloud_import'} = $tmpl->{'dns_cloud_import'};
			}
		}
	elsif ($config{'provision_'.$f}) {
		# Only option is cloudmin services
		$d->{'provision_'.$f} = 1;
		}
	}
# Check if template has an option to control cloud SMTP provider
my $cloud = $d->{'smtp_cloud'} || $tmpl->{'mail_cloud'};
if ($cloud eq 'local') {
	delete($d->{'smtp_cloud'});
	}
else {
	$d->{'smtp_cloud'} = $cloud;
	}
}
# update_edit_limits(&dom, limit-name, limit-value)
# Updates dependencies for given feature 
# when limits for a domain changed
sub update_edit_limits {
my ($d, $lname, $lvalue) = @_;
}

# text_html(&text)
# Prints given only if in HTML mode
sub text_html {
if (defined(&get_sub_ref_name)) {
	my $print_mode = &get_sub_ref_name($first_print);
	if ($print_mode &&
	    $print_mode =~ /_html_/) {
		return &text(@_);
		}
	}
}

# setup_virtualmin_default_hostname_ssl()
# Setup default hostname domain with SSL certificate,
# unless previously default domain has not been setup
# and return error message or undef on success
sub setup_virtualmin_default_hostname_ssl
{
my $wantarr = wantarray;
my $err = sub {
	my ($msg, $code, $d) = @_;
	return $wantarr ? ($code || 0, $msg, $d) : $code || 0;
	};

# Can create
return &$err(&text('check_defhost_cannot', $remote_user))
		if (!&can_create_master_servers());

my $is_default_domain = &get_domain_by("defaultdomain", 1);
my $system_host_name = &get_system_hostname();
if ($system_host_name !~ /\./) {
	my $system_host_name_ = &get_system_hostname(0, 1);
	$system_host_name = $system_host_name_
		if ($system_host_name_ =~ /\./);
	}

# Hostname should be FQDN
return &$err(&text('check_defhost_nok', $system_host_name))
	if ($system_host_name !~ /^.+\.\p{L}{2,}$/);

# Check if domain already exist for some reason
return &$err(&text('check_defhost_clash', $system_host_name))
	if (&get_domain_by("dom", $system_host_name) ||
		$is_default_domain->{'dom'});

# Setup from source
my $setup_source = $0;

&lock_domain_name($system_host_name);

# Work out username / etc
my ($user, $try1, $try2);
$user = "_default_hostname";
if (defined(getpwnam($user))) {
	($user, $try1, $try2) = &unixuser_name($system_host_name);
	}
$user || return &$err(&text('setup_eauto', $try1, $try2));
my ($group, $gtry1, $gtry2);
$group = "_default_hostname";
if (defined(getgrnam($group))) {
	($group, $gtry1, $gtry2) = &unixgroup_name($system_host_name, $user);
	}
$group || return &$err(&text('setup_eauto2', $try1, $try2));
my $defip = &get_default_ip();
my $defip6 = &get_default_ip6();
my $template = &get_init_template();
my $plan = &get_default_plan();

# Create the virtual server object
my %dom;
%dom = ('id', &domain_id(),
	'dom', $system_host_name,
	'user', $user,
	'group', $group,
	'ugroup', $group,
	'owner', $text{'check_defhost_desc'},
	'name', 1,
	'name6', 1,
	'ip', $defip,
	'dns_ip', &get_dns_ip(),
	'virt', 0,
	'virtalready', 0,
	'ip6', $defip6,
	'virt6', 0,
	'virt6already', 0,
	'pass', &random_password(),
	'quota', 0,
	'uquota', 0,
	'source', $setup_source,
	'template', $template,
	'plan', $plan->{'id'},
	'prefix', $prefix,
	'nocreationmail', 1,
	'nowebmailredirect', 1,
	'nodnsspf', 1,
	'hashpass', 1,
	'nocreationscripts', 1,
	'defaultdomain', 1,
	'defaulthostdomain', 1,
	'letsencrypt_dwild', 0,
	'defaultshell', '/dev/null',
	'dns_initial_records', '@',
	'nodnsdmarc', 1,
	'default_php_mode', 4,
	'dom_defnames', $system_host_name
    );
&lock_domain(\%dom);

# Set initial features
$dom{'dir'} = 1;
$dom{'unix'} = 1;
$dom{'dns'} = $config{'dns'};
$dom{'mail'} = 0;
my $webf = &domain_has_website();
my $sslf = &domain_has_ssl();
$dom{$webf} = 1;
$dom{$sslf} = 1;
$dom{'letsencrypt_dname'} = $system_host_name;
$dom{'letsencrypt_subset'} = 1;
$dom{'auto_letsencrypt'} = 2;

# Fill in other default fields
&set_limits_from_plan(\%dom, $plan);
&set_capabilities_from_plan(\%dom, $plan);
$dom{'emailto'} = $dom{'user'}.'@'.$system_host_name;
$dom{'db'} = &database_name(\%dom);
&set_featurelimits_from_plan(\%dom, $plan);
&set_chained_features(\%dom, undef);
&set_provision_features(\%dom);
&generate_domain_password_hashes(\%dom, 1);
$dom{'home'} = &server_home_directory(\%dom, undef);
$dom{'home'} =~ s/(\/)(?=[^\/]*$)/$1./;
&complete_domain(\%dom);

# Check for various clashes
$derr = &virtual_server_depends(\%dom);
return &$err($derr) if ($derr);
$cerr = &virtual_server_clashes(\%dom);
return &$err($cerr) if ($cerr);
my @warns = &virtual_server_warnings(\%dom);
return &$err(join(" ", @warns)) if (@warns);

# Create the server
&push_all_print();
&set_all_null_print();
my ($rs) = &create_virtual_server(
	\%dom, undef, undef, 1, 0, $pass, $dom{'owner'});
&pop_all_print();
if ($rs && ref($rs) ne 'HASH') {
	&unlock_domain(\%dom);
	&unlock_domain_name($system_host_name);
	return &$err($rs);
	}
my $succ = $rs->{'letsencrypt_last'} ? 1 : 0;
# Perhaps shared SSL certificate was installed, trust it
$succ = 2 if ($rs->{'ssl_same'});
my $elelast;
if ($config{'err_letsencrypt'}) {
	$elelast = $rs->{'letsencrypt_last_err'};
	if ($elelast) {
		$elelast =~ s/\t/\n/g;
		$elelast = " :<br>$elelast";
		}
	}
my $succ_msg = $succ ? 
	&text($succ == 2 ? 'check_defhost_sharedsucc'
			 : 'check_defhost_succ', $system_host_name) :
	&text('check_defhost_err', $system_host_name).$elelast;
$config{'defaultdomain_name'} = $dom{'dom'};
$config{'default_domain_ssl'} = 1
	if ($succ && !$config{'default_domain_ssl'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

# Set as default domain if create some time later
if (&can_default_website(\%dom)) {
	&set_default_website(\%dom);
	}

# Enable as default domain for all services
if ($succ) {
	&push_all_print();
	&set_all_null_print();
	foreach my $st (&list_service_ssl_cert_types()) {
		my ($a) = grep { !$_->{'d'} && $_->{'id'} eq $st->{'id'} }
				&get_all_domain_service_ssl_certs(\%dom);
		if (!$a) {
			my $cfunc = "copy_".$st->{'id'}."_ssl_service";
			&$cfunc(\%dom);
			}
		}
	&pop_all_print();
	}

&run_post_actions_silently();
&unlock_domain(\%dom);
&unlock_domain_name($system_host_name);
&clear_links_cache() if ($config{'default_domain_ssl'} == 2);
return &$err($succ_msg, $succ, $rs);
}

# delete_virtualmin_default_hostname_ssl()
# Delete default hostname domain
sub delete_virtualmin_default_hostname_ssl
{
# Test if hostname domain being deleted
my $d = &get_domain_by("defaulthostdomain", 1);
return if (!$d || !$d->{'dom'});
return if (!&can_delete_domain($d));

# Delete hostname domain
&lock_domain_name($d->{'dom'});
&push_all_print();
&set_all_null_print();
$err = &delete_virtual_server($d, 0, 0);
&pop_all_print();
&run_post_actions_silently();
&unlock_domain_name($d->{'dom'});
&lock_file($module_config_file);
$config{'defaultdomain_name'} = undef;
&save_module_config();
&unlock_file($module_config_file);
&clear_links_cache();
return wantarray ? (0, $err) : 0 if ($err);
return wantarray ? (1, undef) : 1;
}

# rename_default_domain_ssl(&domain, new_hostname)
# Rename default hostname domain
sub rename_default_domain_ssl
{
my ($d, $new_hostname) = @_;
if (!&can_edit_domain($d) || !&can_edit_ssl() || !&can_webmin_cert()) {
	return 0;
	}

# Try renaming default domain
&push_all_print();
&set_all_null_print();
my $err = &rename_virtual_server($d, $new_hostname);

# Update state of all certs
my @already = &get_all_domain_service_ssl_certs($d);
foreach my $st (&list_service_ssl_cert_types()) {
	next if (!$st->{'dom'} && !$st->{'virt'});
	next if (!$st->{'dom'} && !$d->{'virt'});
	my ($a) = grep { $_->{'d'} && $_->{'id'} eq $st->{'id'} } @already;
	my $func = "sync_".$st->{'id'}."_ssl_cert";
	my $ok = 1;
	$ok = &$func($d, 1) if (!$a);
	$err = 1 if (!$ok);
	}
# Update config entry
$config{'defaultdomain_name'} = $new_hostname;
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&run_post_actions_silently();
&pop_all_print();
&clear_links_cache() if ($config{'default_domain_ssl'} == 2);
return $err ? 0 : 1;
}

# check_external_dns(hostname, [expected-ip|expected-cname])
# Checks if some DNS record can be looked up externally by consulting the 
# 8.8.8.8 nameserver. Returns 1 if yes, 0 if not, or -1 if the command needed
# is not installed.
sub check_external_dns
{
my ($host, $wantrec) = @_;
if (&has_command("dig")) {
	my $out = &backquote_command(
		"dig ".quotemeta($host)." \@$config{'dns_default_ip4'} 2>/dev/null");
	return -1 if ($?);
	return 0 if ($out !~ /ANSWER\s+SECTION/i);
	# IPv4 and CNAME
	if ($out =~ /\Q$host\E\.?.*\s+(\d+\.\d+\.\d+\.\d+)/ ||
	    $out =~ /\Q$host\E\.?.*CNAME\s+(\S+)/) {
		# Found an IP
		return !$wantrec || $wantrec eq $1;
		}
	# IPv6 only
	$out = &backquote_command(
		"dig -6 AAAA ".quotemeta($host)." \@$config{'dns_default_ip6'} 2>/dev/null");
	if ($out =~ /\Q$host\E\.?.*\s+AAAA\s+(\S+)/) {
		# Found an IP
		return !$wantrec || $wantrec eq $1;
		}
	return 0;
	}
elsif (&has_command("host")) {
	&clean_environment();
	my $out = &backquote_command(
		"host ".quotemeta($host)." $config{'dns_default_ip4'} 2>/dev/null");
	&reset_environment();
	return 0 if ($out =~ /Host\s+\S+\s+not\s+found/i);
	return -1 if ($?);
	# IPv4
	if ($out =~ /has\s+address\s+(\d+\.\d+\.\d+\.\d+)/i) {
		# Found an IP
		return !$wantrec || $wantrec eq $1;
		}
	# IPv6
	if ($out =~ /has\s+IPv6\s+address\s+(\S+)/i) {
		# Found an IP
		return !$wantrec || $wantrec eq $1;
		}
	return 0;
	}
return -1;
}

# filter_external_dns(&hostnames, &unresolvable)
# Given a list of hostnames, removes those that can't be resolved and adds them
# to the unresolvable list. Returns 1 if all are OK, 0 if any are not resolvable
# and -1 if any lookups fail.
sub filter_external_dns
{
my ($dnames, $badnames) = @_;
my $fail = 0;
my @newdnames;
foreach my $h (@$dnames) {
	if ($h =~ /\*/) {
		# Let's Encrypt wildcards are always OK
		push(@newdnames, $h);
		}
	else {
		# Check if it can be resolved
		my $ok = &check_external_dns($h);
		$fail = 1 if ($ok < 0);
		if ($ok) {
			push(@newdnames, $h);
			}
		else {
			push(@$badnames, $h);
			}
		}
	}
@$dnames = @newdnames;
return $fail ? -1 : @$badnames ? 0 : 1;
}

# check_virtualmin_default_hostname_ssl()
# Check default host domain
sub check_virtualmin_default_hostname_ssl
{
# Get actual system hostname
my $system_host_name = &get_system_hostname();
if ($system_host_name !~ /\./) {
	my $system_host_name_ = &get_system_hostname(0, 1);
	$system_host_name = $system_host_name_
		if ($system_host_name_ =~ /\./);
	}
my $remove_default_host_domain = sub {
	my ($silent_print) = @_;	
	if ($silent_print) {
		&push_all_print();
		&set_all_null_print();
		}
	&$first_print(&text('check_hostdefaultdomain_disable', $system_host_name));
		my ($ok, $rsmsg) = &delete_virtualmin_default_hostname_ssl();
		if (!$ok) {
			&$second_print(&text('check_apicmderr', $rsmsg));
			}
		else {
			&$second_print($text{'setup_done'});
			}
	if ($silent_print) {
		&pop_all_print();
		}
	};
my $new_default_domain = &get_domain_by("defaulthostdomain", 1);
if ($new_default_domain->{'dom'}) {
	if ($config{'default_domain_ssl'}) {
		my $known_default_domain = $config{'defaultdomain_name'};
		my $hostname_changed = $known_default_domain ne $system_host_name;
		if ($hostname_changed) {
			&$first_print(&text('check_hostdefaultdomain_change',
				      $known_default_domain, $system_host_name));
			my $defdom_status = &rename_default_domain_ssl(
				$new_default_domain, $system_host_name);
			if ($defdom_status == 1) {
				&$second_print($text{'setup_done'});
				}
			else {
				&$second_print($text{'setup_failed'});
				}
			}
		}
	else {
		&$remove_default_host_domain();
		}
	}
elsif ($config{'default_domain_ssl'}) {
	my $old_default_domain = &get_domain_by("defaultdomain", 1);

	&$first_print(&text('check_hostdefaultdomain_enable', $system_host_name));
	if ($old_default_domain->{'dom'} &&
	    !$old_default_domain->{'defaulthostdomain'}) {
		&$second_print(&text('check_hostdefaultdomain_errold',
			$old_default_domain->{'dom'}));
		}
	else {
		&$remove_default_host_domain(1);
		my ($defdom_status, $defdom_msg) =
			&setup_virtualmin_default_hostname_ssl();
		if ($defdom_status == 2) {
			&$second_print($text{'check_defhost_sharedsucc2'});
			}
		elsif ($defdom_status == 1) {
			&$second_print($text{'setup_done'});
			}
		else {
			# Remove on failure unless host
			# default domain set to be visible
			&$remove_default_host_domain(1)
				if ($config{'default_domain_ssl'} != 2);
			&$second_print(&text('check_apicmderr', $defdom_msg));
			}
		}
	}
}

# error_stderr_local(err, [dont-print-return-as-string]]])
# Print an error message to STDERR,
# or call error_stderr if defined
sub error_stderr_local
{
my ($err, $noprint) = @_;
if (defined(&error_stderr)) {
	if ($noprint) {
		return &error_stderr($err, $noprint);
		}
	else {
		&error_stderr($err);
		}
	}
else {
	print STDERR "$err\n";
	}
}

# list_feature_plugins([include-always])
# Returns a list of all plugins that define features
sub list_feature_plugins
{
my ($always) = @_;
&load_plugin_libraries();
return grep { &plugin_defined($_, "feature_setup") ||
	      $always && &plugin_defined($_, "feature_always_setup") } @plugins;
}

# Returns a list of all plugins that add mailbox-level options
sub list_mail_plugins
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "mailbox_inputs") } @plugins;
}

# Returns a list of all plugins that add a new database type
sub list_database_plugins
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "database_name") } @plugins;
}

# Returns a list of all plugins that add a service that can be started
sub list_startstop_plugins
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "feature_startstop") } @plugins;
}

# Returns a list of all plugins that have a backupable feature
sub list_backup_plugins
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "feature_backup") ||
	      &plugin_defined($_, "feature_always_backup") } @plugins;
}

# Returns a list of all plugins that define new script installers
sub list_script_plugins
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "scripts_list") } @plugins;
}

# Checks if any plugins define script extension
sub check_script_plugins_extensions
{
&load_plugin_libraries();
return grep { &plugin_defined($_, "check_scripts_extension") } @plugins;
}

# update_domains_last_login_times()
# Updates last login time for all domains on the system
sub update_domains_last_login_times
{
foreach my $d (&list_domains()) {
	next if ($d->{'alias'});
	next if ($d->{'no_last_login'});
	my @logins;
	# Get all users logins timestamps
	foreach my $user (&list_domain_users($d, 0, 1, 1, 1)) {
		my $ll = &get_last_login_time($user->{'user'});
		foreach my $k (sort { $a cmp $b } keys %$ll) {
			push(@logins, $ll->{$k});
			}
		}
	next if (!@logins);
	# Logins found
	# Sort logins and get last login
	@logins = sort { $b <=> $a } @logins;
	# Save most recent timestamp
	&lock_domain($d);
	$d->{'last_login_timestamp'} = $logins[0];
	&save_domain($d);
	&unlock_domain($d);
	}
}

# human_time_delta(timestamp)
# Return localized relative time from now or to the future
# for a given timestamp, or undef if not a valid timestamp
sub human_time_delta
{
my $ts = shift;
return undef if (!&is_epochish($ts));
my $last_login;
my $now = time();
my $diff = $ts - $now; # >0 future, <0 past
my $abs = abs($diff);
return $text{'summary_now'} if ($abs < 10); # within ±10 seconds is now
my @units = (
    [ 31536000, 'year',  'years'  ],
    [ 2592000,  'month', 'months' ],
    [ 604800,   'week',  'weeks'  ],
    [ 86400,    'day',   'days'   ],
    [ 3600,     'hour',  'hours'  ],
    [ 60,       'min',   'mins'   ],
    [ 1,        'sec',   'secs'   ],
);
my ($val, $sing, $plur);
foreach my $unit (@units) {
	my ($secs, $s, $p) = @$unit;
	next if ($abs < $secs);
	$val = int($abs / $secs);
	($sing, $plur) = ($s, $p);
	last;
	}
if (defined($val) && $val > 0) {
	my $key = ($diff > 0 ? 'summary_in_' : 'summary_ago_').
		  ($val == 1 ? $sing : $plur);
	$last_login = &text($key, $val);
	}
else {
	$last_login = $text{'summary_now'};
	}
return $last_login;
}

# validation_select_features()
# Returns a list of tuples for validatable features or plugins, each of which
# is the feature ID and description
sub validation_select_features
{
my @fopts;
my @sorted_features = @validate_features;
features_sort(\@sorted_features, \@sorted_features);
foreach my $f (@sorted_features) {
	next if (!$config{$f} && defined($config{$f}));
	push(@fopts, [ $f, $text{'feature_'.$f} ]);
	}
my @sorted_plugins = &list_feature_plugins();
features_sort(\@sorted_plugins, \@sorted_plugins);
foreach my $f (@sorted_plugins) {
	if (&plugin_defined($f, "feature_validate")) {
		push(@fopts, [ $f, &plugin_call($f, "feature_name") ]);
		}
	}
return @fopts;
}

# check_feature_depends(feature)
# If a feature's dependencies are available, return undef. Otherwise return
# an error message
sub check_feature_depends
{
my ($f) = @_;
my $dfunc = "feature_depends_".$f;
return undef if (!defined(&$dfunc));
return &$dfunc();
}

$done_virtual_server_lib_funcs = 1;

1;
