#!/usr/local/bin/perl

=head1 notify-domains.pl

Send email to some or all virtual server owners.

This command can be used to send a text format email message to the owners
and possibly extra administrators of some or all virtual servers. The servers
to notify can be selected with the C<--domain> flag followed by a domain name,
which can be given multiple times. Or you can use C<--user> followed by an
administrator's username. If neither are given, the email is sent to all 
virtual servers.

If the messsage is related to some service such as email or web serving, you
can use the C<--with-feature> flag followed by a feature code like C<mail> or
C<web> to limit the servers notified to those with that feature enabled.
Similarly, you can use C<--without-feature> to select only virtual servers
that do not have some feature enabled.

The message contents are typically read from a file, specified with the 
C<--body-file> parameter. Or they can be passed as input to the script if
the C<--body-stdin> flag is used. Or for very short messages, you can specify
the contents on the command line with C<--body-message>. Als, you can set a
custom character set for the message body with the optional C<--charset> flag.

The email subject line must be set with the C<--subject> flag. The from address
defaults to whatever you have configured globally in Virutalmin, but can be
overridden with the C<--from> flag.

By default only domain owners are notified, but you can include extra admins
for the selected virtual servers with the C<--admins> flag. Only admins who
have an email address configured will receive the message though.

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
	$0 = "$pwd/resend-email.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "resend-email.pl must be run as root";
	}
@OLDARGV = @ARGV;

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--with-feature") {
		$with = shift(@ARGV);
		}
	elsif ($a eq "--without-feature") {
		$without = shift(@ARGV);
		}
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	elsif ($a eq "--subject") {
		$subject = shift(@ARGV);
		}
	elsif ($a eq "--body-file") {
		$bodyfile = shift(@ARGV);
		}
	elsif ($a eq "--body-message") {
		$body = shift(@ARGV);
		}
	elsif ($a eq "--body-stdin") {
		$bodystdin = 1;
		}
	elsif ($a eq "--charset") {
		$charset = shift(@ARGV);
		}
	elsif ($a eq "--admins") {
		$admins = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$from ||= &get_global_from_address();

# Get the domains
if (@domains || @users) {
	# By domain name or username
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage);
	}
else {
	@doms = &list_domains();
	}
if ($with) {
	# Also limit by feature
	@doms = grep { $_->{$with} } @doms;
	}
if ($without) {
	@doms = grep { !$_->{$without} } @doms;
	}
@doms || &usage("No virtual servers selected");

# Read the message
if ($bodyfile) {
	$body = &read_file_contents($bodyfile);
	$body || &usage("Failed to read contents from $bodyfile : $!");
	}
elsif ($bodystdin) {
	$body = "";
	while(<STDIN>) {
		$body .= $_;
		}
	close(STDIN);
	$body || &usage("No message body given as input");
	}
elsif (!$body) {
	&usage("One of --body-file, --body-stdin or --body-message must be given");
	}
$subject || &usage("Missing --subject parameter");

# Work out to addresses
@to = map { $_->{'emailto'} } @doms;
if ($admins) {
        foreach my $d (@doms) {
                push(@to, map { $_->{'email'} }
                            grep { $_->{'email'} }
                               &list_extra_admins($d));
                }
        }
@to = &unique(@to);

# Send the mail
&send_notify_email($from, \@doms, undef, $subject, $body, undef, undef, undef,
		   undef, undef, $charset);

# Tell the user
print "Sent email from $from to the following addresses ..\n";
foreach $t (@to) {
	print "  $t\n";
	}

&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Sends email to some or all virtual server owners\n";
print "\n";
print "virtualmin notify-domains [--domain name]\n";
print "                          [--user login]\n";
print "                          [--with-feature code]\n";
print "                          [--without-feature code]\n";
print "                           --body-file /path/to/file.txt |\n";
print "                           --body-message \"text\" |\n";
print "                           --body-stdin\n";
print "                          [--charset cs]\n";
print "                           --subject \"subject line\"\n";
print "                          [--from user\@domain]\n";
print "                          [--admins]\n";
exit(1);
}

