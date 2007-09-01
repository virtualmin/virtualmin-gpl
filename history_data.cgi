#!/usr/local/bin/perl
# Output the CSV for some stat over some time

require './virtual-server-lib.pl';
&can_show_history() || &error($text{'history_ecannot'});
&ReadParse();
use POSIX;

@info = &list_historic_collected_info($in{'stat'}, $in{'start'} || undef,
						   $in{'end'} || undef);
print "Content-type: text/plain\n\n";
foreach $i (@info) {
	$v = $i->[1];
	if ($in{'nice'}) {
		$v = $in{'stat'} eq 'memused' ||
		     $in{'stat'} eq 'swapused' ? $v/(1024*1024) :
		     $in{'stat'} eq 'diskused' ? $v/(1024*1024*1024) :
		     $v;
		$v = int($v);
		}
	print strftime("%Y-%m-%d %H:%M:%S", localtime($i->[0])),",",$v,"\n";
	}
