#!/usr/local/bin/perl

=head1 modify-database-hosts.pl

Adds or removes an allowed MySQL host for some or all domains

This command can change the remote hosts that are allowed to login to the MySQL
databases owned by some virtual servers and all their sub-servers. The domains
to modify are selected with the C<--domain> flag, or you can select all (with
MySQL enabled) with the C<--all-domains> command-line parameter. The
C<--type> flag must be given, and followed by a database type to modify.
Currently, only C<mysql> databases support configuration of allowed remote
hosts.

To add a remote system to allowed list, use the C<--add-host> flag followed
by a hostname, IP address or IP pattern like I<192.168.1.%>. To take away
a host, use C<--remove-host>. To clear all existing remote hosts and specify
a new list, use C<--set-host>. All of these flags may appear multiple times,
but if you use C<--set-host> the other two cannot be used.

Access from the system running Virtualmin is always granted, and cannot be
removed.

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
	$0 = "$pwd/modify-database-hosts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-database-hosts.pl must be run as root";
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
	elsif ($a eq "--add-host") {
		push(@addhosts, shift(@ARGV));
		}
	elsif ($a eq "--remove-host") {
		push(@delhosts, shift(@ARGV));
		}
	elsif ($a eq "--set-host") {
		push(@sethosts, shift(@ARGV));
		}
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Validate inputs
$type || &usage("Missing --type parameter");
@addhosts || @delhosts || @sethosts || &usage("At least one host to add, remove or set must be given");
if (@sethosts) {
	(@addhosts || @delhosts) && &usage("--set-host cannot be combined with --add-host and --remove-host");
	}

# Get domains to update
if ($all_doms) {
	@doms = grep { !$_->{'parent'} && $_->{$type} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{$type} ||
		  &usage("Virtual server $n does not have a $type database");
		$d->{'parent'} &&
		  &usage("Virtual server $n is not a top-level server");
		push(@doms, $d);
		}
	}
@doms || &usage("No domains to set remote $type hosts on specified");

# Do all the domains
$gfunc = "get_".$type."_allowed_hosts";
$sfunc = "save_".$type."_allowed_hosts";
defined(&$sfunc) || &usage("The $type database does not support per-domain remote hosts");
foreach my $d (@doms) {
	&$first_print("Updating $type remote hosts in $d->{'dom'} ..");
	my @hosts;
	if (@sethosts) {
		# Just use set list
		@hosts = @sethosts;
		}
	else {
		# Add and remove
		@hosts = &$gfunc($d);
		push(@hosts, @addhosts);
		@hosts = grep { &indexoflc($_, @delhosts) < 0 } @hosts;
		}
	@hosts = &unique(@hosts);
	$err = &$sfunc($d, \@hosts);
	if ($err) {
		&$second_print(".. failed : $err");
		}
	else {
		&$second_print(".. set to ",join(" ", @hosts));
		}
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Modifies the allowed remote database hosts for some domains.\n";
print "\n";
local $types = join("|", @database_features);
print "virtualmin modify-database-hosts --domain name | --all-domains\n";
print "                                 --type $types\n";
print "                                [--add-host ip]\n";
print "                                [--remove-host ip]\n";
print "                                [--set-host ip]\n";
exit(1);
}
