#!/usr/local/bin/perl

=head1 test-pop3.pl

Checks if POP3 login to some server works.

This is a tool for testing POP3 servers. It takes C<--server>, C<--user>
and C<--pass> flags, followed by the POP3 hostname, login and password
respectively.

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
	$0 = "$pwd/test-pop3.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "test-pop3.pl must be run as root";
	}

# Parse command-line args
$server = "localhost";
$port = 110;
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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
$user || &usage();

# Open IMAP connection
$folder = { 'server' => $server,
	    'port' => $port,
	    'user' => $user,
	    'pass' => $pass };
&foreign_require("mailboxes", "mailboxes-lib.pl");
$main::error_must_die = 1;
($st, $h) = &mailboxes::pop3_login($folder);
if ($@) {
	# Perl error
	$err = &entities_to_ascii(&html_tags_to_text("$@"));
	$err =~ s/at\s+\S+\s+line\s+\d+.*//;
	print $err;
	exit(1);
	}
elsif ($st == 0) {
	print "POP3 connection failed : $h\n";
	exit(2);
	}
elsif ($st == 2) {
	print "POP3 login failed : $h\n";
	exit(3);
	}
else {
	# Worked .. count messages
	@uidls = &mailboxes::pop3_uidl($h);
	print "POP3 login as $user succeeded - ",scalar(@uidls)," messages\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Make a test POP3 connection to a server.\n";
print "\n";
print "virtualmin test-pop3 --user login\n";
print "                    [--pass password]\n";
print "                    [--server hostname]\n";
print "                    [--port number|name]\n";
exit(1);
}


