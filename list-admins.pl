#!/usr/local/bin/perl

=head1 list-admins.pl

Lists administrators belonging to a virtual server

This program simply displays a list of extra administrators associated with
one virtual server. You must supply the C<--domain> followed by the domain name of the server to list. By default the output is in a reader-friendly table, but the C<--multiline> option can be used to switch to a format more suitable for reading by programs.

To get a list of just the extra admin's usernames (for use in a script perhaps),
add the C<--name-only> command line flag.

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
	$0 = "$pwd/list-databases.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-admins.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@admins = &list_extra_admins($d);
if ($multi) {
	# Show each admin on a separate line
	foreach $admin (@admins) {
		print "$admin->{'name'}\n";
		print "    Description: $admin->{'desc'}\n";
		if ($admin->{'email'}) {
			print "    Email: $admin->{'email'}\n";
			}
		print "    Password: $admin->{'pass'}\n";
		print "    Create servers: ",($admin->{'create'} ? "Yes" : "No"),"\n";
		print "    Rename servers: ",($admin->{'norename'} ? "No" : "Yes"),"\n";
		print "    Configure features: ",($admin->{'features'} ? "Yes" : "No"),"\n";
		print "    Access Webmin modules: ",($admin->{'modules'} ? "Yes" : "No"),"\n";
		$caps = join(" ", grep { $admin->{'edit_'.$_} } @edit_limits);
		print "    Edit capabilities: ",$caps,"\n";
		if ($admin->{'doms'}) {
			@doms = grep { $_ } map { &get_domain($_) }
					split(/\s+/, $admin->{'doms'});
			print "    Allowed virtual servers: ",
				join(" ", map { $_->{'dom'} } @doms),"\n";
			}
		}
	}
elsif ($nameonly) {
	# Just show names
	foreach $admin (@admins) {
		print $admin->{'name'},"\n";
		}
	}
else {
	# Show all on one line
	$fmt = "%-15.15s %-25.25s %-38.38s\n";
	printf $fmt, "Login", "Description", "Capabilities";
	printf $fmt, ("-" x 15), ("-" x 25), ("-" x 38);
	foreach $admin (@admins) {
		$caps = join(" ", grep { $admin->{'edit_'.$_} } @edit_limits);
		printf $fmt, $admin->{'name'}, $admin->{'desc'}, $caps;
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the extra administrators associated with some virtual server.\n";
print "\n";
print "virtualmin list-admins --domain domain.name\n";
print "                      [--multiline]\n";
exit(1);
}

