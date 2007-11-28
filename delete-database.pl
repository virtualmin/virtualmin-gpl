#!/usr/local/bin/perl
# Delete a database from some virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/delete-database.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-database.pl must be run as root";
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
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

$domain && $name && $type || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@dbs = &domain_databases($d);

# Find the database object
($db) = grep { $_->{'name'} eq $name &&
	       $_->{'type'} eq $type } @dbs;
$db || &usage("The specified database is not associated with this server");

# Do it
$first_print = \&null_print;
$second_print = \&null_print;
if (&indexof($type, @database_plugins) >= 0) {
	&plugin_call($type, "database_delete", $d, $name);
	}
else {
	$dfunc = "delete_".$type."_database";
	&$dfunc($d, $name);
	}
&save_domain($d);
&refresh_webmin_user($d);
&run_post_actions();
print "Database $name deleted successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes a database associated with some virtual server.\n";
print "\n";
print "usage: delete-database.pl   --domain domain.name\n";
print "                            --name database-name\n";
print "                            --type [mysql|postgres]\n";
exit(1);
}

