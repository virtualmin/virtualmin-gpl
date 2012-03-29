#!/usr/local/bin/perl

=head1 clone-domain.pl

Duplicates an existing virtual server with a new name.

This command will duplicate an existing virtual server with a new
domain name. Any web content, DNS records, mailboxes, mail aliases, databases
and other settings associated with the original domain will be duplicated,
where possible.

The virtual server to clone is selected with the C<--domain> flag, and the
new name is set with the C<--newdomain> parameter. When cloning a top-level
server the C<--newuser> and C<--newpass> flags can be used to set the login
and password of the new user that will be created as part of the cloning
process.

If the cloned virtual server has a private IP address, Virtualmin will allocate
a new IP for the clone from the configured IP allocation range. If no ranges
are defined or you want to use a specific address, the C<--ip> flag can
be given instead, followed by the address for the new domain to use.

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
	$0 = "$pwd/clone-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "clone-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--newdomain") {
		$newdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--newuser") {
		$newuser = shift(@ARGV);
		}
	elsif ($a eq "--newpass") {
		$newpass = shift(@ARGV);
		}
	elsif ($a eq "--ip") {
		$ip = shift(@ARGV);
		&check_ipaddress($ip) || &usage("Invalid IP address");
		}
	elsif ($a eq "--ip-already") {
		$virtalready = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Find the domain
$domain || usage("Missing --domain flag");
$newdomain || usage("Missing --newdomain flag");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist.");
if (!$d->{'parent'}) {
	if (!$newuser) {
		($newuser, $try1, $try2) = &unixuser_name($newdomain);
		$newuser || &usage("No free new username could be found - use ".
				   "the --newuser flag to specify one");
		}
	}
else {
	$newuser && &usage("The --newuser flag makes no sense when cloning ".
			   "a sub-server");
	}

# Validate the given IP
if ($ip) {
	$d->{'virt'} || &usage("The --ip flag can only be used when cloning ".
			       "a server with a private IP address");
	$clash = &check_virt_clash($ip);
	if ($virtalready) {
		$clash || &usage("The given IP address is not active on ".
				 "this system");
		$already = &get_domain_by("ip", $ip);
		$already && &usage("The given IP address is in use by ".
				   $already->{'dom'});
		}
	else {
		$clash && &usage("The given IP address is already in use");
		}
	}

# Check for clash with new name
$clash = &get_domain_by("dom", $newdomain);
$clash && &usage("A virtual server named $newdomain already exists");
if (!$d->{'parent'}) {
	$clash = &get_domain_by("user", $newuser);
	$clash && &usage("A virtual server with the username $newuser ".
			 "already exists");
	}

# Call the clone function
if ($d->{'parent'}) {
	&$first_print(&text('clone_doing',
			    $d->{'dom'}, $newdomain));
	}
else {
	&$first_print(&text('clone_doing2',
			    $d->{'dom'}, $newdomain, $newuser));
	}
$ok = &clone_virtual_server($d, $newdomain, $newuser, $newpass,
			    $ip, $virtalready);
&run_post_actions_silently();
if ($ok) {
	&$second_print($text{'setup_done'});
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'clone_failed'});
	exit(1);
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Duplicates an existing virtual server with a new name.\n";
print "\n";
print "virtualmin clone-domain --domain domain.name\n";
print "                        --newdomain new.name\n";
print "                       [--newuser name]\n";
print "                       [--newpass password]\n";
print "                       [--ip address [--ip-already]]\n";
exit(1);
}


