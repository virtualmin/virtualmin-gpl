#!/usr/local/bin/perl
# Save the DKIM key for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'domdkim_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_mail() || &error($text{'edit_ecannot'});

# Validate inputs
if ($in{'key_def'} == 0) {
	# Manual key
	$in{'key'} =~ s/\r//g;
	$err = &validate_cert_format($in{'key'}, 'key');
	&error(&text('domdkim_ekey', $err)) if ($err);
	$key = $in{'key'};
	}
elsif ($in{'key_def'} == 2) {
	# Generate key
	($ok, $key) = &generate_dkim_key();
	$ok || &error(&text('domdkim_egen', $key));
	}
else {
	$key = undef;
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'mail_title'}, "");

# Update the key
$err = &save_domain_dkim_key($d, $key);
&save_domain($d);
&run_post_actions();

# All done
&webmin_log("domdkim", "domain", $d->{'dom'});
&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

