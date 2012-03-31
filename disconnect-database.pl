#!/usr/local/bin/perl

=head1 disconnect-database.pl

Removes a database from the control of a virtual server.

This command removes access to a database from the virtual server that
owns it, but does not actually delete the database itself. You must provide
the C<--domain> flag followed by a virtual server name, C<--type> followed by
the DB type (like mysql or postgres), and C<--name> followed by the database
name.

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
	$0 = "$pwd/disconnect-database.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-database.pl must be run as root";
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
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$name || &usage("No database name specified");
$type || &usage("No database type specified");
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
if (&indexof($type, &list_database_plugins()) >= 0) {
	&plugin_call($type, "database_revoke", $d, $name);
	}
else {
	$dfunc = "revoke_".$type."_database";
	&$dfunc($d, $name);
	}

# Save domain object
@dbs = split(/\s+/, $d->{'db_'.$type});
@dbs = grep { $_ ne $name } @dbs;
$d->{'db_'.$type} = join(" ", @dbs);
&save_domain($d);
&refresh_webmin_user($d);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);
print "Database $name disconnected successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes a database from the control of a virtual server.\n";
print "\n";
print "virtualmin disconnect-database --domain domain.name\n";
print "                               --name database-name\n";
print "                               --type mysql|postgres\n";
exit(1);
}

