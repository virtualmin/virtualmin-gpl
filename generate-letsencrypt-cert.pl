#!/usr/local/bin/perl

=head1 generate-letsencrypt-cert.pl

Requests and installs a Let's Encrypt cert for a virtual server.

The server must be specified with the C<--domain> flag, followed by a domain
name. By default the certificate will be the for domain name only, but you
can specify an alternate list of hostnames with the C<--host> flag, which
can be given multiple times.

If the optional C<--renew> flag is given, automatic renewal will be configured
for the specified number of months in the future.

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
	$0 = "$pwd/generate-letsencrypt-cert.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "generate-letsencrypt-cert.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
$size = $config{'key_size'};
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--host") {
		push(@dnames, lc(shift(@ARGV)));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--renew") {
		$renew = shift(@ARGV);
		$renew =~ /^[0-9\.]+$/ && $renew > 0 ||
		    &usage("--renew must be followed by a number of months");
		}
	elsif  ($a eq "--size") {
		$size = shift(@ARGV);
		$size =~ /^\d+$/ ||
		    &usage("--size must be followed by a number of bits");
		}
	elsif ($a eq "--staging") {
		$staging = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
&domain_has_ssl($d) ||
	&usage("Virtual server $dname does not have SSL enabled");
if (!@dnames) {
	@dnames = &get_hostnames_for_ssl($d);
        $custom_dname = undef;
	}
else {
	foreach my $dname (@dnames) {
                my $checkname = $dname;
                $checkname =~ s/^www\.//;
                $err = &valid_domain_name($checkname);
                &usage($err) if ($err);
		}
	}

# Request the cert
&foreign_require("webmin");
$phd = &public_html_dir($d);
&$first_print("Requesting SSL certificate for ".join(" ", @dnames)." ..");
$before = &before_letsencrypt_website($d);
($ok, $cert, $key, $chain) = &request_domain_letsencrypt_cert(
				$d, \@dnames, $staging, $size);
&after_letsencrypt_website($d, $before);
if (!$ok) {
	&$second_print(".. failed : $cert");
	exit(1);
	}
else {
	&$second_print(".. done");

	# Worked .. copy to the domain
	&obtain_lock_ssl($d);
	&$first_print("Copying to webserver configuration ..");
	&install_letsencrypt_cert($d, $cert, $key, $chain);

	# Save renewal state
	$d->{'letsencrypt_dname'} = $custom_dname;
	$d->{'letsencrypt_last'} = time();
	$d->{'letsencrypt_last_success'} = time();
	if ($renew) {
		$d->{'letsencrypt_renew'} = $renew;
		}
	else {
		delete($d->{'letsencrypt_renew'});
		}
	&save_domain($d);

	# Apply any per-domain cert to Dovecot and Postfix
	&sync_dovecot_ssl_cert($d, 1);
	if ($d->{'virt'}) {
		&sync_postfix_ssl_cert($d, 1);
		}

	# For domains that were using the SSL cert on this domain originally but
	# can no longer due to the cert hostname changing, break the linkage
	&break_invalid_ssl_linkages($d);

	# Copy SSL directives to domains using same cert
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		next if (!&domain_has_ssl($od));
		$od->{'ssl_cert'} = $d->{'ssl_cert'};
		$od->{'ssl_key'} = $d->{'ssl_key'};
		$od->{'ssl_newkey'} = $d->{'ssl_newkey'};
		$od->{'ssl_csr'} = $d->{'ssl_csr'};
		$od->{'ssl_pass'} = $d->{'ssl_pass'};
		&save_domain_passphrase($od);
		&save_domain($od);
		}

	# Update DANE DNS records
	&sync_domain_tlsa_records($d);
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		&sync_domain_tlsa_records($od);
		}

	&release_lock_ssl($d);
	&$second_print(".. done");

	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Requests and installs a Let's Encrypt cert for a virtual server.\n";
print "\n";
print "virtualmin generate-letsencrypt-cert --domain name\n";
print "                                    [--host hostname]*\n";
print "                                    [--renew months]\n";
print "                                    [--size bits]\n";
print "                                    [--staging]\n";
exit(1);
}

