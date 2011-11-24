#!/usr/local/bin/perl

=head1 get-ssl.pl

Output SSL certificate information for a domain.

Given a domain name with the C<--domain> flag, this command outputs 
information about the SSL certificate currently in use by that virtual server.

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
	$0 = "$pwd/get-ssl.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-ssl.pl must be run as root";
	}

# Parse command line
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
$d->{'ssl_cert'} || &usage("Virtual server $dname does not have SSL enabled");

$info = &cert_info($d);
$info || &usage("No SSL certificate found");

foreach $i (@cert_attributes) {
	$v = $info->{$i};
	if (ref($v)) {
		foreach my $vv (@$v) {
			print $i,": ",$vv,"\n";
			}
		}
	elsif ($v) {
		print $i,": ",$v,"\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Displays SSL certificate information for some domain.\n";
print "\n";
print "virtualmin get-ssl --domain name\n";
exit(1);
}

