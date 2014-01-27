#!/usr/local/bin/perl

=head1 enable-domain.pl

Re-enable one virtual server

This program reverses the disable process done by C<disable-domain> , or in
the Virtualmin web interface. It will restore the server to the state it was
in before being disabled.

To have all sub-servers owned by the same user as the specified server
enabled as well, use the C<--subservers> flag.

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
	$0 = "$pwd/enable-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "enable-domain.pl must be run as root";
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
!$d->{'disabled'} && &usage("Virtual server $domain is not disabled");
@doms = ( $d );

# If enabling sub-servers, find them too
if ($subservers && !$d->{'parent'}) {
	foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
		if ($sd->{'disabled'}) {
			push(@doms, $sd);
			}
		}
	}

foreach $d (@doms) {
	print "Enabling virtual server $d->{'dom'} ..\n\n";
	$err = &enable_virtual_server($d);
	&usage($err) if ($err);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $doms[0]);
print "All done!\n";

sub usage
{
print $_[0],"\n" if ($_[0]);
print "Enables all disabled features in the specified virtual server.\n";
print "\n";
print "virtualmin enable-domain --domain domain.name\n";
print "                        [--subservers]\n";
exit(1);
}


