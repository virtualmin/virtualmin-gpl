#!/usr/local/bin/perl
# Change the user's language

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'lang_err'});
&can_change_language() || &error($text{'lang_ecannot'});
&foreign_require("acl");
my @users = &acl::list_users();
my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
$user || &error($text{'lang_euser'});

# Update the Webmin user
$user->{'lang'} = $in{'lang'};
&acl::modify_user($user->{'name'}, $user);
&webmin_log("lang");

# Refresh the whole UI
&ui_print_header(undef, $text{'lang_title'}, "");
print &js_redirect("/", "top");
&ui_print_footer("", $text{'index_return'});
