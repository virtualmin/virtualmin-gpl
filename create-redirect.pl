#!/usr/local/bin/perl

=head1 create-redirect.pl

Adds a web redirect or alias to some domain

A redirect maps some URL path like /foo to either a different URL, or a 
different directory on the same virtual server. This can be used to provide
more friendly URL paths on your website, or to cope with the movement of
web pages to new locations.

This command takes a mandatory C<--domain> parameter, followed by a virtual
server's domain name. The C<--path> parameter is also mandatory, and must be
followed by a local URL path like C</rails> or even C</>. 

To redirect to a different URL, use the C<--redirect> flag followed by a
complete URL starting with http or https, or a URL path on this same domain.
To map the path to a directory, use the C<--alias> flag followed by a full
directory path, ideally under the domain's C<public_html> directory.

By default, requests for sub-paths under the URL path will be mapped to
the same sub-path in the destination directory or path. However, you can
use the C<--exact> flag to only match the given path, or the C<--regexp> flag
to ignore sub-paths when redirecting.

If the path to redirect is C</>, this can break requests by Let's Encrypt
needed when issuing new SSL certificates. To prevent this, add the
C<--fix-wellknown> flag which excludes the C<.well-known> path, which is
the same behavior as when a redirect is created in the Virtualmin UI.

For domains with both non-SSL and SSL websites, you can use the C<--http> and
C<--https> flags to limit the alias or redirect to one website type or the
other.

To limit the redirect to requests to a specific URL host, use the 
C<--host> flag followed by a hostname. This is useful for redirecting 
www.domain.com to domain.com, for example. Or if you want the host match
to be a regular expression, use C<--host-regexp> followed by a pattern like
(www|ftp|mail).domain.com.

To set a custom HTTP status code for the redirect, you can use the C<--code>
flag followed by a number. Otherwise the default code of 302 (temporary
redirect) will be used.

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
&licence_status();
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
	elsif ($a eq "--redirect") {
		$url = shift(@ARGV);
		}
	elsif ($a eq "--alias") {
		$dir = shift(@ARGV);
		}
	elsif ($a eq "--regexp") {
		$regexp = 1;
		}
	elsif ($a eq "--exact") {
		$exact = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--http") {
		$http = 1;
		}
	elsif ($a eq "--https") {
		$https = 1;
		}
	elsif ($a eq "--host") {
		$host = shift(@ARGV);
		}
	elsif ($a eq "--host-regexp") {
		$host = shift(@ARGV);
		$hostregexp = 1;
		}
	elsif ($a eq "--code") {
		$code = shift(@ARGV);
		$code =~ /^\d{3}$/ && $code >= 300 && $code < 400 ||
			&usage("--code must be followed by a HTTP status code between 300 and 400");
		}
	elsif ($a eq "--fix-wellknown") {
		$wellknown = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$domain || &usage("No domain specified");
$path || &usage("No redirect path specified");
$exact && $regexp && &usage("Only one of --regexp or --exact can be given");
if ($url) {
	$url =~ /^*(http|https):\/\/\S+$/ ||
	    $url =~ /^\/\S+$/ ||
		&usage("The --redirect flag must be followed by a URL or ".
		       "a URL path");
	}
elsif ($dir) {
	$dir =~ /^\/\S+$/ && -d $dir ||
		&usage("The --alias flag must be followed by a directory");
	}
else {
	&usage("One of --redirect or --alias must be given");
	}
if (!$http && !$https) {
	# If no protocol was given, assume both for backwards compatability
	$http = $https = 1;
	}

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&has_web_redirects($d) ||
	&usage("Virtual server $domain does not support redirects");
!$host || &has_web_host_redirects($d) ||
    &usage("Virtual server $domain does not support hostname-based redirects");

# Check for clash
&obtain_lock_web($d);
@redirects = &list_redirects($d);
($clash) = grep { $_->{'path'} eq $path &&
		  $_->{'host'} eq $host } @balancers;
$clash && &usage("A redirect for path $path ".
		 ($host ? " and host $host" : "")." already exists");

# Create it
$r = { 'path' => $path,
       'dest' => $url || $dir,
       'alias' => $dir ? 1 : 0,
       'regexp' => $regexp,
       'exact' => $exact,
       'http' => $http,
       'https' => $https,
       'code' => $code,
       'host' => $host,
       'hostregexp' => $hostregexp,
     };
if ($wellknown) {
	$r = &add_wellknown_redirect($r);
	}
$err = &create_redirect($d, $r);
&release_lock_web($d);
if ($err) {
	print "Failed to create redirect : $err\n";
	exit(1);
	}
else {
	&set_all_null_print();
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	print "Redirect for $path created successfully\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds redirect or alias to a virtual server's website.\n";
print "\n";
print "virtualmin create-redirect --domain domain.name\n";
print "                           --path url-path\n";
print "                           --alias directory | --redirect url\n";
print "                          [--regexp | --exact]\n";
print "                          [--code number]\n";
print "                          [--host hostname | --host-regexp hostname]\n";
print "                          [--http | --https]\n";
print "                          [--fix-wellknown]\n";
exit(1);
}

