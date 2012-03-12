#!/usr/local/bin/perl

=head1 syncmx-domain.pl

Updates allowed relay addresses in one or more domains.

This command can be used to bring the lists of allowed addresses on secondary
MX servers into sync with the master Virtualmin system for some or all domains.
In general it should never need to be run, unless email addresses have been
modified outside of Virtualmin's control.

The only flags it takes are C<--domain> followed by domain name to sync, 
C<--user> followed by the name of a user who owns domains, or C<--all-domains>.

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
	$0 = "$pwd/syncmx-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "syncmx-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	else {
		&usage("Unknown option $a");
		}
	}

# Find the domains
@domains || @users || $all_doms || usage();
if ($all_doms) {
        # All domains
        @doms = &list_domains();
	}
else {
	# By domain or user
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage);
	}

# Make sure MXs exist
@servers = &list_mx_servers();
@servers || &usage("No secondary mail servers have been defined");

# Call the sync function on each one
foreach $d (grep { $_->{'mail'} } @doms) {
	print $d->{'dom'},"\n";
	@rv = &sync_secondary_virtusers($d);
	foreach $r (@rv) {
		print "    ",$r->[0]->{'host'},": ",($r->[1] || "OK"),"\n";
		}
	}

&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Updates allowed relay addresses in one or more domains.\n";
print "\n";
print "virtualmin syncmx-domain [--domain domain.name]*\n";
print "                         [--user username]*\n";
exit(1);
}


