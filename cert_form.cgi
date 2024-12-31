#!/usr/local/bin/perl
# cert_form.cgi
# Show a form for requesting a CSR, or installing a cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin");
&ui_print_header(&domain_in($d), $text{'cert_title'}, "");
@already = &get_all_domain_service_ssl_certs($d);

# If this domain shares a cert file with another, link to it's page
if ($d->{'ssl_same'}) {
	$same = &get_domain($d->{'ssl_same'});
	print &text('cert_same', &show_domain_name($same)),"\n";
	if (&can_edit_domain($same)) {
		print &text('cert_samelink', "cert_form.cgi?dom=$same->{'id'}");
		}
	print "<p>\n";
	print $text{'cert_breakdesc'},"<p>\n";
	print &ui_form_start("break_cert.cgi");
	print &ui_hidden("dom", $d->{'id'});
	print &ui_form_end([ [ undef, $text{'cert_break'} ] ]);
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	return;
	}

# Get ACME providers, if there are any
my @provs;
if (defined(&list_acme_providers)) {
	@provs = grep { &can_acme_provider($_) ||
			$d->{'letsencrypt_id'} eq $_->{'id'} }
		      &list_acme_providers();
	%known = map { $_->{'id'}, $_ } &list_known_acme_providers();
	foreach my $p (@provs) {
		if (!$p->{'desc'} && $p->{'type'}) {
			$p->{'desc'} = $known{$p->{'type'}}->{'desc'};
			}
		}
	}

# Show tabs
$prog = "cert_form.cgi?dom=$in{'dom'}&mode=";
@tabs = ( [ "current", $text{'cert_tabcurrent'}, $prog."current" ],
	  [ "csr", $text{'cert_tabcsr'}, $prog."csr" ],
	  [ "self", $text{'cert_tabself'}, $prog."self" ],
	  -r $d->{'ssl_newkey'} ?
		( [ "savecsr", $text{'cert_tabsavecsr'}, $prog."savecsr" ] ) :
		( ),
	  [ "new", $text{'cert_tabnew'}, $prog."new" ],
	  &can_edit_letsencrypt() &&
	  (@provs || !defined(&list_acme_providers)) &&
	  (&domain_has_website($d) || $d->{'dns'}) ?
		( [ "lets", $text{'cert_tabacme'}, $prog."lets" ] ) :
		( ),
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "current", 1);

# Details of current cert
print &ui_tabs_start_tab("mode", "current");

if (&domain_has_ssl_cert($d)) {
	print "<p>$text{'cert_desc2'}</p>\n";
	if (!&domain_has_ssl($d)) {
		print &ui_alert_box($text{'cert_hasnossl'}, 'warn');
		}

	print &ui_table_start($text{'cert_header2'}, undef, 4);

	# Cert files
	print &ui_table_row($text{'cert_incert'},
			    "<tt>$d->{'ssl_cert'}</tt>", 3);
	print &ui_table_row($text{'cert_inkey'},
			    "<tt>$d->{'ssl_key'}</tt>", 3);

	# Cert hash type
	$type = &get_ssl_key_type($d->{'ssl_key'}, $d->{'ssl_pass'});
	if ($type) {
		print &ui_table_row($text{'cert_hash'},
			$text{'cert_type_'.$type} || uc($type));
		}



	$info = &cert_info($d);
	$chain = &get_website_ssl_file($d, 'ca');
	
	foreach $i (@cert_attributes) {
		next if ($i eq 'modulus' || $i eq 'exponent');
		$v = $info->{$i};
		if (ref($v)) {
			print &ui_table_row($text{'cert_'.$i},
				&ui_links_row($v), 3);
			}
		elsif ($v) {
			print &ui_table_row($text{'cert_'.$i}, $v);
			}

		# Warn if the CA is wrong
		if ($i eq 'type' && $chain) {
			my $cainfo = &cert_file_info($chain, $d);
			if ($cainfo &&
			    ($cainfo->{'o'} ne $info->{'issuer_o'} ||
			     $cainfo->{'cn'} ne $info->{'issuer_cn'})) {
				print &ui_table_row('',
				    &ui_text_color(
				      "&nbsp;* ".&text('validate_esslcamatch',
					    $cainfo->{'o'}, $cainfo->{'cn'},
					    $info->{'issuer_o'}, $info->{'issuer_cn'}),
				      "danger"), 3);
				}
			}
		}

	# Other domains using same cert, such as via wildcards or UCC
	@others = grep { &domain_has_ssl_cert($_) }
		       &get_domain_by("ssl_same", $d->{'id'});
	if (@others) {
		my @links;
		foreach my $d (@others) {
			my $l = &can_config_domain($d) ? "edit_domain.cgi"
						       : "view_domain.cgi";
			push(@links, "<a href='${l}?dom=$d->{'id'}'>".
				     &show_domain_name($d)."</a>");
			}
		print &ui_table_row($text{'cert_also'},
				    &ui_links_row(\@links));
		}

	# Current usage
	if (@already) {
		my @msgs;
		foreach my $svc (@already) {
			my $m;
			if ($svc->{'ip'}) {
				$m = &text('cert_already_'.$svc->{'id'}.'_ip',
					   $svc->{'ip'});
				}
			elsif ($svc->{'dom'}) {
				$m = &text('cert_already_'.$svc->{'id'}.'_dom',
					   $svc->{'dom'});
				}
			else {
				$m = $text{'cert_already_'.$svc->{'id'}};
				}
			push(@msgs, $m);
			}
		print &ui_table_row($text{'cert_svcs'}, join(", ", @msgs), 3);
		}

	# Links to download
	@dlinks = ( &ui_link("download_cert.cgi/cert.pem?dom=$in{'dom'}",
			     $text{'cert_pem'}),
		    &ui_link("download_cert.cgi/cert.p12?dom=$in{'dom'}",
			     $text{'cert_pkcs12'}),
		  );
	print &ui_table_row($text{'cert_download'}, &ui_links_row(\@dlinks), 3);
	@dlinks = ( &ui_link("download_key.cgi/key.pem?dom=$in{'dom'}",
			     $text{'cert_pem'}),
		    &ui_link("download_key.cgi/key.p12?dom=$in{'dom'}",
			     $text{'cert_pkcs12'}),
		  );
	print &ui_table_row($text{'cert_kdownload'},
			    &ui_links_row(\@dlinks), 3);

	# Can copy as global
	my @gmissing;
	foreach my $st (&list_service_ssl_cert_types()) {
		($a) = grep { !$_->{'d'} && $_->{'id'} eq $st->{'id'}} @already;
		push(@gmissing, $st) if (!$a);
		}

	# Expiry status, if we have it
	my $expiry = &parse_notafter_date($info->{'notafter'});
	if ($expiry) {
		$now = time();
		$future = int(($expiry - $now) / (24*60*60));
		if ($future <= 0) {
			$emsg = "<font color=red>".
				&text('cert_expired', -$future)."</font>";
			}
		elsif ($future < 7) {
			$emsg = "<font color=orange>".
				&text('cert_expiring', $future)."</font>";
			}
		else {
			$emsg = &text('cert_future', $future);
			}
		print &ui_table_row($text{'cert_etime'}, $emsg);
		}

	print &ui_table_row($text{'cert_def'},
		(@gmissing && &can_webmin_cert()) ? $text{'no'} : $text{'yes'}, 3);

	# CA cert details
	if ($chain) {
		print &ui_table_hr();
		my $info = &cert_file_info($chain, $d);
		foreach $i (@cert_attributes) {
			next if ($i eq 'modulus' || $i eq 'exponent');
			if ($info->{$i} && !ref($info->{$i})) {
				print &ui_table_row($text{'cert_c'.$i} ||
					    $text{'cert_'.$i}, $info->{$i});
				}
			}
		}

	print &ui_table_end();

	my $ui_hr;
	print &ui_buttons_start();

	if (!&domain_has_ssl($d) && !@already && !$d->{'ssl_same'}) {
		print &ui_hr() if (!$ui_hr++);
		# Show button to remove SSL cert
		print &ui_buttons_row("remove_cert.cgi",
				      $text{'cert_remove'},
				      $text{'cert_removedesc'},
				      &ui_hidden("dom", $in{'dom'}));
		}

	# Show button to copy to per-service, if any are missing
	my @smissing;
	my @sall;
	foreach my $st (&list_service_ssl_cert_types()) {
		next if (!$st->{'dom'} && !$st->{'virt'});
		next if (!$st->{'dom'} && !$d->{'virt'});
		($a) = grep { $_->{'d'} && $_->{'id'} eq $st->{'id'} } @already;
		push(@sall, $st);
		push(@smissing, $st) if (!$a);
		}
	if (@smissing && &can_webmin_cert()) {
		print &ui_hr() if (!$ui_hr++);
		print &ui_buttons_row(
			"peripcerts.cgi",
			$text{'cert_copyall'},
			&text('cert_copyalldesc',
			    &vui_make_and(map { $_->{'desc'} } @smissing)),
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("enable", 1));
		}
	else {
		# Show button to uninstall all per-service
		print &ui_hr() if (!$ui_hr++);
		print &ui_buttons_row(
			"peripcerts.cgi",
			$text{'cert_removeall'},
			&text('cert_removealldesc',
			    &vui_make_and(map { $_->{'desc'} } @sall)),
			&ui_hidden("dom", $in{'dom'}));
		}

	# Show button to copy to global
	if (@gmissing && &can_webmin_cert()) {
		print &ui_hr() if (!$ui_hr++);
		print &ui_buttons_row(
			"copy_cert_all.cgi",
			$text{'cert_copyall2'},
			&text('cert_copyall2desc',
			    &vui_make_and(map { $_->{'desc'} } @gmissing)),
			&ui_hidden("dom", $in{'dom'}));
		}

	# Show button to copy to the default location
	if (!$d->{'ssl_same'} &&
	    &get_website_ssl_file($d, "key") ne 
	     &default_certificate_file($d, "key")) {
		my $defcert_dir = &default_certificate_file($d, "cert");
		$defcert_dir =~ s|/[^/]+$||;
		print &ui_hr() if (!$ui_hr++);
		print &ui_buttons_row(
			"default_cert.cgi",
			$text{'cert_defaultpath'},
			&text('cert_defaultpathdesc',
			  "<tt>$defcert_dir</tt>"),
			&ui_hidden("dom", $in{'dom'}));
		}

	print &ui_buttons_end();
	}
else {
	# No cert yet! Perhaps a domain without SSL that has no cert yet
	print "<p>",$text{'cert_noneyet'},"</p>\n";
	}

print &ui_tabs_end_tab();

##########################

# CSR generation form
print &ui_tabs_start_tab("mode", "csr");
print "$text{'cert_desc1'}<br>\n";
print "$text{'cert_desc4'}<p>\n";

# Show warning if there is a CSR outstanding
if ($d->{'ssl_csr'} && -r $d->{'ssl_csr'}) {
	print &ui_alert_box(&text('cert_csrwarn',
		"<tt>".&home_relative_path($d, $d->{'ssl_csr'})."</tt>",
		"<tt>".&home_relative_path($d, $d->{'ssl_newkey'})."</tt>"), 'warn');
	}

print &ui_form_start("csr.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header1'}, undef, 2);
&print_cert_fields(0);
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'cert_csrok'} ] ]);
print &ui_tabs_end_tab();

##########################

# Self-signed key generation form
print &ui_tabs_start_tab("mode", "self");
print "$text{'cert_desc6'}<p>\n";

# Show warning if there is an existing key
if ($d->{'ssl_key'} && -r $d->{'ssl_key'} && !&self_signed_cert($d)) {
	print &ui_alert_box(&text('cert_keywarn',
		"<tt>".&home_relative_path($d, $d->{'ssl_cert'})."</tt>",
		"<tt>".&home_relative_path($d, $d->{'ssl_key'})."</tt>"), 'warn');
	}

print &ui_form_start("csr.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("self", 1);
print &ui_table_start($text{'cert_header6'}, undef, 2);
&print_cert_fields(1);
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'cert_self'} ] ]);
print &ui_tabs_end_tab();

##########################

# Apply signed cert form
print &ui_tabs_start_tab("mode", "savecsr");
print "$text{'cert_desc7'}<p>\n";

print &ui_form_start("newkey.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header7'}, undef, 2);

# Cert
print &ui_table_row($text{'cert_cert'},
	&ui_radio_table("cert_mode", 0,
		[ [ 0, $text{'cert_cert0'},
		    &ui_textarea("cert", undef, 8, 70) ],
		  [ 1, $text{'cert_cert1'},
		    &ui_upload("certupload") ],
		  [ 2, $text{'cert_cert2'},
		    &ui_textbox("certfile", undef, 70)." ".
		    &file_chooser_button("certfile") ] ]));

# Use saved key from when CSR was generated
print &ui_hidden("newkey_mode", 4);
print &ui_hidden("newca_mode", 3);

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

##########################

# New key, cert and CA form
print &ui_tabs_start_tab("mode", "new");
print "$text{'cert_desc3'}<p>\n";
print "$text{'cert_desc3a'}<p>\n";

print &ui_form_start("newkey.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header3'}, undef, 2);

# Cert
my $gotcert = $d->{'ssl_cert'} && -r $d->{'ssl_cert'};
print &ui_table_row($text{'cert_cert'},
	&ui_radio_table("cert_mode", $gotcert ? 3 : 0,
		[ $gotcert ? ( [ 3, $text{'cert_newcertkeep'} ] ) : ( ),
		  [ 0, $text{'cert_cert0'},
		    &ui_textarea("cert", undef, 8, 70) ],
		  [ 1, $text{'cert_cert1'},
		    &ui_upload("certupload") ],
		  [ 2, $text{'cert_cert2'},
		    &ui_filebox("certfile", $d->{'ssl_cert'}, 70) ] ]));

# Key
my $gotkey = $d->{'ssl_key'} && -r $d->{'ssl_key'};
print &ui_table_row($text{'cert_newkey'},
	&ui_radio_table("newkey_mode",
		$gotkey ? 3 : 0,
		[ $gotkey ? ( [ 3, $text{'cert_newkeykeep'} ] ) : ( ),
		  [ 0, $text{'cert_cert0'},
		    &ui_textarea("newkey", undef, 8, 70) ],
		  [ 1, $text{'cert_cert1'},
		    &ui_upload("newkeyupload") ],
		  [ 2, $text{'cert_cert2'},
		    &ui_filebox("newkeyfile", $d->{'ssl_key'}, 70) ] ]));

# Passphrase on key
print &ui_table_row($text{'cert_pass'},
		    &ui_opt_textbox("pass", undef, 20, $text{'cert_nopass'}));

# CA cert
my $gotca = $d->{'ssl_chain'} && -r $d->{'ssl_chain'};
print &ui_table_row($text{'cert_newca'},
	&ui_radio_table("newca_mode",
		$gotca ? 3 : 4,
		[ $gotca ? ( [ 3, $text{'cert_newcakeep'} ] ) : ( ),
		  [ 4, $text{'cert_chain0'} ],
		  [ 0, $text{'cert_cert0'},
		    &ui_textarea("newca", undef, 8, 70) ],
		  [ 1, $text{'cert_cert1'},
		    &ui_upload("newcaupload") ],
		  [ 2, $text{'cert_cert2'},
		    &ui_filebox("newcafile", $d->{'ssl_chain'}, 70) ] ]));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

# Let's encrypt tab
if (&can_edit_letsencrypt() && (&domain_has_website($d) || $d->{'dns'})) {
	&foreign_require("webmin");
	$err = &webmin::check_letsencrypt();
	print &ui_tabs_start_tab("mode", "lets");
	print "$text{'cert_desc9'}\n";
	if  (defined(&can_acme_providers) && &can_acme_providers()) {
		print &text('cert_acmelink',
			    'pro/edit_newacmes.cgi'),"\n";
		}
	print "<p>\n";

	if ($err) {
		print &text('cert_elets', $err),"<p>\n";
		if (&master_admin() &&
		    defined(&webmin::get_letsencrypt_install_message)) {
			my $msg = &webmin::get_letsencrypt_install_message(
				"/$module_name/cert_form.cgi?dom=$d->{'id'}&mode=$in{'mode'}",
				$text{'cert_title'});
			print $msg,"<p>\n";
			}
		}
	else {
		$phd = &public_html_dir($d);
		print &text('cert_acmedesc', "<tt>$phd</tt>"),"<p>\n";

		print &ui_form_start("letsencrypt.cgi");
		print &ui_hidden("dom", $in{'dom'});
		print &ui_table_start(undef, undef, 2);

		# Domain names to request cert for
		@defnames = &get_hostnames_for_ssl($d);
		$dis1 = &js_disable_inputs([ "dname" ], [ ], "onClick");
		$dis0 = &js_disable_inputs([ ], [ "dname" ], "onClick");
		$wildcb = "";
		&foreign_require("webmin");
		if ($webmin::letsencrypt_cmd && $d->{'dns'}) {
			$wildcb = "<br>".&ui_checkbox(
				"dwild", 1, $text{'cert_dwild'},
				$d->{'letsencrypt_dwild'});
			}
		print &ui_table_row($text{'cert_dnamefor'},
		    &ui_radio_table("dname_def", 
		      $d->{'letsencrypt_dname'} ? 0 : 1,
		      [ [ 1, $text{'cert_dnamedef'},
			  join("<br>\n", map { "<tt>$_</tt>" } @defnames),
			  $dis1 ],
		        [ 0, $text{'cert_dnamesel'},
			  &ui_textarea("dname",
			    join("\n", split(/\s+/, $d->{'letsencrypt_dname'})),
			     5, 60, undef, $d->{'letsencrypt_dname'} ? 0 : 1).
			  $wildcb, $dis0 ] ]));

		# SSL certificate provider
		if (defined(&list_acme_providers)) {
			print &ui_table_row($text{'cert_acmes'},
				&ui_select("acme", $d->{'letsencrypt_id'},
					[ map { [ $_->{'id'}, $_->{'desc'} ] }
					      @provs ]));
			}
		else {
			print &ui_table_row($text{'cert_acmes'},
				$text{'acme_letsencrypt'});
			}

		# Setup automatic renewal?
		print &ui_table_row($text{'cert_letsrenew2'},
			&ui_yesno_radio("renew",
					$d->{'letsencrypt_renew'} ? 1 : 0));

		# Renewal email option
		print &ui_table_row($text{'cert_letsemail'},
			&ui_radio("email", $d->{'letsencrypt_email'} || 0,
				  [ [ 0, $text{'yes'} ],
				    [ 1, $text{'cert_letsemailerr'} ],
				    [ 2, $text{'no'} ] ]));

		# Test connectivity first?
		if (defined(&check_domain_connectivity)) {
			print &ui_table_row($text{'cert_connectivity'},
				&ui_radio("connectivity", 1,
				  [ [ 2, $text{'cert_connectivity2'} ],
				    [ 1, $text{'cert_connectivity1'} ],
				    [ 0, $text{'cert_connectivity0'} ] ]));
			}

		# Check DNS lookup?
		print &ui_table_row($text{'cert_dnscheck'},
			&ui_yesno_radio("dnscheck",
					!$d->{'letsencrypt_nodnscheck'}));

		# Skip unverifiable hostnames?
		print &ui_table_row($text{'cert_subset'},
			&ui_yesno_radio("subset", $d->{'letsencrypt_subset'}));

		# Certificate type, if supported
		if (&letsencrypt_supports_ec()) {
			print &ui_table_row($text{'cert_hash'},
				&ui_select("ctype", $d->{'letsencrypt_ctype'},
					[ [ "rsa", $text{'cert_type_rsa'} ],
					  [ "ecdsa", $text{'cert_type_ec'} ] ]));
			}

		# Recent renewal details
		if ($d->{'letsencrypt_last'}) {
			$ago = (time() - $d->{'letsencrypt_last'}) /
			       (30*24*60*60);
			print &ui_table_row($text{'cert_letsage'},
				&text('cert_letsmonths', sprintf("%.2f",$ago)));
			}
		if ($d->{'letsencrypt_last_success'}) {
			print &ui_table_row($text{'cert_lets_success'},
				&make_date($d->{'letsencrypt_last_success'}));
			}
		if ($d->{'letsencrypt_last_failure'} &&
		    $d->{'letsencrypt_last_failure'} >
		      $d->{'letsencrypt_last_success'}) {
			print &ui_table_row($text{'cert_lets_failure'},
				"<font color=red>".
				&make_date($d->{'letsencrypt_last_failure'}).
				"</font>");

			if ($d->{'letsencrypt_last_err'}) {
				my $err = $d->{'letsencrypt_last_err'};
				$err =~ s/\t/\n/g;
				print &ui_table_row($text{'cert_lets_freason'},
					"<font color=red>".$err."</font>");
				}
			}

		print &ui_table_end();
		print &ui_form_end([ [ undef, $text{'cert_letsok'} ],
				     [ 'only', $text{'cert_letsonly'} ] ]);
		}
	print &ui_tabs_end_tab();
	}

print &ui_tabs_end(1);

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

# print_cert_fields(show-days)
sub print_cert_fields
{
local ($showdays) = @_;

print &ui_table_row($webmin::text{'ssl_cn'},
		    &ui_textbox("commonName", "www.$d->{'dom'}", 30));

$alts = join("\n", map { "www.".$_->{'dom'} } @others);
print &ui_table_row($text{'cert_alt'},
		    &ui_textarea("subjectAltName", $alts, 5, 30));

print &ui_table_row($webmin::text{'ca_email'},
		    &ui_textbox("emailAddress", $d->{'emailto_addr'}, 30));

print &ui_table_row($webmin::text{'ca_ou'},
		    &ui_textbox("organizationalUnitName", undef, 30));

print &ui_table_row($webmin::text{'ca_o'},
		    &ui_textbox("organizationName", $d->{'owner'}, 30));

print &ui_table_row($webmin::text{'ca_city'} || $text{'cert_city'},
		    &ui_textbox("cityName", undef, 30));

print &ui_table_row($webmin::text{'ca_sp'},
		    &ui_textbox("stateOrProvinceName", undef, 15));

print &ui_table_row($webmin::text{'ca_c'},
		    &ui_textbox("countryName", undef, 2));

$key_size = $config{'key_size'};
$key_size = undef if ($key_size == $webmin::default_key_size);
print &ui_table_row($webmin::text{'ssl_size'},
		    &ui_opt_textbox("size", $key_size, 6,
			    "$text{'default'} ($webmin::default_key_size)").
			" ".$text{'ssl_bits'});

if ($showdays) {
	print &ui_table_row($webmin::text{'ssl_days'},
			    &ui_textbox("days", 1825, 8));
	}

print &ui_table_row($text{'cert_hash'},
		    &ui_select("hash", $config{'cert_type'},
			       [ [ "sha1", "SHA1" ],
				 [ "sha2", "SHA2" ],
				 [ "ecdsa", $text{'cert_type_ec'} ] ]));
}
