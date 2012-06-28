#!/usr/local/bin/perl
# Change a domain or reseller password

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'pass_err'});
&foreign_require("acl");

# Get and validate the domain
if ($in{'dom'}) {
	$in{'dom'} || &error($text{'pass_ecannot2'});
	$d = &get_domain($in{'dom'});
	&can_passwd() && &can_edit_domain($d) || &error($text{'pass_ecannot'});
	}
elsif (!&reseller_admin() && !&extra_admin()) {
	&error($text{'pass_ecannot2'});
	}

# Check passwords
$in{'new1'} || &error($text{'pass_enew1'});
$in{'new1'} eq $in{'new2'} || error($text{'pass_enew2'});

# Check password quality for virtual servers
if ($d) {
	local $fakeuser = { 'user' => $d->{'user'},
			    'plainpass' => $in{'new1'} };
	$err = &check_password_restrictions($fakeuser, $d->{'webmin'});
	&error($err) if ($err);
	}

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
	if (&master_admin()) {
		$d->{'hashpass'} = $in{'hashpass'};
		}
	$d->{'pass'} = $in{'new1'};
	$d->{'pass_set'} = 1;
	&generate_domain_password_hashes($d, 0);

	# Run the before command
	&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
	$merr = &making_changes();
	&reset_domain_envs(\%oldd);
	&error(&text('save_emaking', "<tt>$merr</tt>")) if (defined($merr));

	# Call all save functions
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
	&run_post_actions();
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));
	&reset_domain_envs($d);
	&webmin_log("pass", "domain", $d->{'dom'}, $d);
	}
elsif (&reseller_admin()) {
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
elsif (&extra_admin()) {
	# Update current extra admin
	# XXX also, exits at syscall
	&$first_print($text{'pass_changing2'});
	$myd = &get_domain($access{'admin'});
	@admins = &list_extra_admins($myd);
	($admin) = grep { $_->{'name'} eq $base_remote_user } @admins;
	$admin || &error($text{'pass_eadmin'});
	$oldadmin = { %$admin };
	$admin->{'pass'} = $in{'new1'};
	&modify_extra_admin($admin, $oldadmin, $myd);
	&$second_print($text{'setup_done'});
        &webmin_log("pass", "admin", $admin->{'name'});
	}

if ($d) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return'});
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

