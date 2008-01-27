#!/usr/local/bin/perl
# Delete several extra admins

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_admins($d) || &error($text{'admins_ecannot'});
&error_setup($text{'dadmins_err'});
@del = split(/\0/, $in{'d'});
@del || &error($text{'dadmins_enone'});

&obtain_lock_webmin();
@admins = &list_extra_admins($d);
foreach $name (@del) {
	($admin) = grep { $_->{'name'} eq $name } @admins;
	$admin || &error($text{'dadmins_egone'});
	&delete_extra_admin($admin, $d);
	}
&release_lock_webmin();
&webmin_log("delete", "admins", scalar(@del));
&redirect("list_admins.cgi?dom=$d->{'id'}");

