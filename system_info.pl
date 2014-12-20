# Provide more system info blocks specific to Virtualmin

require 'virtual-server-lib.pl';

sub list_system_info
{
my ($data, $in) = @_;

my @rv;
my $info = &get_collected_info();
my @poss = $info ? @{$info->{'poss'}} : ( );

# XXX resellers and domain owners and extra admins!

# Check for wizard redirect
my $redir = &wizard_redirect();
if ($redir) {
	push(@rv, { 'type' => 'redirect',
		    'url' => $redir });
	}

# Custom URL redirect
if ($data->{'alt'} && !$in{'noalt'}) {
	push(@rv, { 'type' => 'redirect',
		    'url' => $data->{'alt'} });
	}

# Warning messages
foreach my $warn (&list_warning_messages()) {
	push(@rv, { 'type' => 'warning',
		    'level' => 'warn',
		    'warning' => $warn });
	}

# Need to check module config?
if (&need_config_check() && &can_check_config()) {
	push(@rv, { 'type' => 'warning',
		    'level' => 'info',
		    'warning' => &ui_form_start('/'.$module_name.'/check.cgi').
				 "<b>$text{'index_needcheck'}</b><p>\n".
				 &ui_submit($text{'index_srefresh'}).
				 &ui_form_end(),
		  });
	}

# Virtualmin package updates
my $hasposs = foreign_check("security-updates");
my $canposs = foreign_available("security-updates");
if (!$data->{'noupdates'} && $hasposs && $canposs && @poss) {
	my $html = &ui_form_start("/security-updates/update.cgi");
	$html .= &text(@poss > 1 ? 'right_upcount' : 'right_upcount1',
		       scalar(@poss),
		       '/security-updates/index.cgi?mode=updates')."<p>\n";
	$html .= &ui_columns_start([ $text{'right_upname'},
                                     $text{'right_updesc'},
                                     $text{'right_upver'} ], "80%");
	foreach my $p (@poss) {
		$html .= &ui_columns_row([
			$p->{'name'}, $p->{'desc'}, $p->{'version'} ]);
		$html .= &ui_hidden("u", $p->{'update'}."/".$p->{'system'});
		}
	$html .= &ui_columns_end();
	$html .= &ui_form_end([ [ undef, $text{'right_upok'} ] ]);
	push(@rv, { 'type' => 'html',
		    'desc' => $text{'right_updatesheader'},
		    'html' => $html });
	}

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

# New features

# Virtualmin feature counts

# Top quota users

# Top BW users

# IP addresses used

# Programs and versions

# Virtualmin licence

return @rv;
}

1;
