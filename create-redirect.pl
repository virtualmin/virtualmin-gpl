#!/usr/local/bin/perl

=head1 create-redirect.pl

Adds a web redirect or alias to some domain

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
	$0 = "$pwd/create-redirect.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-redirect.pl must be run as root";
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
	else {
		&usage();
		}
	}
$domain && $path || &usage();
@urls || $none || &usage("At least one URL must be specified");
$path =~ /^\/\S*$/ || &error("Path must be like / or /foo");

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$has = &has_proxy_balancer($d);

$has || &usage("Proxies cannot be configured for this virtual server");
$has == 2 || $none || @urls == 1 || &usage("Multiple URL proxy balancers cannot be configured for this virtual server");
!$none || &has_proxy_none() || &usage("Paths that do not proxy cannot be configured on this system");

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
print "Adds redirect or alias to a virtual server's website.\n";
print "\n";
print "virtualmin create-redirect --domain domain.name\n";
print "                           --path url-path\n";
print "                           --alias directory | --redirect url\n";
print "                          [--regexp]\n";
exit(1);
}

