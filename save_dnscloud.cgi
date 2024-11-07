#!/usr/local/bin/perl
# Save settings for one DNS cloud provider

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($text{'dnscloud_err'});
&can_cloud_providers() || &error($text{'dnsclouds_ecannot'});

@clouds = &list_dns_clouds();
($cloud) = grep { $_->{'name'} eq $in{'name'} } @clouds;
$cloud || &error($text{'dnscloud_egone'});

if ($in{'clear'}) {
	# Clear all cloud settings for this provider, to force re-enrollment
	$cfunc = "dnscloud_".$cloud->{'name'}."_clear";
	&$cfunc();
	&webmin_log("clear", "dnscloud", $in{'name'});
	&redirect("dnsclouds.cgi");
	}
else {
	# Save provider settings
	$config{'dnscloud_'.$in{'name'}.'_reseller'} = $in{'useby_reseller'};
	$config{'dnscloud_'.$in{'name'}.'_owner'} = $in{'useby_owner'};
	$pfunc = "dnscloud_".$cloud->{'name'}."_parse_inputs";
	$html = &$pfunc(\%in);
	&webmin_log("save", "dnscloud", $in{'name'});

	if ($html) {
		&ui_print_header(undef, $text{'dnscloud_title'}, "");
		print $html;
		&ui_print_footer("dnsclouds.cgi", $text{'dnsclouds_return'});
		}
	else {
		&redirect("dnsclouds.cgi");
		}
	}
