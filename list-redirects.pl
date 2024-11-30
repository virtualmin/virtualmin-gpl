#!/usr/local/bin/perl

=head1 list-redirects.pl

Lists web redirects and aliases in some domain

This command lists all the aliases configured for some domain identified
by the C<--domain> parameter. By default the list is in a reader-friendly
table format, but can be switched to a more complete and parsable output with
the C<--multiline> flag. Or you can have just the alias paths listed with
the C<--name-only> parameter.

To limit the list to only redirects for some path, use the C<--path> flag
followed by a URL path. Or to limit to redirects for a certain hostname,
use the C<--host> flag.

By default the underlying path to redirect from will be shown, which
typically excludes the C<.well-known> path used by Let's Encrypt. However,
you can transform this to the more user-friendly path shown in the
Virtualmin UI with the C<--fix-wellknown> flag.

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
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	elsif ($a eq "--host") {
		$host = shift(@ARGV);
		}
	elsif ($a eq "--fix-wellknown") {
		$wellknown = 1;
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

# Get the redirect, possibly with filtering
@redirects = &list_redirects($d);
if ($path) {
	$phd = &public_html_dir($d);
	@redirects = grep { $_->{'path'} eq $path ||
			    $_->{'path'} eq $phd.$path } @redirects;
	}
if (defined($host)) {
	@redirects = grep { $_->{'host'} eq $host } @redirects;
	}
if ($wellknown) {
	@redirects = map { &remove_wellknown_redirect($_) } @redirects;
	}

if ($multiline) {
	# Show in multi-line format
	foreach $r (@redirects) {
		print "$r->{'path'}\n";
		print "    Destination: $r->{'dest'}\n";
		print "    Type: ",$r->{'alias'} ? "Alias" : "Redirect","\n";
		print "    Match sub-paths: ",
			$r->{'regexp'} ? "Yes" : "No","\n";
		print "    Match exact path: ",
			$r->{'exact'} ? "Yes" : "No","\n";
		if ($r->{'code'}) {
			print "    Code: ",$r->{'code'},"\n";
			}
		print "    Protocols: ",join(" ", grep { $r->{$_} } ("http", "https")),"\n";
		if ($r->{'host'}) {
			print "    Limit to hostname: $r->{'host'}\n";
			print "    Regexp hostname: ",
				($r->{'hostregexp'} ? "Yes" : "No"),"\n";
			}
		if ($r->{'dirs'}) {
			print "    Directives: ",
				join(" ", &unique(map { $_->{'name'} }
							@{$r->{'dirs'}})),"\n";
			}
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
	$fmt = "%-20.20s %-59.59s\n";
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
print "                         [--multiline | --json | --xml | --name-only]\n";
print "                         [--path /path]\n";
print "                         [--host hostname]\n";
print "                         [--fix-wellknown]\n";
exit(1);
}

