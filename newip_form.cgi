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

# Get reseller IP ranges
@r = split(/\s+/, $d->{'reseller'});
%racl = @r ? &get_reseller_acl($r[0]) : ();

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
	if ($d->{'virt'}) {
		# Already got a private IP, show option to keep
		push(@opts, [ 1, $text{'newip_virtaddr'} ] );
		}
	if ($tmpl->{'ranges'} ne "none" || $racl{'ranges'}) {
		# IP can be alllocated, show option to generate a new one
		push(@opts, [ 2, $text{'newip_virtaddr2'} ]);
		}
	# User can enter IP, but has option to use one that is
	# already active
	push(@opts, [ 3, $text{'newip_virtaddr3'},
		      &ui_textbox("virt", undef, 15)." ".
		      &ui_checkbox("virtalready", 1,
				   $text{'form_virtalready'}) ]);

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
	# Build list of possible shared IPv6 addresses
	@canips = ( );
	push(@canips, [ &get_default_ip6(), $text{'newip_shared'} ]);
	$rd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	if ($rd->{'reseller'}) {
		push(@canips, [ &get_default_ip6($rd->{'reseller'}),
			&text('newip_resel', $rd->{'reseller'}) ]);
		}
	push(@canips, map { [ $_, $text{'newip_shared2'} ] }
			  &list_shared_ip6s());
	if (!$d->{'virt6'} && $d->{'ip6'}) {
		push(@canips, [ $d->{'ip6'}, $text{'newip_current'} ]);
		}
	@canips = map { [ $_->[0], "$_->[0] ($_->[1])" ] }
		      grep { !$done{$_->[0]}++ } @canips;

	# Build options for new IPv6 field
	@opts = ( [ -1, $text{'edit_virt6off'} ],
		  [ 0, $text{'newip_sharedaddr'},
		    &ui_select("ip6", $d->{'ip6'}, \@canips) ] );
	if ($d->{'virt6'}) {
		# Already got a private IP, show option to keep
		push(@opts, [ 1, $text{'newip_virtaddr'} ] );
		}
	if ($tmpl->{'ranges6'} ne "none" || $racl{'ranges6'}) {
		# IP can be alllocated, show option to generate a new one
		push(@opts, [ 2, $text{'newip_virtaddr2'} ]);
		}
	# User can enter IPv6, but has option to use one that is
	# already active
	push(@opts, [ 3, $text{'newip_virtaddr3'},
		      &ui_textbox("virt6", undef, 40)." ".
		      &ui_checkbox("virtalready6", 1,
				   $text{'form_virtalready'}) ]);

	# Show new IPv6 field
	print &ui_table_row($text{'newips_new6'},
		&ui_radio_table("mode6", $d->{'virt6'} ? 1 :
					 $d->{'ip6'} ? 0 : -1, \@opts, 1));
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

	print &ui_table_row($text{'newip_urlport'},
		    &ui_opt_textbox("urlport", $d->{'web_urlport'}, 5,
				$text{'newip_sameport'}));

	print &ui_table_row($text{'newip_urlsslport'},
		    &ui_opt_textbox("urlsslport", $d->{'web_urlsslport'}, 5,
				$text{'newip_sameport'}));
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newips_ok'} ],
		     ($d->{'virt'} || $d->{'virt6'}) && &can_edit_templates() ?
			( [ "convert", $text{'newip_convert'} ] ) : ( )
		   ]);

&ui_print_footer(&domain_footer_link($d));
