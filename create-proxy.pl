#!/usr/local/bin/perl

=head1 create-proxy.pl

Adds a per-directory proxy to some domain

A proxy maps some URL on a virtual server to another webserver. This means
that requests for any page under that URL path will be forwarded to the
other site, which could be a separate machine or another webserver process
on the same system (such as Tomcat for Java or Mongrel for Ruby on Rails).

The C<--domain> parameter must be given and followed by a virtual server's
domain name. The C<--path> parameter is also mandatory, and must be followed
by a local URL path like C</rails> or even C</>. Finally, you must give the
C<--url> parameter, followed by a URL to forward to like C<http://www.foo.com/>.

If running Apache 2.0 or later with the C<mod_proxy_balancer> module, the
C<--url> parameter can be given multiple times. Your webserver will then
round-robin balance requests between all the URLs, which should serve the
same content. This is useful for load-balancing between multiple backend
servers.

If you want to turn off proxying for some URL path, the C<--no-proxy>
flag can be given instead of C<--url>. This is useful if you have proxying
enabled for C</> but want to serve content for some sub-directory locally.

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
	$0 = "$pwd/create-proxy.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-proxy.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
&require_mail();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--balancer") {
		$balancer = shift(@ARGV);
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	elsif ($a eq "--url") {
		push(@urls, shift(@ARGV));
		}
	elsif ($a eq "--no-proxy") {
		$none = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$domain || &usage("No domain specified");
$path || &usage("No proxy path specified");
@urls || $none || &usage("At least one URL must be specified");
$path =~ /^\/\S*$/ || &error("Path must be like / or /foo");

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$has = &has_proxy_balancer($d);

$has || &usage("Proxies cannot be configured for this virtual server");
$has == 2 || $none || @urls == 1 || &usage("Multiple URL proxy balancers cannot be configured for this virtual server");
!$none || &has_proxy_none($d) ||
	&usage("Paths that do not proxy cannot be configured on this system");

# Work out balancer name, if needed
if ($has == 1) {
	$balancer && &usage("No balancer name is needed for virtual servers ".
			    "that only support a single URL");
	}
elsif (!$balancer) {
	$path =~ /^\/(\S*)$/;
	$balancer = $1 || "root";
	}

# Check for clash
&obtain_lock_web($d);
@balancers = &list_proxy_balancers($d);
($clash) = grep { $_->{'path'} eq $path } @balancers;
$clash && &usage("A balancer for the path $path already exists");
if ($balancer) {
	($clash) = grep { $_->{'balancer'} eq $balancer } @balancers;
	$clash && &usage("A balancer named $balancer already exists");
	}

# Create it
$b = { 'path' => $path,
       'balancer' => $balancer,
       'none' => $none,
       'urls' => \@urls };
$err = &create_proxy_balancer($d, $b);
&release_lock_web($d);
if ($err) {
	print "Failed to create proxy : $err\n";
	exit(1);
	}
else {
	&set_all_null_print();
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	print "Proxy for $path created successfully\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a proxy to a virtual server's website.\n";
print "\n";
print "virtualmin create-proxy --domain domain.name\n";
print "                        --path url-path\n";
if (!defined($has) || $has == 2) {
	print "                        --url destination [--url destination]*\n";
	print "                       [--balancer name]\n";
	}
else {
	print "                        --url destination\n";
	}
print "                        --no-proxy\n";
exit(1);
}

