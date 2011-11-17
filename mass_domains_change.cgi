#!/usr/local/bin/perl
# Actually update a bunch of domains

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massdomains_err'});

# Get the domains
@d = split(/\0/, $in{'d'});
@d || &error($text{'massdelete_enone'});
foreach $did (@d) {
	$d = &get_domain($did);
	$d && $d->{'uid'} && ($d->{'gid'} || $d->{'ugid'}) ||
		&error("Domain $did does not exist!");
	&can_config_domain($d) || &error($text{'edit_ecannot'});
	push(@doms, $d);
	}

# Validate inputs
if ($config{'spam'} && &can_edit_spam()) {
	if ($in{'spamclear_def'} == 2) {
		$in{'spamclear_days'} =~ /^\d+$/ &&
		    $in{'spamclear_days'} > 0 ||
			&error($text{'spam_edays'});
		$spamclear = { 'days' => $in{'spamclear_days'} };
		}
	elsif ($in{'spamclear_def'} == 3) {
		$in{'spamclear_size'} =~ /^\d+$/ &&
		    $in{'spamclear_size'} > 0 ||
			&error($text{'spam_esize'});
		$spamclear = { 'size' => $in{'spamclear_size'}*
					 $in{'spamclear_size_units'} };
		}
	elsif ($in{'spamclear_def'} == 0) {
		$spamclear = "";
		}
	}
if (&can_edit_phpmode() && !$in{'phpchildren_def'}) {
	$in{'phpchildren'} > 0 &&
	    $in{'phpchildren'} <= $max_php_fcgid_children || 
		&error(&text('phpmode_echildren',
			     $max_php_fcgid_children));
	}

# Apply the changes to the new domain objects, where possible
local $changed_limits = 0;
foreach $d (@doms) {
	local $oldd = { %$d };
	local $newdom = { %$d };

	my $parentdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
	my $aliasdom = $d->{'alias'} ? &get_domain($d->{'alias'}) : undef;
	my $subdom = $d->{'subdom'} ? &get_domain($d->{'subdom'}) : undef;

	if (&has_home_quotas() && &can_edit_quotas() &&
	    $in{'quota_def'} != 2) {
		# Update server quota
		if ($in{'quota_def'}) {
			$newdom->{'quota'} = undef;
			}
		else {
			$in{'quota'} =~ /^\d+$/ ||
				&error($text{'save_equota'});
			$newdom->{'quota'} = &quota_parse('quota', 'home');
			}
		}

	if (&has_home_quotas() && &can_edit_quotas() &&
	    $in{'uquota_def'} != 2) {
		# Update Unix user quota
		if ($in{'uquota_def'}) {
			$newdom->{'uquota'} = undef;
			}
		else {
			$in{'uquota'} =~ /^\d+$/ ||
				&error($text{'save_euquota'});
			$newdom->{'uquota'} = &quota_parse('uquota', 'home');
			}
		}

	if ($config{'bw_active'} && !$d->{'parent'} &&
	    &can_edit_bandwidth() && $in{'bw_def'} != 2) {
		# Update BW limit
		$newdom->{'bw_limit'} =
			&parse_bandwidth("bw", $text{'save_ebwlimit'});
		}

	# Update features
	local %check;
	foreach $f (&domain_features($d), &list_feature_plugins()) {
		# User can't use this feature
		next if (!&can_use_feature($f));

		# Not suitable for plugin
		if (&indexof($f, &list_feature_plugins()) >= 0 &&
		    !&plugin_call($f, "feature_suitable",
				  $parentdom, $aliasdom, $subdom)) {
			next;
			}

		if ($in{$f} == 1) {
			$newdom->{$f} = 1;
			if (!$d->{$f}) {
				$check{$f}++;
				}
			}
		elsif ($in{$f} == 0) {
			$newdom->{$f} = 0;
			}
		}

	# Update owner limits
	if (!$d->{'parent'} && &can_edit_limits($d)) {
		foreach $l (@limit_types) {
			if ($in{$l."_def"} == 1) {
				$newdom->{$l} = undef;
				$changed_limits = 1;
				}
			elsif ($in{$l."_def"} == 0) {
				$in{$l} =~ /^\d+$/ ||
				    &error($text{'setup_e'.$l} ||
					   $text{'limits_e'.$l});
				$newdom->{$l} = $in{$l};
				$changed_limits = 1;
				}
			}

		foreach $ed (@edit_limits) {
			if ($in{"edit_".$ed} == 0) {
				$newdom->{"edit_".$ed} = 0;
				$changed_limits = 1;
				}
			elsif ($in{"edit_".$ed} == 1) {
				$newdom->{"edit_".$ed} = 1;
				$changed_limits = 1;
				}
			}

		if ($in{'features_def'} == 1) {
			$newdom->{'limit_'.$in{'feature1'}} = 1;
			$changed_limits = 1;
			}
		elsif ($in{'features_def'} == 0) {
			$newdom->{'limit_'.$in{'feature0'}} = 0;
			$changed_limits = 1;
			}
		}

	# Check depends, clashes and limits
	$derr = &virtual_server_depends($newdom, undef, $oldd);
	&error("$d->{'dom'} : $derr") if ($derr);
	$cerr = &virtual_server_clashes($newdom, \%check);
	&error("$d->{'dom'} : $cerr") if ($cerr);
	$lerr = &virtual_server_limits($newdom, $oldd);
	&error("$d->{'dom'} : $lerr") if ($lerr);

	$oldd_map{$d->{'id'}} = $oldd;
	$newdom_map{$d->{'id'}} = $newdom;
	}

# Make the changes
&ui_print_unbuffered_header(undef, $text{'massdomains_title'}, "");

# Lock everything in the domains being modified
foreach $d (@doms) {
	&obtain_lock_everything($d);
	}

foreach $d (@doms) {
	&$first_print(&text('massdomains_dom', &show_domain_name($d)));
	&$indent_print();

	$oldd = $oldd_map{$d->{'id'}};
	$newdom = $newdom_map{$d->{'id'}};

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN", $newdom);
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('save_emaking', "<tt>$merr</tt>"))
		if (defined($merr));

	# Update quotas and BW limit
	if (&has_home_quotas() && !$d->{'parent'} &&
	    &can_edit_quotas($d)) {
		$d->{'quota'} = $newdom->{'quota'};
		$d->{'uquota'} = $newdom->{'uquota'};
		}
	if ($config{'bw_active'} && !$d->{'parent'} &&
	    &can_edit_bandwidth()) {
		$d->{'bw_limit'} = $newdom->{'bw_limit'};
		}

	# Call appropriate save functions
	if (!$d->{'disabled'}) {
		# Update the real domain object
		my $f;
		foreach $f (&domain_features($d)) {
			if ($config{$f}) {
				$d->{$f} = $newdom->{$f};
				}
			}
		foreach $f (&list_feature_plugins()) {
			$d->{$f} = $newdom->{$f};
			}
		foreach $f (&list_ordered_features($d)) {
			&call_feature_func($f, $d, $oldd);
			}
		}
	else {
		# Only modify unix if disabled
		if ($d->{'unix'}) {
			&modify_unix($d, $oldd);
			}
		}

	# Update limits
	if (!$d->{'parent'} && $changed_limits) {
		&$first_print($text{'massdomains_limits'});
		foreach $l (@limit_types) {
			$d->{$l} = $newdom->{$l};
			}
		foreach $ed (@edit_limits) {
			$d->{"edit_".$ed} = $newdom->{"edit_".$ed};
			}
		foreach $f (@opt_features, "virt", &list_feature_plugins()) {
			$d->{'limit_'.$f} = $newdom->{'limit_'.$f};
			}
		&$second_print($text{'setup_done'});
		}

	# Change the PHP execution mode
	if (&can_edit_phpmode() && $in{'phpmode'} && $d->{'web'} &&
	    !$d->{'alias'}) {
		&$first_print($text{'massdomains_phpmoding'});
		if ($in{'phpmode'} ne 'mod_php' &&
		    !&get_domain_suexec($d)) {
			# Enable suexec automatically
			&save_domain_suexec($d, 1);
			}
		&save_domain_php_mode($d, $in{'phpmode'});
		&$second_print($text{'setup_done'});
		}

	# Check the PHP child processes ..
	if (&can_edit_phpmode() && $in{'phpchildren_def'} != 1 &&
	    $d->{'web'} && !$d->{'alias'}) {
		&$first_print($text{'massdomains_phpchildrening'});
		&save_domain_php_children($d,
			$in{'phpchildren_def'} == 2 ? 0 : $in{'phpchildren'});
		&$second_print($text{'setup_done'});
		}

	# Change the Ruby execution mode
	if (&can_edit_phpmode() && $in{'rubymode'} && $d->{'web'} &&
	    !$d->{'alias'}) {
		&$first_print($text{'massdomains_rubymoding'});
		if ($in{'rubymode'} ne 'mod_ruby' &&
		    $in{'rubymode'} ne 'none' &&
		    !&get_domain_suexec($d)) {
			# Enable suexec automatically
			&save_domain_suexec($d, 1);
			}
		&save_domain_ruby_mode($d, $in{'rubymode'} eq 'none' ?
					    undef : $in{'rubymode'});
		&$second_print($text{'setup_done'});
		}

	# Change the default PHP version
	if (&can_edit_phpver() && $in{'phpver'} && $d->{'web'} &&
	    !$d->{'alias'}) {
		&$first_print($text{'massdomains_phpvering'});
		&save_domain_php_directory($d, &public_html_dir($d),
					   $in{'phpver'});
		&$second_print($text{'setup_done'});
		}

	# Change the shell
	if (&can_edit_shell() && !$in{'shell_def'} && $d->{'unix'}) {
		$user = &get_domain_owner($d);
		if ($user) {
			&$first_print($text{'massdomains_shelling'});
			$olduser = { %$user };
			$user->{'shell'} = $in{'shell'};
			&modify_user($user, $olduser, undef);
			&$second_print($text{'setup_done'});
			}
		}

	# Change spam clearing
	if ($d->{'spam'} && defined($spamclear)) {
		&$first_print($text{'massdomains_spamclearing'});
		&save_domain_spam_autoclear($d, $spamclear);
		&$second_print($text{'setup_done'});
		}

	# Save new domain details
	&$first_print($text{'save_domain'});
	&save_domain($d);
	&$second_print($text{'setup_done'});

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));
	&reset_domain_envs($d);

	&$outdent_print();
	&$second_print($text{'setup_done'});

	# Call any theme post command
	if (defined(&theme_post_save_domain) &&
	    !defined(&theme_post_save_domains)) {
		&theme_post_save_domain($d, 'modify');
		}
	else {
		push(@das, $d, 'modify');
		}
	}

foreach $d (@doms) {
	&release_lock_everything($d);
	}

# Run post-change commands
&run_post_actions();
if (defined(&theme_post_save_domains)) {
	&theme_post_save_domains(@das);
	}
&webmin_log("modify", "domains", scalar(@doms));

&ui_print_footer("", $text{'index_return'});

