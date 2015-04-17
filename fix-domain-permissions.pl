#!/usr/local/bin/perl

=head1 fix-domain-permissions.pl

Set correct permissions on a domain's home directory.

This command ensures that the ownership and permissions on one or more virtual
server's home directories are correct. It can be run either with the
C<--all-domains> flag to update all virtual servers, or C<--domain> followed
by a single domain name. To include sub-servers of selected domains, you
can also add the C<--subservers> flag.

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
	$0 = "$pwd/fix-domain-permissions.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "fix-domain-permissions.pl must be run as root";
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
	elsif ($a eq "--subservers") {
		$subservers = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains to fix specified");

# Get the domains
if ($all_doms) {
	@doms = grep { $_->{'dir'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		push(@doms, $d);
		if ($subservers && !$d->{'parent'}) {
			push(@doms, &get_domain_by("parent", $d->{'id'}));
			}
		}
	}

# Lock them all
foreach $d (@doms) {
	&obtain_lock_unix($d);
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Fixing permissions for server $d->{'dom'} ..");
	if (!$d->{'dir'}) {
		&$second_print(".. does not have a home directory");
		}
	else {
		$err = &set_home_ownership($d);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}
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
print "Set correct permissions on a domain's home directory.\n";
print "\n";
print "virtualmin fix-domain-permissions --domain name | --all-domains\n";
print "                                 [--subservers]\n";
exit(1);
}
