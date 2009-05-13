#!/usr/local/bin/perl

=head1 create-database.pl

Creates a database for a virtual server

This command creates a new MySQL or PostgreSQL database, and associates it
with an existing virtual server. You must supply the C<--domain> parameter to
specify the server, C<--name> to set the database name, and C<--type> followed by
either C<mysql>, C<postgres> or some plugin database type. It would typically be run
something like :

  create-database.pl --domain foo.com --name foo_phpbb --type mysql

Some database types support additional creation-time options, specified using the C<--opt> flag. At the time of writing, those available for MySQL are :

C<--opt charset name> - Sets the character set (like latin2 or euc-jp) for the new database.

And for PostgreSQL, the options are :

C<--opt encoding name> - Sets the text encoding (like LATIN2 or EUC_JP) for the new database.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/create-database.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-database.pl must be run as root";
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
	elsif ($a eq "--opt") {
		local $oname = shift(@ARGV);
		local $ovalue = shift(@ARGV);
		$oname && $ovalue ne '' ||
		  &usage("--opt must be followed by an option name and value");
		$opts{$oname} = $ovalue;
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

# Prepend suffix (if missing)
$tmpl = &get_template($d->{'template'});
if ($tmpl->{'mysql_suffix'} ne "none") {
	$suffix = &substitute_domain_template($tmpl->{'mysql_suffix'}, $d);
	if ($name !~ /^$suffix/) {
		$name = $suffix.$name;
		}
	}

# Check for clash in the virtual server
($clash) = grep { $_->{'name'} eq $name &&
		  $_->{'type'} eq $type } @dbs;
$clash && &usage("A database with the same name and type is already associated with this server");

# Check for a global clash
if (&indexof($type, &list_database_plugins()) >= 0) {
	&plugin_call($type, "database_clash", $d, $name) &&
		&usage("A database called $name already exists");
	}
else {
	$cfunc = "check_".$type."_database_clash";
	&$cfunc($d, $name) && &usage("A database called $name already exists");
	}

# Do it
$first_print = \&null_print;
$second_print = \&null_print;
if (&indexof($type, &list_database_plugins()) >= 0) {
	&plugin_call($type, "database_create", $d, $name, \%opts);
	}
else {
	$crfunc = "create_".$type."_database";
	&$crfunc($d, $name, \%opts);
	}
&save_domain($d);
&refresh_webmin_user($d);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);
print "Database $name created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Creates a new database associated with some virtual server.\n";
print "\n";
print "virtualmin create-database --domain domain.name\n";
print "                           --name database-name\n";
print "                           --type [mysql|postgres]\n";
print "                           [--opt name value]*\n";
exit(1);
}

