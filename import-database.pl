#!/usr/local/bin/perl

=head1 import-database.pl

Adds an existing database to a virtual server

This command finds a MySQL or PostgreSQL database that is not currently
owned by any virtual server and associates it with the server specified with
the C<--domain> parameter.

The database to import is set with the C<--type> flag followed by either
C<mysql> or C<postgres> , and the C<--name> flag followed by a database name.
You cannot import a DB that is owned by another domain, or has a special purpose
like the C<mysql> or C<template0> databases.

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
	$0 = "$pwd/import-database.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "import-database.pl must be run as root";
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
		$name =~ /^[a-z0-9\_]+$/i && $name =~ /^[a-z]/i ||
			&usage("Invalid database name");
		}
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

$domain && $name && $type || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@dbs = &domain_databases($d);
$d->{$type} || &usage("The specified database type is not enabled in this virtual server");

# Find the database, and validate that it can be imported
@all = &all_databases($d);
($db) = grep { $_->{'type'} eq $type &&
	       $_->{'name'} eq $name } @all;
$db || &usage("No $type database named $name exists");
$db->{'special'} && &usage("The $type database named $name is special and cannot be imported");
foreach $dd (&list_domains()) {
	foreach $dddb (&domain_databases($dd)) {
		if ($dddb->{'name'} eq $name && $dddb->{'type'} eq $type) {
			&usage("The $type database named $name is already owned by virtual server $dd->{'dom'}");
			}
		}
	}

# Add to DB list
@dbs = split(/\s+/, $d->{'db_'.$type});
push(@dbs, $name);
$d->{'db_'.$type} = join(" ", @dbs);

# Grant access
$gfunc = "grant_".$type."_database";
if (defined(&$gfunc)) {
	&$gfunc($d, $name);
	}

&save_domain($d);
&set_all_null_print();
&refresh_webmin_user($d);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);
print "Database $name imported successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Associates an existing database with some virtual server.\n";
print "\n";
print "virtualmin import-database --domain domain.name\n";
print "                           --name database-name\n";
print "                           --type mysql|postgres\n";
exit(1);
}

