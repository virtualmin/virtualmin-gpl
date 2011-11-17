#!/usr/local/bin/perl
# Update all custom fields for domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newfields_ecannot'});
&ReadParse();
&error_setup($text{'newfields_err'});

for($i=0; defined($in{"name_$i"}); $i++) {
	next if (!$in{"name_$i"});
	$in{"desc_$i"} || &error(&text('newfields_edesc', $i+1));
	push(@rv, { 'name' => $in{"name_$i"},
		    'desc' => $in{"desc_$i"},
		    'type' => $in{"type_$i"},
		    'opts' => $in{"opts_$i"},
		    'show' => $in{"show_$i"},
		    'visible' => $in{"visible_$i"},
		  });
	}
&save_custom_fields(\@rv);
&run_post_actions_silently();
&webmin_log("save", "fields");
&redirect("");


