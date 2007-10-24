#!/usr/local/bin/perl
# Output the CSV for some stat over some time

require './virtual-server-lib.pl';
&can_show_history() || &error($text{'history_ecannot'});
&ReadParse();
use POSIX;
@stats = split(/\0/, $in{'stat'});

# Get the stats, and fill in missing section to the left. All stats need
# to have the same time range.
foreach $stat (@stats) {
	my @info = &list_historic_collected_info($stat,
			$in{'start'} || undef, $in{'end'} || undef);
	if ($in{'start'} && @info > 1) {
		$gap = $info[1]->[0] - $info[0]->[0];
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
	my @newinfo;
	foreach $stat (@stats) {
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
			if ($stat eq 'memused' || $stat eq 'swapused') {
				$v /= 1024*1024;
				}
			elsif ($stat eq 'quotalimit' || $stat eq 'quotaused') {
				if ($maxes->{$stat} < 10*1024*1024*1024) {
					$v /= 1024*1024;
					}
				else {
					$v /= 1024*1024*1024;
					}
				}
			elsif ($stat eq 'diskused') {
				$v /= 1024*1024*1024;
				}
			elsif ($stat =~ /^load(|5|15)$/) {
				$v *= 100;
				}
			}
		$v = int($v);
		push(@values, $v);
		}
	print strftime("%Y-%m-%d %H:%M:%S", localtime($first->[$i]->[0])),",",
	      join(",", @values),"\n";
	}

