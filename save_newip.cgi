#!/usr/local/bin/perl
# Update the IP for one server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_change_ip($d) && &can_edit_domain($d) || &error($text{'newip_ecannot'});

# Validate inputs
&error_setup($text{'newip_err'});
if ($d->{'virt'}) {
	# Changing virtual IP
	&check_ipaddress($in{'ip'}) || &error($text{'newip_eip'});
	$in{'ip'} ne $d->{'ip'} || &error($text{'newip_esame'});
	foreach $ed (&list_domains()) {
		if ($ed->{'virt'} && $e->{'ip'} eq $in{'ip'}) {
			&error(&text('newip_eclash', $d->{'dom'}));
			}
		}
	$in{'ip'} ne &get_default_ip() || &error($text{'newip_edefault'});
	&check_virt_clash($in{'ip'}) && &error($text{'newip_eused'});
	}
if ($d->{'web'}) {
	# Changing webserver port
	foreach $p ("port", "sslport") {
		$in{$p} =~ /^\d+$/ && $in{$p} > 0 && $in{$p} < 65536 ||
			&error($text{'newip_e'.$p});
		}
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'newip_title'}, "");

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN");
$merr = &making_changes();
&reset_domain_envs($d);
&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Work out which domains we need to update (selected and aliases)
@doms = ( $d, &get_domain_by("alias", $d->{'id'}) );
foreach $sd (@doms) {
	if (@doms > 1) {
		&$first_print(&text('newip_dom', $sd->{'dom'}));
		&$indent_print();
		}

	# Do it!
	$oldd = { %$sd };
	if ($sd->{'virt'}) {
		# Change virtual IP
		$sd->{'ip'} = $in{'ip'};
		&try_function("virt", "modify_virt", $sd, $oldd);
		}
	elsif ($in{'ip'}) {
		# Changing shared IP
		$sd->{'ip'} = $in{'ip'};
		}
	if ($sd->{'web'}) {
		$sd->{'web_port'} = $in{'port'};
		$sd->{'web_sslport'} = $in{'sslport'};
		}
	foreach $f (@features) {
		local $mfunc = "modify_$f";
		if ($config{$f} && $sd->{$f}) {
			&try_function($f, $mfunc, $sd, $oldd);
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f}) {
			&plugin_call($f, "feature_modify", $sd, $oldd);
			}
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	&save_domain($sd);
	print $text{'setup_done'},"<p>\n";

	if (@doms > 1) {
		&$outdent_print();
		}
	}

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN");
&made_changes();
&reset_domain_envs($d);
&webmin_log("newip", "domain", $d->{'dom'}, $d);

&ui_print_footer(&domain_footer_link($d));
