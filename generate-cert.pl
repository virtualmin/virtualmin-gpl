#!/usr/local/bin/perl

=head1 generate-cert.pl

Generate a new self-signed cert or CSR for a virtual server.

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
	else {
		&usage();
		}
	}
$dname || &usage("Missing --domain parameter");
$self || $csr || &usage("One of the --self or --csr parameters must be given");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
$d->{'ssl'} || &usage("Virtual server $dname does not have SSL enabled");

if ($self) {
	# Generate the self-signed cert
	# XXX
	$err = &generate_self_signed_cert
	}
else {
	# Generate the CSR
	}

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

