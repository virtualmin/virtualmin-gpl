#!/usr/local/bin/perl

=head1 list-ports.pl

Lists TCP ports associated with some virtual server

This command lists all TCP ports in use by or allowed to be used by the
virtual server selected with the C<--domain> flag. To output a list of just
port numbers, use the C<--port-only> flag. Or to show the full details of
each port, use C<--multiline>.

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
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--port-only") {
		$portonly = 1;
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

my %done;
if ($multiline) {
	# Show full details
	foreach my $p (@allports) {
		next if ($done{$p->{'lport'}}++);
		print $p->{'lport'},"\n";
		my ($use) = grep { $_->{'lport'} eq $p->{'lport'} } @useports;
		my ($can) = grep { $_->{'lport'} eq $p->{'lport'} } @canports;
		print "  In use: ",($use ? "Yes" : "No"),"\n";
		print "  Allowed: ",($can ? "Yes" : "No"),"\n";
		if ($use) {
			print "  Used by PID: ",$use->{'proc'}->{'pid'},"\n";
			print "  Used by command: ",$use->{'proc'}->{'args'},"\n";
			print "  Used by user: ",$use->{'user'}->{'user'},"\n";
			}
		if ($can) {
			print "  Allowed type: ",$can->{'type'},"\n";
			print "  Allowed by: ",$can->{'desc'},"\n";
			}
		}
	}
elsif ($portonly) {
	# Just show port numbers
	foreach my $p (&unique(map { $_->{'lport'} } @allports)) {
		print $p,"\n";
		}
	}
else {
	# Show table of ports
	$fmt = "%-6.6s %-10.10s %-6.6s %-50.50s\n";
	printf $fmt, "Port", "Status", "PID", "Allowed by";
	printf $fmt, ("-" x 6), ("-" x 10), ("-" x 6), ("-" x 50);
	foreach my $p (@allports) {
		next if ($done{$p->{'lport'}}++);
		my ($use) = grep { $_->{'lport'} eq $p->{'lport'} } @useports;
		my ($can) = grep { $_->{'lport'} eq $p->{'lport'} } @canports;
		printf $fmt, $p->{'lport'},
			$use && $can ? "Active" :
			$can ? "Allowed" :
			$use ? "Not allowed" : "",
			$use ? $use->{'proc'}->{'pid'} : "",
			$can ? $can->{'desc'} : "";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists TCP ports associated with some virtual server.\n";
print "\n";
print "virtualmin list-ports --domain name\n";
print "                     [--multiline | --json | --xml]\n";
print "                     [--port-only]\n";
exit(1);
}

