#!/usr/local/bin/perl
# Re-send the signup email for a domain

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/resend-email.pl";
require './virtual-server-lib.pl';
$< == 0 || die "resend-email.pl must be run as root";

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
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
	}
else {
	print "Signup email is not enabled for this domain\n";
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Se-sends the email sent on virtual server creation to its owner.\n";
print "\n";
print "usage: resend-email.pl  --domain domain.name\n";
exit(1);
}

