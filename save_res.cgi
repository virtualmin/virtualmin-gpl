#!/usr/local/bin/perl
# Update memory and process limits

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_res($d) || &error($text{'edit_ecannot'});
&obtain_lock_unix();
&obtain_lock_web($d);

# Validate and store inputs
&error_setup($text{'res_err'});
$rv = &get_domain_resource_limits($d);
&parse_resource_limit_inputs($rv, \%in);
&save_domain_resource_limits($d, $rv);

&set_all_null_print();
&run_post_actions();
&release_lock_web($d);
&release_lock_unix();
&webmin_log("res", "domain", $d->{'dom'}, $rv);

&domain_redirect($d);


