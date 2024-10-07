#!/usr/local/bin/perl

=head1 install-service-cert.pl

Copy the cert and key from a virtual server to some other service.

The domain to copy the cert from is specified with the C<--domain> flag
followed by a virtual server name. The services (like dovecot, postfix, mysql,
webmin or usermin) to copy it to are set with the C<--service> flag, which can be
given multiple times.

If the C<--add-global> flag is given, the cert will be used as the default
for the selected servers. But if C<--add-domain> is given, it will only be
used for requests to the servers on the domain's hostname or IP address.
When configured, the per-domain cert will be used in favor of the global default
cert for each service, when a client connects using that domain name.

Finally, the C<--remove-domain> flag will remove any per-domain cert for
the service, causing the global default to be used instead.

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
	elsif ($a eq "--add-global") {
		$add_global = 1;
		}
	elsif ($a eq "--add-domain") {
		$add_domain = 1;
		}
	elsif ($a eq "--remove-domain") {
		$remove_domain = 1;
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
&domain_has_ssl_cert($d) ||
	&usage("Virtual server $dname does not have SSL enabled");
@services || &usage("No services to copy the cert to specified");

# Do the specified services exist?
%svcnames = map { $_->{'id'}, $_ } &list_service_ssl_cert_types();
foreach my $s (@services) {
	$svcnames{$s} || &usage("Invalid service $s. Valid services are ".
				join(" ", keys %svcnames));
	}

# Copy to each of them
foreach my $s (@services) {
	$svc = $svcnames{$s};
	if ($add_global) {
		&$first_print("Copying to service $s ..");
		&$indent_print();
		$func = "copy_".$s."_ssl_service";
		&$func($d);
		&$outdent_print();
		&$second_print(".. done");
		}
	elsif ($add_domain) {
		&$first_print("Copying to service $s for $d->{'dom'} ..");
		$func = "sync_".$s."_ssl_cert";
		if (!$svc->{'virt'} && !$svc->{'dom'}) {
			&$second_print(".. service not supported");
			}
		elsif (!$svc->{'dom'} && !$d->{'virt'}) {
			&$second_print(".. service not supported without a private IP");
			}
		else {
			$ok = &$func($d, 1);
			&$second_print($ok == 1 ? ".. done" :
				       $ok == 0 ? ".. failed" :
						  ".. not supported");
			}
		}
	elsif ($remove_domain) {
		&$first_print("Removing from service $s for $d->{'dom'} ..");
		$func = "sync_".$s."_ssl_cert";
		if (!$svc->{'virt'} && !$svc->{'dom'}) {
			&$second_print(".. service not supported");
			}
		else {
			$ok = &$func($d, 0);
			&$second_print($ok == 1 ? ".. done" :
				       $ok == 0 ? ".. failed" :
						  ".. not supported");
			}
		}
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
print "                                --add-global | --add-domain | --remove-domain\n";
print "                               [--service type]+\n";
exit(1);
}

