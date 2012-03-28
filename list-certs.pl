#!/usr/local/bin/perl

=head1 get-cert.pl

Output the certificates for some or all virtual servers.

The virtual servers to list can be selected with the C<--domain> flag
followed by a domain name, or C<--user> followed by an administrator's
username - both of which can be given multiple times. Or you can use 
C<--all-domains> to find certificates for every virtual server with SSL
enabled.

By default, all known certificates and keys are output. However, you can
limit the results to particular certificates with one of more of the
following flags :

C<--cert> - SSL certificate only

C<--key> - SSL private key

C<--ca> - SSL chained CA certificate, if there is one

C<--csr> - SSL certificate signing request, for sending to a CA

C<--newkey> - SSL private key matching the CSR, but not yet installed

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
@alltypes = ( "cert", "key", "ca", "csr", "newkey" );
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--cert" || $a eq "--key" || $a eq "--ca" ||
	       $a eq "--csr" || $a eq "--newkey") {
		push(@types, substr($a, 2));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the domains
@dnames || @users || $all || &usage();
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@doms || &usage("No virtual servers matching the domain names and usernames ".
		"given were found");
@doms = grep { &domain_has_ssl($_) } @doms;
@doms || &usage("None of the specified virtual servers have SSL enabled");
if (!@types) {
	@types = @alltypes;
	}

# Output the certs
foreach $d (@doms) {
	foreach $t (@types) {
		$data = $d->{'ssl_'.$t} ? &read_file_contents($d->{'ssl_'.$t})
					: undef;
		if ($data) {
			print "$d->{'dom'}:\n";
			print "    Type: $t\n";
			print "    File: ",$d->{'ssl_'.$t},"\n";
			$data =~ s/\s*$//g;
			$data .= "\n";
			print $data;
			}
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Outputs the certificates and keys for one or more virtual servers.\n";
print "\n";
print "virtualmin list-certs --all-domains | --domain name | --user username\n";
print "                     [".join(" | ", map { "--".$_ } @alltypes)."]\n";
exit(1);
}

