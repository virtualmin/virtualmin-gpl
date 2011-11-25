#!/usr/local/bin/perl
# cert_form.cgi
# Show a form for requesting a CSR, or installing a cert

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&foreign_require("webmin", "webmin-lib.pl");
&ui_print_header(&domain_in($d), $text{'cert_title'}, "");

# If this domain shares a cert file with another, link to it's page
if ($d->{'ssl_same'}) {
	$same = &get_domain($d->{'ssl_same'});
	print "<b>",&text('cert_same', &show_domain_name($same)),"\n";
	if (&can_edit_domain($same)) {
		print &text('cert_samelink', "cert_form.cgi?dom=$same->{'id'}");
		}
	print "</b><p>\n";
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	return;
	}

# Show tabs
$prog = "cert_form.cgi?dom=$in{'dom'}&mode=";
@tabs = ( [ "current", $text{'cert_tabcurrent'}, $prog."current" ],
	  [ "csr", $text{'cert_tabcsr'}, $prog."csr" ],
	  [ "self", $text{'cert_tabself'}, $prog."self" ],
	  [ "new", $text{'cert_tabnew'}, $prog."new" ],
	  [ "chain", $text{'cert_tabchain'}, $prog."new" ],
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "current", 1);

# Details of current cert
print &ui_tabs_start_tab("mode", "current");
print "$text{'cert_desc2'}<p>\n";
print &ui_table_start($text{'cert_header2'}, undef, 4);
$info = &cert_info($d);
foreach $i (@cert_attributes) {
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
@others = grep { $_->{'ssl_cert'} } &get_domain_by("ssl_same", $d->{'id'});
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
	print &ui_hr();
	print &ui_buttons_start();

	# Copy to Webmin button
	&get_miniserv_config(\%miniserv);
	print &ui_buttons_row(
		"copy_cert.cgi",
		$text{'cert_copy'},
		&text('cert_copydesc', $miniserv{'port'}),
		&ui_hidden("dom", $in{'dom'}).
		&ui_hidden("webmin", 1));

	# Copy to Usermin, if installed
	if (&foreign_installed("usermin")) {
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
	if (&foreign_installed("dovecot")) {
		print &ui_buttons_row(
			"copy_cert_dovecot.cgi",
			$text{'cert_dcopy'}, $text{'cert_dcopydesc'},
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("dovecot", 1));
		}

	# Copy to Postfix, if in use
	if ($config{'mail_system'} == 0) {
		print &ui_buttons_row(
			"copy_cert_postfix.cgi",
			$text{'cert_pcopy'}, $text{'cert_pcopydesc'},
			&ui_hidden("dom", $in{'dom'}).
			&ui_hidden("postfix", 1));
		}

	print &ui_buttons_end();
	}

print &ui_tabs_end_tab();

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
&print_cert_fields();
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'cert_csrok'} ] ]);
print &ui_tabs_end_tab();

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
&print_cert_fields();
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'cert_self'} ] ]);
print &ui_tabs_end_tab();

# New key and cert form, for using existing key
print &ui_tabs_start_tab("mode", "new");
print "$text{'cert_desc3'}<p>\n";

print &ui_form_start("newkey.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'cert_header3'}, undef, 2);

# Cert
print &ui_table_row($text{'cert_cert'},
		    &ui_textarea("cert", undef, 8, 70)."<br>\n".
		    "<b>$text{'cert_upload'}</b>\n".
		    &ui_upload("certupload"));

# Key
if (-r $d->{'ssl_newkey'}) {
	$newkey = &read_file_contents_as_domain_user($d, $d->{'ssl_newkey'});
	}
print &ui_table_row($text{'cert_newkey'},
		    &ui_textarea("newkey", $newkey, 8, 70)."<br>\n".
		    "<b>$text{'cert_upload'}</b>\n".
		    &ui_upload("newkeyupload"));

# Passphrase on key
print &ui_table_row($text{'cert_pass'},
		    &ui_opt_textbox("pass", undef, 20, $text{'cert_nopass'}));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_newok'} ] ]);
print &ui_tabs_end_tab();

# CA certificate form
$chain = &get_website_ssl_file($d, 'ca');
print &ui_tabs_start_tab("mode", "chain");
print "$text{'cert_desc5'}<p>\n";

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
		if ($info->{$i} && !ref($info->{$i})) {
			print &ui_table_row($text{'cert_c'.$i} ||
					    $text{'cert_'.$i}, $info->{$i});
			}
		}
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'cert_chainok'} ] ]);
print &ui_tabs_end_tab();

print &ui_tabs_end(1);

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

sub print_cert_fields
{
print &ui_table_row($webmin::text{'ssl_cn'},
		    &ui_textbox("commonName", "www.$d->{'dom'}", 30));

$alts = join("\n", map { "www.".$_->{'dom'} } @others);
print &ui_table_row($text{'cert_alt'},
		    &ui_textarea("subjectAltName", $alts, 5, 30));

print &ui_table_row($webmin::text{'ca_email'},
		    &ui_textbox("emailAddress", $d->{'emailto'}, 30));

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

print &ui_table_row($webmin::text{'ssl_days'},
		    &ui_textbox("days", 1825, 8));


}
