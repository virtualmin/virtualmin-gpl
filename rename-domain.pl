#!/usr/local/bin/perl

=head1 rename-domain.pl

Change the domain name, home directory or username of a virtual server.

This command is typically used to rename an existing server, selected with the
C<--domain> flag, and changed to the name set with the C<--new-domain> option.

XXX

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
	$0 = "$pwd/modify-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--new-domain") {
		$newdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--new-user") {
		$newuser = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-user") {
		$newuser = "auto";
		}
	elsif ($a eq "--new-home") {
		$newhome = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-home") {
		$newhome = "auto";
		}
	elsif ($a eq "--new-prefix") {
		$newprefix = lc(shift(@ARGV));
		}
	elsif ($a eq "--auto-prefix") {
		$newprefix = "auto";
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain
$domain || usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist.");

# Validate other inputs
$newdomain || $newuser || $newhome || $newprefix ||
	&usage("No changes specified");
# XXX

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


