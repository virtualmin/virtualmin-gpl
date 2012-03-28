#!/usr/local/bin/perl

=head1 resend-email.pl

Re-send the signup email for a domain

This command re-sends the initial signup email to a virtual server's owner.
It takes only one parameter, C<--domain> followed by a domain name.

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
	$0 = "$pwd/resend-email.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "resend-email.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

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
		&usage();
		}
	}

# Find the domain
$domain || usage();
$dom = &get_domain_by("dom", $domain);
$dom || usage("Virtual server $domain does not exist");

if (&will_send_domain_email($dom)) {
	&send_domain_email($dom);
	&run_post_actions_silently();
	&virtualmin_api_log(\@OLDARGV, $dom);
	}
else {
	print "Signup email is not enabled for this domain\n";
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Se-sends the email sent on virtual server creation to its owner.\n";
print "\n";
print "virtualmin resend-email --domain domain.name\n";
exit(1);
}

