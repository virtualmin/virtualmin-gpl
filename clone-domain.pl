#!/usr/local/bin/perl

=head1 clone-domain.pl

Duplicates an existing virtual server with a new name.

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
	$newuser || &usage("The --newuser flag is required when cloning ".
			   "a top-level virtual server");
	}
else {
	$newuser && &usage("The --newuser flag makes no sense when cloning ".
			   "a sub-server");
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
			    $oldd->{'dom'}, $newdomain));
	}
else {
	&$first_print(&text('clone_doing2',
			    $oldd->{'dom'}, $newdomain, $newuser));
	}
$ok = &clone_virtual_server($d, $newdomain, $newuser, $newpass);
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
exit(1);
}


