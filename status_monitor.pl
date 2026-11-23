
do 'virtual-server-lib.pl';

# monitor_service_id(&service)
# Returns feature:init-name, falling back to feature:id or just feature.
# The init name keeps PHP-FPM monitor IDs stable across patch updates.
sub monitor_service_id
{
my ($s) = @_;
my $name = defined($s->{'init'}) && $s->{'init'} ne '' ? $s->{'init'}
							: $s->{'id'};
return $s->{'feature'} if (!defined($name) || $name eq '');
return $s->{'feature'}.':'.$name;
}

# status_monitor_dashboard(&data)
# Returns permitted services from collected status for the shared dashboard.
# The data hash contains dashboard options, including nostatus.
sub status_monitor_dashboard
{
my ($data) = @_;
# Respect hidden status and Virtualmin viewing or control permissions
return ( ) if ($data->{'nostatus'} ||
	       !(&can_view_status() || &can_stop_servers()));

# Match service features to monitor types so each pair appears once
my %types = ( 'web' => 'apache', 'dns' => 'bind8', 'ftp' => 'proftpd',
	      'dovecot' => 'dovecot', 'sshd' => 'sshd', 'mysql' => 'mysql',
	      'postgres' => 'postgresql',
	      'virtualmin-nginx' => 'nginx::nginx' );
my @rv;
foreach my $s (@{&get_collected_info()->{'startstop'} || []}) {
	my ($manage) = grep { $_->{'manage'} } @{$s->{'links'} || []};
	my $type = $types{$s->{'feature'}};
	if ($s->{'feature'} eq 'mail' && $manage &&
	    $manage->{'link'} =~ m!^/(postfix|sendmail|qmailadmin)/$!) {
		# The mail server in use decides the type of its monitor
		$type = $1;
		}
	# Keep the original service details for action labels and parameters
	push(@rv, { 'id' => &monitor_service_id($s),
		    'desc' => $s->{'name'},
		    'up' => $s->{'status'} ? 1 : 0,
		    'type' => $type,
		    'manage' => $manage ? $manage->{'link'} : undef,
		    'service' => $s });
	}
return @rv;
}

# status_monitor_actions(type, &monitor, up)
# Returns permitted actions using the original feature and service ID.
# The handlers recheck permission when the user submits an action.
sub status_monitor_actions
{
my ($type, $monitor, $up) = @_;
# Viewing service status does not grant control permissions
return ( ) if (!&can_stop_servers());

# Scheduled service monitors store an ID; dashboard services carry details
my $s = $monitor->{'service'};
if (!$s && $type eq 'service') {
	($s) = grep { &monitor_service_id($_) eq $monitor->{'service_id'} }
		    @{&get_collected_info()->{'startstop'} || []};
	}

# Hide controls if the service is missing or its collected status disagrees
return ( ) if (!$s || !!$up != !!$s->{'status'});
my $fields = { 'feature' => $s->{'feature'}, 'id' => $s->{'id'} // '' };
return $up ? ( [ 'stop', $s->{'desc'}, 'stop_feature.cgi', $fields ],
	       [ 'restart', $s->{'restartdesc'}, 'restart_feature.cgi',
		 $fields ] ) :
	     ( [ 'start', $s->{'desc'}, 'start_feature.cgi', $fields ] );
}

# status_monitor_list()
# Returns the monitor types that Virtualmin adds to the status module
sub status_monitor_list
{
return ( [ "validate", $text{'monitor_validate'} ],
	 [ "service", $text{'monitor_service'} ] );
}

# Reuse service checks within the same second
my (%service_states, $service_check_time);

# status_monitor_status(type, &monitor, [from-ui])
# Returns service status or domain validation results. from-ui is unused.
sub status_monitor_status
{
my ($type, $serv, $fromui) = @_;

if ($type eq 'service') {
	# Read current service state for scheduled monitoring
	if (!$service_check_time || $service_check_time != time()) {
		# Share one lookup across service monitors checked in this second
		%service_states = map { &monitor_service_id($_),
					$_->{'status'} ? 1 : 0 }
				      &get_startstop_links();
		$service_check_time = time();
		}
	# A missing service is reported as not installed
	my $up = $service_states{$serv->{'service_id'}};
	return { 'up' => defined($up) ? $up : -1 };
	}

# Get the domains to check
my @doms;
if ($serv->{'doms'}) {
	foreach my $id (split(/\s+/, $serv->{'doms'})) {
		my $d = &get_domain($id);
		push(@doms, $d) if ($d);
		}
	}
else {
	@doms = &list_visible_domains();
	}
@doms || return { 'up' => -1,
		  'desc' => $text{'monitor_nodoms'} };

# Get features to check
my @feats;
if ($serv->{'feats'}) {
	@feats = split(/\s+/, $serv->{'feats'});
	}
else {
	@feats = ( @validate_features, &list_feature_plugins() );
	}
@feats || return { 'up' => -1,
		   'desc' => $text{'monitor_nofeats'} };

# Do all the domains and features
my @allerrs;
my $count = 0;
foreach my $d (@doms) {
	my @errs;
	foreach $f (@feats) {
		next if (!$d->{$f});
		if (&indexof($f, &list_feature_plugins()) < 0) {
			# Core feature
			next if (!$config{$f});
			$vfunc = "validate_$f";
			$err = &$vfunc($d);
			$name = $text{'feature_'.$f};
			}
		else {
			# Plugin feature
			$err = &plugin_call($f, "feature_validate", $d);
			$name = &plugin_call($f, "feature_name");
			}
		push(@errs, "$name : $err") if ($err);
		}
	if (@errs) {
		$count += scalar(@errs);
		push(@allerrs, &show_domain_name($d)." - ".join(", ", @errs));
		}
	}
if (@allerrs) {
	return { 'up' => 0,
		 'value' => $count,
		 'desc' => join(" ", @allerrs),
	       },
	}
else {
	return { 'up' => 1,
		 'value' => $count,
		 'desc' => &text('monitor_done', scalar(@doms), scalar(@feats)),
	       };
	}
}

# status_monitor_dialog(type, &monitor)
# Returns the form fields for a monitor of the given type
sub status_monitor_dialog
{
my ($type, $serv) = @_;
if ($type eq 'service') {
	# Build choices from the same service lookup used by scheduled checks
	my @services = &get_startstop_links();
	return &ui_table_row($text{'monitor_service'},
		&ui_select("service_id", $serv->{'service_id'},
			   [ map { [ &monitor_service_id($_), $_->{'name'} ] }
				 @services ]));
	}
my $rv = "";

# Domains to check
my @doms = &list_visible_domains();
$rv .= &ui_table_row($text{'monitor_doms'},
    &ui_radio("servers_def", $serv->{'doms'} ? 0 : 1,
	[ [ 1, $text{'newips_all'} ],
	  [ 0, $text{'newips_sel'} ] ])."<br>\n".
    &servers_input("servers", [ split(/\s+/, $serv->{'doms'}) ], \@doms, 0, 1));

# Features to check
my @fopts = &validation_select_features();
$rv .= &ui_table_row($text{'monitor_feats'},
    &ui_radio("features_def", $serv->{'feats'} ? 0 : 1,
	[ [ 1, $text{'newvalidate_all'} ],
	  [ 0, $text{'newvalidate_sel'} ] ])."<br>\n".
    &ui_select("features", [ split(/\s+/, $serv->{'feats'}) ],
	       \@fopts, 10, 1));

return $rv;
}

# status_monitor_parse(type, &monitor, &in)
# Validates submitted fields and updates the monitor hash
sub status_monitor_parse
{
my ($type, $serv, $in) = @_;

if ($type eq 'service') {
	# Require a current service and save its ID for dashboard matching
	my @services = &get_startstop_links();
	grep { &monitor_service_id($_) eq $in->{'service_id'} } @services
		or &error($text{'monitor_eservice'});
	$serv->{'service_id'} = $in->{'service_id'};
	$serv->{'dashboard_service'} = $module_name.'::'.$in->{'service_id'};
	return;
	}
if ($in->{'servers_def'}) {
	delete($serv->{'doms'});
	}
else {
	$in->{'servers'} || &error($text{'monitor_edoms'});
	$serv->{'doms'} = join(" ", split(/\s+/, $in->{'servers'}));
	}

if ($in->{'features_def'}) {
	delete($serv->{'feats'});
	}
else {
	$in->{'features'} || &error($text{'monitor_edoms'});
	$serv->{'feats'} = join(" ", split(/\0/, $in->{'features'}));
	}
}

1;
