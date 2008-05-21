#!/usr/local/bin/perl
# Moves a virtual server to a new owner

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/move-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "move-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--parent") {
		$parentdomain = lc(shift(@ARGV));
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

# Find the domains
$domain && ($parentdomain || $newuser) || usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist.");
if ($parentdomain) {
	# Get the new parent
	$parent = &get_domain_by("dom", $parentdomain);
	$parent || usage("Virtual server $parentdomain does not exist.");
	if ($d->{'parent'}) {
		$parent->{'id'} ==$d->{'parent'} && &usage($text{'move_esame'});
		}
	else {
		$parent->{'id'} == $d->{'id'} && &error($text{'move_eparent'});
		}
	}
else {
	# Validate new username
	$newd = { %$d };
	$newd->{'user'} = $newuser;
	$newd->{'group'} = $newuser;
	$derr = &virtual_server_clashes($newd, undef, 'user') ||
		&virtual_server_clashes($newd, undef, 'group');
	&usage($derr) if ($derr);
	}

# Check if this is a sub-domain
if ($d->{'subdom'}) {
	&usage("Sub-domains cannot be moved independently");
	}

# Call the move function
if ($parentdomain) {
	&$first_print(&text('move_doing', $d->{'dom'}, $parent->{'dom'}));
	$ok = &move_virtual_server($d, $parent);
	}
else {
	&$first_print(&text('move_doing2', $d->{'dom'}));
	$ok = &reparent_virtual_server($d, $newuser, $newpass);
	}
if ($ok) {
	&$second_print($text{'setup_ok'});
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'move_failed'});
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Moves a virtual server under a new parent server, or converts it.\n";
print "into a parent server of its own.\n";
print "\n";
print "usage: move-domain.pl --domain domain.name\n";
print "                      [--parent domain.name]\n";
print "                      [--newuser username]\n";
print "                      [--newpass password]\n";
exit(1);
}


