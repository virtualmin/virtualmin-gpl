# Provide more system info blocks specific to Virtualmin

require 'virtual-server-lib.pl';

sub list_system_info
{
my ($data, $in) = @_;

my @rv;
my $info = &get_collected_info();

# Status of various servers
if (!$data->{'nostatus'} && $info->{'startstop'} &&
    &can_stop_servers()) {
	my @ss = @{$info->{'startstop'}};
	my @down = grep { !$_->{'status'} } @ss;
	my @table;
	my $idir = '/'.$module_name.'/images';
	foreach my $status (@ss) {
		# Work out label, possibly with link
		my $label;
		foreach my $l (@{$status->{'links'}}) {
			if ($l->{'manage'}) {
				$label = &ui_link($l->{'link'},
						  $status->{'name'});
				}
			}
		$label ||= $status->{'name'};

		# Stop / start icon
		my $action = ($status->{'status'} ? "stop_feature.cgi" :
			      "start_feature.cgi");
		my $action_icon = ($status->{'status'} ?
		   "<img src='$idir/stop.png' alt='$status->{'desc'}' />" :
		   "<img src='$idir/start.png' alt='$status->{'desc'}' />");
		my $action_link = "<a href='/$module_name/$action?".
		   "feature=$status->{'feature'}'".
		   " title='$status->{'desc'}'>".
		   "$action_icon</a>";

		# Restart link 
		my $restart_link = ($status->{'status'}
		   ? "<a href='/$module_name/restart_feature.cgi?".
		     "feature=$status->{'feature'}'".
		     " title='$status->{'restartdesc'}'>".
		     "<img src='$idir/reload.png'".
		     "alt='$status->{'restartdesc'}'></a>\n"
		   : "");

		push(@table, { 'desc' => $label,
			       'value' =>
			(!$status->{'status'} ?
			      "<img src='$idir/down.gif' alt='Stopped'>" :
			      "<img src='$idir/up.gif' alt='Running'>").
		        $action_link.
		        "&nbsp;".$restart_link });
		}
	push(@rv, { 'type' => 'table',
		    'desc' => $text{'right_statusheader'},
		    'open' => @down ? 1 : 0,
		    'table' => \@table });
	}

# Virtualmin feature counts

# Top quota users

# Top BW users

# Programs and versions

# New features

# Virtualmin licence

return @rv;
}

1;
