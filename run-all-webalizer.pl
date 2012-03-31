#!/usr/local/bin/perl

=head1 run-all-webalizer.pl

Run Webalizer reports for all virtual servers

This is designed to be called from Cron, instead of Virtualmin's regular
per-domain C</etc/webmin/webalizer/webalizer.pl> script, which can generate
a lot of load if more than one copy runs at the same time. If you decide to
use it, change the I<Setup Webalizer Cron job for each virtual server?> option
to I<No> on the I<Module Config> page.

=cut

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*)\/[^\/]+$/) {
	chdir($pwd = $1);
	}
else {
	chop($pwd = `pwd`);
	}
$0 = "$pwd/run-all-webalizer.pl";
require './virtual-server-lib.pl';
$< == 0 || die "run-all-webalizer.pl must be run as root";

if (@ARGV) {
	&usage("No parameters required");
	}

&require_webalizer();
&foreign_require("cron", "cron-lib.pl");

&cron::create_wrapper($webalizer::cron_cmd,
		      "webalizer", "webalizer.pl");
foreach $d (&list_domains()) {
	next if (!$d->{'webalizer'});
	$alog = &get_website_log($d);
	next if (!$alog);
	print "Running Webalizer for $d->{'dom'} ($alog)\n";
	system("$webalizer::cron_cmd ".quotemeta($alog));
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Runs Webalizer for all domains with it enabled, in series.\n";
print "\n";
print "usage: $ENV{'WEBMIN_CONFIG'}/run-all-webalizer.pl\n";
exit(1);
}

