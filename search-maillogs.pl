#!/usr/local/bin/perl
# Searches mail server and procmail logs

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/search-maillogs.pl";
require './virtual-server-lib.pl';
$< == 0 || die "search-maillogs.pl must be run as root";
use POSIX;
require 'timelocal.pl';

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--start") {
		$start = &date_to_time(shift(@ARGV), 0);
		}
	elsif ($a eq "--end") {
		$end = &date_to_time(shift(@ARGV), 1);
		}
	elsif ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--source") {
		$source = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--no-spam") {
		$nospam = 1;
		}
	elsif ($a eq "--no-virus") {
		$novirus = 1;
		}
	else {
		&usage();
		}
	}

&procmail_logging_enabled() || &usage("Logging is not enabled in global Procmail configuration file");

# Get the matching logs
@logs = &parse_procmail_log($start, $end, $source, $dest);
@logs = grep { (!$_->{'spam'} || !$nospam) &&
	       (!$_->{'virus'} || !$novirus) } @logs;

# Show what's left
if ($multiline) {
	# As multiple lines per event, with details
	foreach $l (@logs) {
		@tm = localtime($l->{'time'});
		print "$l->{'id'}\n";
		print "    Date: ",strftime("%Y-%m-%d", @tm),"\n";
		print "    Time: ",strftime("%H:%M:%S", @tm),"\n";
		print "    Unixtime: $l->{'time'}\n";
		print "    From: $l->{'from'}\n";
		print "    To: $l->{'to'}\n";
		print "    Size: $l->{'size'}\n";
		print "    User: $l->{'user'}\n" if ($l->{'level'});
		if ($l->{'spam'}) {
			print "    Classified: Spam\n";
			}
		elsif ($l->{'virus'}) {
			print "    Classified: Virus\n";
			}
		print $l->{'auto'} ? "    Action: Auto-reply" :
		      $l->{'forward'} ? "    Forward: $l->{'forward'}" :
		      $l->{'inbox'} ? "    Action: Inbox" :
		      $l->{'file'} ? "    Mailbox: $l->{'file'}" :
		      $l->{'program'} ? "    Program: $l->{'program'}" :
		      $l->{'local'} ?   "    Local: $l->{'local'}" :
		      $l->{'bounce'} ?  "    Action: Bounce" :
		      $l->{'throw'} ?   "    Action: Discard" :
					"    Action: Unknown","\n";
		if ($l->{'fullfile'}) {
			print "    Full path: $l->{'fullfile'}\n";
			}
		if ($l->{'relay'}) {
			print "    Outgoing email relay: $l->{'relay'}\n";
			}
		if ($l->{'status'}) {
			print "    Mail server status: $l->{'status'}\n";
			}
		}
	}
else {
	# One line per event
	$fmt = "%-10.10s %-8.8s %-20.20s %-20.20s %-18.18s\n";
	printf $fmt, "Date", "Time", "From", "To", "Dest";
	printf $fmt, ("-" x 10), ("-" x 8), ("-" x 20), ("-" x 20), ("-" x 18);
	foreach $l (@logs) {
		@tm = localtime($l->{'time'});
		$dest = $l->{'auto'} ? "Autoreply" :
			$l->{'forward'} ? $l->{'forward'} :
		        $l->{'spam'} ? "Spam" :
		        $l->{'virus'} ? "Virus" :
		        $l->{'inbox'} ? "Inbox" :
			$l->{'file'} ? $l->{'file'} :
			$l->{'program'} ? "|".$l->{'program'} :
			$l->{'local'} ? "Local $l->{'local'}" :
		        $l->{'bounce'} ? "Bounce" :
		        $l->{'throw'} ? "Discard" :
					"Unknown";
		printf $fmt,
			strftime("%Y-%m-%d", @tm),
			strftime("%H:%M:%S", @tm),
			$l->{'from'},
			$l->{'to'},
			$dest;
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Searches the combined mail logs.\n";
print "\n";
print "usage: search-mailllogs.pl   [--start yyyy-mm-dd:hh:mm:ss]\n";
print "                             [--end yyyy-mm-dd:hh:mm:ss]\n";
print "                             [--dest domain|user\@domain]\n";
print "                             [--source domain|user\@domain]\n";
print "                             [--multiline]\n";
print "                             [--no-spam] [--no-virus]\n";
exit(1);
}

sub date_to_time
{
local ($date, $endday) = @_;
local $rv;
if ($date =~ /^(\d{4})-(\d+)-(\d+):(\d+):(\d+):(\d+)$/) {
	# Full date-time spec
	$rv = timelocal($6, $5, $4, $3, $2-1, $1-1900);
	}
elsif ($date =~ /^(\d{4})-(\d+)-(\d+)$/) {
	# Date only
	if ($endday) {
		$rv = timelocal(0, 0, 0, $3, $2-1, $1-1900);
		}
	else {
		$rv = timelocal(59, 59, 23, $3, $2-1, $1-1900);
		}
	}
elsif ($date =~ /^\-(\d+)$/) {
	# Some days ago
	$rv = time()-($1*24*60*60);
	}
$rv || &usage("Date/time spec must be like 2007-01-20:09:30:00 or 2007-01-20 or -5 (days ago)");
return $rv;
}
