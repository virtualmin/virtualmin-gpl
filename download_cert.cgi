#!/usr/local/bin/perl
# Output the certificate in PEM format

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
$mode = $ENV{'PATH_INFO'} =~ /\.pem$/ ? "pem" :
	$ENV{'PATH_INFO'} =~ /\.p12$/ ? "pkcs12" : undef;
$mode || &error($text{'cert_eformat'});
$data = $mode eq "pem" ? &cert_pem_data($d) :
	$mode eq "pkcs12" ? &cert_pkcs12_data($d) : undef;
$type = $mode eq "pem" ? "text/plain" :
	$mode eq "pkcs12" ? "application/x-pkcs12" : undef;
if ($data) {
	print "Content-type: $type\n\n";
	print $data;
	}
else {
	&error($text{'cert_edownload'});
	}
