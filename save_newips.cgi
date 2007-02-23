#!/usr/local/bin/perl
# Actually update the IPs

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

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

	$oldd = { %$d };
	$d->{'ip'} = $in{'new'};
	foreach $f (@features) {
		local $mfunc = "modify_$f";
		if ($config{$f} && $d->{$f}) {
			&try_function($f, $mfunc, $d, $oldd);
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f}) {
			&plugin_call($f, "feature_modify", $d, $oldd);
			}
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	&save_domain($d);
	print $text{'setup_done'},"<p>\n";

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	&made_changes();
	&reset_domain_envs($d);

	&$outdent_print();
	}
&run_post_actions();
&webmin_log("newips", "domains", scalar(@doms), { 'old' => $in{'old'},
					          'new' => $in{'new'} });

&ui_print_footer("", $text{'index_return'});
