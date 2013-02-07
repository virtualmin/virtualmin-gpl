#!/usr/bin/perl
# This script gets copied to each domain's CGI directory to output the
# correct SMTP and IMAP server details.

# These variables get replaced when the script is copied
$OWNER = '';		# Bob's website
$USER = '';		# bob
$SMTP_HOST = '';	# mail.bob.com
$SMTP_PORT = '';	# 25
$SMTP_TYPE = '';	# plain or SSL
$SMTP_ENC = '';		# password-cleartext
$IMAP_HOST = '';	# mail.bob.com
$IMAP_PORT = '';	# 143
$IMAP_TYPE = '';	# plain or SSL
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
	$email = $1;
	$email =~ s/%(..)/pack("c",hex($1))/ge;
	($mailbox, $SMTP_DOMAIN) = split(/\@/, $email);
	$mailbox && $SMTP_DOMAIN ||
	    &error_exit("emailaddress parameter is not in user@domain format");
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
	$SMTP_LOGIN = $name."_".$PREFIX;
	}
elsif ($STYLE == 5) {
	$SMTP_LOGIN = $PREFIX."_".$name;
	}
elsif ($STYLE == 6) {
	$SMTP_LOGIN = $email;
	}
elsif ($STYLE == 7) {
	$SMTP_LOGIN = $name."\%".$PREFIX;
	}
else {
	&error_exit("Unknown style $STYLE");
	}

# Output the XML
print "Content-type: text/xml\n\n";
print <<EOF;
_XML_GOES_HERE_
EOF
