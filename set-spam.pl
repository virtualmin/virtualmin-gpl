#!/usr/local/bin/perl
# Change the spam and virus scanners for all domains

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/set-spam.pl";
require './virtual-server-lib.pl';
$< == 0 || die "set-spam.pl must be run as root";
$config{'spam'} || &usage("Spam filtering is not enabled for Virtualmin");

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a =~ /^--use-(spamc|spamassassin)$/) {
		$spam_client = $1;
		}
	elsif ($a =~ /^--use-(clamscan|clamdscan)$/) {
		$virus_scanner = $1;
		}
	elsif ($a eq "--use-virus") {
		$virus_scanner = shift(@ARGV);
		}
	elsif ($a eq "--show") {
		$show = 1;
		}
	else {
		&usage();
		}
	}
$virus_scanner || $spam_scanner || $show || &usage("Nothing to do");

# XXX do it

if ($show) {
	# Show current settings
	}
