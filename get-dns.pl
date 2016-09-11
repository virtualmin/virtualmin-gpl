#!/usr/local/bin/perl

=head1 get-dns.pl

Output all DNS records for a domain.

For virtual servers with DNS enabled, this command provides an easy way to
see what DNS records currently exist. The server is specified with the 
C<--domain> flag, followed by a domain name.

By default, output is in a human-readable table format. However, you can
choose to a more easily parsed and complete format with the C<--multiline>
flag, or get a list of just record names with the C<--name-only> option.

Normally the command will output the DNS records in the domain's zone file,
but you can request to show the DNSSEC DS records that should be created
in the registrar's zone with the C<--ds-records> flag.

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
	$0 = "$pwd/get-dns.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-dns.pl must be run as root";
	}

# Parse command line
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--ds-records") {
		$dsmode = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs and get the domain
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("Virtual server $dname does not exist");
$d->{'dns'} || &usage("Virtual server $dname does not have DNS enabled");

if ($dsmode) {
	$dsrecs = &get_domain_dnssec_ds_records($d);
	ref($dsrecs) || &usage($dsrecs);
	@recs = @$dsrecs;
	}
else {
	@recs = grep { $_->{'type'} } &get_domain_dns_records($d);
	}
if ($nameonly) {
	# Only record names
	foreach $r (@recs) {
		print $r->{'name'},"\n";
		}
	}
elsif ($multiline) {
	# Full details
	foreach $r (@recs) {
		print $r->{'name'},"\n";
		print "    Type: $r->{'type'}\n";
		print "    Class: $r->{'class'}\n";
		if ($r->{'ttl'}) {
			print "    TTL: $r->{'ttl'}\n";
			}
		foreach $v (@{$r->{'values'}}) {
			print "    Value: $v\n";
			}
		}
	}
else {
	# Table format
	$fmt = "%-30.30s %-5.5s %-40.40s\n";
	printf $fmt, "Record", "Type", "Value";
	printf $fmt, ("-" x 30), ("-" x 5), ("-" x 40);
	foreach $r (@recs) {
		$r->{'name'} =~ s/\.\Q$d->{'dom'}\E\.//i;
		$r->{'name'} ||= '@';
		printf $fmt, $r->{'name'}, $r->{'type'}, 
			     join(" ", @{$r->{'values'}});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the DNS records in some domain.\n";
print "\n";
print "virtualmin get-dns --domain name\n";
print "                  [--ds-records]\n";
print "                  [--multiline | --name-only]\n";
exit(1);
}

