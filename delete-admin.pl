#!/usr/local/bin/perl
# Delete an extra admin from some virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/delete-admin.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-admin.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--name") {
		$name = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

$domain && $name || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");

# Find the admin, and delete him
&obtain_lock_webmin();
@admins = &list_extra_admins($d);
($admin) = grep { $_->{'name'} eq $name } @admins;
$admin || &usage("Extra administrator $name does not exist in this virtual server");
&delete_extra_admin($admin, $d);
&release_lock_webmin();
print "Extra administrator $name deleted successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes an extra administrator associated with some virtual server.\n";
print "\n";
print "usage: delete-admin.pl --domain domain.name\n";
print "                       --name login\n";
exit(1);
}

