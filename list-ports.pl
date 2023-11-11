#!/usr/local/bin/perl

=head1 list-ports.pl

Lists TCP ports associated with some virtual server

XXX

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
	$0 = "$pwd/list-ports.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-ports.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--port-only") {
		$portonly = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");

my @useports = &active_domain_server_ports($d);
my @canports = &allowed_domain_server_ports($d);
my @allports = sort { $a->{'lport'} <=> $b->{'lport'} } (@useports, @canports);

if ($multiline) {
	foreach my $p (@allports) {
		}
	}
elsif ($portonly) {
	foreach my $p (&unique(map { $_->{'lport'} } @allports)) {
		print $p,"\n";
		}
	}
else {
	}

