#!/usr/local/bin/perl

=head1 test-imap.pl

Checks if IMAP login to some server works.

This is a tool for testing IMAP servers. It takes C<--server>, C<--user>
and C<--pass> flags, followed by the IMAP hostname, login and password
respectively. The optional C<--folder> flag can be used to select an IMAP
folder other than the inbox.

To connect to a different IMAP server port, use the C<--port> flag followed by
a port number. To make an SSL connection, use the C<--ssl> flag. To validate
the certificate name and send SNI on the SSL connection, use C<--cert-host>
and optionally C<--sni>. To also verify the selected certificate, use
C<--cert-org>.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	require FindBin;
	chdir($pwd = $FindBin::RealBin) ||
		die "Failed to chdir to $FindBin::RealBin : $!";
	$0 = "$pwd/test-imap.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "test-imap.pl must be run as root";
	}

# Parse command-line args
$server = "localhost";
while(@ARGV > 0) {
	my $a = shift(@ARGV);
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
	elsif ($a eq "--ssl") {
		$ssl = 1;
		}
	elsif ($a eq "--cert-host") {
		$cert_host = shift(@ARGV);
		}
	elsif ($a eq "--cert-org") {
		$cert_org = shift(@ARGV);
		}
	elsif ($a eq "--sni") {
		$sni = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$user || &usage("No IMAP username specified");
$cert_host && !$ssl && &usage("--cert-host requires --ssl");
$cert_org && !$ssl && &usage("--cert-org requires --ssl");
$sni && !$ssl && &usage("--sni requires --ssl");

# Open IMAP connection
$folder = { 'server' => $server,
	    'port' => $port,
	    'ssl' => $ssl,
	    'user' => $user,
	    'pass' => $pass,
	    'mailbox' => $mailbox };
&foreign_require("mailboxes");
$main::error_must_die = 1;
if ($cert_host || $cert_org || $sni) {
	($st, $h, $count) = &imap_login_with_ssl_name_check($folder,
							    $cert_host,
							    $cert_org, $sni);
	}
else {
	($st, $h, $count) = &mailboxes::imap_login($folder);
	}
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
	if ($cert_host) {
		print "IMAP SSL certificate for $cert_host matched\n";
		}
	if ($cert_org) {
		print "IMAP SSL certificate organization $cert_org matched\n";
		}
	print "IMAP login as $user succeeded - $count messages\n";
	}

sub imap_login_with_ssl_name_check
{
my ($folder, $cert_host, $cert_org, $sni) = @_;
my $port = $folder->{'port'} || 993;
my $h = "SSLIMAP".time().$$;
my $error;
&open_socket($folder->{'server'}, $port, $h, \$error);
return (0, $error) if ($error);
eval "use Net::SSLeay";
$@ && return (0, "Net::SSLeay module is not installed");
eval "Net::SSLeay::SSLeay_add_ssl_algorithms()";
eval "Net::SSLeay::load_error_strings()";
my $ssl_ctx = Net::SSLeay::CTX_new() ||
	return (0, "Failed to create SSL context");
my $ssl_con = Net::SSLeay::new($ssl_ctx) ||
	return (0, "Failed to create SSL connection");
Net::SSLeay::set_fd($ssl_con, fileno($h));
my $snihost = $sni || $cert_host || $folder->{'server'};
if ($snihost) {
	defined(&Net::SSLeay::set_tlsext_host_name) ||
		return (0, "Net::SSLeay does not support SNI");
	Net::SSLeay::set_tlsext_host_name($ssl_con, $snihost);
	}
Net::SSLeay::connect($ssl_con) ||
	return (0, "SSL connect() failed");
$mailboxes::imap_login_ssl{$h} = $ssl_con;
if ($cert_host || $cert_org) {
	my $cerr = &check_imap_ssl_cert($ssl_con, $cert_host, $cert_org);
	return (0, $cerr) if ($cerr);
	}

my @rv = &mailboxes::imap_command($h);
return (0, $rv[3] || "No response") if (!$rv[0]);
my $user = $folder->{'user'} eq '*' ? $remote_user : $folder->{'user'};
my $pass = $folder->{'pass'};
$pass =~ s/\\/\\\\/g;
$pass =~ s/"/\\"/g;
@rv = &mailboxes::imap_command($h, "login \"$user\" \"$pass\"");
return (2, $rv[3] || "No response") if (!$rv[0]);
@rv = &mailboxes::imap_command($h,
			       "select \"".($folder->{'mailbox'} || "INBOX")."\"");
return (3, $rv[3]) if (!$rv[0]);
my $count = $rv[2] =~ /\*\s+(\d+)\s+EXISTS/i ? $1 : undef;
return (1, $h, $count);
}

sub check_imap_ssl_cert
{
my ($ssl_con, $host, $org) = @_;
my $x509 = Net::SSLeay::get_peer_certificate($ssl_con);
$x509 || return "Could not fetch peer certificate";
my @names;
my $subject = Net::SSLeay::X509_get_subject_name($x509);
if (defined($org)) {
	my $gotorg = Net::SSLeay::X509_NAME_get_text_by_NID($subject, 17);
	$gotorg eq $org ||
		return "Certificate organization is $gotorg, not $org";
	}
my $cn = Net::SSLeay::X509_NAME_get_text_by_NID($subject, 13);
push(@names, $cn) if ($cn);
my @alts = Net::SSLeay::X509_get_subjectAltNames($x509);
while(my ($type, $val) = splice(@alts, 0, 2)) {
	push(@names, $val) if ($type == 2);	# dNSName
	push(@names, &ssl_cert_packed_ip_address($val))
		if ($type == 7);			# iPAddress
	}
return undef if (!$host);
foreach my $name (@names) {
	return undef if (&imap_ssl_cert_name_matches($name, $host));
	}
return "Certificate is for ".join(", ", @names).", not $host";
}

sub imap_ssl_cert_name_matches
{
my ($name, $host) = @_;
$name = lc($name);
$host = lc($host);
if ($name =~ /^\*\.(\S+)$/) {
	return $host =~ /^[^\.]+\.\Q$1\E$/;
	}
return $name eq $host;
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
print "                    [--ssl]\n";
print "                    [--cert-host hostname]\n";
print "                    [--cert-org name]\n";
print "                    [--sni hostname]\n";
print "                    [--folder name]\n";
exit(1);
}
