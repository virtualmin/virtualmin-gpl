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

# Validate inputs
$virus_scanner || $spam_client || $show || &usage("Nothing to do");
if ($spam_client) {
	&has_command($spam_client) ||
	    &usage("SpamAssassin client program $spam_client does not exist");
	}
if ($virus_scanner) {
	local ($cmd, @args) = &split_quoted_string($virus_scanner);
	&has_command($cmd) ||
		&usage("Virus scanning command $cmd does not exist");
	$err = &test_virus_scanner($virus_scanner);
	$err && &usage("Virus scanner failed : $err");
	}

if ($spam_client) {
	print "Updating all virtual servers with new SpamAssassin client ..\n";
	&save_global_spam_client($spam_client);
	print ".. done\n\n";
	}

if ($virus_scanner) {
	print "Updating all virtual servers with new virus scanner ..\n";
	&save_global_virus_scanner($virus_scanner);
	print ".. done\n\n";
	}

&run_post_actions();

if ($show) {
	# Show current settings
	if ($config{'spam'}) {
		$client = &get_global_spam_client();
		print "SpamAssassin client: $client\n";
		}
	if ($config{'virus'}) {
		$scanner = &get_global_virus_scanner();
		print "Virus scanner: $scanner\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the spam and virus scanning programs for all domains.\n";
print "\n";
print "usage: set-spam.pl [--use-spamassassin | --use-spamc]\n";
print "                   [--use-clamscan | --use-clamdscan |\n";
print "                    --use-virus command]\n";
print "                   [--show]\n";
exit(1);
}

