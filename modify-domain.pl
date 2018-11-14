#!/usr/local/bin/perl

=head1 modify-domain.pl

Change parameters of a virtual server

This command can be used to modify various settings for an existing virtual
server from the command line. The only mandatory parameter is C<--domain>, which
must be followed by the domain name of the server to update. The actual
changes to make are specified by the other optional parameters, such as C<--pass>
to set a new password, C<--desc> to change the server description, and C<--quota> and C<--uquota> to change the disk quota.

To add a private IP address to a virtual server that currently does not have
one, the C<--ip> or C<--allocate-ip> options can be used, as described in the
section on C<create-domain>.

To revert a server with a private IP back to the system's default shared
address, use the C<--default-ip> flag. If the system has more than one shared
address, the C<--shared-ip> flag can be used to change it.

To add an IPv6 address to a virtual server that currently does not have
one, the C<--ip6> or C<--allocate-ip6> options can be used. To remove a v6
address, you can use C<--no-ip6> instead.

To change a server's domain name, the C<--newdomain> option can be used. It must
be followed by a new domain name, which of course cannot be used by any
existing virtual server. When changing the domain name, you may also want to
use the C<--user> option to update the administration username for the server.
Both of these options will effect sub-servers as well, where appropriate.

To change a virtual server's plan and apply quota and other limits from the
new plan, use the C<--apply-plan> parameter followed by the plan name or ID.
Alternately, you can switch the plan without applying any of it's limits
with the C<--plan> flag.

You can also have the domain's enabled features updated to match the current
or new plan with the C<--plan-features> flag. This will disable or enable
features to match those that are allowed on the plan by default.

If your system is on an internal network and made available to the Internet
via a router doing NAT, the IP address of a domain in DNS may be different
from it's IP on the actual system. To set this, the C<--dns-ip> flag can
be given, followed by the external IP address to use. To revert to using the
real IP in DNS, use C<--no-dns-ip> instead. In both cases, the actual
DNS records managed by Virtualmin will be updated.

If your system supports chroot jails with Jailkit, the C<--enable-jail>
flag can be used to force all commands run by the domain to execute in
a jail. Conversely, this can be turned off with the C<--disable-jail> flag.

If you have configured additional remote (or local) MySQL servers, you can
change the one used by this domain with the C<--mysql-server> flag followed
by a hostname, hostname:port or socket file. All databases and users will be
migrated to the new server.

To specify an alias server that will be used for any links inside Virtualmin
to this server, use the C<--link-domain> flag followed by a domain name. To
revert to the normal behavior, use C<--no-link-domain>.

By default, virtual server plan changes that modify features will be blocked
if any warnings are detected, such as an existing database or SSL certificate
conflict. These can be overridden with the C<--skip-warnings> flag.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/modify-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
$name = 1;
$virt = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--desc") {
		$owner = shift(@ARGV);
		$owner =~ /:/ && &usage($text{'setup_eowner'});
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--passfile") {
		$pass = &read_file_contents(shift(@ARGV));
		$pass =~ s/\r|\n//g;
		}
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--quota") {
		$quota = shift(@ARGV);
		$quota = 0 if ($quota eq 'UNLIMITED');
		$quota =~ /^\d+$/ || &usage("Quota must be a number of blocks");
		}
	elsif ($a eq "--uquota") {
		$uquota = shift(@ARGV);
		$uquota = 0 if ($uquota eq 'UNLIMITED');
		$uquota =~ /^\d+$/ ||&usage("Quota must be a number of blocks");
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		$user =~ /^[^\t :]+$/ || &usage($text{'setup_euser2'});
		defined(getpwnam($user)) &&
			&usage("A user named $user already exists");
		}
	elsif ($a eq "--home") {
		$home = shift(@ARGV);
		$home =~ /^\/\S+$/ || &usage("Home directory must be an absolute path");
		-d $home && &usage("New home directory already exists");
		}
	elsif ($a eq "--newdomain") {
		$newdomain = shift(@ARGV);
		$newdomain =~ /^[A-Za-z0-9\.\-]+$/ || &usage("Invalid new domain name");
		$newdomain = lc($newdomain);
		foreach $d (&list_domains()) {
			if (lc($d->{'dom'}) eq $newdomain) {
				&usage("A domain called $newdomain already exists");
				}
			}
		}
	elsif ($a eq "--bw") {
		# Setting or removing the bandwidth limit
		$bw = shift(@ARGV);
		$bw eq "NONE" || $bw =~ /^\d+$/ || &usage("Bandwidth limit must be a number of bytes, or NONE");
		}
	elsif ($a eq "--bw-disable") {
		# Set over-bw limit disable to yes
		$bw_no_disable = 0;
		}
	elsif ($a eq "--bw-no-disable") {
		# Set over-bw limit disable to no
		$bw_no_disable = 1;
		}
	elsif ($a eq "--ip") {
		# Changing or adding a virtual IP
		$ip = shift(@ARGV);
		&check_ipaddress($ip) || &usage("Invalid IP address");
		}
	elsif ($a eq "--shared-ip") {
		# Changing the shared IP
		$sharedip = shift(@ARGV);
		&check_ipaddress($sharedip) ||
			&usage("Invalid shared IP address");
		}
	elsif ($a eq "--allocate-ip") {
		# Allocating an IP
		$ip = "allocate";
		}
	elsif ($a eq "--default-ip") {
		# Fall back to the default shared IP
		$defaultip = 1;
		}
	elsif ($a eq "--ip6" && &supports_ip6()) {
		# Adding or changing an IPv6 address
		$ip6 = shift(@ARGV);
		&check_ip6address($ip6) || &usage("Invalid IPv6 address");
		}
	elsif ($a eq "--no-ip6" && &supports_ip6()) {
		# Removing an IPv6 address
		$noip6 = 1;
		}
	elsif ($a eq "--allocate-ip6" && &supports_ip6()) {
		# Allocating an IPv6 address
		$ip6 = "allocate";
		}
	elsif ($a eq "--default-ip6" && &supports_ip6()) {
		# IPv6 on default shared address
		$defaultip6 = 1;
		}
	elsif ($a eq "--shared-ip6") {
		# Changing the shared IPv6 address
		$sharedip6 = shift(@ARGV);
		&check_ip6address($sharedip6) ||
			&usage("Invalid shared IPv6 address");
		}
	elsif ($a eq "--reseller") {
		# Changing the reseller
		$resel = shift(@ARGV);
		}
	elsif ($a eq "--add-reseller") {
		# Adding a reseller
		push(@add_resel, shift(@ARGV));
		}
	elsif ($a eq "--delete-reseller") {
		# Removing a reseller
		push(@del_resel, shift(@ARGV));
		}
	elsif ($a eq "--prefix") {
		# Changing the prefix
		$prefix = shift(@ARGV);
		}
	elsif ($a eq "--template") {
		# Changing the template
		$templatename = shift(@ARGV);
		foreach $t (&list_templates()) {
			if ($t->{'name'} eq $templatename ||
			    $t->{'id'} eq $templatename) {
				$template = $t->{'id'};
				}
			}
		$template eq "" && &usage("Unknown template name");
		}
	elsif ($a eq "--plan" || $a eq "--apply-plan") {
		# Changing the plan
		$planname = shift(@ARGV);
		foreach $p (&list_plans()) {
			if ($p->{'id'} eq $planname ||
			    $p->{'name'} eq $planname) {
				$planid = $p->{'id'};
				$plan = $p;
				}
			}
		$planapply = 1 if ($a eq "--apply-plan");
		}
	elsif ($a eq "--plan-features") {
		$planfeatures = 1;
		}
	elsif ($a eq "--add-exclude") {
		push(@add_excludes, shift(@ARGV));
		}
	elsif ($a eq "--remove-exclude") {
		push(@remove_excludes, shift(@ARGV));
		}
	elsif ($a eq "--add-db-exclude") {
		push(@add_db_excludes, shift(@ARGV));
		}
	elsif ($a eq "--remove-db-exclude") {
		push(@remove_db_excludes, shift(@ARGV));
		}
	elsif ($a eq "--pre-command") {
		$precommand = shift(@ARGV);
		}
	elsif ($a eq "--post-command") {
		$postcommand = shift(@ARGV);
		}
	elsif ($a eq "--dns-ip") {
		$dns_ip = shift(@ARGV);
		&check_ipaddress($dns_ip) ||
			&usage("--dns-ip must be followed by an IP address");
		}
	elsif ($a eq "--no-dns-ip") {
		$dns_ip = "";
		}
	elsif ($a eq "--skip-warnings") {
		$skipwarnings = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--enable-jail") {
		$jail = 1;
		}
	elsif ($a eq "--disable-jail") {
		$jail = 0;
		}
	elsif ($a eq "--mysql-server") {
		$myserver = shift(@ARGV);
		}
	elsif ($a eq "--link-domain") {
		$linkdname = shift(@ARGV);
		}
	elsif ($a eq "--no-link-domain") {
		$linkdname = "";
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain
$domain || usage("No domain specified");
$dom = &get_domain_by("dom", $domain);
$dom || usage("Virtual server $domain does not exist.");
$old = { %$dom };
$tmpl = &get_template(defined($template) ? $template : $dom->{'template'});

# Make sure options are valid for domain
if ($dom->{'parent'}) {
	defined($user) && &usage("The username cannot be changed for a sub-domain");
	defined($pass) && &usage("The password cannot be changed for a sub-domain");
	(defined($quota) || defined($uquota)) && &usage("Quotas cannot be changed for a sub-domain");
	}

# Check for unlimited quota clash with reseller, if quota was changed
if ($dom->{'reseller'} && defined(&get_reseller)) {
	foreach $r (split(/\s+/, $dom->{'reseller'})) {
		$rinfo = &get_reseller($r);
		next if (!$rinfo);
		if (!$dom->{'parent'} &&
		    defined($quota) && $quota eq "0" &&
		    $rinfo->{'acl'}->{'max_quota'}) {
			&usage("The disk quota for this domain cannot be set ".
			       "to unlimited, as it is owned by reseller ".
			       "$r who has a quota limit");
			       
			}
		if (!$dom->{'parent'} &&
		    $bw eq "NONE" &&
		    $rinfo->{'acl'}->{'max_bw'}) {
			&usage("The bandwidth for this domain cannot be set ".
			       "to unlimited, as it is owned by reseller ".
			       "$r who has a bandwidth limit");
			       
			}
		}
	}

# Validate IP change options
if ($ip && $dom->{'alias'}) {
	&usage("An IP address cannot be added to an alias domain");
	}
if ($dom->{'virt'} && $ip eq "allocate") {
	&usage("An IP address cannot be allocated when one is already active");
	}
elsif (!$dom->{'virt'} && $ip eq "allocate") {
	$config{'all_namevirtual'} && &usage("The --allocate-ip option cannot be used when all virtual servers are name-based");
	%racl = $d->{'reseller'} ? &get_reseller_acl($d->{'reseller'}) : ( );
	if ($racl{'ranges'}) {
		# Allocating IP from reseller's ranges
		($ip, $netmask) = &free_ip_address(\%racl);
		$ip || &usage("Failed to allocate IP address from reseller's ranges!");
		}
	else {
		# Allocating from template's ranges
		$tmpl->{'ranges'} eq "none" && &usage("The --allocate-ip option cannot be used unless automatic IP allocation is enabled - use --ip instead");
		($ip, $netmask) = &free_ip_address($tmpl);
		$ip || &usage("Failed to allocate IP address from ranges!");
		}
	}
if ($dom->{'virt'} && defined($sharedip)) {
	&usage("The shared IP address cannot be changed for a virtual server with a private IP");
	}
if (!$dom->{'virt'} && $defaultip) {
	&usage("The --default-ip flag can only be used when the virtual server has a private address");
	}
if (($defaultip || $sharedip) && $ip) {
	&usage("The --default-ip and --shared-ip flags cannot be combined with --ip or --allocate-ip");
	}
if ($dom->{'virt6'} && defined($sharedip6)) {
	&usage("The shared IPv6 address cannot be changed for a virtual server with a private IP");
	}
if (($defaultip6 || $sharedip6) && $ip6) {
	&usage("The --default-ip6 and --shared-ip6 flags cannot be combined with --ip6 or --allocate-ip6");
	}

# Validate IPv6 changes
if ($dom->{'virt6'} && $ip6 eq "allocate") {
	&usage("An IPv6 address cannot be allocated when one is already active");
	}
elsif (!$dom->{'virt6'} && $ip6 eq "allocate") {
	$tmpl->{'ranges6'} eq "none" && &usage("The --allocate-ip6 option cannot be used unless automatic IP allocation is enabled - use --ip6 instead");
	($ip6, $netmask6) = &free_ip6_address($tmpl);
	$ip6 || &usage("Failed to allocate IPv6 address from ranges!");
	}

if (defined($resel) || @add_resel || @del_resel) {
	$dom->{'parent'} && &usage("Reseller cannot be set for a sub-server");
	foreach $r ($resel ? ($resel) : (), @add_resel, @del_resel) {
		$rinfo = &get_reseller($r);
		$r eq "NONE" || $rinfo || &usage("Reseller $r not found");
		}
	}
if (defined($prefix)) {
	$dom->{'alias'} && &usage("Prefix cannot be changed for alias domains");
	@users = &list_domain_users($dom, 1, 1, 1, 1);
	@users && &usage("Prefix cannot be changed for virtual servers with existing mailbox users");
	$prefix =~ /^[a-z0-9\.\-]+$/i || &usage($text{'setup_eprefix'});
	if ($prefix ne $dom->{'prefix'}) {
		$pclash = &get_domain_by("prefix", $prefix);
                $pclash && &usage($text{'setup_eprefix2'});
		}
	}
if (defined($template)) {
	if ($dom->{'parent'} && !$dom->{'alias'} && !$tmpl->{'for_sub'}) {
		&usage("The selected template cannot be used for sub-servers");
		}
	elsif (!$dom->{'parent'} && !$tmpl->{'for_parent'}) {
		&usage("The selected template cannot be used for top-level servers");
		}
	elsif ($dom->{'alias'} && !$tmpl->{'for_alias'}) {
		&usage("The selected template cannot be used for alias servers");
		}
	$dom->{'template'} = $template;
	}

# Plans can only be used with top-level servers
if ($plan) {
	$d->{'parent'} && &usage("--plan can only be used with top ".
				 "level virtual servers");
	}

# Make sure plan specifies features
if ($planfeatures) {
	$d->{'parent'} && &usage("--plan-features can only be used with top ".
				 "level virtual servers");
	$plan ||= &get_plan($d->{'plan'});
	$plan->{'featurelimits'} eq 'none' &&
		&usage("--plan-features cannot be used if the plan has ".
		       "no features");
	}

# Make sure jails are available
if (defined($jail)) {
	my $err = &check_jailkit_support();
	$err && &usage("Chroot jails are not supported on this system : $err");
	}

# Make sure the MySQL server is valid
if ($myserver) {
	$dom->{'parent'} && &usage("The MySQL server can only be updated for ".
				   "top level virtual servers");
	my $mm = &get_remote_mysql_module($myserver);
	$mm || &usage("No remote MySQL server named $myserver was found");
	$mm->{'config'}->{'virtualmin_provision'} &&
		&usage("Remote MySQL server $myserver is for use only by ".
		       "Cloudmin Services provisioned domains");
	$mysql_module = $mm->{'minfo'}->{'dir'};
	}

# Validate link domain
if ($linkdname) {
	$linkd = &get_domain_by("dom", $linkdname);
	$linkd || &usage("Link domain $linkdname does not exist");
	$linkd->{'alias'} eq $dom->{'id'} || 
	    &usage("Link domain $linkdname is not an alias of this domain");
	}

# Find all other domains to be changed
@doms = ( $dom );
@olddoms = ( $old );
foreach $sdom (&get_domain_by("parent", $dom->{'id'})) {
	$oldsdom = { %$sdom };
	push(@doms, $sdom);
	push(@olddoms, $oldsdom);
	}

# Make the changes to the domain objects
if (defined($owner)) {
	$dom->{'owner'} = $owner;
	}
if (defined($prefix)) {
	$dom->{'prefix'} = $prefix;
	}
if (defined($pass)) {
	foreach $d (@doms) {
		if ($d->{'disabled'}) {
			# Clear any saved passwords, as they should
			# be reset at this point
			$d->{'disabled_mysqlpass'} = undef;
			$d->{'disabled_postgrespass'} = undef;
			}
		$d->{'pass'} = $pass;
		$d->{'pass_set'} = 1;
		&generate_domain_password_hashes($d, 0);
		}
	}
if (defined($email)) {
	&extract_address_parts($email) ||
		&usage("Invalid email address $email");
	foreach $d (@doms) {
		$d->{'email'} = $email;
		&compute_emailto($d);
		}
	}
if (defined($quota)) {
	$dom->{'quota'} = $quota;
	}
if (defined($uquota)) {
	$dom->{'uquota'} = $uquota;
	}
if (defined($user)) {
	foreach $d (@doms) {
		$d->{'user'} = $user;
		}
	}
if (defined($home)) {
	foreach $d (@doms) {
		local $k;
		foreach $k (keys %$d) {
			$d->{$k} =~ s/$old->{'home'}/$home/g;
			}
		}
	}
if (defined($newdomain)) {
	$dom->{'dom'} = $newdomain;
	}
if (defined($bw)) {
	$dom->{'bw_limit'} = $bw eq "NONE" ? undef : $bw;
	}
if (defined($bw_no_disable)) {
	$dom->{'bw_no_disable'} = $bw_no_disable;
	}
if ($linkdname) {
	$dom->{'linkdom'} = $linkd ? $linkd->{'id'} : undef;
	}

# Apply new IPv4 address
if (defined($ip)) {
	# Just change the IP
	$dom->{'ip'} = $ip;
	$dom->{'netmask'} = $netmask;
	delete($dom->{'dns_ip'});
	if (!$config{'all_namevirtual'}) {
		$dom->{'virt'} = 1;
		$dom->{'name'} = 0;
		$dom->{'virtalready'} = 0;
		}
	}
elsif ($defaultip) {
	# Falling back to default IP
	$dom->{'ip'} = &get_default_ip($dom->{'reseller'});
	$dom->{'netmask'} = undef;
	$dom->{'defip'} = $dom->{'ip'} eq &get_default_ip();
	$dom->{'virt'} = 0;
	$dom->{'virtalready'} = 0;
	$dom->{'name'} = 1;
	delete($dom->{'dns_ip'});
	}
elsif (defined($sharedip)) {
	# Just change the shared IP address
	$dom->{'ip'} = $sharedip;
	}

# Apply new IPv6 address
if ($ip6) {
	# Adding or changing an IPv6 address
	$dom->{'ip6'} = $ip6;
	$dom->{'netmask6'} = $netmask6;
	$dom->{'virt6'} = 1;
	$dom->{'name6'} = 0;
	}
elsif ($defaultip6) {
	# Using the default IPv6 address
	$dom->{'ip6'} = &get_default_ip6($dom->{'reseller'});
	$dom->{'netmask6'} = undef;
	$dom->{'virt6'} = 0;
	$dom->{'name6'} = 1;
	}
elsif (defined($sharedip6)) {
	# Just change the shared IP address
	$dom->{'ip6'} = $sharedip6;
	}
elsif ($noip6) {
	# Removing the IPv6 address
	$dom->{'netmask6'} = undef;
	$dom->{'virt6'} = 0;
	$dom->{'name6'} = 0;
	$dom->{'ip6'} = undef;
	}

# Apply reseller change
if ($resel eq "NONE") {
	# Just clear reseller
	$dom->{'reseller'} = undef;
	}
elsif (defined($resel) || @add_resel || @del_resel) {
	defined(&get_reseller) || &usage("Resellers are not supported");

	# Make sure resellers are compatible with quota
	foreach $r ($resel ? ($resel) : (), @add_resel) {
		$rinfo = &get_reseller($r);
		if (($dom->{'quota'} eq '' || $dom->{'quota'} eq '0') &&
		    $rinfo->{'acl'}->{'max_quota'}) {
			&usage("This domain has unlimited disk quota, and so ".
			       "cannot be assigned to reseller $r who has ".
			       "a quota limit");
			}
		if (($dom->{'bw_limit'} eq '' || $dom->{'bw_limit'} eq '0') &&
		    $rinfo->{'acl'}->{'max_bw'}) {
			&usage("This domain has unlimited bandwidth, and so ".
			       "cannot be assigned to reseller $r who has ".
			       "a bandwidth limit");
			}
		}

	# Apply changes
	my @r = split(/\s+/, $dom->{'reseller'});
	if ($resel) {
		@r = ( $resel );
		}
	push(@r, @add_resel);
	@r = grep { &indexof($_, @del_resel) < 0 } @r;
	$dom->{'reseller'} = join(" ", &unique(@r));
	}

if (defined($dns_ip)) {
	if ($dns_ip) {
		# Changing IP address for DNS
		$dom->{'dns_ip'} = $dns_ip;
		}
	else {
		# Resetting DNS IP address to default
		delete($dom->{'dns_ip'});
		}
	}

# Change the plan and limits, if given
if ($plan) {
	$dom->{'plan'} = $plan->{'id'};
	if ($planapply) {
		&set_limits_from_plan($dom, $plan);
		&set_featurelimits_from_plan($dom, $plan);
		&set_capabilities_from_plan($dom, $plan);
		}
	}

# Update the IP in alias domains too
if ($dom->{'ip'} ne $old->{'ip'}) {
	@aliases = grep { $_->{'alias'} eq $dom->{'id'} } @doms;
	foreach my $adom (@aliases) {
		$adom->{'ip'} = $dom->{'ip'};
		}
	}

# Run the before script
$config{'pre_command'} = $precommand if ($precommand);
$config{'post_command'} = $postcommand if ($postcommand);
&set_domain_envs($old, "MODIFY_DOMAIN", $dom);
$merr = &making_changes();
&reset_domain_envs($old);
&usage(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Apply the IP change
if ($dom->{'virt'} && !$old->{'virt'}) {
	&setup_virt($dom);
	}
elsif ($dom->{'virt'} && $old->{'virt'}) {
	&modify_virt($dom, $dom);
	}
elsif (!$dom->{'virt'} && $old->{'virt'}) {
	&delete_virt($old);
	}

# Apply the IPv6 change
if ($dom->{'virt6'} && !$old->{'virt6'}) {
	&setup_virt6($dom);
	}
elsif ($dom->{'virt6'} && $old->{'virt6'}) {
	&modify_virt6($dom, $old);
	}
elsif (!$dom->{'virt6'} && $old->{'virt6'}) {
	&delete_virt6($old);
	}

# Apply any jail change
if (defined($jail)) {
	my $err;
	if ($jail) {
		print "Enabling chroot jail ..\n";
		$err = &enable_domain_jailkit($dom);
		}
	else {
		print "Disabling chroot jail ..\n";
		$err = &disable_domain_jailkit($dom);
		}
	$d->{'jail'} = $jail if (!$err);
	&save_domain($dom);
	print $err ? ".. failed : $err\n\n" : ".. done\n\n";
	}

# If the plan is being applied, update features
if ($planfeatures) {
	if ($plan->{'featurelimits'}) {
		# Use features from plan
		%flimits = map { $_, 1 } split(/\s+/, $plan->{'featurelimits'});
		}
	else {
		# Plan is using default features
		%flimits = ( );
		my $parent = $d->{'parent'} ? &get_domain($d->{'parent'})
					   : undef;
		my $alias = $d->{'alias'} ? &get_domain($d->{'alias'})
					  : undef;
		my $subdom = $d->{'subdom'} ? &get_domain($d->{'subdom'})
					    : undef;
		foreach my $f (&list_available_features($parent, $alias,
							$subdom)) {
			if ($f->{'default'} && $f->{'enabled'}) {
				$flimits{$f->{'feature'}} = 1;
				}
			}
		}
	%newdom = %$dom;
	$oldd = { %$dom };

	# Update the newdom object
	print "Applying features from plan ..\n";
	@fchanged = ( );
	foreach my $feat (&list_available_features(undef, undef, undef)) {
		$f = $feat->{'feature'};
		next if ($f eq "dir" || $f eq "unix" ||
			 $f eq "virt" || $f eq "virt6");
		if (!$dom->{$f} && $flimits{$f}) {
			# Need to enable feature
			$newdom{$f} = 1;
			push(@fchanged, $f);
			}
		elsif ($dom->{$f} && !$flimits{$f}) {
			# Need to disable feature
			$newdom{$f} = 0;
			push(@fchanged, $f);
			}
		}
	if (!@fchanged) {
		print ".. nothing to do\n\n";
		goto PLANFAILED;
		}

	# Check for dependencies and clashes
	$derr = &virtual_server_depends(\%newdom, undef, $oldd);
        if ($derr) {
		print ".. $derr\n\n";
		goto PLANFAILED;
                }
        $cerr = &virtual_server_clashes(\%newdom, \%check);
        if ($cerr) {
		print ".. $cerr\n\n";
		goto PLANFAILED;
                }

	# Check warnings
	@warns = &virtual_server_warnings(\%newdom, $oldd);
        if (@warns) {
		if (!$skipwarnings) {
			print ".. warnings detected : ",
			      join(", ", @warns),"\n\n";
			goto PLANFAILED;
			}
		else {
			print ".. warnings bypassed : ",
			      join(", ", @warns),"\n\n";
			}
		}

	# Make the changes
	&$indent_print();
        foreach $f (@fchanged) {
		$dom->{$f} = $newdom{$f};
                }
        foreach $f (@fchanged) {
                &call_feature_func($f, $dom, $oldd);
                }
	&$outdent_print();

	print ".. done\n\n";
	PLANFAILED:
	}

# Call the modify function for enabled features on the domain and sub-servers
for(my $i=0; $i<@doms; $i++) {
	$d = $doms[$i];
	$od = $olddoms[$i];
	print "Updating virtual server $d->{'dom'} ..\n\n";
	foreach $f (@features) {
		if ($config{$f} && $d->{$f}) {
			local $mfunc = "modify_$f";
			&try_function($f, $mfunc, $d, $od);
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($d->{$f}) {
			&plugin_call($f, "feature_modify", $d, $od);
			}
		}

	# Save new domain details
	&$first_print($text{'save_domain'});
	&save_domain($d);
	&$second_print($text{'setup_done'});
	}

# Apply exclude changes
if (@add_excludes || @remove_excludes) {
	&$first_print("Updating excluded directories ..");
	@excludes = &get_backup_excludes($dom);
	push(@excludes, @add_excludes);
	%remove_excludes = map { $_, 1 } @remove_excludes;
	@excludes = grep { !$remove_excludes{$_} } @excludes;
	@excludes = &unique(@excludes);
	&save_backup_excludes($dom, \@excludes);
	&$second_print($text{'setup_done'});
	}
if (@add_db_excludes || @remove_db_excludes) {
	&$first_print("Updating excluded databases ..");
	@db_excludes = &get_backup_db_excludes($dom);
	push(@db_excludes, @add_db_excludes);
	%remove_db_excludes = map { $_, 1 } @remove_db_excludes;
	@db_excludes = grep { !$remove_db_excludes{$_} } @db_excludes;
	@db_excludes = &unique(@db_excludes);
	&save_backup_db_excludes($dom, \@db_excludes);
	&$second_print($text{'setup_done'});
	}

# If the MySQL module changed, update it
if ($mysql_module) {
	if ($dom->{'mysql'}) {
		my ($mod) = grep { $_->{'minfo'}->{'dir'} eq $mysql_module }
			         &list_remote_mysql_modules();
		&$first_print("Moving databases to MySQL server $mod->{'desc'} ..");
		my $ok = &move_mysql_server($dom, $mysql_module);
		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print(".. move failed");
			}
		}
	else {
		# Save if enabled later
		$dom->{'mysql_module'} = $mysql_module;
		}
	}

# Update the Webmin user for this domain, or the parent
&refresh_webmin_user($dom, $old);

# If the template has changed, update secondary groups
if ($dom->{'template'} ne $old->{'template'}) {
	&update_domain_owners_group(undef, $oldd);
	&update_domain_owners_group($d, undef);
	&update_secondary_groups($dom);
	}

# Run the after command
&run_post_actions();
&set_domain_envs($dom, "MODIFY_DOMAIN", undef, $old);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($dom);
&virtualmin_api_log(\@OLDARGV, $dom, $dom->{'hashpass'} ? [ "pass" ] : [ ]);
print "All done\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Changes the settings for a Virtualmin server, based on the specified\n";
print "command-line parameters.\n";
print "\n";
print "virtualmin modify-domain --domain domain.name\n";
print "                        [--desc new-description]\n";
print "                        [--user new-username]\n";
print "                        [--pass \"new-password\" | --passfile password-file]\n";
print "                        [--email new-email]\n";
print "                        [--quota new-quota|UNLIMITED]\n";
print "                        [--uquota new-unix-quota|UNLIMITED]\n";
print "                        [--newdomain new-name]\n";
print "                        [--bw bytes|NONE]\n";
if ($config{'bw_disable'}) {
	print "                        [--bw-disable|--bw-no-disable]\n";
	}
print "                        [--reseller reseller|NONE]\n";
print "                        [--add-reseller reseller]*\n";
print "                        [--delete-reseller reseller]*\n";
print "                        [--ip address] | [--allocate-ip] |\n";
print "                        [--default-ip | --shared-ip address]\n";
if (&supports_ip6()) {
	print "                        [--ip6 address | --allocate-ip6 |\n";
	print "                         --no-ip6 | --default-ip6 |\n";
	print "                         --shared-ip6 address]\n";
	}
print "                        [--prefix name]\n";
print "                        [--template name|id]\n";
print "                        [--plan name|id | --apply-plan name|id]\n";
print "                        [--plan-features]\n";
print "                        [--add-exclude directory]*\n";
print "                        [--remove-exclude directory]*\n";
print "                        [--add-db-exclude db|db.table]*\n";
print "                        [--remove-db-exclude db|db.table]*\n";
print "                        [--dns-ip address | --no-dns-ip]\n";
print "                        [--enable-jail | --disable-jail]\n";
print "                        [--mysql-server hostname]\n";
print "                        [--link-domain domain | --no-link-domain]\n";
print "                        [--skip-warnings]\n";
exit(1);
}


