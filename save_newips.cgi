#!/usr/local/bin/perl
# Actually update the IPs for multiple servers at once

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newips_ecannot'});
&ReadParse();

# Validate inputs
&error_setup($text{'newips_err'});
&check_ipaddress($in{'old'}) || &error($text{'newips_eold'});
&check_ipaddress($in{'new'}) || &error($text{'newips_enew'});

&ui_print_unbuffered_header(undef, $text{'newips_title'}, "");

# Work out which domains to update
if ($in{'servers_def'}) {
	@doms = grep { !$_->{'virt'} && $_->{'ip'} eq $in{'old'} }
		     &list_domains();
	}
else {
	%servers = map { $_, 1 } split(/\0/, $in{'servers'});
	@doms = grep { $servers{$_->{'id'}} } &list_domains();
	}
if (!@doms) {
	print "<b>",&text('newips_none', $in{'old'}),"</b><p>\n";
	}

# Do each domain, and all active features in it
foreach $d (@doms) {
	&$first_print(&text('newips_dom', $d->{'dom'}));
	&$indent_print();

	$oldd = { %$d };
	$d->{'ip'} = $in{'new'};

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
&run_post_actions();

# Update old default IP
if ($in{'setold'}) {
	$config{'old_defip'} = &get_default_ip();
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	}

&webmin_log("newips", "domains", scalar(@doms), { 'old' => $in{'old'},
					          'new' => $in{'new'} });

&ui_print_footer("", $text{'index_return'});
