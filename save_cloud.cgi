#!/usr/local/bin/perl
# Save settings for one provider

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'clouds_ecannot'});

@provs = &list_cloud_providers();
($prov) = grep { $_->{'name'} eq $in{'name'} } @provs;
$prov || &error($text{'cloud_egone'});

if ($in{'clear'}) {
	# Clear all cloud settings for this provider, to force re-enrollment
	$cfunc = "cloud_".$prov->{'name'}."_clear";
	&$cfunc();
	&redirect("list_clouds.cgi");
	}
else {
	# Save provider settings
	$config{'cloud_'.$in{'name'}.'_reseller'} = $in{'useby_reseller'};
	$config{'cloud_'.$in{'name'}.'_owner'} = $in{'useby_owner'};
	$pfunc = "cloud_".$prov->{'name'}."_parse_inputs";
	$html = &$pfunc(\%in);
	&webmin_log("save", "cloud", $in{'name'});

	if ($html) {
		&ui_print_header(undef, $text{'cloud_title'}, "");
		print $html;
		&ui_print_footer("list_clouds.cgi", $text{'clouds_return'});
		}
	else {
		&redirect("list_clouds.cgi");
		}
	}
