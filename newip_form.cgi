#!/usr/local/bin/perl
# Show a form for changing the IP address of one server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_change_ip($d) && &can_edit_domain($d) || &error($text{'newip_ecannot'});
&ui_print_header(&domain_in($d), $text{'newip_title'}, "");

if ($d->{'virt'}) {
	print "$text{'newip_desc'}<p>\n";
	}
else {
	print "$text{'newip_desc2'}<p>\n";
	}

print &ui_form_start("save_newip.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'newip_header'}, undef, 2);

print &ui_table_row($text{'newip_old'},
		    "<tt>$d->{'ip'}</tt>");

if ($d->{'virt'}) {
	# Changing a domain's private IP address
	print &ui_table_row($text{'newip_iface'},
			    "<tt>$d->{'iface'}</tt>");

	print &ui_table_row($text{'newips_new'},
			    &ui_textbox("ip", $d->{'ip'}, 20));
	}
else {
	# Changing to/from a reseller IP
	local @canips;
	push(@canips, [ &get_default_ip(), $text{'newip_shared'} ]);
	if ($d->{'reseller'}) {
		push(@canips, [ &get_default_ip($d->{'reseller'}),
			&text('newip_resel', $d->{'reseller'}) ]);
		}
	push(@canips, map { [ $_, $text{'newip_shared2'} ] }
			  &list_shared_ips());
	push(@canips, [ $d->{'ip'}, $text{'newip_current'} ]);
	@canips = map { [ $_->[0], "$_->[0] ($_->[1])" ] }
		      grep { !$done{$_->[0]}++ } @canips;
	if (@canips > 1) {
		print &ui_table_row($text{'newips_new'},
				    &ui_select("ip", $d->{'ip'}, \@canips));
		}
	}

if ($d->{'web'}) {
	$tmpl = &get_template($d->{'template'});
	$d->{'web_port'} ||= $tmpl->{'web_port'} || 80;
	$d->{'web_sslport'} ||= $tmpl->{'web_sslport'} || 443;

	print &ui_table_row($text{'newip_port'},
			    "<tt>$d->{'web_port'}</tt> (HTTP) ".
			    "<tt>$d->{'web_sslport'}</tt> (HTTPS)");

	print &ui_table_row($text{'newip_newport'},
			    &ui_textbox("port", $d->{'web_port'}, 5));

	print &ui_table_row($text{'newip_sslport'},
			    &ui_textbox("sslport", $d->{'web_sslport'}, 5));
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newips_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d));
