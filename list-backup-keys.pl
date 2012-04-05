#!/usr/local/bin/perl

=head1 list-backup-keys.pl

Lists all available backup encryption keys.

When run with no flags, this command outputs a table of backup keys for
use by scheduled and manula backups.  To get a more parsable format with full
details for each shell, use the C<--multiline> parameter. Or to only output
key IDs, use the C<--id-only> flag.

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
	$0 = "$pwd/list-backup-keys.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-backup-keys.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--id-only") {
		$idonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

@keys = &list_backup_keys();
if ($multi) {
	# Show full details
	foreach $key (@keys) {
		print $key->{'id'},"\n";
		print "    Description: ",$key->{'desc'},"\n";
		if ($key->{'owner'}) {
			print "    Owner: ",$key->{'owner'},"\n";
			}
		print "    Created: ",&make_date($key->{'created'}),"\n";
		}
	}
elsif ($idonly) {
	# Just IDs
	foreach $key (@keys) {
		print $key->{'id'},"\n";
		}
	}
else {
	# One per line
	$fmt = "%-20.20s %-40.40s %-17.17s\n";
	printf $fmt, "Key ID", "Description", "Owner";
	printf $fmt, ("-" x 20), ("-" x 40), ("-" x 17);
	foreach $key (@keys) {
		printf $fmt, $key->{'id'},
			     $key->{'desc'},
			     $key->{'owner'} || "root";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all available backup encryption keys.\n";
print "\n";
print "virtualmin list-backup-keys [--multiline]\n";
print "                            [--id-only]\n";
exit(1);
}

