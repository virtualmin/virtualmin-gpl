#!/usr/local/bin/perl
# Show a historic graph of one or more collected stats

require './virtual-server-lib.pl';
&can_show_history() || &error($text{'history_ecannot'});
&ReadParse();

@history_periods = (
	[ 'year', 365*24*60*60 ],
	[ 'month', 31*24*60*60 ],
	[ 'week', 7*24*60*60 ],
	[ 'day', 24*60*60 ],
	[ 'hour', 60*60 ],
	);

&ui_print_header(undef, $text{'history_title'}, "", undef, 0, 0, 0, undef,
		 "<script src='timeplot/timeplot-api.js?local'></script>",
		 "onload='onLoad();' onresize='onResize();'");

# Work out the stat and time range we want
@stats = split(/\0/, $in{'stat'});
@stats = ( "load" ) if (!@stats);
$statsparams = join("&", map { "stat=$_" } @stats);
$period = $in{'period'} || 24*60*60;
$start = $in{'start'} || time()-$period;
$end = $start + $period;
($first, $last) = &get_historic_first_last($stats[0]);
if (!$first) {
	&ui_print_endpage($text{'history_none'});
	}
if ($end > $last) {
	# Too far in future .. shift back
	$start = $last-$period;
	$end = $start+$period;
	}

# Heading for stats being shown
$maxes = &get_historic_maxes();
for($i=0; $i<@stats; $i++) {
	$color = $historic_graph_colors[$i % scalar(@historic_graph_colors)];
	$stat = $stats[$i];
	$fmt = &historic_stat_info($stat, $maxes);
	$units = $fmt ? $fmt->{'units'} : undef;
	$sttxt = $text{'history_stat_'.$stat};
	push(@statnames, "<font color=$color>".
			 ($units ? &text('history_units', $sttxt, $units)
				 : $sttxt).
			 "</font>");
	}
print "<b>",&text('history_showing', join(", ", @statnames)),"</b><p>\n";
print "<table cellpadding=0 cellspacing=0 width=100%><tr>\n";

# Move back links. The steps are 1, 2 and 4 times the period
print "<td align=left width=33%>";
@llinks = ( );
for($i=1; $i<=4; $i*=2) {
	$s = $i == 1 ? "" : "s";
	$msg = "&lt;&lt;".&text('history_'.&period_to_name($period).$s, $i);
	push(@llinks, "<a href='history.cgi?$statsparams&period=$period&".
		      "start=".($start-$period*$i).
		      "&logscale=$in{'logscale'}'>$msg</a>");
	}
print &ui_links_row(\@llinks);
print "</td>\n";

# Time period links
@plinks = ( );
print "<td align=middle width=33%>";
foreach $p (map { [ $text{'history_'.$_->[0]}, $_->[1] ] } @history_periods) {
	if ($period == $p->[1]) {
		push(@plinks, "<b>$p->[0]</b>");
		}
	else {
		$nstart = $end - $p->[1];
		push(@plinks,"<a href='history.cgi?$statsparams&start=$nstart&".
			     "period=$p->[1]&logscale=$in{'logscale'}'>".
			     $p->[0]."</a>");
		}
	}
print &ui_links_row(\@plinks);
print "</td>\n";

# Move forward links
print "<td align=right width=33%>";
@rlinks = ( );
for($i=1; $i<=4; $i*=2) {
	$s = $i == 1 ? "" : "s";
	next if ($start+$period*$i >= $last);	# Off the end
	$msg = &text('history_'.&period_to_name($period).$s, $i)."&gt;&gt;";
	push(@rlinks, "<a href='history.cgi?$statsparams&period=$period&".
		      "start=".($start+$period*$i)."'>$msg</a>");
	}
print &ui_links_row(\@rlinks);
print "</td>\n";

# The graph itself
print "</tr></table>\n";
print "<div id='history' style='height: 300px;'></div>\n";
print "<a href='history_data.cgi?$statsparams&start=$start&end=$end&nice=1'>$text{'history_rawdata'}</a><br>\n";

# For email, show total over time period
my @tstats;
foreach $stat (@stats) {
	$fmt = &historic_stat_info($stat, $maxes);
	if ($fmt && $fmt->{'type'} eq 'email') {
		my @info = &list_historic_collected_info($stat, $start, $end);
		my $lasttime;
		my $count = 0;
		foreach $i (@info) {
			if ($lasttime) {
				$count += $i->[1] * (($i->[0] - $lasttime) / 60);
				}
			$lasttime = $i->[0];
			}
		push(@tstats, &text('history_total_'.$stat, int($count)));
		}
	}
if (@tstats) {
	print &ui_links_row(\@tstats);
	}

# Checkboxes for statistics to show
print &ui_hr();
print "<b>$text{'history_showsel'}</b><br>\n";
print &ui_form_start("history.cgi");
print &ui_hidden("start", $start);
print &ui_hidden("period", $period);
foreach $s (&list_historic_stats()) {
	$fmt = &historic_stat_info($s, $maxes);
	if ($fmt) {
		push(@{$type_to_stat{$fmt->{'type'}}}, $s);
		}
	}
foreach $t (sort { $text{'history_type_'.$a} cmp
		   $text{'history_type_'.$b} } keys %type_to_stat) {
	@grid = ( );
	foreach $s (sort { $text{'history_stat_'.$a} cmp
			   $text{'history_stat_'.$b} } @{$type_to_stat{$t}}) {
		$link = "history.cgi?start=".&urlize($start).
			"&period=".&urlize($period).
			"&logscale=".$in{'logscale'}."&stat=$s";
		push(@grid, &ui_checkbox("stat", $s,
			"<a href='$link'>".
			  ($text{'history_stat_'.$s} || $s)."</a>",
			&indexof($s, @stats) >= 0));
		}
	print &ui_grid_table(\@grid, 4, 100,
		[ "width=25%", "width=25%", "width=25%", "width=25%" ], undef,
		$text{'history_type_'.$t});
	}
print "<b>$text{'history_logscale'}</b>\n";
print &ui_radio("logscale", int($in{'logscale'}),
		[ [ 0, $text{'history_logscale0'} ],
		  [ 1, $text{'history_logscale1'} ] ]),"<br>\n";
print &ui_form_end([ [ undef, $text{'history_ok'} ] ]);

# Javascript to generate it
print "<script>\n";
print "var timeplot;\n";
print "function onLoad() {\n";
print "  var eventSource = new Timeplot.DefaultEventSource();\n";

# Work out how many different axes we have
@axes = ( );
$geom = $in{'logscale'} ? 'LogarithmicValueGeometry'
		        : 'DefaultValueGeometry';
foreach $stat (@stats) {
	$maxopt = "";
	$fmt = &historic_stat_info($stat, $maxes);
	if ($maxes->{$stat}) {
		$maxv = $maxes->{$stat};
		$maxv /= $fmt->{'scale'} if ($fmt && $fmt->{'scale'});
		$maxopt = "max: $maxv,";
		}
	$units = $fmt ? $fmt->{'units'} : "count";
	$axis = &indexof($units, @axes);
	if ($axis < 0) {
		# New axis
		$axis = scalar(@axes);
		push(@axes, $units);
		if ($axis == 0) {
			$place = "left";
			}
		elsif ($axis == 1) {
			$place = "right";
			}
		else {
			next;
			}
		print "var value$axis = new Timeplot.$geom({\n";
		print "        gridColor: '#B3B6B0',\n";
		print "        axisLabelsPlacement: '$place',\n";
		print "        $maxopt\n";
		print "        min: 0\n";
		print "      });\n";
		}
	$stat_to_axis{$stat} = "value".$axis;
	}

# Generate JS for each stat
print "  var plotInfo = [\n";
$plotno = 1;
foreach $stat (@stats) {
	next if (!$stat_to_axis{$stat});	# Not enough axes!
	$color = $historic_graph_colors[
			($plotno-1) % scalar(@historic_graph_colors)];
	print "    Timeplot.createPlotInfo({\n";
	print "      id: 'plot$plotno',\n";
	print "      dataSource: new Timeplot.ColumnSource(eventSource, $plotno),\n";
	print "      valueGeometry: $stat_to_axis{$stat},\n";
	print "      timeGeometry: new Timeplot.DefaultTimeGeometry({\n";
	print "        gridColor: '#B3B6B0',\n";
	print "        axisLabelsPlacement: 'top'\n";
	print "      }),\n";
	print "      showValues: true,\n";
	print "      roundValues: false,\n";
	if (@stats == 1) {
		print "      fillColor: '#dadaf8',\n";
		}
	print "      lineColor: '$color'\n";
	if ($stat eq $stats[$#stats]) {
		print "    })\n";
		}
	else {
		print "    }),\n";
		}
	$plotno++;
	}
print "  ];\n";
print "  timeplot = Timeplot.create(document.getElementById('history'), plotInfo);\n";
print "  timeplot.loadText('history_data.cgi?$statsparams&start=$start&end=$end&nice=1', ',', eventSource);\n";
print "}\n";

# Resize handler Javascript
print <<EOF;
var resizeTimerID = null;
function onResize() {
    if (resizeTimerID == null) {
        resizeTimerID = window.setTimeout(function() {
            resizeTimerID = null;
            timeplot.repaint();
        }, 100);
    }
}
</script>
EOF

&ui_print_footer("", $text{'index_return'});

sub period_to_name
{
local ($p) = @_;
foreach my $hp (@history_periods) {
	return $hp->[0] if ($p == $hp->[1]);
	}
return undef;
}
