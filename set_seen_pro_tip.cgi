#!/usr/local/bin/perl
# Mark given Pro tip as seen by the current user

require './virtual-server-lib.pl';
&ReadParse();
&set_seen_pro_tip($in{'tipid'}) if ($in{'tipid'});
&redirect(&get_referer_relative());

