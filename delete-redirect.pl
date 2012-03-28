#!/usr/local/bin/perl

=head1 delete-redirect.pl

Removes a web redirect or alias from some domain

This command deletes one redirect from the virtual server identified
by the C<--domain> flag. The redirect to remove must be identified by the 
C<--path> parameter.

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
	$0 = "$pwd/delete-redirect.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-redirect.pl must be run as root";
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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
$domain && $path || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&has_web_redirects($d) ||
	&usage("Virtual server $domain does not support redirects");

# Get the redirect
&obtain_lock_web($d);
@redirects = &list_redirects($d);
($r) = grep { $_->{'path'} eq $path } @redirects;
$r || &usage("No redirect for the path $path was found");

# Delete it
$err = &delete_redirect($d, $r);
&release_lock_web($d);
if ($err) {
	print "Failed to delete redirect : $err\n";
	exit(1);
	}
else {
	&set_all_null_print();
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	print "Redirect for $path deleted successfully\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes a web redirect or alias from some domain.\n";
print "\n";
print "virtualmin delete-redirect --domain domain.name\n";
print "                           --path url-path\n";
exit(1);
}

