#!/usr/local/bin/perl
# Copy this domain's cert to Postfix

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_header(&domain_in($d), $text{'copycert_title'}, "");

# Get the Postfix config and cert files
&foreign_require("postfix");
$cfile = &postfix::get_real_value("smtpd_tls_cert_file");
$kfile = &postfix::get_real_value("smtpd_tls_key_file");
$cdir = &postfix::guess_config_dir();
if ($cfile =~ /snakeoil/) {
	# Hack to not use shared cert file on Ubuntu / Debian
	$cfile = $kfile = undef;
	}
$cfile ||= "$cdir/postfix.cert.pem";
$kfile ||= "$cdir/postfix.key.pem";

# Copy cert into those files
&$first_print($text{'copycert_psaving'});
$cdata = &cert_pem_data($d);
$kdata = &key_pem_data($d);
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

# Update config with correct files
&postfix::set_current_value("smtpd_tls_cert_file", $cfile);
&postfix::set_current_value("smtpd_tls_key_file", $kfile);
&$second_print(&text('copycert_dsaved', "<tt>$cfile</tt>", "<tt>$kfile</tt>"));

# Make sure SSL is enabled
&$first_print($text{'copycert_penabling'});
if ($postfix::postfix_version >= 2.3) {
	&postfix::set_current_value("smtpd_tls_security_level", "may");
	}
else {
	&postfix::set_current_value("smtpd_use_tls", "yes");
	}
&$second_print($text{'setup_done'});

# Apply Postfix config
&postfix::reload_postfix();

&webmin_log("copycert", "postfix");

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

