#!/usr/local/bin/perl

=head1 get-logs.pl

Output webserver logs for a domain.

Given a domain name with the C<--domain> flag, this command outputs some or
all of it's Apache access or error log. The log file to display can be
selected with the C<--access-log>, C<--error-log> or C<--ftp-log> flag,
and the number of lines to output can be limited with the C<--tail> flag
followed by a line count.

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
	$0 = "$pwd/get-ssl.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-ssl.pl must be run as root";
	}

# Parse command line
$logtype = "alog";
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--access-log") {
		$logtype = "alog";
		}
	elsif ($a eq "--error-log") {
		$logtype = "elog";
		}
	elsif ($a eq "--ftp-log") {
		$logtype = "flog";
		}
	elsif ($a eq "--tail") {
		$lines = int(shift(@ARGV));
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs and get the domain
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("Virtual server $dname does not exist");

# Find the log file
if ($logtype eq "alog" || $logtype eq "elog") {
	&domain_has_website($d) ||
		&usage("Virtual server does not have a website");
	$logfile = &get_website_log($d, $logtype eq "elog" ? 1 : 0);
	}
elsif ($logtype eq "flog") {
	$d->{'ftp'} || &usage("Virtual server does not have FTP enabled");
	$logfile = &get_proftpd_log($d->{'ip'});
	}
$logfile || &usage("Log file not found!");

# Print it out
if ($lines) {
	&open_execute_command(LOG, "tail -".quotemeta($lines)." ".
					    quotemeta($logfile));
	}
else {
	&open_readfile(LOG, $logfile);
	}
while(<LOG>) {
	print $_;
	}
close(LOG);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Output webserver logs for a domain.\n";
print "\n";
print "virtualmin get-logs --domain name\n";
print "                    --access-log | --error-log | --ftp-log\n";
print "                   [--tail lines]\n";
exit(1);
}

