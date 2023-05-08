#!/usr/local/bin/perl
# Edit settings for cloud DNS provider

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'dnsclouds_ecannot'});

&ui_print_header(undef, $text{'dnscloud_title'}, "");

# Lookup the provider
@clouds = &list_dns_clouds();
($cloud) = grep { $_->{'name'} eq $in{'name'} } @clouds;
$cloud || &error($text{'dnscloud_egone'});
$sfunc = "dnscloud_".$cloud->{'name'}."_get_state";
$state = &$sfunc($p);

my $longdesc = $cloud->{'longdesc'};
if (ref($longdesc) eq 'CODE') {
	$longdesc = &$longdesc();
	}
if ($longdesc) {
	print $longdesc,"<p>\n";
	}

# First check if provider can be used
my $cfunc = "dnscloud_".$cloud->{'name'}."_check";
if (defined(&$cfunc)) {
	my $err = &$cfunc();
	if ($err) {
		print &text('dnscloud_echeck', $cloud->{'desc'}, $err),"<p>\n";
		&ui_print_footer("dnsclouds.cgi", $text{'dnsclouds_return'});
		return;
		}
	}

print &ui_form_start("save_dnscloud.cgi", "post");
print &ui_hidden("name", $in{'name'});
print &ui_table_start($text{'dnscloud_header'}, undef, 2);

# Cloud provider name
print &ui_table_row($text{'dnscloud_provider'},
		    $cloud->{'desc'});
print &ui_table_row($text{'dnscloud_url'},
		    &ui_link($cloud->{'url'}, $cloud->{'url'}, undef,
			     "target=_blank"));

# Provider options
$ifunc = "dnscloud_".$cloud->{'name'}."_show_inputs";
print &$ifunc($cloud);

# Allow use by other users?
print &ui_table_row($text{'cloud_useby'},
	&ui_checkbox("useby_reseller", 1, $text{'cloud_byreseller'},
		     $config{'dnscloud_'.$in{'name'}.'_reseller'})."\n".
	&ui_checkbox("useby_owner", 1, $text{'cloud_byowner'},
		     $config{'dnscloud_'.$in{'name'}.'_owner'}));

# Used by domains
@users = grep { &dns_uses_cloud($_, $cloud) } &list_domains();
if (@users) {
	@grid = map { &ui_link("list_records.cgi?dom=".&urlize($_->{'id'}),
			       &show_domain_name($_)) } @users;
	$utable = &ui_grid_table(\@grid, 4);
	}
else {
	$utable = $text{'dnscloud_nousers'};
	}
print &ui_table_row($text{'dnscloud_users'}, $utable);

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ],
		     $state->{'ok'} ? ( [ 'clear', $text{'dnscloud_clear'} ] )
				    : ( ) ]);

&ui_print_footer("dnsclouds.cgi", $text{'dnsclouds_return'});
