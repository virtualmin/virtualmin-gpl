#!/usr/local/bin/perl
# Update all custom links for domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newlinks_ecannot'});
&ReadParse();
&error_setup($text{'newlinks_err'});

for($i=0; defined($in{"desc_$i"}); $i++) {
	next if (!$in{"desc_$i"});
	$in{"url_$i"} || &error(&text('newlinks_eurl', $i+1));
	local %who = map { $_, 1 } split(/\0/, $in{"who_$i"});
	%who || &error(&text('newlinks_ewho', $i+1));
	push(@rv, { 'desc' => $in{"desc_$i"},
		    'url' => $in{"url_$i"},
		    'open' => $in{"open_$i"},
		    'who' => \%who,
		    'cat' => $in{"cat_$i"},
		   });
	}
&save_custom_links(\@rv);
&webmin_log("save", "links");
&redirect("edit_newlinks.cgi");


