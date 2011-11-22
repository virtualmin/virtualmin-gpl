#!/usr/local/bin/perl
# Show a form for changing the IP address of one server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$tmpl = &get_template($d->{'template'});
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
print &ui_table_start($text{'newip_header'}, "width=100%", 2, [ "width=30%" ]);

# Old IP
print &ui_table_row($text{'newip_old'},
		    "<tt>$d->{'ip'}</tt>");

# Virtual interface
if ($d->{'virt'}) {
	print &ui_table_row($text{'newip_iface'},
			    "<tt>$d->{'iface'}</tt>");
	}

if ($config{'all_namevirtual'} && &can_use_feature("virt")) {
	# Always name-based, but IP can be changed
	print &ui_table_row($text{'newips_new'},
		&ui_textbox("ip", $d->{'ip'}, 15));
	}
elsif (&can_use_feature("virt")) {
	# Build list of possible shared IPs
	@canips = ( );
	push(@canips, [ &get_default_ip(), $text{'newip_shared'} ]);
	$rd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	if ($rd->{'reseller'}) {
		push(@canips, [ &get_default_ip($rd->{'reseller'}),
			&text('newip_resel', $rd->{'reseller'}) ]);
		}
	push(@canips, map { [ $_, $text{'newip_shared2'} ] }
			  &list_shared_ips());
	if (!$d->{'virt'}) {
		push(@canips, [ $d->{'ip'}, $text{'newip_current'} ]);
		}
	@canips = map { [ $_->[0], "$_->[0] ($_->[1])" ] }
		      grep { !$done{$_->[0]}++ } @canips;

	# Build options for new IP field
	@opts = ( [ 0, $text{'newip_sharedaddr'},
		    &ui_select("ip", $d->{'ip'}, \@canips) ] );
	%racl = $d->{'reseller'} ? &get_reseller_acl($d->{'reseller'}) : ();
	if ($d->{'virt'}) {
		# Already got a private IP
		push(@opts, [ 1, $text{'newip_virtaddr'} ] );
		}
	elsif ($tmpl->{'ranges'} ne "none" || $racl{'ranges'}) {
		# IP can be alllocated
		push(@opts, [ 1, $text{'newip_virtaddr2'} ]);
		}
	else {
		# User must enter IP, but has option to use one that is
		# already active
		push(@opts, [ 1, $text{'newip_virtaddr3'},
			      &ui_textbox("virt", undef, 15)." ".
			      &ui_checkbox("virtalready", 1,
					   $text{'form_virtalready'}) ]);
		}

	# Show new IP field
	print &ui_table_row($text{'newips_new'},
		&ui_radio_table("mode", $d->{'virt'} ? 1 : 0, \@opts, 1));
	}

if (&supports_ip6() && $d->{'virt6'}) {
	# Current IPv6 addres
	print &ui_table_row($text{'newip_old6'},
			    "<tt>$d->{'ip6'}</tt>");
	}

if (&supports_ip6() && &can_use_feature("virt6")) {
	# New IPv6 address
	@ip6opts = ( [ 0, $text{'newip_virt6off'} ] );
	if ($d->{'virt6'}) {
		# Already active, so just show
		push(@ip6opts, [ 1, $text{'newip_virt6addr'} ]);
		}
	elsif ($tmpl->{'ranges6'} ne 'none') {
		# Can allocate
		push(@ip6opts, [ 1, $text{'newip_virt6addr2'} ]);
		}
	else {
		# Manually enter, or already active
		push(@ip6opts, [ 1, $text{'newip_virt6addr3'},
				 &ui_textbox("ip6", $d->{'ip6'}, 30) ]);
		}
	print &ui_table_row($text{'newip_new6'},
		&ui_radio_table("mode6", $d->{'virt6'} ? 1 : 0,
				\@ip6opts, 1));
	}

# HTTP and HTTPS ports
$p = &domain_has_website($d);
if ($p) {
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
print &ui_form_end([ [ "ok", $text{'newips_ok'} ],
		     $d->{'virt'} && &can_edit_templates() ?
			( [ "convert", $text{'newip_convert'} ] ) : ( )
		   ]);

&ui_print_footer(&domain_footer_link($d));
