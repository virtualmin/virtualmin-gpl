#!/usr/local/bin/perl

=head1 create-plan.pl

Creates a new account plan for use with virtual servers.

This command allows you to create a new account plan, which defines limits
that can be applied to new or existing virtual servers. The only mandatory
parameter is C<--name>, which must be followed by a unique name for the plan
to create.

Quotas for virtual servers on the plan can be set with the C<--quota> or
C<--admin-quota> flags, followed by a quota in blocks (typically 1k in size).
By default, plan quotas are unlimited.

Restrictions on the number of virtual servers, mailboxes, aliases and databases
can be set with the C<--max-doms>, C<--max-mailbox>, C<--max-alias> and
C<--max-dbs> parameters, followed by a number. By default, all of these are
unlimited.

Allowed features for new virtual servers can be set with the C<--features> flag,
followed by a space-separated feature code list like I<web dns mail>. Similarly,
allowed editing capabilities can be set with C<--capabilities> followed by
a list of codes like I<domain users aliases>. In both cases, the lists must
be a single quoted parameter.

Scripts that virtual servers on the plan can install can be restricted by
the C<--scripts> flag, followed by a quoted list of script codes. To find
available codes, use the C<list-available-scripts> API command.

To create a plan that is owned by a reseller, use the C<--owner> flag followed
by an existing reseller name. To limit use of the plan to only some resellers,
use C<--resellers> followed by a list of reseller names. Or use
C<--no-resellers> to prevent any resellers from seeing it.

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
	$0 = "$pwd/create-plan.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-plan.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
$plan = { };
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name") {
		$plan->{'name'} = shift(@ARGV);
		}
	elsif ($a eq "--owner") {
		$plan->{'owner'} = shift(@ARGV);
		&get_reseller($plan->{'owner'}) ||
		    &usage("Reseller owner $plan->{'owner'} does not exisst");
		}
	elsif ($a eq "--quota" || $a eq "--admin-quota") {
		# Some quota
		$q = shift(@ARGV);
		$q =~ /^\d+$/ ||
			&usage("$a must be followed by a quota in blocks");
		$f = $a eq "--quota" ? "quota" : "uquota";
		$plan->{$f} = $q;
		}
	elsif ($a =~ /^\-\-max\-(\S+)$/ && &indexof($1, @plan_maxes) >= 0) {
		# Some limit on domains / etc
		$l = $1; $q = shift(@ARGV);
		$q =~ /^\d+$/ ||
			&usage("$a must be followed by a numeric limit");
		$plan->{$l.'limit'} = $q;
		}
	elsif ($a =~ /^\-\-(\S+)$/ && &indexof($1, @plan_restrictions) >= 0) {
		# No db name or other binary limit
		$plan->{$1} = 1;
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
		$plan->{'featurelimits'} = join(" ", @fl);
		}
	elsif ($a eq "--no-features") {
		$plan->{'featurelimits'} = 'none';
		}
	elsif ($a eq "--capabilities") {
		# Edit capabilities
		@cl = split(/\s+/, shift(@ARGV));
		foreach $c (@cl) {
			&indexof($c, @edit_limits) >=0 ||
			    &usage("Unknown capability $c - allowed options ".
				   "are : ".join(" ", @edit_limits));
			}
		$plan->{'capabilities'} = join(" ", @cl);
		}
	elsif ($a eq "--scripts") {
		# Allowed scripts
		@sc = split(/\s+/, shift(@ARGV));
		foreach $s (@sc) {
			&get_script($s) ||
				&usage("Unknown script code $s");
			}
		$plan->{'scripts'} = join(" ", @sc);
		}
	elsif ($a eq "--no-resellers") {
		$plan->{'resellers'} = 'none';
		}
	elsif ($a eq "--resellers") {
		@rl = split(/\s+/, shift(@ARGV));
		foreach $r (@rl) {
			&get_reseller($r) || &usage("Unknown reseller $r");
			}
		$plan->{'resellers'} = join(" ", @rl);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate vital parameters
$plan->{'name'} || &usage("Missing --name flag");
($clash) = grep { lc($_->{'name'}) eq lc($plan->{'name'}) } &list_plans();
$clash && &usage("A plan name $plan->{'name'} already exists");

# Create it
&save_plan($plan);
print "Created plan $plan->{'name'} with ID $plan->{'id'}\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Creates a new Virtualmin account plan with the given limits.\n";
print "\n";
print "virtualmin create-plan --name plan-name\n";
print "                      [--owner reseller]\n";
print "                      [--quota blocks]\n";
print "                      [--admin-quota blocks]\n";
foreach $l (@plan_maxes) {
	print "                      [--max-$l limit]\n";
	}
foreach $r (@plan_restrictions) {
	print "                      [--$r]\n";
	}
print "                      [--features \"web dns mail ...\" | --no-features]\n";
print "                      [--capabilities \"domain users aliases ...\"]\n";
if (defined(&list_scripts)) {
	print "                      [--scripts \"name name ...\"]\n";
	}
if (defined(&list_resellers)) {
	print "                      [--no-resellers | --resellers \"name name..\"]\n";
	}
exit(1);
}

