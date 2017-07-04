#!/usr/local/bin/perl
# cert_form.cgi
# Show a form for requesting a CSR, or installing a cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin");
&ui_print_header(&domain_in($d), $text{'cert_title'}, "");

# If this domain shares a cert file with another, link to it's page
if ($d->{'ssl_same'}) {
	$same = &get_domain($d->{'ssl_same'});
	print "<b>",&text('cert_same', &show_domain_name($same)),"\n";
	if (&can_edit_domain($same)) {
		print &text('cert_samelink', "cert_form.cgi?dom=$same->{'id'}");
		}
	print "</b><p>\n";
	print $text{'cert_breakdesc'},"<p>\n";
	print &ui_form_start("break_cert.cgi");
	print &ui_hidden("dom", $d->{'id'});
	print &ui_form_end([ [ undef, $text{'cert_break'} ] ]);
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	return;
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
	  [ "chain", $text{'cert_tabchain'}, $prog."chain" ],
	  &can_edit_letsencrypt() ?
		( [ "lets", $text{'cert_tablets'}, $prog."lets" ] ) :
		( ),
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "current", 1);

# Details of current cert
print &ui_tabs_start_tab("mode", "current");
print "$text{'cert_desc2'}<p>\n";
print &ui_table_start($text{'cert_header2'}, undef, 4);

print &ui_table_row($text{'cert_incert'}, "<tt>$d->{'ssl_cert'}</tt>", 3);
print &ui_table_row($text{'cert_inkey'}, "<tt>$d->{'ssl_key'}</tt>", 3);

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
	}

# Other domains using same cert, such as via wildcards or UCC
@others = grep { &domain_has_ssl($_) } &get_domain_by("ssl_same", $d->{'id'});
if (@others) {
	print &ui_table_row($text{'cert_also'},
		&ui_links_row([
			map { $l = &can_config_domain($_) ? "edit_domain.cgi"
							  : "view_domain.cgi";
			      "<a href='$l?dom=$_->{'id'}'>".
			        &show_domain_name($_)."</a>" } @others ]), 3);
	}

# Links to download
@dlinks = (
	"<a href='download_cert.cgi/cert.pem?dom=$in{'dom'}'>".
	"$text{'cert_pem'}</a>",
	"<a href='download_cert.cgi/cert.p12?dom=$in{'dom'}'>".
	"$text{'cert_pkcs12'}</a>",
	);
print &ui_table_row($text{'cert_download'}, &ui_links_row(\@dlinks), 3);
@dlinks = (
	"<a href='download_key.cgi/key.pem?dom=$in{'dom'}'>".
	"$text{'cert_pem'}</a>",
	"<a href='download_key.cgi/key.p12?dom=$in{'dom'}'>".
	"$text{'cert_pkcs12'}</a>",
	);
print &ui_table_row($text{'cert_kdownload'}, &ui_links_row(\@dlinks), 3);
print &ui_table_end();

# Buttons to copy cert to Webmin
if (&can_webmin_cert()) {
	# Build a list of services and their certs, and work out which ones
	# are already copied
	@svcs = &get_all_service_ssl_certs($d, 1);
	%cert_already = ( );
	foreach my $svc (@svcs) {
		if (&same_cert_file($d->{'ssl_cert'}, $svc->{'cert'}) &&
		    (&same_cert_file($chain, $svc->{'ca'}) ||
		     $svc->{'ca'} eq 'none')) {
			$cert_already{$svc->{'id'}} = $svc;
			}
		}

	# Show which services are already using the cert
	if (%cert_already) {
		my @a;
		foreach my $k (keys %cert_already) {
			if ($cert_already{$k}->{'ip'}) {
				push(@a, &text('cert_already_'.$k.'_ip',
					       $cert_already{$k}->{'ip'}));
				}
			elsif ($cert_already{$k}->{'dom'}) {
				push(@a, &text('cert_already_'.$k.'_dom',
					       $cert_already{$k}->{'dom'}));
				}
			else {
				push(@a, $text{'cert_already_'.$k});
				}
			}
		print "<p><b>".&text('cert_already', join(", ",@a)),"</b><p>\n";
		}

	print &ui_hr();
	print &ui_buttons_start();

	# Copy to Webmin button
	&get_miniserv_config(\%miniserv);
	if (!$cert_already{'webmin'}) {
		print &ui_buttons_row(
			"copy_cert.cgi",
			$text{'cert_copy'},
			&text('cert_copydesc', $miniserv{'port'}),
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("webmin", 1));
		}

	# Copy to Usermin, if installed
	if (&foreign_installed("usermin") && !$cert_already{'usermin'}) {
		&foreign_require("usermin");
		&usermin::get_usermin_miniserv_config(\%uminiserv);
		print &ui_buttons_row(
			"copy_cert.cgi",
			$text{'cert_ucopy'},
			&text('cert_ucopydesc', $uminiserv{'port'}),
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("usermin", 1));
		}

	# Copy to Dovecot, if installed
	if (&foreign_installed("dovecot") && !$cert_already{'dovecot'}) {
		print &ui_buttons_row(
			"copy_cert_dovecot.cgi",
			$text{'cert_dcopy'}, $text{'cert_dcopydesc'},
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("dovecot", 1));
		}

	# Copy to Postfix, if in use
	if ($config{'mail_system'} == 0 && !$cert_already{'postfix'}) {
		print &ui_buttons_row(
			"copy_cert_postfix.cgi",
			$text{'cert_pcopy'}, $text{'cert_pcopydesc'},
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("postfix", 1));
		}

	# Copy to ProFTPd, if in use
	if ($config{'ftp'} && !$cert_already{'proftpd'}) {
		print &ui_buttons_row(
			"copy_cert_proftpd.cgi",
			$text{'cert_fcopy'}, $text{'cert_fcopydesc'},
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("proftpd", 1));
		}

	print &ui_buttons_end();
	}

print &ui_tabs_end_tab();

##########################

# CSR generation form
print &ui_tabs_start_tab("mode", "csr");
print "$text{'cert_desc1'}<br>\n";
print "$text{'cert_desc4'}<p>\n";

# Show warning if there is a CSR outstanding
if ($d->{'ssl_csr'} && -r $d->{'ssl_csr'}) {
	print "<b>",&text('cert_csrwarn',
		"<tt>".&home_relative_path($d, $d->{'ssl_csr'})."</tt>",
		"<tt>".&home_relative_path($d, $d->{'ssl_newkey'})."</tt>"),
	      "</b><p>\n";
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
if ($d->{'ssl_key'} && -r $d->{'ssl_key'}) {
	print "<b>",&text('cert_keywarn',
		"<tt>".&home_relative_path($d, $d->{'ssl_cert'})."</tt>",
		"<tt>".&home_relative_path($d, $d->{'ssl_key'})."</tt>"),
	      "</b><p>\n";
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

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

##########################

# New key and cert form
print &ui_tabs_start_tab("mode", "new");
print "$text{'cert_desc3'}<p>\n";

print &ui_form_start("newkey.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header3'}, undef, 2);

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

# Key
print &ui_table_row($text{'cert_newkey'},
	&ui_radio_table("newkey_mode", -r $d->{'ssl_key'} ? 3 : 0,
		[ -r $d->{'ssl_key'} ? ( [ 3, $text{'cert_newkeykeep'} ] ) : ( ),
		  [ 0, $text{'cert_cert0'},
		    &ui_textarea("newkey", undef, 8, 70) ],
		  [ 1, $text{'cert_cert1'},
		    &ui_upload("newkeyupload") ],
		  [ 2, $text{'cert_cert2'},
		    &ui_textbox("newkeyfile", undef, 70)." ".
		    &file_chooser_button("newkeyfile") ] ]));

# Passphrase on key
print &ui_table_row($text{'cert_pass'},
		    &ui_opt_textbox("pass", undef, 20, $text{'cert_nopass'}));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

##########################

# CA certificate form
print &ui_tabs_start_tab("mode", "chain");
print "$text{'cert_desc5'}<p>\n";
print "$text{'cert_desc5a'}<p>\n";

print &ui_form_start("newchain.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header4'}, undef, 2);

# Where cert is stored
print &ui_table_row($text{'cert_chain'},
	&ui_radio("mode", $chain ? 1 : 0,
	  [ [ 0, $text{'cert_chain0'}."<br>" ],
	    &can_chained_cert_path() ?
		  ( [ 1, &text('cert_chain1',
			       &ui_textbox("file", $chain, 50)." ".
			       &file_chooser_button("file"))."<br>" ] ) :
	    $chain ? ( [ 1, &text('cert_chain1', "<tt>$chain</tt>")."<br>" ] ) :
		     ( ),
	    [ 2, &text('cert_chain2',
		       &ui_upload("upload", 50))."<br>" ],
	    [ 3, $text{'cert_chain3'}."<br>\n".
		 &ui_textarea("paste", undef, 8, 70) ] ]));

# Current details
if ($chain) {
	$info = &cert_file_info($chain, $d);
	foreach $i (@cert_attributes) {
		next if ($i eq 'modulus' || $i eq 'exponent');
		if ($info->{$i} && !ref($info->{$i})) {
			print &ui_table_row($text{'cert_c'.$i} ||
					    $text{'cert_'.$i}, $info->{$i});
			}
		}
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_chainok'} ] ]);
print &ui_tabs_end_tab();

# Let's encrypt tab
&foreign_require("webmin");
if (!defined(&webmin::check_letsencrypt)) {
	$err = $text{'cert_ewebminver'};
	}
else {
	$err = &webmin::check_letsencrypt();
	}
print &ui_tabs_start_tab("mode", "lets");
print "$text{'cert_desc8'}<p>\n";

if ($err) {
	print &text('cert_elets', $err),"<p>\n";
	}
else {
	$phd = &public_html_dir($d);
	print &text('cert_letsdesc', "<tt>$phd</tt>"),"<p>\n";

	print &ui_form_start("letsencrypt.cgi");
	print &ui_hidden("dom", $in{'dom'});
	print &ui_table_start(undef, undef, 2);

	# Domain names to request cert for
	@defnames = &get_hostnames_for_ssl($d);
	$dis1 = &js_disable_inputs([ "dname" ], [ ], "onClick");
	$dis0 = &js_disable_inputs([ ], [ "dname" ], "onClick");
	print &ui_table_row($text{'cert_dnamefor'},
		&ui_radio_table("dname_def", 
		      $d->{'letsencrypt_dname'} ? 0 : 1,
		      [ [ 1, $text{'cert_dnamedef'},
			  join("<br>\n", map { "<tt>$_</tt>" } @defnames), $dis1 ],
			[ 0, $text{'cert_dnamesel'},
			  &ui_textarea("dname", join("\n", split(/\s+/, $d->{'letsencrypt_dname'})), 5, 60,
				       undef, $d->{'letsencrypt_dname'} ? 0 : 1), $dis0 ] ]));

	# Setup automatic renewal?
	print &ui_table_row($text{'cert_letsrenew'},
		&ui_opt_textbox("renew", $d->{'letsencrypt_renew'}, 5,
				$text{'cert_letsnotrenew'}));

	# Recent renewal details
	if ($d->{'letsencrypt_last'}) {
		$ago = (time() - $d->{'letsencrypt_last'}) / (30*24*60*60);
		print &ui_table_row($text{'cert_letsage'},
			&text('cert_letsmonths', sprintf("%.2f", $ago)));
		}
	if ($d->{'letsencrypt_last_success'}) {
		print &ui_table_row($text{'cert_lets_success'},
			&make_date($d->{'letsencrypt_last_success'}));
		}
	if ($d->{'letsencrypt_last_failure'} &&
	    $d->{'letsencrypt_last_failure'} > $d->{'letsencrypt_last_success'}) {
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

print &ui_tabs_end(1);
print "</div>";
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
			       [ [ "sha1", "SHA1" ], [ "sha2", "SHA2" ] ]));
}
