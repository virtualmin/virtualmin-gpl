#!/usr/local/bin/perl

=head1 modify-proxy.pl

Changes a proxy balancer from some domain

This command updates one proxy path from the virtual server identified
by the C<--domain> flag. The proxy to remove must be identified by the 
C<--path> parameter.

The URL path for the proxy can be changed with the C<--new-path> flag, followed
by a path like /foo. The destination URLs can be set with the C<--url> flag
followed by a URL - this flag can be given multiple times.

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
	$0 = "$pwd/modify-proxy.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-proxy.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
&require_mail();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	elsif ($a eq "--new-path") {
		$newpath = shift(@ARGV);
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
$domain && $path || &usage("No domain or URL path specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&has_proxy_balancer($d) || &usage("Proxy balancers cannot be configured for this virtual server");
!$newpath || $newpath =~ /^\/\S*$/ || &error("Path must be like / or /foo");

# Get the balancer
&obtain_lock_web($d);
@balancers = &list_proxy_balancers($d);
($b) = grep { $_->{'path'} eq $path } @balancers;
$b || &usage("No proxy balancer for the path $path was found");
$oldb = { %$b };

# Modify the object
if ($newpath) {
	$b->{'path'} = $newpath;
	}
if ($none) {
	$b->{'none'} = 1;
	}
elsif (@urls) {
	$b->{'none'} = 0;
	$b->{'urls'} = \@urls;
	}

# Update it
$err = &modify_proxy_balancer($d, $b, $oldb);
&release_lock_web($d);
if ($err) {
	print "Failed to update balancer : $err\n";
	exit(1);
	}
else {
	&set_all_null_print();
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	print "Proxy balancer for $path updated successfully\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Updates a proxy balancer in a virtual server's website.\n";
print "\n";
print "virtualmin modify-proxy --domain domain.name\n";
print "                        --path url-path\n";
print "                       [--new-path url-path]\n";
print "                       [--no-proxy]\n";
print "                       [--url http://something]*\n";
exit(1);
}

