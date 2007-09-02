#!/usr/local/bin/perl
# Show a historic graph of one or more collected stats
# XXX multiple stats on same graph
# XXX put empty values to left where we don't have them (not quite working)
# XXX labels on graph
# XXX link from left menu

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
		 "<script src=timeplot/timeplot-api.js></script>",
		 "onload='onLoad();' onresize='onResize();'");

# Work out the stat and time range we want
$stat = $in{'stat'} || "load";
$start = $in{'start'} || time()-60*60;
$period = $in{'period'} || 60*60;
$end = $start + $period;
if ($end > time()) {
	# Too far in future .. shift back
	$start = time()-$period;
	$end = $start+$period;
	}

# Generate DIV for the graph and navigation buttons
if ($period > 24*60*60) {
	# Show dates only
	$startmsg = &make_date($start, 1);
	$endmsg = &make_date($end, 1);
	}
else {
	$startmsg = &make_date($start, 0);
	$endmsg = &make_date($end, 0);
	}
print "<b>",&text('history_range', $text{'history_stat_'.$stat},
				   $startmsg, $endmsg),"</b><p>\n";
print "<table cellpadding=0 cellspacing=0 width=100%><tr>\n";

# Move back links. The steps are 1, 2 and 4 times the period
# XXX what if off the end?
print "<td align=left>";
@llinks = ( );
for($i=1; $i<=4; $i*=2) {
	$msg = "&lt;&lt;".&text('history_'.&period_to_name($period).'s', $i);
	push(@llinks, "<a href='history.cgi?stat=$stat&period=$period&".
		      "start=".($start-$period*$i)."'>$msg</a>");
	}
print &ui_links_row(\@llinks);
print "</td>\n";

# Time period links
@plinks = ( );
print "<td align=middle>";
foreach $p (map { [ $text{'history_'.$_->[0]}, $_->[1] ] } @history_periods) {
	if ($period == $p->[1]) {
		push(@plinks, "<b>$p->[0]</b>");
		}
	else {
		push(@plinks, "<a href='history.cgi?stat=$stat&start=$start&".
			      "period=$p->[1]'>$p->[0]</a>");
		}
	}
print &ui_links_row(\@plinks);
print "</td>\n";

# Move forward links
# XXX what if off the end?
print "<td align=right>";
@rlinks = ( );
for($i=1; $i<=4; $i*=2) {
	$msg = &text('history_'.&period_to_name($period).'s', $i)."&gt;&gt;";
	push(@rlinks, "<a href='history.cgi?stat=$stat&period=$period&".
		      "start=".($start+$period*$i)."'>$msg</a>");
	}
print &ui_links_row(\@rlinks);
print "</td>\n";

# The graph itself
print "</tr></table>\n";
print "<div id='history' style='height: 300px;'></div>\n";

# Generate 
$maxes = &get_historic_maxes();
if ($maxes->{$stat}) {
	$maxv = $stat eq "memused" || $stat eq "swapused" ?
		 $maxes->{$stat}/(1024*1024) :
		$stat eq "diskused" ?
		 $maxes->{$stat}/(1024*1024*1024) :
		 $maxes->{$stat};
	$maxopt = "max: $maxv,";
	}
print <<EOF;
<script>
var timeplot;

function onLoad() {
  var eventSource = new Timeplot.DefaultEventSource();
  var plotInfo = [
    Timeplot.createPlotInfo({
      id: "plot1",
      dataSource: new Timeplot.ColumnSource(eventSource,1),
      valueGeometry: new Timeplot.DefaultValueGeometry({
        gridColor: "#000000",
        axisLabelsPlacement: "left",
	min: 0,
	$maxopt
      }),
      timeGeometry: new Timeplot.DefaultTimeGeometry({
        gridColor: "#000000",
        axisLabelsPlacement: "top"
      }),
      showValues: true,
      fillColor: "#dadaf8",
    })
  ];
            
  timeplot = Timeplot.create(document.getElementById("history"), plotInfo);
  timeplot.loadText("history_data.cgi?stat=$stat&start=$start&end=$end&nice=1", ",", eventSource);
}

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
