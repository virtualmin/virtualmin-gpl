#!/usr/bin/perl
# This script gets copied to each domain's CGI directory to output the
# correct SMTP and IMAP server details.

# These variables get replaced when the script is copied
$OWNER = '';		# Bob's website
$USER = '';		# bob
$SMTP_HOST = '';	# mail.bob.com
$SMTP_PORT = '';	# 25
$SMTP_TYPE = '';	# plain or SSL
$SMTP_SSL = '';		# yes or no
$SMTP_ENC = '';		# password-cleartext
$IMAP_HOST = '';	# mail.bob.com
$IMAP_PORT = '';	# 143
$IMAP_TYPE = '';	# plain or SSL
$IMAP_SSL = '';		# yes or no
$IMAP_ENC = '';		# password-cleartext or password-encrypted
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
	# Thunderbird style
	$email = $1;
	$email =~ s/%(..)/pack("c",hex($1))/ge;
	($mailbox, $SMTP_DOMAIN) = split(/\@/, $email);
	$mailbox && $SMTP_DOMAIN ||
	    &error_exit("emailaddress parameter is not in user@domain format");
	}
elsif ($ENV{'REQUEST_METHOD'} eq 'POST') {
	# Outlook style
	read(STDIN, $buf, $ENV{'CONTENT_LENGTH'});
	$buf =~ /<EMailAddress>([^@<>]+)@([^<>]+)<\/EMailAddress>/i ||
		&error_exit("EMailAddress missing from input XML");
	($mailbox, $SMTP_DOMAIN) = ($1, $2);
	$email = $1."\@".$2;
	}
else {
	&error_exit("Missing emailaddress parameter");
	}

# Work out the full username
if ($mailbox eq $USER) {
	# Domain owner, so no need for prefix
	$SMTP_LOGIN = $USER;
	}
elsif ($STYLE == 0) {
	$SMTP_LOGIN = $mailbox.".".$PREFIX;
	}
elsif ($STYLE == 1) {
	$SMTP_LOGIN = $mailbox."-".$PREFIX;
	}
elsif ($STYLE == 2) {
	$SMTP_LOGIN = $PREFIX.".".$mailbox;
	}
elsif ($STYLE == 3) {
	$SMTP_LOGIN = $PREFIX."-".$mailbox;
	}
elsif ($STYLE == 4) {
	$SMTP_LOGIN = $mailbox."_".$PREFIX;
	}
elsif ($STYLE == 5) {
	$SMTP_LOGIN = $PREFIX."_".$mailbox;
	}
elsif ($STYLE == 6) {
	$SMTP_LOGIN = $email;
	}
elsif ($STYLE == 7) {
	$SMTP_LOGIN = $mailbox."\%".$PREFIX;
	}
else {
	&error_exit("Unknown style $STYLE");
	}
$MAILBOX = $mailbox;

# Output the XML
print "Content-type: text/xml\n\n";
if ($ENV{'SCRIPT_NAME'} =~ /autodiscover.xml/i) {
	# Outlook
	print <<EOF;
_OUTLOOK_XML_GOES_HERE_
EOF
	}
else {
	# Thunderbird
	print <<EOF;
_THUNDERBIRD_XML_GOES_HERE_
EOF
	}

