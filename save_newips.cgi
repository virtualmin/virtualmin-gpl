#!/usr/local/bin/perl
# Actually update the IPs for multiple servers at once

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newips_ecannot'});
&ReadParse();
&licence_status();

# Validate inputs
&error_setup($text{'newips_err'});
&check_ipaddress($in{'old'}) || &error($text{'newips_eold'});
$in{'new_def'} || &check_ipaddress($in{'new'}) || &error($text{'newips_enew'});
if (defined($in{'old6'})) {
	&check_ip6address($in{'old6'}) || &error($text{'newips6_eold'});
	$in{'new6_def'} || &check_ip6address($in{'new6'}) ||
		&error($text{'newips6_enew'});
	}
if ($in{'new_def'} && (!defined($in{'old6'}) || $in{'new6_def'})) {
	&error($text{'newips_enothing'});
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
my $changes = 0;
foreach $d (@doms) {
	# Update IP addresses, if matching. Alias domains whose target points to
	# the old IP are also updated
	$oldd = { %$d };
	$changed = 0;
	if ($in{'mode'} == 0) {
		# Changing real IP address
		if (!$in{'new_def'} &&
		    ($d->{'ip'} eq $in{'old'} ||
		     $d->{'alias'} &&
		     &get_domain($d->{'alias'})->{'ip'} eq $in{'old'})) {
			$d->{'ip'} = $in{'new'};
			$changed++;
			}
		if ($in{'old6'}) {
			if (!$in{'new6_def'} &&
			    ($d->{'ip6'} eq $in{'old6'} ||
			     $d->{'alias'} &&
			     &get_domain($d->{'alias'})->{'ip6'} eq
			      $in{'old6'})) {
				$d->{'ip6'} = $in{'new6'};
				$changed++;
				}
			}
		}
	else {
		# Changing external IP address
		my $dns_ip = $d->{'dns_ip'} || $d->{'ip'};
		my $dns_ip6 = $d->{'dns_ip6'} || $d->{'ip6'};
		if (!$in{'new_def'} && $dns_ip eq $in{'old'}) {
			$d->{'dns_ip'} = $in{'new'};
			$changed++;
			}
		if ($in{'old6'}) {
			if (!$in{'new6_def'} && $dns_ip6 eq $in{'old6'}) {
				$d->{'dns_ip6'} = $in{'new6'};
				$changed++;
				}
			}
		}
	next if (!$changed);
	$changes++;

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
	&$second_print($text{'setup_done'});

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));
	&reset_domain_envs($d);

	&$outdent_print();
	}

# Tell the user if nothing happened
if (!$changes) {
	print "<b>$text{'newips_none3'}</b><p>\n";
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
if ($in{'masterip'} && !$in{'new_def'}) {
	&$first_print(&text('newips_slaves', $in{'old'}, $in{'new'}));
	&$indent_print();
	&update_dns_slave_ip_addresses($in{'new'}, $in{'old'}, \@doms);
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

&run_post_actions();
&webmin_log("newips", "domains", scalar(@doms),
	    { 'old' => $in{'old'},
	      'new' => $in{'new_def'} ? "" : $in{'new'},
	      'old6' => $in{'old6'},
	      'new6' => $in{'new6_def'} ? "" : $in{'new6'} });

&ui_print_footer("", $text{'index_return'});
