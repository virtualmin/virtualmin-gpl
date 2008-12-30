#!/usr/local/bin/perl

=head1 install-cert.pl

Replace the SSL certificate or private key for a virtual server.

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
	else {
		&usage("Unknown parameter $a");
		}
	}
$dname || &usage("Missing --domain parameter");
@got || &usage("One of the --self or --csr parameters must be given");
$d = &get_domain_by("dom", $dname);
$d || &usage("No virtual server named $dname found");
$d->{'ssl'} || &usage("Virtual server $dname does not have SSL enabled");

# Validate given certs and keys
# XXX

# Make sure new cert and key will match
# XXX

# Install them
# XXX
# XXX support newkey

