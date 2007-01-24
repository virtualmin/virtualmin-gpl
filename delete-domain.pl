#!/usr/local/bin/perl
# Deletes a single domain and all sub-domains

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/delete-domain.pl";
require './virtual-server-lib.pl';
$< == 0 || die "delete-domain.pl must be run as root";

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--only") {
		$only = 1;
		}
	else {
		&usage("Unknown option $a");
		}
	}

# Find the domain
$domain || usage();
$dom = &get_domain_by("dom", $domain);
$dom || &usage("Virtual server $domain does not exist");

# Kill it!
print "Deleting virtual server $domain ..\n\n";
$err = &delete_virtual_server($dom, $only);
if ($err) {
	print "$err\n";
	exit 1;
	}
print "All done!\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Deletes an existing Virtualmin virtual server and all sub-servers,\n";
print "mailboxes and alias domains.\n";
print "\n";
print "usage: delete-domain.pl  --domain domain.name\n";
print "                         [--only]\n";
exit(1);
}


