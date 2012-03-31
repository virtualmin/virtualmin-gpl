#!/usr/local/bin/perl

=head1 modify-dns.pl

Change DNS settings for virtual servers

This program updates DNS-related options for one or more servers, selected using the C<--domain> or C<--all-domains> flags. Or you can select all domains that
don't have their own private IP address with C<--all-nonvirt-domains>.

To enable SPF for a domain, using C<--spf> option, and to turn it off use C<--no-spf>. By default, the SPF record will be created using the settings from the DNS section of the domain's server template.

To add allowed hostname, MX domains or IP addresses, use the C<--spf-add-a>, C<--spf-add-mx> and C<--spf-add-ip4> options respectively. Each of which must be followed by a single host, domain or IP address.

Similarly, the C<--spf-remove-a>, C<--spf-remove-mx> and C<--spf-remove-ip4> options will remove the following host, domain or IP address from the allowed list for the specified domains.

To control how SPF treats senders not in the allowed hosts list, use one of the C<--spf-all-disallow>, C<--spf-all-discourage>, C<--spf-all-neutral>, C<--spf-all-allow> or C<--spf-all-default> parameters.

This command can also be used to add and remove DNS records from all the
selected domains. Adding is done with the C<--add-record> flag, which must
be followed by a single parameter containing the record name, type and value.
Similarly, deletion is done with the C<--delete-record> flag, followed by a 
single parameter containing the name and type of the record(s) to delete. Both
of these can be given multiple times.

Similarly, the default TTL for records can be set with the C<--ttl> flag
followed by a number in seconds. Suffixes like h, m and d are also allowed
to specific a TTL in hours, minutes or days.

You can also add or remove slave DNS servers for this domain, assuming that
they have already been setup in Webmin's BIND DNS Server module. To add a
specific slave host, use the C<--add-slave> flag followed by a hostname. Or to
add them all, use the C<--add-all-slaves> flag. To remove a single slave host,
use the C<--remove-slave> command followed by a hostname.

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
	$0 = "$pwd/modify-dns.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-dns.pl must be run as root";
	}
&require_bind();
@OLDARGV = @ARGV;
$config{'dns'} || &usage("The BIND DNS server is not enabled for Virtualmin");
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--all-nonvirt-domains") {
		$all_doms = 2;
		}
	elsif ($a eq "--spf") {
		$spf = 1;
		}
	elsif ($a eq "--no-spf") {
		$spf = 0;
		}
	elsif ($a =~ /^--spf-add-(a|mx|ip4)$/) {
		$add = shift(@ARGV);
		$type = $1;
		$add =~ /^[a-z0-9\.\-\_]+$/ ||
		    &usage("$a must be followed by a hostname or IP address");
		push(@{$add{$type}}, $add);
		}
	elsif ($a =~ /^--spf-remove-(a|mx|ip4)$/) {
		$rem = shift(@ARGV);
		$type = $1;
		$rem =~ /^[a-z0-9\.\-\_]+$/ ||
		    &usage("$a must be followed by a hostname or IP address");
		push(@{$rem{$type}}, $rem);
		}
	elsif ($a =~ /^--spf-all-(disallow|discourage|neutral|allow|default)$/){
		$spfall = $1 eq "disallow" ? 3 :
			  $1 eq "discourage" ? 2 :
			  $1 eq "neutral" ? 1 :
			  $1 eq "allow" ? 0 : -1;
		}
	elsif ($a eq "--dns-ip") {
		$dns_ip = shift(@ARGV);
		&check_ipaddress($dns_ip) ||
			&usage("--dns-ip must be followed by an IP address");
		}
	elsif ($a eq "--no-dns-ip") {
		$dns_ip = "";
		}
	elsif ($a eq "--add-record") {
		my ($name, $type, @values) = split(/\s+/, shift(@ARGV));
		$name && $type && @values || &usage("--add-record must be followed by the record name, type and values, all in one parameter");
		push(@addrecs, [ $name, $type, \@values ]);
		}
	elsif ($a eq "--remove-record") {
		my ($name, $type) = split(/\s+/, shift(@ARGV));
		$name && $type || &usage("--remove-record must be followed by the record name and type, all in one parameter");
		push(@delrecs, [ $name, $type ]);
		}
	elsif ($a eq "--ttl") {
		$ttl = shift(@ARGV);
		$ttl =~ /^\d+(s|m|h|d)?$/ || &usage("--ttl must be followed by a number with a valid suffix");
		}
	elsif ($a eq "--increment-soa") {
		$bumpsoa = 1;
		}
	elsif ($a eq "--add-slave") {
		push(@addslaves, shift(@ARGV));
		}
	elsif ($a eq "--remove-slave") {
		push(@delslaves, shift(@ARGV));
		}
	elsif ($a eq "--add-all-slaves") {
		$addallslaves = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains specified");
defined($spf) || %add || %rem || defined($spfall) || defined($dns_ip) ||
  @addrecs || @delrecs || @addslaves || @delslaves || $addallslaves || $ttl ||
  &usage("Nothing to do");

# Get domains to update
if ($all_doms == 1) {
	@doms = grep { $_->{'dns'} } &list_domains();
	}
elsif ($all_doms == 2) {
	@doms = grep { $_->{'dns'} && !$_->{'virt'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'dns'} || &usage("Virtual server $n does not have a DNS domain");
		push(@doms, $d);
		}
	}

# Validate slave args
&require_bind();
if (@addslaves && $addallslaves) {
	&usage("Both --add-slave and --add-all-slaves cannot be specified at the same time");
	}
@slaveservers = &bind8::list_slave_servers();
if ($addallslaves) {
	@addslaves = map { $_->{'host'} } @slaveservers;
	@addslaves || &usage("No slave DNS servers have been setup in Webmin's BIND module");
	}
elsif (@addslaves) {
	foreach $s (@addslaves) {
		($ss) = grep { $_->{'host'} eq $s } @slaveservers;
		$ss || &usage("No slave DNS server with hostname $s exists");
		}
	}
if (@delslaves) {
	foreach $s (@delslaves) {
		($ss) = grep { $_->{'host'} eq $s } @slaveservers;
		$ss || &usage("No slave DNS server with hostname $s exists");
		}
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&obtain_lock_dns($d);
	&$indent_print();
	$oldd = { %$d };

	$currspf = &get_domain_spf($d);
	if (defined($spf)) {
		# Turn SPF on or off
		if ($spf == 1 && !$currspf) {
			# Need to enable, with default settings
			&$first_print($text{'spf_enable'});
			&save_domain_spf($d, $currspf=&default_domain_spf($d));
			&$second_print($text{'setup_done'});
			}
		elsif ($spf == 0 && $currspf) {
			# Need to disable
			&$first_print($text{'spf_disable'});
			&save_domain_spf($d, undef);
			&$second_print($text{'setup_done'});
			$currspf = undef;
			}
		}

	if ((%add || %rem || defined($spfall)) && $currspf) {
		# Update a, mx and ip4 in SPF record
		&$first_print($text{'spf_change'});
		foreach $t (keys %add) {
			foreach $a (@{$add{$t}}) {
				push(@{$currspf->{$t.":"}}, $a);
				}
			$currspf->{$t.":"} = [ &unique(@{$currspf->{$t.":"}}) ];
			}
		foreach $t (keys %rem) {
			foreach $a (@{$rem{$t}}) {
				$currspf->{$t.":"} =
				    [ grep { $_ ne $a } @{$currspf->{$t.":"}} ];
				}
			}
		if (defined($spfall)) {
			if ($spfall < 0) {
				delete($currspf->{'all'});
				}
			else {
				$currspf->{'all'} = $spfall;
				}
			}
		&save_domain_spf($d, $currspf);
		&$second_print($text{'setup_done'});
		}

	if (defined($dns_ip)) {
		if ($dns_ip) {
			# Changing IP address for DNS
			$d->{'dns_ip'} = $dns_ip;
			}
		else {
			# Resetting DNS IP address to default
			delete($d->{'dns_ip'});
			}
		&modify_dns($d, $oldd);
		&save_domain($d);
		}

	# Remove records from the domain
	local ($recs, $file) = &get_domain_dns_records_and_file($d);
	local $changed;
	if (@delrecs) {
		local @alld;
		foreach my $rn (@delrecs) {
			my ($name, $type) = @$rn;
			if ($name !~ /\.$/) {
				$name .= ".".$d->{'dom'}.".";
				}
			local @d = grep { $_->{'name'} eq $name &&
					  lc($_->{'type'}) eq lc($type) } @$recs;
			push(@alld, @d);
			}
		@alld = sort { $b->{'line'} cmp $a->{'line'} } @alld;
		foreach my $r (@alld) {
			&bind8::delete_record($file, $r);
			$changed++;
			}
		}

	# Add records to the domain
	if (@addrecs) {
		foreach my $rn (@addrecs) {
			my ($name, $type, $values) = @$rn;
			if ($name !~ /\.$/) {
				$name .= ".".$d->{'dom'}.".";
				}
			&bind8::create_record($file, $name, undef, "IN",
					      uc($type), join(" ", @$values));
			$changed++;
			}
		}

	# Set or modify default TTL
	if ($ttl) {
		($oldttl) = grep { $_->{'defttl'} } @$recs;
		if ($oldttl) {
			$oldttl->{'defttl'} = $ttl;
			&bind8::modify_defttl($file, $oldttl, $ttl);
			}
		else {
			&bind8::create_defttl($file, $ttl);
			foreach my $e (@$recs) {
				$e->{'line'}++;
				$e->{'eline'}++ if (defined($e->{'eline'}));
				}
			}
		$changed++;
		}

	if ($changed || $bumpsoa) {
		&post_records_change($d, $recs, $file);
		&reload_bind_records($d);
		}

	# Add to slave DNS servers
	if (@addslaves) {
		&create_zone_on_slaves($d, join(" ", @addslaves));
		}
	if (@delslaves) {
		&delete_zone_on_slaves($d, join(" ", @delslaves));
		}

	&$outdent_print();
	&save_domain($d);
	&release_lock_dns($d);
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes DNS settings for one or more domains.\n";
print "\n";
print "virtualmin modify-dns --domain name | --all-domains | --all-nonvirt-domains\n";
print "                     [--spf | --no-spf]\n";
print "                     [--spf-add-a hostname]*\n";
print "                     [--spf-add-mx domain]*\n";
print "                     [--spf-add-ip4 address]*\n";
print "                     [--spf-remove-a hostname]*\n";
print "                     [--spf-remove-mx domain]*\n";
print "                     [--spf-remove-ip4 address]*\n";
print "                     [--spf-all-disallow | --spf-all-discourage |\n";
print "                      --spf-all-neutral | --spf-all-allow |\n";
print "                      --spf-all-default]\n";
print "                     [--add-record \"name type value\"]\n";
print "                     [--remove-record \"name type\"]\n";
print "                     [--ttl seconds]\n";
print "                     [--add-slave hostname]* | [--add-all-slaves]\n";
print "                     [--remove-slave hostname]*\n";
exit(1);
}

