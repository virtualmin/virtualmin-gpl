#!/usr/local/bin/perl
# Output the CSV for some stat over some time

require './virtual-server-lib.pl';
&can_show_history() || &error($text{'history_ecannot'});
&ReadParse();
use POSIX;

# Get the stats, and fill in missing section to the left
@info = &list_historic_collected_info($in{'stat'}, $in{'start'} || undef,
						   $in{'end'} || undef);
if ($in{'start'} && @info > 1) {
	$gap = $info[1]->[0] - $info[0]->[0];
	while($info[0]->[0] > $in{'start'}+$gap) {
		unshift(@info, [ $info[0]->[0]-$gap, undef ]);
		}
	}

# If there is too much data to reasonably display, reduce the number of points
# to approx 1024
if (scalar(@info) > 1024) {
	$step = int(scalar(@info) / 1024);
	for($i=0; $i<scalar(@info); $i+=$step) {
		push(@newinfo, $info[$i]);
		}
	@info = @newinfo;
	}

print "Content-type: text/plain\n\n";
foreach $i (@info) {
	$v = $i->[1];
	if ($in{'nice'}) {
		$v = $in{'stat'} eq 'memused' ||
		     $in{'stat'} eq 'swapused' ? $v/(1024*1024) :
		     $in{'stat'} eq 'diskused' ? $v/(1024*1024*1024) :
		     $in{'stat'} eq 'load' ? $v*100 :
		     $v;
		}
	$v = int($v);
	print strftime("%Y-%m-%d %H:%M:%S", localtime($i->[0])),",",$v,"\n";
	}
