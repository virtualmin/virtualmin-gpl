#!/usr/local/bin/perl

=head1 generate-cert.pl

Generate a new self-signed cert or CSR for a virtual server.

XXX

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
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
	else {
		&usage("Unknown parameter $a");
		}
	}
$dname || &usage("Missing --domain parameter");
$self || $csr || &usage("One of the --self or --csr parameters must be given");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
$d->{'ssl'} || &usage("Virtual server $dname does not have SSL enabled");

if ($self) {
	# Generate the self-signed cert, over-writing the existing file
	&$first_print("Generating new self-signed certificate ..");
	$d->{'ssl_cert'} ||= &default_certificate_file($d, 'cert');
	$d->{'ssl_key'} ||= &default_certificate_file($d, 'key');
	&lock_file($d->{'ssl_cert'});
	&lock_file($d->{'ssl_key'});
	&obtain_lock_ssl($d);
	$err = &generate_self_signed_cert(
		$d->{'ssl_cert'}, $d->{'ssl_key'}, undef, 1825,
		$subject{'c'},
		$subject{'st'},
		$subject{'l'},
		$subject{'o'},
		$subject{'ou'},
		$subject{'cn'} || "*.$d->{'dom'}",
		$subject{'email'} || $d->{'emailto'},
		\@alts,
		);
	if ($err) {
		&$second_print(".. failed : $err");
		exit(1);
		}
	&set_certificate_permissions($d, $d->{'ssl_cert'});
	&set_certificate_permissions($d, $d->{'ssl_key'});
	&$second_print(".. done");

	# Remove any SSL passphrase on this domain
	&$first_print("Configuring Apache to use it ..");
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
	&register_post_action(\&restart_apache, 1);
	&run_post_actions();
	}
else {
	# Generate the CSR
	&$first_print("Generating new self-signed certificate ..");
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
		$subject{'email'} || $d->{'emailto'},
		\@alts,
		);
	if ($err) {
		&$second_print(".. failed : $err");
		exit(1);
		}
	&set_certificate_permissions($d, $d->{'ssl_csr'});
	&set_certificate_permissions($d, $d->{'ssl_newkey'});
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
print "usage: generate-cert.pl --domain name\n";
print "                        --self | --csr\n";
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

