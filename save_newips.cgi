#!/usr/local/bin/perl
# Actually update the IPs for multiple servers at once

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newips_ecannot'});
&ReadParse();

# Validate inputs
&error_setup($text{'newips_err'});
&check_ipaddress($in{'old'}) || &error($text{'newips_eold'});
&check_ipaddress($in{'new'}) || &error($text{'newips_enew'});
if (defined($in{'old6'})) {
	&check_ip6address($in{'old6'}) || &error($text{'newips6_eold'});
	&check_ip6address($in{'new6'}) || &error($text{'newips6_enew'});
	}

&ui_print_unbuffered_header(undef, $text{'newips_title'}, "");

# Work out which domains to update
if ($in{'servers_def'}) {
	# Update all virtual servers
	@doms = &list_domains();
	}
else {
	# Update selected virtual servers
	%servers = map { $_, 1 } split(/\0/, $in{'servers'});
	@doms = grep { $servers{$_->{'id'}} } &list_domains();
	}
if (!@doms) {
	print "<b>$text{'newips_none2'}</b><p>\n";
	}

# Do each domain, and all active features in it
foreach $d (@doms) {
	# Update IP addresses, if matching. Alias domains whose target points to
	# the old IP are also updated
	$oldd = { %$d };
	$changed = 0;
	if ($d->{'ip'} eq $in{'old'} ||
	    $d->{'alias'} &&
	    &get_domain($d->{'alias'})->{'ip'} eq $in{'old'}) {
		$d->{'ip'} = $in{'new'};
		$changed++;
		}
	if ($in{'old6'}) {
		if ($d->{'ip6'} eq $in{'old6'} ||
		    $d->{'alias'} &&
		    &get_domain($d->{'alias'})->{'ip6'} eq $in{'old6'}) {
			$d->{'ip6'} = $in{'new6'};
			$changed++;
			}
		}
	next if (!$changed);

	&$first_print(&text('newips_dom', $d->{'dom'}));
	&$indent_print();

	# Run the before command
	&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
	$merr = &making_changes();
	&reset_domain_envs(\%oldd);
	&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

	foreach $f (@features) {
		local $mfunc = "modify_$f";
		if ($config{$f} && $d->{$f}) {
			&try_function($f, $mfunc, $d, $oldd);
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($d->{$f}) {
			&plugin_call($f, "feature_modify", $d, $oldd);
			}
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	&save_domain($d);
	print $text{'setup_done'},"<p>\n";

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));
	&reset_domain_envs($d);

	&$outdent_print();
	}

# Update old default IP
if ($in{'setold'}) {
	$config{'old_defip'} = &get_default_ip();
	$config{'old_defip6'} = &get_default_ip6();
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	}

# Update master IP on slave zones
if ($in{'masterip'}) {
	&require_bind();
	$oldmasterip = $bconfig{'this_ip'} ||
		       &to_ipaddress(&get_system_hostname());
	@bdoms = grep { $_->{'dns'} && $_->{'dns_slave'} ne '' } @doms;
	if ($oldmasterip eq $in{'old'} && @bdoms) {
		&$first_print(&text('newips_slaves', $in{'old'}, $in{'new'}));
		if ($bconfig{'this_ip'} eq $in{'old'}) {
			$bconfig{'this_ip'} = $in{'new'};
			&save_module_config(\%bconfig, "bind8");
			}
		&$indent_print();
		foreach $d (@bdoms) {
			$oldslaves = $d->{'dns_slave'};
			&delete_zone_on_slaves($d);
			&create_zone_on_slaves($d, $oldslaves);
			}
		&$outdent_print();
		&$second_print($text{'setup_done'});
		}
	}

&run_post_actions();
&webmin_log("newips", "domains", scalar(@doms), { 'old' => $in{'old'},
					          'new' => $in{'new'} });

&ui_print_footer("", $text{'index_return'});
