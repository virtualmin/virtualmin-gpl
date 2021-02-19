#!/usr/local/bin/perl
# Show a list of Cloud DNS providers

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'dnsclouds_ecannot'});

&ui_print_header(undef, $text{'dnsclouds_title'}, "", "dnsclouds");

@clouds = &list_dns_clouds();
@doms = &list_domains();
print &ui_columns_start([ $text{'dnsclouds_name'},
                          $text{'dnsclouds_url'},
                          $text{'dnsclouds_state'},
                          $text{'dnsclouds_users'} ]);
foreach my $c (@clouds) {
	@users = grep { &dns_uses_cloud($_, $c) } @doms;
	$users = @users ? &text('dnsclouds_nusers', scalar(@users))
                        : $text{'dnsclouds_nousers'};
	$sfunc = "dnscloud_".$c->{'name'}."_get_state";
        $state = &$sfunc($c);
	print &ui_columns_row([
                &ui_link("edit_dnscloud.cgi?name=$c->{'name'}", $c->{'desc'}),
		&ui_link($c->{'url'}, $c->{'url'}, undef, "target=_blank"),
                $state->{'ok'} ? $state->{'desc'} :
                  "<font color=red>$text{'clouds_unconf'}</font>",
                $users ]);
	}
print &ui_columns_end();

&ui_print_footer("", $text{'index_return'});


