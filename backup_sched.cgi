#!/usr/local/bin/perl
# Create, update or delete a scheduled backup

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_sched() || &error($text{'backup_ecannot2'});
$cbmode = &can_backup_domain();

# Get the current backup object
&obtain_lock_cron();
&lock_file($module_config_file);
@scheds = grep { &can_backup_sched($_) } &list_scheduled_backups();
if (!$in{'new'}) {
	($sched) = grep { $_->{'id'} == $in{'sched'} } @scheds;
        $sched || &error($text{'backup_egone'});
	}
else {
	# Create a new empty one
	$sched = { };
	}

if ($in{'clone'}) {
	# Redirect to backup form, cloning an existing backup
	&redirect("backup_form.cgi?clone=$sched->{'id'}&new=1");
	return;
	}

# Work out the current user's main domain, if needed
if ($cbmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
	}
elsif ($cbmode == 3 && $in{'dest_mode'} == 0 && !$in{'new'}) {
	# A reseller saving a backup to a local file, created by one of
	# his domains.
	$d = &get_domain($sched->{'owner'});
	}

if ($in{'delete'}) {
	# Just delete this schedule
	&delete_scheduled_backup($sched);
	}
else {
	# Validate inputs
	&error_setup($text{'backup_err2'});
	if ($in{'all'} == 1) {
		@doms = grep { &can_edit_domain($_) } &list_domains();
		}
	elsif ($in{'all'} == 2) {
		%exc = map { $_, 1 } split(/\0/, $in{'doms'});
		@doms = grep { !$exc{$_->{'id'}} } &list_domains();
		}
	else {
		foreach $did (split(/\0/, $in{'doms'})) {
			push(@doms, &get_domain($did));
			}
		}
	if ($in{'feature_all'}) {
		@do_features = ( &get_available_backup_features(),
				 &list_backup_plugins() );
		}
	else {
		@do_features = split(/\0/, $in{'feature'});
		}
	@do_features || &error($text{'backup_efeatures'});
	for($i=0; defined($in{"dest".$i."_mode"}); $i++) {
		# Parse destination
		next if ($in{"dest".$i."_mode"} == 0 &&
			 !$in{"dest".$i."_file"});
		$dest = &parse_backup_destination("dest".$i, \%in,
						  $cbmode == 3, $d);
		push(@dests, $dest);

		# Parse purge policy for the destination
		if (!$in{'purge'.$i.'_def'}) {
			($mode, undef, undef, $host, $path) =
				&parse_backup_url($dest);
			$in{'strftime'} || &error($text{'backup_epurgetime'});
			$path =~ /%/ || $host =~ /%/ ||
				&error($text{'backup_epurgetime'});
			($basepath, $pattern) = &extract_purge_path($dest);
			$basepath || $pattern ||
				&error($text{'backup_epurgepath'});
			$in{'purge'.$i} =~ /^[0-9\.]+$/ ||
				&error($text{'backup_epurge'});
			}
		push(@purges, $in{'purge_'.$i.'def'} ? undef : $in{'purge'.$i});
		}
	@dests || &error($text{'backup_edests'});

	# Parse key ID
	$key = undef;
	if ($in{'key'}) {
		$key = &get_backup_key($in{'key'});
		$key || &error($text{'backup_ekey'});
		&can_use_backup_key($key) ||
			&error($text{'backup_ekey2'});
		}

	# Parse option inputs
	foreach $f (@do_features) {
		local $ofunc = "parse_backup_$f";
		if (&indexof($f, &list_backup_plugins()) < 0 &&
		    defined(&$ofunc)) {
			$options{$f} = &$ofunc(\%in);
			}
		elsif (&indexof($f, &list_backup_plugins()) >= 0 &&
		       &plugin_defined($f, "feature_backup_parse")) {
			$options{$f} = &plugin_call($f,
					"feature_backup_parse", \%in);
			}
		}

	# Parse virtualmin config
	if (&can_backup_virtualmin()) {
		@vbs = split(/\0/, $in{'virtualmin'});
		}
	@doms || $in{'all'} || @vbs || &error($text{'backup_edoms'});

	# Update the schedule object
	$sched->{'all'} = $in{'all'};
	$sched->{'doms'} = join(" ", split(/\0/, $in{'doms'}));
	if (&can_edit_plans()) {
		$sched->{'plan'} = $in{'plan'};
		}
	$sched->{'parent'} = $in{'parent'};
	%sel_features = map { $_, 1 } split(/\0/, $in{'feature'});
	$sched->{'feature_all'} = $in{'feature_all'};
	$sched->{'features'} = join(" ", grep { $sel_features{$_} }
				    (@backup_features, &list_backup_plugins()));

	# Save destinations
	foreach my $k (keys %$sched) {
		if ($k =~ /^(dest|purge)\d+/) {
			delete($sched->{$k});
			}
		}
	$sched->{'dest'} = $dests[0];
	for(my $i=1; $i<@dests; $i++) {
		$sched->{'dest'.$i} = $dests[$i];
		}

	# Save purge policies
	$sched->{'purge'} = $purges[0];
	for(my $i=1; $i<@purges; $i++) {
		$sched->{'purge'.$i} = $purges[$i];
		}

	# Save backup key
	$sched->{'key'} = $key ? $key->{'id'} : undef;

	$sched->{'fmt'} = $in{'fmt'};
	$sched->{'mkdir'} = $in{'mkdir'};
	$sched->{'email'} = $in{'email'};
	$sched->{'email_err'} = $in{'email_err'};
	$sched->{'email_doms'} = $in{'email_doms'};
	$sched->{'errors'} = $in{'errors'};
	if (defined($in{'increment'})) {
		$sched->{'increment'} = $in{'increment'};
		}
	$sched->{'strftime'} = $in{'strftime'};
	$sched->{'onebyone'} = $in{'onebyone'};
	foreach $f (keys %options) {
		$sched->{'backup_opts_'.$f} =
		    join(",", map { $_."=".$options{$f}->{$_} }
				  keys %{$options{$f}});
		}
	if (scalar(@vbs) && &can_backup_virtualmin()) {
		$sched->{'virtualmin'} = join(" ", @vbs);
		}
	$sched->{'enabled'} = $in{'enabled'};
	if (&can_backup_commands()) {
		$sched->{'before'} = $in{'before_def'} ? undef : $in{'before'};
		$sched->{'after'} = $in{'after_def'} ? undef : $in{'after'};
		}
	$sched->{'exclude'} = join("\t", split(/\r?\n/, $in{'exclude'}));
	if ($cbmode != 1 && !$sched->{'owner'}) {
		# Record the owner of this scheduled backup, which controls
		# who it runs as
		$sched->{'owner'} = &reseller_admin() ? $base_remote_user
			      : &get_domain_by_user($base_remote_user)->{'id'};
		}
	if ($in{'enabled'}) {
		&virtualmin_ui_parse_cron_time("enabled", $sched, \%in);
		}

	# Save the schedule and thus the cron job
	&save_scheduled_backup($sched);
	}
&unlock_file($module_config_file);
&release_lock_cron();
&run_post_actions_silently();

# Log it
$what = $sched->{'all'} ? 'all' :
	$sched->{'doms'} ? scalar(split(/\s+/, $sched->{'doms'})) :
	$sched->{'virtualmin'} ? 'virtualmin' : 'none';
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    'sched', $what, $sched);
&redirect("list_sched.cgi");

