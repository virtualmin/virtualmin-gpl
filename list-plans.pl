#!/usr/local/bin/perl

=head1 list-plans.pl

List available account plans for new domains

The command simply outputs a list of available plans for use when
creating new virtual servers, or for applying to existing servers.

To just display the plan names, you can give the C<--name-only> parameter.
Or to show full details about each plan in a more machine-readable format,
use the C<--multiline> option.

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
	$0 = "$pwd/list-plans.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-plans.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--id-only") {
		$idonly = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--id") {
		$planid = shift(@ARGV);
		}
	elsif ($a eq "--name") {
		$planname = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the plans to list
if (defined($planid)) {
	$plan = &get_plan($planid);
	$plan || &usage("No plan with ID $planid was found");
	@plans = ( $plan );
	}
elsif (defined($planname)) {
	@plans = grep { $_->{'name'} eq $planname } &list_plans();
	@plans || &usage("No plan with name $planname was found");
	}
else {
	@plans = &list_plans();
	}

$bsize = &quota_bsize("home");
if ($nameonly) {
	# Just plan names
	foreach $plan (@plans) {
		print $plan->{'name'},"\n";
		}
	}
elsif ($idonly) {
	# Just plan IDs
	foreach $plan (@plans) {
		print $plan->{'id'},"\n";
		}
	}
elsif ($multiline) {
	# Full details
	foreach $plan (@plans) {
		print $plan->{'id'},"\n";
		print "    Name: $plan->{'name'}\n";
		print "    Owner: $plan->{'owner'}\n" if ($plan->{'owner'});

		# Quota limits
		print "    Server block quota: ",
			($plan->{'quota'} || "Unlimited"),"\n";
		if ($bsize && $plan->{'quota'}) {
			print "    Server quota: ",
				&nice_size($plan->{'quota'}*$bsize),"\n";
			}
		print "    Administrator block quota: ",
			($plan->{'uquota'} || "Unlimited"),"\n";
		if ($bsize && $plan->{'uquota'}) {
			print "    Administrator quota: ",
				&nice_size($plan->{'uquota'}*$bsize),"\n";
			}

		# Count limits
		foreach $l (@plan_maxes) {
			print "    Maximum ${l}: ",
				($plan->{$l.'limit'} eq '' ? 'Unlimited' :
				  $plan->{$l.'limit'}),"\n";
			}

		# Other limits
		print "    Can choose database names: ",
			$plan->{'nodbname'} ? "No" : "Yes","\n";
		print "    Can rename domains: ",
			$plan->{'norename'} ? "No" : "Yes","\n";
		print "    Can migrate backups: ",
			$plan->{'migrate'} ? "Yes" : "No","\n";
		print "    Can create sub-servers under any domain: ",
			$plan->{'forceunder'} ? "No" : "Yes","\n";
		print "    Can create sub-servers under other domains: ",
			($plan->{'safeunder'} ? "Yes" : "No"),"\n";

		# Allowed features
		print "    Allowed features: ",
			($plan->{'featurelimits'} || "Automatic"),"\n";
		print "    Edit capabilities: ",
			($plan->{'capabilities'} || "Automatic"),"\n";

		# Allowed scripts
		print "    Allowed scripts: ",
			($plan->{'scripts'} || "All"),"\n";

		# Available to resellers
		print "    Resellers: ",
			($plan->{'resellers'} eq 'none' ? "None" :
			 $plan->{'resellers'} || "All"),"\n";
		}
	}
else {
	# Basic details
	$fmt = "%-18.18s %-40.40s %-10.10s %-8.8s\n";
	printf $fmt, "ID", "Name", "Quota", "Domains";
	printf $fmt, ("-" x 18), ("-" x 40), ("-" x 10), ("-" x 8);
	foreach $plan (@plans) {
		printf $fmt, $plan->{'id'}, $plan->{'name'},
		     $plan->{'quota'} ? &nice_size($plan->{'quota'}*$bsize)
				      : "Unlimited",
		     $plan->{'domslimit'} ne '' ? $plan->{'domslimit'}
						: "Unlimited";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available account plans for virtual servers.\n";
print "\n";
print "virtualmin list-plans [--name-only | --multiline]\n";
print "                      [--id number | --name \"plan name\"]\n";
exit(1);
}

