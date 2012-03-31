#!/usr/local/bin/perl

=head1 move-domain.pl

Change the owner of a virtual server

This command can be used to move a sub-server from one parent domain to
another, thus changing the administrator who is responsible for it. It can
also be used to convert a parent server into a sub-server under some existing
owner.

In this mode, it takes only two parameters : C<--domain> followed by the domain name
to move, and C<--parent> followed by the domain name of the new parent server.
Naturally the new parent must be different from the old one, and a server
cannot be moved under itself.

This command should be used with care when moving a parent server, as
information that is specific to it such as the password, quotas and bandwidth
limit will be lost. Instead, the settings from the new parent will apply.

The C<move-domain> command can also be used to convert a sub-server into
a top-level server. In this case, you must give the C<--newuser> and
C<--newpass> parameters, which are followed by the username and password for
the new top-level server respectively. The original owner of the domain will
no longer have access to it once the command completes.

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
	$0 = "$pwd/move-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "move-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domains
$domain || &usage("No domain to move specified");
$parentdomain || $newuser ||
	&usage("No destination domain or new username specified");
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
	$newd->{'unix'} = 1;
	$newd->{'webmin'} = 1;
	$newd->{'user'} = $newuser;
	$newd->{'group'} = $newuser;
	$derr = &virtual_server_clashes($newd, undef, 'user') ||
		&virtual_server_clashes($newd, undef, 'group');
	&usage($derr) if ($derr);

	# Check if the domain already has a user with that name
	@dusers = &list_domain_users($d, 0, 1, 1, 1);
	($clash) = grep { $_->{'user'} eq $newuser ||
		  &remove_userdom($_->{'user'}, $d) eq $newuser } @dusers;
	$clash && &usage("A user named $newuser already exists in $d->{'dom'}");

	# Check if a user with that name exists anywhere
	defined(getpwnam($newuser)) &&
		&usage("A user named $newuser already exists");
	}

# Check if this is a sub-domain
if ($d->{'subdom'}) {
	&usage("Sub-domains cannot be moved independently - use unsub-domain.pl first");
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
&run_post_actions_silently();
if ($ok) {
	&$second_print($text{'setup_done'});
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
print "virtualmin move-domain --domain domain.name\n";
print "                      [--parent domain.name]\n";
print "                      [--newuser username]\n";
print "                      [--newpass password]\n";
exit(1);
}


