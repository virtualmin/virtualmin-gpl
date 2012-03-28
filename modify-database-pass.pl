#!/usr/local/bin/perl

=head1 modify-database-pass.pl

Changes the MySQL or PostgreSQL password for some domain.

This command changes the password that a domain's administrator uses to
login to MySQL or PostgreSQL. The domain is selected with the C<--domain>
flag, the database type with C<--type> and the new password is set with the
C<--pass> flag.

Because this operation will change the actual MySQL or PostgreSQL password,
any application or scripts in the virtual server's directory that have the
database password in their configuration files will be broken until those
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
	$0 = "$pwd/modify-database-pass.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-database-pass.pl must be run as root";
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
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
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
$pass || &usage("Missing --pass parameter");
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No domain named $dname exists");
$d->{'parent'} && &usage("The database password can only be changed for a top ".
			 "level virtual server");
$oldd = { %$d };

# Run the before command
&set_all_null_print();
&set_domain_envs($oldd, "DBPASS_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($oldd);
&usage(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Call the database change function
$sfunc = "set_${type}_pass";
&$sfunc($d, $pass);
$mfunc = "modify_${type}";
&$mfunc($d, $oldd);

# Update Webmin user, so that it logs in correctly
&modify_webmin($d, $oldd);
&run_post_actions();

# Save the domain object
&save_domain($d);

# Run the after command
&set_domain_envs($d, "DBPASS_DOMAIN", undef, $oldd);
&made_changes();
&reset_domain_envs($d);

&virtualmin_api_log(\@OLDARGV);
$ofunc = "${type}_pass";
print "Changed $type password for $d->{'dom'} to ",&$ofunc($d),"\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the MySQL or PostgreSQL password for some domain.\n";
print "\n";
local $types = join("|", @database_features);
print "virtualmin modify-database-pass --domain name\n";
print "                                --type $types\n";
print "                                --user new-name\n";
exit(1);
}
