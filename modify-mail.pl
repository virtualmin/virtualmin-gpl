#!/usr/local/bin/perl

=head1 modify-mail.pl

Change mail-related settings for some domains

This command can be used to configure BCCing of outgoing email and set the
alias mode for one or more virtual servers. The domains to effect are set
by the C<--domain> flag, which can occur multiple times and must be followed
by a virtual server name. Or you can use C<--user> followed by an 
administrator's username to get all his domains, or C<--all-domains> to modify
all those on the system with mail enabled.

If your mail server supports it, BCCing of relayed email by all users in
the selected domains can  be enabled with the C<--sender-bcc> flag, which must
be followed by an email address. To turn this off again, use the
C<--no-sender-bcc> flag.

Similarly, BCCing of incoming email to all users in the selected domains can
be enabled with the C<--recipient-bcc> flag, which must be followed by an
email address. To turn this off again, use the C<--no-recipient-bcc> flag.

By default, Virtualmin implements mail alias domains with catchall aliases,
which forward all email to addresses in the alias domain to the same address
in the target. However, when using Postfix this prevents email to invalid
addresses in the alias from being bounced at the SMTP conversation stage -
instead, a bounce eamil is sent, which is regarded as poor mail server practice
and can be abused by spammers.

To prevent this, the C<--alias-copy> flag can be used to duplicate Postfix
C<virtual> table entries into the alias domain. To revert to the default
mode, use the C<--alias-catchall> flag.

If supported by your mail server and if the domain has a non-default IP address,
the C<--outgoing-ip> flag can be used to have email sent by addresses in the
domain use its own IP address for outgoing SMTP connections. This can be useful
for separating virtual servers from each other from the point of view of 
other mail servers. To disable this mode, use the C<--no-outgoing-ip> flag.

To enable the Thunderbird auto-configuration URL for this domain, use the 
C<--autoconfig> flag. This allows email clients to find the SMTP and IMAP
username, hostname, port and protocol just based on an email address. To turn
this feature off, use the C<--no-autoconfig> flag.

If DKIM is enabled on the system, by default all virtual servers share the same
key for signing outgoing email. However, the C<--dkim-key> flag followed by a
path contained a PEM-format key can be used to select an alternate custom key
for this domain. Alternately you can revert to the default key with the
C<--default-dkim-key> flag, or generate a new random key with the
C<--generate-dkim-key> flag.

To use a cloud mail filter, specify the C<--cloud-mail> flag followed by
the name of a provider like MailShark. This will update the MX records for the
domain to point to that provider's filtering servers (which you typically must
sign up for in advance). To revert to using only the local mail server, 
set the C<--no-cloud-mail> flag.

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
	$0 = "$pwd/modify-mail.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-mail.pl must be run as root";
	}
@OLDARGV = @ARGV;
$config{'mail'} || &usage("Email is not enabled for Virtualmin");
&require_mail();

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--bcc" || $a eq "--sender-bcc") {
		$bcc = shift(@ARGV);
		}
	elsif ($a eq "--no-bcc" || $a eq "--no-sender-bcc") {
		$bcc = "";
		}
	elsif ($a eq "--recipient-bcc") {
		$rbcc = shift(@ARGV);
		}
	elsif ($a eq "--no-recipient-bcc") {
		$rbcc = "";
		}
	elsif ($a eq "--outgoing-ip") {
		$dependent = 1;
		}
	elsif ($a eq "--no-outgoing-ip") {
		$dependent = 0;
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--alias-copy") {
		$aliascopy = 1;
		$supports_aliascopy ||
			&usage("Your mail server does not support changing the alias mode");
		}
	elsif ($a eq "--alias-catchall") {
		$aliascopy = 0;
		}
	elsif ($a eq "--autoconfig") {
		$autoconfig = 1;
		}
	elsif ($a eq "--no-autoconfig") {
		$autoconfig = 0;
		}
	elsif ($a eq "--dkim-key") {
		$keyfile = shift(@ARGV);
		$key = &read_file_contents($keyfile);
		$key || &usage("DKIM key file $keyfile does not exist");
		$err = &validate_cert_format($key, 'key');
		$err && &usage("DKIM key format is invalid : $err");
		}
	elsif ($a eq "--default-dkim-key") {
		$key = "";
		}
	elsif ($a eq "--generate-dkim-key") {
		($ok, $key) = &generate_dkim_key();
		$ok || &usage("Failed to generate key : $key");
		}
	elsif ($a eq "--cloud-mail") {
		$cloud = shift(@ARGV);
		@provs = &list_cloud_mail_providers();
		($prov) = grep { $_->{'name'} eq $cloud } @provs;
		$prov || &usage("Valid cloud mail filter providers are : ".
				join(" ", map { $_->{'name'} } @provs));
		}
	elsif ($a eq "--no-cloud-mail") {
		$prov = "";
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || @users || usage("No domains or users specified");
defined($bcc) || defined($rbcc) || defined($aliascopy) || defined($dependent) ||
    defined($autoconfig) || defined($key) || defined($prov) ||
    &usage("Nothing to do");

# Get domains to update
if ($all_doms == 1) {
	@doms = grep { $_->{'mail'} } &list_domains();
	}
else {
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@doms = grep { $_->{'mail'} } @doms;
@doms || &usage("None of the selected domains have email enabled");

# Check supported features
if (defined($bcc) && !$supports_bcc) {
	&usage("Sender BCCing of email is not supported on this system");
	}
if (defined($rbcc) && $supports_bcc != 2) {
	&usage("Recipient BCCing of email is not supported on this system");
	}
if (defined($dependent) && !$supports_dependent) {
	&usage("Outgoing IP addresses are not supported on this system");
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();
	$oldd = { %$d };

	# Turn sender BCCing on or off
	$currbcc = &get_domain_sender_bcc($d);
	if (defined($bcc)) {
		if ($bcc) {
			# Change or enable
			&$first_print("BCCing all outgoing email to $bcc ..");
			&save_domain_sender_bcc($d, $bcc);
			&$second_print(".. done");
			}
		elsif (!$bcc && $currbcc) {
			# Turn off
			&$first_print("Turning off outgoing BCCing ..");
			&save_domain_sender_bcc($d, undef);
			&$second_print(".. done");
			}
		}

	# Turn recipient BCCing on or off
	$currbcc = &get_domain_recipient_bcc($d);
	if (defined($rbcc)) {
		if ($rbcc) {
			# Change or enable
			&$first_print("BCCing all incoming email to $rbcc ..");
			&save_domain_recipient_bcc($d, $rbcc);
			&$second_print(".. done");
			}
		elsif (!$rbcc && $currbcc) {
			# Turn off
			&$first_print("Turning off incoming BCCing ..");
			&save_domain_recipient_bcc($d, undef);
			&$second_print(".. done");
			}
		}

	# Change alias mode
	if ($d->{'alias'} && defined($aliascopy)) {
		my $aliasdom = &get_domain($d->{'alias'});
		if ($d->{'aliascopy'} && !$aliascopy) {
			# Switch to catchall
			&$first_print("Switching to catchall for ".
				      "server $d->{'dom'} ..");
			&delete_alias_virtuals($d);
			&create_virtuser({ 'from' => '@'.$d->{'dom'},
				   'to' => [ '%1@'.$aliasdom->{'dom'} ] });
			&$second_print(".. done");
			}
		elsif (!$d->{'aliascopy'} && $aliascopy) {
			# Switch to copy mode
			&$first_print("Switching to alias copy for ".
				      "server $d->{'dom'} ..");
			&copy_alias_virtuals($d, $aliasdom);
			&$second_print(".. done");
			}

		# Save new domain details
		$d->{'aliascopy'} = $aliascopy;
		}

	# Change outgoing IP mode
	if (defined($dependent)) {
		$old_dependent = &get_domain_dependent($d);
		if ($dependent && !$old_dependent) {
			# Turn on sender-dependent IP
			&$first_print("Enabling outgoing IP address for $d->{'dom'} ..");
			&save_domain_dependent($d, 1);
			&$second_print(".. done");
			}
		elsif (!$dependent && $old_dependent) {
			# Turn off sender-dependent IP
			&$first_print("Disabling outgoing IP address for $d->{'dom'} ..");
			&save_domain_dependent($d, 0);
			&$second_print(".. done");
			}
		}

	# Enable or disable autoconfig
	if (!$d->{'alias'} && &domain_has_website($d) && defined($autoconfig)) {
		local $err;
		if ($autoconfig) {
			&$first_print("Enabling mail client ".
				      "auto-configuration for $d->{'dom'} ..");
			$err = &enable_email_autoconfig($d);
			}
		else {
			&$first_print("Disabling mail client ".
				      "auto-configuration for $d->{'dom'} ..");
			$err = &disable_email_autoconfig($d);
			}
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	# Change DKIM key
	if ($d->{'mail'} && !$d->{'alias'} && $config{'dkim_enabled'} &&
	    defined($key)) {
		&save_domain_dkim_key($d, $key);
		}

	# Enable or disable cloud mail provider
	if (defined($prov)) {
		local $err;
		if ($prov) {
			&$first_print("Using cloud mail filter ".
				      "$prov->{'name'} ..");
			$err = &save_domain_cloud_mail_provider($d, $prov);
			}
		else {
			&$first_print("Disabling cloud mail filter ..");
			$err = &save_domain_cloud_mail_provider($d, undef);
			}
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	&save_domain($d);

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes email-related settings for one or more domains.\n";
print "\n";
print "virtualmin modify-mail --domain name | --user name | --all-domains\n";
print "                      [--sender-bcc user\@domain] |\n";
print "                      [--no-sender-bcc]\n";
print "                      [--recipient-bcc user\@domain] |\n";
print "                      [--no-recipient-bcc]\n";
print "                      [--alias-copy] | [--alias-catchall]\n";
print "                      [--outgoing-ip | --no-outgoing-ip]\n";
print "                      [--autoconfig | --no-autoconfig]\n";
print "                      [--dkim-key file | --default-dkim-key |\n";
print "                       --generate-dkim-key]\n";
print "                      [--cloud-mail name | --no-cloud-mail]\n";
exit(1);
}

