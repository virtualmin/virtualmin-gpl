#!/usr/local/bin/perl

=head1 list-backup-logs.pl

Outputs a list of backups that have been run.

This command by default outputs logs of all backups made using Virtualmin,
in a simple table format. To switch to a more detailed and parseable output
format, add the C<--multiline> flag to the command line.

To limit the display to backups that contain a specific domain, use the
C<--domain> flag followed by a virtual server name.

To limit to backups made by a particular Virtualmin user, use the C<--user>
flag followed by a username.

To only show backups made via the web UI, use the C<--mode cgi> flag. To show
scheduled backups, use C<--mode sched>. Or to show backups made from the command
line or remote API, use C<--mode api>.

To only show backups that failed, add the C<--failed> flag to the command line.
Or to show backups that worked, use C<--succeeded>. By default both are shown.

To limit the display to backups within some time range, use the C<--start>
flag followed by a date in yyyy-mm-dd format to only show backups that started
on or after this date. Or use C<--end> to only show backups that started before
the following date.

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
	$0 = "$pwd/list-backup-logs.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-backup-logs.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--mode") {
		$mode = shift(@ARGV);
		}
	elsif ($a eq "--failed") {
		$failed = 1;
		}
	elsif ($a eq "--succeeded") {
		$succeeded = 1;
		}
	elsif ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--start") {
		$start = &date_to_time(shift(@ARGV));
		}
	elsif ($a eq "--end") {
		$end = &date_to_time(shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$failed && $succeeded &&
	&usage("The --failed and --succeeded flags are mutually exclusive");

# Get all the backup logs, then filter down
@alllogs = &list_backup_logs($start);
@logs = ( );
foreach $l (@alllogs) {
	if ($domain) {
		# Filter by domain
		@ldoms = split(/\s+/, $l->{'doms'});
		next if (&indexof($domain, @ldoms) < 0);
		}
	if ($user) {
		# Filter by user who did it
		next if ($l->{'user'} ne $user);
		}
	if ($mode) {
		# Filter by how it was run
		next if ($l->{'mode'} ne $mode);
		}
	if ($dest) {
		# Filter by dest directory
		next if ($l->{'dest'} !~ /\Q$dest\E/);
		}
	# Filter by start time
	if ($start) {
		next if ($l->{'start'} < $start);
		}
	if ($end) {
		next if ($l->{'start'} > $end);
		}
	# Filter by success
	if ($failed) {
		next if ($l->{'ok'});
		}
	elsif ($succeeded) {
		next if (!$l->{'ok'});
		}
	push(@logs, $l);
	}

if ($multi) {
	# Show all details
	%schedmap = map { $_->{'id'}, $_ } &list_scheduled_backups();
	foreach my $l (@logs) {
		print "$l->{'id'}:\n";
		print "    Domains: $l->{'doms'}\n";
		if ($l->{'errdoms'}) {
			print "    Failed domains: $l->{'errdoms'}\n";
			}
		print "    Destination: $l->{'dest'}\n";
		print "    Incremental: ",
		      ($l->{'increment'} == 1 ? "Yes" :
		       $l->{'increment'} == 2 ? "Disabled" : "No"),"\n";
		print "    Started: ",&make_date($l->{'start'}),"\n";
		print "    Ended: ",&make_date($l->{'end'}),"\n";
		if ($l->{'size'}) {
			print "    Final size: $l->{'size'}\n";
			print "    Final nice size: ",
			      &nice_size($l->{'size'}),"\n";
			}
		print "    Final status: ",($l->{'ok'} ? "OK" : "Failed"),"\n";
		if ($l->{'user'}) {
			print "    Run by user: $l->{'user'}\n";
			}
		print "    Run from: $l->{'mode'}\n";
		if ($l->{'sched'}) {
			$sched = $schedmap{$l->{'sched'}};
			if ($sched) {
				print "    Scheduled backup ID: ",
				      $sched->{'id'},"\n";
				@dests = get_scheduled_backup_dests($sched);
				for(my $i=0; $i<@dests; $i++) {
					print "    Scheduled destination: ",
					      "$dests[$i]\n";
					}
				}
			else {
				print "    Scheduled backup ID: DELETED\n";
				}
			}
		if ($l->{'key'}) {
			print "    Encrypted: Yes\n";
			print "    Encryption key ID: $l->{'key'}\n";
			if (!defined(&get_backup_key)) {
				$key = undef;
				print "    Encryption key state: ",
				      "Not supported","\n";
				}
			else {
				$key = &get_backup_key($l->{'key'});
				print "    Encryption key state: ",
				      ($key ? "Available" : "Missing"),"\n";
				}
			if ($key) {
				print "    Encryption key description: ",
				      $key->{'desc'},"\n";
				}
			}
		else {
			print "    Encrypted: No\n";
			}
		}
	}
else {
	# Just show one per line
	$fmt = "%-20.20s %-40.40s %-6.6s %-10.10s\n";
	printf $fmt, "Domains", "Destination", "Status", "Size";
	printf $fmt, ("-" x 20), ("-" x 40), ("-" x 6), ("-"  x 10);
	foreach my $l (@logs) {
		printf $fmt, $l->{'doms'},
			     &html_tags_to_text(
				&nice_backup_url($l->{'dest'}, 1)),
			     $l->{'ok'} ? 'OK' : 'Failed',
			     &nice_size($l->{'size'});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Outputs a list of backups that have been run.\n";
print "\n";
print "virtualmin list-backup-logs [--domain domain.name |\n";
print "                            [--user name]\n";
print "                            [--failed | --succeeded]\n";
print "                            [--mode \"cgi\"|\"sched\"|\"api\"]\n";
print "                            [--start yyyy-mm-dd]\n";
print "                            [--end yyyy-mm-dd]\n";
print "                            [--multiline]\n";
exit(1);
}
