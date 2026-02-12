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

# XXX call the validation function

