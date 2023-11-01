#!/usr/local/bin/perl

=head1 get-ssl.pl

Output SSL certificate information for a domain.

Given a domain name with the C<--domain> flag, this command outputs 
information about the SSL certificate currently in use by that virtual server.

If the C<--chain> flag is given, details of the CA certificate will be
shown instead (if there is one).

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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--chain") {
		$chain = 1;
		}
	elsif ($a eq "--help") {
		&usage();
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

# Get either the CA or actual cert
$cafile = &get_website_ssl_file($d, "ca");
if ($chain) {
	$cafile || &usage("Virtual server does not have a CA certificate");
	$info = &cert_file_info($cafile, $d);
	}
else {
	$info = &cert_info($d);
	}
$info || &usage("No SSL certificate found");

if (!$chain) {
	print "cert: ",&get_website_ssl_file($d, "cert"),"\n";
	print "key: ",&get_website_ssl_file($d, "key"),"\n";
	}
if ($cafile) {
	print "ca: ",$cafile,"\n";
	}
my $keytype = &get_ssl_key_type(
		&get_website_ssl_file($d, "key"),
		$d->{'ssl_pass'});
print "type: $keytype\n";
foreach my $i (@cert_attributes) {
	$v = $info->{$i};
	if (ref($v)) {
		foreach my $vv (@$v) {
			print $i,": ",$vv,"\n";
			}
		}
	elsif ($v) {
		if ($keytype =~ /^ec/) {
			$i = "pub" if ($i eq "modulus");
			$i = "properties" if ($i eq "exponent");
			}
		print $i,": ",$v,"\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Displays SSL certificate information for some domain.\n";
print "\n";
print "virtualmin get-ssl --domain name\n";
print "                  [--chain]\n";
exit(1);
}

