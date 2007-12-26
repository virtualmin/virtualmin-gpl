#!/usr/local/bin/perl
# Change DNS settings for some domains

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-dns.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-dns.pl must be run as root";
	}
$config{'dns'} || &usage("The BIND DNS server is not enabled for Virtualmin");

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

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
	else {
		&usage();
		}
	}
@dnames || $all_doms || usage();
defined($spf) || %add || %rem || defined($spfall) || defined($dns_ip) ||
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

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
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

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes DNS settings for one or more domains.\n";
print "\n";
print "usage: modify-dns.pl [--domain name]* | [--all-domains] |\n";
print "                     [--all-nonvirt-domains]\n";
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
print "                     [--dns-ip address | --no-dns-ip]\n";
exit(1);
}

