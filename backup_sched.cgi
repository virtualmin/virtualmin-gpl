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
	$sched->{'owner'} = $base_remote_user if (!&master_admin());
	}

# Work out the current user's main domain, if needed
if ($cbmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
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
	@doms || &error($text{'backup_edoms'});
	if ($in{'feature_all'}) {
		@do_features = ( &get_available_backup_features(),
				 @backup_plugins );
		}
	else {
		@do_features = split(/\0/, $in{'feature'});
		}
	@do_features || &error($text{'backup_efeatures'});
	$dest = &parse_backup_destination("dest", \%in, $cbmode == 3, $d);
	if ($in{'onebyone'}) {
		$in{'dest_mode'} > 0 || &error($text{'backup_eonebyone1'});
		$in{'fmt'} == 2 || &error($text{'backup_eonebyone2'});
		}

	# Parse option inputs
	foreach $f (@do_features) {
		local $ofunc = "parse_backup_$f";
		if (&indexof($f, @backup_plugins) < 0 &&
		    defined(&$ofunc)) {
			$options{$f} = &$ofunc(\%in);
			}
		elsif (&indexof($f, @backup_plugins) >= 0 &&
		       &plugin_defined($f, "feature_backup_parse")) {
			$options{$f} = &plugin_call($f,
					"feature_backup_parse", \%in);
			}
		}

	# Parse virtualmin config
	if (&can_backup_virtualmin()) {
		@vbs = split(/\0/, $in{'virtualmin'});
		}

	# Update the schedule object
	$sched->{'all'} = $in{'all'};
	$sched->{'doms'} = join(" ", split(/\0/, $in{'doms'}));
	$sched->{'parent'} = $in{'parent'};
	%sel_features = map { $_, 1 } split(/\0/, $in{'feature'});
	$sched->{'feature_all'} = $in{'feature_all'};
	$sched->{'features'} = join(" ",
		grep { $sel_features{$_} } (@backup_features, @backup_plugins));
	$sched->{'dest'} = $dest;
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
	if (defined(@vbs) && &can_backup_virtualmin()) {
		$sched->{'virtualmin'} = join(" ", @vbs);
		}
	$sched->{'enabled'} = $in{'enabled'};
	if ($cbmode != 1) {
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

# Log it
$what = $sched->{'all'} ? 'all' :
	$sched->{'doms'} ? scalar(split(/\s+/, $sched->{'doms'})) :
	$sched->{'virtualmin'} ? 'virtualmin' : 'none';
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    'sched', $what, $sched);
&redirect("list_sched.cgi");

