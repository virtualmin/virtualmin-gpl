#!/usr/local/bin/perl

=head1 install-service-cert.pl

Copy the cert and key from a virtual server to some other service.

The domain to copy the cert from is specified with the C<--domain> flag
followed by a virtual server name. The services (like dovecot, postfix, webmin
or usermin) to copy it to are set with the C<--service> flag, which can be
given multiple times.

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
	elsif ($a eq "--service") {
		push(@services, shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$dname || &usage("Missing --domain parameter");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
&domain_has_ssl($d) ||
	&usage("Virtual server $dname does not have SSL enabled");
@services || &usage("No services to copy the cert to specified");

# Do the specified services exist?
@svcs = &get_all_service_ssl_certs($d, 0);
%svcnames = map { $_->{'id'}, $_ } @svcs;
foreach my $s (@services) {
	$svcnames{$s} || &usage("Invalid service $s. Valid services are ".
				join(" ", keys %svcnames));
	}

# Copy to each of them
foreach my $s (@services) {
	$svc = $svcnames{$s};
	&$first_print("Copying to service $s ..");
	&$indent_print();
	$func = "copy_".$s."_ssl_service";
	&$func($d);
	&$outdent_print();
	}

&save_domain($d);

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Copy the cert and key from a virtual server to some other service.\n";
print "\n";
print "virtualmin install-service-cert --domain name\n";
print "                               [--service type]+\n";
exit(1);
}

