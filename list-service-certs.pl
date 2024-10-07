#!/usr/local/bin/perl

=head1 list-service-certs.pl

Output a virtual server's certificates used by other services.

The only required flag is C<--domain>, which must be followed by the domain
name to display service certificates for. The optional C<--multiline> param
determines if full details of each service are displayed or not.

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
	$0 = "$pwd/list-certs.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-certs.pl must be run as root";
	}

# Parse command line to get domains
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs and get the domain
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("Virtual server $dname does not exist");
&domain_has_ssl_cert($d) ||
	&usage("Virtual server $dname does not have an SSL cert");
@svcs = &get_all_domain_service_ssl_certs($d);

if ($multiline) {
	# Show all details of each service
	foreach my $svc (@svcs) {
		print $svc->{'id'},"\n";
		print "    Service type: ",
		      ($svc->{'d'} ? "domain" : "global"),"\n";
		print "    Cert file: ",$svc->{'cert'},"\n";
		print "    Key file: ",$svc->{'key'},"\n" if ($svc->{'key'});
		print "    CA file: ",$svc->{'ca'},"\n" if ($svc->{'ca'});
		print "    IP address: ",$svc->{'ip'},"\n" if ($svc->{'ip'});
		print "    Domain name: ",$svc->{'dom'},"\n" if ($svc->{'dom'});
		print "    Service port: ",$svc->{'port'},"\n" if ($svc->{'port'});
		}
	}
else {
	# Just show summary lines
	$fmt = "%-10.10s %-6.6s %-60.60s\n";
	printf $fmt, "Service", "Type", "Domain or IP";
	printf $fmt, ("-" x 10), ("-" x 6), ("-" x 60);
	foreach my $svc (@svcs) {
		printf $fmt, $svc->{'id'},
			     $svc->{'d'} ? "Domain" : "Global",
			     $svc->{'ip'} || $svc->{'dom'} || "All";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Output a virtual server's certificates used by other services.\n";
print "\n";
print "virtualmin list-service-certs --domain name\n";
print "                             [--multiline | --json | --xml]\n";
exit(1);
}

