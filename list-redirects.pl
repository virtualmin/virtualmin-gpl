#!/usr/local/bin/perl

=head1 list-redirects.pl

Lists web redirects and aliases in some domain

This command lists all the aliases configured for some domain identified
by the C<--domain> parameter. By default the list is in a reader-friendly
table format, but can be switched to a more complete and parsable output with
the C<--multiline> flag. Or you can have just the alias paths listed with
the C<--name-only> parameter.

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
	$0 = "$pwd/list-proxies.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-redirects.pl must be run as root";
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
&has_web_redirects($d) ||
	&usage("Virtual server $domain does not support redirects");

@redirects = &list_redirects($d);
if ($multi) {
	# Show in multi-line format
	foreach $r (@redirects) {
		print "$r->{'path'}\n";
		print "    Destination: $r->{'dest'}\n";
		print "    Type: ",$r->{'alias'} ? "Alias" : "Redirect","\n";
		print "    Match sub-paths: ",
			$r->{'regexp'} ? "Yes" : "No","\n";
		}
	}
elsif ($nameonly) {
	# Just show paths
	foreach $r (@redirects) {
		print $r->{'path'},"\n";
		}
	}
else {
	# Show all on one line
	$fmt = "%-20s %-59s\n";
	printf $fmt, "Path", "Destination";
	printf $fmt, ("-" x 20), ("-" x 59);
	foreach $r (@redirects) {
		printf $fmt, $r->{'path'}, $r->{'dest'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the web aliases and redirects in some virtual server.\n";
print "\n";
print "virtualmin list-redirects --domain domain.name\n";
print "                         [--multiline | --name-only]\n";
exit(1);
}

