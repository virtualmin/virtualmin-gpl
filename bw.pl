#!/usr/local/bin/perl
# Work out the bandwidth usage for all virtual servers.
# For those that are over their limit, send a warning.

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

# Are we already running? If so, die
if (&test_lock($bandwidth_dir)) {
	exit(0);
	}
&lock_file($bandwidth_dir);

# Work out the start of the monitoring period
$now = time();
$day = int($now / (24*60*60));
$start_day = &bandwidth_period_start();

if ($ARGV[0]) {
	$onedom = &get_domain_by("dom", $ARGV[0]);
	$onedom || die "Server $ARGV[0] not found";
	@doms = ( $onedom, &get_domain_by("parent", $onedom->{'id'}) );
	}
else {
	@doms = &list_domains();
	}
@bwdoms = grep { &can_monitor_bandwidth($_) } @doms;

# Get bandwidth info map for all domains
foreach $d (@bwdoms) {
	$bwinfo = &get_bandwidth($d);
	$bwinfomap{$d->{'id'}} = $bwinfo;
	}

# For each feature that has a function for doing bandwidth for all domains
# at once, call it
foreach $f (@bandwidth_features) {
	local $bwfunc = "bandwidth_all_$f";
	if (defined(&$bwfunc)) {
		local %starts = map { $_, $bwinfomap{$_}->{"last_$f"} }
				    (keys %bwinfomap);
		local $newstarts = &$bwfunc(\@bwdoms, \%starts, \%bwinfomap);
		foreach my $did (keys %$newstarts) {
			$bwinfomap{$did}->{"last_$f"} = $newstarts->{$did};
			}
		}
	}

# For each server, scan it's log files for all usage since the last check, and
# update the count for each day.
$maxdays = $config{'bw_maxdays'} || 366;
foreach $d (@bwdoms) {
	# Add bandwidth for all features
	$bwinfo = $bwinfomap{$d->{'id'}};
	foreach $f (@bandwidth_features) {
		local $bwfunc = "bandwidth_$f";
		if (defined(&$bwfunc)) {
			$bwinfo->{"last_$f"} =
				&$bwfunc($d, $bwinfo->{"last_$f"}, $bwinfo);
			}
		}

	# Add bandwidth for all plugins
	foreach $f (&list_feature_plugins()) {
		if (&plugin_defined($f, "feature_bandwidth")) {
			$bwinfo->{"last_$f"} =
				&plugin_call($f, "feature_bandwidth", $d,
					     $bwinfo->{"last_$f"}, $bwinfo);
			}
		}

	# Prune days more than 1 year old
	foreach $k (keys %$bwinfo) {
		if ($k =~ /^(\S+)_(\d+)$/ && $2 < $day - $maxdays) {
			delete($bwinfo->{$k});
			}
		}
	&save_bandwidth($d, $bwinfo);
	}

# For each server, sum up usage over the monitoring period to find those
# that are over their limit
foreach $d (@doms) {
	$d = &get_domain($d->{'id'}, undef, 1);	# Force re-read from disk
	next if (!$d);				# Deleted
	next if ($d->{'parent'});

	# Find domain and sub-domains
	@alld = ($d, &get_domain_by("parent", $d->{'id'}));

	# Sum up usage for domain and sub-domains
	$usage = 0;
	%usage = ( );
	foreach $dd (@alld) {
		$bwinfo = &get_bandwidth($dd);
		local $usage_only = 0;
		local %usage_only = ( );
		foreach $k (keys %$bwinfo) {
			if ($k =~ /^(\S+)_(\d+)$/ && $2 >= $start_day) {
				$usage += $bwinfo->{$k};
				$usage_only += $bwinfo->{$k};
				$usage{$1} += $bwinfo->{$k};
				$usage_only{$1} += $bwinfo->{$k};
				}
			}
		$dd->{'bw_usage_only'} = $usage_only;
		$dd->{'bw_start'} = $start_day;
		foreach $f (@bandwidth_features) {
			delete($dd->{"bw_usage_only_$f"});
			}
		foreach $k (keys %usage_only) {
			$dd->{'bw_usage_only_'.$k} = $usage_only{$k};
			}
		if ($d ne $dd) {
			&save_domain($dd);
			}
		}
	$d->{'bw_usage'} = $usage;
	foreach $f (@bandwidth_features) {
		delete($d->{"bw_usage_$f"});
		}
	foreach $k (keys %usage) {
		$d->{'bw_usage_'.$k} = $usage{$k};
		}
	local $from = &get_global_from_address($d);
	if ($d->{'bw_limit'} && $usage > $d->{'bw_limit'}) {
		# Over the limit! But check limit on how often to notify
		$etime = $now - $d->{'bw_notify'} > $config{'bw_notify'}*60*60;
		if ($etime) {
			# Time to email ..
			$tmpl = $config{'bw_template'} eq 'default' ?
				"$module_config_directory/bw-template" :
				$config{'bw_template'};
			%tkeys = &make_domain_substitions($d, 1);
			$tkeys{'bw_percent'} = int(100*$usage/$d->{'bw_limit'});
			foreach $k (keys %usage) {
				$tkeys{'bw_usage_'.$k} =
					&nice_size($tkeys{'bw_usage_'}.$k);
				}
			local @addrs;
			push(@addrs, $d->{'email'} ||
				   $d->{'user'}.'@'.&get_system_hostname() )
				if ($config{'bw_owner'});
			push(@addrs, split(/\s+,\s+/, $config{'bw_email'}));
			@erv = &send_template_email(
				&cat_file($tmpl),
				join(", ", @addrs),
				\%tkeys,
				&text('newbw_subject', $d->{'dom'}),
				undef, undef, undef, $from);
			if ($erv[0]) {
				$d->{'bw_notify'} = $now;
				}
			else {
				print STDERR "Failed to send email : $erv[1]\n";
				}
			}
		if (!$d->{'disabled'} && $etime && $config{'bw_disable'} &&
		    !$d->{'bw_no_disable'}) {
			# Time to disable this domain and all sub-servers
			&set_all_null_print();

			foreach my $dd (@alld) {
				&disable_virtual_server($dd, 'bw',
					'Exceeded bandwidth limit');
				}
			&run_post_actions();
			}
		&webmin_log("disable", "domain", $d->{'dom'}, $d);
		}
	elsif ($d->{'bw_limit'} && $config{'bw_warn'} &&
	       $usage > $d->{'bw_limit'}*$config{'bw_warn'}/100) {
		# Reached the warning limit! But check limit on how often warn
		if ($now - $d->{'bw_warnnotify'} > $config{'bw_notify'}*60*60) {
			# Time to email ..
			$tmpl = $config{'warnbw_template'} eq 'default' ?
				"$module_config_directory/warnbw-template" :
				$config{'warnbw_template'};
			%tkeys = &make_domain_substitions($d, 1);
			$tkeys{'bw_percent'} = int(100*$usage/$d->{'bw_limit'});
			foreach $k (keys %usage) {
				$tkeys{'bw_usage_'.$k} =
					&nice_size($tkeys{'bw_usage_'.$k});
				}
			$tkeys{'bw_warn'} = $config{'bw_warn'};
			local @addrs;
			push(@addrs, $d->{'email'} ||
				   $d->{'user'}.'@'.&get_system_hostname() )
				if ($config{'bw_owner'});
			push(@addrs, split(/\s+,\s+/, $config{'bw_email'}));
			@erv = &send_template_email(
				&cat_file($tmpl),
				join(", ", @addrs),
				\%tkeys,
				&text('newbw_warnsubject', $d->{'dom'}),
				undef, undef, undef, $from);
			if ($erv[0]) {
				$d->{'bw_warnnotify'} = $now;
				}
			else {
				print STDERR "Failed to send email : $erv[1]\n";
				}
			}
		}

	if ($config{'bw_enable'} &&
	    ($usage < $d->{'bw_limit'} || !$d->{'bw_limit'}) &&
	    $d->{'disabled'} && $d->{'disabled_reason'} eq 'bw') {
		# Falled below the disable limit .. re-enable
		&set_all_null_print();

		foreach my $dd (@alld) {
			@enable = &get_enable_features($dd);
			%enable = map { $_, 1 } @enable;
			delete($dd->{'disabled_reason'});
			delete($dd->{'disabled_why'});
			delete($dd->{'disabled_time'});

			# Run the before command
			&set_domain_envs($dd, "ENABLE_DOMAIN");
			$merr = &making_changes();
			&reset_domain_envs($dd);
			next if ($merr);

			# Enable all disabled features
			foreach my $f (@features) {
				if ($dd->{$f} && $enable{$f}) {
					local $efunc = "enable_$f";
					&try_function($f, $efunc, $dd);
					}
				}
			foreach my $f (&list_feature_plugins()) {
				if ($dd->{$f} && $enable{$f}) {
					&plugin_call($f, "feature_enable", $dd);
					}
				}

			# Disable extra admins
			&update_extra_webmin($dd, 0);

			# Save new domain details
			delete($dd->{'disabled'});
			&save_domain($dd);

			# Run the after command
			&set_domain_envs($dd, "ENABLE_DOMAIN");
			&made_changes();
			&reset_domain_envs($dd);
			}
		&run_post_actions();
		&webmin_log("enable", "domain", $d->{'dom'}, $d);
		}
	&save_domain($d);
	}

# Release running lock
&unlock_file($bandwidth_dir);
