#!/usr/local/bin/perl

=head1 create-login-link.pl

Generates a link that can be used to login to Virtualmin.

This command can be used to login to Virtualmin as a domain owner without
needing to enter a password. When a server is selected with either the 
C<--domain> or C<--user> flag, a URL will be displayed that when opened in
a browser will immediately login as the owner of that server.

Alternately, you can use the C<--usermin-user> flag to login to Usermin
as a mailbox user. This must be followed by the full Unix username of the 
mailbox.

If you want to login as root, use C<--root> flag only.

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
	$0 = "$pwd/create-login-link.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-login-link.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$uname = shift(@ARGV);
		}
	elsif ($a eq "--usermin-user") {
		$uname = shift(@ARGV);
		$usermin = 1;
		}
	elsif ($a eq "--root") {
		$root = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs
if ($root) {
	$uname = "root";
	$usermin = 0;
	}
elsif ($dname) {
	$d = &get_domain_by("dom", $dname);
	$d || &usage("No virtual server named $dname found");
	}
elsif ($uname) {
	if ($usermin) {
		getpwnam($uname) || &usage("Unix user $uname does not exist");
		$d = &get_user_domain($uname);
		}
	else {
		$d = &get_domain_by("user", $uname, "parent", "");
		$d || &usage("No virtual server owned by $uname found");
		}
	}
else {
	&usage("One of --domain or --user must be provided");
	}
if ($d) {
	$d->{'webmin'} ||
		&usage("Virtual server $d->{'dom'} has no Webmin login");
	$uname = $d->{'user'};
	}

# Create the session in the appropriate program
&foreign_require("acl");
defined(&acl::create_session_user) ||
	&usage("Your Webmin version does not support switching sessions");
if ($usermin) {
	# Add a Usermin session
	&foreign_require("usermin");
	my %miniserv;
	&usermin::get_usermin_miniserv_config(\%miniserv);
	my $sid = &acl::create_session_user(\%miniserv, $uname);
	$sid || &usage("Failed to create login session");
	&usermin::restart_usermin_miniserv();
	my $dom = $d ? $d->{'dom'} : undef;
	$url = &usermin::get_usermin_email_url(undef, undef, undef, $dom).
	       "/session_login.cgi?session=".&urlize($sid);
	print $url."\n";
	}
else {
	# Add a Webmin session
	&foreign_require("webmin");
	my %miniserv;
	&get_miniserv_config(\%miniserv);
	($uinfo) = grep { $_->{'name'} eq $uname } &acl::list_users();
	$uinfo || &usage("Webmin user $uname does not exist");
	my $sid = &acl::create_session_user(\%miniserv, $uname);
	$sid || &usage("Failed to create login session");
	&reload_miniserv();
	$url = &get_virtualmin_url($d)."/session_login.cgi?session=".&urlize($sid);
	print $url."\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Generates a link that can be used to login to Virtualmin.\n";
print "\n";
print "virtualmin create-login-link [--domain name | --user name |\n";
print "                              --usermin-user name | --root]\n";
exit(1);
}

