#!/usr/local/bin/perl
# bwgraph.cgi
# Show current bandwidth usage graphs

require './virtual-server-lib.pl';
&ReadParse();

# Work out which domains to show
if ($in{'dom'}) {
	# Specific domain
	@doms = ( $d=&get_domain($in{'dom'}) );
	&can_edit_domain($d) || &error($text{'newbw_ecannot'});
	$subh = &domain_in($doms[0]);
	if ($d->{'parent'}) {
		# Which is a sub-server
		$parent = &get_domain($d->{'parent'});
		}
	}
else {
	# All owned by user
	@doms = grep { !$_->{'parent'} &&
		       &can_edit_domain($_) } &list_domains();
	}
&ui_print_header($subh, $text{'bwgraph_title'}, "");

# Show current usage and limit for all virtual servers
$max = 0;
foreach $d (@doms) {
	$max = $d->{'bw_usage'} if ($d->{'bw_usage'} > $max);
	$max = $d->{'bw_usage_only'} if ($d->{'bw_usage_only'} > $max);
	$max = $d->{'bw_limit'} if ($d->{'bw_limit'} > $max);
	}
if ($parent) {
	$max = $parent->{'bw_limit'} if ($parent->{'bw_limit'} > $max);
	}
if ($max) {
	# Show links for mode
	print "<b>$text{'bwgraph_mode'}</b>\n";
	if ($in{'dom'}) {
		@subs = grep { !$_->{'alias'} }
		     	     &get_domain_by("parent", $doms[0]->{'id'});
		}
	@links = ( );
	if ($parent && !$in{'mode'}) {
		# For sub-servers, default mode is by date
		$in{'mode'} = 2;
		}
	foreach $m (0, 4, 1, 2, 3) {
		if ($m == 4 && $in{'dom'}) {
			# Just one domain, so no need for over-limit mode
			next;
			}
		if ($m == 0 && $parent) {
			# If this is a sub-server, don't show limit
			next;
			}
		if ($m == 1 && $in{'dom'}) {
			# Don't show sub-server if none
			next if (!@subs);
			$t = $text{'bwgraph_mode_'.$m};
			}
		elsif (($m == 0 || $m == 4) && $in{'dom'}) {
			$t = @subs ? $text{'bwgraph_mode_'.$m.'two'}
				   : $text{'bwgraph_mode_'.$m.'one'};
			}
		else {
			$t = $text{'bwgraph_mode_'.$m};
			}
		if ($m == $in{'mode'}) {
			push(@links, $t);
			}
		else {
			push(@links, "<a href='bwgraph.cgi?mode=$m&".
			     "dom=$in{'dom'}&mago=$in{'mago'}'>$t</a>\n");
			}
		}
	print &ui_links_row(\@links),"<p>\n";

	# Show table
	$width = 500;
	print "<table width=100%>\n";
	if ($in{'mode'} == 0 || $in{'mode'} == 1 || $in{'mode'} == 4) {
		# By domain .. start by computing usage for the selected
		# period for each domain
		%usage = ( );
		%usage_only = ( );
		%fusage = ( );
		%fusage_only = ( );
		$start_day = &bandwidth_period_start($in{'mago'});
		$end_day = &bandwidth_period_end($in{'mago'});
		if ($in{'mago'}) {
			foreach $d (grep { !$_->{'parent'} } @doms) {
				# Need to re-compute for some past period
				foreach $dd ($d, &get_domain_by("parent", $d->{'id'})) {
					$bwinfo = &get_bandwidth($dd);
					foreach $k (keys %$bwinfo) {
						$v = $bwinfo->{$k};
						if ($k =~ /^(\S+)_(\d+)$/ &&
						    $2 >= $start_day &&
						    $2 <= $end_day) {
							$usage_only{$dd->{'id'}} += $v;
							$fusage_only{$1}->{$dd->{'id'}} += $v;
							$pid = $dd->{'parent'} || $dd->{'id'};
							$usage{$pid} += $v;
							$fusage{$1}->{$pid} += $v;
							}
						}
					}
				}
			}
		else {
			foreach $d (@doms) {
				# bw.pl has already given us stats for the
				# current period
				foreach $dd ($d, &get_domain_by("parent",
								$d->{'id'})) {
					$pid = $dd->{'parent'} || $dd->{'id'};
					$usage{$pid} += $dd->{'bw_usage'};
					$usage_only{$dd->{'id'}} = $dd->{'bw_usage_only'};
					foreach $f (@bandwidth_features) {
						$fusage{$f}->{$pid} +=
							$dd->{'bw_usage_'.$f};
						$fusage_only{$f}->{$dd->{'id'}} =
							$dd->{'bw_usage_only_'.$f};
						}
					}
				}
			}

		# Only show those that are over the limit
		if ($in{'mode'} == 4) {
			@doms = grep { $usage{$_->{'id'}} > $_->{'bw_limit'} &&
				       $_->{'bw_limit'} } @doms;
			if (!@doms) {
				print "<tr> <td><b>$text{'newbw_allunder'}</b></td> </tr>\n";
				}
			}

		# Show the table of domains
		if (@doms) {
			print "<tr> <td><b>$text{'newbw_dom'}</b></td>\n";
			print "<td><b>",&text('edit_bwpast_'.$config{'bw_past'},
			      $text{'newbw_graph'}, $config{'bw_period'}),
			      "</b></td>\n";
			print "<td><b>$text{'newbw_glimit'}</b></td>\n";
			print "<td><b>$text{'newbw_gusage'}</b></td>\n";
			print "</tr>\n";
			}
		foreach $d (sort { $usage{$b->{'id'}} <=> $usage{$a->{'id'}} }
			    grep { !$_->{'parent'} }
			    @doms) {
			$usage = $in{'mode'} == 1 ? $usage_only{$d->{'id'}}
						  : $usage{$d->{'id'}};
			$dname = &show_domain_name($d);
			if ($in{'dom'}) {
				print "<tr> <td>$dname</td> <td nowrap>\n";
				}
			else {
				print "<tr> <td><a href='bwgraph.cgi?",
				      "dom=$d->{'id'}&mago=$in{'mago'}'>",
				      "$dname</td> <td nowrap>\n";
				}

			# Show nothing if this domain is disabled
			if (!&can_monitor_bandwidth($d)) {
				print "</td> <td colspan=2>",
				      "$text{'bwgraph_dis'}</td> </tr>\n";
				next;
				}

			# Show limit, or grey box if unlimited
			if ($d->{'bw_limit'}) {
				printf "<img src=images/red.gif width=%s height=10>\n",
					int($width*$d->{'bw_limit'}/$max)+1;
				}
			else {
				printf "<img src=images/grey.gif width=%s height=10>\n",
					$width;
				}

			# Show usage by feature
			print "<br>";
			&usage_colours($d, $in{'mode'} ? \%fusage_only
						       : \%fusage);

			print "</td>\n";
			print "<td>\n";
			if ($d->{'bw_limit'}) {
				print &nice_size($d->{'bw_limit'});
				}
			else {
				print $text{'newbw_unlim'};
				}
			print "</td>\n";
			print "<td>",&nice_size($usage),"</td>\n";
			print "</tr>\n";

			next if ($in{'mode'} != 1);

			# Show sub-servers
			$space = $d->{'bw_usage_only'};
			foreach $sd (grep { !$_->{'alias'} }
				         &get_domain_by("parent", $d->{'id'})) {
				$dname = &show_domain_name($sd);
				print "<tr> <td>&nbsp;&nbsp;&nbsp;",
				      "<a href='bwgraph.cgi?dom=$sd->{'id'}&",
				      "mago=$in{'mago'}'>$dname</a>",
				      "</td> <td>\n";

				# Show nothing if this domain is disabled
				if (!&can_monitor_bandwidth($sd)) {
					print "</td> <td colspan=2>$text{'bwgraph_dis'}</td> </tr>\n";
					next;
					}

				printf "<img src=images/white.gif width=%s height=10>",
					int($width*$space/$max);
				&usage_colours($sd, $in{'mode'} ? \%fusage_only
							        : \%fusage);
				print "</td>\n";
				print "<td></td>\n";
				print "<td>",&nice_size($usage_only{$sd->{'id'}}),"</td>\n";
				print "</tr>\n";
				$space += $sd->{'bw_usage_only'};
				}
			}
		}
	elsif ($in{'mode'} == 2) {
		# By date, for current billing period
		print "<tr> <td><b>$text{'newbw_date'}</b></td>\n";
		print "<td><b>$text{'newbw_dusage'}</b></td>\n";
		print "<td><b>$text{'newbw_gusage'}</b></td>\n";
		print "</tr>\n";

		# Get bandwidth for relevant domains and sub-domains
		foreach $d (@doms) {
			foreach $dd ($d, &get_domain_by("parent", $d->{'id'})) {
				local $bwinfo = &get_bandwidth($dd);
				push(@bands, $bwinfo);
				}
			}

		# Work out the max day
		$day = &bandwidth_period_end($in{'mago'});
		$start_day = &bandwidth_period_start($in{'mago'});
		$max = 0;
		for($i=$day; $i>=$start_day; $i--) {
			$usage = 0;
			foreach $f (@bandwidth_features) {
				$usage += &usage_for_days($i, $i, $f, @bands);
				}
			$max = $usage if ($usage > $max);
			}

		# Show the day table
		$max ||= 1;
		for($i=$day; $i>=$start_day; $i--) {
			print "<tr>\n";
			print "<td>",&make_date($i*24*60*60, 1),"</td>\n";
			print "<td>";
			local $usage = 0;
			foreach $f (@bandwidth_features) {
				local $fusage = &usage_for_days($i, $i, $f,
								@bands);
				$usage += $fusage;
				if ($fusage) {
					printf "<img src=images/usage-$f.gif width=%s height=10>",
						int($width*$fusage/$max)+($f eq "web" ? 1 : 0);
					$donecolour{$f} += $fusage;
					}
				}
			print "</td>";
			print "<td>",&nice_size($usage),"</td>\n";
			print "</tr>\n";
			}
		}
	elsif ($in{'mode'} == 3) {
		# By month
		print "<tr> <td><b>$text{'newbw_month'}</b></td>\n";
		print "<td><b>$text{'newbw_dusage'}</b></td>\n";
		print "<td><b>$text{'newbw_gusage'}</b></td>\n";
		print "</tr>\n";

		# Get bandwidth for relevant domains and sub-domains, and
		# work out the earliest time
		$start_day = undef;
		foreach $d (@doms) {
			foreach $dd ($d, &get_domain_by("parent", $d->{'id'})) {
				local $bwinfo = &get_bandwidth($dd);
				push(@bands, $bwinfo);
				local $min = &minimum_day($bwinfo);
				if ($min && (!defined($start_day) ||
					     $min < $start_day)) {
					$start_day = $min;
					}
				}
			}
		$start_day ||= time()/(24*60*60);	# If none

		# Work out the start and end months
		@start_tm = localtime($start_day * (24*60*60));
		@end_tm = localtime(time());
		$start_month = ($start_tm[5]+1900)*12 + $start_tm[4];
		$end_month = ($end_tm[5]+1900)*12 + $end_tm[4];

		# Work out the max usage for a month
		$max = 0;
		for($i=$end_month; $i>=$start_month; $i--) {
			@tm = ( 0, 0, 0, 1, $i%12, int($i/12)-1900 );
			$istart[$i] = int(timelocal(@tm)/(24*60*60));
			@endtm = ( 0, 0, 0, 1, $tm[4]+1, $tm[5] );
			if ($endtm[4] == 12) { $endtm[4] = 0; $endtm[5]++ };
			$iend[$i] = int(timelocal(@endtm)/(24*60*60) - 1);
			$usage = 0;
			foreach $f (@bandwidth_features) {
				$usage += &usage_for_days(
					$istart[$i], $iend[$i], $f, @bands);
				}
			$max = $usage if ($usage > $max);
			}

		# Show the month table
		$max ||= 1;
		for($i=$end_month; $i>=$start_month; $i--) {
			@tm = ( 0, 0, 0, 1, $i%12, int($i/12)-1900 );
			print "<tr>\n";
			print "<td>",strftime("%m/%Y", @tm),"</td>\n";
			print "<td>";
			local $usage = 0;
			foreach $f (@bandwidth_features) {
				local $fusage = &usage_for_days(
					$istart[$i], $iend[$i], $f, @bands);
				$usage += $fusage;
				if ($fusage) {
					printf "<img src=images/usage-$f.gif width=%s height=10>",
						int($width*$fusage/$max)+($f eq "web" ? 1 : 0);
					$donecolour{$f} += $fusage;
					}
				}
			print "</td>";
			print "<td>",&nice_size($usage),"</td>\n";
			print "</tr>\n";
			}
		}

	print "</table>\n";

	# Show colour keys
	print "<br>\n";
	foreach $f (@bandwidth_features) {
		if ($donecolour{$f}) {
			print "<img src=images/usage-$f.gif ",
			      "width=10 height=10>\n";
			local $label = $text{'bandwidth_'.$f} ||
				       $text{'feature_'.$f};
			print $label," (",
			      &nice_size($donecolour{$f}),")\n";
			}
		}
	print "<br>\n";

	# Show month selector
	if ($in{'mode'} != 3) {
		print &ui_form_start("bwgraph.cgi");
		print &ui_hidden("mode", $in{'mode'});
		print &ui_hidden("dom", $in{'dom'});
		print "<b>",$text{'bwgraph_mago_'.$config{'bw_past'}},"</b>\n";
		@mago = ( );
		@tm = localtime(time());
		for($i=0; $i<24; $i++) {
			local $sday = &bandwidth_period_start($i);
			local $eday = &bandwidth_period_end($i);
			push(@mago, [ $i, &make_date($sday*24*60*60, 1)." - ".
					  &make_date($eday*24*60*60, 1) ]);
			}
		print &ui_select("mago", $in{'mago'}, \@mago,
				 1, 0, 0, 0, "onChange='form.submit()'" );
		print &ui_submit($text{'bwgraph_mok'});
		print &ui_form_end();
		}
	}
else {
	print "<b>$text{'bwgraph_none'}</b><p>\n";
	}

if ($parent) {
	push(@rets, "bwgraph.cgi?dom=$parent->{'id'}",
		    $text{'bwgraph_returnparent'});
	}
if ($in{'dom'}) {
	push(@rets, &domain_footer_link($d));
	}
if (&can_edit_templates() && $in{'dom'}) {
	push(@rets, "bwgraph.cgi", $text{'bwgraph_return'});
	}
push(@rets, "", $text{'index_return'});
&ui_print_footer(@rets);

# usage_colours(&domain, &usage)
sub usage_colours
{
local ($d, $usage) = @_;
local ($f, $total);
foreach $f (@bandwidth_features) {
	local $fusage = $usage->{$f}->{$d->{'id'}};
	if ($fusage) {
		printf "<img src=images/usage-$f.gif width=%s height=10>",
			int($width*$fusage/$max)+($f eq "web" ? 1 : 0);
		$donecolour{$f} += $fusage;
		$total += $fusage;
		}
	}
if (!$total) {
	print "<img src=images/usage-web.gif width=1 height=10>";
	}
}

# minimum_day(&bandwidth)
sub minimum_day
{
local $min = undef;
foreach $k (keys %{$_[0]}) {
	if ($k =~ /^(\S+)_(\d+)$/ && (!defined($min) || $2 < $min)) {
		$min = $2;
		}
	}
return $min;
}

# usage_for_days(start, end, feature, &bandwidth, ...)
sub usage_for_days
{
local ($start, $end, $f, @bands) = @_;
local $usage = 0;
local ($i, $band);
for($i=int($start); $i<=int($end); $i++) {
	foreach $band (@bands) {
		$usage += $band->{$f.'_'.$i};
		}
	}
return $usage;
}

