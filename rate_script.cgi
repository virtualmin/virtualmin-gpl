#!/usr/local/bin/perl
# Record a script rating for the current user

require './virtual-server-lib.pl';
&ReadParse();
$ratings = &get_script_ratings();
($type) = grep { $_ ne 'dom' } (keys %in);
$ratings->{$type} = $in{$type};
&save_script_ratings($ratings);
&redirect($ENV{'HTTP_REFERER'});


