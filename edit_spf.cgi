#!/usr/local/bin/perl
# Show SPF settings for this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_dns($d) || &error($text{'spf_ecannot'});
$readonly = &copy_alias_records($d);

# Build a list of Cloud providers or remote DNS servers
my $cloud = $d->{'dns_cloud'} ? $d->{'dns_cloud'} :
	    $d->{'dns_remote'} ? "remote_".$d->{'dns_remote'} :
	    $d->{'provision_dns'} ? 'services' : 'local';
my @opts;
push(@opts, [ 'services', $text{'dns_cloud_services'} ])
	if ($config{'provision_dns'});
foreach my $c (&list_dns_clouds()) {
	my $sfunc = "dnscloud_".$c->{'name'}."_get_state";
	my $s = &$sfunc();
	if ($s->{'ok'} && (&can_dns_cloud($d) || $c->{'name'} eq $cloud)) {
		push(@opts, [ $c->{'name'}, $c->{'desc'} ]);
		}
	}
my $canlocal = 0;
if (defined(&list_remote_dns)) {
	foreach my $r (grep { !$_->{'slave'} } &list_remote_dns()) {
		if ($r->{'id'} == 0) {
			$canlocal = 1;
			}
		else {
			push(@opts, [ "remote_".$r->{'host'},
				      &text('tmpl_dns_remote', $r->{'host'}) ]);
			}
		}
	}
else {
	$canlocal = 1;
	}
if ($canlocal) {
	splice(@opts, 0, 0, [ 'local', $text{'dns_cloud_local'} ]);
	}
my ($found) = grep { $_->[0] eq $cloud } @opts;
&error(&text('spf_ecloudprov', $cloud)) if (!$found);

&ui_print_header(&domain_in($d), $text{'spf_title'}, "", "spf");

print &ui_form_start("save_spf.cgi");
print &ui_hidden("dom", $d->{'id'});
print &ui_hidden("readonly", $readonly);
@tds = ( "width=30%" );
print &ui_table_start($text{'spf_header'}, "width=100%", 2, \@tds);

# Show DNS cloud host or remote DNS provider
print &ui_table_row(&hlink($text{'spf_cloud'}, 'spf_cloud'),
		    &ui_select("cloud", $cloud, \@opts));

# Alias domain own records?
if ($d->{'alias'}) {
	print &ui_table_row(&hlink($text{'spf_aliasdnsmode'}, 'spf_aliasdns'),
		&ui_radio("aliasdns", $d->{'aliasdns'} || 0,
			  [ [ 0, $text{'spf_aliasdns0'} ],
			    [ 1, $text{'spf_aliasdns1'} ] ]));
	}

if (!$readonly) {
	# SPF enabled
	$spf = &get_domain_spf($d);
	$defspf = &default_domain_spf($d);
	print &ui_table_row(&hlink($text{'spf_enabled'}, 'spf_enabled'),
			    &ui_yesno_radio("enabled", $spf ? 1 : 0));

	# Extra a, mx and ip4
	$edspf = $spf || $defspf;
	foreach $t ('a', 'mx', 'ip4', 'ip6', 'include') {
		print &ui_table_row(&hlink($text{'spf_'.$t}, 'spf_'.$t),
			&ui_textarea('extra_'.$t,
				     join("\n", @{$edspf->{$t.':'}}), 3, 40));
		}

	# All mode
	print &ui_table_row(&hlink($text{'spf_all'}, 'template_dns_spfall'),
			    &ui_select("all", $edspf->{'all'},
				       [ [ '', "&lt;$text{'default'}&gt;" ],
					 [ 3, $text{'spf_all3'} ],
					 [ 2, $text{'spf_all2'} ],
					 [ 1, $text{'spf_all1'} ],
					 [ 0, $text{'spf_all0'} ] ]));

	# DKIM status
	my $dkim = &get_dkim_config();
	if ($dkim && $dkim->{'enabled'}) {
		my $def = &can_dkim_domain($d, $dkim) ? $text{'yes'}
						      : $text{'no'};
		print &ui_table_row(&hlink($text{'spf_dkim'}, 'spf_dkim'),
			&ui_radio("dkim", $d->{'dkim_enabled'} eq '1' ? 1 :
					  $d->{'dkim_enabled'} eq '0' ? 0 : 2,
				  [ [ 1, $text{'spf_dkim1'} ],
				    [ 0, $text{'spf_dkim0'} ],
				    [ 2, $text{'spf_dkim2'}.' ('.$def.')' ] ]));
		}

	# TLSA records
	$err = &check_tlsa_support();
	if (!$err) {
		my @trecs = &get_domain_tlsa_records($d);
		print &ui_table_row(&hlink($text{'spf_tlsa'}, 'spf_tlsa'),
				    &ui_yesno_radio("tlsa", @trecs ? 1 : 0));
		}

	# DMARC enabled
	$dmarc = &get_domain_dmarc($d);
	$defdmarc = &default_domain_dmarc($d);
	@dinputs = ("dp", "dpct", "dmarcruf_def", "dmarcruf",
		    "dmarcrua_def", "dmarcrua");
	my $dis0 = &js_disable_inputs(\@dinputs, []);
	my $dis1 = &js_disable_inputs([], \@dinputs);
	my $ddis = $dmarc ? 0 : 1;
	print &ui_table_row(&hlink($text{'spf_denabled'}, 'spf_denabled'),
		    &ui_radio("denabled", $dmarc ? 1 : 0,
			      [ [ 1, $text{'yes'}, "onClick='$dis1'" ],
				[ 0, $text{'no'}, "onClick='$dis0'" ] ]));

	# DMARC policy
	$eddmarc = $dmarc || $defdmarc;
	print &ui_table_row(&hlink($text{'spf_dp'}, 'spf_dp'),
		&ui_select("dp", $eddmarc->{'p'},
			  [ [ "none", $text{'tmpl_dmarcnone'} ],
			    [ "quarantine", $text{'tmpl_dmarcquar'} ],
			    [ "reject", $text{'tmpl_dmarcreject'} ] ],
			  1, 0, 0, $ddis));

	# DMARC percent
	print &ui_table_row(&hlink($text{'spf_dpct'}, 'spf_dpct'),
		&ui_textbox("dpct", $eddmarc->{'pct'} || 100, 5, $ddis)."%");

	# DMARC email addresses
	foreach my $r ('ruf', 'rua') {
		print &ui_table_row(&hlink($text{'spf_dmarc'.$r},
					   'spf_dmarc'.$r),
			&ui_radio("dmarc".$r."_def",
				  $eddmarc->{$r} eq "" ? 1 : 0,
				  [ [ 1, $text{'tmpl_dmarcskip'} ],
				    [ 0, &ui_textbox('dmarc'.$r,
					    $eddmarc->{$r}, 40, $ddis) ] ],
				  $ddis));
		}
	}

# DNSSEC enabled
if (&can_domain_dnssec($d)) {
	print &ui_table_row(&hlink($text{'spf_dnssec'}, 'spf_dnssec'),
		&ui_yesno_radio("dnssec", &has_domain_dnssec($d)));
	}

print &ui_table_end();

# DNSSEC key details
my $r = &require_bind($d);
my $zone = &get_bind_zone($d->{'dom'}, undef, $d);
my $key = &remote_foreign_call($r, "bind8", "get_dnssec_key", $zone);
if ($key) {
	print &ui_hidden_table_start($text{'spf_header2'}, "width=100%",
				     2, "dnssec", 0, \@tds);
	print &ui_table_row($text{'spf_public'},
		&ui_textarea("keyline", $key->{'publictext'}, 4, 80,
			     "off", 0, "readonly"));
	print &ui_table_row($text{'spf_private'},
		&ui_textarea("private", $key->{'privatetext'}, 14, 80,
			     "off", 0, "readonly"));
	$dsrecs = &get_domain_dnssec_ds_records($d);
	if (ref($dsrecs)) {
		$dsrecstext = &format_dns_text_records(
			&dns_records_to_text(@$dsrecs));
		$dsrecsbox = &ui_textarea("dsrecs", $dsrecstext, 2, 80,
					  "off", 0, "readonly");
		$dsrecsbox .= &ui_columns_start([
			$text{'spf_keytag'},
			$text{'spf_alg'},
			$text{'spf_type'},
			$text{'spf_digest'},
			]);
		foreach my $r (@$dsrecs) {
			$dsrecsbox .= &ui_columns_row($r->{'values'});
			}
		$dsrecsbox .= &ui_columns_end();
		}
	else {
		$dsrecsbox = &text('spf_edsrecs', $dsrecs);
		}
	print &ui_table_row($text{'spf_dsrecs'},
		$dsrecsbox);
	print &ui_hidden_table_end();
	}

print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


