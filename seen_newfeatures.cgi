#!/usr/local/bin/perl
# Mark features as seen by the current user

require './virtual-server-lib.pl';

# For each module and plugin, set the current version as seen
foreach $minfo (&list_new_features_modules()) {
	if ($minfo->{'version'}) {
		&set_seen_new_features($minfo->{'dir'}, $minfo->{'version'},
				       !$in{'reshow'});
		}
	}
&redirect("");

