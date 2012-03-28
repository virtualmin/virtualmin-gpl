#!/usr/local/bin/perl

=head1 test-smtp.pl

Checks if the mail server can RCPT to some address

This command is debugging tool for mailboxes and aliases - it can be used
to check if some address is accepted by your mail server, and if SMTP
authentication is working.

The C<--server> flag specifies the mail server to test, which defaults to
C<localhost>. The C<--from> flag sets the email address used in the 
C<MAIL FROM> SMTP operation, which defaults to C<nobody@virtualmin.com>.
The C<--to> flag is mandatory, and sets the destination email address.

To have it try SMTP authentication, use the C<--user> and C<--pass> flags
which must be followed a username and password respectively. The C<--auth>
flag can be used to set the SMTP authentication type, which defaults to
C<Plain>.

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
	$0 = "$pwd/test-smtp.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "test-smtp.pl must be run as root";
	}

# Parse command-line args
$server = "localhost";
$from = "nobody\@virtualmin.com";
$auth = "Plain";
$port = 25;
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
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	elsif ($a eq "--to") {
		$to = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--auth") {
		$auth = shift(@ARGV);
		}
	elsif ($a eq "--data") {
		$datafile = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
$to || &usage();

# Open SMTP connection
&foreign_require("mailboxes", "mailboxes-lib.pl");
$main::error_must_die = 1;
eval {
	&mailboxes::open_socket($server, $port, mailboxes::MAIL);
	&mailboxes::smtp_command(mailboxes::MAIL);
	&mailboxes::smtp_command(mailboxes::MAIL, "helo ".&get_system_hostname()."\r\n");

	if ($user) {
		# Login to SMTP server
		eval "use Authen::SASL";
		if ($@) {
			&error("Perl module <tt>Authen::SASL</tt> is needed for SMTP authentication");
			}
		my $sasl = Authen::SASL->new('mechanism' => uc($auth),
					     'callback' => {
						'auth' => $user,
						'user' => $user,
						'pass' => $pass } );
		&error("Failed to create Authen::SASL object") if (!$sasl);
		local $conn = $sasl->client_new("smtp", &get_system_hostname());
		local $arv = &mailboxes::smtp_command(mailboxes::MAIL, "auth $auth\r\n", 1);
		if ($arv =~ /^(334)\s+(.*)/) {
			# Server says to go ahead
			$extra = $2;
			local $initial = $conn->client_start();
			local $auth_ok;
			if ($initial) {
				local $enc = &encode_base64($initial);
				$enc =~ s/\r|\n//g;
				$arv = &mailboxes::smtp_command(mailboxes::MAIL, "$enc\r\n", 1);
				if ($arv =~ /^(\d+)\s+(.*)/) {
					if ($1 == 235) {
						$auth_ok = 1;
						}
					else {
						&error("Unknown SMTP authentication response : $arv");
						}
					}
				$extra = $2;
				}
			while(!$auth_ok) {
				local $message = &decode_base64($extra);
				local $return = $conn->client_step($message);
				local $enc = &encode_base64($return);
				$enc =~ s/\r|\n//g;
				$arv = &mailboxes::smtp_command(mailboxes::MAIL, "$enc\r\n", 1);
				if ($arv =~ /^(\d+)\s+(.*)/) {
					if ($1 == 235) {
						$auth_ok = 1;
						}
					elsif ($1 == 535) {
						&error("SMTP authentication failed : $arv");
						}
					$extra = $2;
					}
				else {
					&error("Unknown SMTP authentication response : $arv");
					}
				}
			}
		}

	# Send from and to
	&mailboxes::smtp_command(mailboxes::MAIL, "mail from: <$from>\r\n");
	&mailboxes::smtp_command(mailboxes::MAIL, "rcpt to: <$to>\r\n");
	if ($datafile) {
		$data = &read_file_contents($datafile);
		$data || die "Failed to read $datafile : $!";
		$data =~ s/^From\s.*\r?\n//;	# Remove From line
		$r = &mailboxes::smtp_command(mailboxes::MAIL, "data\r\n");
		print mailboxes::MAIL $data;
		$r = &mailboxes::smtp_command(mailboxes::MAIL, ".\r\n");
		}
	&mailboxes::smtp_command(mailboxes::MAIL, "quit\r\n");
	close(MAIL);
	};
if ($@) {
	$err = &entities_to_ascii(&html_tags_to_text("$@"));
	$err =~ s/at\s+\S+\s+line\s+\d+.*//;
	print $err;
	exit(1);
	}
else {
	print "SMTP address $to accepts RCPT\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Make a test SMTP connection to a mail server.\n";
print "\n";
print "virtualmin test-smtp --to address\n";
print "                    [--server hostname]\n";
print "                    [--port number|name]\n";
print "                    [--from address]\n";
print "                    [--user login --pass password]\n";
print "                    [--auth method]\n";
print "                    [--data mail-file]\n";
exit(1);
}


