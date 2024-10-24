#!/usr/local/bin/perl
# Show a form for 2fa setup

require './virtual-server-lib.pl';
&ReadParse();
&can_user_2fa() || &can_master_reseller_2fa() || &error($text{'2fa_ecannot'});

&ui_print_header(undef, $text{'2fa_title'}, "");

# Get current status
&foreign_require("acl");
&foreign_require("webmin");
my @users = &acl::list_users();
my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
$user || &error($text{'2fa_euser'});
my @provs = &webmin::list_twofactor_providers();

print &ui_form_start("save_2fa.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";

if ($user->{'twofactor_provider'}) {
	# Already setup
	$msg = $text{'2fa_cancel'};
	my ($prov) = grep { $_->[0] eq $user->{'twofactor_provider'} } @provs;
	print &text('2fa_already',
		    $prov->[1],
		    "<tt>$user->{'twofactor_id'}</tt>"),"<p>\n";
	}
else {
	# Need to enable
	$msg = $text{'2fa_ok'};
	my %miniserv;
	&get_miniserv_config(\%miniserv);
	my ($prov) = grep { $_->[0] eq $miniserv{'twofactor_provider'} } @provs;
	print &text('2fa_desc', $prov->[1], $prov->[2]),"<p>\n";
        my $ffunc = "webmin::show_twofactor_form_".
                    $miniserv{'twofactor_provider'};
        if (defined(&$ffunc)) {
                print &ui_table_start($text{'2fa_header'}, undef, 2);
                print &{\&{$ffunc}}($user);
                print &ui_table_end();
                }
	}

print &ui_form_end([ [ undef, $msg ] ]);

&ui_print_footer("", $text{'index_return'});
