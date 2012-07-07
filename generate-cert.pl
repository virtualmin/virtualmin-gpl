#!/usr/local/bin/perl

=head1 generate-cert.pl

Generate a new self-signed cert or CSR for a virtual server.

A self-signed certificate is one that can be used immediately to protect
a virtual server with SSL, but is not validated by a certificate authority.
As such, browsers will typically warn the user that it cannot be validated,
and thus provides not protection against man-in-the-middle attacks. All 
Virtualmin server with SSL enabled have a self-signed cert by default, but
this command can be used to create a new one, perhaps with different hostnames
or more information about the owner.

The virtual server to create a cert for must be specified with the 
C<--domain> parameter, followed by a domain name. You must also supply the
C<--self> flag, to indicate that a self-signed cert is being created.
Additional details about the certificate's owner can be set with the following
optional flags :

C<--o> - Followed by the name of the organization or person who owns the domain.

C<--ou> - Sets the department or group within the organization. 

C<--c> - Sets the country.

C<--st> - Sets the state or province.

C<--l> - Sets the city or locality.

C<--email> - Sets the contact email address.

C<--cn> - Specifies the domain name in the certificate.

When run, the command will create certificate and private key files, and
configure Apache to use them. Any existing files will be overwritten.

This command can also create a CSR, or certificate signing request. This is
a file that is sent to a certificate authority like Verisign or Thawte along
with payment and a request to validate the owner of a domain. The command is
run in the same way, except that the C<--csr> flag is used instead of C<--self>,
and the generated files are different.

Once the CA has validated the certificate, they will send you back a signed
cert that can be installed using the C<--install-cert> command or the
Virtualmin web interface.

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
	$0 = "$pwd/generate-cert.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "generate-cert.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--self") {
		$self = 1;
		}
	elsif ($a eq "--csr") {
		$csr = 1;
		}
	elsif ($a eq "--cn" || $a eq "--c" || $a eq "--st" || $a eq "--l" ||
	       $a eq "--o" || $a eq "--ou" || $a eq "--email") {
		$subject{substr($a, 2)} = shift(@ARGV);
		}
	elsif ($a eq "--alt") {
		push(@alts, shift(@ARGV));
		}
	elsif ($a eq "--size") {
		$size = shift(@ARGV);
		}
	elsif ($a eq "--days") {
		$days = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$dname || &usage("Missing --domain parameter");
$self || $csr || &usage("One of the --self or --csr parameters must be given");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
&domain_has_ssl($d) ||
	&usage("Virtual server $dname does not have SSL enabled");

if ($self) {
	# Break SSL linkages that no longer work with this cert
	local $newcert = { 'cn' => $subject{'cn'} || "*.$d->{'dom'}",
			   'alt' => \@alts };
	&break_invalid_ssl_linkages($d, $newcert);

	# Generate the self-signed cert, over-writing the existing file
	&$first_print("Generating new self-signed certificate ..");
	$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
	$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
	&lock_file($d->{'ssl_cert'});
	&lock_file($d->{'ssl_key'});
	&obtain_lock_ssl($d);
	$err = &generate_self_signed_cert(
		$d->{'ssl_cert'}, $d->{'ssl_key'}, $size, $days,
		$subject{'c'},
		$subject{'st'},
		$subject{'l'},
		$subject{'o'},
		$subject{'ou'},
		$subject{'cn'} || "*.$d->{'dom'}",
		$subject{'email'} || $d->{'emailto_addr'},
		\@alts,
		$d,
		);
	if ($err) {
		&$second_print(".. failed : $err");
		exit(1);
		}
	&set_certificate_permissions($d, $d->{'ssl_cert'});
	&set_certificate_permissions($d, $d->{'ssl_key'});
	&$second_print(".. done");

	# Remove any SSL passphrase on this domain
	&$first_print("Configuring webserver to use it ..");
	$d->{'ssl_pass'} = undef;
	&save_domain_passphrase($d);
	&save_domain($d);
	&release_lock_ssl($d);
	&unlock_file($d->{'ssl_key'});
	&unlock_file($d->{'ssl_cert'});

	# Remove SSL passphrase on other domains sharing the cert
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		&obtain_lock_ssl($od);
                $od->{'ssl_pass'} = undef;
                &save_domain_passphrase($od);
                &save_domain($od);
		&release_lock_ssl($od);
                }
	&$second_print(".. done");

	# Re-start Apache
	&register_post_action(\&restart_website_server, $d, 1);
	&run_post_actions();
	}
else {
	# Generate the CSR
	&$first_print("Generating new certificate signing request ..");
	$d->{'ssl_csr'} ||= &default_certificate_file($d, 'csr');
	$d->{'ssl_newkey'} ||= &default_certificate_file($d, 'newkey');
	&lock_file($d->{'ssl_csr'});
	&lock_file($d->{'ssl_newkey'});
	$err = &generate_certificate_request(
		$d->{'ssl_csr'}, $d->{'ssl_newkey'}, undef, 1825,
		$subject{'c'},
		$subject{'st'},
		$subject{'l'},
		$subject{'o'},
		$subject{'ou'},
		$subject{'cn'} || "*.$d->{'dom'}",
		$subject{'email'} || $d->{'emailto_addr'},
		\@alts,
		$d,
		);
	if ($err) {
		&$second_print(".. failed : $err");
		exit(1);
		}
	&set_certificate_permissions($d, $d->{'ssl_csr'});
	&set_certificate_permissions($d, $d->{'ssl_newkey'});
	&unlock_file($d->{'ssl_newkey'});
	&unlock_file($d->{'ssl_csr'});
	&$second_print(".. done");

	# Save the domain
	&save_domain($d);
	&run_post_actions();
	}

&virtualmin_api_log(\@OLDARGV, $d);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Generates a new self-signed certificate or CSR.\n";
print "\n";
print "virtualmin generate-cert --domain name\n";
print "                         --self | --csr\n";
print "                        [--size bits]\n";
print "                        [--days expiry-days]\n";
print "                        [--cn domain-name]\n";
print "                        [--c country]\n";
print "                        [--st state]\n";
print "                        [--l city]\n";
print "                        [--o organization]\n";
print "                        [--ou organization-unit]\n";
print "                        [--email email-address]\n";
print "                        [--alt alternate-domain-name]*\n";
exit(1);
}

