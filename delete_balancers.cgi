#!/usr/local/bin/perl
# Delete several proxy balancers

$0 =~ /^(.*)\/pro\// && chdir($1);
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() ||
	&error($text{'balancers_ecannot'});
&has_proxy_balancer($d) || &error($text{'balancers_esupport'});
&error_setup($text{'balancers_derr'});

# Find them and delete them
@d = split(/\0/, $in{'d'});
@d || &error($text{'balancers_denone'});
&obtain_lock_web($d);
@balancers = &list_proxy_balancers($d);
foreach $path (@d) {
	($b) = grep { $_->{'path'} eq $path } @balancers;
	if ($b) {
		$err = &delete_proxy_balancer($d, $b);
		&error($err) if ($err);
		}
	}

# Log and return
&release_lock_web($d);
&set_all_null_print();
&run_post_actions();
&webmin_log("delete", "balancers", scalar(@d), { 'dom' => $d->{'dom'} });

&redirect("list_balancers.cgi?dom=$in{'dom'}");

