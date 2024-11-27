use 5.010;
use strict;
use warnings;
no warnings 'uninitialized';

our (%config, %text, @features, @aliasmail_features, @alias_features,
     @opt_subdom_features, @banned_usernames, $first_print, $second_print,
     $virtualmin_pro);

# create_domain_cli(domain-name, &opts)
# This sub is fully compatible with the ‘create-domain.pl’ API. Returns an error
# message if something goes wrong, or new domain hashref if successful.
sub create_domain_cli
{
my ($domain_name, $opts) = @_;

# Build args used by plugins
my %plugin_args = ();
foreach my $f (&list_feature_plugins()) {
	if (&plugin_defined($f, "feature_args")) {
		foreach my $a (&plugin_call($f, "feature_args")) {
			$a->{'feature'} = $f;
			$plugin_args{$a->{'name'}} = $a;
			}
		}
	}

# Initialize variables
my $name = 1;
my $virt = 0;
my $anylimits = 0;
my $email = $config{'contact_email'};

# Set variables from %opts
my $domain = $domain_name;
$domain || return $text{'api_ndom_missing_domain_name'};

my $owner = $opts->{'desc'};
if (defined($owner)) {
	$owner =~ /:/ && return $text{'setup_eowner'};
}

if (defined($opts->{'email'})) {
	$email = $opts->{'email'};
	&extract_address_parts($email) ||
		return $text{'api_ndom_invalid_email_address'};
	}

my $user  = defined($opts->{'user'})  ? lc($opts->{'user'})  : undef;
my $group = defined($opts->{'group'}) ? lc($opts->{'group'}) : undef;
my $pass  = $opts->{'pass'};
if (defined($opts->{'passfile'})) {
	$pass = &read_file_contents($opts->{'passfile'});
	$pass =~ s/\r|\n//g;
	}

my ($mysqlpass, $postgrespass, $hashpass);
$mysqlpass    = $opts->{'mysql-pass'};
$postgrespass = $opts->{'postgres-pass'};
$hashpass     = 1 if ($opts->{'hashpass'});

my ($quota, $uquota);
if (defined($opts->{'quota'})) {
	$quota = $opts->{'quota'};
	$anylimits = 1;
	}

if (defined($opts->{'uquota'})) {
	$uquota = $opts->{'uquota'};
	$anylimits = 1;
	}

# Set features
my %feature = ();
foreach my $f (@features) {
	if ($opts->{$f}) {
		$config{$f} ||
		    return &text('api_ndom_feature_not_enabled', $f);
		$feature{$f}++;
		}
	}

# Set plugins
my %plugin = ();
foreach my $f (&list_feature_plugins()) {
	if ($opts->{$f}) {
		$plugin{$f}++;
		}
	}

# Handle other options
my ($deffeatures, $planfeatures);
$deffeatures = 1 if ($opts->{'default-features'});
$planfeatures = 1 if ($opts->{'features-from-template'} ||
		      $opts->{'features-from-plan'});

my $ip;
if ($opts->{'ip'}) {
	$ip = $opts->{'ip'};
	$feature{'virt'} = 1;    # for dependency checks
	$virt = 1;
	$name = 0;
	}

if ($opts->{'allocate-ip'}) {
	$ip = "allocate";    # will be done later
	$virt = 1;
	$name = 0;
	}

my $virtalready;
$virtalready = 1 if ($opts->{'ip-already'});

my $sharedip;
if ($opts->{'shared-ip'}) {
	$sharedip = $opts->{'shared-ip'};
	$virt = 0;
	$name = 1;
	}

my $parentip;
$parentip = 1 if ($opts->{'parent-ip'});

my ($ip6, $virt6, $name6);
if ($opts->{'no-ip6'}) {
	# IPv6 explicitly turned off
	$ip6 = undef;
	$virt6 = 0;
	$name6 = 0;
	}

if ($opts->{'default-ip6'} && &supports_ip6()) {
	# IPv6 on default shared address
	$ip6 = "default";
	$ip6 || return $text{'api_ndom_no_default_ipv6'};
	$virt6 = 0;
	$name6 = 1;
	}

if ($opts->{'ip6'} && &supports_ip6()) {
	# IPv6 on specific address
	$ip6 = $opts->{'ip6'};
	$virt6 = 1;
	$name6 = 0;
	}

my $virt6already;
$virt6already = 1 if ($opts->{'ip6-already'} && &supports_ip6());

if ($opts->{'allocate-ip6'} && &supports_ip6()) {
	# IPv6 on allocated address
	$ip6 = "allocate";
	$virt6 = 1;
	$name6 = 0;
	}

if (defined($opts->{'shared-ip6'})) {
	# IPv6 on shared address
	$ip6 = $opts->{'shared-ip6'};
	$virt6 = 0;
	$name6 = 1;
	&indexof($ip6, &list_shared_ip6s()) >= 0 ||
		return &text('api_ndom_ip6_not_in_shared_list', $ip6);
	}

my $dns_ip;
if ($opts->{'dns-ip'}) {
	$dns_ip = $opts->{'dns-ip'};
	&check_ipaddress($dns_ip) ||
		return $text{'api_ndom_invalid_dns_ip'};
	}

if ($opts->{'no-dns-ip'}) {
	$dns_ip = "";
	}

my $mailboxlimit;
if (defined($opts->{'max-mailboxes'})) {
	$mailboxlimit = $opts->{'max-mailboxes'};
	$anylimits = 1;
	}

my $dbslimit;
if (defined($opts->{'max-dbs'})) {
	$dbslimit = $opts->{'max-dbs'};
	$anylimits = 1;
}

my $domslimit;
if (defined($opts->{'max-doms'})) {
	$domslimit = $opts->{'max-doms'};
	$anylimits = 1;
	}

my $aliaslimit;
if (defined($opts->{'max-aliases'})) {
	$aliaslimit = $opts->{'max-aliases'};
	$anylimits = 1;
	}

my $aliasdomslimit;
if (defined($opts->{'max-aliasdoms'})) {
	$aliasdomslimit = $opts->{'max-aliasdoms'};
	$anylimits = 1;
	}

my $realdomslimit;
if (defined($opts->{'max-realdoms'})) {
	$realdomslimit = $opts->{'max-realdoms'};
	$anylimits = 1;
	}

my $template;
if (defined($opts->{'template'})) {
	my $templatename = $opts->{'template'};
	foreach my $t (&list_templates()) {
		if ($t->{'name'} eq $templatename ||
		    $t->{'id'} eq $templatename) {
			$template = $t->{'id'};
			}
		}
	$template eq "" &&
		return $text{'api_ndom_unknown_template_name'};
	}

my $planid;
if (defined($opts->{'plan'})) {
	my $planname = $opts->{'plan'};
	foreach my $p (&list_plans()) {
		if ($p->{'id'} eq $planname || $p->{'name'} eq $planname) {
			$planid = $p->{'id'};
			}
		}
	$planid eq "" && return $text{'api_ndom_unknown_plan_name'};
	}

my $bw;
if (defined($opts->{'bandwidth'})) {
	$bw = $opts->{'bandwidth'};
	$anylimits = 1;
	}

my $tlimit;
$tlimit = 1 if ($opts->{'limits-from-template'} || $opts->{'limits-from-plan'});

my $prefix = $opts->{'prefix'} || $opts->{'suffix'};

my $db;
if ($opts->{'db'}) {
	$db = $opts->{'db'};
	$db =~ /^[a-z0-9\-\_]+$/i || return $text{'invalid_database_name'};
	}

my $fwdto;
if ($opts->{'fwdto'}) {
	$fwdto = $opts->{'fwdto'};
	$fwdto =~ /^\S+\@\S+$/i ||
		return $text{'api_ndom_invalid_forwarding_address'};
	}

my $parentdomain;
if (defined($opts->{'parent'})) {
	$parentdomain = lc($opts->{'parent'});
	}

my ($aliasdomain, $aliasmail);
if (defined($opts->{'alias'}) || defined($opts->{'alias-with-mail'})) {
	$aliasdomain = $parentdomain = lc($opts->{'alias'} ||
					  $opts->{'alias-with-mail'});
	if ($opts->{'alias-with-mail'}) {
		$aliasmail = 1;
		}
	}

my $subdomain;
if (defined($opts->{'subdom'}) || defined($opts->{'superdom'})) {
	$subdomain = $parentdomain = lc($opts->{'subdom'} ||
					$opts->{'superdom'});
	}

my $resel = $opts->{'reseller'};

my $content = $opts->{'content'};

my $nocreationmail;
$nocreationmail = 1 if $opts->{'no-email'};
my $noslaves;
$noslaves       = 1 if $opts->{'no-slaves'};
my $nosecondaries;
$nosecondaries  = 1 if $opts->{'no-secondaries'};

my $precommand = $opts->{'pre-command'};
my $postcommand = $opts->{'post-command'};

my $letsencrypt = $opts->{'acme'} ? 1 :
		  $opts->{'acme-always'} ? 2 : undef;

my $jail = $opts->{'enable-jail'} ? 1 :
	   $opts->{'disable-jail'} ? 0 : undef;

my $myserver = $opts->{'mysql-server'};
my $pgserver = $opts->{'postgres-server'};

my $clouddns = $opts->{'cloud-dns'};

my $clouddns_import;
$clouddns_import = 1 if ($opts->{'cloud-dns-import'});

my $remotedns = $opts->{'remote-dns'};

my ($dns_submode, $dns_subany);
$dns_submode = 0 if ($opts->{'separate-dns-subdomain'});
$dns_subany  = 1 if ($opts->{'any-dns-subdomain'});

my $linkcert;
$linkcert = 0 if ($opts->{'break-ssl-cert'});
$linkcert = 1 if ($opts->{'link-ssl-cert'});
$linkcert = 2 if ($opts->{'always-link-ssl-cert'});

my $always_ssl;
$always_ssl = 1 if ($opts->{'generate-ssl-cert'});

my ($sshmode, $sshkey);
if ($opts->{'generate-ssh-key'}) {
	$sshmode = 1;
	}

if ($opts->{'use-ssh-key'}) {
	$sshmode = 2;
	$sshkey  = $opts->{'use-ssh-key'};
	if ($sshkey =~ /^\//) {
		$sshkey = &read_file_contents($sshkey);
		}
	$sshkey =~ /\S/ ||
		return $text{'api_ndom_ssh_key_option_required'};
	}

my $auto_redirect;
$auto_redirect = 1 if ($opts->{'ssl-redirect'});

my $append_style;
if (defined $opts->{'append-style'}) {
	$append_style = $opts->{'append-style'};
	my ($as) = grep { $_->[0] eq $append_style || $_->[1] eq $append_style }
			&list_append_styles();
	$as || return &text('api_ndom_append_style_not_exist',
			$append_style);
	$append_style = $as->[0];
}

my $phpmode = $opts->{'mode'};

my $defaultshell = $opts->{'shell'};

my $subprefix = $opts->{'subprefix'};

my ($proxy_pass_mode, $proxy_pass);
if ($opts->{'proxy'}) {
	$proxy_pass_mode = 1;
	$proxy_pass      = $opts->{'proxy'};
	}

if ($opts->{'framefwd'}) {
	$proxy_pass_mode = 2;
	$proxy_pass      = $opts->{'framefwd'};
	}

my $default_cert_owner;
$default_cert_owner = 1 if $opts->{'default-cert-owner'};

# Process plugin-specific args
my %plugin_values = ();
foreach my $arg (keys %plugin_args) {
	if (exists($opts->{$arg})) {
		if ($plugin_args{$arg}->{'novalue'}) {
			$plugin_values{$arg} = "";
			}
		else {
			$plugin_values{$arg} = $opts->{$arg};
			}
		}
	}

# Process custom fields
my %fields = ();
foreach my $key (keys %{$opts}) {
	if ($key =~ /^field-(\S+)$/) {
		my $fn = $1;
		my $fv = $opts->{$key};
		my @fields = &list_custom_fields();
		my ($f) = grep { $_->{'name'} eq $fn } @fields;
		$f || return &text('api_ndom_custom_field_not_exist', $fn);
		$fields{'field_'.$fn} = $fv;
	}
}

# If no template given, use the default
$template = &get_init_template($parentdomain) if ($template eq "");
my $tmpl = &get_template($template);
my $plan = $planid ne '' ? &get_plan($planid) : &get_default_plan();
$plan || return $text{'api_ndom_plan_not_exist'};
my $defip = &get_default_ip($resel);
my $defip6 = &get_default_ip6($resel);
if ($sharedip) {
	if ($sharedip eq $defip) {
		$sharedip = undef;
		}
	else {
		&indexof($sharedip, &list_shared_ips()) >= 0 ||
			return &text('api_ndom_shared_ip_not_in_list',
				     $sharedip);
		}
	}
$clouddns && $remotedns &&
	return $text{'api_ndom_cloud_dns_remote_dns_mutually_exclusive'};

my $netmask;
if ($ip eq "allocate") {
	# Allocate IP now
	$virtalready && return 
		$text{'api_ndom_ip_already_allocate_ip_incompatible'};
	my %racl = $resel ? &get_reseller_acl($resel) : ();
	if ($racl{'ranges'}) {
		# Allocating from reseller's range
		($ip, $netmask) = &free_ip_address(\%racl);
		$ip || return $text{'api_ndom_failed_allocate_ip_'.
				    'reseller_ranges'};
		}
	else {
		# Allocating from template
		$tmpl->{'ranges'} ne "none" || return $text{'api_ndom_'.
			'allocate_ip_option_requires_auto_ip_allocation'};
		($ip, $netmask) = &free_ip_address($tmpl);
		$ip || return $text{'api_ndom_failed_allocate_ip_from_ranges'};
		}
	}
elsif ($virt) {
	# Make sure manual IP specification is allowed
	$tmpl->{'ranges'} eq "none" || return $text{'api_ndom_ip_'.
			'option_cannot_be_used_with_auto_ip_allocation'};
	}

my $netmask6;
if ($ip6 eq "allocate") {
	# Allocate an IPv6 address now
	$virt6already && return $text{'api_ndom_ip6_already_allocate_'.
				      'ip6_incompatible'};
	my %racl = $resel ? &get_reseller_acl($resel) : ();
	if ($racl{'ranges6'}) {
		# Allocating from reseller's range
		($ip6, $netmask6) = &free_ip6_address(\%racl);
		$ip6 || return $text{'api_ndom_failed_allocate_ip6_'.
				     'reseller_ranges'};
		}
	else {
		# Allocating from template
		$tmpl->{'ranges6'} ne "none" || return $text{'cli_create_domain'.
			'_allocate_ip6_option_requires_auto_ip6_allocation'};
		($ip6, $netmask6) = &free_ip6_address($tmpl);
		$ip6 || return $text{'api_ndom_failed_allocate_ip6_'.
				     'from_ranges'};
		}
	}
elsif ($virt6) {
	# Make sure manual IP specification is allowed
	$tmpl->{'ranges6'} eq "none" || return $text{'api_ndom_ip6_'.
		'option_cannot_be_used_with_auto_ip6_allocation'};
	}
elsif ($ip6 eq "default") {
	# Use default IP for reseller
	$ip6 = $defip6;
	$ip6 || return $text{'api_ndom_no_default_ipv6_address_found'};
	$virt6 = 0;
	$name6 = 1;
	}
elsif (!defined($virt6) && $config{'ip6enabled'}) {
	# No IPv6 selection made, use default
	$ip6 = $defip6;
	if ($ip6) {
		$virt6 = 0;
		$name6 = 1;
		}
	}

# If no limit-related flags are given, assume from plan
if (!$tlimit && !$anylimits) {
	$tlimit = 1;
	}

# Make sure all needed args are set
$parentdomain || $pass || return $text{'api_ndom_missing_password'};
if (!defined($jail) && !$parentdomain) {
	$jail = $tmpl->{'ujail'};
	}
if ($jail && $parentdomain) {
	return $text{'api_ndom_enable_jail_only_for_top_level'};
	}
if (&has_home_quotas() && !$parentdomain) {
	$quota ne '' && $uquota ne '' || $tlimit ||
	return $text{'api_ndom_no_quota_specified'};
	}
if ($parentdomain) {
	$feature{'unix'} && return $text{'api_ndom_unix_option_not_'.
					 'valid_for_subservers'};
	}
if ($aliasdomain) {
	my @af = $aliasmail ? @aliasmail_features : @alias_features;
	foreach my $f (keys %feature) {
		&indexof($f, @af) >= 0 || return &text('api_ndom_'.
			'feature_not_valid_for_alias_servers', $f);
		}
	}
if ($subdomain) {
	foreach my $f (keys %feature) {
		&indexof($f, @opt_subdom_features) >= 0 ||
			return &text('api_ndom_feature_not_'.
				     'valid_for_subdomains', $f);
		}
	}

# Validate args and work out defaults for those unset
my $skipwarnings = $opts->{'skip-warnings'} || 0;
$domain = lc(&parse_domain_name($domain));
if (!$skipwarnings) {
	my $err = &valid_domain_name($domain);
	return $err if ($err);
	}
&lock_domain_name($domain);
my $clashed = &domain_name_clash($domain);
if ($clashed) {
	return ($clashed->{'defaulthostdomain'} ?
		&text('setup_edomain5', $clashed->{'dom'}) :
		$text{'setup_edomain4'});
	}
my ($parent, $alias, $subdom);
if ($parentdomain) {
	$parent = &get_domain_by("dom", $parentdomain);
	$parent || return $text{'api_ndom_parent_domain_not_exist'};
	$plan = &get_plan($parent->{'plan'});   # Parent overrides any selection
	$alias = $parent if ($aliasdomain);
	$subdom = $parent if ($subdomain);
	if ($parent->{'parent'}) {
		# Parent is not actually the top, such as when creating an alias
		$parent = &get_domain($parent->{'parent'});
		$parent || return $text{'api_ndom_no_top_'.
					'level_parent_domain_found'};
		}
	if ($subdomain) {
		$domain =~ /^(\S+)\.\Q$subdomain\E$/ ||
			return &text('api_ndom_subdomain_must_be_'.
				     'under_parent', $domain, $subdomain);
		$subprefix ||= $1;
		}
	}

# Allow user and group names
if (!$parent) {
	if (!$user) {
		# Select user automatically
		my ($try1, $try2);
		($user, $try1, $try2) = &unixuser_name($domain);
		$user || return &text('setup_eauto', $try1, $try2);
		}
	else {
		# Use specified username, and also group
		&valid_mailbox_name($user) && return $text{'setup_euser2'};
		defined(getpwnam($user)) && return $text{'setup_euser'};
		$group ||= $user;
		}
	if (!$group) {
		# Select group automatically
		my ($gtry1, $gtry2);
		($group, $gtry1, $gtry2) = &unixgroup_name($domain, $user);
		$group || return &text('setup_eauto2', $gtry1, $gtry2);
		}
	else {
		# Use specified group name
		&valid_mailbox_name($group) && return $text{'setup_egroup2'};
		defined(getgrnam($group)) &&
			return &text('setup_egroup', $group);
		}
	}
$owner ||= $domain;

# Work out features, if using automatic mode.
# If the user asked for features from the plan but it doesn't define any,
# fall back to the global defaults.
my $tfl = $plan->{'featurelimits'};
if ($planfeatures && $tfl) {
	# From limits on selected plan
	$tfl eq 'none' && return $text{'api_ndom_selected_plan_no_features'};
	my %flimits = map { $_, 1 } split(/\s+/, $tfl);
	%feature = ( 'virt' => $feature{'virt'} );
	%plugin = ( );
	foreach my $f (&list_available_features($parent, $alias, $subdom)) {
		if ($flimits{$f->{'feature'}} && $f->{'enabled'}) {
			if ($f->{'plugin'}) {
				$plugin{$f->{'feature'}} = 1;
				}
			else {
				$feature{$f->{'feature'}} = 1;
				}
			}
		}
	}
elsif ($deffeatures || $planfeatures && !$tfl) {
	# From global configured defaults
	%feature = ( 'virt' => $feature{'virt'} );
	%plugin = ( );
	foreach my $f (&list_available_features($parent, $alias, $subdom)) {
		if ($f->{'default'} && $f->{'enabled'}) {
			if ($f->{'plugin'}) {
				$plugin{$f->{'feature'}} = 1;
				}
			else {
				$feature{$f->{'feature'}} = 1;
				}
			}
		}
	}

# Check that at least one feature is enabled
scalar(keys %feature) ||
	return $text{'api_ndom_no_virtual_server_features_enabled'};

if (!$parent) {
	# Make sure alias, database, etc limits are set properly
	!defined($mailboxlimit) || $mailboxlimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_emailboxlimit'};
	!defined($dbslimit) || $dbslimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_edbslimit'};
	!defined($aliaslimit) || $aliaslimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_ealiaslimit'};
	!defined($domslimit) || $domslimit eq "*" ||
		$domslimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_edomslimit'};
	!defined($aliasdomslimit) || $aliasdomslimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_ealiasdomslimit'};
	!defined($realdomslimit) || $realdomslimit =~ /^[1-9]\d*$/ ||
		return $text{'setup_erealdomslimit'};

	# Validate username
	&require_useradmin();
	my $uerr = &useradmin::check_username_restrictions($user);
	if ($uerr) {
		return &text('setup_eusername', $user, $uerr);
		}
	$user =~ /^[^\t :]+$/ || return $text{'setup_euser2'};
	&indexof($user, @banned_usernames) < 0 ||
		return &text('setup_eroot', 'root');
	}

# Validate quotas
if (&has_home_quotas() && !$parent && !$tlimit) {
	$quota =~ /^\d+$/ || return $text{'setup_equota'};
	$uquota =~ /^\d+$/ || return $text{'setup_euquota'};
	}

# Validate reseller
if (defined($resel)) {
	# Set on the command line
	$parent && return $text{'api_ndom_reseller_cannot_be_set_'.
				'for_subservers'};
	my @resels = &list_resellers();
	my ($rinfo) = grep { $_->{'name'} eq $resel } @resels;
	$rinfo || return &text('api_ndom_reseller_not_found', $resel);
	}
elsif ($parent) {
	$resel = $parent->{'reseller'};
	}

if (!$alias) {
	if ($virt) {
		# Validate virtual IP address
		&check_ipaddress($ip) || return $text{'setup_eip'};
		my $clash = &check_virt_clash($ip);
		if ($virtalready) {
			# Make sure IP is already active
			$clash || return 
				$text{'api_ndom_setup_evirtclash2'};
			if ($virtalready == 1) {
				# Don't allow clash with another domain
				my $already = &get_domain_by("ip", $ip);
				$already && return &text('setup_evirtclash4',
					$already->{'dom'});
				}
			else {
				# The system's PRIMARY ip is being used by
				# this domain, so we can host a single SSL
				# virtual host on it.
				}
			}
		else {
			# Make sure the IP isn't assigned yet
			$clash && return 
				$text{'api_ndom_setup_evirtclash'};
			}
		}
	elsif ($parentip) {
		# IP comes from parent domain
		$parent || return $text{'api_ndom_parent_ip_cannot_'.
					'be_used_for_top_level_servers'};
		}

	if ($virt6) {
		# Validate virtual IPv6 address
		&check_ip6address($ip6) || return $text{'setup_eip6'};
		my $clash = &check_virt6_clash($ip6);
		if ($virt6already) {
			# Make sure it is already active
			$clash || return $text{'setup_evirt6clash2'};
			}
		else {
			# Make sure the IP isn't assigned yet
			$clash && return $text{'setup_evirt6clash'};
			}
		}
	}
else {
	# IP comes from alias target
	$ip = $alias->{'ip'};
	$ip6 = $alias->{'ip6'};
	}
my ($gid, $ugid, $uid);
if ($parent) {
	# User and group IDs come from parent
	$gid = $parent->{'gid'};
	$ugid = $parent->{'ugid'};
	$user = $parent->{'user'};
	$group = $parent->{'group'};
	$uid = $parent->{'uid'};
	}
else {
	# IDs are allocated later
	$uid = $ugid = $gid = undef;
	}

# Get remote MySQL or PostgreSQL server
my $mysql_module;
if ($myserver) {
	my $mm = &get_remote_mysql_module($myserver);
	$mm || return &text('api_ndom_remote_mysql_server_not_found',
			    $myserver);
	$mm->{'config'}->{'virtualmin_provision'} &&
		return &text('api_ndom_remote_mysql_server_'.
			     'provision_only', $myserver);
	$mysql_module = $mm->{'minfo'}->{'dir'};
	}
my $postgres_module;
if ($pgserver) {
	my $mm = &get_remote_postgres_module($pgserver);
	$mm || return 
		&text('api_ndom_remote_postgres_server_not_found', $pgserver);
	$postgres_module = $mm->{'minfo'}->{'dir'};
	}

# Validate the Cloud DNS provider
if ($clouddns) {
	if ($clouddns eq "services") {
		$config{'provision_dns'} ||
			return $text{'api_ndom_cloudmin_'.
				     'services_dns_not_enabled'};
		}
	elsif ($clouddns ne "local") {
		my @cnames = map { $_->{'name'} } &list_dns_clouds();
		&indexof($clouddns, @cnames) >= 0 ||
			return &text('api_ndom_valid_cloud_'.
				     'dns_providers', join(" ", @cnames));
		}
	}

# Validate the remote DNS server
if ($remotedns) {
	defined(&list_remote_dns) ||
	    return $text{'api_ndom_remote_dns_servers_not_supported'};
	my ($r) = grep { $_->{'host'} eq $remotedns } &list_remote_dns();
	$r || return &text('api_ndom_remote_dns_'.
			   'server_not_found', $remotedns);
	$r->{'slave'} && return &text('api_ndom_remote_dns_'.
				      'server_not_master', $remotedns);
	}

# Validate PHP mode
if ($phpmode) {
	my @supp = &supported_php_modes();
	&indexof($phpmode, @supp) >= 0 || return $text{'api_ndom_php_'.
		'execution_mode_not_supported'};
	}

# Work out prefix if needed, and check it
$prefix ||= &compute_prefix($domain, $group, $parent, 1);
$prefix =~ /^[a-z0-9\.\-]+$/i || return $text{'setup_eprefix'};
my $pclash = &get_domain_by("prefix", $prefix);
$pclash && return &text('setup_eprefix3', $prefix, $pclash->{'dom'});

# Build up domain object
my %dom =
       ( 'id', &domain_id(),
	 'dom', $domain,
	 'user', $user,
	 'group', $group,
	 'ugroup', $group,
	 'uid', $uid,
	 'gid', $gid,
	 'ugid', $gid,
	 'owner', $owner,
	 'email', $parent ? $parent->{'email'} : $email,
	 'name', $name,
	 'name6', $name6,
	 'ip', $virt ? $ip :
	       $alias ? $ip :
	       $parentip ? $parent->{'ip'} :
	       $sharedip ? $sharedip : $defip,
	 'netmask', $netmask,
	 'dns_ip', defined($dns_ip) ? $dns_ip : $alias ? $alias->{'dns_ip'} :
				      $virt ? undef : &get_dns_ip($resel),
	 'virt', $virt,
	 'virtalready', $virtalready,
	 'ip6', $parentip ? $parent->{'ip6'} : $ip6,
	 'netmask6', $netmask6,
	 'virt6', $virt6,
	 'virt6already', $virt6already,
		$parent ? ( 'pass', $parent->{'pass'} ) : 
			  ( 'pass', $pass, 'quota', $quota, 'uquota', $uquota ),
	 'alias', $alias ? $alias->{'id'} : undef,
	 'aliasmail', $aliasmail,
	 'subdom', $subdom ? $subdom->{'id'} : undef,
	 'source', 'create-domain.pl',
	 'template', $template,
	 'plan', $plan->{'id'},
	 'parent', $parent ? $parent->{'id'} : "",
		$parent ? ( ) :
			( 'mailboxlimit', $mailboxlimit,
			  'dbslimit', $dbslimit,
			  'aliaslimit', $aliaslimit,
			  'domslimit', $domslimit,
			  'aliasdomslimit', $aliasdomslimit,
			  'realdomslimit', $realdomslimit,
			  'bw_limit', $bw eq 'NONE' ? undef : $bw ),
	 'prefix', $prefix,
	 'reseller', $resel,
	 'nocreationmail', $nocreationmail,
	 'noslaves', $noslaves,
	 'nosecondaries', $nosecondaries,
	 'default_cert_owner', $default_cert_owner,
	 'subprefix', $subprefix,
	 'hashpass', $hashpass,
	 'auto_letsencrypt', $letsencrypt,
	 'jail', $jail,
	 'mysql_module', $mysql_module,
	 'postgres_module', $postgres_module,
	 'default_php_mode', $phpmode,
	 'dns_cloud', $clouddns,
	 'dns_cloud_import', $clouddns_import,
	 'dns_remote', $remotedns,
	 'proxy_pass_mode', $proxy_pass_mode,
	 'proxy_pass', $proxy_pass,
	);
$dom{'dns_submode'} = $dns_submode if (defined($dns_submode));
$dom{'dns_subany'} = $dns_subany if (defined($dns_subany));
$dom{'nolink_certs'} = 1 if ($linkcert eq '0');
$dom{'link_certs'} = $linkcert if ($linkcert == 1 || $linkcert == 2);
$dom{'always_ssl'} = $always_ssl if (defined($always_ssl));
$dom{'append_style'} = $append_style if (defined($append_style));
$dom{'defaultshell'} = $defaultshell if (defined($defaultshell));
foreach my $f (keys %fields) {
	$dom{$f} = $fields{$f};
	}
if (!$parent) {
	if ($tlimit) {
		&set_limits_from_plan(\%dom, $plan);
		}
	&set_capabilities_from_plan(\%dom, $plan);
	}
$dom{'emailto'} = $parent ? $parent->{'emailto'} :
		  $dom{'email'} ? $dom{'email'} :
		  $dom{'mail'} ? $dom{'user'}.'@'.$dom{'dom'} :
				 $dom{'user'}.'@'.&get_system_hostname();
foreach my $f (@features) {
	$dom{$f} = $feature{$f} ? 1 : 0;
	}
foreach my $f (&list_feature_plugins()) {
	$dom{$f} = $plugin{$f} ? 1 : 0;
	}
$dom{'db'} = $db || &database_name(\%dom);
&set_featurelimits_from_plan(\%dom, $plan);
&set_chained_features(\%dom, undef);
&set_provision_features(\%dom);
&generate_domain_password_hashes(\%dom, 1);

# Check SSL redirect flag
if ($auto_redirect) {
	&domain_has_ssl(\%dom) ||
		return $text{'api_ndom_ssl_redirect_requires_ssl'};
	$dom{'auto_redirect'} = 1;
	}

# Work out home directory
$dom{'home'} = &server_home_directory(\%dom, $parent);
if (defined($mysqlpass) && $config{'mysql'}) {
	$dom{'parent'} &&
		return $text{'api_ndom_mysql_pass_top_level_only'};
	&set_mysql_pass(\%dom, $mysqlpass);
	}
if (defined($postgrespass) && $config{'postgres'}) {
	$dom{'parent'} &&
		return $text{'api_ndom_postgres_pass_top_level_only'};
	&set_postgres_pass(\%dom, $postgrespass);
	}
&complete_domain(\%dom);

# Set plugin-defined command line args
foreach my $f (&list_feature_plugins()) {
	if ($dom{$f}) {
		my $err = &plugin_call($f, "feature_args_parse",
				    \%dom, \%plugin_values);
		return $err if ($err);
		}
	}

# Check for various clashes
my $derr = &virtual_server_depends(\%dom);
return $derr if ($derr);
my $cerr = &virtual_server_clashes(\%dom);
return $cerr if ($cerr);

# Check if features are not forbidden
if (!$skipwarnings) {
	foreach my $ff (&forbidden_domain_features(\%dom, 1)) {
		$dom{$ff} && return &text('api_ndom_feature_not_allowed', $ff);
		}
	}

# Check for warnings, unless overriding
my @warns = &virtual_server_warnings(\%dom);
if (!$skipwarnings && @warns) {
	my $wmsg = $text{'api_ndom_possible_problems_detected'} . " ";
	foreach my $w (@warns) {
		$wmsg .= "$w ";
		}
	return $wmsg;
	}

# Check if over quota
if ($parent) {
	my $err = &check_domain_over_quota($parent);
	if ($err) {
		return &text('api_ndom_overquota_error', $err);
		}
	}

# Content can come from template
if (!defined($content)) {
	my $content_web_tmpl = $tmpl->{'content_web'};
	my $content_web_tmpl_html_file = $tmpl->{'content_web_html'};
	# Default HTML page
	if ($content_web_tmpl == 2) {
		$content = "";
		}
	# Want to set content to the given from file
	elsif (!$content_web_tmpl && $virtualmin_pro &&
		-r $content_web_tmpl_html_file) {
		$content = &read_file_contents($content_web_tmpl_html_file);
		}
	}

# Do it
&lock_domain(\%dom);
$config{'pre_command'} = $precommand if ($precommand);
$config{'post_command'} = $postcommand if ($postcommand);
my $err = &create_virtual_server(\%dom, $parent,
				 $parent ? $parent->{'user'} : undef,
				 0, 1, $parent ? undef : $pass, $content);
&unlock_domain(\%dom);
return &text('api_ndom_creation_failed', $err) if ($err);

if ($fwdto) {
	&$first_print(&text('setup_fwding', $fwdto));
	&create_domain_forward(\%dom, $fwdto);
	&$second_print($text{'setup_done'});
	}

if ($sshmode == 1) {
	# Generate and use a key
	&$first_print($text{'setup_sshkey1'});
	my $err;
	($sshkey, $err) = &create_domain_ssh_key(\%dom);
	if (!$err) {
		$err = &save_domain_ssh_pubkey(\%dom, $sshkey);
		}
	if ($err) {
		&$second_print(&text('setup_esshkey', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
elsif ($sshmode == 2) {
	# Just use an existing key
	&$first_print($text{'setup_sshkey2'});
	$sshkey =~ s/\r|\n/ /g;
	my $err = &save_domain_ssh_pubkey(\%dom, $sshkey);
	if ($err) {
		&$second_print(&text('setup_esshkey', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

&run_post_actions_silently();
&unlock_domain_name($domain);
return \%dom;
}
