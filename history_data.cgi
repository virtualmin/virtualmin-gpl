#!/usr/local/bin/perl
# Output the CSV for some stat over some time

require './virtual-server-lib.pl';
&can_show_history() || &error($text{'history_ecannot'});
&ReadParse();
use POSIX;
@stats = split(/\0/, $in{'stat'});

# Get the stats, and fill in missing section to the left. All stats need
# to have the same time range.
$gap = 0;
foreach $stat (@stats) {
	my @info = &list_historic_collected_info($stat,
			$in{'start'} || undef, $in{'end'} || undef);
	if ($in{'start'} && @info > 1) {
		$gap ||= &compute_average_gap(\@info);
		while($info[0]->[0] > $in{'start'}+$gap) {
			unshift(@info, [ $info[0]->[0]-$gap, undef ]);
			}
		}
	$infomap{$stat} = \@info;
	}

# If there is too much data to reasonably display, reduce the number of points
# to approx 1024
$first = $infomap{$stats[0]};
if (scalar(@$first) > 1024) {
	$step = int(scalar(@$first) / 1024);
	foreach $stat (@stats) {
		my @newinfo;
		for($i=0; $i<scalar(@$first); $i+=$step) {
			push(@newinfo, $infomap{$stat}->[$i]);
			}
		$infomap{$stat} = \@newinfo;
		}
	}
$first = $infomap{$stats[0]};

print "Content-type: text/plain\n\n";
$maxes = &get_historic_maxes();
for($i=0; $i<scalar(@$first); $i++) {
	@values = ( );
	foreach $stat (@stats) {
		$v = $infomap{$stat}->[$i]->[1];
		if ($in{'nice'}) {
			$fmt = &historic_stat_info($stat, $maxes);
			$v /= $fmt->{'scale'} if ($fmt && $fmt->{'scale'});
			}
		if ($v ne int($v)) {
			# Two decimal places only
			$v = sprintf("%.2f", $v);
			}
		push(@values, $v);
		}
	print strftime("%Y-%m-%d %H:%M:%S", localtime($first->[$i]->[0])),",",
	      join(",", @values),"\n";
	}

# compute_average_gap(&info-list)
# Given a list of time,value pairs, compute the average gap between times
sub compute_average_gap
{
local ($info) = @_;
local $totalgap = 0;
local $totalcount = 0;
for(my $i=0; $i<@$info-1; $i++) {
	local $gap = $info[$i+1]->[0] - $info[$i]->[0];
	if ($gap > 0) {
		$totalgap += $gap;
		$totalcount++;
		}
	}
if ($totalcount) {
	return $totalgap / $totalcount;
	}
return 5*60;
}
