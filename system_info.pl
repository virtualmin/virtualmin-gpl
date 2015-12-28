# Provide more system info blocks specific to Virtualmin

do 'virtual-server-lib.pl';
use Time::Local;

sub list_system_info
{
my ($data, $in) = @_;

# If user doesn't have access to Virtualmin, none of this makes sense
if (!&foreign_available($module_name)) {
	return ( );
	}

my @rv;
my $info = &get_collected_info();
my @poss = $info ? @{$info->{'poss'}} : ( );
my @doms = &list_visible_domains();

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

# Refresh button that does Virtualmin too, and replaces the one
# from the system-status module
push(@rv, { 'type' => 'link',
            'id' => 'vrecollect',
            'priority' => 100,
            'desc' => $text{'right_recollect'},
            'link' => '/'.$module_name.'/recollect.cgi' });
push(@rv, { 'type' => 'veto',
	    'veto' => 'recollect' });

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

# Show a domain owner info about his domain, but NOT info about the system
if (!&master_admin() && !&reseller_admin()) {
	my @table;

	# General info about the domain
	my $ex = &extra_admin();
	my $d = $ex ? &get_domain($ex)
		    : &get_domain_by("user", $remote_user, "parent", "");
	push(@table, { 'desc' => $text{'right_login'},
		       'value' => $remote_user });
	push(@table, { 'desc' => $text{'right_from'},
		       'value' => $ENV{'REMOTE_HOST'} });
	push(@table, { 'desc' => $text{'right_virtualmin'},
		       'value' => $module_info{'version'} });
	push(@table, { 'desc' => $text{'right_dom'},
		       'value' => &show_domain_name($d) });

	# Number of sub-servers
        my @subs = ( $d, virtual_server::get_domain_by("parent", $d->{'id'}) );
        my @reals = grep { !$_->{'alias'} } @subs;
        my @mails = grep { $_->{'mail'} } @subs;
        my ($sleft, $sreason, $stotal, $shide) =
                &count_domains("realdoms");
        if ($sleft < 0 || $shide) {
		push(@table, { 'desc' => $text{'right_subs'},
			       'value' => scalar(@reals) });
                }
        else {
		push(@table, { 'desc' => $text{'right_subs'},
                      	       'value' => &text('right_of',
						scalar(@reals), $stotal) });

                }

	# Number of alias domains
        my @aliases = grep { $_->{'alias'} } @subs;
        if (@aliases) {
                my ($aleft, $areason, $atotal, $ahide) =
                        &count_domains("aliasdoms");
                if ($aleft < 0 || $ahide) {
			push(@table, { 'desc' => $text{'right_aliases'},
				       'value' => scalar(@aliases) });
                        }
                else {
			push(@table, { 'desc' => $text{'right_aliases'},
				       'value' => &text('right_of',
						scalar(@aliases), $atotal) });
                        }
                }

	# Users and aliases
        my $users = &count_domain_feature("mailboxes", @subs);
        my ($uleft, $ureason, $utotal, $uhide) =
		&count_feature("mailboxes");
        my $msg = @mails ? $text{'right_fusers'} : $text{'right_fusers2'};
        if ($uleft < 0 || $uhide) {
		push(@table, { 'desc' => $msg,
			       'value' => $users });
                }
        else {
		push(@table, { 'desc' => $msg,
			       'value' => &text('right_of', $users, $utotal) });
                }

	# Mail aliases
        if (@mails) {
                my $aliases = &count_domain_feature("aliases", @subs);
                my ($aleft, $areason, $atotal, $ahide) =
                        virtual_server::count_feature("aliases");
                if ($aleft < 0 || $ahide) {
			push(@table, { 'desc' => $text{'right_faliases'},
				       'value' => $aliases });
                        }
                else {
			push(@table, { 'desc' => $text{'right_faliases'},
				       'value' => &text('right_of',
							$aliases, $atotal) });
                        }
                }

	# Database count
        my $dbs = &count_domain_feature("dbs", @subs);
        my ($dleft, $dreason, $dtotal, $dhide) =
                virtual_server::count_feature("dbs");
        if ($dleft < 0 || $dhide) {
		push(@table, { 'desc' => $text{'right_fdbs'},
			       'value' => $dbs });
                }
        else {
		push(@table, { 'desc' => $text{'right_fdbs'},
			       'value' => &text('right_of', $dbs, $dtotal) });
                }

	# Quota summary for top-level domain
	if (!$data->{'noquotas'} &&
            virtual_server::has_home_quotas()) {
                my $homesize = virtual_server::quota_bsize("home");
                my $mailsize = virtual_server::quota_bsize("mail");
                my ($home, $mail, $db) = &get_domain_quota($d, 1);
                my $usage = $home*$homesize + $mail*$mailsize + $db;
                my $limit = $d->{'quota'}*$homesize;
                if ($limit) {
			if ($usage > $limit) {
				$limit = $usage;
				}
			push(@table, { 'desc' => $text{'right_quota'},
				       'value' => &text('right_out',
					&nice_size($usage), &nice_size($limit)),
				       'chart' => [ $limit, $usage-$db, $db ]});
                        }
                else {
			push(@table, { 'desc' => $text{'right_quota'},
				       'value' => &nice_size($usage),
				       'wide' => 1 });
                        }
		}

	push(@rv, { 'type' => 'table',
		    'id' => 'domain',
	 	    'desc' => $text{'right_header3'},
		    'table' => \@table });
	push(@rv, { 'type' => 'veto',
		    'veto' => 'sysinfo' });
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
		    'id' => 'updates',
		    'desc' => $text{'right_updatesheader'},
		    'html' => $html });
	if (&get_webmin_version() >= 1.733) {
		# Block same section from being shown by Cloudmin
		push(@rv, { 'type' => 'veto',
			    'veto' => 'updates',
			    'veto_module' => 'server-manager' });
		}
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
		    'id' => 'status',
		    'desc' => $text{'right_statusheader'},
		    'open' => @down ? 1 : 0,
		    'table' => \@table });
	}

# New features
if ($data->{'dom'}) {
	$defdom = &get_domain($data->{'dom'});
	if ($defdom && !&can_edit_domain($defdom)) {
		$defdom = undef;
		}
	}
if (!$defdom && @doms) {
	$defdom = $doms[0];
	}
my $newhtml = &get_new_features_html($defdom);
if ($newhtml) {
	push(@rv, { 'type' => 'html',
		    'id' => 'newfeatures',
		    'open' => 1,
		    'desc' => $text{'right_newfeaturesheader'},
		    'html' => $newhtml });
	}

# Show usage count by type
if (&master_admin() && !$data->{'novirtualmin'} && $info->{'fcount'}) {
	my @table;
	foreach my $f (@{$info->{'ftypes'}}) {
		my $cur = int($info->{'fcount'}->{$f});
		my $extra = $info->{'fextra'}->{$f};
		my $max = $info->{'fmax'}->{$f};
		my $hide = $info->{'fhide'}->{$f};
		if ($extra < 0 || $hide) {
			push(@table, { 'desc' => $text{'right_f'.$f},
				       'value' => $cur });
			}
		else {
			push(@table, { 'desc' => $text{'right_f'.$f},
				       'value' => &text('right_out', $cur, $max) });
			}
		}
	push(@rv, { 'type' => 'table',
		    'id' => 'ftypes',
		    'desc' => $text{'right_virtheader'},
		    'open' => 0,
		    'table' => \@table });
	}

# Top quota users
my @quota = $info->{'quota'} ?
		grep { &can_edit_domain($_->[0]) } @{$info->{'quota'}} : ( );
if (!$data->{'noquotas'} && @quota && (&master_admin() || &reseller_admin())) {
	my @usage;
	my $max = $data->{'max'} || 10;
	my $maxquota = $info->{'maxquota'};

	# Work out if showing by percent makes sense
	my $qshow = $data->{'qshow'};
        if ($qshow) {
                my @quotawithlimit = grep { $_->[2] } @quota;
                $qshow = 0 if (!@quotawithlimit);
                }

	# Limit to those with a quota limit, if showing a percent
	if ($qshow) {
                @quota = grep { $_->[2] } @quota;
                }

	if ($qshow) {
		# Sort by percent used
		@quota = grep { $_->[2] } @quota;
                @quota = sort { ($b->[1]+$b->[3])/$b->[2] <=>
                                ($a->[1]+$a->[3])/$a->[2] } @quota;
                }
        else {
                # Sort by usage
		@quota = sort { $b->[1]+$b->[3] <=> $a->[1]+$a->[3] } @quota;
                }

	# Message above list
	my $qmsg;
        if (@quota > $max) {
                @quota = @quota[0..($max-1)];
                $qmsg = &text('right_quotamax', $max);
                }
	elsif (&master_admin()) {
                $qmsg = $text{'right_quotaall'};
                }
        else {
                $qmsg = $text{'right_quotayours'};
                }

	my $open = 0;
	foreach my $q (@quota) {
		my $cmd = &can_edit_domain($q->[0]) ? "edit_domain.cgi"
						    : "view_domain.cgi";
		my $chart = { 'desc' => &ui_link(
			'/'.$module_name.'/'.$cmd.'?dom='.$q->[0]->{'id'},
			 &show_domain_name($q->[0])) };
		if ($qshow) {
			# By percent used
			my $qpc = int($q->[1]*100 / $q->[2]);
                        my $dpc = int($q->[3]*100 / $q->[2]);
			$chart->{'chart'} = [ 100, $qpc, $dpc ];
			}
		else {
			# By actual usage
			$chart->{'chart'} = [ $maxquota, $q->[1], $q->[3] ];
			}
		if ($q->[2]) {
			# Show used and limit
			my $pc = int(($q->[1]+$q->[3])*100 / $q->[2]);
                        $pc = "&nbsp;$pc" if ($pc < 10);
			$chart->{'value'} = &text('right_out',
						  &nice_size($q->[1]+$q->[3]),
						  &nice_size($q->[2]));
			}
		else {
			# Just show used
			$chart->{'value'} = &nice_size($q->[1]+$q->[3]);
			}
		if ($q->[2] && $q->[1]+$q->[3] >= $q->[2]) {
			# Domain is over quota
			$open = 1;
			}
		push(@usage, $chart);
		}
	push(@rv, { 'type' => 'chart',
		    'id' => 'quota',
		    'desc' => $text{'right_quotasheader'},
		    'open' => $open,
		    'header' => $qmsg,
		    'chart' => \@usage });
	}

# Top BW users
my @bwdoms = grep { !$_->{'parent'} &&
		    defined($_->{'bw_usage'}) } @doms;
my $maxbw = 0;
foreach my $d (@doms) {
	$maxbw = $d->{'bw_limit'} if ($d->{'bw_limit'} > $maxbw);
	$maxbw = $d->{'bw_usage'} if ($d->{'bw_usage'} > $maxbw);
	}
if (!$data->{'nobw'} && $config{'bw_active'} && @bwdoms && $maxbw) {
	my $qshow = $data->{'qshow'};

	# Work out if showing by percent makes sense
	my $qshow = $data->{'qshow'};
	if ($qshow) {
		my @domswithlimit = grep { $_->{'bw_limit'} } @doms;
		$qshow = 0 if (!@domswithlimit);
		}

	if ($qshow) {
		# Sort by percent used
                @doms = grep { $_->{'bw_limit'} } @doms;
		@doms = sort { $b->{'bw_usage'}/$b->{'bw_limit'} <=>
			       $a->{'bw_usage'}/$a->{'bw_limit'} } @doms;
                }
        else {
                # Sort by usage
		@doms = sort { $b->{'bw_usage'} <=> $a->{'bw_usage'} } @doms;
                }

	# Show message about number of domains being displayed
	my $max = $data->{'max'} || 10;
	my $qmsg;
	if (@doms > $max) {
		@doms = @doms[0..($max-1)];
		$qmsg = &text('right_quotamax', $max);
		}
	else {
		$qmsg = $text{'right_quotaall'};
		}

	# Add the table of domains
	my $open = 0;
	foreach my $d (@doms) {
		my $cmd = &can_edit_domain($d) ? "edit_domain.cgi"
					       : "view_domain.cgi";
		my $chart = { 'desc' => &ui_link(
			'/'.$module_name.'/'.$cmd.'?dom='.$d->{'id'},
			 &show_domain_name($d)) };
		my $pc = $d->{'bw_limit'} ?
			int($d->{'bw_usage'}*100 / $d->{'bw_limit'}) : undef;
		if ($qshow) {
			# By percent used
			$chart->{'chart'} = [ 100, $pc ];
			}
		else {
			# By actual usage
			$chart->{'chart'} = [ $maxbw, $d->{'bw_usage'} ];
			}

		# Percent used, if available
		if ($d->{'bw_limit'}) {
			$pc = "&nbsp;$pc" if ($pc < 10);
			$chart->{'value'} = &text('right_out',
					   &nice_size($d->{'bw_usage'}),
					   &nice_size($d->{'bw_limit'}));
			}
		else {
			$chart->{'value'} = &nice_size($d->{'bw_usage'});
			}
		push(@usage, $chart);
		if ($d->{'bw_limit'} && $d->{'bw_usage'} >= $d->{'bw_limit'}) {
			$open = 1;
			}
		}
	push(@rv, { 'type' => 'chart',
		    'id' => 'bw',
		    'desc' => $text{'right_bwheader'},
		    'open' => $open,
		    'header' => $qmsg,
		    'chart' => \@usage });
	}

# IP addresses used
if (&master_admin() && !$data->{'noips'} && $info->{'ips'}) {
	my @table;
	my @allips = @{$info->{'ips'}};
	push(@allips, @{$info->{'ips6'}}) if ($info->{'ips6'});
	foreach my $ipi (@allips) {
		my $umsg;
		if ($ipi->[3] == 1) {
			$umsg = "<tt>$ipi->[4]</tt>";
			}
		else {
			my $slink = '/'.$module_name.
				    '/search.cgi?field=ip&what='.$ipi->[0];
			$umsg = &ui_link($slink, &text('right_ips', $ipi->[3]));
			}
		push(@table, { 'desc' => $ipi->[0],
			       'value' => ($ipi->[1] eq 'def' ?
				        $text{'right_defip'} :
                                     $ipi->[1] eq 'reseller' ?
                                        text('right_reselip', $ipi->[2]) :
                                     $ipi->[1] eq 'shared' ?
                                        $text{'right_sharedip'} :
                                        $text{'right_ip'})." ".$umsg });
		}
	if ($info->{'ipranges'}) {
		foreach my $r (@{$info->{'ipranges'}}) {
			push(@table, { 'desc' => $r->[0],
				       'value' => &text('right_iprange',
							$r->[1], $r->[2]),
				       'wide' => 1 });
			}
		}
	push(@rv, { 'type' => 'table',
                    'id' => 'ips',
		    'desc' => $text{'right_ipsheader'},
		    'open' => 0,
		    'table' => \@table });
	}

# Programs and versions
if (!$data->{'nosysinfo'} && $info->{'progs'} && &can_view_sysinfo()) {
	my @table;
	foreach my $info (@{$info->{'progs'}}) {
		push(@table, { 'desc' => $info->[0],
			       'value' => $info->[1] });
		}
	push(@rv, { 'type' => 'table',
		    'id' => 'sysinfo',
		    'desc' => $text{'right_sysinfoheader'},
		    'open' => 0,
		    'table' => \@table });
	}

# Virtualmin licence
my %vserial;
if (&read_env_file($virtualmin_license_file, \%vserial) &&
    $vserial{'SerialNumber'} ne 'GPL' &&
    &master_admin()) {
	my @table;
	my $open = 0;

	# Serial and key
	push(@table, { 'desc' => $text{'right_vserial'},
		       'value' => $vserial{'SerialNumber'} });
	push(@table, { 'desc' => $text{'right_vkey'},
		       'value' => $vserial{'LicenseKey'} });

	# Allowed domain counts
	my ($dleft, $dreason, $dmax, $dhide) =
		&count_domains("realdoms");
	push(@table, { 'desc' => $text{'right_vmax'},
		       'value' => $dmax <= 0 ? $text{'right_vunlimited'}
					     : $dmax });
	push(@table, { 'desc' => $text{'right_vleft'},
		       'value' => $dleft < 0 ? $text{'right_vunlimited'}
					     : $dleft });

	# Add allowed domain counts
	my %lstatus;
	&read_file($licence_status, \%lstatus);
	if ($lstatus{'used_servers'}) {
		push(@table, { 'desc' => $text{'right_smax'},
			       'value' => $lstatus{'servers'} ||
					  $text{'right_vunlimited'} });
		push(@table, { 'desc' => $text{'right_sused'},
			       'value' => $lstatus{'used_servers'} });
		}

	# Show license expiry date
	if ($lstatus{'expiry'} =~ /^203[2-8]-/) {
		push(@table, { 'desc' => $text{'right_expiry'},
			       'value' => $text{'right_expirynever'} });
		}
	elsif ($lstatus{'expiry'}) {
		push(@table, { 'desc' => $text{'right_expiry'},
			       'value' => $lstatus{'expiry'} });
		my $ltm = &parse_license_date($lstatus{'expiry'});
		if ($ltm) {
			my $days = int(($ltm - time()) / (24*60*60));
			push(@table, { 'desc' => $text{'right_expirydays'},
				       'value' => $days < 0 ?
					&text('right_expiryago', -$days) :
					$days });
			$open = 1 if ($days < 7);
			}
		}

	push(@rv, { 'type' => 'table',
		    'id' => 'serial',
		    'desc' => $text{'right_licenceheader'},
		    'open' => $open,
		    'table' => \@table });

	# Re-check licence link
	push(@rv, { 'type' => 'link',
		    'priority' => 20,
		    'desc' => $text{'right_vlcheck'},
		    'link' => '/'.$module_name.'/licence.cgi' });
	}

# Documentation links
my $doclink = &get_virtualmin_docs();
push(@rv, { 'type' => 'link',
	    'priority' => 50,
	    'desc' => $text{'right_virtdocs'},
	    'target' => 'new',
	    'link' => $doclink });
if ($config{'docs_link'}) {
	push(@rv, { 'type' => 'link',
		    'priority' => 49,
		    'desc' => $text{'right_virtdocs2'},
		    'target' => 'new',
		    'link' => $config{'docs_link'} });
	}

# Sections defined by plugins
foreach my $p (&list_plugin_sections()) {
	push(@rv, { 'type' => 'html',
		    'id' => 'plugin_'.$p->{'name'},
		    'desc' => $p->{'title'},
		    'html' => $p->{'html'},
		    'open' => $p->{'status'} });
	}

return @rv;
}

sub get_virtualmin_docs
{               
return &master_admin() ?
		"http://www.virtualmin.com/documentation" :
       &reseller_admin() ?
		"http://www.virtualmin.com/documentation/users/reseller" :
       		"http://www.virtualmin.com/documentation/users/server-owner";
}      

sub parse_license_date
{
my ($str) = @_;
if ($str =~ /^(\d{4})-(\d+)-(\d+)$/) {
        return eval { timelocal(0, 0, 0, $3, $2-1, $1-1900) };
        }
return undef;
}

1;
