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
	@doms = ( $onedom );
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
foreach $f (@features) {
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
	foreach $f (@features) {
		local $bwfunc = "bandwidth_$f";
		if (defined(&$bwfunc)) {
			$bwinfo->{"last_$f"} =
				&$bwfunc($d, $bwinfo->{"last_$f"}, $bwinfo);
			}
		}

	# Add bandwidth for all plugins
	foreach $f (@feature_plugins) {
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
	next if ($d->{'parent'});

	# Sum up usage for domain and sub-domains
	$usage = 0;
	%usage = ( );
	foreach $dd ($d, &get_domain_by("parent", $d->{'id'})) {
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
		foreach $f (@features) {
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
	foreach $f (@features) {
		delete($d->{"bw_usage_$f"});
		}
	foreach $k (keys %usage) {
		$d->{'bw_usage_'.$k} = $usage{$k};
		}
	if ($d->{'bw_limit'} && $usage > $d->{'bw_limit'}) {
		# Over the limit! But check limit on how often to notify
		$etime = $now - $d->{'bw_notify'} > $config{'bw_notify'}*60*60;
		if ($etime) {
			# Time to email ..
			$tmpl = $config{'bw_template'} eq 'default' ?
				"$module_config_directory/bw-template" :
				$config{'bw_template'};
			%tkeys = %$d;
			$tkeys{'bw_limit'} = &nice_size($tkeys{'bw_limit'});
			$tkeys{'bw_usage'} = &nice_size($tkeys{'bw_usage'});
			$tkeys{'bw_period'} = $config{'bw_period'};
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
				&text('newbw_subject', $d->{'dom'}));
			if ($erv[0]) {
				$d->{'bw_notify'} = $now;
				}
			else {
				print STDERR "Failed to send email : $erv[1]\n";
				}
			}
		if (!$d->{'disabled'} && $etime && $config{'bw_disable'} &&
		    !$d->{'bw_no_disable'}) {
			# Time to disable
			&set_all_null_print();
			@disable = &get_disable_features($d);
			%disable = map { $_, 1 } @disable;

			# Run the before command
			&set_domain_envs($d, "DISABLE_DOMAIN");
			$merr = &making_changes();
			&reset_domain_envs($d);
			next if ($merr);

			# Disable all configured features
			my $f;
			foreach $f (@features) {
				if ($d->{$f} && $disable{$f}) {
					local $dfunc = "disable_$f";
					&$dfunc($d);
					push(@disabled, $f);
					}
				}
			foreach $f (@feature_plugins) {
				if ($d->{$f} && $disable{$f}) {
					&plugin_call($f, "feature_disable", $d);
					push(@disabled, $f);
					}
				}

			# Save new domain details
			$d->{'disabled'} = join(",", @disabled);
			$d->{'disabled_reason'} = 'bw';

			# Run the after command
			&run_post_actions();
			&set_domain_envs($d, "DISABLE_DOMAIN");
			&made_changes();
			&reset_domain_envs($d);
			}
		}
	elsif ($d->{'bw_limit'} && $config{'bw_warn'} &&
	       $usage > $d->{'bw_limit'}*$config{'bw_warn'}/100) {
		# Reached the warning limit! But check limit on how often warn
		if ($now - $d->{'bw_warnnotify'} > $config{'bw_notify'}*60*60) {
			# Time to email ..
			$tmpl = $config{'warnbw_template'} eq 'default' ?
				"$module_config_directory/warnbw-template" :
				$config{'warnbw_template'};
			%tkeys = %$d;
			$tkeys{'bw_limit'} = &nice_size($tkeys{'bw_limit'});
			$tkeys{'bw_usage'} = &nice_size($tkeys{'bw_usage'});
			$tkeys{'bw_period'} = $config{'bw_period'};
			$tkeys{'bw_percent'} = int(100*$usage/$d->{'bw_limit'});
			foreach $k (keys %usage) {
				$tkeys{'bw_usage_'.$k} =
					&nice_size($tkeys{'bw_usage_'}.$k);
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
				&text('newbw_warnsubject', $d->{'dom'}));
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
		@enable = &get_enable_features($d);
		%enable = map { $_, 1 } @enable;

		# Run the before command
		&set_domain_envs($d, "ENABLE_DOMAIN");
		$merr = &making_changes();
		&reset_domain_envs($d);
		next if ($merr);

		# Enable all disabled features
		my $f;
		foreach $f (@features) {
			if ($d->{$f} && $enable{$f}) {
				local $efunc = "enable_$f";
				&try_function($f, $efunc, $d);
				}
			}
		foreach $f (@feature_plugins) {
			if ($d->{$f} && $enable{$f}) {
				&plugin_call($f, "feature_enable", $d);
				}
			}

		# Save new domain details
		delete($d->{'disabled'});
		delete($d->{'disabled_reason'});
		delete($d->{'disabled_why'});
		&save_domain($d);

		# Run the after command
		&run_post_actions();
		&set_domain_envs($d, "ENABLE_DOMAIN");
		&made_changes();
		&reset_domain_envs($d);
		}
	&save_domain($d);
	}

# Release running lock
&unlock_file($bandwidth_dir);
