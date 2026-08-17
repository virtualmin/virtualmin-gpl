#!/usr/local/bin/perl

=head1 fix-btrfs-homes.pl

Convert existing home directories into Btrfs subvolumes so quotas can be enforced.

Virtual servers created before Btrfs quotas were enabled have ordinary home
directories, which Btrfs qgroups cannot limit. This command converts the home
directory of each selected top-level virtual server, and every mailbox home
below it, into a subvolume and then rebuilds the quota hierarchy and limits.
It can be run either with the C<--all-domains> flag to convert all virtual
servers, or C<--domain> followed by a single domain name.

Each directory is copied into a new subvolume using reflinks and then swapped
into place, so files written to the old directory during the conversion are
lost. The affected virtual servers should therefore be idle, and a recent
backup is strongly recommended. The C<--test> flag only lists the directories
that would be converted.

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
	$0 = "$pwd/fix-btrfs-homes.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "fix-btrfs-homes.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--test") {
		$test = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains to convert specified");
&has_btrfs_quotas() ||
	&usage("Btrfs quotas have not been detected on this system");

# Get the domains
if ($all_doms) {
	@doms = grep { !$_->{'parent'} && !$_->{'alias'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'parent'} && &usage("Domain $n is not a top-level server");
		$d->{'alias'} && &usage("Domain $n is an alias server");
		push(@doms, $d);
		}
	}

# Do it for all domains
$failed = 0;
foreach $d (@doms) {
	my $err;
	my @invalid = &list_invalid_btrfs_domain_homes($d, \$err);
	if ($err) {
		&$first_print("Checking home directories for server $d->{'dom'} ..");
		&$second_print(".. failed : $err");
		$failed++;
		next;
		}
	if (!@invalid) {
		&$first_print("Server $d->{'dom'} already uses Btrfs subvolumes");
		&$second_print(".. skipped");
		next;
		}
	if ($test) {
		# Only report what would be converted
		&$first_print("Server $d->{'dom'} has ".scalar(@invalid).
			      " home directories to convert ..");
		&$indent_print();
		foreach my $home (@invalid) {
			&$first_print($home);
			&$second_print(".. not a subvolume");
			}
		&$outdent_print();
		&$second_print(".. done");
		next;
		}
	&$first_print("Converting home directories for server $d->{'dom'} ..");
	&obtain_lock_unix($d);
	&$indent_print();
	# Report each directory as it is converted so a failure is easy to place
	$err = &migrate_btrfs_domain_homes($d, sub {
		my ($home, $done) = @_;
		if ($done) {
			&$second_print(".. done");
			}
		else {
			&$first_print("Converting $home ..");
			}
		});
	&$outdent_print();
	&release_lock_unix($d);
	if ($err) {
		&$second_print(".. failed : $err");
		$failed++;
		}
	else {
		&$second_print(".. done");
		}
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
exit($failed ? 1 : 0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Convert existing home directories into Btrfs subvolumes so quotas\n";
print "can be enforced. Affected virtual servers should be idle, and a\n";
print "recent backup is strongly recommended.\n";
print "\n";
print "virtualmin fix-btrfs-homes --domain name | --all-domains\n";
print "                          [--test]\n";
exit(1);
}
