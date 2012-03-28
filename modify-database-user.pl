#!/usr/local/bin/perl

=head1 modify-database-user.pl

Changes the MySQL or PostgreSQL login for some domain.

This command changes the username that a domain's administrator uses to
login to MySQL or PostgreSQL. The domain is selected with the C<--domain>
flag, the database type with C<--type> and the new login is set with the
C<--user> flag.

Because this operation will rename the actual MySQL or PostgreSQL user,
any application or scripts in the virtual server's directory that have the
database login in their configuration files will be broken until those
configurations are updated with the new username.

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
	$0 = "$pwd/modify-database-user.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-database-user.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Validate inputs
$type || &usage("Missing --type parameter");
&indexof($type, @database_features) >= 0 ||
	&usage("$type is not valid database type - options are : ".
	       join(" ", @database_features));
defined($user) || &usage("Missing --user parameter");
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No domain named $dname exists");
$d->{'parent'} && &usage("The database username can only be changed for a top ".
			 "level virtual server");
$user =~ /^[a-z0-9\.\-\_]+$/ || &usage("Invalid new username");
$oldd = { %$d };

# Check for name clash
$sfunc = "set_${type}_user";
&$sfunc($d, $user);
$cfunc = "check_${type}_clash";
&$cfunc($d, 'user') && &usage("The database username $user is already in use");

# Run the before command
&set_all_null_print();
&set_domain_envs($oldd, "DBNAME_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($oldd);
&usage(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Call the database change function
$mfunc = "modify_${type}";
&$mfunc($d, $oldd);

# Update Webmin user, so that it logs in correctly
&modify_webmin($d, $oldd);
&run_post_actions();

# Save the domain object
&save_domain($d);

# Run the after command
&set_domain_envs($d, "DBNAME_DOMAIN", undef, $oldd);
&made_changes();
&reset_domain_envs($d);

&virtualmin_api_log(\@OLDARGV);
$ofunc = "${type}_user";
print "Changed $type login for $d->{'dom'} to ",&$ofunc($d),"\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the MySQL or PostgreSQL login for some domain.\n";
print "\n";
local $types = join("|", @database_features);
print "virtualmin modify-database-user --domain name\n";
print "                                --type $types\n";
print "                                --user new-name\n";
exit(1);
}
