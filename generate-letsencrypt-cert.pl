#!/usr/local/bin/perl

=head1 generate-letsencrypt-cert.pl

Requests and installs a Let's Encrypt cert for a virtual server.

The server must be specified with the C<--domain> flag, followed by a domain
name. By default the certificate will be the for either previously used
hostnames for Let's Encrypt, or the default SSL hostnames for the domain.
However, you can specify an alternate list of hostnames with the C<--host>
flag, which can be given multiple times. Or you can force use of the default
SSL hostname list with C<--default-hosts>.

If the optional C<--renew> flag is given, automatic renewal will be configured
to occur when the certificate is close to expiry.

To have Virtualmin attempt to verify external Internet connectivity to your
domain before requesting the certificate, use the C<--check-first> flag. This
will detect common errors before your Let's Encrypt service quota is consumed.

To have Virtualmin perform a local validation check of the domain, use the
C<--validate-first> flag. This is automatically enabled when C<--check-first>
is set.

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
	elsif ($a eq "--default-hosts") {
		$defdnames = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--renew") {
		if ($ARGV[0] =~ /^[0-9\.]+$/) {
			# Ignore months flag now
			shift(@ARGV);
			}
		$renew = 1;
		}
	elsif  ($a eq "--size") {
		$size = shift(@ARGV);
		$size =~ /^\d+$/ ||
		    &usage("--size must be followed by a number of bits");
		}
	elsif ($a eq "--staging") {
		$staging = 1;
		}
	elsif ($a eq "--check-first") {
		$connectivity = 1;
		}
	elsif ($a eq "--validate-first") {
		$validation = 1;
		}
	elsif ($a =~ /^--(web|dns)$/) {
		$mode = $1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
if (!@dnames) {
	# No hostnames specified
	if ($defdnames || !$d->{'letsencrypt_dname'}) {
		# Use default hostnames
		@dnames = &get_hostnames_for_ssl($d);
		$custom_dname = undef;
		}
	else {
		# Use hostnames from last time
		@dnames = split(/\s+/, $d->{'letsencrypt_dname'});
		$custom_dname = $d->{'letsencrypt_dname'};
		}
	push(@dnames, "*.".$d->{'dom'}) if ($d->{'letsencrypt_dwild'});
	}
else {
	# Hostnames given
	foreach my $dname (@dnames) {
                my $checkname = $dname;
                $checkname =~ s/^www\.//;
                $checkname =~ s/^\*\.//;
                $err = &valid_domain_name($checkname);
                &usage($err) if ($err);
		}
	$custom_dname = join(" ", @dnames);
	}

# Build a list of the domains being validated
my @cdoms = ( $d );
if (!$d->{'alias'} && !$custom_dname) {
	push(@cdoms, grep { &domain_has_website($_) }
			  &get_domain_by("alias", $d->{'id'}));
	}

# Check for external connectivity first
if ($connectivity && defined(&check_domain_connectivity)) {
	my @errs;
	foreach my $cd (@cdoms) {
		push(@errs, &check_domain_connectivity($cd,
				{ 'mail' => 1, 'ssl' => 1 }));
		}
	if (@errs) {
		print "Connectivity check failed :\n";
		foreach my $e (@errs) {
			print "ERROR: $e->{'desc'} : $e->{'error'}\n";
			}
		exit(1);
		}
	}

# If doing a connectivity check, also do web and DNS validation
if ($connectivity || $validation) {
	my $vcheck = ['web'];
	foreach my $dn (@dnames) {
		$vcheck = ['dns'] if ($dn =~ /\*/);
		}
	my @errs = map { &validate_letsencrypt_config($_, $vcheck) } @cdoms;
	if (@errs) {
		print "Validation check failed :\n";
		foreach my $e (@errs) {
			print "ERROR: $e->{'desc'} : $e->{'error'}\n";
			}
		exit(1);
		}
	}

# Request the cert
&foreign_require("webmin");
$phd = &public_html_dir($d);
&$first_print("Requesting SSL certificate for ".join(" ", @dnames)." ..");
$before = &before_letsencrypt_website($d);
@beforecerts = &get_all_domain_service_ssl_certs($d);
($ok, $cert, $key, $chain) = &request_domain_letsencrypt_cert(
				$d, \@dnames, $staging, $size, $mode);
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
	$d->{'letsencrypt_renew'} = $renew;
	&refresh_ssl_cert_expiry($d);
	&save_domain($d);

	# Update other services using the cert
	&update_all_domain_service_ssl_certs($d, \@beforecerts);

	# For domains that were using the SSL cert on this domain originally but
	# can no longer due to the cert hostname changing, break the linkage
	&break_invalid_ssl_linkages($d);

	# Copy SSL directives to domains using same cert
	foreach $od (&get_domain_by("ssl_same", $d->{'id'})) {
		next if (!&domain_has_ssl_cert($od));
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
print "                                    [--default-hosts]\n";
print "                                    [--renew]\n";
print "                                    [--size bits]\n";
print "                                    [--staging]\n";
print "                                    [--check-first | --validate-first]\n";
print "                                    [--web | --dns]\n";
exit(1);
}

