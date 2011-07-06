#!/usr/local/bin/perl
# Update custom link categories

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newlinks_ecannot'});
&ReadParse();
&error_setup($text{'newcats_err'});

for($i=0; defined($in{"desc_$i"}); $i++) {
	next if (!$in{"desc_$i"});
	push(@rv, { 'id' => $in{"id_$i"} ||
			    &desc_to_category_id($in{"desc_$i"}),
		    'desc' => $in{"desc_$i"},
		   });
	}
&save_custom_link_categories(\@rv);
&run_post_actions_silently();
&webmin_log("save", "linkcats");
&redirect("edit_newlinks.cgi?refresh=1");

sub desc_to_category_id
{
local ($desc) = @_;
$desc =~ s/\s+/_/g;
$desc = lc($desc);
return $desc;
}
