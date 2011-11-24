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
			$f =~ s/\s+/\n/g;
			push(@got, [ $g, $f ]);
			}
		}
	elsif ($a eq "--use-newkey") {
		$usenewkey = 1;
		}
	elsif ($a eq "--pass") {
		$newpass = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$dname || &usage("Missing --domain parameter");
@got || &usage("No new certificates or keys given");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
$d->{'ssl_cert'} || &usage("Virtual server $dname does not have SSL enabled");
if ($usenewkey) {
	($clash) = grep { $_->[0] eq 'key' } @got;
	$clash && &usage("--use-newkey and --key cannot both be given");
	$d->{'ssl_newkey'} || &usage("--use-newkey can only be given if a ".
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
$passok = &check_passphrase($checkkey, $d->{'ssl_pass'} || $newpass);
$passok || &usage("Private key is password-protected, but either none was entered or the password was incorrect");
$err = &check_cert_key_match($checkcert, $checkkey);
$err && &usage("Certificate problems found : $err");

# XXX nginx support
&$first_print("Installing new SSL files ..");
&obtain_lock_ssl($d);
($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $d->{'web_sslport'});
$changed = 0;
foreach $g (@got) {
	$d->{'ssl_'.$g->[0]} ||= &default_certificate_file($d, $g->[0]);
	&lock_file($d->{'ssl_'.$g->[0]});
	&open_tempfile_as_domain_user($d, SSL, ">".$d->{'ssl_'.$g->[0]});
	&print_tempfile(SSL, $g->[1]);
	&close_tempfile_as_domain_user($d, SSL);
	&set_certificate_permissions($d, $d->{'ssl_'.$g->[0]});
	&unlock_file($d->{'ssl_'.$g->[0]});
	if ($g->[0] eq 'cert') {
		&apache::save_directive("SSLCertificateFile",
			[ $d->{'ssl_cert'} ], $vconf, $conf);
		$changed++;
		}
	elsif ($g->[0] eq 'key') {
		&apache::save_directive("SSLCertificateKeyFile",
			[ $d->{'ssl_key'} ], $vconf, $conf);
		$changed++;
		}
	elsif ($g->[0] eq 'ca') {
		&apache::save_directive("SSLCACertificateFile",
			[ $d->{'ssl_ca'} ], $vconf, $conf);
		$changed++;
		}
	}
if ($changed) {
	&flush_file_lines($virt->{'file'});
	&register_post_action(\&restart_apache, 1);
	}
&release_lock_ssl($d);
&$second_print(".. done");

# Remove old private key and CSR, as they are now installed
if ($usenewkey) {
	&unlink_logged($d->{'ssl_newkey'});
	delete($d->{'ssl_newkey'});
	delete($d->{'ssl_csr'});
	}

# If a passphrase is needed, add it to the top-level Apache config. This is
# done by creating a small script that outputs the passphrase
$d->{'ssl_pass'} = $passok == 2 ? $newpass : undef;
&save_domain_passphrase($d);

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

&run_post_actions();
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
exit(1);
}

