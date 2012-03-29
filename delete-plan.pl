#!/usr/local/bin/perl

=head1 delete-plan.pl

Removes one existing account plan.

The plan to delete is specified either by ID with the C<--id> parameter followed
by a numeric ID, or by name with the C<--name> flag.

Deletion of plans in use by one or more virtual servers is safe, as in this case
Virtualmin will merely flag it as deleted and hide it from the plans list.

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
	$0 = "$pwd/delete-plan.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-plan.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
$plan = { };
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name") {
		$planname = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$planid = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the plan
if (defined($planid)) {
	$plan = &get_plan($planid);
	$plan || &usage("No plan with ID $planid was found");
	}
elsif (defined($planname)) {
	($plan) = grep { $_->{'name'} eq $planname } &list_plans();
	$plan || &usage("No plan with name $planname was found");
	}
else {
	&usage("Either the --id or --name parameter must be given");
	}

# Delete it
&delete_plan($plan);
print "Deleted plan $plan->{'name'} with ID $plan->{'id'}\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Deletes an existing Virtualmin account plan.\n";
print "\n";
print "virtualmin delete-plan --name plan-name | --id plan-id\n";
exit(1);
}

