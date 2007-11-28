#!/usr/local/bin/perl
# Lists all databases in some virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/list-databases.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-databases.pl must be run as root";
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
	else {
		&usage();
		}
	}

$domain || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@dbs = &domain_databases($d);
if ($multi) {
	# Show each database on a separate line
	foreach $db (@dbs) {
		print "$db->{'name'}\n";
		print "    Type: $db->{'type'}\n";
		($size, $tables) = &get_db_size($db);
		if ($size) {
			print "    Size: ",&nice_size($size),"\n";
			}
		print "    Tables: $tables\n";
		}
	}
else {
	# Show all on one line
	$fmt = "%-30.30s %-20.20s %-15.15s %-10.10s\n";
	printf $fmt, "Database", "Type", "Size", "Tables";
	printf $fmt, ("-" x 30), ("-" x 20), ("-" x 15), ("-" x 10);
	foreach $db (@dbs) {
		($size, $tables) = &get_db_size($db);
		printf $fmt, $db->{'name'}, $db->{'type'},
			     $size ? &nice_size($size) : "Unknown", $tables;
		}
	}

# get_db_size(&db)
sub get_db_size
{
local ($db) = @_;
if (&indexof($db->{'type'}, @database_plugins) >= 0) {
	return &plugin_call($db->{'type'}, "database_size", $d, $db->{'name'});
	}
else {
	$szfunc = $db->{'type'}."_size";
	($size, $tables) = &$szfunc($d, $db->{'name'});
	}
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the databases associated with some virtual server.\n";
print "\n";
print "usage: list-databases.pl   --domain domain.name\n";
print "                           [--multiline]\n";
exit(1);
}

