#!/usr/local/bin/perl

=head1 delete-admin.pl

Deletes an extra administrator from a virtual server

This command removes one extra administrator from a virtual server. The
required parameters are C<--domain> followed by the domain name, and C<--name>
followed by the administrator account name.

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
	$0 = "$pwd/delete-admin.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-admin.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--name") {
		$name = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$name || &usage("No username specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");

# Find the admin, and delete him
&obtain_lock_webmin();
@admins = &list_extra_admins($d);
($admin) = grep { $_->{'name'} eq $name } @admins;
$admin || &usage("Extra administrator $name does not exist in this virtual server");
&delete_extra_admin($admin, $d);
&release_lock_webmin();
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV, $d);
print "Extra administrator $name deleted successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes an extra administrator associated with some virtual server.\n";
print "\n";
print "virtualmin delete-admin --domain domain.name\n";
print "                        --name login\n";
exit(1);
}

