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

To use a cloud mail filter, specify the C<--cloud-mail-filter> flag followed by
the name of a provider like MailShark. This will update the MX records for the
domain to point to that provider's filtering servers (which you typically must
sign up for in advance). For some providers Virtualmin also needs to know
a customer ID (used in the MX records), which is set with the
C<--cloud-mail-filter-id> flag. To revert to using only the local mail server,
set the C<--no-cloud-mail-filter> flag.

In Virtualmin Pro, to use a cloud SMTP provider, specify the C<--cloud-smtp>
flag followed by a provider name like C<ses>. The selected provider must have
already been configured in the Virtualmin UI. To revert to direct email 
delivery, use the C<--no-cloud-smtp> flag.

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
	elsif ($a eq "--cloud-mail" || $a eq "--cloud-mail-filter") {
		$cloud = shift(@ARGV);
		}
	elsif ($a eq "--no-cloud-mail" || $a eq "--no-cloud-mail-filter") {
		$cloud = "";
		}
	elsif ($a eq "--cloud-mail-id" || $a eq "--cloud-mail-filter-id") {
		$cloudid = shift(@ARGV);
		}
	elsif ($a eq "--cloud-smtp") {
		$cloudsmtp = shift(@ARGV);
		}
	elsif ($a eq "--no-cloud-smtp") {
		$cloudsmtp = "";
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
@dnames || $all_doms || @users || usage("No domains or users specified");
defined($bcc) || defined($rbcc) || defined($aliascopy) || defined($dependent) ||
    defined($autoconfig) || defined($key) || defined($cloud) ||
    defined($cloudsmtp) || &usage("Nothing to do");

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

# Check cloud mail filter
if ($cloud) {
	@provs = &list_cloud_mail_providers();
	($prov) = grep { $_->{'name'} eq $cloud } @provs;
	$prov || &usage("Valid cloud mail filter providers are : ".
			join(" ", map { $_->{'name'} } @provs));
	if ($prov->{'id'} && !$cloudid) {
		&usage("The cloud mail filter ".$cloud." requires a customer ".
		       "ID to be set with the --cloud-mail-filter-id flag");
		}
	}

# Cloud cloud SMTP provider
if ($cloudsmtp) {
	defined(&list_smtp_clouds) ||
	    &usage("Cloud SMTP providers are not supported on this system");
	($smtp) = grep { $_->{'name'} eq $cloudsmtp } &list_smtp_clouds();
	$smtp || &usage("Cloud SMTP provider $cloudsmtp does not exist");
	$gfunc = "smtpcloud_".$cloudsmtp."_get_state";
	$st = &$gfunc();
	$st->{'ok'} ||
	    &usage("Cloud SMTP provider $cloudsmtp is not configured");
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

	# Enable or disable cloud mail filter
	if (defined($cloud)) {
		local $err;
		local $oldprov = &get_domain_cloud_mail_provider($d);
		if ($prov) {
			if (!$oldprov ||
			    $prov->{'name'} ne $oldprov->{'name'} ||
			    $cloudid ne $d->{'cloud_mail_id'}) {
				# Re-fetch provider object for THIS domain, and
				# apply it
				my @provs = &list_cloud_mail_providers(
						$d, $cloudid);
				($prov) = grep { $_->{'name'} eq $cloud }
					       @provs;
				&$first_print("Configuring MX records for ".
					      "filter $prov->{'name'} ..");
				$err = &save_domain_cloud_mail_provider(
						$d, $prov, $cloudid);
				}
			}
		else {
			if ($oldprov) {
				# Stop using filter provider
				&$first_print("Configuring MX records to ".
					      "deliver to this system ..");
				$err = &save_domain_cloud_mail_provider(
						$d, undef, undef);
				}
			}
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	# Change cloud SMTP provider
	$oldsmtp = $d->{'smtp_cloud'};
	if (defined($cloudsmtp) && $oldsmtp ne $cloudsmtp) {
		my $oldfailed = 0;
		if ($oldsmtp) {
			# Turn off the old provider
			&$first_print(
				"Removing cloud SMTP provider $oldsmtp ..");
			my $sfunc = "smtpcloud_".$oldsmtp."_delete_domain";
			my $info = { 'domain' => $d->{'dom'},
				     'id' => $d->{'smtp_cloud_id'},
				     'location' => $d->{'smtp_cloud_location'}};
			my ($ok, $err) = &$sfunc($d, $info);
			if ($err) {
				&$second_print(".. failed : $err");
				$oldfailed = 1;
				}
			else {
				&$second_print(".. done");
				delete($d->{'smtp_cloud'});
				delete($d->{'smtp_cloud_id'});
				}
			}
		if ($cloudsmtp && !$oldfailed) {
			# Setup the new provider
			&$first_print(
			    "Configuring cloud SMTP provider $cloudsmtp ..");
			my $sfunc = "smtpcloud_".$cloudsmtp."_create_domain";
			my $info = { 'domain' => $d->{'dom'} };
			my ($ok, $id, $location) = &$sfunc($d, $info);
			if ($ok) { 
				$d->{'smtp_cloud'} = $cloudsmtp;
				$d->{'smtp_cloud_id'} = $id;
				$d->{'smtp_cloud_location'} = $location;
				&$second_print(".. done");
				}
			else {
				&$second_print(".. failed : $id");
				}
			}
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
print "                      [--cloud-mail-filter name |\n";
print "                       --no-cloud-mail-filter]\n";
print "                      [--cloud-mail-filter-id number]\n";
print "                      [--cloud-smtp name | --no-cloud-smtp]\n";
exit(1);
}

