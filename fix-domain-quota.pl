#!/usr/local/bin/perl

=head1 fix-domain-quota.pl

Set the Unix quotas for some domains to match the Virtualmin configuration.

This command can be used to bring the Unix quotas for domain owners back into
sync with what Virtualmin expects, if the quota file has been lose or manually
edited. It can be run either with the C<--all-domains> flag to update all
virtual servers, or C<--domain> followed by a single domain name.

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
	$0 = "$pwd/fix-domain-quota.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "fix-domain-quota.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains to fix specified");
&has_home_quotas() || &usage("Quotas have not been detected on this system");

# Get the domains
if ($all_doms) {
	@doms = grep { !$_->{'parent'} && $_->{'unix'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'parent'} && &usage("Domain $n is not a top-level server");
		$d->{'unix'} || &usage("Domain $n does not have a Unix user");
		push(@doms, $d);
		}
	}

# Lock them all
foreach $d (@doms) {
	&obtain_lock_unix($d);
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Fixing quota for server $d->{'dom'} ..");
	&set_server_quotas($d);
	&$second_print(".. done");
	}

# Un-lock them all
foreach $d (reverse(@doms)) {
	&release_lock_unix($d);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Set the Unix quotas for some domains to match the Virtualmin configuration.\n";
print "\n";
print "virtualmin fix-domain-quota --domain name | --all-domains\n";
exit(1);
}
