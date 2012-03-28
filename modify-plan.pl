#!/usr/local/bin/perl

=head1 modify-plan.pl

Modifies an existing account plan for use with virtual servers.

This command allows you to modify the limits for an existing account plan,
and optionally apply it to all virtual servers currently on that plan
(with the C<--apply> flag). Its parameters are exactly the same as
C<create-plan>, so for full documentation you should refer to that command.

To change the name of a plan, use the C<--new-name> flag followed by the
new name of your choice.

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
	$0 = "$pwd/modify-plan.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-plan.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
$newplan = { };
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name") {
		$planname = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$planid = shift(@ARGV);
		}
	elsif ($a eq "--new-name") {
		$newplan->{'name'} = shift(@ARGV);
		}

	elsif ($a eq "--owner") {
		$newplan->{'owner'} = shift(@ARGV);
		&get_reseller($plan->{'owner'}) ||
		    &usage("Reseller owner $plan->{'owner'} does not exisst");
		}
	elsif ($a eq "--no-owner") {
		$newplan->{'owner'} = '';
		}

	elsif ($a eq "--quota" || $a eq "--admin-quota") {
		# Some quota
		$q = shift(@ARGV);
		$q =~ /^\d+$/ ||
			&usage("$a must be followed by a quota in blocks");
		$f = $a eq "--quota" ? "quota" : "uquota";
		$newplan->{$f} = $q;
		}
	elsif ($a eq "--no-quota" || $a eq "--no-admin-quota") {
		# Unlimited quota
		$f = $a eq "--no-quota" ? "quota" : "uquota";
		$newplan->{$f} = '';
		}

	elsif ($a =~ /^\-\-max\-(\S+)$/ && &indexof($1, @plan_maxes) >= 0) {
		# Some limit on domains / etc
		$l = $1; $q = shift(@ARGV);
		$q =~ /^\d+$/ ||
			&usage("$a must be followed by a numeric limit");
		$newplan->{$l.'limit'} = $q;
		}
	elsif ($a =~ /^\-\-no\-max\-(\S+)$/ && &indexof($1, @plan_maxes) >= 0) {
		# Removing limit on domains / etc
		$l = $1;
		$newplan->{$l.'limit'} = '';
		}

	elsif ($a =~ /^\-\-(\S+)$/ &&
	       &indexof($1, @plan_restrictions) >= 0) {
		# No db name or other binary limit
		$newplan->{$1} = 1;
		}
	elsif ($a =~ /^\-\-no\-(\S+)$/ &&
	       &indexof($1, @plan_restrictions) >= 0) {
		# Disabel no db name or other binary limit
		$newplan->{$1} = 0;
		}

	elsif ($a eq "--features") {
		# Allowed features
		@fl = split(/\s+/, shift(@ARGV));
		@allf = ( @opt_features, "virt", &list_feature_plugins() );
		foreach $f (@fl) {
			&indexof($f, @allf) >= 0 ||
			     &usage("Unknown feature $f - allowed options ".
				    "are : ".join(" ", @allf));
			}
		$newplan->{'featurelimits'} = join(" ", @fl);
		}
	elsif ($a eq "--auto-features") {
		# Allow all features
		$newplan->{'featurelimits'} = '';
		}
	elsif ($a eq "--no-features") {
		# Remove all features
		$newplan->{'featurelimits'} = 'none';
		}

	elsif ($a eq "--capabilities") {
		# Edit capabilities
		@cl = split(/\s+/, shift(@ARGV));
		foreach $c (@cl) {
			&indexof($c, @edit_limits) >=0 ||
			    &usage("Unknown capability $c - allowed options ".
				   "are : ".join(" ", @edit_limits));
			}
		$newplan->{'capabilities'} = join(" ", @cl);
		}
	elsif ($a eq "--auto-capabilities") {
		# Allow all capabilities
		$newplan->{'capabilities'} = '';
		}

	elsif ($a eq "--scripts") {
		# Allowed scripts
		@sc = split(/\s+/, shift(@ARGV));
		foreach $s (@sc) {
			&get_script($s) ||
				&usage("Unknown script code $s");
			}
		$newplan->{'scripts'} = join(" ", @sc);
		}
	elsif ($a eq "--all-scripts") {
		# Allow all scripts
		$newplan->{'scripts'} = '';
		}

	elsif ($a eq "--no-resellers") {
		# Not for any resellers
		$newplan->{'resellers'} = 'none';
		}
	elsif ($a eq "--resellers") {
		# Only for listed resellers
		@rl = split(/\s+/, shift(@ARGV));
		foreach $r (@rl) {
			&get_reseller($r) || &usage("Unknown reseller $r");
			}
		$newplan->{'resellers'} = join(" ", @rl);
		}
	elsif ($a eq "--all-resellers") {
		# For all resellers
		$newplan->{'resellers'} = '';
		}
	elsif ($a eq "--apply") {
		# Apply to domains
		$applyplan = 1;
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

# Check for name clash
if ($newplan->{'name'}) {
	($clash) = grep { lc($_->{'name'}) eq lc($newplan->{'name'}) &&
			  $_->{'id'} ne $plan->{'id'} } &list_plans();
	$clash && &usage("A plan named $newplan->{'name'} already exists");
	}

# Merge in changes from command line
foreach $k (keys %$newplan) {
	$plan->{$k} = $newplan->{$k};
	}

# Save it
&save_plan($plan);
print "Modified plan $plan->{'name'} with ID $plan->{'id'}\n";

# Apply the change
if ($applyplan) {
	$count = 0;
	&set_all_null_print();
	foreach my $d (&get_domain_by("plan", $plan->{'id'})) {
		next if ($d->{'parent'});
		local $oldd = { %$d };
		&set_limits_from_plan($d, $plan);
		&set_featurelimits_from_plan($d, $plan);
		&set_capabilities_from_plan($d, $plan);
		foreach $f (&domain_features($d), &list_feature_plugins()) {
			&call_feature_func($f, $d, $oldd);
			}
		&save_domain($d);
		$count++;
		}
	&run_post_actions();
	print "Applied to $count virtual servers\n";
	}

&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Updates an existing Virtualmin account plan with the given limits.\n";
print "\n";
print "virtualmin modify-plan --name plan-name | --id number\n";
print "                      [--new-name plan-name]\n";
print "                      [--owner reseller | --no-owner]\n";
print "                      [--quota blocks | --no-quota]\n";
print "                      [--admin-quota blocks | --no-admin-quota]\n";
foreach $l (@plan_maxes) {
	print "                      [--max-$l limit | --no-max-$l]\n";
	}
foreach $r (@plan_restrictions) {
	print "                      [--$r | --no-$r]\n";
	}
print "                      [--features \"web dns mail ...\" |\n";
print "                       --auto-features | --no-features]\n";
print "                      [--capabilities \"domain users aliases ...\" |\n";
print "                       --auto-capabilities]\n";
if (defined(&list_resellers)) {
	print "                      [--no-resellers | --resellers \"name name..\" |\n";
	print "                       --all-resellers]\n";
	}
print "                      [--apply]\n";
exit(1);
}

