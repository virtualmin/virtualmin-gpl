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
section on create-domain.pl.

To revert a server with a private IP back to the system's default shared
address, use the C<--default-ip> flag. If the system has more than one shared
address, the C<--shared-ip> flag can be used to change it.

To change a server's domain name, the C<--newdomain> option can be used. It must
be followed by a new domain name, which of course cannot be used by any
existing virtual server. When changing the domain name, you may also want to
use the C<--user> option to update the administration username for the server.
Both of these options will effect sub-servers as well, where appropriate.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;

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
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--quota") {
		$quota = shift(@ARGV);
		$quota =~ /^\d+$/ || &usage("Quota must be a number of blocks");
		}
	elsif ($a eq "--uquota") {
		$uquota = shift(@ARGV);
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
		-d $home || &usage("New home directory already exists");
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
	elsif ($a eq "--reseller") {
		# Changing the reseller
		$resel = shift(@ARGV);
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
	elsif ($a eq "--add-exclude") {
		push(@add_excludes, shift(@ARGV));
		}
	elsif ($a eq "--remove-exclude") {
		push(@remove_excludes, shift(@ARGV));
		}
	elsif ($a eq "--pre-command") {
		$precommand = shift(@ARGV);
		}
	elsif ($a eq "--post-command") {
		$postcommand = shift(@ARGV);
		}
	else {
		usage();
		}
	}

# Find the domain
$domain || usage();
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

# Validate IP change options
if ($ip && $dom->{'alias'}) {
	&usage("An IP address cannot be added to a virtual domain");
	}
if ($dom->{'virt'} && $ip eq "allocate") {
	&usage("An IP address cannot be allocated when one is already active");
	}
elsif (!$dom->{'virt'} && $ip eq "allocate") {
	$config{'all_namevirtual'} && &usage("The --allocate-ip option cannot be used when all virtual servers are name-based");
	%racl = $d->{'reseller'} ? &get_reseller_acl($d->{'reseller'}) : ( );
	if ($racl{'ranges'}) {
		# Allocating IP from reseller's ranges
		$ip = &free_ip_address(\%racl);
		$ip || &usage("Failed to allocate IP address from reseller's ranges!");
		}
	else {
		# Allocating from template's ranges
		$tmpl->{'ranges'} eq "none" && &usage("The --allocate-ip option cannot be used unless automatic IP allocation is enabled - use --ip instead");
		$ip = &free_ip_address($tmpl);
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

if (defined($resel)) {
	$dom->{'parent'} && &usage("Reseller cannot be set for a sub-server");
	@resels = &list_resellers();
	($rinfo) = grep { $_->{'name'} eq $resel } @resels;
	$resel eq "NONE" || $rinfo || &usage("Reseller $resel not found");
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
		}
	}
if (defined($email)) {
	foreach $d (@doms) {
		$d->{'email'} = $email;
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
	$dom->{'bw_limit'} = $bw eq "none" ? undef : $bw;
	}
if (defined($bw_no_disable)) {
	$dom->{'bw_no_disable'} = $bw_no_disable;
	}
if (defined($ip)) {
	# Just change the IP
	$dom->{'ip'} = $ip;
	delete($dom->{'dns_ip'});
	if (!$config{'all_namevirtual'}) {
		$dom->{'virt'} = 1;
		$dom->{'name'} = 0;
		$dom->{'virtalready'} = 0;
		}
	}
if ($defaultip) {
	# Falling back to default IP
	$dom->{'ip'} = &get_default_ip($dom->{'reseller'});
	$dom->{'defip'} = $dom->{'ip'} eq &get_default_ip();
	$dom->{'virt'} = 0;
	$dom->{'virtalready'} = 0;
	$dom->{'name'} = 1;
	delete($dom->{'dns_ip'});
	}
if (defined($sharedip)) {
	# Just change the shared IP address
	$dom->{'ip'} = $sharedip;
	}
if (defined($resel)) {
	$dom->{'reseller'} = $resel eq "NONE" ? undef : $resel;
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

# Actually update the domains
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
	foreach $f (@feature_plugins) {
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

&refresh_webmin_user($dom);

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $old);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);
&virtualmin_api_log(\@OLDARGV, $dom);
print "All done\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Changes the settings for a Virtualmin server, based on the specified\n";
print "command-line parameters.\n";
print "\n";
print "usage: modify-domain.pl  --domain domain.name\n";
print "                        [--desc new-description]\n";
print "                        [--user new-username]\n";
print "                        [--pass new-password]\n";
print "                        [--email new-email]\n";
print "                        [--quota new-quota]\n";
print "                        [--uquota new-unix-quota]\n";
print "                        [--newdomain new-name]\n";
print "                        [--bw bytes|NONE]\n";
if ($config{'bw_disable'}) {
	print "                        [--bw-disable|--bw-no-disable]\n";
	}
print "                        [--resel reseller|NONE]\n";
print "                        [--ip address] | [--allocate-ip] |\n";
print "                        [--default-ip | --shared-ip address]\n";
print "                        [--prefix name]\n";
print "                        [--template name|id]\n";
print "                        [--add-exclude directory]*\n";
print "                        [--remove-exclude directory]*\n";
exit(1);
}


