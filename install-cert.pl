#!/usr/local/bin/perl

=head1 install-cert.pl

Replace the SSL certificate or private key for a virtual server.

This command is typically used to install a signed certificate that you
have received from a CA in response to a signing request, generated with
C<generate-cert>. However, it can be used to install any certificate,
private key or CA certificate file into a virtual server.

The server must be specified with the C<--domain> flag, followed by a domain
name. When installing a signed cert, you should use the C<--cert> flag
followed by the path to the certificate file, which will be copied into the
virtual server's home directory. You should also use the C<--use-newkey> flag
to use the key generated at the same time as the CSR.

Alternately, you can install a new matching key and certificate with the
C<--key> and C<--cert> flags. If the key is protected by a passphrase, it
must be specified with the C<--pass> parameter. Any errors in the key or
certificate format or the match between them will cause the command to fail
before the web server configuration is updated.

Finally, for virtual servers that have an SSL certificate that is not in
use, you can delete it with the C<--remove-cert> flag. Be aware that this will
delete the key and certificate files permanently! Once this is done, the
C<generate-cert>, C<install-cert> or C<generate-letsencrypt-cert> API commands
must be used to create a new certificate.

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
	$0 = "$pwd/install-cert.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "install-cert.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--cert" || $a eq "--key" ||
	       $a eq "--csr" || $a eq "--ca") {
		$g = substr($a, 2);
		$f = shift(@ARGV);
		if ($f =~ /^\//) {
			# In some file on the server
			$data = &read_file_contents($f);
			$data || &usage("File $f does not exist");
			push(@got, [ $g, $data ]);
			}
		else {
			# In parameter
			$f =~ s/\r//g;
			$f =~ s/\t+/\n/g;
			push(@got, [ $g, $f ]);
			}
		}
	elsif ($a eq "--use-newkey") {
		$usenewkey = 1;
		}
	elsif ($a eq "--pass") {
		$newpass = shift(@ARGV);
		}
	elsif ($a eq "--remove-cert") {
		$remove = 1;
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
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
$d->{'ssl_same'} && &usage("This server shares it's SSL certificate ".
			   "with another domain");
$remove && (@got || $usenewkey || $newpass) &&
	&usage("--remove-cert cannot be combined with any other options");

# Run the before command
&set_domain_envs($d, "SSL_DOMAIN");
my $merr = &making_changes();
&usage($merr) if ($merr);
&reset_domain_envs($d);

my $oldd = { %$d };
if ($remove) {
	# Validate that the cert isn't in use
	&domain_has_ssl_cert($d) ||
		&usage("Virtual server has no certificate to remove");
	&domain_has_ssl($d) && &usage("Certificate cannot be removed from a ".
				      "virtual server with SSL enabled");
	@same = &get_domain_by("ssl_same", $d->{'id'});
	@same && &usage("Other virtual servers are sharing the certificate ".
			"with this one, so it cannot be removed");
	$d->{'ssl_same'} && &usage("This virtual server is sharing the ".
				   "certificate with another server, so it ".
				   "cannot be removed");
	@beforecerts = &get_all_domain_service_ssl_certs($d);
	@beforecerts && &usage("Other services are using the certificate ".
			       "belonging to this server");

	# Remove the cert and key from the domain object
	&$first_print("Removing SSL certificate and key ..");
	foreach my $k ('cert', 'key', 'chain', 'combined', 'everything') {
		if ($d->{'ssl_'.$k}) {
			&unlink_logged_as_domain_user($d, $d->{'ssl_'.$k});
			delete($d->{'ssl_'.$k});
			}
		}
	delete($d->{'ssl_pass'});
	foreach $f (&domain_features($d), &list_feature_plugins()) {
		&call_feature_func($f, $d, $oldd);
		}
	&save_domain($d);
	&$second_print(".. done");
	}
else {
	# Check if there is a CSR and key to use
	@got || &usage("No new certificates or keys given");
	if ($usenewkey) {
		($clash) = grep { $_->[0] eq 'key' } @got;
		$clash && &usage("--use-newkey and --key cannot both be given");
		$d->{'ssl_newkey'} ||
			&usage("--use-newkey can only be given if a ".
			       "private key and CSR have been created");
		$newkey = &read_file_contents($d->{'ssl_newkey'});
		$newkey || &usage("Private key matching CSR was not found");
		push(@got, [ 'key', $newkey ]);
		}

	# Validate given certs and keys for basic formatting
	foreach $g (@got) {
		$err = &validate_cert_format($g->[1], $g->[0]);
		$err && &usage("Invalid data for $g->[0] : $err");
		}

	# Make sure new cert and key will match
	$checkcert = &read_file_contents($d->{'ssl_cert'});
	$checkkey = &read_file_contents($d->{'ssl_key'});
	foreach $g (@got) {
		if ($g->[0] eq 'cert') {
			$checkcert = $g->[1];
			}
		elsif ($g->[0] eq 'key') {
			$checkkey = $g->[1];
			}
		}
	$checkcert && $checkkey ||
		&usage("Both a cert and key must either already ".
		       "exist, or be supplied on the command line");
	$passok = &check_passphrase($checkkey, $d->{'ssl_pass'} || $newpass);
	$passok || &usage("Private key is password-protected, but either ".
			  "none was entered or the password was incorrect");
	$err = &check_cert_key_match($checkcert, $checkkey);
	$err && &usage("Certificate problems found : $err");
	@beforecerts = &get_all_domain_service_ssl_certs($d);

	# Break SSL linkages that no longer work with this cert
	($gotcert) = grep { $_->[0] eq 'cert' } @got;
	if ($gotcert) {
		$temp = &transname();
		&open_tempfile(TEMP, ">$temp", 0, 1);
		&print_tempfile(TEMP, $gotcert->[1]);
		&close_tempfile(TEMP);
		$newcertinfo = &cert_file_info($temp);
		&break_invalid_ssl_linkages($d, $newcertinfo);
		&unlink_file($temp);
		}

	&$first_print("Installing new SSL files ..");
	$changed = 0;
	foreach $g (@got) {
		my $k = $g->[0] eq 'ca' ? 'chain' : $g->[0];
		$d->{'ssl_'.$k} ||= &default_certificate_file($d, $g->[0]);
		&lock_file($d->{'ssl_'.$k});
		&write_ssl_file_contents($d, $d->{'ssl_'.$k}, $g->[1]);
		&unlock_file($d->{'ssl_'.$k});
		if ($g->[0] ne 'csr') {
			&save_website_ssl_file($d, $g->[0], $d->{'ssl_'.$k});
			}
		}
	&sync_combined_ssl_cert($d);
	&$second_print(".. done");

	# Remove old private key and CSR, as they are now installed
	if ($usenewkey) {
		&unlink_logged($d->{'ssl_newkey'});
		delete($d->{'ssl_newkey'});
		delete($d->{'ssl_csr'});
		}

	# If a passphrase is needed, add it to the top-level Apache config. This
	# is done by creating a small script that outputs the passphrase
	$d->{'ssl_pass'} = $passok == 2 ? $newpass : undef;
	&save_domain_passphrase($d);

	foreach $f (&domain_features($d), &list_feature_plugins()) {
		&call_feature_func($f, $d, $oldd);
		}
	&save_domain($d);

	# Copy SSL directives to domains using same cert
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		$od->{'ssl_cert'} = $d->{'ssl_cert'};
		$od->{'ssl_key'} = $d->{'ssl_key'};
		$od->{'ssl_newkey'} = $d->{'ssl_newkey'};
		$od->{'ssl_csr'} = $d->{'ssl_csr'};
		$od->{'ssl_pass'} = $d->{'ssl_pass'};
		&save_domain_passphrase($od);
		}

	# Update other services using the cert
	&update_all_domain_service_ssl_certs($d, \@beforecerts);
	}

# Update DANE DNS records
&sync_domain_tlsa_records($d);
foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
	&sync_domain_tlsa_records($od);
	}

# Turn off any let's encrypt renewal
&disable_letsencrypt_renewal($d);

&run_post_actions();

# Call the post command
&set_domain_envs($d, "SSL_DOMAIN");
&made_changes();
&reset_domain_envs($d);

&virtualmin_api_log(\@OLDARGV, $d);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Installs a certificate, private key, CSR or CA certificate.\n";
print "\n";
print "virtualmin install-cert --domain name\n";
print "                       [--cert file|data]\n";
print "                       [--key file|data]\n";
print "                       [--ca file|data]\n";
print "                       [--csr file|data]\n";
print "                       [--use-newkey]\n";
print "                       [--pass key-password]\n";
print "                       [--remove-cert]\n";
exit(1);
}

