#!/usr/local/bin/perl

=head1 rename-domain.pl

Change the domain name, home directory or username of a virtual server.

This command is typically used to rename an existing server, selected with the
C<--domain> flag, and changed to the name set with the C<--new-domain> option.

By default, the administration username, home directory and prefix for mailboxes
will remaining unchanged. You can have these selected automatically based on
the new domain name with the C<--auto-user>, C<--auto-home> and C<--auto-prefix>
flags. Alternately, you can set them directly with the C<--new-user>, 
C<--new-home> and C<--new-prefix> flags followed by the settings you want.

This command can also be used to change the home directory or username for
a domain without even changing the domain name, just set the C<--new-home>
or C<--new-user> flags without C<--new-domain>.

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
	$0 = "$pwd/rename-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "rename-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--new-domain") {
		$newdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--new-user") {
		# Selecting a Unix login is only offered to those who can
		# rename and choose a username
		&can_rename_domains() == 2 ||
			&usage("--new-user is only available to the master ".
			       "administrator");
		$newuser = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-user") {
		&can_rename_domains() == 2 ||
			&usage("--auto-user is only available to the master ".
			       "administrator");
		$newuser = "auto";
		}
	elsif ($a eq "--new-home") {
		# An arbitrary home directory can only be set by the master
		&can_rehome_domains() == 2 ||
			&usage("--new-home is only available to the master ".
			       "administrator");
		$newhome = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-home") {
		&can_rehome_domains() ||
			&usage("You are not allowed to change the home ".
			       "directory");
		$newhome = "auto";
		}
	elsif ($a eq "--new-prefix") {
		$newprefix = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-prefix") {
		$newprefix = "auto";
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain and validate inputss
$domain || usage("No domain specified");
$d = &get_remote_api_domain("dom", $domain);
$d || usage("Virtual server $domain does not exist.");
$newdomain || $newuser || $newhome || $newprefix ||
	&usage("No changes specified");

# Do the rename
$err = &rename_virtual_server($d, $newdomain, $newuser, $newhome, $newprefix);
&usage($err) if ($err);

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Change the domain name, home directory or username of a ";
print "virtual server.\n";
print "\n";
print "virtualmin rename-domain --domain domain.name\n";
print "                        [--new-domain name]\n";
print "                        [--new-user login | --auto-user]\n";
print "                        [--new-home directory | --auto-home]\n";
print "                        [--new-prefix string | --auto-prefix]\n";
exit(1);
}


