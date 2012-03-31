#!/usr/local/bin/perl

=head1 list-available-shells.pl

List all shells for use with domain owners and mailboxes

When run with no flags, this command outputs a table of shells for use
by domain owners and mailbox users. To limit it to just domain owners,
the C<--owner> flag can be given. Or to show only shells designated for use
by mailboxes, add C<--mailbox> to the command line.

To get a more parsable format with full details for each shell, use the
C<--multiline> parameter. Or to only output shell paths, use C<--name-only>.

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
	$0 = "$pwd/list-available-shells.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-available-shells.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--owner") {
		$type = "owner";
		}
	elsif ($a eq "--mailbox") {
		$type = "mailbox";
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the shells
@shells = &list_available_shells();
if ($type) {
	@shells = grep { $_->{$type} } @shells;
	}

if ($multi) {
	# Show full details
	foreach $shell (@shells) {
		print $shell->{'shell'},"\n";
		print "    Description: ",$shell->{'desc'},"\n";
		print "    Login type: ",$shell->{'id'},"\n";
		print "    For mailboxes: ",
			($shell->{'mailbox'} ? "Yes" : "No"),"\n";
		print "    For administrators: ",
			($shell->{'owner'} ? "Yes" : "No"),"\n";
		print "    Available: ",
			($shell->{'avail'} ? "Yes" : "No"),"\n";
		print "    Default: ",
			($shell->{'default'} ? "Yes" : "No"),"\n";
		}
	}
elsif ($nameonly) {
	# Just shell commands
	foreach $shell (@shells) {
		print $shell->{'shell'},"\n";
		}
	}
else {
	# One per line
	$fmt = "%-20.20s %-40.40s %-5.5s %-10.10s\n";
	printf $fmt, "Shell path", "Description", "Avail", "For use by";
	printf $fmt, ("-" x 20), ("-" x 40), ("-" x 5), ("-" x 10);
	foreach $shell (@shells) {
		printf $fmt, $shell->{'shell'},
			     $shell->{'desc'},
			     $shell->{'avail'} ? "Yes" : "No",
			     $shell->{'mailbox'} && $shell->{'owner'} ? "Both" :
			     $shell->{'mailbox'} ? "Mailboxes" :
			     $shell->{'owner'} ? "Admins" : "Nobody";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the shells available for mailboxes and domain administrators.\n";
print "\n";
print "virtualmin list-available-shells [--multiline]\n";
print "                                 [--owner | --mailbox]\n";
exit(1);
}

