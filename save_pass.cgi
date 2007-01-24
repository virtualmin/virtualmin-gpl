#!/usr/local/bin/perl
# Change a domain or reseller password

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'pass_err'});

# Get and validate the domain
if ($in{'dom'}) {
	$in{'dom'} || &error($text{'pass_ecannot2'});
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'pass_ecannot'});
	}
elsif (!&reseller_admin()) {
	&error($text{'pass_ecannot2'});
	}

# Check passwords
$in{'new1'} || &error($text{'pass_enew1'});
$in{'new1'} eq $in{'new2'} || error($text{'pass_enew2'});

&ui_print_header($d ? &domain_in($d) : undef, $text{'pass_title'}, "");
if ($d) {
	# Update domain's password
	$oldd = { %$d };
	if ($d->{'disabled'}) {
		# Clear any saved passwords, as they should
		# be reset at this point
		$d->{'disabled_mysqlpass'} = undef;
		$d->{'disabled_postgrespass'} = undef;
		}
	$d->{'pass'} = $in{'new1'};
	$d->{'pass_set'} = 1;

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

	# Call all save functions
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
	&run_post_actions();
	&set_domain_envs($d, "MODIFY_DOMAIN");
	&made_changes();
	&reset_domain_envs($d);
	&webmin_log("pass", "domain", $d->{'dom'}, $d);
	}
else {
	# Update current reseller
	&$first_print($text{'pass_changing'});
	@resels = &list_resellers();
	($resel) = grep { $_->{'name'} eq $base_remote_user } @resels;
	$resel || &error($text{'pass_eresel'});
	$oldresel = { %$resel };
	$resel->{'pass'} = &acl::encrypt_password($in{'new1'});
	&modify_reseller($resel, $oldresel);
	&$second_print($text{'setup_done'});
	&run_post_actions();
	&webmin_log("pass", "resel", $resel->{'name'});
	}

if ($d) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

