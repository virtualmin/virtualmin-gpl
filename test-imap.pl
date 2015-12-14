#!/usr/local/bin/perl

=head1 test-imap.pl

Checks if IMAP login to some server works.

This is a tool for testing IMAP servers. It takes C<--server>, C<--user>
and C<--pass> flags, followed by the IMAP hostname, login and password
respectively. The optional C<--folder> flag can be used to select an IMAP
folder other than the inbox.

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
	$0 = "$pwd/test-imap.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "test-imap.pl must be run as root";
	}

# Parse command-line args
$server = "localhost";
$port = 143;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--server") {
		$server = shift(@ARGV);
		}
	elsif ($a eq "--port") {
		$port = shift(@ARGV);
		if ($port !~ /^\d+$/) {
			$oldport = $port;
			$port = getservbyname($oldport, "tcp");
			$port || &usage("Port $oldport is not valid");
			}
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--folder") {
		$mailbox = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$user || &usage("No IMAP username specified");

# Open IMAP connection
$folder = { 'server' => $server,
	    'port' => $port,
	    'user' => $user,
	    'pass' => $pass,
	    'mailbox' => $mailbox };
&foreign_require("mailboxes");
$main::error_must_die = 1;
($st, $h, $count) = &mailboxes::imap_login($folder);
if ($@) {
	# Perl error
	$err = &entities_to_ascii(&html_tags_to_text("$@"));
	$err =~ s/at\s+\S+\s+line\s+\d+.*//;
	print $err;
	exit(1);
	}
elsif ($st == 0) {
	print "IMAP connection failed : $h\n";
	exit(2);
	}
elsif ($st == 2) {
	print "IMAP login failed : $h\n";
	exit(3);
	}
elsif ($st == 3) {
	print "IMAP folder selection failed : $h\n";
	exit(4);
	}
else {
	print "IMAP login as $user succeeded - $count messages\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Make a test IMAP connection to a server.\n";
print "\n";
print "virtualmin test-imap --user login\n";
print "                    [--pass password]\n";
print "                    [--server hostname]\n";
print "                    [--port number|name]\n";
print "                    [--folder name]\n";
exit(1);
}


