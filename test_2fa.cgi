#!/usr/local/bin/perl
# Test two-factor for a user who has just set it up

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($text{'2fa_terr'});
&can_user_2fa() || &can_master_reseller_2fa() || &error($text{'2fa_ecannot'});

# Get current status
&foreign_require("acl");
&foreign_require("webmin");
my @users = &acl::list_users();
my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
$user || &error($text{'2fa_euser'});
$user->{'twofactor_provider'} || &error($text{'2fa_etestuser'});
my @provs = &webmin::list_twofactor_providers();
my ($prov) = grep { $_->[0] eq $user->{'twofactor_provider'} } @provs;

# Call the validation function
&ui_print_header(undef, $text{'2fa_title'}, "");

print &text('2fa_testing', $prov->[1]),"<br>\n";
my $func = "webmin::validate_twofactor_".$user->{'twofactor_provider'};
$err = &$func($user->{'twofactor_id'}, $in{'test'}, $user->{'twofactor_apikey'});
if ($err) {
	print &text('2fa_testfailed', $err),"<p>\n";

	print &ui_form_start("save_2fa.cgi");
	print &ui_form_end([ [ undef, $text{'2fa_testdis'} ] ]);
	}
else {
	print $text{'2fa_testok'},"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});
