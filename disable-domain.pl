#!/usr/local/bin/perl

=head1 disable-domain.pl

Temporarily disable a virtual server

When a server is disabled, it will become temporarily unavailable without
being completely deleted. This program can be used to disable one server,
specified with the C<--domain> option. The exact features that will be disabled
for the server are set on the module configuration page.

The optional C<--why> parameter can be followed by a description explaining
why the domain has been disabled, which will be shown when anyone tries to
edit it in Virtualmin.

To have all sub-servers owned by the same user as the specified server
disabled as well, use the C<--subservers> flag.

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
	$0 = "$pwd/disable-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "disable-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--why") {
		$why = shift(@ARGV);
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

# Find the domain
$domain || usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || &usage("Virtual server $domain does not exist");
$d->{'disabled'} && &usage("Virtual server $domain is already disabled");
@doms = ( $d );

# If disabling sub-servers, find them too
if ($subservers && !$d->{'parent'}) {
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		if (!$sd->{'disabled'}) {
			push(@doms, $sd);
			}
		}
	}

foreach $d (@doms) {
	print "Disabling virtual server $d->{'dom'} ..\n\n";
	$err = &disable_virtual_server($d, 'manual', $why);
	&usage($err) if ($err);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $doms[0]);
print "All done!\n";

sub usage
{
print $_[0],"\n" if ($_[0]);
print "Disables all features in the specified virtual server.\n";
print "\n";
print "virtualmin disable-domain --domain domain.name\n";
print "                         [--why \"explanation for disable\"]\n";
print "                         [--subservers]\n";
exit(1);
}


