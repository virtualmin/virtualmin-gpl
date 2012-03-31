#!/usr/local/bin/perl

=head1 unsub-domain.pl

Convert a sub-domain into a sub-server.

This command can be used to convert a sub-domain into a sub-server, by moving
its web pages to under the virtual server's home directory, and extracting DNS
records into a separate domain. Sub-domains are a legacy feature that should
not be used in future, and have fewer features available than full sub-servers.

This command takes only one parameter, which is C<--domain> followed by the
domain name of the sub-domain to convert.

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
	$0 = "$pwd/unsub-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "unsub-domain.pl must be run as root";
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
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain
$domain || usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist.");
$d->{'subdom'} || &usage("Only sub-domains can be converted to sub-servers");

# Call the move function
&$first_print(&text('unsub_doing', "<tt>$d->{'dom'}</tt>"));
$ok = &unsub_virtual_server($d);
&run_post_actions_silently();
if ($ok) {
	&$second_print($text{'setup_done'});
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'unsub_failed'});
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Converts a virtual server that is a sub-domain into a sub-server.\n";
print "\n";
print "virtualmin unsub-domain --domain domain.name\n";
exit(1);
}


