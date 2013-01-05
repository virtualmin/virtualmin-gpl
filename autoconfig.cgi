#!/usr/bin/perl
# This script gets copied to each domain's CGI directory to output the
# correct SMTP and IMAP server details.

# These variables get replaced when the script is copied
$OWNER = '';		# Bob's website
$STMP_HOST = '';	# mail.bob.com
$STMP_PORT = '';	# 25
$STMP_TYPE = '';	# plain or SSL
$IMAP_HOST = '';	# mail.bob.com
$IMAP_PORT = '';	# 143
$IMAP_TYPE = '';	# plain or SSL
$PREFIX = '';		# bob
$STYLE = '';		# 1

sub error_exit
{
print "Content-type: text/plain\n\n";
print @_,"\n";
exit(0);
}

# Get email address parameter
if ($ENV{'QUERY_STRING'} =~ /emailaddress=([^&]+)/) {
	$email = $1;
	$email =~ s/%(..)/pack("c",hex($1))/ge;
	($mailbox, $domain) = split(/\@/, $email);
	$mailbox && $domain ||
	    &error_exit("emailaddress parameter is not in user@domain format");
	}
else {
	&error_exit("Missing emailaddress parameter");
	}

# Work out the full username
if ($STYLE == 0) {
	$login = $mailbox.".".$PREFIX;
	}
elsif ($STYLE == 1) {
	$login = $mailbox."-".$PREFIX;
	}
elsif ($STYLE == 2) {
	$login = $PREFIX.".".$mailbox;
	}
elsif ($STYLE == 3) {
	$login = $PREFIX."-".$mailbox;
	}
elsif ($STYLE == 4) {
	$login = $name."_".$PREFIX;
	}
elsif ($STYLE == 5) {
	$login = $PREFIX."_".$name;
	}
elsif ($STYLE == 6) {
	$login = $emailaddress;
	}
elsif ($STYLE == 7) {
	$login = $name."\%".$PREFIX;
	}
else {
	&error_exit("Unknown style $STYLE");
	}

# Output the XML
print "Content-type: text/plain\n\n";
print <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
 
<clientConfig version="1.1">
  <emailProvider id="$domain">
    <domain>$domain</domain>
    <displayName>$OWNER Email</displayName>
    <displayShortName>$OWNER</displayShortName>
    <incomingServer type="imap">
      <hostname>$IMAP_HOST</hostname>
      <port>$IMAP_PORT</port>
      <socketType>$IMAP_TYPE</socketType>
      <authentication>password-cleartext</authentication>
      <username>$login</username>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>$SMTP_HOST</hostname>
      <port>$SMTP_PORT</port>
      <socketType>$SMTP_TYPE</socketType>
      <authentication>password-cleartext</authentication>
      <username>$login</username>
    </outgoingServer>
  </emailProvider>
</clientConfig>
EOF

