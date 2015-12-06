#!/usr/local/bin/perl
# Copy this domain's cert to ProFTPd

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_header(&domain_in($d), $text{'copycert_title'}, "");

# Get the ProFTPd config and cert files
&foreign_require("proftpd");
&proftpd::lock_proftpd_files();
$conf = &proftpd::get_config();
$cfile = &proftpd::find_directive("TLSRSACertificateFile", $conf);
$kfile = &proftpd::find_directive("TLSRSACertificateKeyFile", $conf);
$cafile = &proftpd::find_directive("TLSCACertificateFile", $conf);
$cdir = $proftpd::config{'proftpd_conf'};
$cdir =~ s/\/[^\/]+$//;
$cfile ||= "$cdir/proftpd.cert";
$kfile ||= "$cdir/proftpd.key";
$cafile ||= "$cdir/proftpd.ca";

# Copy cert into those files
$casrcfile = &get_website_ssl_file($d, "ca");
&$first_print($casrcfile ? $text{'copycert_fsaving2'}
			 : $text{'copycert_fsaving'});
$cdata = &cert_pem_data($d);
$kdata = &key_pem_data($d);
$cadata = $casrcfile ? &read_file_contents($casrcfile) : undef;
$cdata || &error($text{'copycert_ecert'});
$kdata || &error($text{'copycert_ekey'});
&open_lock_tempfile(CERT, ">$cfile");
&print_tempfile(CERT, $cdata,"\n");
&close_tempfile(CERT);
&set_ownership_permissions(undef, undef, 0700, $cfile);
if ($cfile eq $kfile) {
	&open_lock_tempfile(KEY, ">>$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	}
else {
	&open_lock_tempfile(KEY, ">$kfile");
	&print_tempfile(KEY, $kdata,"\n");
	&close_tempfile(KEY);
	&set_ownership_permissions(undef, undef, 0700, $kfile);
	}
if ($cadata) {
	&open_lock_tempfile(CA, ">$cafile");
	&print_tempfile(CA, $cadata,"\n");
	&close_tempfile(CA);
	&set_ownership_permissions(undef, undef, 0750, $cafile);
	}

# Update config with correct files
&proftpd::save_directive("TLSRSACertificateFile", [ $cfile ], $conf, $conf);
&proftpd::save_directive("TLSRSACertificateKeyFile", [ $kfile ], $conf, $conf);
&proftpd::save_directive("TLSCACertificateFile", $cadata ? [ $cafile ] : [ ],
			 $conf, $conf);
&$second_print(&text('copycert_dsaved', "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_fenabling'});
&proftpd::save_directive("TLSEngine", [ "on" ], $conf, $conf);
&flush_file_lines();
&proftpd::unlock_proftpd_files();
&register_post_action(\&restart_proftpd);
&$second_print($text{'setup_done'});

&run_post_actions();
&webmin_log("copycert", "proftpd");

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

