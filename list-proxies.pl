#!/usr/local/bin/perl

=head1 list-proxies.pl

Lists web proxy balancers in some domain

This command lists all the proxies configured for some domain identified
by the C<--domain> parameter. By default the list is in a reader-friendly
table format, but can be switched to a more complete and parsable output with
the C<--multiline> flag. Or you can have just the proxy paths listed with
the C<--name-only> parameter.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/pro\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/list-proxies.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-proxies.pl must be run as root";
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
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&has_proxy_balancer($d) || &usage("Proxies cannot be configured for this virtual server");

@balancers = &list_proxy_balancers($d);
if ($multi) {
	# Show each destination on a separate line
	foreach $b (@balancers) {
		print "$b->{'path'}\n";
		if ($b->{'balancer'}) {
			print "    Balancer: $b->{'balancer'}\n";
			}
		print "    Proxying: ",$b->{'none'} ? "No" : "Yes","\n";
		foreach $u (@{$b->{'urls'}}) {
			print "    URL: $u\n";
			}
		}
	}
elsif ($nameonly) {
	# Just show paths
	foreach $b (@balancers) {
		print $b->{'path'},"\n";
		}
	}
else {
	# Show all on one line
	$fmt = "%-20s %-59s\n";
	printf $fmt, "Path", "URLs";
	printf $fmt, ("-" x 20), ("-" x 59);
	foreach $b (@balancers) {
		printf $fmt, $b->{'path'}, $b->{'none'} ? "No proxying" :
						join(" ", @{$b->{'urls'}});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the web proxy balancers in some virtual server.\n";
print "\n";
print "virtualmin list-proxies --domain domain.name\n";
print "                       [--multiline | --name-only]\n";
exit(1);
}

