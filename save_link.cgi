#!/usr/local/bin/perl
# Create, update or delete a custom link

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'elink_err'});
&can_edit_templates() || &error($text{'newlinks_ecannot'});

# Get the link
@links = &list_custom_links();
if ($in{'new'}) {
	$link = { };
	push(@links, $link);
	}
else {
	$link = $links[$in{'idx'}];
	}

if ($in{'delete'}) {
	# Just remove from the list
	@links = grep { $_ ne $link } @links;
	}
else {
	# Validate inputs and update object
	$in{'desc'} =~ /\S/ || &error($text{'elink_edesc'});
	$link->{'desc'} = $in{'desc'};
	$in{'url'} =~ /^\S+$/ || &error($text{'elink_eurl'});
	$link->{'url'} = $in{'url'};
	$link->{'open'} = $in{'open'};
	$link->{'cat'} = $in{'cat'};
	$link->{'who'} = { };
	foreach $w (split(/\0/, $in{'who'})) {
		$link->{'who'}->{$w} = 1;
		}
	$link->{'tmpl'} = $in{'tmpl'};
	$link->{'feature'} = $in{'feature'};
	}

# Save custom links
&save_custom_links(\@links);
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    'link', undef, $link);
&redirect("edit_newlinks.cgi?refresh=1");

