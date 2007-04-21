#!/usr/local/bin/perl
# Output the certificate in PEM format

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});

$data = &cert_pem_data($d);
if ($data) {
	print "Content-type: text/plain\n\n";
	print $data;
	}
else {
	&error($text{'cert_edownload'});
	}
